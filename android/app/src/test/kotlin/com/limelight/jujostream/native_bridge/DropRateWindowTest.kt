package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Test

class DropRateWindowTest {
    @Test
    fun `one stray drop does not read as a spike`() {
        val window = DropRateWindow()
        repeat(24) { window.add(12, 0) }
        // Old per-tick math: 1 / 12 = 8%.
        assertEquals(0, window.add(11, 1))
    }

    @Test
    fun `sustained drops still show`() {
        val window = DropRateWindow()
        var rate = 0
        repeat(25) { rate = window.add(9, 3) }
        assertEquals(25, rate)
    }

    @Test
    fun `old drops age out and reset clears`() {
        val window = DropRateWindow(samples = 2)
        assertEquals(50, window.add(6, 6))
        assertEquals(0, window.add(12, 0).let { window.add(12, 0) })
        window.add(0, 5)
        window.reset()
        assertEquals(0, window.add(12, 0))
    }
}
