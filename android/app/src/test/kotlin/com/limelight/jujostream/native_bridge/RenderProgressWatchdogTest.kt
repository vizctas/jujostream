package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Test

class RenderProgressWatchdogTest {
    @Test
    fun `detects startup black screen when packets arrive but output stays zero`() {
        val watchdog = RenderProgressWatchdog(stallThresholdSamples = 3)

        assertEquals(RenderProgressWatchdog.Action.NONE, watchdog.observe(1, 0))
        assertEquals(RenderProgressWatchdog.Action.NONE, watchdog.observe(1, 0))
        assertEquals(RenderProgressWatchdog.Action.RECOVER, watchdog.observe(1, 0))
    }

    @Test
    fun `escalates a failed recovery to reconnect`() {
        val watchdog = RenderProgressWatchdog(stallThresholdSamples = 2)

        watchdog.observe(2, 0)
        assertEquals(RenderProgressWatchdog.Action.RECOVER, watchdog.observe(2, 0))
        watchdog.observe(2, 0)
        assertEquals(RenderProgressWatchdog.Action.RECONNECT, watchdog.observe(2, 0))
    }

    @Test
    fun `render progress rearms local recovery`() {
        val watchdog = RenderProgressWatchdog(stallThresholdSamples = 2)

        watchdog.observe(1, 0)
        assertEquals(RenderProgressWatchdog.Action.RECOVER, watchdog.observe(1, 0))
        assertEquals(RenderProgressWatchdog.Action.NONE, watchdog.observe(1, 1))
        watchdog.observe(1, 0)
        assertEquals(RenderProgressWatchdog.Action.RECOVER, watchdog.observe(1, 0))
    }

    @Test
    fun `network silence never looks like a decoder stall`() {
        val watchdog = RenderProgressWatchdog(stallThresholdSamples = 2)

        repeat(10) {
            assertEquals(RenderProgressWatchdog.Action.NONE, watchdog.observe(0, 0))
        }
    }
}
