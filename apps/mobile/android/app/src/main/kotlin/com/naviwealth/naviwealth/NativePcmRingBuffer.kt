package com.naviwealth.naviwealth

import kotlin.math.min

/**
 * Bounded native-only PCM16 ring buffer.
 *
 * The buffer is deliberately not exposed through a Flutter channel. A future
 * native ASR/VAD consumer can drain it in-process; until then the newest audio
 * replaces the oldest audio and only aggregate drop metrics leave native.
 */
internal class NativePcmRingBuffer(capacityBytes: Int) {
    init {
        require(capacityBytes > 0) { "capacityBytes must be positive" }
    }

    private val storage = ByteArray(capacityBytes)
    private var readIndex = 0
    private var sizeBytes = 0
    private var droppedBytes = 0L

    @Synchronized
    fun write(source: ByteArray, offset: Int = 0, length: Int = source.size) {
        require(offset >= 0 && length >= 0 && offset + length <= source.size) {
            "Invalid PCM source range"
        }
        if (length == 0) return

        if (length >= storage.size) {
            droppedBytes += sizeBytes.toLong() + (length - storage.size).toLong()
            val sourceStart = offset + length - storage.size
            System.arraycopy(source, sourceStart, storage, 0, storage.size)
            readIndex = 0
            sizeBytes = storage.size
            return
        }

        val overflow = sizeBytes + length - storage.size
        if (overflow > 0) {
            droppedBytes += overflow.toLong()
            readIndex = (readIndex + overflow) % storage.size
            sizeBytes -= overflow
        }

        var writeIndex = (readIndex + sizeBytes) % storage.size
        var sourceIndex = offset
        var remaining = length
        while (remaining > 0) {
            val contiguous = min(remaining, storage.size - writeIndex)
            System.arraycopy(source, sourceIndex, storage, writeIndex, contiguous)
            sourceIndex += contiguous
            remaining -= contiguous
            writeIndex = (writeIndex + contiguous) % storage.size
        }
        sizeBytes += length
    }

    /** Drains up to [length] bytes for a future in-process ASR consumer. */
    @Synchronized
    fun read(destination: ByteArray, offset: Int = 0, length: Int = destination.size): Int {
        require(offset >= 0 && length >= 0 && offset + length <= destination.size) {
            "Invalid PCM destination range"
        }
        val count = min(length, sizeBytes)
        if (count == 0) return 0

        var destinationIndex = offset
        var sourceIndex = readIndex
        var remaining = count
        while (remaining > 0) {
            val contiguous = min(remaining, storage.size - sourceIndex)
            System.arraycopy(storage, sourceIndex, destination, destinationIndex, contiguous)
            destinationIndex += contiguous
            remaining -= contiguous
            sourceIndex = (sourceIndex + contiguous) % storage.size
        }
        readIndex = sourceIndex
        sizeBytes -= count
        return count
    }

    @Synchronized
    fun snapshot(): Snapshot = Snapshot(
        bufferedBytes = sizeBytes,
        droppedBytes = droppedBytes,
    )

    @Synchronized
    fun clear() {
        readIndex = 0
        sizeBytes = 0
        droppedBytes = 0L
    }

    internal data class Snapshot(
        val bufferedBytes: Int,
        val droppedBytes: Long,
    )
}
