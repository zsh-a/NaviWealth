package com.naviwealth.app

import org.junit.Assert.*
import org.junit.Test

class BleSessionGateTest {
    @Test fun cancelledAndReplacedCallbacksCannotReturn() {
        val gate = BleSessionGate()
        val first = gate.begin("capture-1")
        gate.invalidate()
        assertFalse(gate.accepts("capture-1", first))
        val second = gate.begin("capture-1")
        assertFalse(gate.accepts("capture-1", first))
        assertTrue(gate.accepts("capture-1", second))
        gate.begin("capture-2")
        assertFalse(gate.accepts("capture-1", second))
    }
    @Test fun sessionIdsAreBoundedAndCannotContainControlCharacters() {
        for (id in listOf("", "x".repeat(97), "capture\n1", "a/b")) {
            assertThrows(IllegalArgumentException::class.java) { BleSessionGate().begin(id) }
        }
    }
}
