package com.naviwealth.naviwealth

/**
 * Thin Kotlin handle for the native sherpa-onnx streaming C API.
 *
 * The class deliberately exposes only semantic text updates to its caller.
 * AudioRecord's PCM stays between Kotlin and JNI/native code and never enters
 * Dart or a Flutter channel.
 */
internal class NativeSherpaStreamingRecognizer private constructor(
    modelDirectory: String,
) {
    private var handle: Long
    private var segmentFinished = false

    init {
        System.loadLibrary("naviwealth_speech")
        handle = nativeCreate(modelDirectory)
        if (handle == 0L) {
            throw IllegalStateException("Unable to create native Zipformer recognizer")
        }
    }

    data class Update(
        val text: String,
        val isFinal: Boolean,
    )

    fun acceptPcm16(source: ByteArray, length: Int): Update? {
        val currentHandle = handle
        if (currentHandle == 0L || length <= 0) return null
        if (segmentFinished) {
            nativeReset(currentHandle)
            segmentFinished = false
        }
        val changedText = nativeAcceptPcm16(currentHandle, source, length)
        val isFinal = nativeIsEndpoint(currentHandle)
        if (changedText == null && !isFinal) return null
        val text = changedText ?: nativeCurrentText(currentHandle).orEmpty()
        if (text.isEmpty() && !isFinal) return null
        return Update(text = text, isFinal = isFinal)
    }

    fun finishSegment(): String? {
        val currentHandle = handle
        if (currentHandle == 0L || segmentFinished) return null
        val text = nativeFinish(currentHandle)?.takeIf { it.isNotEmpty() }
        segmentFinished = true
        return text
    }

    fun reset() {
        val currentHandle = handle
        if (currentHandle != 0L) {
            nativeReset(currentHandle)
            segmentFinished = false
        }
    }

    fun close() {
        val currentHandle = handle
        if (currentHandle == 0L) return
        handle = 0L
        nativeDestroy(currentHandle)
    }

    private external fun nativeCreate(modelDirectory: String): Long

    private external fun nativeDestroy(handle: Long)

    private external fun nativeAcceptPcm16(
        handle: Long,
        pcm16: ByteArray,
        length: Int,
    ): String?

    private external fun nativeIsEndpoint(handle: Long): Boolean

    private external fun nativeCurrentText(handle: Long): String?

    private external fun nativeFinish(handle: Long): String?

    private external fun nativeReset(handle: Long)

    companion object {
        fun create(modelDirectory: String): NativeSherpaStreamingRecognizer =
            NativeSherpaStreamingRecognizer(modelDirectory)
    }
}
