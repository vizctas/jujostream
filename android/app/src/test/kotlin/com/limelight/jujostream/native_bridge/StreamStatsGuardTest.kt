package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class StreamStatsGuardTest {

    @Test
    fun `stop waits for active native stats call and rejects later calls`() {
        val guard = StreamStatsGuard()
        val nativeCallEntered = CountDownLatch(1)
        val releaseNativeCall = CountDownLatch(1)
        val pollCompleted = CountDownLatch(1)

        guard.startSession()
        Thread {
            guard.runIfActive {
                nativeCallEntered.countDown()
                releaseNativeCall.await()
                42
            }
            pollCompleted.countDown()
        }.start()

        assertTrue(nativeCallEntered.await(1, TimeUnit.SECONDS))

        val stopCompleted = CountDownLatch(1)
        Thread {
            guard.stopAndAwait()
            stopCompleted.countDown()
        }.start()

        assertFalse(stopCompleted.await(100, TimeUnit.MILLISECONDS))
        releaseNativeCall.countDown()

        assertTrue(pollCompleted.await(1, TimeUnit.SECONDS))
        assertTrue(stopCompleted.await(1, TimeUnit.SECONDS))

        val calledAfterStop = AtomicBoolean(false)
        val result = guard.runIfActive {
            calledAfterStop.set(true)
            99
        }
        assertNull(result)
        assertFalse(calledAfterStop.get())
    }

    @Test
    fun `new session accepts stats after prior stop`() {
        val guard = StreamStatsGuard()

        guard.startSession()
        guard.stopAndAwait()
        guard.startSession()

        assertEquals(7, guard.runIfActive { 7 })
    }
}
