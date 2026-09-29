package io.github.ictashik.tapedash

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's own GPS (CLAUDE.md 5): a thin layer over the platform
 * `LocationManager` and its GNSS provider. There is no fused provider and no
 * Google Play Services, so this works on a phone without them and offline.
 *
 * It is the Android side of lib/platform/native_location_source.dart. The channel
 * names, the method names and the shape of a fix have to match it.
 *
 * Unverified on hardware until the handoff (CLAUDE.md 11).
 *
 * Everything arrives on the main thread, so nothing here needs a lock.
 */
class GpsChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, LocationListener {

    private val methods = MethodChannel(messenger, "tapedash/gps")
    private val events = EventChannel(messenger, "tapedash/gps/fixes")
    private val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    private var sink: EventChannel.EventSink? = null
    private var running = false
    private var pendingPermission: MethodChannel.Result? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        stopUpdates()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        pendingPermission = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermission(result)
            "isEnabled" -> result.success(gpsEnabled())
            "start" -> start(result)
            "stop" -> {
                stopUpdates()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermission() =
        ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun gpsEnabled() = try {
        manager.isProviderEnabled(LocationManager.GPS_PROVIDER)
    } catch (e: SecurityException) {
        false
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }
        // One request at a time: a second is told no rather than left hanging.
        if (pendingPermission != null) {
            result.success(false)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
            REQUEST_CODE,
        )
    }

    /** Called from the activity with the user's answer. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_CODE) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    private fun start(result: MethodChannel.Result) {
        if (!hasPermission()) {
            result.error("permission_denied", "Location permission is not granted", null)
            return
        }
        try {
            if (!running) {
                manager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    UPDATE_INTERVAL_MS,
                    0f,
                    this,
                    activity.mainLooper,
                )
                running = true
            }
            result.success(null)
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        } catch (e: IllegalArgumentException) {
            // No GPS provider on this phone.
            result.error("no_gps", e.message, null)
        }
    }

    private fun stopUpdates() {
        if (!running) return
        running = false
        try {
            manager.removeUpdates(this)
        } catch (e: SecurityException) {
            // Permission taken away while running: nothing left to stop.
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onLocationChanged(location: Location) {
        sink?.success(toMap(location))
    }

    // Older Android versions call these; nothing to do.
    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    override fun onProviderEnabled(provider: String) {}

    override fun onProviderDisabled(provider: String) {}

    private fun toMap(l: Location): Map<String, Any?> = mapOf(
        "latitude" to l.latitude,
        "longitude" to l.longitude,
        // Metres per second; -1 when the receiver has no speed.
        "speed" to if (l.hasSpeed()) l.speed.toDouble() else -1.0,
        // Null when not known, as when standing still.
        "bearing" to if (l.hasBearing()) l.bearing.toDouble() else null,
        "altitude" to if (l.hasAltitude()) l.altitude else 0.0,
        "accuracy" to if (l.hasAccuracy()) l.accuracy.toDouble() else -1.0,
        "timeMillis" to l.time,
    )

    companion object {
        private const val REQUEST_CODE = 4127
        private const val UPDATE_INTERVAL_MS = 1000L
    }
}
