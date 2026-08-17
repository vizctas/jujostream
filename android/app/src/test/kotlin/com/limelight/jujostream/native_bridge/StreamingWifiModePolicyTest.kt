package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Test

class StreamingWifiModePolicyTest {
    @Test
    fun `uses low latency mode when Android supports it`() {
        assertEquals(
            StreamingWifiMode.LOW_LATENCY,
            StreamingWifiModePolicy.forSdk(29),
        )
    }

    @Test
    fun `falls back to high performance before Android 10`() {
        assertEquals(
            StreamingWifiMode.HIGH_PERFORMANCE,
            StreamingWifiModePolicy.forSdk(28),
        )
    }
}
