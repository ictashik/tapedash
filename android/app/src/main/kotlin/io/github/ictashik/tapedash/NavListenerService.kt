package io.github.ictashik.tapedash

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Reads the navigation notification of a navigation app (Google Maps) so the HUD
 * can show the next turn (docs/NAV.md). Google Maps talks to the internet; this
 * does not, and it sends Maps nothing (CLAUDE.md 1 and 4).
 *
 * It does nothing until the person grants TapeDash Notification access in Android's
 * settings (or an adb command does, for testing).
 *
 * **The package filter is the first thing that happens to a notification.** Nothing
 * of one from another package is read, kept or logged. tool/check_offline.sh fails
 * if the notification is touched before NavSources.isAllowed is asked.
 */
class NavListenerService : NotificationListenerService() {
    private var allowed: Set<String> = NavSources.RELEASE_PACKAGES
    private var tap: NavTap? = null

    override fun onCreate() {
        super.onCreate()
        allowed = NavSources.allowed(NavBuild.extraPackages(this))
        tap = NavBuild.tap(this)
    }

    override fun onListenerConnected() {
        tap?.event("connected")
        // A navigation already under way when the access was granted.
        try {
            activeNotifications?.forEach { posted(it) }
        } catch (e: SecurityException) {
            tap?.event("active notifications refused")
        }
    }

    override fun onListenerDisconnected() {
        tap?.event("disconnected")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn != null) posted(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (!NavSources.isAllowed(sbn.packageName, allowed)) return
        tap?.removed(sbn)
    }

    private fun posted(sbn: StatusBarNotification) {
        // The filter. Everything below may read the notification; nothing above does.
        if (!NavSources.isAllowed(sbn.packageName, allowed)) return
        tap?.posted(sbn)
    }
}
