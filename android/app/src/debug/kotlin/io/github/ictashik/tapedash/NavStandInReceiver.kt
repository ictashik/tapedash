package io.github.ictashik.tapedash

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Build
import android.os.Bundle

/**
 * **A stand-in for Google Maps' navigation notification. Debug builds only.**
 *
 * It posts what a capture of Google Maps 25.33 showed Maps posts (docs/NAV.md): a
 * standard notification with the distance and instruction in the title, or the
 * distance in the title and the street in the text, the time and distance left or
 * the ETA in the sub text, the route's progress and length in metres, and the
 * manoeuvre as a white arrow in the large icon. It lets the whole path (listener,
 * channel, parser and HUD) run on an emulator without Google Maps, in step with a
 * simulated drive (`tool/sim_server.dart --nav-adb`).
 *
 * It proves TapeDash's machinery. It proves nothing about Google's format beyond
 * what that one capture showed; only a capture of the real thing does.
 *
 * Every extra is optional, and one that is absent is not set. Strings:
 * `title`, `text`, `sub`, `short` (the short critical text); ints: `progress`,
 * `max`; `arrow` is left, right, straight, uturn or none. `--ez remove true` takes
 * the notification away, as Maps does when navigation ends. `--ei id N` posts (or
 * removes) a notification of that number, so that two can be up at once, and
 * `--es category none` leaves out the navigation category, to be one of Maps' other
 * notifications (a traffic alert) that the HUD must not take for a turn.
 *
 *     adb shell am broadcast -n io.github.ictashik.tapedash/.NavStandInReceiver \
 *         --es title '650 m · Turn right onto Mission Rd' --es short '650 m' \
 *         --es sub 'Arrive 9:25 PM' --ei progress 171 --ei max 6605 --es arrow right
 *
 * On Android 13 and later the app needs the notification permission:
 * `adb shell pm grant io.github.ictashik.tapedash android.permission.POST_NOTIFICATIONS`.
 */
class NavStandInReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val id = intent.getIntExtra("id", NOTIFICATION_ID)
        if (intent.getBooleanExtra("remove", false)) {
            manager.cancel(id)
            return
        }
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Navigation stand-in", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        if (intent.getStringExtra("category") != "none") {
            builder.setCategory(Notification.CATEGORY_NAVIGATION)
        }

        intent.getStringExtra("title")?.let { builder.setContentTitle(it) }
        intent.getStringExtra("text")?.let { builder.setContentText(it) }
        intent.getStringExtra("sub")?.let { builder.setSubText(it) }
        if (intent.hasExtra("max")) {
            builder.setProgress(intent.getIntExtra("max", 0), intent.getIntExtra("progress", 0), false)
        }
        // Android 16's own field, which older builders have no setter for.
        intent.getStringExtra("short")?.let {
            builder.addExtras(Bundle().apply { putCharSequence("android.shortCriticalText", it) })
        }
        val arrow = intent.getStringExtra("arrow") ?: "none"
        if (arrow != "none") builder.setLargeIcon(arrow(arrow))
        manager.notify(id, builder.build())
    }

    /** A white arrow on transparent, 126 px as Maps' are: the shape a turn icon has. */
    private fun arrow(kind: String): Bitmap {
        val size = 126
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = 14f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val s = size / 100f
        val path = Path()
        when (kind) {
            "right" -> {
                path.moveTo(30 * s, 90 * s); path.lineTo(30 * s, 50 * s); path.lineTo(72 * s, 50 * s)
                path.moveTo(55 * s, 30 * s); path.lineTo(74 * s, 50 * s); path.lineTo(55 * s, 70 * s)
            }
            "straight" -> {
                path.moveTo(50 * s, 92 * s); path.lineTo(50 * s, 20 * s)
                path.moveTo(27 * s, 42 * s); path.lineTo(50 * s, 17 * s); path.lineTo(73 * s, 42 * s)
            }
            "uturn" -> {
                path.moveTo(70 * s, 92 * s); path.lineTo(70 * s, 40 * s); path.quadTo(70 * s, 18 * s, 50 * s, 18 * s)
                path.quadTo(30 * s, 18 * s, 30 * s, 40 * s); path.lineTo(30 * s, 64 * s)
                path.moveTo(17 * s, 50 * s); path.lineTo(30 * s, 68 * s); path.lineTo(43 * s, 50 * s)
            }
            else -> {
                path.moveTo(70 * s, 90 * s); path.lineTo(70 * s, 50 * s); path.lineTo(28 * s, 50 * s)
                path.moveTo(45 * s, 30 * s); path.lineTo(26 * s, 50 * s); path.lineTo(45 * s, 70 * s)
            }
        }
        canvas.drawPath(path, paint)
        return bitmap
    }

    private companion object {
        const val CHANNEL = "nav_stand_in"
        const val NOTIFICATION_ID = 4711
    }
}
