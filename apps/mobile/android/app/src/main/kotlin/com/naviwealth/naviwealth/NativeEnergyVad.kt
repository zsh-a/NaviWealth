package com.naviwealth.naviwealth

import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Small native VAD gate for the AudioRecord hot path.
 *
 * This is deliberately a deterministic bootstrap implementation rather than
 * a claim that an energy gate is the final ASR-quality VAD. It keeps PCM on
 * the native thread, provides the semantic events needed by InteractionSession
 * and leaves the replacement seam small enough for a future native
 * Silero/Sherpa model.
 *
 * The gate uses hysteresis, an adaptive quiet-room floor, and minimum speech /
 * silence durations so a single noisy frame does not become a turn. It emits
 * no PCM, confidence, or audio-derived payload other than timestamps and
 * aggregate speech duration.
 */
internal class NativeEnergyVad(
    private val onSpeechStarted: (startedAtMs: Long) -> Unit,
    private val onSpeechStopped: (stoppedAtMs: Long, durationMs: Long) -> Unit,
) {
    companion object {
        const val MODE = "native_energy"
        const val FRAME_DURATION_MS = 20
        const val MIN_SPEECH_FRAMES = 2
        const val MIN_SILENCE_FRAMES = 20

        private const val FRAME_SAMPLES = 320
        private const val START_FLOOR_DB = -48.0
        private const val STOP_FLOOR_DB = -54.0
        private const val NOISE_MARGIN_DB = 10.0
        private const val SILENCE_MARGIN_DB = 4.0
        private const val INITIAL_NOISE_FLOOR_DB = -60.0
        private const val NOISE_FLOOR_ALPHA = 0.05
        private const val MIN_RMS = 0.00001
    }

    private var frameSampleCount = 0
    private var frameEnergy = 0.0
    private var pendingLowByte: Int? = null

    private var noiseFloorDb = INITIAL_NOISE_FLOOR_DB
    private var consecutiveSpeechFrames = 0
    private var consecutiveSilenceFrames = 0
    private var speaking = false
    private var speechStartedAtMs: Long? = null

    /**
     * Accepts little-endian PCM16. The input may be smaller than one VAD
     * frame; incomplete samples are held natively until the next read.
     */
    fun acceptPcm16(
        source: ByteArray,
        offset: Int,
        length: Int,
        timestampMs: Long,
    ) {
        require(offset >= 0 && length >= 0 && offset + length <= source.size) {
            "Invalid PCM source range"
        }
        if (length == 0) return

        var index = offset
        val end = offset + length
        val pending = pendingLowByte
        if (pending != null && index < end) {
            addSample(pending or ((source[index].toInt() and 0xff) shl 8), timestampMs)
            pendingLowByte = null
            index++
        }

        while (index + 1 < end) {
            val low = source[index].toInt() and 0xff
            val high = source[index + 1].toInt() and 0xff
            addSample(low or (high shl 8), timestampMs)
            index += 2
        }

        if (index < end) {
            pendingLowByte = source[index].toInt() and 0xff
        }
    }

    /** Completes the semantic speech interval when capture is stopped. */
    fun finish(timestampMs: Long) {
        if (speaking) {
            val startedAt = speechStartedAtMs ?: timestampMs
            onSpeechStopped(timestampMs, (timestampMs - startedAt).coerceAtLeast(0))
        }
        reset()
    }

    fun reset() {
        frameSampleCount = 0
        frameEnergy = 0.0
        pendingLowByte = null
        noiseFloorDb = INITIAL_NOISE_FLOOR_DB
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        speaking = false
        speechStartedAtMs = null
    }

    private fun addSample(sampleBits: Int, timestampMs: Long) {
        // Converting to a signed Int before squaring avoids treating negative
        // PCM values as large positive magnitudes.
        val sample = if (sampleBits and 0x8000 != 0) sampleBits - 0x10000 else sampleBits
        frameEnergy += sample.toDouble() * sample.toDouble()
        frameSampleCount++
        if (frameSampleCount < FRAME_SAMPLES) return

        val rms = sqrt(frameEnergy / FRAME_SAMPLES) / 32768.0
        val levelDb = 20.0 * log10(max(rms, MIN_RMS))
        frameSampleCount = 0
        frameEnergy = 0.0
        processFrame(levelDb, timestampMs)
    }

    private fun processFrame(levelDb: Double, timestampMs: Long) {
        if (!speaking) {
            // Only quiet frames update the floor. Speech must not raise its
            // own threshold and make a continuing utterance disappear.
            noiseFloorDb = if (levelDb < noiseFloorDb) {
                levelDb
            } else {
                noiseFloorDb + (levelDb - noiseFloorDb) * NOISE_FLOOR_ALPHA
            }

            val startThreshold = max(START_FLOOR_DB, noiseFloorDb + NOISE_MARGIN_DB)
            if (levelDb >= startThreshold) {
                consecutiveSpeechFrames++
            } else {
                consecutiveSpeechFrames = 0
            }
            consecutiveSilenceFrames = 0

            if (consecutiveSpeechFrames >= MIN_SPEECH_FRAMES) {
                speaking = true
                speechStartedAtMs = timestampMs
                consecutiveSpeechFrames = 0
                onSpeechStarted(timestampMs)
            }
            return
        }

        val stopThreshold = max(STOP_FLOOR_DB, noiseFloorDb + SILENCE_MARGIN_DB)
        if (levelDb <= stopThreshold) {
            consecutiveSilenceFrames++
        } else {
            consecutiveSilenceFrames = 0
        }
        if (consecutiveSilenceFrames < MIN_SILENCE_FRAMES) return

        val startedAt = speechStartedAtMs ?: timestampMs
        speaking = false
        speechStartedAtMs = null
        consecutiveSilenceFrames = 0
        onSpeechStopped(timestampMs, (timestampMs - startedAt).coerceAtLeast(0))
    }
}
