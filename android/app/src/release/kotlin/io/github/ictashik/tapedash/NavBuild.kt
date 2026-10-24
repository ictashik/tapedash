package io.github.ictashik.tapedash

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger

/**
 * What a release (and profile) build adds to the navigation listener: nothing.
 * The debug build's NavBuild adds a capture tool and TapeDash's own package, for
 * testing on an emulator; neither is compiled into this kind of build
 * (CLAUDE.md 4, "Navigation notification"). tool/check_offline.sh holds this file
 * to that.
 */
object NavBuild {
    fun extraPackages(context: Context): Set<String> = emptySet()

    fun tap(context: Context): NavTap? = null

    fun attach(context: Context, messenger: BinaryMessenger) {}

    fun detach() {}
}
