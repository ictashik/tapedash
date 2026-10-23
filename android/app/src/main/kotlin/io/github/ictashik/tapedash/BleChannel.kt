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
 * once and `paired` lists nothing. Besides `found`, `data` and `lost` it sends
 * `diag` events: a line of plain text about what the radio just did (a status code,
 * the services found), which the app writes into its connection log, since a link
 * that will not come up is otherwise a silence.
 *
 * **Which characteristics carry the serial data.** BLE ELM327s put a UART on GATT
 * in a few well-known ways, tried in this order: a service `FFE0` with one
 * characteristic `FFE1` that both notifies and is written; `FFF0` with `FFF1`
 * (notify) and `FFF2` (write); `18F0` with `2AF0` and `2AF1`; and the OBDLink CX's
 * own service. Failing those, any service that is not one of the standard GATT
 * ones (1800, 1801, 180A) with a characteristic that notifies and one that is
 * written (the same one, or two). What an adapter actually offers is in the log.
 *
 * **Why it opens the way it does** (a cheap adapter is the fussy end of Bluetooth,
 * and a phone that is rarely asked for reliability is the other):
 *  - A link is let go of properly: `disconnect()`, then wait for the stack to say it
 *    has, and only then `close()`. Closing straight after disconnecting can leave the
 *    adapter holding a connection nobody owns, and it then refuses the next one
 *    (the "connecting, then unreachable after 15 s" of the first drives).
 *  - A connection is tried up to three times, each with its own time limit, with a
 *    pause that grows, and the GATT cache dropped on a retry. Status 133 and its
 *    relatives are common and usually pass on the second try.
 *  - The MTU request is optional. An adapter that never answers it must not hold the
 *    connection for ever: after a second and a half the services are looked for
 *    anyway.
 *  - Service discovery waits a moment after the connection is up, which some phones
 *    need.
 *  - Once up, the connection interval is asked to be short (`CONNECTION_PRIORITY_HIGH`),
 *    which is the cheapest speed-up a BLE adapter has.
 *
 * **Verified on a phone only as far as the first drives** (CLAUDE.md 11): the first
 * version connected and read an `OBDBLE` adapter; the retries, the graceful release
 * and the diagnostics are new and have not met one.
 *
 * The GATT callbacks arrive on Binder threads and are handed to the main thread at
 * once, where all state is kept; writes go one at a time from a worker thread, each
 * waiting for its callback.
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
    // failed attempt, and after it a lost link. All of it is touched on the main
    // thread, except what the writer thread reads (hence the volatiles).
    @Volatile private var gatt: BluetoothGatt? = null
    @Volatile private var writer: BluetoothGattCharacteristic? = null
    @Volatile private var ready = false
    @Volatile private var closing = false
    @Volatile private var mtu = DEFAULT_MTU

    // A request to open, and where it has got to.
    private var openResult: MethodChannel.Result? = null
    private var target: BluetoothDevice? = null
    private var attempt = 0
    private var discovering = false

    // Which open this is: a retry or a pause that was scheduled for an earlier one
    // finds a different number and does nothing.
    private var generation = 0

    private var openTimeout: Runnable? = null
    private var attemptTimeout: Runnable? = null
    private var mtuTimeout: Runnable? = null

    // A link being let go of, and what finishes the job.
    private var releasing: BluetoothGatt? = null
    private var releaseDone: Runnable? = null

    private val writeDone = Semaphore(0)

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        stopScan()
        generation++
        cancelOpenTimers()
        release {}
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
            "pair", "unpair" -> result.success(null)
            "open" -> open(call.argument<String>("address"), result)
            "close" -> {
                generation++
                cancelOpenTimers()
                openResult?.error("connect_failed", "The connection was cancelled", null)
                openResult = null
                // Answered once the link is really let go of, so that what the app
                // does next (open it again) finds the adapter free.
                release { result.success(null) }
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

    /** A line for the app's connection log. */
    private fun diag(text: String) {
        main.post { sink?.success(mapOf("type" to "diag", "text" to "ble: $text")) }
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
                        "rssi" to result.rssi,
                    ),
                )
            }
        }

        override fun onScanFailed(errorCode: Int) {
            diag("scan failed, error $errorCode")
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

    // ---- opening the link --------------------------------------------------

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
        // An open still waiting is answered, not forgotten.
        openResult?.error("connect_failed", "Another connection was asked for", null)
        cancelOpenTimers()
        val mine = ++generation
        openResult = result
        target = device
        attempt = 0
        diag("opening ${device.address} (${device.name ?: "no name"})")
        openTimeout = Runnable { failOpen("The adapter did not answer in time") }.also {
            main.postDelayed(it, OPEN_TIMEOUT_MS)
        }
        // Whatever was open is let go of properly before the next is made.
        release { startAttempt(mine) }
    }

    private fun startAttempt(mine: Int) {
        if (mine != generation) return
        val device = target ?: return
        attempt++
        closing = false
        ready = false
        discovering = false
        mtu = DEFAULT_MTU
        diag("attempt $attempt of $MAX_ATTEMPTS: connecting")
        attemptTimeout?.let { main.removeCallbacks(it) }
        attemptTimeout = Runnable {
            retryOrFail(mine, "no answer in ${ATTEMPT_TIMEOUT_MS / 1000} s")
        }.also { main.postDelayed(it, ATTEMPT_TIMEOUT_MS) }
        try {
            val g = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(activity, false, callback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(activity, false, callback)
            }
            gatt = g
            if (g == null) retryOrFail(mine, "the phone would not start a connection")
        } catch (e: SecurityException) {
            failOpen("Bluetooth permission is not granted", "permission_denied")
        }
    }

    /** This attempt failed: let go, wait a little, and try again if there are tries left. */
    private fun retryOrFail(mine: Int, reason: String) {
        if (mine != generation || openResult == null) return
        diag("attempt $attempt failed: $reason")
        attemptTimeout?.let { main.removeCallbacks(it) }
        attemptTimeout = null
        if (attempt >= MAX_ATTEMPTS) {
            failOpen("Could not connect ($reason)")
            return
        }
        release { main.postDelayed({ startAttempt(mine) }, RETRY_PAUSE_MS * attempt) }
    }

    private fun cancelOpenTimers() {
        openTimeout?.let { main.removeCallbacks(it) }
        attemptTimeout?.let { main.removeCallbacks(it) }
        mtuTimeout?.let { main.removeCallbacks(it) }
        openTimeout = null
        attemptTimeout = null
        mtuTimeout = null
    }

    private fun succeedOpen() {
        cancelOpenTimers()
        val r = openResult
        openResult = null
        closing = false
        ready = true
        diag("ready after attempt $attempt, mtu $mtu")
        // A short connection interval is the cheapest speed-up there is.
        try {
            gatt?.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
        } catch (e: Exception) {
            // Not every phone lets an app ask.
        }
        r?.success(null)
    }

    private fun failOpen(message: String, code: String = "connect_failed") {
        generation++
        cancelOpenTimers()
        val r = openResult
        openResult = null
        diag("open failed: $message")
        release {}
        r?.error(code, message, null)
    }

    // ---- letting go --------------------------------------------------------

    /**
     * Lets go of the current link and then runs [then]: `disconnect()`, a wait for the
     * stack to say it has (or [RELEASE_WAIT_MS]), `close()`, and a short settle. Safe
     * with no link.
     */
    private fun release(then: () -> Unit) {
        closing = true
        ready = false
        writer = null
        discovering = false
        mtuTimeout?.let { main.removeCallbacks(it) }
        mtuTimeout = null
        // A release already under way is finished now; the new one follows it.
        releaseDone?.let {
            main.removeCallbacks(it)
            it.run()
        }
        val g = gatt
        gatt = null
        if (g == null) {
            then()
            return
        }
        releasing = g
        val finish = Runnable {
            if (releasing !== g) return@Runnable
            releasing = null
            releaseDone = null
            try {
                g.close()
            } catch (e: Exception) {
                // Already gone.
            }
            main.postDelayed({ then() }, SETTLE_MS)
        }
        releaseDone = finish
        try {
            g.disconnect()
        } catch (e: SecurityException) {
            finish.run()
            return
        } catch (e: Exception) {
            finish.run()
            return
        }
        main.postDelayed(finish, RELEASE_WAIT_MS)
    }

    // ---- the GATT callbacks ------------------------------------------------

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                if (releasing === g) {
                    // The stack has let go: the release can finish now.
                    if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                        releaseDone?.let {
                            main.removeCallbacks(it)
                            it.run()
                        }
                    }
                    return@post
                }
                if (gatt !== g) return@post
                diag("link status=$status state=${stateName(newState)}")
                if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    if (!ready) afterConnect(g)
                    return@post
                }
                // Disconnected, or a connection that came with an error.
                if (!ready) {
                    retryOrFail(generation, "connection state $status")
                } else if (!closing) {
                    release {}
                    sink?.success(mapOf("type" to "lost"))
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, newMtu: Int, status: Int) {
            main.post {
                if (gatt !== g) return@post
                mtuTimeout?.let { main.removeCallbacks(it) }
                mtuTimeout = null
                if (status == BluetoothGatt.GATT_SUCCESS) mtu = newMtu
                diag("mtu $newMtu (status $status)")
                discover(g)
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            main.post {
                if (gatt !== g) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    retryOrFail(generation, "services not read, status $status")
                    return@post
                }
                diag("services: ${describe(g)}")
                if (g.services.isEmpty()) {
                    retryOrFail(generation, "the adapter listed no services")
                    return@post
                }
                val pipe = findSerial(g)
                if (pipe == null) {
                    failOpen("This adapter has no serial service TapeDash knows")
                    return@post
                }
                writer = pipe.second
                diag("serial: listen ${pipe.first.uuid}, write ${pipe.second.uuid}")
                if (!g.setCharacteristicNotification(pipe.first, true)) {
                    diag("the phone would not turn notifications on locally")
                }
                val cccd = pipe.first.getDescriptor(CCCD)
                if (cccd == null) {
                    // Nothing to write: the notifications are on, as far as can be told.
                    succeedOpen()
                    return@post
                }
                val value = if (pipe.first.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                } else {
                    BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                }
                if (!writeDescriptor(g, cccd, value)) {
                    retryOrFail(generation, "the phone would not write the notification switch")
                }
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            main.post {
                if (gatt !== g) return@post
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    succeedOpen()
                } else {
                    retryOrFail(generation, "notifications refused, status $status")
                }
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

    /** The link is up: a moment, then the MTU (optionally), then the services. */
    private fun afterConnect(g: BluetoothGatt) {
        val mine = generation
        main.postDelayed({
            if (gatt !== g || mine != generation) return@postDelayed
            // A retry starts from nothing: what the phone remembers of this adapter's
            // services from an earlier try may be stale or empty.
            if (attempt > 1) refresh(g)
            val asked = try {
                g.requestMtu(REQUESTED_MTU)
            } catch (e: Exception) {
                false
            }
            if (asked) {
                mtuTimeout = Runnable {
                    mtuTimeout = null
                    diag("no answer to the MTU request; going on without it")
                    discover(g)
                }.also { main.postDelayed(it, MTU_WAIT_MS) }
            } else {
                discover(g)
            }
        }, AFTER_CONNECT_DELAY_MS)
    }

    private fun discover(g: BluetoothGatt) {
        if (gatt !== g || discovering) return
        discovering = true
        val started = try {
            g.discoverServices()
        } catch (e: Exception) {
            false
        }
        if (!started) retryOrFail(generation, "the phone would not look for services")
    }

    /** `BluetoothGatt.refresh()` is hidden from the SDK, so it is called by name. */
    private fun refresh(g: BluetoothGatt) {
        try {
            g.javaClass.getMethod("refresh").invoke(g)
            diag("service cache cleared")
        } catch (e: Exception) {
            // Not on this phone.
        }
    }

    private fun deliver(bytes: ByteArray) {
        val text = String(bytes, Charsets.ISO_8859_1)
        main.post { sink?.success(mapOf("type" to "data", "text" to text)) }
    }

    private fun stateName(state: Int) = when (state) {
        BluetoothProfile.STATE_CONNECTED -> "connected"
        BluetoothProfile.STATE_CONNECTING -> "connecting"
        BluetoothProfile.STATE_DISCONNECTED -> "disconnected"
        BluetoothProfile.STATE_DISCONNECTING -> "disconnecting"
        else -> "state $state"
    }

    /** What an adapter offers, short enough for one line of a log. */
    private fun describe(g: BluetoothGatt): String = g.services.joinToString("; ") { s ->
        val chars = s.characteristics.joinToString(",") { c ->
            val flags = buildString {
                if (c.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) append('N')
                if (c.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0) append('I')
                if (c.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0) append('W')
                if (c.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0) append('w')
                if (c.properties and BluetoothGattCharacteristic.PROPERTY_READ != 0) append('R')
            }
            "${shortUuid(c.uuid)}[$flags]"
        }
        "${shortUuid(s.uuid)}{$chars}"
    }

    private fun shortUuid(u: UUID): String {
        val s = u.toString()
        return if (s.startsWith("0000") && s.endsWith("-0000-1000-8000-00805f9b34fb")) s.substring(4, 8) else s
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

    private fun writeDescriptor(g: BluetoothGatt, d: BluetoothGattDescriptor, value: ByteArray): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeDescriptor(d, value) == android.bluetooth.BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            d.value = value
            @Suppress("DEPRECATION")
            g.writeDescriptor(d)
        }
    } catch (e: SecurityException) {
        false
    }

    // ---- writing ----------------------------------------------------------

    private fun send(text: String?, result: MethodChannel.Result) {
        val g = gatt
        val w = writer
        if (text == null || g == null || w == null || !ready) {
            result.error("not_connected", "No adapter is connected", null)
            return
        }
        worker.execute {
            val bytes = text.toByteArray(Charsets.ISO_8859_1)
            // A command is a handful of bytes. 20 is what every adapter takes in one
            // write, whatever MTU it agreed to.
            val chunk = minOf(mtu - ATT_OVERHEAD, MAX_CHUNK).coerceAtLeast(MIN_CHUNK)
            val noResponse = w.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
            val type = if (noResponse) {
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            } else {
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            }
            var ok = true
            var at = 0
            while (at < bytes.size && ok) {
                val piece = bytes.copyOfRange(at, minOf(at + chunk, bytes.size))
                writeDone.drainPermits()
                ok = writeCharacteristic(g, w, piece, type)
                if (ok) {
                    val answered = writeDone.tryAcquire(WRITE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    // A write without a response is on its way once the phone has
                    // taken it; some phones never say so. That is not a lost link.
                    if (!answered && !noResponse) ok = false
                    if (!answered && noResponse) diag("no write callback; carrying on")
                }
                at += chunk
            }
            main.post {
                if (ok) {
                    result.success(null)
                } else {
                    result.error("not_connected", "The write did not complete", null)
                    if (ready && !closing && gatt === g) {
                        diag("write failed: the link is lost")
                        release {}
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
        private const val MAX_CHUNK = 20

        /** The whole of an open, however many tries it takes. */
        private const val OPEN_TIMEOUT_MS = 40_000L

        /** One try at connecting, up to the notifications being on. */
        private const val ATTEMPT_TIMEOUT_MS = 10_000L
        private const val MAX_ATTEMPTS = 3

        /** Between tries, times the number of tries so far. */
        private const val RETRY_PAUSE_MS = 700L

        /** How long the stack gets to say a link is gone before it is closed anyway. */
        private const val RELEASE_WAIT_MS = 1_500L

        /** After a close, before the next connect: the adapter needs a moment too. */
        private const val SETTLE_MS = 300L
        private const val AFTER_CONNECT_DELAY_MS = 300L
        private const val MTU_WAIT_MS = 1_500L
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
