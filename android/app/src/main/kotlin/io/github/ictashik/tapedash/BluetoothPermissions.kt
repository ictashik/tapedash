package io.github.ictashik.tapedash

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

/**
 * The runtime permissions the Bluetooth channels need (CLAUDE.md 4), asked for in
 * one place so the Classic and BLE channels share one dialog and one request code.
 *
 * On Android 12 and later that is BLUETOOTH_CONNECT and BLUETOOTH_SCAN (the
 * manifest declares the scan one `neverForLocation`, so the app never needs the
 * location permission for Bluetooth). Before Android 12, connecting to a paired
 * adapter needs no runtime permission, and scanning needs ACCESS_FINE_LOCATION,
 * which the app declares for its GPS anyway.
 *
 * Unverified on hardware until the handoff (CLAUDE.md 11). Everything runs on the
 * main thread.
 */
class BluetoothPermissions(private val activity: Activity) {

    private var pending: MethodChannel.Result? = null

    /** What has to be granted before a scan or a connection can be made. */
    fun required(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    fun granted(): Boolean = required().all {
        ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
    }

    /** Asks, or answers at once if it is already granted. */
    fun request(result: MethodChannel.Result) {
        if (granted()) {
            result.success(true)
            return
        }
        // One request at a time: a second is told no rather than left hanging.
        if (pending != null) {
            result.success(false)
            return
        }
        pending = result
        ActivityCompat.requestPermissions(activity, required(), REQUEST_CODE)
    }

    /** Called from the activity with the user's answer. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_CODE) return
        val ok = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pending?.success(ok)
        pending = null
    }

    fun dispose() {
        pending = null
    }

    companion object {
        private const val REQUEST_CODE = 7101
    }
}
