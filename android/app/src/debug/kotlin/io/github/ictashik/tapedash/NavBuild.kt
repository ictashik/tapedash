package io.github.ictashik.tapedash

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * What a debug build adds to the navigation listener (docs/NAV.md, N1): TapeDash's
 * own package, so that the stand-in (NavStandInReceiver) can be seen on an
 * emulator, and the capture tool, which writes what Google Maps' notification
 * holds to the app's external files folder for the human to pull with adb.
 *
 * It also lets an integration test post the stand-in's notification from inside the
 * app, with no adb (`tapedash/nav/standin`).
 *
 * A release and a profile build have a NavBuild that adds nothing.
 */
object NavBuild {
    private var channel: MethodChannel? = null

    fun extraPackages(context: Context): Set<String> = setOf(context.packageName)

    fun tap(context: Context): NavTap? = NavCapture(context)

    /** The integration tests' way to post the stand-in: the extras of the broadcast. */
    fun attach(context: Context, messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "tapedash/nav/standin").also { c ->
            c.setMethodCallHandler { call, result ->
                if (call.method != "post") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val intent = Intent(context, NavStandInReceiver::class.java)
                (call.arguments as? Map<*, *>)?.forEach { (key, value) ->
                    when (value) {
                        is String -> intent.putExtra(key as String, value)
                        is Int -> intent.putExtra(key as String, value)
                        is Boolean -> intent.putExtra(key as String, value)
                    }
                }
                context.sendBroadcast(intent)
                result.success(true)
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
