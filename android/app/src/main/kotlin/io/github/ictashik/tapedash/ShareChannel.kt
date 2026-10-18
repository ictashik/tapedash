package io.github.ictashik.tapedash

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hands a picture the app has drawn to Android's share sheet (Year on Tape). The
 * picture is written to the app's own cache and handed over through a
 * FileProvider, so no storage permission is needed, and nothing is sent by this
 * app: what the person picks in the sheet is theirs to choose (CLAUDE.md 1).
 *
 * This is the Android side of lib/platform/image_sharer.dart. The channel name and
 * arguments have to match it.
 */
class ShareChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val methods = MethodChannel(messenger, "tapedash/share")

    init {
        methods.setMethodCallHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareImage" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name")
                if (bytes == null || name == null) {
                    result.error("bad_args", "bytes and name are required", null)
                    return
                }
                result.success(share(bytes, name))
            }
            else -> result.notImplemented()
        }
    }

    private fun share(bytes: ByteArray, name: String): Boolean {
        return try {
            val dir = File(activity.cacheDir, SHARED_DIR).apply { mkdirs() }
            // One picture at a time: the last is of no use once there is a new one.
            dir.listFiles()?.forEach { it.delete() }
            val safe = name.replace(Regex("[^A-Za-z0-9_-]"), "_")
            val file = File(dir, "$safe.png")
            file.writeBytes(bytes)
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.share",
                file,
            )
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(Intent.createChooser(send, null))
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: java.io.IOException) {
            false
        }
    }

    private companion object {
        /** A folder of the cache, named in res/xml/share_paths.xml. */
        const val SHARED_DIR = "shared"
    }
}
