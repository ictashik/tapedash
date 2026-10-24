package io.github.ictashik.tapedash

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationManagerCompat

/**
 * Reads the navigation notification of a navigation app (Google Maps) so the HUD
 * can show the next turn (docs/NAV.md). Google Maps talks to the internet; this
 * does not, and it sends Maps nothing (CLAUDE.md 1 and 4).
 *
 * It does nothing until the person grants TapeDash Notification access in Android's
 * settings (or an adb command does, for testing), and then reads nothing until the
 * navigation switch in Garage is on (NavBridge).
 *
 * **The package filter is the first thing that happens to a notification.** Nothing
 * of one from another package is read, kept or logged. tool/check_offline.sh fails
 * if the notification is touched here, or handed on, before NavSources.isAllowed is
 * asked.
 */
class NavListenerService : NotificationListenerService() {
    private var allowed: Set<String> = NavSources.RELEASE_PACKAGES
    private var tap: NavTap? = null

    override fun onCreate() {
        super.onCreate()
        allowed = NavSources.allowed(NavBuild.extraPackages(this))
        tap = NavBuild.tap(this)
        // A debug build records what the bridge decides; a release build has no tap.
        NavBridge.note = tap?.let { t -> { text: String -> t.event(text) } }
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    override fun onListenerConnected() {
        current = this
        tap?.event("connected")
        NavBridge.link(true)
        // A navigation already under way when the access was granted.
        redeliver()
    }

    override fun onListenerDisconnected() {
        if (current === this) current = null
        tap?.event("disconnected")
        NavBridge.link(false)
        // Android 7 does not always bind it again by itself, after its process was killed
        // or the app was updated: ask. (Nothing happens if the access was taken away.)
        requestRebindSafely(this)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn != null) posted(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (!NavSources.isAllowed(sbn.packageName, allowed)) return
        tap?.removed(sbn)
        NavBridge.removed(sbn)
    }

    /** Shows what is on the phone's shade now, each notification through the filter. */
    fun redeliver() {
        try {
            activeNotifications?.forEach { posted(it) }
        } catch (e: RuntimeException) {
            tap?.event("active notifications refused")
        }
    }

    private fun posted(sbn: StatusBarNotification) {
        // The filter. Everything below may read the notification; nothing above does.
        if (!NavSources.isAllowed(sbn.packageName, allowed)) return
        tap?.posted(sbn)
        NavBridge.posted(this, sbn)
    }

    companion object {
        /** The connected listener, for NavBridge to ask for what is on the shade. */
        @Volatile
        var current: NavListenerService? = null
            private set

        private val main = Handler(Looper.getMainLooper())
        private var rebinding = false

        /**
         * Sees to it that a listener the person has switched on is connected.
         *
         * Android 7 can leave an enabled listener unbound until the phone is restarted,
         * after its app was updated or killed (found on an Android 7 emulator, where
         * the system listed it as enabled and never tried to bind it). So when the app
         * starts to listen and the listener is not there, the system is asked to bind
         * it again, and if that does not do it, the component is switched off and on,
         * which makes the system look at it afresh. Where the listener is connected, or
         * the access has not been given, this does nothing.
         */
        fun ensureBound(context: Context) {
            if (current != null || rebinding) return
            if (!NotificationManagerCompat.getEnabledListenerPackages(context)
                    .contains(context.packageName)
            ) {
                return
            }
            rebinding = true
            // What was done, never what a notification said.
            Log.i(TAG, "access is on and the listener is not connected: asking Android to bind it")
            requestRebindSafely(context)
            main.postDelayed({
                rebinding = false
                if (current == null) {
                    Log.i(TAG, "still not connected: switching the component off and on")
                    val component = ComponentName(context, NavListenerService::class.java)
                    val packages = context.packageManager
                    packages.setComponentEnabledSetting(
                        component,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                    packages.setComponentEnabledSetting(
                        component,
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                }
            }, REBIND_WAIT_MS)
        }

        private fun requestRebindSafely(context: Context) {
            try {
                requestRebind(ComponentName(context, NavListenerService::class.java))
            } catch (e: RuntimeException) {
                // Not allowed or not possible just now: the system's own binding is all there is.
            }
        }

        private const val REBIND_WAIT_MS = 4000L
        private const val TAG = "TapeDashNav"
    }
}
