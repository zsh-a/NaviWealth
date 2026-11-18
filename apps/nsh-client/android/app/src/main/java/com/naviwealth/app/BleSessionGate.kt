package com.naviwealth.app

/** Session identity and generation fence for every asynchronous platform callback. */
internal class BleSessionGate {
    var generation: Long = 0
        private set
    var sessionId: String? = null
        private set
    fun begin(id: String): Long {
        require(id.length in 1..96 && id.all { it.isLetterOrDigit() || it in "-_:" })
        generation += 1
        sessionId = id
        return generation
    }
    fun accepts(id: String, token: Long): Boolean = sessionId == id && generation == token
    fun invalidate() { generation += 1; sessionId = null }
}
