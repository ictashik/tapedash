package io.github.ictashik.tapedash

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Build
import android.view.InputDevice
import android.view.MotionEvent
import android.view.Surface
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's own features that Flutter does not expose: the screen's power,
 * brightness and system bars, the battery temperature, and the light and
 * acceleration sensors (CLAUDE.md 5). No plugin, just small native calls.
 *
 * This is the Android side of lib/platform/device_channel.dart. The channel
 * names and arguments have to match it.
 *
 * Channel calls and sensor callbacks both arrive on the main thread, so
 * nothing here needs a lock.
 */
class DeviceChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val methods = MethodChannel(messenger, "tapedash/device")
    private val lightEvents = EventChannel(messenger, "tapedash/device/light")
    private val accelerationEvents = EventChannel(messenger, "tapedash/device/acceleration")
    private val rotaryEvents = EventChannel(messenger, "tapedash/device/rotary")
    private val sensorManager = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    // Ambient light drives the Daylight and Night modes, which change slowly.
    private val lightStream = SensorStream(
        sensorManager,
        Sensor.TYPE_LIGHT,
        SensorManager.SENSOR_DELAY_NORMAL,
    ) { event -> event.values[0].toDouble() }

    // The sensor's own axes plus the display rotation. Dart turns that into
    // screen axes, where it can be unit-tested.
    private val accelerationStream = SensorStream(
        sensorManager,
        Sensor.TYPE_ACCELEROMETER,
        ACCELERATION_PERIOD_US,
    ) { event ->
        listOf(
            event.values[0].toDouble(),
            event.values[1].toDouble(),
            event.values[2].toDouble(),
            displayRotation(),
        )
    }

    private var immersive = false

    // A rotating bezel or crown: one event a detent, +1 clockwise (DESIGN.md 16.6).
    private var rotarySink: EventChannel.EventSink? = null

    init {
        methods.setMethodCallHandler(this)
        lightEvents.setStreamHandler(lightStream)
        accelerationEvents.setStreamHandler(accelerationStream)
        rotaryEvents.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    rotarySink = events
                }

                override fun onCancel(arguments: Any?) {
                    rotarySink = null
                }
            },
        )
    }

    /** Stops everything, when the Flutter engine goes away. */
    fun dispose() {
        methods.setMethodCallHandler(null)
        lightEvents.setStreamHandler(null)
        accelerationEvents.setStreamHandler(null)
        rotaryEvents.setStreamHandler(null)
        rotarySink = null
        lightStream.stop()
        accelerationStream.stop()
    }

    /**
     * The system can drop the immersive state when another window has had
     * focus, so put it back.
     */
    fun onWindowFocusChanged(hasFocus: Boolean) {
        if (hasFocus && immersive) applyImmersive()
    }

    /**
     * The bezel. Wear OS delivers a turn of the rotating bezel (or the crown) as a
     * scroll event from the rotary encoder source, which Flutter's view does not
     * claim. Returns true when the event was one and has been passed on.
     */
    fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (event.action != MotionEvent.ACTION_SCROLL ||
            !event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)
        ) {
            return false
        }
        val sink = rotarySink ?: return false
        // Clockwise reads as a negative scroll, so it is turned round. Only the
        // direction is sent: how big a value a detent makes differs by watch.
        val turn = -event.getAxisValue(MotionEvent.AXIS_SCROLL)
        if (turn == 0f) return true
        sink.success(if (turn > 0f) 1 else -1)
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deviceName" -> result.success(
                if (Build.MODEL.startsWith(Build.MANUFACTURER, ignoreCase = true)) {
                    Build.MODEL
                } else {
                    "${Build.MANUFACTURER} ${Build.MODEL}"
                },
            )

            "formFactor" -> result.success(
                mapOf(
                    "watch" to isWatch(activity),
                    "round" to activity.resources.configuration.isScreenRound,
                ),
            )

            "setKeepScreenOn" -> withEnabled(call, result) { enabled ->
                if (enabled) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            }

            "setImmersive" -> withEnabled(call, result) { enabled ->
                immersive = enabled
                applyImmersive()
            }

            "setBrightness" -> {
                // A double from 0 to 1, or null for the phone's own setting.
                setBrightness(call.argument<Double>("level"))
                result.success(null)
            }

            "batteryTemperature" -> result.success(batteryTemperatureCelsius())

            // Where session recordings go: reachable over USB without a permission.
            "externalFilesDirectory" -> result.success(activity.getExternalFilesDir(null)?.absolutePath)

            "sensorSupport" -> result.success(
                mapOf(
                    "ambientLight" to (sensorManager.getDefaultSensor(Sensor.TYPE_LIGHT) != null),
                    "accelerometer" to (sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null),
                ),
            )

            else -> result.notImplemented()
        }
    }

    private inline fun withEnabled(
        call: MethodCall,
        result: MethodChannel.Result,
        action: (Boolean) -> Unit,
    ) {
        val enabled = call.argument<Boolean>("enabled")
        if (enabled == null) {
            result.error("bad_arguments", "'enabled' must be a boolean", null)
            return
        }
        action(enabled)
        result.success(null)
    }

    private fun setBrightness(level: Double?) {
        val attributes = activity.window.attributes
        attributes.screenBrightness = if (level == null) {
            WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        } else {
            // Some phones treat 0 as backlight off, which would blank the dash.
            level.toFloat().coerceIn(MIN_BRIGHTNESS, 1f)
        }
        activity.window.attributes = attributes
    }

    private fun applyImmersive() {
        val window = activity.window
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val controller = window.insetsController ?: return
            if (immersive) {
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                controller.hide(WindowInsets.Type.systemBars())
            } else {
                controller.show(WindowInsets.Type.systemBars())
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                if (immersive) IMMERSIVE_FLAGS else View.SYSTEM_UI_FLAG_VISIBLE
        }
    }

    /** In degrees Celsius, or null if the phone does not report it. */
    private fun batteryTemperatureCelsius(): Double? {
        // A null receiver reads the last sticky broadcast and needs no permission.
        val status = activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?: return null
        val tenths = status.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
        return if (tenths == Int.MIN_VALUE) null else tenths / 10.0
    }

    /** Quarter turns of the drawn screen from the phone's natural orientation. */
    private fun displayRotation(): Int {
        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.rotation
        }
        // Surface.ROTATION_0..270 are 0..3, which is what the Dart side expects.
        return rotation
    }

    /**
     * One sensor as an EventChannel stream. It is switched on when Dart starts
     * listening and off when the last listener goes, so an unused sensor costs
     * no battery.
     */
    private class SensorStream(
        private val sensorManager: SensorManager,
        private val sensorType: Int,
        private val samplingPeriod: Int,
        private val convert: (SensorEvent) -> Any,
    ) : EventChannel.StreamHandler, SensorEventListener {

        private var sink: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val sensor = sensorManager.getDefaultSensor(sensorType)
            if (sensor == null || !sensorManager.registerListener(this, sensor, samplingPeriod)) {
                events.error("unavailable", "This phone has no such sensor", null)
                events.endOfStream()
                return
            }
            sink = events
        }

        override fun onCancel(arguments: Any?) = stop()

        fun stop() {
            sensorManager.unregisterListener(this)
            sink = null
        }

        override fun onSensorChanged(event: SensorEvent) {
            sink?.success(convert(event))
        }

        override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) = Unit
    }

    companion object {
        /** Whether this device is a watch (DESIGN.md 16.2). */
        fun isWatch(context: Context): Boolean {
            val ui = context.resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
            return ui == Configuration.UI_MODE_TYPE_WATCH ||
                context.packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH)
        }

        /** 25 readings a second, plenty for body roll. */
        const val ACCELERATION_PERIOD_US = 40_000

        /** Never fully dark; see setBrightness. */
        const val MIN_BRIGHTNESS = 0.01f

        @Suppress("DEPRECATION")
        const val IMMERSIVE_FLAGS =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
    }
}
