package com.naviwealth.naviwealth

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.media.audiofx.AudioEffect
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import kotlin.math.max

/**
 * Android-owned audio capture pipeline for the local native ASR/VAD backend.
 *
 * This is intentionally separate from [AndroidSpeechBridge]. Android's
 * SpeechRecognizer owns its own AudioRecord, so platform recognition continues
 * to use that service. This bridge is the native hot path for Sherpa/native
 * models: AudioRecord -> voice processing effects -> bounded ring buffer.
 * PCM never crosses a Flutter channel; only capability, lifecycle, semantic
 * transcript events, and aggregate buffer metrics are emitted.
 */
internal class AndroidAudioCaptureBridge(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "com.naviwealth/audio_capture_android"
        const val EVENT_CHANNEL = "com.naviwealth/audio_capture_android/events"

        private const val RECORD_AUDIO_REQUEST_CODE = 7382
        private const val SAMPLE_RATE_HZ = 16_000
        private const val CHANNEL_COUNT = 1
        private const val FRAME_BYTES = 640 // 20 ms of mono PCM16 at 16 kHz.
        private const val RING_BUFFER_DURATION_SECONDS = 2
        private const val MAX_BUFFERED_EVENTS = 32

        private const val AVAILABILITY_READY = "ready"
        private const val AVAILABILITY_PERMISSION_DENIED = "permission_denied"
        private const val AVAILABILITY_UNSUPPORTED = "unsupported"
    }

    private val context: Context = activity.applicationContext
    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val leaseOwner = "audio_capture:${System.identityHashCode(this)}"
    private val bufferedEvents = ArrayDeque<Map<String, Any?>>()

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingStart: MethodChannel.Result? = null
    private var pendingModelDirectory: String? = null
    private var pendingStop: MethodChannel.Result? = null

    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private var active = false
    private var previousAudioMode: Int? = null
    private var ringBuffer = NativePcmRingBuffer(ringCapacityBytes())
    private var capturedBytes = 0L
    private var readErrors = 0
    private var vad: NativeEnergyVad? = null
    private var streamingRecognizer: NativeSherpaStreamingRecognizer? = null
    private var pendingSpeechStopped: SpeechStop? = null

    private var echoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var automaticGainControl: AutomaticGainControl? = null

    fun attach(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).also { it.setMethodCallHandler(this) }
        eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).also { it.setStreamHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(statusPayload())
            "start" -> start(result, call.arguments)
            "stop" -> stop(result)
            "cancel" -> cancel(result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        while (bufferedEvents.isNotEmpty()) {
            events.success(bufferedEvents.removeFirst())
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        if (active) finishCapture(cancelled = true, emitTerminalEvent = false)
    }

    private fun statusPayload(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return mapOf(
                "availability" to AVAILABILITY_UNSUPPORTED,
                "reason" to "Native audio capture requires Android API 26 or newer",
            )
        }
        if (!hasRecordAudioPermission()) {
            return mapOf(
                "availability" to AVAILABILITY_PERMISSION_DENIED,
                "reason" to "Microphone permission is required for native audio capture",
            )
        }
        val minimumBuffer = minimumBufferBytes()
        if (minimumBuffer <= 0) {
            return mapOf(
                "availability" to AVAILABILITY_UNSUPPORTED,
                "reason" to "The Android audio recorder is unavailable",
            )
        }
        return baseFormatPayload() + effectsPayload() + vadPayload()
    }

    private fun start(result: MethodChannel.Result, arguments: Any?) {
        if (active || pendingStart != null) {
            result.error(
                "session_busy",
                "Another native audio capture session is already active",
                null,
            )
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error(
                "runtime_unavailable",
                "Native audio capture requires Android API 26 or newer",
                null,
            )
            return
        }
        if (!hasRecordAudioPermission()) {
            pendingStart = result
            pendingModelDirectory = modelDirectoryFromArguments(arguments)
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                RECORD_AUDIO_REQUEST_CODE,
            )
            return
        }
        startCapture(result, modelDirectoryFromArguments(arguments))
    }

    private fun startCapture(result: MethodChannel.Result, modelDirectory: String?) {
        if (!AndroidMicrophoneLease.tryAcquire(leaseOwner)) {
            result.error(
                "session_busy",
                "Another native microphone pipeline is already active",
                null,
            )
            return
        }

        val minimumBuffer = minimumBufferBytes()
        if (minimumBuffer <= 0) {
            AndroidMicrophoneLease.release(leaseOwner)
            result.error(
                "recorder_unavailable",
                "The Android audio recorder is unavailable",
                null,
            )
            return
        }

        val bufferSize = max(minimumBuffer, FRAME_BYTES * 4)
        val recorder = try {
            AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE_HZ)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(bufferSize)
                .build()
        } catch (error: RuntimeException) {
            AndroidMicrophoneLease.release(leaseOwner)
            result.error(
                "recorder_unavailable",
                "Unable to create the Android audio recorder",
                error.message,
            )
            return
        }

        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            AndroidMicrophoneLease.release(leaseOwner)
            result.error(
                "recorder_unavailable",
                "The Android audio recorder failed to initialize",
                null,
            )
            return
        }

        audioRecord = recorder
        ringBuffer.clear()
        capturedBytes = 0L
        readErrors = 0
        pendingSpeechStopped = null
        streamingRecognizer = try {
            modelDirectory?.let { NativeSherpaStreamingRecognizer.create(it) }
        } catch (error: RuntimeException) {
            failNativeRecognizerStart(result, recorder, error)
            return
        } catch (error: LinkageError) {
            failNativeRecognizerStart(result, recorder, error)
            return
        }
        vad = NativeEnergyVad(
            onSpeechStarted = { startedAtMs ->
                emit(
                    mapOf(
                        "type" to "speech_started",
                        "started_at_ms" to startedAtMs,
                        "vad_mode" to NativeEnergyVad.MODE,
                    ),
                )
            },
            onSpeechStopped = { stoppedAtMs, durationMs ->
                pendingSpeechStopped = SpeechStop(
                    stoppedAtMs = stoppedAtMs,
                    durationMs = durationMs,
                )
            },
        )
        previousAudioMode = audioManager.mode
        try {
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            configureEffects(recorder.audioSessionId)
            recorder.startRecording()
            if (recorder.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                throw IllegalStateException("AudioRecord did not enter recording state")
            }
            active = true
            emit(startedEvent(bufferSize))
            captureThread = Thread(
                { captureLoop(recorder) },
                "NaviWealthAudioCapture",
            ).also { it.start() }
            result.success(null)
        } catch (error: RuntimeException) {
            abortStart(recorder)
            result.error(
                "recorder_unavailable",
                error.message ?: "Unable to start the Android audio recorder",
                null,
            )
        }
    }

    private fun stop(result: MethodChannel.Result) {
        if (!active) {
            result.success(null)
            return
        }
        if (pendingStop != null) {
            result.error(
                "session_busy",
                "Native audio capture is already stopping",
                null,
            )
            return
        }
        pendingStop = result
        finishCapture(cancelled = false)
    }

    private fun cancel(result: MethodChannel.Result) {
        if (!active) {
            result.success(null)
            return
        }
        result.success(null)
        finishCapture(cancelled = true, emitTerminalEvent = false)
    }

    private fun captureLoop(recorder: AudioRecord) {
        val frame = ByteArray(FRAME_BYTES)
        while (active && !Thread.currentThread().isInterrupted) {
            val read = recorder.read(frame, 0, frame.size, AudioRecord.READ_BLOCKING)
            when {
                read > 0 -> {
                    ringBuffer.write(frame, length = read)
                    capturedBytes += read.toLong()
                    try {
                        // Feed the complete native frame to ASR before the VAD
                        // callback can finalize a segment. This keeps the
                        // trailing frame in the stream being finalized.
                        val update = streamingRecognizer?.acceptPcm16(frame, read)
                        if (update?.isFinal == true) streamingRecognizer?.reset()
                        vad?.acceptPcm16(
                            source = frame,
                            offset = 0,
                            length = read,
                            timestampMs = System.currentTimeMillis(),
                        )
                        val speechStopped = pendingSpeechStopped
                        pendingSpeechStopped = null
                        if (speechStopped != null) {
                            // A model endpoint on this frame already owns the
                            // final event. Otherwise flush the accumulated
                            // native stream exactly once before the boundary.
                            if (update?.isFinal == true) {
                                emitStreamingTranscript(update)
                            } else {
                                finishStreamingSegment()
                            }
                            emitSpeechStopped(speechStopped)
                        } else {
                            update?.let { emitStreamingTranscript(it) }
                        }
                    } catch (error: RuntimeException) {
                        readErrors++
                        mainHandler.post {
                            if (active) {
                                finishCapture(
                                    cancelled = true,
                                    terminalError =
                                        "runtime_unavailable" to
                                            (error.message
                                                ?: "Native Zipformer recognition failed"),
                                )
                            }
                        }
                        return
                    }
                }
                read == AudioRecord.ERROR_DEAD_OBJECT -> {
                    readErrors++
                    mainHandler.post {
                        if (active) {
                            finishCapture(
                                cancelled = true,
                                terminalError =
                                    "recorder_unavailable" to
                                        "Android audio recorder was disconnected",
                            )
                        }
                    }
                    return
                }
                read < 0 -> {
                    readErrors++
                    mainHandler.post {
                        if (active) {
                            finishCapture(
                                cancelled = true,
                                terminalError =
                                    "recorder_unavailable" to
                                        "Android audio recorder returned error $read",
                            )
                        }
                    }
                    return
                }
            }
        }
    }

    private fun finishCapture(
        cancelled: Boolean,
        terminalError: Pair<String, String>? = null,
        emitTerminalEvent: Boolean = true,
    ) {
        if (!active && audioRecord == null) return
        active = false
        val recorder = audioRecord
        audioRecord = null
        try {
            recorder?.stop()
        } catch (_: RuntimeException) {
            // The recorder may already be dead; release still happens below.
        }
        val thread = captureThread
        captureThread = null
        if (thread != null && thread !== Thread.currentThread()) {
            try {
                thread.join(500)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
        val shouldFinalize = emitTerminalEvent && !cancelled && terminalError == null
        val currentVad = vad
        vad = null
        if (shouldFinalize) {
            currentVad?.finish(System.currentTimeMillis())
        } else {
            currentVad?.reset()
        }
        val speechStopped = pendingSpeechStopped
        pendingSpeechStopped = null
        val currentRecognizer = streamingRecognizer
        streamingRecognizer = null
        if (shouldFinalize) {
            if (speechStopped != null) {
                finishStreamingSegment(currentRecognizer)
                emitSpeechStopped(speechStopped)
            } else {
                finishStreamingSegment(currentRecognizer)
            }
        }
        currentRecognizer?.close()
        try {
            recorder?.release()
        } finally {
            releaseEffects()
            restoreAudioMode()
            AndroidMicrophoneLease.release(leaseOwner)
        }

        terminalError?.let { (code, message) ->
            if (emitTerminalEvent) {
                emit(mapOf("type" to "error", "code" to code, "message" to message))
            }
        }
        if (emitTerminalEvent) emit(stoppedEvent(cancelled))
        pendingStop?.let { stopResult ->
            pendingStop = null
            if (terminalError == null) {
                stopResult.success(null)
            } else {
                stopResult.error(terminalError.first, terminalError.second, null)
            }
        }
    }

    private fun abortStart(recorder: AudioRecord) {
        active = false
        audioRecord = null
        vad?.reset()
        vad = null
        pendingSpeechStopped = null
        streamingRecognizer?.close()
        streamingRecognizer = null
        try {
            recorder.stop()
        } catch (_: RuntimeException) {
            // Best-effort cleanup for a recorder that failed during startup.
        }
        recorder.release()
        captureThread?.interrupt()
        captureThread = null
        releaseEffects()
        restoreAudioMode()
        AndroidMicrophoneLease.release(leaseOwner)
    }

    private fun failNativeRecognizerStart(
        result: MethodChannel.Result,
        recorder: AudioRecord,
        error: Throwable,
    ) {
        audioRecord = null
        recorder.release()
        AndroidMicrophoneLease.release(leaseOwner)
        result.error(
            "runtime_unavailable",
            error.message ?: "Unable to create the native Zipformer recognizer",
            null,
        )
    }

    private fun configureEffects(audioSessionId: Int) {
        echoCanceler = createEffect(
            available = { AcousticEchoCanceler.isAvailable() },
            create = { AcousticEchoCanceler.create(audioSessionId) },
        ) as? AcousticEchoCanceler
        noiseSuppressor = createEffect(
            available = { NoiseSuppressor.isAvailable() },
            create = { NoiseSuppressor.create(audioSessionId) },
        ) as? NoiseSuppressor
        automaticGainControl = createEffect(
            available = { AutomaticGainControl.isAvailable() },
            create = { AutomaticGainControl.create(audioSessionId) },
        ) as? AutomaticGainControl
    }

    private fun createEffect(
        available: () -> Boolean,
        create: () -> AudioEffect?,
    ): AudioEffect? {
        if (!runCatching { available() }.getOrDefault(false)) return null
        val effect = runCatching { create() }.getOrNull() ?: return null
        return try {
            effect.enabled = true
            effect
        } catch (_: RuntimeException) {
            effect.release()
            null
        }
    }

    private fun releaseEffects() {
        listOf(echoCanceler, noiseSuppressor, automaticGainControl).forEach { effect ->
            try {
                effect?.release()
            } catch (_: RuntimeException) {
                // Effects are best-effort platform enhancements.
            }
        }
        echoCanceler = null
        noiseSuppressor = null
        automaticGainControl = null
    }

    private fun minimumBufferBytes(): Int = AudioRecord.getMinBufferSize(
        SAMPLE_RATE_HZ,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT,
    )

    private fun ringCapacityBytes(): Int = SAMPLE_RATE_HZ *
        CHANNEL_COUNT *
        2 *
        RING_BUFFER_DURATION_SECONDS

    private fun baseFormatPayload(): Map<String, Any?> = mapOf(
        "availability" to AVAILABILITY_READY,
        "sample_rate_hz" to SAMPLE_RATE_HZ,
        "channel_count" to CHANNEL_COUNT,
        "encoding" to "pcm16le",
        "ring_capacity_bytes" to ringCapacityBytes(),
    )

    private fun vadPayload(): Map<String, Any?> = mapOf(
        "vad_available" to true,
        "vad_mode" to NativeEnergyVad.MODE,
        "vad_frame_duration_ms" to NativeEnergyVad.FRAME_DURATION_MS,
        "vad_min_speech_frames" to NativeEnergyVad.MIN_SPEECH_FRAMES,
        "vad_min_silence_frames" to NativeEnergyVad.MIN_SILENCE_FRAMES,
    )

    private fun effectsPayload(): Map<String, Any?> = mapOf(
        "aec_available" to runCatching { AcousticEchoCanceler.isAvailable() }
            .getOrDefault(false),
        "ns_available" to runCatching { NoiseSuppressor.isAvailable() }
            .getOrDefault(false),
        "agc_available" to runCatching { AutomaticGainControl.isAvailable() }
            .getOrDefault(false),
    )

    private fun startedEvent(bufferSize: Int): Map<String, Any?> =
        baseFormatPayload() +
            effectsPayload() +
            vadPayload() +
            mapOf(
                "type" to "capture_started",
                "buffer_size_bytes" to bufferSize,
                "aec_enabled" to (echoCanceler != null),
                "ns_enabled" to (noiseSuppressor != null),
                "agc_enabled" to (automaticGainControl != null),
                "asr_mode" to if (streamingRecognizer != null) {
                    "sherpa_zipformer"
                } else {
                    "none"
                },
            )

    private fun stoppedEvent(cancelled: Boolean): Map<String, Any?> {
        val snapshot = ringBuffer.snapshot()
        return mapOf(
            "type" to "capture_stopped",
            "cancelled" to cancelled,
            "captured_bytes" to capturedBytes,
            "buffered_bytes" to snapshot.bufferedBytes,
            "dropped_bytes" to snapshot.droppedBytes,
            "read_errors" to readErrors,
            "vad_mode" to NativeEnergyVad.MODE,
        )
    }

    private fun hasRecordAudioPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED

    private fun modelDirectoryFromArguments(arguments: Any?): String? {
        val map = arguments as? Map<*, *> ?: return null
        return (map["model_directory"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun emitStreamingTranscript(update: NativeSherpaStreamingRecognizer.Update) {
        if (update.text.isEmpty()) return
        emit(
            mapOf(
                "type" to "transcript",
                "text" to update.text,
                "is_final" to update.isFinal,
                "recognizer" to "sherpa_zipformer",
            ),
        )
    }

    private fun emitSpeechStopped(stop: SpeechStop) {
        emit(
            mapOf(
                "type" to "speech_stopped",
                "stopped_at_ms" to stop.stoppedAtMs,
                "duration_ms" to stop.durationMs,
                "vad_mode" to NativeEnergyVad.MODE,
            ),
        )
    }

    private fun finishStreamingSegment(
        recognizer: NativeSherpaStreamingRecognizer? = streamingRecognizer,
    ) {
        val text = try {
            recognizer?.finishSegment()
        } catch (_: RuntimeException) {
            null
        }
        if (text.isNullOrEmpty()) return
        emit(
            mapOf(
                "type" to "transcript",
                "text" to text,
                "is_final" to true,
                "recognizer" to "sherpa_zipformer",
            ),
        )
        recognizer?.reset()
    }

    private data class SpeechStop(
        val stoppedAtMs: Long,
        val durationMs: Long,
    )

    private fun restoreAudioMode() {
        val mode = previousAudioMode ?: return
        previousAudioMode = null
        try {
            audioManager.mode = mode
        } catch (_: RuntimeException) {
            // The Activity may already be detached.
        }
    }

    private fun emit(event: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            emitOnMain(event)
        } else {
            mainHandler.post { emitOnMain(event) }
        }
    }

    private fun emitOnMain(event: Map<String, Any?>) {
        val sink = eventSink
        if (sink != null) {
            sink.success(event)
            return
        }
        if (bufferedEvents.size == MAX_BUFFERED_EVENTS) bufferedEvents.removeFirst()
        bufferedEvents.addLast(event)
    }

    fun onHostStopped() {
        if (active) finishCapture(cancelled = true, emitTerminalEvent = false)
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != RECORD_AUDIO_REQUEST_CODE) return false
        val result = pendingStart ?: return true
        val modelDirectory = pendingModelDirectory
        pendingStart = null
        pendingModelDirectory = null
        pendingSpeechStopped = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startCapture(result, modelDirectory)
        } else {
            result.error(
                "permission_denied",
                "Microphone permission was denied",
                null,
            )
        }
        return true
    }

    fun dispose() {
        pendingStart?.error(
            "runtime_unavailable",
            "Android audio capture host was destroyed",
            null,
        )
        pendingStart = null
        pendingModelDirectory = null
        if (active) finishCapture(cancelled = true, emitTerminalEvent = false)
        mainHandler.removeCallbacksAndMessages(null)
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        eventSink = null
        bufferedEvents.clear()
        ringBuffer.clear()
    }
}
