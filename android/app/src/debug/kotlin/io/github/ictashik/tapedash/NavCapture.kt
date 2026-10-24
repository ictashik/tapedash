package io.github.ictashik.tapedash

import android.app.Notification
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.StatusBarNotification
import android.text.Spanned
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.RemoteViews
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * The capture tool of docs/NAV.md (N1). **Compiled into debug builds only.**
 *
 * It writes down what a navigation app's notification holds, so that the parser is
 * built from what Google Maps really posts and not from another project's notes:
 * every `extras` key, the actions, and the RemoteViews trees (the app's own custom
 * views, and the standard layouts Android rebuilds from the extras), with each
 * view's class, id name, text and image. Each image is saved as a PNG, once.
 *
 * Output, in the app's external files folder (adb reaches it; tool/nav_spike.sh
 * pulls it):
 *
 *     navspike/nav.jsonl     one JSON object a line
 *     navspike/icons/NAME.png   every distinct image, named by its pixels
 *
 * It holds street names and places. It is for the human to pull into
 * recordings/private/ (git-ignored) and is never uploaded or committed.
 *
 * Only called with a notification that has passed NavSources' filter.
 */
class NavCapture(private val context: Context) : NavTap {
    private val dir = File(context.getExternalFilesDir(null), "navspike")
    private val iconDir = File(dir, "icons")
    private val log = File(dir, "nav.jsonl")
    private var records = 0
    private var posts = 0
    private var bytes = log.length()
    private var capped = false

    override fun event(name: String) {
        append(JSONObject().put("t", now()).put("event", name))
    }

    override fun posted(sbn: StatusBarNotification) {
        // The first few and then every FULL_EVERY'th get the whole view trees. The
        // ones between hold the texts only, which is what changes from second to
        // second and shows how often Maps updates.
        val full = posts < FULL_FIRST || posts % FULL_EVERY == 0
        posts++
        val o = header("posted", sbn)
        try {
            o.put("notification", describe(sbn.notification, full))
        } catch (e: Throwable) {
            o.put("describeError", e.toString())
        }
        append(o)
    }

    override fun removed(sbn: StatusBarNotification) {
        append(header("removed", sbn))
    }

    private fun header(event: String, sbn: StatusBarNotification): JSONObject =
        JSONObject()
            .put("t", now())
            .put("event", event)
            .put("package", sbn.packageName)
            .put("id", sbn.id)
            .put("tag", sbn.tag ?: JSONObject.NULL)
            .put("key", sbn.key)
            .put("postTime", sbn.postTime)
            .put("ongoing", sbn.isOngoing)

    private fun now() = System.currentTimeMillis()

    // ---- the notification ----------------------------------------------------

    private fun describe(n: Notification, full: Boolean): JSONObject {
        val o = JSONObject()
        o.put("flags", n.flags)
        o.put("category", n.category ?: JSONObject.NULL)
        o.put("visibility", n.visibility)
        o.put("color", n.color)
        o.put("number", n.number)
        o.put("group", n.group ?: JSONObject.NULL)
        o.put("tickerText", n.tickerText?.toString() ?: JSONObject.NULL)
        if (Build.VERSION.SDK_INT >= 26) o.put("channelId", n.channelId ?: JSONObject.NULL)
        n.getLargeIcon()?.let { o.put("largeIcon", describeIcon(it)) }
        n.smallIcon?.let { o.put("smallIcon", describeIcon(it)) }
        o.put("extras", describeBundle(n.extras, 0))

        val actions = JSONArray()
        n.actions?.forEach { actions.put(it.title?.toString() ?: JSONObject.NULL) }
        o.put("actions", actions)

        // The texts of every view, flattened, whichever way the app made them.
        val texts = JSONArray()
        if (full) {
            val views = JSONObject()
            views.put("contentView", describeViews(n.contentView))
            views.put("bigContentView", describeViews(n.bigContentView))
            views.put("headsUpContentView", describeViews(n.headsUpContentView))
            try {
                val builder = Notification.Builder.recoverBuilder(context, n)
                views.put("recoveredContent", describeViews(builder.createContentView()))
                views.put("recoveredBig", describeViews(builder.createBigContentView()))
                views.put("recoveredHeadsUp", describeViews(builder.createHeadsUpContentView()))
            } catch (e: Throwable) {
                views.put("recoverError", e.toString())
            }
            o.put("views", views)
        } else {
            collectTexts(n.extras, texts)
            o.put("texts", texts)
        }
        return o
    }

