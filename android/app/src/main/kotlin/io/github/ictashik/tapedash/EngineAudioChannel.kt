package io.github.ictashik.tapedash

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Process
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * The phone's audio output for the engine sound: 16-bit mono PCM from Dart, played
 * on an [AudioTrack] by a thread of its own. No plugin and no library: the platform's
 * own API (CLAUDE.md 5).
 *
 * This is the Android side of lib/platform/engine_audio.dart. The channel name and
 * arguments have to match it.
 *
 * It is made to be quiet in the right places:
 *  - It asks for no audio focus, so that music carries on under the engine.
 *  - With `requireExternal` it plays only where there is car audio (Bluetooth A2DP,
 *    a wire, USB) and never on the phone's speaker: it does not start without one,
 *    and when the output changes from one to the speaker (the Bluetooth link drops:
 *    ACTION_AUDIO_BECOMING_NOISY), it stops at once.
 *  - It stops when the activity does: there is no foreground service, so it is a
 *    sound of the screen that is showing, and never one that goes on behind a
 *    screen that is not.
 * Once stopped for either of those it answers every write with -1 (lost) until it
 * is started again, which is how Dart finds out.
 *
 * Channel calls arrive on the main thread and are quick: a write copies the samples
 * into a queue and answers. The [AudioTrack] is written by [writer], which blocks
 * in the write.
 */
class EngineAudioChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val methods = MethodChannel(messenger, "tapedash/engine_audio")
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var track: AudioTrack? = null
    private var writer: Thread? = null
    private val queue = LinkedBlockingQueue<ShortArray>()
    private val framesIn = AtomicLong(0)

    @Volatile private var open = false
    @Volatile private var lost = false
    private var requireExternal = true
    private var writes = 0
    private var receiverRegistered = false

    // The output changing from car audio to the phone's speaker.
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY && requireExternal) {
                lost = true
                shutDown()
            }
        }
    }

    init {
        methods.setMethodCallHandler(this)
    }

    /** Stops everything, when the Flutter engine goes away. */
    fun dispose() {
        methods.setMethodCallHandler(null)
        shutDown()
    }

    /** The activity is no longer on screen: the sound goes with it. */
    fun onAppStopped() {
        if (open) {
            lost = true
            shutDown()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)
            "write" -> write(call, result)
            "underruns" -> result.success(track?.underrunCount ?: 0)
            "stop" -> {
                shutDown()
                lost = false
                result.success(null)
            }
            "externalOutput" -> result.success(externalOutputPresent())
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        shutDown()
        lost = false
        val sampleRate = call.argument<Int>("sampleRate") ?: 32000
        requireExternal = call.argument<Boolean>("requireExternal") ?: true
        if (requireExternal && !externalOutputPresent()) {
            result.success("noExternalOutput")
            return
        }
        try {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val minimum = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            // A quarter of a second, or what the device needs if that is more.
            val bytes = maxOf(minimum, sampleRate / 4 * 2)
            val t = AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(format)
                .setBufferSizeInBytes(bytes)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            track = t
            framesIn.set(0)
            queue.clear()
            writes = 0
            open = true
            t.play()
            context.registerReceiver(noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
            receiverRegistered = true
            writer = Thread({ writeLoop(t) }, "tapedash-engine-audio").also {
                it.isDaemon = true
                it.start()
            }
            result.success("started")
        } catch (e: Exception) {
            shutDown()
            result.success("failed")
        }
    }

    private fun writeLoop(t: AudioTrack) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        try {
            while (open) {
                val block = queue.poll(200, TimeUnit.MILLISECONDS) ?: continue
                if (!open) break
                t.write(block, 0, block.size)
            }
        } catch (e: InterruptedException) {
            // Shut down.
        } catch (e: IllegalStateException) {
            // The track was released under it.
        }
    }

    private fun write(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("pcm")
        val t = track
        if (bytes == null) {
            result.error("bad_arguments", "'pcm' must be bytes", null)
            return
        }
        if (!open || lost || t == null) {
            result.success(-1)
            return
        }
        // The output may have changed without the broadcast: look about once a second.
        if (requireExternal && ++writes % 50 == 0 && !externalOutputPresent()) {
            lost = true
            shutDown()
            result.success(-1)
            return
        }
        val shorts = ShortArray(bytes.size / 2)
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shorts)
        // Dart keeps about a tenth of a second ahead: a longer queue is a stall, and
        // what is behind it is stale, so it is dropped rather than played late.
        if (queue.size > 40) {
            var dropped = 0L
            while (queue.size > 8) {
                dropped += queue.poll()?.size ?: 0
            }
            framesIn.addAndGet(-dropped)
        }
        framesIn.addAndGet(shorts.size.toLong())
        queue.offer(shorts)
        val played = t.playbackHeadPosition.toLong() and 0xFFFFFFFFL
        result.success(maxOf(0L, framesIn.get() - played).toInt())
    }

    private fun shutDown() {
        val wasOpen = open
        open = false
        writer?.interrupt()
        writer = null
        queue.clear()
        track?.let {
            try {
                if (wasOpen) {
                    it.pause()
                    it.flush()
                }
            } catch (e: IllegalStateException) {
                // Already stopped.
            }
            it.release()
        }
        track = null
        if (receiverRegistered) {
            try {
                context.unregisterReceiver(noisy)
            } catch (e: IllegalArgumentException) {
                // Not registered.
            }
            receiverRegistered = false
        }
    }

    /** Whether there is car audio to play on: Bluetooth A2DP, a wire, USB. */
    private fun externalOutputPresent(): Boolean =
        audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in EXTERNAL_TYPES }

    private companion object {
        // AudioDeviceInfo types, as numbers where a constant needs a newer API than
        // minSdk 24: wired headset 3, wired headphones 4, line analog 5, line digital
        // 6, Bluetooth A2DP 8, USB device 11, aux line 19, USB headset 22, hearing aid
        // 23, BLE headset 26, BLE speaker 27.
        val EXTERNAL_TYPES = setOf(3, 4, 5, 6, 8, 11, 19, 22, 23, 26, 27)
    }
}
