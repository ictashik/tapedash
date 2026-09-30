package io.github.ictashik.tapedash

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit

/**
 * Bluetooth Low Energy, for the newer "BLE" ELM327 adapters (CLAUDE.md 5): a thin
 * layer over the platform `BluetoothLeScanner` and `BluetoothGatt`. No plugin, no
 * Play Services, and no third-party licence to check.
 *
 * It is the Android side of lib/platform/adapter_radio.dart, and speaks the same
 * vocabulary as BtClassicChannel (see there), on the channels `tapedash/ble` and
 * `tapedash/ble/events`. There is no pairing step for BLE, so `pair` succeeds at
 * once and `paired` lists nothing.
 *
 * **Which characteristics carry the serial data.** BLE ELM327s put a UART on GATT
 * in a few well-known ways, tried in this order: a service `FFE0` with one
 * characteristic `FFE1` that both notifies and is written; `FFF0` with `FFF1`
 * (notify) and `FFF2` (write); `18F0` with `2AF0` and `2AF1`; and the OBDLink CX's
 * own service. Failing those, any service that is not one of the standard GATT
 * ones (1800, 1801, 180A) with a characteristic that notifies and one that is
 * written (the same one, or two). What an adapter actually offers is what the
 * hardware handoff checks first.
 *
 * **Unverified on hardware until the handoff (CLAUDE.md 11).** The GATT callbacks
 * arrive on Binder threads; results and events are handed to Flutter on the main
 * thread, and writes go one at a time from a worker thread, each waiting for its
 * callback.
 */
