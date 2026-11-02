package com.limelight.jujostream.native_bridge

import org.junit.Assert.*
import org.junit.Test

class FrameTimingWindowTest {
    @Test
    fun `discarding stale frames does not report false render progress`() {
        val timing = FrameTimingWindow()
        timing.record(1_000_000, 5_000_000, true)
        timing.record(2_000_000, 20_000_000, false)
        timing.record(3_000_000, 21_000_000, false)
        timing.record(33_000_000, 37_000_000, true)
        val (decode, intervals) = timing.snapshot()
        assertArrayEquals(floatArrayOf(4f, 4f), decode, 0f)
        assertArrayEquals(floatArrayOf(32f), intervals, 0f)
        assertEquals(4f, timing.averageMs, 0.0001f)
    }

    @Test
    fun `window is bounded snapshots independent and reset starts a new cadence`() {
        val timing = FrameTimingWindow(3)
        for (i in 1L..6L) timing.record(i * 10_000_000, i * 10_000_000 + 2_000_000, true)
        val (decode, intervals) = timing.snapshot()
        assertArrayEquals(floatArrayOf(2f, 2f, 2f), decode, 0f)
        assertArrayEquals(floatArrayOf(10f, 10f, 10f), intervals, 0f)
        decode[0] = 900f
        assertEquals(2f, timing.snapshot().first[0], 0f)
        timing.reset()
        assertEquals(0f, timing.averageMs, 0f)
        assertTrue(timing.snapshot().first.isEmpty())
        timing.record(100_000_000, 103_000_000, true)
        assertTrue(timing.snapshot().second.isEmpty())
        assertEquals(3f, timing.averageMs, 0f)
    }
}
