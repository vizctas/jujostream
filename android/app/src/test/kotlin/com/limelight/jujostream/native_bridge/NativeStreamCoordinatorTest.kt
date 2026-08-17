package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class NativeStreamCoordinatorTest {
    @Test
    fun `stop interrupts startup then tears down late native success exactly once`() {
        val allowStartReturn = CountDownLatch(1)
        val startEntered = CountDownLatch(1)
        val idle = CountDownLatch(1)
        val interrupts = AtomicInteger()
        val stops = AtomicInteger()
        val coordinator = NativeStreamCoordinator(
            nativeInterrupt = {
                interrupts.incrementAndGet()
                allowStartReturn.countDown()
            },
            nativeStop = { stops.incrementAndGet() },
            onIdle = { idle.countDown() },
        )

        assertTrue(coordinator.start(
            nativeStart = {
                startEntered.countDown()
                allowStartReturn.await()
                0
            },
            onComplete = {},
        ))
        assertTrue(startEntered.await(1, TimeUnit.SECONDS))

        coordinator.stop()

        assertTrue(idle.await(1, TimeUnit.SECONDS))
        assertEquals(1, interrupts.get())
        assertEquals(1, stops.get())
        assertEquals(NativeStreamLifecycle.Phase.IDLE, coordinator.phase())
    }

    @Test
    fun `active stop serializes duplicate stop requests`() {
        val started = CountDownLatch(1)
        val stopRelease = CountDownLatch(1)
        val idle = CountDownLatch(1)
        val stops = AtomicInteger()
        val coordinator = NativeStreamCoordinator(
            nativeInterrupt = {},
            nativeStop = {
                stops.incrementAndGet()
                stopRelease.await()
            },
            onIdle = { idle.countDown() },
        )

        coordinator.start(nativeStart = { 0 }, onComplete = { started.countDown() })
        assertTrue(started.await(1, TimeUnit.SECONDS))
        assertEquals(NativeStreamLifecycle.Phase.ACTIVE, coordinator.phase())

        coordinator.stop()
        coordinator.stop()
        assertFalse(idle.await(50, TimeUnit.MILLISECONDS))
        stopRelease.countDown()

        assertTrue(idle.await(1, TimeUnit.SECONDS))
        assertEquals(1, stops.get())
    }
}
