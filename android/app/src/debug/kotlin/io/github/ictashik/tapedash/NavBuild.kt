package io.github.ictashik.tapedash

import android.content.Context

/**
 * What a debug build adds to the navigation listener (docs/NAV.md, N1): TapeDash's
 * own package, so that the stand-in (NavStandInReceiver) can be seen on an
 * emulator, and the capture tool, which writes what Google Maps' notification
 * holds to the app's external files folder for the human to pull with adb.
 *
 * A release and a profile build have a NavBuild that adds nothing.
 */
object NavBuild {
    fun extraPackages(context: Context): Set<String> = setOf(context.packageName)

    fun tap(context: Context): NavTap? = NavCapture(context)
}
