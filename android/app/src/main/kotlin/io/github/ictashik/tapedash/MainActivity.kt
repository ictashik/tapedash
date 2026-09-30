package io.github.ictashik.tapedash

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var device: DeviceChannel? = null
    private var gps: GpsChannel? = null
    private var bluetoothPermissions: BluetoothPermissions? = null
    private var btClassic: BtClassicChannel? = null
    private var ble: BleChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        device = DeviceChannel(this, messenger)
        gps = GpsChannel(this, messenger)
        val permissions = BluetoothPermissions(this)
        bluetoothPermissions = permissions
        btClassic = BtClassicChannel(this, messenger, permissions)
        ble = BleChannel(this, messenger, permissions)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        device?.dispose()
        device = null
        gps?.dispose()
        gps = null
        btClassic?.dispose()
        btClassic = null
        ble?.dispose()
        ble = null
        bluetoothPermissions?.dispose()
        bluetoothPermissions = null
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
        bluetoothPermissions?.onRequestPermissionsResult(requestCode, grantResults)
    }
}