    private fun collectTexts(b: Bundle?, out: JSONArray) {
        if (b == null) return
        try {
            for (key in b.keySet()) {
                val v = b.get(key)
                if (v is CharSequence) out.put(JSONObject().put(key, v.toString()))
            }
        } catch (e: Throwable) {
            out.put("error: $e")
        }
    }

    // ---- extras ----------------------------------------------------------------

    private fun describeBundle(b: Bundle?, depth: Int): JSONObject {
        val o = JSONObject()
        if (b == null) return o
        try {
            for (key in b.keySet()) {
                o.put(key, describeValue(b.get(key), depth))
            }
        } catch (e: Throwable) {
            o.put("_error", e.toString())
        }
        return o
    }

    private fun describeValue(v: Any?, depth: Int): Any {
        return when (v) {
            null -> JSONObject.NULL
            is Spanned -> JSONObject()
                .put("type", "Spanned")
                .put("text", v.toString())
                .put("spans", JSONArray().also { spans ->
                    for (s in v.getSpans(0, v.length, Any::class.java)) {
                        spans.put(
                            JSONObject()
                                .put("class", s.javaClass.name)
                                .put("start", v.getSpanStart(s))
                                .put("end", v.getSpanEnd(s)),
                        )
                    }
                })
            is CharSequence -> JSONObject().put("type", "CharSequence").put("text", v.toString())
            is Boolean, is Int, is Long, is Double, is Float, is Short, is Byte ->
                JSONObject().put("type", v.javaClass.simpleName).put("value", v)
            is Bitmap -> JSONObject().put("type", "Bitmap").put("image", saveBitmap(v))
            is Icon -> describeIcon(v).put("type", "Icon")
            is Bundle ->
                if (depth > 4) JSONObject().put("type", "Bundle").put("truncated", true)
                else JSONObject().put("type", "Bundle").put("values", describeBundle(v, depth + 1))
            is Array<*> -> JSONObject()
                .put("type", "Array")
                .put("items", JSONArray().also { a -> v.take(MAX_ITEMS).forEach { a.put(describeValue(it, depth + 1)) } })
            is IntArray -> JSONObject().put("type", "IntArray").put("value", v.take(MAX_ITEMS).toString())
            is Parcelable -> JSONObject()
                .put("type", v.javaClass.name)
                .put("toString", v.toString().take(400))
            else -> JSONObject().put("type", v.javaClass.name).put("toString", v.toString().take(400))
        }
    }

    private fun describeIcon(icon: Icon): JSONObject {
        val o = JSONObject().put("toString", icon.toString())
        try {
            val image = saveDrawable(icon.loadDrawable(context))
            if (image != null) o.put("image", image)
        } catch (e: Throwable) {
            o.put("loadError", e.toString())
        }
        return o
    }

    // ---- remote views ----------------------------------------------------------

    private fun describeViews(rv: RemoteViews?): Any {
        if (rv == null) return JSONObject.NULL
        val o = JSONObject()
        o.put("package", rv.getPackage() ?: JSONObject.NULL)
        o.put("layoutId", rv.layoutId)
        try {
            val view = rv.apply(context, FrameLayout(context))
            o.put("tree", describeView(view, 0))
        } catch (e: Throwable) {
            // Often the finding itself: a package the app can't see, a missing
            // resource.
            o.put("applyError", e.toString())
        }
        return o
    }

