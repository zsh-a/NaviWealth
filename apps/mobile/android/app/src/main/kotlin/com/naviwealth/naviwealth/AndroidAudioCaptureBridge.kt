package com.naviwealth.naviwealth

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioFocusRequest
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
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

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
    private val modelExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "NaviWealthSpeechModel").apply { isDaemon = true }
    }
    private val leaseOwner = "audio_capture:${System.identityHashCode(this)}"
    private val bufferedEvents = ArrayDeque<Map<String, Any?>>()

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingStart: MethodChannel.Result? = null
    private var pendingModelDirectory: String? = null
    private var pendingCaptureStart: PendingCaptureStart? = null
    private var pendingModelPrepare: PendingModelPrepare? = null
    private var pendingStop: MethodChannel.Result? = null

    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    @Volatile
    private var active = false
    private var previousAudioMode: Int? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var audioFocusOwned = false
    private var ringBuffer = NativePcmRingBuffer(ringCapacityBytes())
    private var capturedBytes = 0L
    private var readErrors = 0
    private var vad: NativeEnergyVad? = null
    private var streamingRecognizer: NativeSherpaStreamingRecognizer? = null
    private var currentModelDirectory: String? = null
    private var cachedModelDirectory: String? = null
    private var cachedRecognizer: NativeSherpaStreamingRecognizer? = null
    private var pendingSpeechStopped: SpeechStop? = null
    private var modelPreparationToken = 0L
    private var startRequestedAtMs: Long? = null
    private var disposed = false

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
            "prepare" -> prepareModel(result, call.arguments)
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
        cancelPendingCaptureStart(
            "Android audio capture stream closed before recording started",
        )
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
        if (active || pendingStart != null || pendingCaptureStart != null ||
            pendingModelPrepare != null
        ) {
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

    /**
     * Loads the native recognizer without opening AudioRecord. This is used
     * while the chat surface is idle so the first microphone tap only pays for
     * recorder setup, not the 155 MB model load.
     */
    private fun prepareModel(result: MethodChannel.Result, arguments: Any?) {
        if (active || pendingStart != null || pendingCaptureStart != null ||
            pendingModelPrepare != null
        ) {
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
        val modelDirectory = modelDirectoryFromArguments(arguments)
        if (modelDirectory == null) {
            result.error(
                "runtime_unavailable",
                "A Zipformer model directory is required",
                null,
            )
            return
        }
        if (cachedRecognizer != null && cachedModelDirectory == modelDirectory) {
            result.success(null)
            return
        }

        cachedRecognizer?.let {
            try {
                it.close()
            } catch (_: RuntimeException) {
                // A stale cache must not prevent a fresh warmup attempt.
            }
        }
        cachedRecognizer = null
        cachedModelDirectory = null
        val token = ++modelPreparationToken
        pendingModelPrepare = PendingModelPrepare(
            token = token,
            result = result,
            modelDirectory = modelDirectory,
        )
        try {
            modelExecutor.execute {
                var recognizer: NativeSherpaStreamingRecognizer? = null
                var error: Throwable? = null
                try {
                    recognizer = NativeSherpaStreamingRecognizer.create(modelDirectory)
                } catch (failure: Throwable) {
                    error = failure
                }
                mainHandler.post {
                    onModelPrepared(token, recognizer, error)
                }
            }
        } catch (failure: RuntimeException) {
            pendingModelPrepare = null
            modelPreparationToken++
            result.error(
                "runtime_unavailable",
                failure.message ?: "Unable to prepare the native Zipformer recognizer",
                null,
            )
        }
    }

    private fun startCapture(result: MethodChannel.Result, modelDirectory: String?) {
        // A terminal event can be buffered when the previous Flutter listener
        // disappeared during Activity teardown. It belongs to that old
        // capture session and must never be replayed into the next one.
        bufferedEvents.clear()
        if (!AndroidMicrophoneLease.tryAcquire(leaseOwner)) {
            result.error(
                "session_busy",
                "Another native microphone pipeline is already active",
                null,
            )
            return
        }
        startRequestedAtMs = System.currentTimeMillis()

        val normalizedModelDirectory = modelDirectory?.trim()?.takeIf { it.isNotEmpty() }
        val cached = cachedRecognizer
        if (normalizedModelDirectory == null ||
            (cached != null && cachedModelDirectory == normalizedModelDirectory)
        ) {
            startCaptureWithRecognizer(
                result,
                normalizedModelDirectory,
                cached,
            )
            return
        }

        // Loading a 155 MB Zipformer model synchronously from the Flutter
        // method-channel callback blocks Android's main thread and prevents
        // the button's pending state from being painted. Keep the microphone
        // lease while the model is prepared, but do all JNI/model work on a
        // dedicated executor and resume the AudioRecord setup on main.
        val oldCached = cachedRecognizer
        try {
            oldCached?.close()
        } catch (_: RuntimeException) {
            // Replacing a stale cache must not prevent a fresh model attempt.
        }
        cachedRecognizer = null
        cachedModelDirectory = null
        val token = ++modelPreparationToken
        pendingCaptureStart = PendingCaptureStart(
            token = token,
            result = result,
            modelDirectory = normalizedModelDirectory,
        )
        try {
            modelExecutor.execute {
                var recognizer: NativeSherpaStreamingRecognizer? = null
                var error: Throwable? = null
                try {
                    recognizer = NativeSherpaStreamingRecognizer.create(
                        normalizedModelDirectory,
                    )
                } catch (failure: Throwable) {
                    error = failure
                }
                mainHandler.post {
                    onModelPrepared(token, recognizer, error)
                }
            }
        } catch (failure: RuntimeException) {
            pendingCaptureStart = null
            modelPreparationToken++
            AndroidMicrophoneLease.release(leaseOwner)
            startRequestedAtMs = null
            result.error(
                "runtime_unavailable",
                failure.message ?: "Unable to prepare the native Zipformer recognizer",
                null,
            )
        }
    }

    private fun onModelPrepared(
        token: Long,
        recognizer: NativeSherpaStreamingRecognizer?,
        error: Throwable?,
    ) {
        val pendingCapture = pendingCaptureStart
        val pendingPrepare = pendingModelPrepare
        if (disposed ||
            (pendingCapture == null && pendingPrepare == null) ||
            (pendingCapture != null && pendingCapture.token != token) ||
            (pendingPrepare != null && pendingPrepare.token != token)
        ) {
            recognizer?.close()
            return
        }
        if (pendingCapture != null) {
            pendingCaptureStart = null
            if (error != null || recognizer == null) {
                AndroidMicrophoneLease.release(leaseOwner)
                startRequestedAtMs = null
                pendingCapture.result.error(
                    "runtime_unavailable",
                    error?.message ?: "Unable to prepare the native Zipformer recognizer",
                    null,
                )
                return
            }

            cachedRecognizer = recognizer
            cachedModelDirectory = pendingCapture.modelDirectory
            startCaptureWithRecognizer(
                pendingCapture.result,
                pendingCapture.modelDirectory,
                recognizer,
            )
            return
        }

        pendingModelPrepare = null
        if (error != null || recognizer == null) {
            pendingPrepare!!.result.error(
                "runtime_unavailable",
                error?.message ?: "Unable to prepare the native Zipformer recognizer",
                null,
            )
            return
        }
        cachedRecognizer = recognizer
        cachedModelDirectory = pendingPrepare!!.modelDirectory
        pendingPrepare.result.success(null)
    }

    private fun startCaptureWithRecognizer(
        result: MethodChannel.Result,
        modelDirectory: String?,
        recognizer: NativeSherpaStreamingRecognizer?,
    ) {

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
        currentModelDirectory = modelDirectory
        streamingRecognizer = recognizer
        try {
            recognizer?.reset()
        } catch (_: RuntimeException) {
            // A cached recognizer can be discarded below if its native handle
            // is no longer usable; AudioRecord startup remains deterministic.
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
            if (!requestAudioFocus()) {
                throw IllegalStateException("Audio focus is unavailable")
            }
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
            startRequestedAtMs = null
        } catch (error: RuntimeException) {
            abortStart(recorder)
            startRequestedAtMs = null
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
        val pendingPrepare = pendingModelPrepare
        if (pendingPrepare != null) {
            pendingModelPrepare = null
            modelPreparationToken++
            pendingPrepare.result.error(
                "runtime_unavailable",
                "Native Zipformer preparation was cancelled",
                null,
            )
            result.success(null)
            return
        }
        val pendingPermission = this.pendingStart
        if (pendingPermission != null && pendingCaptureStart == null) {
            this.pendingStart = null
            pendingModelDirectory = null
            pendingPermission.error(
                "runtime_unavailable",
                "Android audio capture start was cancelled",
                null,
            )
            result.success(null)
            return
        }
        if (pendingCaptureStart != null) {
            cancelPendingCaptureStart(
                "Android audio capture start was cancelled",
            )
            result.success(null)
            return
        }
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
        val currentModelPath = this.currentModelDirectory
        this.currentModelDirectory = null
        if (shouldFinalize) {
            if (speechStopped != null) {
                finishStreamingSegment(currentRecognizer)
                emitSpeechStopped(speechStopped)
            } else {
                finishStreamingSegment(currentRecognizer)
            }
        }
        if (currentRecognizer != null &&
            currentModelPath != null &&
            terminalError == null &&
            !disposed
        ) {
            try {
                currentRecognizer.reset()
                cachedRecognizer = currentRecognizer
                cachedModelDirectory = currentModelPath
            } catch (_: RuntimeException) {
                currentRecognizer.close()
                cachedRecognizer = null
                cachedModelDirectory = null
            }
        } else {
            currentRecognizer?.close()
            if (cachedRecognizer === currentRecognizer) {
                cachedRecognizer = null
                cachedModelDirectory = null
            }
        }
        try {
            recorder?.release()
        } finally {
            releaseEffects()
            releaseAudioFocus()
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
        val currentRecognizer = streamingRecognizer
        streamingRecognizer = null
        val currentModelPath = this.currentModelDirectory
        this.currentModelDirectory = null
        if (currentRecognizer != null && currentModelPath != null && !disposed) {
            try {
                currentRecognizer.reset()
                cachedRecognizer = currentRecognizer
                cachedModelDirectory = currentModelPath
            } catch (_: RuntimeException) {
                currentRecognizer.close()
                cachedRecognizer = null
                cachedModelDirectory = null
            }
        } else {
            currentRecognizer?.close()
        }
        try {
            recorder.stop()
        } catch (_: RuntimeException) {
            // Best-effort cleanup for a recorder that failed during startup.
        }
        recorder.release()
        captureThread?.interrupt()
        captureThread = null
        releaseEffects()
        releaseAudioFocus()
        restoreAudioMode()
        AndroidMicrophoneLease.release(leaseOwner)
    }

    /**
     * Keeps the native full-duplex path and system TTS in one communication
     * audio session. External media is allowed to yield or duck, while a
     * genuine focus loss terminates capture through the same semantic error
     * path as every other native recorder failure.
     */
    private fun requestAudioFocus(): Boolean {
        if (audioFocusOwned) return true
        val request = AudioFocusRequest.Builder(
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
        )
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener { change ->
                if (change == AudioManager.AUDIOFOCUS_LOSS ||
                    change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
                ) {
                    mainHandler.post {
                        if (active) {
                            finishCapture(
                                cancelled = true,
                                terminalError =
                                    "runtime_unavailable" to
                                        "Audio focus was lost during speech capture",
                            )
                        }
                    }
                }
            }
            .build()
        audioFocusRequest = request
        audioFocusOwned = audioManager.requestAudioFocus(request) ==
            AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (!audioFocusOwned) audioFocusRequest = null
        return audioFocusOwned
    }

    private fun releaseAudioFocus() {
        val request = audioFocusRequest ?: return
        audioFocusRequest = null
        if (audioFocusOwned) {
            try {
                audioManager.abandonAudioFocusRequest(request)
            } catch (_: RuntimeException) {
                // The Activity may already be detached during teardown.
            }
        }
        audioFocusOwned = false
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
        "supports_barge_in" to true,
        "full_duplex" to true,
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
                "startup_duration_ms" to (
                    startRequestedAtMs?.let {
                        (System.currentTimeMillis() - it).coerceAtLeast(0L)
                    } ?: 0L
                ),
                "aec_enabled" to (echoCanceler != null),
                "ns_enabled" to (noiseSuppressor != null),
                "agc_enabled" to (automaticGainControl != null),
                "audio_focus_owned" to audioFocusOwned,
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
        if (disposed) return
        val sink = eventSink
        if (sink != null) {
            sink.success(event)
            return
        }
        if (bufferedEvents.size == MAX_BUFFERED_EVENTS) bufferedEvents.removeFirst()
        bufferedEvents.addLast(event)
    }

    fun onHostStopped() {
        // The Dart session must observe the terminal lifecycle event while the
        // Flutter engine is still attached. This prevents a backgrounded
        // Activity from leaving the UI in a listening state with a released
        // microphone lease.
        pendingStart?.error(
            "runtime_unavailable",
            "Android audio capture host stopped before recording started",
            null,
        )
        pendingStart = null
        pendingModelDirectory = null
        cancelPendingCaptureStart(
            "Android audio capture host stopped before recording started",
        )
        if (active) finishCapture(cancelled = true)
    }

    private fun cancelPendingCaptureStart(message: String) {
        val pending = pendingCaptureStart ?: return
        pendingCaptureStart = null
        modelPreparationToken++
        startRequestedAtMs = null
        AndroidMicrophoneLease.release(leaseOwner)
        pending.result.error("runtime_unavailable", message, null)
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
            startRequestedAtMs = null
            result.error(
                "permission_denied",
                "Microphone permission was denied",
                null,
            )
        }
        return true
    }

    fun dispose() {
        disposed = true
        pendingStart?.error(
            "runtime_unavailable",
            "Android audio capture host was destroyed",
            null,
        )
        pendingStart = null
        pendingModelDirectory = null
        cancelPendingCaptureStart("Android audio capture host was destroyed")
        pendingModelPrepare?.let { pending ->
            pendingModelPrepare = null
            modelPreparationToken++
            pending.result.error(
                "runtime_unavailable",
                "Android audio capture host was destroyed",
                null,
            )
        }
        if (active) finishCapture(cancelled = true, emitTerminalEvent = false)
        cachedRecognizer?.close()
        cachedRecognizer = null
        cachedModelDirectory = null
        modelExecutor.shutdownNow()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        eventSink = null
        bufferedEvents.clear()
        ringBuffer.clear()
    }

    private data class PendingCaptureStart(
        val token: Long,
        val result: MethodChannel.Result,
        val modelDirectory: String,
    )

    private data class PendingModelPrepare(
        val token: Long,
        val result: MethodChannel.Result,
        val modelDirectory: String,
    )
}
