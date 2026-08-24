package com.naviwealth.naviwealth

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import java.util.Locale

/**
 * Android semantic speech bridge.
 *
 * The platform recognizer owns microphone capture and recognition. The app
 * explicitly uses Android's API 31+ on-device recognizer and requests the
 * VOICE_COMMUNICATION input source so the platform can apply its voice
 * processing path. No PCM is copied through a Flutter channel.
 */
internal class AndroidSpeechBridge(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    RecognitionListener {

    companion object {
        const val METHOD_CHANNEL = "com.naviwealth/speech_android"
        const val EVENT_CHANNEL = "com.naviwealth/speech_android/events"

        private const val RECORD_AUDIO_REQUEST_CODE = 7381
        private const val MAX_BUFFERED_EVENTS = 64
    }

    private val context: Context = activity.applicationContext
    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val leaseOwner = "speech:${System.identityHashCode(this)}"

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private val bufferedEvents = ArrayDeque<Map<String, Any?>>()

    private var speechRecognizer: SpeechRecognizer? = null
    private var active = false
    private var pendingStart: MethodChannel.Result? = null
    private var pendingStop: MethodChannel.Result? = null
    private var previousAudioMode: Int? = null

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
            "start" -> start(result)
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
        // A detached event stream cannot deliver the terminal event. Cancel
        // native recognition so an Activity teardown never leaves the
        // microphone owned by a dead Dart session.
        if (active) cancelActive(emitTerminalEvent = false)
    }

    private fun statusPayload(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return mapOf(
                "availability" to "unsupported",
                "reason" to "Android on-device speech recognition requires API 31 or newer",
            )
        }
        if (!hasRecordAudioPermission()) {
            return mapOf(
                "availability" to "permission_denied",
                "reason" to "Microphone permission is required for speech input",
            )
        }
        if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            return mapOf(
                "availability" to "unsupported",
                "reason" to "No Android on-device speech recognition service is available",
            )
        }
        return mapOf("availability" to "ready")
    }

    private fun start(result: MethodChannel.Result) {
        if (active || pendingStart != null) {
            result.error(
                "session_busy",
                "Another speech recognition session is already active",
                null,
            )
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.error(
                "runtime_unavailable",
                "Android on-device speech recognition requires API 31 or newer",
                null,
            )
            return
        }
        if (!hasRecordAudioPermission()) {
            pendingStart = result
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                RECORD_AUDIO_REQUEST_CODE,
            )
            return
        }
        startRecognition(result)
    }

    private fun startRecognition(result: MethodChannel.Result) {
        if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            result.error(
                "runtime_unavailable",
                "No Android on-device speech recognition service is available",
                null,
            )
            return
        }

        if (!AndroidMicrophoneLease.tryAcquire(leaseOwner)) {
            result.error(
                "session_busy",
                "Another native microphone pipeline is already active",
                null,
            )
            return
        }

        val recognizer = try {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        } catch (error: RuntimeException) {
            AndroidMicrophoneLease.release(leaseOwner)
            result.error(
                "runtime_unavailable",
                "Unable to create Android on-device speech recognizer",
                error.message,
            )
            return
        }

        speechRecognizer = recognizer
        active = true
        previousAudioMode = audioManager.mode
        try {
            // MODE_IN_COMMUNICATION is the platform audio mode for simultaneous
            // capture/playback. The requested VOICE_COMMUNICATION source below
            // lets the recognition service select its system AEC/NS/AGC path.
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            recognizer.setRecognitionListener(this)
            recognizer.startListening(recognitionIntent())
            result.success(null)
        } catch (error: RuntimeException) {
            abortStart()
            result.error(
                "runtime_unavailable",
                error.message ?: "Unable to start Android speech recognition",
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
                "Speech recognition is already stopping",
                null,
            )
            return
        }
        pendingStop = result
        try {
            speechRecognizer?.stopListening()
        } catch (error: RuntimeException) {
            finishRecognition(
                cancelled = true,
                terminalError = "runtime_unavailable" to
                    (error.message ?: "Unable to stop Android speech recognition"),
            )
        }
    }

    private fun cancel(result: MethodChannel.Result) {
        if (!active) {
            result.success(null)
            return
        }
        result.success(null)
        cancelActive()
    }

    private fun cancelActive(emitTerminalEvent: Boolean = true) {
        if (!active) return
        val recognizer = speechRecognizer
        // Mark inactive before calling into the platform. Some recognition
        // services synchronously invoke onError from cancel().
        active = false
        speechRecognizer = null
        try {
            recognizer?.cancel()
        } catch (_: RuntimeException) {
            // The native resource is destroyed below even if cancel failed.
        } finally {
            recognizer?.destroy()
            restoreAudioMode()
            AndroidMicrophoneLease.release(leaseOwner)
            if (emitTerminalEvent) {
                emit(mapOf("type" to "ended", "cancelled" to true))
            }
            pendingStop?.success(null)
            pendingStop = null
        }
    }

    private fun abortStart() {
        active = false
        val recognizer = speechRecognizer
        speechRecognizer = null
        try {
            recognizer?.destroy()
        } catch (_: RuntimeException) {
            // Best-effort cleanup for a recognizer that failed during startup.
        }
        restoreAudioMode()
        AndroidMicrophoneLease.release(leaseOwner)
    }

    private fun finishRecognition(
        cancelled: Boolean,
        terminalError: Pair<String, String>? = null,
    ) {
        if (!active && speechRecognizer == null) return
        active = false
        val recognizer = speechRecognizer
        speechRecognizer = null
        try {
            recognizer?.destroy()
        } catch (_: RuntimeException) {
            // Resource cleanup remains best effort; the lease is released by
            // the terminal semantic event regardless.
        }
        restoreAudioMode()
        AndroidMicrophoneLease.release(leaseOwner)
        terminalError?.let { (code, message) ->
            emit(mapOf("type" to "error", "code" to code, "message" to message))
        }
        emit(mapOf("type" to "ended", "cancelled" to cancelled))
        val stop = pendingStop
        pendingStop = null
        if (stop != null) {
            if (terminalError == null) stop.success(null)
            else stop.error(terminalError.first, terminalError.second, null)
        }
    }

    private fun recognitionIntent(): Intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(
            RecognizerIntent.EXTRA_LANGUAGE_MODEL,
            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
        )
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        // Keep the Android capture path on the communication source. This is
        // the only supported way to ask a SpeechRecognizer service to use the
        // platform voice-processing route without copying PCM through Flutter.
        putExtra(
            RecognizerIntent.EXTRA_AUDIO_SOURCE,
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
        )
    }

    private fun hasRecordAudioPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED

    private fun restoreAudioMode() {
        val mode = previousAudioMode ?: return
        previousAudioMode = null
        try {
            audioManager.mode = mode
        } catch (_: RuntimeException) {
            // The Activity may already be detached. There is no safe retry
            // path after the process loses the audio service.
        }
    }

    private fun emit(event: Map<String, Any?>) {
        val sink = eventSink
        if (sink != null) {
            sink.success(event)
            return
        }
        if (bufferedEvents.size == MAX_BUFFERED_EVENTS) bufferedEvents.removeFirst()
        bufferedEvents.addLast(event)
    }

    override fun onReadyForSpeech(params: Bundle?) = Unit

    override fun onBeginningOfSpeech() {
        if (!active) return
        emit(
            mapOf(
                "type" to "speech_started",
                "started_at_ms" to System.currentTimeMillis(),
            ),
        )
    }

    override fun onRmsChanged(rmsdB: Float) = Unit

    override fun onBufferReceived(buffer: ByteArray?) = Unit

    override fun onEndOfSpeech() = Unit

    override fun onError(error: Int) {
        if (!active) return
        when (error) {
            SpeechRecognizer.ERROR_NO_MATCH,
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> finishRecognition(cancelled = false)
            else -> finishRecognition(
                cancelled = true,
                terminalError = errorCode(error),
            )
        }
    }

    override fun onResults(results: Bundle?) {
        if (!active) return
        emitTranscript(results, isFinal = true)
        finishRecognition(cancelled = false)
    }

    override fun onPartialResults(partialResults: Bundle?) {
        if (!active) return
        emitTranscript(partialResults, isFinal = false)
    }

    override fun onEvent(eventType: Int, params: Bundle?) = Unit

    private fun emitTranscript(bundle: Bundle?, isFinal: Boolean) {
        val text = bundle
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            ?.trim()
            ?: return
        if (text.isEmpty()) return
        emit(
            mapOf(
                "type" to "transcript",
                "text" to text,
                "is_final" to isFinal,
            ),
        )
    }

    private fun errorCode(error: Int): Pair<String, String> = when (error) {
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
            "permission_denied" to "Microphone permission was denied"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
            "session_busy" to "Android speech recognizer is busy"
        SpeechRecognizer.ERROR_AUDIO ->
            "recorder_unavailable" to "Android speech recognizer could not capture audio"
        else ->
            "runtime_unavailable" to "Android speech recognition failed (code $error)"
    }

    fun onHostStopped() {
        // Pending permission requests are left alive so Android can deliver a
        // deterministic result. Active capture, however, must never continue
        // while the app is backgrounded.
        if (active) cancelActive()
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != RECORD_AUDIO_REQUEST_CODE) return false
        val result = pendingStart ?: return true
        pendingStart = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startRecognition(result)
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
            "Android speech host was destroyed",
            null,
        )
        pendingStart = null
        if (active) cancelActive(emitTerminalEvent = false)
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        eventSink = null
        bufferedEvents.clear()
    }
}