    private fun describeView(v: View, depth: Int): JSONObject {
        val o = JSONObject()
        o.put("class", v.javaClass.name)
        o.put("id", idName(v))
        o.put(
            "visibility",
            when (v.visibility) {
                View.VISIBLE -> "visible"
                View.INVISIBLE -> "invisible"
                else -> "gone"
            },
        )
        v.contentDescription?.let { o.put("contentDescription", it.toString()) }
        if (v is TextView) {
            o.put("text", v.text?.toString() ?: JSONObject.NULL)
            val spanned = v.text as? Spanned
            if (spanned != null) {
                val spans = JSONArray()
                for (s in spanned.getSpans(0, spanned.length, Any::class.java)) {
                    spans.put(s.javaClass.simpleName)
                }
                if (spans.length() > 0) o.put("spans", spans)
            }
        }
        if (v is ImageView) {
            saveDrawable(v.drawable)?.let { o.put("image", it) }
        }
        if (v is ProgressBar) {
            o.put("progress", v.progress).put("max", v.max).put("indeterminate", v.isIndeterminate)
        }
        if (v is ViewGroup && depth < MAX_DEPTH) {
            val children = JSONArray()
            for (i in 0 until v.childCount) children.put(describeView(v.getChildAt(i), depth + 1))
            o.put("children", children)
        }
        return o
    }

    private fun idName(v: View): Any =
        if (v.id == View.NO_ID) {
            JSONObject.NULL
        } else {
            try {
                v.resources.getResourceEntryName(v.id)
            } catch (e: Throwable) {
                "0x" + Integer.toHexString(v.id)
            }
        }

    // ---- images ----------------------------------------------------------------

    private fun saveDrawable(d: Drawable?): JSONObject? {
        if (d == null) return null
        if (d is BitmapDrawable && d.bitmap != null) return saveBitmap(d.bitmap)
        val w = if (d.intrinsicWidth > 0) d.intrinsicWidth else DEFAULT_ICON
        val h = if (d.intrinsicHeight > 0) d.intrinsicHeight else DEFAULT_ICON
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, w, h)
        d.draw(Canvas(bitmap))
        return saveBitmap(bitmap).put("drawable", d.javaClass.simpleName)
    }

    /** Saves [source] once as a PNG named by its pixels; says how it is made. */
    private fun saveBitmap(source: Bitmap): JSONObject {
        // (Bitmap.Config.HARDWARE is Android 8's: not to be named on Android 7.)
        val bitmap = if (Build.VERSION.SDK_INT >= 26 && source.config == Bitmap.Config.HARDWARE) {
            source.copy(Bitmap.Config.ARGB_8888, false)
        } else {
            source
        }
        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)

        val digest = MessageDigest.getInstance("SHA-1")
        var opaque = 0
        var visible = 0
        val colours = HashSet<Int>()
        for (p in pixels) {
            digest.update(byteArrayOf((p ushr 24).toByte(), (p ushr 16).toByte(), (p ushr 8).toByte(), p.toByte()))
            val alpha = p ushr 24
            if (alpha > 0) visible++
            if (alpha == 255) opaque++
            if (alpha > 0 && colours.size < 64) colours.add(p and 0xFFFFFF)
        }
        val hex = digest.digest().take(5).joinToString("") { "%02x".format(it) }
        val name = "icon-$hex-${w}x$h.png"
        iconDir.mkdirs()
        val file = File(iconDir, name)
        if (!file.exists()) {
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        return JSONObject()
            .put("file", "icons/$name")
            .put("width", w)
            .put("height", h)
            // A mask is white (or one colour) on transparent: the pixels that show
            // are all one colour. An image has many.
            .put("visiblePixels", visible)
            .put("opaquePixels", opaque)
            .put("distinctColours", if (colours.size >= 64) "64+" else colours.size.toString())
    }

    // ---- the file --------------------------------------------------------------

    private fun append(o: JSONObject) {
        if (capped) return
        try {
            dir.mkdirs()
            if (bytes > MAX_BYTES) {
                capped = true
                log.appendText(JSONObject().put("t", now()).put("event", "capped at $MAX_BYTES bytes").toString() + "\n")
                return
            }
            val line = o.toString() + "\n"
            log.appendText(line)
            bytes += line.length
            records++
        } catch (e: Throwable) {
            // A full disk or a folder adb removed: the capture stops quietly.
            capped = true
        }
    }

    private companion object {
        const val FULL_FIRST = 30
        const val FULL_EVERY = 20
        const val MAX_BYTES = 6L * 1024 * 1024
        const val MAX_DEPTH = 14
        const val MAX_ITEMS = 24
        const val DEFAULT_ICON = 96
    }
}
