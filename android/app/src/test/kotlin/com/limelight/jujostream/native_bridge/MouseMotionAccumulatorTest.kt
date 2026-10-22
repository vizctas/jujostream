package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Test

class MouseMotionAccumulatorTest {
    @Test
    fun `slow diagonal mouse motion retains subpixel input`() {
        var totalX = 0
        var totalY = 0
        val mouse = MouseMotionAccumulator { x, y -> totalX += x; totalY += y }
        mouse.seed(1, 0f, 0f)
        for (i in 1..100) mouse.move(1, i.toFloat(), -i.toFloat(), 0.5f)
        assertEquals(50, totalX)
        assertEquals(-50, totalY)
    }

    @Test
    fun `reversals cancel residuals independently on each axis`() {
        val events = mutableListOf<Pair<Short, Short>>()
        val mouse = MouseMotionAccumulator { x, y -> events.add(x to y) }
        mouse.seed(1, 0f, 0f)
        mouse.move(1, 1f, -1f, 0.5f)
        mouse.move(1, 0f, 0f, 0.5f)
        assertEquals(emptyList<Pair<Short, Short>>(), events)
        mouse.move(1, -1f, 1f, 0.5f)
        mouse.move(1, -2f, 2f, 0.5f)
        assertEquals(listOf((-1).toShort() to 1.toShort()), events)
    }

    @Test
    fun `hover to drag retains precision without generating a click displacement`() {
        var total = 0
        val mouse = MouseMotionAccumulator { x, _ -> total += x }
        mouse.seed(1, 0f, 0f)
        mouse.move(1, 1f, 0f, 0.5f)
        mouse.seed(1, 1f, 0f)
        mouse.move(1, 2f, 0f, 0.5f)
        assertEquals(1, total)
    }

    @Test
    fun `new device and reset discard both coordinates and fractional history`() {
        var total = 0
        val mouse = MouseMotionAccumulator { x, _ -> total += x }
        mouse.move(1, 0f, 0f, 0.5f)
        mouse.move(1, 1f, 0f, 0.5f)
        mouse.move(2, 100f, 0f, 0.5f)
        mouse.move(2, 101f, 0f, 0.5f)
        assertEquals(0, total)
        mouse.reset()
        mouse.move(2, 500f, 0f, 0.5f)
        mouse.move(2, 501f, 0f, 0.5f)
        assertEquals(0, total)
        mouse.move(2, 502f, 0f, 0.5f)
        assertEquals(1, total)
    }

    @Test
    fun `packet limits do not wrap or replay a clipped jump`() {
        val events = mutableListOf<Pair<Short, Short>>()
        val mouse = MouseMotionAccumulator { x, y -> events.add(x to y) }
        mouse.seed(1, 0f, 0f)
        mouse.move(1, 100000f, -100000f, 1f)
        mouse.move(1, 100000f, -100000f, 1f)
        mouse.move(1, 100001f, -100002f, 1f)
        assertEquals(listOf(32767.toShort() to (-32767).toShort(), 1.toShort() to (-2).toShort()), events)
    }

    @Test
    fun `invalid coordinates cannot poison subsequent input`() {
        var total = 0
        val mouse = MouseMotionAccumulator { x, _ -> total += x }
        mouse.seed(1, 0f, 0f)
        mouse.move(1, Float.NaN, 0f, 1f)
        mouse.move(1, 100f, 0f, 1f)
        mouse.move(1, 101f, 0f, 1f)
        assertEquals(1, total)
    }
}
