package io.github.ictashik.tapedash

/**
 * Whose notifications TapeDash may look at (CLAUDE.md 4, "Navigation notification").
 *
 * Android's Notification access shows an app every notification on the phone, so
 * the promise TapeDash makes is made here, and kept by tool/check_offline.sh: a
 * notification from any other package is dropped before a byte of it is read.
 */
object NavSources {
    /**
     * What a release build looks at: Google Maps, and nothing else.
     * tool/check_offline.sh fails if this is anything but that one package.
     */
    val RELEASE_PACKAGES: Set<String> = setOf("com.google.android.apps.maps")

    /** The release list plus what this kind of build adds (see NavBuild). */
    fun allowed(extra: Set<String>): Set<String> = RELEASE_PACKAGES + extra

    fun isAllowed(packageName: String?, allowed: Set<String>): Boolean =
        packageName != null && packageName in allowed
}
