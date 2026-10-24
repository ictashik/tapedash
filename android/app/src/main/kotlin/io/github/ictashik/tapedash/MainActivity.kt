package io.github.ictashik.tapedash

import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Bundle
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var device: DeviceChannel? = null
    private var gps: GpsChannel? = null
    private var bluetoothPermissions: BluetoothPermissions? = null
    private var btClassic: BtClassicChannel? = null
    private var ble: BleChannel? = null
    private var engineAudio: EngineAudioChannel? = null
    private var share: ShareChannel? = null
    private var exchange: ExchangeChannel? = null
    private var nav: NavChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // The manifest locks a phone to landscape (CLAUDE.md 3). A watch has an
        // up, which is 12 o'clock, and keeps the orientation the system gives it
        // (DESIGN.md 16.2).
        if (DeviceChannel.isWatch(this)) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        super.onCreate(savedInstanceState)
    }

    // A turn of the watch's bezel or crown (DESIGN.md 16.6).
    override fun onGenericMotionEvent(event: MotionEvent): Boolean =
        device?.onGenericMotionEvent(event) == true || super.onGenericMotionEvent(event)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        device = DeviceChannel(this, messenger)
        gps = GpsChannel(this, messenger)
        val permissions = BluetoothPermissions(this)
        bluetoothPermissions = permissions
        btClassic = BtClassicChannel(this, messenger, permissions)
        ble = BleChannel(this, messenger, permissions)
        engineAudio = EngineAudioChannel(this, messenger)
        share = ShareChannel(this, messenger)
        exchange = ExchangeChannel(this, messenger)
        nav = NavChannel(this, messenger)
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
        engineAudio?.dispose()
        engineAudio = null
        share?.dispose()
        share = null
        exchange?.dispose()
        exchange = null
        nav?.dispose()
        nav = null
        bluetoothPermissions?.dispose()
        bluetoothPermissions = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // A launch from adb while the app is already running (singleTop) brings a new
    // intent here (docs/EXCHANGE.md 5).
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        exchange?.readRequest(intent)
    }

    @Deprecated("The picker answers through the platform's own result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        exchange?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onStop() {
        super.onStop()
        // The engine sound is a sound of the screen that is showing (no service).
        engineAudio?.onAppStopped()
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
