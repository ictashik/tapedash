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
import android.widget.RemoteViews

/**
 * **A stand-in for Google Maps' navigation notification. Debug builds only.**
 *
 * It lets the whole path (listener, capture, and later the channel, parser and HUD)
 * run on an emulator, a phone on the desk or a test, without Google Maps. It is
 * shaped after what GMapsParser's notes say Maps' notification holds (a custom
 * layout with views named nav_title, nav_description, nav_time and
 * nav_notification_icon). It proves TapeDash's machinery; it proves nothing about
 * Google's format. Only a capture of the real thing does (docs/NAV.md, N1/N2).
 *
 * Drive it with adb (tool/nav_spike.sh standin):
 *
 *     adb shell am broadcast -n io.github.ictashik.tapedash/.NavStandInReceiver \
 *         --es title "300 m" --es instruction "Turn left onto MG Road" \
 *         --es time "12 min · 5.2 km · 3:45 pm" --es arrow left
 *
 * `--ez remove true` takes the notification away, as Maps does when navigation ends.
 * On Android 13 and later the app needs the notification permission:
 * `adb shell pm grant io.github.ictashik.tapedash android.permission.POST_NOTIFICATIONS`.
 */
class NavStandInReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (intent.getBooleanExtra("remove", false)) {
            manager.cancel(NOTIFICATION_ID)
            return
        }
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Navigation stand-in", NotificationManager.IMPORTANCE_LOW),
            )
        }

        val views = RemoteViews(context.packageName, R.layout.nav_stand_in)
        views.setTextViewText(R.id.nav_title, intent.getStringExtra("title") ?: "300 m")
        views.setTextViewText(R.id.nav_description, intent.getStringExtra("instruction") ?: "Turn left onto MG Road")
        views.setTextViewText(R.id.nav_time, intent.getStringExtra("time") ?: "12 min · 5.2 km · 3:45 pm")
        views.setImageViewBitmap(R.id.nav_notification_icon, arrow(intent.getStringExtra("arrow") ?: "left"))

        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setCategory(Notification.CATEGORY_NAVIGATION)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setStyle(Notification.DecoratedCustomViewStyle())
            .setCustomContentView(views)
        manager.notify(NOTIFICATION_ID, builder.build())
    }

    /** A white arrow on transparent, 96 px: the shape a turn icon would have. */
    private fun arrow(kind: String): Bitmap {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = 12f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val path = Path()
        when (kind) {
            "right" -> {
                path.moveTo(30f, 84f); path.lineTo(30f, 44f); path.lineTo(70f, 44f)
                path.moveTo(54f, 28f); path.lineTo(70f, 44f); path.lineTo(54f, 60f)
            }
            "straight" -> {
                path.moveTo(48f, 86f); path.lineTo(48f, 14f)
                path.moveTo(26f, 36f); path.lineTo(48f, 14f); path.lineTo(70f, 36f)
            }
            "uturn" -> {
                path.moveTo(66f, 84f); path.lineTo(66f, 36f); path.quadTo(66f, 14f, 48f, 14f)
                path.quadTo(30f, 14f, 30f, 36f); path.lineTo(30f, 56f)
                path.moveTo(14f, 42f); path.lineTo(30f, 58f); path.lineTo(46f, 42f)
            }
            else -> {
                path.moveTo(66f, 84f); path.lineTo(66f, 44f); path.lineTo(26f, 44f)
                path.moveTo(42f, 28f); path.lineTo(26f, 44f); path.lineTo(42f, 60f)
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
