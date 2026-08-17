package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeStreamLifecycleTest {

    @Test
    fun `stop during startup interrupts and late success requires teardown`() {
        val lifecycle = NativeStreamLifecycle()
        val generation = lifecycle.beginStart()

        assertEquals(NativeStreamLifecycle.StopDirective.INTERRUPT_START, lifecycle.requestStop())

        val completion = lifecycle.completeStart(generation, status = 0)
        assertFalse(completion.accepted)
        assertTrue(completion.stopNative)
        assertEquals(NativeStreamLifecycle.Phase.STOPPING, lifecycle.phase())

        lifecycle.completeStop(generation)
        assertEquals(NativeStreamLifecycle.Phase.IDLE, lifecycle.phase())
    }

    @Test
    fun `new start is rejected until prior stop completes`() {
        val lifecycle = NativeStreamLifecycle()
        val generation = lifecycle.beginStart()
        lifecycle.completeStart(generation, status = 0)
        assertEquals(NativeStreamLifecycle.StopDirective.STOP_ACTIVE, lifecycle.requestStop())

        val rejected = runCatching { lifecycle.beginStart() }
        assertTrue(rejected.isFailure)

        lifecycle.completeStop(generation)
        assertTrue(lifecycle.beginStart() > generation)
    }

    @Test
    fun `failed interrupted startup returns directly to idle`() {
        val lifecycle = NativeStreamLifecycle()
        val generation = lifecycle.beginStart()
        lifecycle.requestStop()

        val completion = lifecycle.completeStart(generation, status = 104)

        assertFalse(completion.accepted)
        assertFalse(completion.stopNative)
        assertEquals(NativeStreamLifecycle.Phase.IDLE, lifecycle.phase())
    }
}
