package io.github.ictashik.tapedash

import android.app.Notification
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
 * **Only Google Maps' navigation notification is a turn.** Maps also posts others
 * (a traffic alert, a request to rate a visit), and a title and a time in one of
 * those would read as a route. A notification whose category is not navigation is
 * left alone, and a removal ends the navigation only if it is the removal of the
 * notification being followed.
 *
 * Only called with a notification that has passed NavSources' filter.
 */
object NavBridge {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: ((Map<String, Any?>) -> Unit)? = null

    /** The navigation as last sent, or null when there is none. */
    private var last: Map<String, Any?>? = null

    /** The key of the navigation notification being followed. */
    private var followed: String? = null

    /**
     * A debug build's way of saying what the bridge did with a notification: that it
     * was passed on, or left alone and why. Never what it said. A release build has
     * none.
     */
    @Volatile
    var note: ((String) -> Unit)? = null

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
        followed = null
    }

    val listening: Boolean get() = sink != null

    fun posted(context: Context, sbn: StatusBarNotification) {
        if (sink == null) {
            note?.invoke("bridge: not listening")
            return
        }
        val notification = sbn.notification
        if (notification.category != Notification.CATEGORY_NAVIGATION) {
            note?.invoke("bridge: left alone, category ${notification.category}")
            return
        }
        followed = sbn.key
        // One notification that cannot be read (a field a phone's Android lacks, a picture
        // that will not load) is left out, and never takes the app down.
        val event = try {
            HashMap(NavReader.read(context, notification))
        } catch (e: Exception) {
            note?.invoke("bridge: could not read it, ${e.javaClass.simpleName}")
            return
        } catch (e: LinkageError) {
            note?.invoke("bridge: could not read it, ${e.javaClass.simpleName}")
            return
        }
        event["event"] = "posted"
        note?.invoke("bridge: sent a navigation notification")
        deliver(event)
    }

    fun removed(sbn: StatusBarNotification) {
        if (sink == null) return
        // Another of Maps' notifications going away is not the end of the route.
        if (sbn.key != followed) {
            note?.invoke("bridge: another notification went away")
            return
        }
        followed = null
        note?.invoke("bridge: the navigation notification went away")
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
