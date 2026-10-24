package io.github.ictashik.tapedash

import android.app.Notification
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable

/**
 * Reads the fields of Google Maps' navigation notification that the HUD shows
 * (docs/NAV.md): the title, the text, the sub text, the short critical text, the
 * progress and its maximum, the template, and the manoeuvre's picture as a mask.
 *
 * Only called with a notification that has passed NavSources' filter, and only
 * while the app is listening (NavBridge). The result is the wire form of
 * lib/nav/nav_notification.dart; the names and types have to match it.
 */
object NavReader {
    /** Larger than any arrow Maps draws (126 px): a picture past this is not one. */
    private const val MAX_SIDE = 512

    fun read(context: Context, n: Notification): Map<String, Any?> {
        val e = n.extras
        return mapOf(
            "title" to e.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            "text" to e.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            "subText" to e.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString(),
            // Android 16's own field; absent before it.
            "shortCriticalText" to e.getCharSequence("android.shortCriticalText")?.toString(),
            "progress" to if (e.containsKey(Notification.EXTRA_PROGRESS)) e.getInt(Notification.EXTRA_PROGRESS) else null,
            "progressMax" to if (e.containsKey(Notification.EXTRA_PROGRESS_MAX)) e.getInt(Notification.EXTRA_PROGRESS_MAX) else null,
            "template" to e.getCharSequence(Notification.EXTRA_TEMPLATE)?.toString(),
            "arrow" to arrow(context, n),
        )
    }

    /** The large icon's coverage, row by row: the arrow is white on transparent. */
    private fun arrow(context: Context, n: Notification): Map<String, Any?>? {
        val icon = n.getLargeIcon() ?: return null
        val drawable = try {
            icon.loadDrawable(context)
        } catch (e: RuntimeException) {
            null
        } ?: return null

        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else return null
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else return null
        if (width > MAX_SIDE || height > MAX_SIDE) return null

        var bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val drawn = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, width, height)
            drawable.draw(Canvas(drawn))
            drawn
        }
        // A hardware bitmap cannot be read pixel by pixel.
        if (bitmap.config == Bitmap.Config.HARDWARE) {
            bitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false) ?: return null
        }

        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
        val alpha = ByteArray(w * h)
        var hash = -0x7ee3623b // FNV-1a, 32 bit
        for (i in pixels.indices) {
            val a = pixels[i] ushr 24
            alpha[i] = a.toByte()
            hash = (hash xor a) * 0x01000193
        }
        return mapOf(
            "id" to "%08x".format(hash),
            "width" to w,
            "height" to h,
            "alpha" to alpha,
        )
    }
}
