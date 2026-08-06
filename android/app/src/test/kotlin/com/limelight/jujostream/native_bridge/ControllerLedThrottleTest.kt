package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Test

class ControllerLedThrottleTest {

    @Test
    fun `first color is dispatched immediately`() {
        val throttle = ControllerLedThrottle()

        val schedule = throttle.enqueue(deviceId = 7, color = 0x112233, nowNanos = 1L)

        assertNotNull(schedule)
        assertEquals(0L, schedule!!.delayMs)
        assertEquals(0x112233, throttle.takePending(7, 1L))
    }

    @Test
    fun `burst keeps newest color and creates one scheduled dispatch`() {
        val throttle = ControllerLedThrottle()

        assertNotNull(throttle.enqueue(7, 0x111111, 1L))
        assertNull(throttle.enqueue(7, 0x222222, 2L))
        assertNull(throttle.enqueue(7, 0x333333, 3L))

        assertEquals(0x333333, throttle.takePending(7, 4L))
    }

    @Test
    fun `next dispatch observes the thirty hertz interval`() {
        val throttle = ControllerLedThrottle(minIntervalNanos = 33_000_000L)

        throttle.enqueue(7, 0x111111, 0L)
        val first = throttle.takePending(7, 0L)!!
        throttle.markApplied(7, first)

        val schedule = throttle.enqueue(7, 0x222222, 10_000_000L)

        assertNotNull(schedule)
        assertEquals(23L, schedule!!.delayMs)
    }

    @Test
    fun `already applied color is ignored`() {
        val throttle = ControllerLedThrottle()

        throttle.enqueue(7, 0x112233, 0L)
        val color = throttle.takePending(7, 0L)!!
        throttle.markApplied(7, color)

        assertNull(throttle.enqueue(7, 0x112233, 40_000_000L))
    }

    @Test
    fun `controllers are throttled independently and clear removes state`() {
        val throttle = ControllerLedThrottle()

        assertNotNull(throttle.enqueue(1, 0x111111, 0L))
        assertNotNull(throttle.enqueue(2, 0x222222, 0L))
        throttle.clear(1)

        assertNull(throttle.takePending(1, 1L))
        assertEquals(0x222222, throttle.takePending(2, 1L))
    }
}
