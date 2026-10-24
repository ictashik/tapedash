package io.github.ictashik.tapedash

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.service.notification.StatusBarNotification

/**
 * Carries what NavListenerService sees to Dart, and only while Dart is listening.
 *
 * **Nothing is read unless the app has asked.** With the navigation switch off in
 * Garage, Dart does not listen, [sink] is null, and a Maps notification is not so
 * much as opened: [posted] returns before it touches the notification. (The access
 * Android grants is broader than the switch; the switch is what decides whether
 * TapeDash uses it.)
 *
 * Nothing is kept beyond the last event, in memory, so that a listener that
 * arrives later is told where the navigation is. It is never written anywhere
 * (CLAUDE.md 4, "Navigation notification").
 *
 * Only called with a notification that has passed NavSources' filter.
 */
object NavBridge {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: ((Map<String, Any?>) -> Unit)? = null

    /** The navigation as last sent, or null when there is none. */
    private var last: Map<String, Any?>? = null

    /** Dart is listening: send events to [send], starting with where things are. */
    fun attach(send: (Map<String, Any?>) -> Unit) {
        sink = send
        NavListenerService.current?.redeliver()
        last?.let(send)
    }

    /** Dart has stopped listening. */
    fun detach() {
        sink = null
        last = null
    }

    val listening: Boolean get() = sink != null

    fun posted(context: Context, sbn: StatusBarNotification) {
        if (sink == null) return
        val event = HashMap(NavReader.read(context, sbn.notification))
        event["event"] = "posted"
        deliver(event)
    }

    fun removed() {
        if (sink == null) return
        deliver(mapOf("event" to "removed"))
    }

    /** Android's access was granted or taken away. */
    fun link(connected: Boolean) {
        if (sink == null) return
        deliver(mapOf("event" to if (connected) "connected" else "disconnected"))
    }

    private fun deliver(event: Map<String, Any?>) {
        last = if (event["event"] == "posted") event else null
        main.post { sink?.invoke(event) }
    }
}
