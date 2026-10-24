package io.github.ictashik.tapedash

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * What the exchange file (docs/EXCHANGE.md) needs from Android that Dart cannot do:
 *
 * - **The launch's request**, from adb: `am start -n <package>/.MainActivity --es
 *   tapedash.exchange export` (or `import`, with `--es tapedash.scopes a,b` and
 *   `--ez tapedash.apply_profile true`). It is read from the intent and held until
 *   Dart takes it, once.
 * - **The file picker** (`ACTION_OPEN_DOCUMENT`): the person picks a file and the
 *   app is given that one file and no storage permission. It is copied into the
 *   app's cache for Dart to read.
 * - **The share sheet** (`ACTION_SEND`) for an export, through the same
 *   FileProvider as Year on Tape's picture (a copy in the cache, never the app's
 *   private files). Nothing is sent by this app; what the person picks in the
 *   sheet is theirs to choose (CLAUDE.md 1).
 *
 * A watch has neither picker nor share sheet, and says so in `capabilities`, so
 * the app uses the folder.
 *
 * This is the Android side of lib/platform/exchange_host.dart. The channel name and
 * arguments have to match it. **Unverified on a device** (CLAUDE.md 11).
 */
class ExchangeChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val methods = MethodChannel(messenger, "tapedash/exchange")
    private var request: Map<String, Any?>? = null
    private var pendingPick: MethodChannel.Result? = null

    init {
        methods.setMethodCallHandler(this)
        readRequest(activity.intent)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        pendingPick?.success(null)
        pendingPick = null
    }

    /** Reads the request an intent carries, if it carries one. */
    fun readRequest(intent: Intent?) {
        val operation = intent?.getStringExtra(EXTRA_OPERATION) ?: return
        request = mapOf(
            "operation" to operation,
            "scopes" to intent.getStringExtra(EXTRA_SCOPES),
            "applyProfile" to intent.getBooleanExtra(EXTRA_APPLY_PROFILE, false),
        )
        // Taken once: a rotation or a relaunch of the same intent does not repeat it.
        intent.removeExtra(EXTRA_OPERATION)
        // If Dart is already running it is told (a cold start finds the request when
        // it asks, since nothing listens yet).
        methods.invokeMethod("requestArrived", null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takeRequest" -> {
                val taken = request
                request = null
                result.success(taken)
            }

            "capabilities" -> result.success(
                mapOf(
                    "canPick" to canResolve(pickIntent()),
                    "canShare" to canResolve(
                        Intent(Intent.ACTION_SEND).setType(MIME),
                    ),
                ),
            )

            "pickFile" -> pick(result)

            "shareFile" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("bad_args", "path is required", null)
                    return
                }
                result.success(share(File(path)))
            }

            else -> result.notImplemented()
        }
    }

    private fun canResolve(intent: Intent): Boolean =
        intent.resolveActivity(activity.packageManager) != null

    private fun pickIntent(): Intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = "*/*"
    }

    private fun pick(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.success(null)
            return
        }
        try {
            pendingPick = result
            activity.startActivityForResult(pickIntent(), PICK_REQUEST)
        } catch (e: ActivityNotFoundException) {
            pendingPick = null
            result.success(null)
        }
    }

    /** Called by MainActivity with the picker's answer. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_REQUEST) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        result.success(copyToCache(uri))
    }

    private fun copyToCache(uri: Uri): String? {
        return try {
            val dir = File(activity.cacheDir, PICKED_DIR).apply { mkdirs() }
            dir.listFiles()?.forEach { it.delete() }
            val name = displayName(uri)?.replace(Regex("[^A-Za-z0-9._-]"), "_") ?: "picked.tdx"
            val out = File(dir, name)
            activity.contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { input.copyTo(it) }
            } ?: return null
            out.absolutePath
        } catch (e: java.io.IOException) {
            null
        } catch (e: SecurityException) {
            null
        }
    }

    private fun displayName(uri: Uri): String? {
        activity.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (column >= 0 && cursor.moveToFirst()) return cursor.getString(column)
        }
        return null
    }

    private fun share(file: File): Boolean {
        return try {
            if (!file.isFile) return false
            val dir = File(activity.cacheDir, SHARED_DIR).apply { mkdirs() }
            // One export at a time: the last is of no use once there is a new one.
            dir.listFiles()?.forEach { it.delete() }
            val copy = File(dir, file.name)
            file.copyTo(copy, overwrite = true)
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.share",
                copy,
            )
            val send = Intent(Intent.ACTION_SEND).apply {
                type = MIME
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
        const val EXTRA_OPERATION = "tapedash.exchange"
        const val EXTRA_SCOPES = "tapedash.scopes"
        const val EXTRA_APPLY_PROFILE = "tapedash.apply_profile"
        const val PICK_REQUEST = 0x7D01

        /** An exchange file is text, or gzip; the picker and the sheet need one type. */
        const val MIME = "application/octet-stream"

        /** Folders of the cache, the second named in res/xml/share_paths.xml. */
        const val PICKED_DIR = "exchange_in"
        const val SHARED_DIR = "exchange"
    }
}
