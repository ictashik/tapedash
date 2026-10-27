package io.github.ictashik.tapedash

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
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
 * - **`openMapsNotificationSettings`**: Android's own screen for Google Maps'
 *   notifications, where the person can switch off the card Maps pops over the screen
 *   at a turn. It opens a Settings page; it does not start Maps or send it anything.
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
            "access" -> {
                val granted = NotificationManagerCompat.getEnabledListenerPackages(activity)
                    .contains(activity.packageName)
                // Granted, and not connected, is what Android 7 can do after an update.
                if (granted && NavBridge.listening) NavListenerService.ensureBound(activity)
                result.success(granted)
            }
            "openAccessSettings" -> result.success(openAccessSettings())
            "mapsVersion" -> result.success(mapsVersion())
            "openMapsNotificationSettings" -> result.success(openMapsNotificationSettings())
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        NavBridge.attach { sink.success(it) }
        // The person has switched it on: see that the listener is there to hear.
        NavListenerService.ensureBound(activity)
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

    /**
     * The page of Google Maps' notification channels in Android's Settings. On Android 8
     * and later that is the public app-notification page, which lists the channels
     * (one of them is "Navigation urgent updates", the card). Before that there are no
     * channels, and the app's own details page is the nearest.
     */
    private fun openMapsNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, NavSources.GOOGLE_MAPS)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", NavSources.GOOGLE_MAPS, null))
        }
        return try {
            activity.startActivity(intent)
            true
        } catch (e: RuntimeException) {
            false
        }
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
