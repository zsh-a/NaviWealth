package com.naviwealth.naviwealth

/**
 * Process-local ownership for native microphone pipelines.
 *
 * Android's SpeechRecognizer and an app-owned AudioRecord must never capture
 * at the same time. Dart also has a managed lease, but this native guard is
 * required because the two platform channels can otherwise be called
 * independently. The owner token makes release idempotent and prevents an
 * old Activity from releasing a newer Activity's capture session.
 */
internal object AndroidMicrophoneLease {
    private var owner: String? = null

    @Synchronized
    fun tryAcquire(ownerToken: String): Boolean {
        if (owner != null) return false
        owner = ownerToken
        return true
    }

    @Synchronized
    fun release(ownerToken: String) {
        if (owner == ownerToken) owner = null
    }
}
