package io.github.ictashik.tapedash

import android.service.notification.StatusBarNotification

/**
 * Something that is shown the notifications NavSources lets through. In a debug
 * build it is the capture tool (docs/NAV.md, N1); in a release build there is
 * none yet (NavBuild).
 *
 * Only called with a notification that has already passed the package filter.
 */
interface NavTap {
    /** The listener connected or disconnected, or another event with no notification. */
    fun event(name: String)

    fun posted(sbn: StatusBarNotification)

    fun removed(sbn: StatusBarNotification)
}
