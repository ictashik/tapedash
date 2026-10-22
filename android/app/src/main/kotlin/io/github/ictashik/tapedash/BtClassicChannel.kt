package io.github.ictashik.tapedash

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.app.Activity
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Bluetooth Classic, for the ELM327s that pair in Android's settings and speak
 * SPP over RFCOMM (CLAUDE.md 5): a thin layer over the platform `BluetoothAdapter`
 * and `BluetoothSocket`. No plugin and no Play Services.
 *
 * It is the Android side of lib/platform/adapter_radio.dart. The channel names,
 * the method names, the error codes and the shape of an event have to match it:
 *
 *   methods `tapedash/bt_classic`: status, requestPermission, paired, startScan,
 *     stopScan, pair {address}, unpair {address}, open {address}, close, send {text}
 *   events `tapedash/bt_classic/events`: {type: found, name, address, paired},
 *     {type: data, text} and {type: lost}
 *   error codes: permission_denied, radio_off, unsupported, connect_failed,
 *     not_connected
 *
 * **Unverified on hardware until the handoff (CLAUDE.md 11).** Connecting and
 * writing happen on one worker thread, the reader has a thread of its own, and
 * everything is handed to Flutter on the main thread.
 */
class BtClassicChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val permissions: BluetoothPermissions,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methods = MethodChannel(messenger, "tapedash/bt_classic")
    private val events = EventChannel(messenger, "tapedash/bt_classic/events")
    private val main = Handler(Looper.getMainLooper())
    private val adapter: BluetoothAdapter? =
        (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private var sink: EventChannel.EventSink? = null
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()

    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var output: OutputStream? = null
    @Volatile private var closing = false
    private var scanReceiver: BroadcastReceiver? = null
    private var bondReceiver: BroadcastReceiver? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        stopScan()
        cancelBonding()
        closeSocket()
        worker.shutdownNow()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(
                mapOf(
                    "supported" to (adapter != null),
                    "enabled" to (adapter?.isEnabled == true),
                    "permitted" to permissions.granted(),
                ),
            )
            "requestPermission" -> permissions.request(result)
            "paired" -> paired(result)
            "startScan" -> startScan(result)
            "stopScan" -> {
                stopScan()
                result.success(null)
            }
            "pair" -> pair(call.argument<String>("address"), result)
            "unpair" -> unpair(call.argument<String>("address"), result)
            "open" -> open(call.argument<String>("address"), result)
            "close" -> {
                worker.execute {
                    closeSocket()
                    main.post { result.success(null) }
                }
            }
            "send" -> send(call.argument<String>("text"), result)
            else -> result.notImplemented()
        }
    }

    // ---- what the phone already knows ------------------------------------

    /** Null if the radio can be used; otherwise the reason, as an error to return. */
    private fun unusable(result: MethodChannel.Result): Boolean {
        if (adapter == null) {
            result.error("unsupported", "This phone has no Bluetooth", null)
            return true
        }
        if (!permissions.granted()) {
            result.error("permission_denied", "Bluetooth permission is not granted", null)
            return true
        }
        if (!adapter.isEnabled) {
            result.error("radio_off", "Bluetooth is switched off", null)
            return true
        }
        return false
    }

    @SuppressLint("MissingPermission") // checked by unusable()
    private fun paired(result: MethodChannel.Result) {
        if (unusable(result)) return
        try {
            result.success(adapter!!.bondedDevices.map { describe(it) })
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun describe(device: BluetoothDevice, paired: Boolean? = null) = mapOf(
        "name" to (device.name ?: ""),
        "address" to device.address,
        "paired" to (paired ?: (device.bondState == BluetoothDevice.BOND_BONDED)),
    )

    // ---- looking for adapters --------------------------------------------

    @SuppressLint("MissingPermission")
    private fun startScan(result: MethodChannel.Result) {
        if (unusable(result)) return
        stopScan()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != BluetoothDevice.ACTION_FOUND) return
                val device = deviceOf(intent) ?: return
                val found = describe(device) + ("type" to "found")
                sink?.success(found)
            }
        }
        scanReceiver = receiver
        registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_FOUND))
        try {
            adapter!!.startDiscovery()
            result.success(null)
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopScan() {
        scanReceiver?.let {
            try {
                activity.unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Not registered any more.
            }
        }
        scanReceiver = null
        try {
            if (adapter?.isDiscovering == true) adapter.cancelDiscovery()
        } catch (e: SecurityException) {
            // Permission taken away while scanning: nothing left to stop.
        }
    }

    // ---- pairing ---------------------------------------------------------

    @SuppressLint("MissingPermission")
    private fun pair(address: String?, result: MethodChannel.Result) {
        if (unusable(result)) return
        val device = deviceAt(address)
        if (device == null) {
            result.error("connect_failed", "No such device: $address", null)
            return
        }
        if (device.bondState == BluetoothDevice.BOND_BONDED) {
            result.success(null)
            return
        }
        cancelBonding()
        // A pairing left half-done (a wrong PIN, a dialog dismissed) blocks the
        // next one: drop it first.
        if (device.bondState == BluetoothDevice.BOND_BONDING) removeBond(device)
        var answered = false
        fun answer(ok: Boolean) {
            if (answered) return
            answered = true
            cancelBonding()
            if (ok) result.success(null) else result.error("connect_failed", "Pairing did not complete", null)
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
                val changed = deviceOf(intent) ?: return
                if (changed.address != device.address) return
                when (intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)) {
                    BluetoothDevice.BOND_BONDED -> answer(true)
                    // Bonding then none: the user said no, or the PIN was wrong.
                    BluetoothDevice.BOND_NONE -> answer(false)
                }
            }
        }
        bondReceiver = receiver
        registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED))
        main.postDelayed({ answer(false) }, PAIRING_TIMEOUT_MS)
        try {
            if (!device.createBond()) answer(false)
        } catch (e: SecurityException) {
            answered = true
            cancelBonding()
            result.error("permission_denied", e.message, null)
        }
    }

    /**
     * Forgets the pairing with [address], as Android's settings do. A pairing made
     * with a wrong PIN, or an old one the adapter no longer knows, makes every
     * connection fail until it is dropped and made again.
     */
    @SuppressLint("MissingPermission")
    private fun unpair(address: String?, result: MethodChannel.Result) {
        if (unusable(result)) return
        val device = deviceAt(address)
        if (device == null) {
            result.error("connect_failed", "No such device: $address", null)
            return
        }
        worker.execute {
            // A pairing cannot be dropped under an open link.
            closeSocket()
            main.post { forget(device, result) }
        }
    }

    @SuppressLint("MissingPermission")
    private fun forget(device: BluetoothDevice, result: MethodChannel.Result) {
        if (device.bondState == BluetoothDevice.BOND_NONE) {
            result.success(null)
            return
        }
        cancelBonding()
        var answered = false
        fun answer(ok: Boolean) {
            if (answered) return
            answered = true
            cancelBonding()
            if (ok) result.success(null) else result.error("connect_failed", "Could not forget the pairing", null)
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
                val changed = deviceOf(intent) ?: return
                if (changed.address != device.address) return
                if (intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR) ==
                    BluetoothDevice.BOND_NONE
                ) {
                    answer(true)
                }
            }
        }
        bondReceiver = receiver
        registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED))
        main.postDelayed({ answer(device.bondState == BluetoothDevice.BOND_NONE) }, UNPAIR_TIMEOUT_MS)
        try {
            if (!removeBond(device)) answer(device.bondState == BluetoothDevice.BOND_NONE)
        } catch (e: SecurityException) {
            answered = true
            cancelBonding()
            result.error("permission_denied", e.message, null)
        }
    }

    /** `BluetoothDevice.removeBond()` is hidden from the SDK, so it is called by name. */
    private fun removeBond(device: BluetoothDevice): Boolean = try {
        device.javaClass.getMethod("removeBond").invoke(device) as? Boolean ?: false
    } catch (e: ReflectiveOperationException) {
        false
    }

    private fun cancelBonding() {
        bondReceiver?.let {
            try {
                activity.unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Not registered any more.
            }
        }
        bondReceiver = null
    }

    // ---- the link --------------------------------------------------------

    @SuppressLint("MissingPermission")
    private fun open(address: String?, result: MethodChannel.Result) {
        if (unusable(result)) return
        val device = deviceAt(address)
        if (device == null) {
            result.error("connect_failed", "No such device: $address", null)
            return
        }
        worker.execute {
            closeSocket()
            closing = false
            try {
                // A discovery running slows a connection down and makes it fail.
                adapter!!.cancelDiscovery()
                val connected = connect(device)
                socket = connected
                output = connected.outputStream
                startReader(connected.inputStream, connected)
                main.post { result.success(null) }
            } catch (e: SecurityException) {
                main.post { result.error("permission_denied", e.message, null) }
            } catch (e: IOException) {
                closeSocket()
                main.post { result.error("connect_failed", e.message ?: "Could not connect", null) }
            }
        }
    }

    /**
     * Cheap ELM327 clones are fussy about how they are connected to, so three ways
     * are tried in turn: the secure SPP socket, the insecure one, and RFCOMM channel
     * 1 by reflection (which many clones answer when the service lookup fails).
     */
    @SuppressLint("MissingPermission")
    private fun connect(device: BluetoothDevice): BluetoothSocket {
        var last: IOException? = null
        val makers: List<() -> BluetoothSocket> = listOf(
            { device.createRfcommSocketToServiceRecord(SPP_UUID) },
            { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) },
            {
                @Suppress("UNCHECKED_CAST")
                device.javaClass
                    .getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                    .invoke(device, 1) as BluetoothSocket
            },
        )
        for (make in makers) {
            try {
                val s = make()
                try {
                    s.connect()
                    return s
                } catch (e: IOException) {
                    last = e
                    try { s.close() } catch (_: IOException) {}
                }
            } catch (e: ReflectiveOperationException) {
                last = IOException("This phone cannot make that kind of socket", e)
            }
        }
        throw last ?: IOException("Could not connect")
    }

    private fun startReader(input: InputStream, owner: BluetoothSocket) {
        Thread {
            val buffer = ByteArray(512)
            try {
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    val text = String(buffer, 0, n, Charsets.ISO_8859_1)
                    main.post { sink?.success(mapOf("type" to "data", "text" to text)) }
                }
            } catch (e: IOException) {
                // The pipe ended: told below, unless the app closed it.
            }
            if (socket === owner && !closing) {
                closeSocket()
                main.post { sink?.success(mapOf("type" to "lost")) }
            }
        }.apply { isDaemon = true; name = "tapedash-bt-reader" }.start()
    }

    private fun send(text: String?, result: MethodChannel.Result) {
        val out = output
        if (text == null || out == null) {
            result.error("not_connected", "No adapter is connected", null)
            return
        }
        worker.execute {
            try {
                out.write(text.toByteArray(Charsets.ISO_8859_1))
                out.flush()
                main.post { result.success(null) }
            } catch (e: IOException) {
                closeSocket()
                main.post {
                    result.error("not_connected", e.message, null)
                    sink?.success(mapOf("type" to "lost"))
                }
            }
        }
    }

    private fun closeSocket() {
        closing = true
        output = null
        val s = socket
        socket = null
        try { s?.close() } catch (_: IOException) {}
    }

    // ---- small helpers ---------------------------------------------------

    private fun deviceAt(address: String?): BluetoothDevice? = try {
        if (address == null) null else adapter?.getRemoteDevice(address)
    } catch (e: IllegalArgumentException) {
        null
    }

    private fun deviceOf(intent: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }

    private fun registerReceiver(receiver: BroadcastReceiver, filter: IntentFilter) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Only the system sends these.
            activity.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            activity.registerReceiver(receiver, filter)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    companion object {
        /** The Serial Port Profile's well-known UUID, which every ELM327 answers. */
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val PAIRING_TIMEOUT_MS = 60_000L
        private const val UNPAIR_TIMEOUT_MS = 8_000L
    }
}
