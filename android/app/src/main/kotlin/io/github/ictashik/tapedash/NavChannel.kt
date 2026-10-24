package io.github.ictashik.tapedash

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * What the navigation HUD needs from Android that Dart cannot do (docs/NAV.md):
 *
 * - **`access`**: whether TapeDash has been granted Notification access.
 * - **`openAccessSettings`**: Android's own screen to grant it. The app cannot grant
 *   it itself, and does not ask for more than that.
 * - **`mapsVersion`**: the version of Google Maps on the phone, or null if it is not
 *   there. Only this one package is looked for (a `<queries>` entry).
 * - **`tapedash/nav/events`**: what NavListenerService sees of Maps' navigation
 *   notification, while Dart listens (NavBridge).
 *
 * This is the Android side of lib/platform/nav_channel.dart. The channel names and
 * arguments have to match it. **Unverified on a phone** (CLAUDE.md 11); it has been
 * run on an Android 16 emulator against real Google Maps.
 */
class NavChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methods = MethodChannel(messenger, "tapedash/nav")
    private val events = EventChannel(messenger, "tapedash/nav/events")

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        NavBridge.detach()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "access" -> result.success(
                NotificationManagerCompat.getEnabledListenerPackages(activity)
                    .contains(activity.packageName),
            )
            "openAccessSettings" -> result.success(openAccessSettings())
            "mapsVersion" -> result.success(mapsVersion())
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        NavBridge.attach { sink.success(it) }
    }

    override fun onCancel(arguments: Any?) {
        NavBridge.detach()
    }

    /** Android 11 and later can open the page of this app's listener directly. */
    private fun openAccessSettings(): Boolean {
        val detail = if (Build.VERSION.SDK_INT >= 30) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                ComponentName(activity, NavListenerService::class.java).flattenToString(),
            )
        } else {
            null
        }
        for (intent in listOfNotNull(detail, Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))) {
            try {
                activity.startActivity(intent)
                return true
            } catch (e: RuntimeException) {
                // Try the next: a phone may have only the list.
            }
        }
        return false
    }

    private fun mapsVersion(): String? =
        try {
            activity.packageManager
                .getPackageInfo(NavSources.GOOGLE_MAPS, 0)
                .versionName
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
}
