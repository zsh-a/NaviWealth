package com.naviwealth.naviwealth

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/** Bounded local video decoding. Images are returned in memory; no audio or network I/O. */
internal class AndroidVideoFrameBridge : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    @Volatile private var disposed = false

    fun attach(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.naviwealth/video_frames")
            .also { it.setMethodCallHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "extract") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        if (path.isNullOrBlank() || !File(path).isAbsolute) {
            result.error("unreadable", "A local video file is required", null)
            return
        }
        worker.execute {
            val retriever = MediaMetadataRetriever()
            try {
                val file = File(path)
                require(file.isFile && file.length() > 0) { "unreadable" }
                require(file.length() <= 50L * 1024 * 1024) { "video_size" }
                retriever.setDataSource(file.canonicalPath)
                val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L
                require(duration > 0) { "unreadable" }
                require(duration <= 10_000L) { "video_duration" }
                val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                    ?.toIntOrNull() ?: 0
                val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                    ?.toIntOrNull() ?: 0
                require(width > 0 && height > 0 && width.toLong() * height <= 40_000_000L) {
                    "unreadable"
                }
                val scale = minOf(1.0, 1280.0 / max(width, height))
                val targetWidth = max(1, (width * scale).roundToInt())
                val targetHeight = max(1, (height * scale).roundToInt())
                val frames = mutableListOf<Map<String, Any>>()
                for (index in 0 until 8) {
                    if (disposed || Thread.currentThread().isInterrupted) break
                    val timeMs = duration * (index * 2 + 1) / 16
                    val original = if (Build.VERSION.SDK_INT >= 27) {
                        retriever.getScaledFrameAtTime(
                            timeMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST,
                            targetWidth, targetHeight,
                        )
                    } else {
                        retriever.getFrameAtTime(timeMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST)
                    } ?: continue
                    val bitmap = if (max(original.width, original.height) > 1280) {
                        val factor = 1280.0 / max(original.width, original.height)
                        Bitmap.createScaledBitmap(
                            original, max(1, (original.width * factor).roundToInt()),
                            max(1, (original.height * factor).roundToInt()), true,
                        )
                    } else original
                    try {
                        val bytes = ByteArrayOutputStream().use { stream ->
                            check(bitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream))
                            stream.toByteArray()
                        }
                        require(bytes.size <= 2 * 1024 * 1024) { "video_size" }
                        frames.add(mapOf("time_ms" to timeMs, "bytes" to bytes))
                    } finally {
                        if (bitmap !== original) bitmap.recycle()
                        original.recycle()
                    }
                }
                require(frames.isNotEmpty()) { "unreadable" }
                main.post {
                    if (!disposed) result.success(mapOf("duration_ms" to duration, "frames" to frames))
                }
            } catch (error: Exception) {
                val code = error.message.takeIf { it == "video_size" || it == "video_duration" }
                    ?: "unreadable"
                main.post { if (!disposed) result.error(code, "Unable to extract video frames", null) }
            } finally {
                retriever.release()
            }
        }
    }

    fun dispose() {
        disposed = true
        channel?.setMethodCallHandler(null)
        channel = null
        worker.shutdownNow()
    }
}
