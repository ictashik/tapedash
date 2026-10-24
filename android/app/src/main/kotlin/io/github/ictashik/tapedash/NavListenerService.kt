package io.github.ictashik.tapedash

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

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
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn != null) posted(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (!NavSources.isAllowed(sbn.packageName, allowed)) return
        tap?.removed(sbn)
        NavBridge.removed()
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
    }
}