@SuppressLint("MissingPermission") // every entry point checks BluetoothPermissions
class BleChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val permissions: BluetoothPermissions,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methods = MethodChannel(messenger, "tapedash/ble")
    private val events = EventChannel(messenger, "tapedash/ble/events")
    private val main = Handler(Looper.getMainLooper())
    private val adapter: BluetoothAdapter? =
        (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private var sink: EventChannel.EventSink? = null
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()

    private var scanning = false

    // The link. `ready` is set once the notifications are on; until then a drop is a
    // failed connection, and after it a lost link.
    @Volatile private var gatt: BluetoothGatt? = null
    @Volatile private var writer: BluetoothGattCharacteristic? = null
    @Volatile private var ready = false
    @Volatile private var closing = false
    @Volatile private var mtu = DEFAULT_MTU
    private var openResult: MethodChannel.Result? = null
    private var openTimeout: Runnable? = null
    private val writeDone = Semaphore(0)

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        stopScan()
        closeGatt()
        worker.shutdownNow()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(
                mapOf(
                    "supported" to (adapter != null &&
                        activity.packageManager.hasSystemFeature("android.hardware.bluetooth_le")),
                    "enabled" to (adapter?.isEnabled == true),
                    "permitted" to permissions.granted(),
                ),
            )
            "requestPermission" -> permissions.request(result)
            "paired" -> result.success(emptyList<Any>())
            "startScan" -> startScan(result)
            "stopScan" -> {
                stopScan()
                result.success(null)
            }
            "pair" -> result.success(null)
            "open" -> open(call.argument<String>("address"), result)
            "close" -> {
                closeGatt()
                result.success(null)
            }
            "send" -> send(call.argument<String>("text"), result)
            else -> result.notImplemented()
        }
    }

    private fun unusable(result: MethodChannel.Result): Boolean {
        if (adapter == null || !activity.packageManager.hasSystemFeature("android.hardware.bluetooth_le")) {
            result.error("unsupported", "This phone has no Bluetooth LE", null)
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

    // ---- looking for adapters --------------------------------------------

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = result.device.name ?: result.scanRecord?.deviceName ?: ""
            main.post {
                sink?.success(
                    mapOf(
                        "type" to "found",
                        "name" to name,
                        "address" to result.device.address,
                        "paired" to false,
                    ),
                )
            }
        }
    }

    private fun startScan(result: MethodChannel.Result) {
        if (unusable(result)) return
        stopScan()
        val scanner = adapter!!.bluetoothLeScanner
        if (scanner == null) {
            result.error("radio_off", "Bluetooth is switched off", null)
            return
        }
        try {
            scanner.startScan(
                null,
                ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),
                scanCallback,
            )
            scanning = true
            result.success(null)
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        }
    }

    private fun stopScan() {
        if (!scanning) return
        scanning = false
        try {
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (e: SecurityException) {
            // Permission taken away while scanning: nothing left to stop.
        }
    }

    // ---- the link --------------------------------------------------------

    private fun open(address: String?, result: MethodChannel.Result) {
        if (unusable(result)) return
        val device: BluetoothDevice? = try {
            if (address == null) null else adapter!!.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            null
        }
        if (device == null) {
            result.error("connect_failed", "No such device: $address", null)
            return
        }
        stopScan()
        closeGatt()
        closing = false
        ready = false
        mtu = DEFAULT_MTU
        openResult = result
        openTimeout = Runnable { failOpen("The adapter did not answer") }.also {
            main.postDelayed(it, OPEN_TIMEOUT_MS)
        }
        try {
            gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(activity, false, callback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(activity, false, callback)
            }
        } catch (e: SecurityException) {
            failOpen("Bluetooth permission is not granted", "permission_denied")
        }
    }

    private fun succeedOpen() {
        openTimeout?.let { main.removeCallbacks(it) }
        openTimeout = null
        val r = openResult
        openResult = null
        ready = true
        r?.success(null)
    }

    private fun failOpen(message: String, code: String = "connect_failed") {
        openTimeout?.let { main.removeCallbacks(it) }
        openTimeout = null
        val r = openResult
        openResult = null
        closeGatt()
        r?.error(code, message, null)
    }

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    // A bigger MTU means fewer, larger writes; the answer comes below.
                    if (!g.requestMtu(REQUESTED_MTU)) g.discoverServices()
                }
                BluetoothProfile.STATE_DISCONNECTED -> main.post {
                    if (gatt !== g) return@post
                    if (!ready) {
                        failOpen("The adapter did not accept the connection")
                    } else if (!closing) {
                        closeGatt()
                        sink?.success(mapOf("type" to "lost"))
                    }
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, newMtu: Int, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) mtu = newMtu
            g.discoverServices()
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                main.post { failOpen("Could not read the adapter's services") }
                return
            }
            val pipe = findSerial(g)
            if (pipe == null) {
                main.post { failOpen("This adapter has no serial service TapeDash knows") }
                return
            }
            writer = pipe.second
            g.setCharacteristicNotification(pipe.first, true)
            val cccd = pipe.first.getDescriptor(CCCD)
            if (cccd == null) {
                // Nothing to write: the notifications are on, as far as can be told.
                main.post { succeedOpen() }
                return
            }
            val value = if (pipe.first.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
                BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            } else {
                BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
            }
            writeDescriptor(g, cccd, value)
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            main.post {
                if (status == BluetoothGatt.GATT_SUCCESS) succeedOpen()
                else failOpen("Could not turn the adapter's notifications on")
            }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            writeDone.release()
        }

        // Android 13 and later give the value here; earlier ones in the characteristic.
        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            c: BluetoothGattCharacteristic,
            value: ByteArray,
        ) = deliver(value)

        @Deprecated("Replaced by the version with the value, from Android 13")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            c.value?.let { deliver(it) }
        }
    }

    private fun deliver(bytes: ByteArray) {
        val text = String(bytes, Charsets.ISO_8859_1)
        main.post { sink?.success(mapOf("type" to "data", "text" to text)) }
    }

    /**
     * The characteristic to listen to and the one to write, or null. They are the
     * same when one characteristic does both.
     */
    private fun findSerial(g: BluetoothGatt): Pair<BluetoothGattCharacteristic, BluetoothGattCharacteristic>? {
        fun notifies(c: BluetoothGattCharacteristic) = c.properties and
            (BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
        fun writable(c: BluetoothGattCharacteristic) = c.properties and
            (BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0

        // The known layouts first.
        for ((service, listen, write) in KNOWN) {
            val s = g.getService(service) ?: continue
            val l = s.getCharacteristic(listen) ?: continue
            val w = s.getCharacteristic(write) ?: continue
            if (notifies(l) && writable(w)) return l to w
        }
        // Then any service that looks like a serial port.
        for (s in g.services) {
            if (s.uuid in STANDARD_SERVICES) continue
            val both = s.characteristics.firstOrNull { notifies(it) && writable(it) }
            if (both != null) return both to both
            val l = s.characteristics.firstOrNull { notifies(it) }
            val w = s.characteristics.firstOrNull { writable(it) }
            if (l != null && w != null) return l to w
        }
        return null
    }

    private fun writeDescriptor(g: BluetoothGatt, d: BluetoothGattDescriptor, value: ByteArray) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeDescriptor(d, value)
        } else {
            @Suppress("DEPRECATION")
            d.value = value
            @Suppress("DEPRECATION")
            g.writeDescriptor(d)
        }
    }

    private fun send(text: String?, result: MethodChannel.Result) {
        val g = gatt
        val w = writer
        if (text == null || g == null || w == null || !ready) {
            result.error("not_connected", "No adapter is connected", null)
            return
        }
        worker.execute {
            val bytes = text.toByteArray(Charsets.ISO_8859_1)
            val chunk = (mtu - ATT_OVERHEAD).coerceAtLeast(MIN_CHUNK)
            val type = if (w.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0) {
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            } else {
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            }
            var ok = true
            var at = 0
            while (at < bytes.size && ok) {
                val piece = bytes.copyOfRange(at, minOf(at + chunk, bytes.size))
                writeDone.drainPermits()
                ok = writeCharacteristic(g, w, piece, type) &&
                    writeDone.tryAcquire(WRITE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                at += chunk
            }
            main.post {
                if (ok) {
                    result.success(null)
                } else {
                    result.error("not_connected", "The write did not complete", null)
                    if (ready && !closing) {
                        closeGatt()
                        sink?.success(mapOf("type" to "lost"))
                    }
                }
            }
        }
    }

    private fun writeCharacteristic(
        g: BluetoothGatt,
        c: BluetoothGattCharacteristic,
        bytes: ByteArray,
        type: Int,
    ): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeCharacteristic(c, bytes, type) == android.bluetooth.BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            c.writeType = type
            @Suppress("DEPRECATION")
            c.value = bytes
            @Suppress("DEPRECATION")
            g.writeCharacteristic(c)
        }
    } catch (e: SecurityException) {
        false
    }

    private fun closeGatt() {
        closing = true
        ready = false
        writer = null
        val g = gatt
        gatt = null
        try {
            g?.disconnect()
            g?.close()
        } catch (e: SecurityException) {
            // Permission taken away: nothing left to close.
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    companion object {
        private const val DEFAULT_MTU = 23
        private const val REQUESTED_MTU = 185
        private const val ATT_OVERHEAD = 3
        private const val MIN_CHUNK = 20
        private const val OPEN_TIMEOUT_MS = 15_000L
        private const val WRITE_TIMEOUT_MS = 2_000L

        private fun uuid16(short: String): UUID =
            UUID.fromString("0000$short-0000-1000-8000-00805f9b34fb")

        /** The client characteristic configuration descriptor, which turns notifications on. */
        private val CCCD: UUID = uuid16("2902")

        /** Services every device has: never the serial port. */
        private val STANDARD_SERVICES = setOf(uuid16("1800"), uuid16("1801"), uuid16("180a"))

        /** Service, the characteristic to listen to, the one to write. */
        private val KNOWN: List<Triple<UUID, UUID, UUID>> = listOf(
            Triple(uuid16("ffe0"), uuid16("ffe1"), uuid16("ffe1")),
            Triple(uuid16("fff0"), uuid16("fff1"), uuid16("fff2")),
            Triple(uuid16("18f0"), uuid16("2af0"), uuid16("2af1")),
            // The OBDLink CX: one service, one characteristic that does both.
            Triple(
                UUID.fromString("e7810a71-73ae-499d-8c15-faa9aef0c3f2"),
                UUID.fromString("bef8d6c9-9c21-4c9e-b632-bd58c1009f9f"),
                UUID.fromString("bef8d6c9-9c21-4c9e-b632-bd58c1009f9f"),
            ),
        )
    }
}
