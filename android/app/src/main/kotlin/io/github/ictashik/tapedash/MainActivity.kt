package io.github.ictashik.tapedash

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var device: DeviceChannel? = null
    private var gps: GpsChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        device = DeviceChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        gps = GpsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        device?.dispose()
        device = null
        gps?.dispose()
        gps = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        device?.onWindowFocusChanged(hasFocus)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        gps?.onRequestPermissionsResult(requestCode, grantResults)
    }
}
