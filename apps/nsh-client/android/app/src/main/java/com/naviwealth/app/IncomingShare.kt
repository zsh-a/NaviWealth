package com.naviwealth.app

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import com.longbridge.nsh.NshView
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Content another app shares to NaviWealth (`ACTION_SEND` / `ACTION_SEND_MULTIPLE`). Shared text and
 * up to four `content:` streams are copied off the main thread into the app-private [DIR] and announced
 * once as `share.received`; NSH keeps the event until the TSX entry listens. Rust validates, reads and
 * removes each copy. Nothing here parses, uploads or saves a record.
 */
internal class IncomingShare(private val activity: Activity, private val nsh: NshView) {
    companion object {
        /** Must match `FOLDER` in `src/data/incoming.rs`. */
        const val DIR = "naviwealth-incoming"
        private const val MAX_FILES = 4
        private const val MAX_BYTES = 25L * 1024 * 1024
        private const val MAX_TEXT = 4000
    }

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val folder = File(activity.filesDir, DIR)
    @Volatile private var destroyed = false

    init {
        // Copies an earlier process never handed over; queued before any new copy.
        worker.execute { folder.listFiles()?.forEach { it.delete() } }
    }

    fun receive(intent: Intent?) {
        val action = intent?.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.take(MAX_TEXT).orEmpty()
        val uris = streams(intent).filter(::acceptable).take(MAX_FILES)
        worker.execute {
            val files = uris.mapNotNull(::copy)
            main.post {
                if (!destroyed && (files.isNotEmpty() || text.isNotBlank())) {
                    nsh.send("share.received", mapOf("text" to text, "files" to files))
                }
            }
        }
    }

    fun destroy() {
        destroyed = true
        worker.shutdown()
    }

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri> =
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
            } else {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
            }
        } else {
            listOfNotNull(
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                },
            )
        }

    /** Only other apps' `content:` streams: never `file:` paths, never this app's own provider. */
    private fun acceptable(uri: Uri): Boolean =
        uri.scheme == ContentResolver.SCHEME_CONTENT && uri.authority?.startsWith(activity.packageName) != true

    private fun copy(uri: Uri): Map<String, String>? {
        val target = File(folder, UUID.randomUUID().toString())
        return try {
            folder.mkdirs()
            val resolver = activity.contentResolver
            val input = resolver.openInputStream(uri) ?: return null
            input.use { source ->
                target.outputStream().use { sink ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_BYTES) throw IllegalStateException("share_too_large")
                        sink.write(buffer, 0, read)
                    }
                }
            }
            mapOf("path" to target.absolutePath, "name" to displayName(uri).take(120), "mime" to (resolver.getType(uri) ?: ""))
        } catch (_: Exception) {
            target.delete()
            null
        }
    }

    private fun displayName(uri: Uri): String =
        try {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: uri.lastPathSegment.orEmpty()
        } catch (_: Exception) {
            ""
        }
}
