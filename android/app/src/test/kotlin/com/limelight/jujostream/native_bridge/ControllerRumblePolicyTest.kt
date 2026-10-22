package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.sin

class ControllerRumblePolicyTest {

    // --- platform gate -------------------------------------------------------

    @Test
    fun `chromecast hd on android 14 never reaches the input reader`() {
        assertFalse(ControllerRumblePolicy.inputVibrationSafe(sdkInt = 34, device = "boreal"))
    }

    @Test
    fun `other devices keep controller rumble`() {
        assertTrue(ControllerRumblePolicy.inputVibrationSafe(30, "AFTKRT"))       // Fire TV 4K
        assertTrue(ControllerRumblePolicy.inputVibrationSafe(34, "husky"))        // Pixel 8
        assertTrue(ControllerRumblePolicy.inputVibrationSafe(35, "boreal"))       // boreal on a fixed release
        assertTrue(ControllerRumblePolicy.inputVibrationSafe(33, "boreal"))
    }

    // --- quantization --------------------------------------------------------

    @Test
    fun `zero stays zero and full scale stays full scale`() {
        assertEquals(0, ControllerRumblePolicy.quantize(0))
        assertEquals(255, ControllerRumblePolicy.quantize(65535))
    }

    @Test
    fun `faint rumble is never rounded away`() {
        assertTrue(ControllerRumblePolicy.quantize(1) > 0)
        assertTrue(ControllerRumblePolicy.quantize(200) > 0)
    }

    @Test
    fun `out of range input is clamped`() {
        assertEquals(0, ControllerRumblePolicy.quantize(-5))
        assertEquals(255, ControllerRumblePolicy.quantize(70000))
    }

    @Test
    fun `output uses at most LEVELS distinct nonzero amplitudes and is monotonic`() {
        var previous = 0
        val seen = mutableSetOf<Int>()
        for (raw in 0..65535 step 7) {
            val q = ControllerRumblePolicy.quantize(raw)
            assertTrue("not monotonic at $raw", q >= previous)
            assertTrue(q in 0..255)
            previous = q
            if (q > 0) seen += q
        }
        assertEquals(ControllerRumblePolicy.LEVELS, seen.size)
    }

    // --- packed motor + trigger state ---------------------------------------

    @Test
    fun `motors and triggers share one state without clobbering each other`() {
        var state = 0
        state = ControllerRumblePolicy.withMotors(state, low = 255, high = 63)
        state = ControllerRumblePolicy.withTriggers(state, left = 31, right = 127)

        assertEquals(255, ControllerRumblePolicy.low(state))
        assertEquals(63, ControllerRumblePolicy.high(state))
        assertEquals(31, ControllerRumblePolicy.leftTrigger(state))
        assertEquals(127, ControllerRumblePolicy.rightTrigger(state))

        state = ControllerRumblePolicy.withMotors(state, low = 0, high = 0)
        assertEquals(31, ControllerRumblePolicy.leftTrigger(state))
        assertEquals(127, ControllerRumblePolicy.rightTrigger(state))
        assertEquals(0, ControllerRumblePolicy.low(state))
    }

    // --- whole pipeline: game packets -> throttle -> InputReader calls ------

    /**
     * Replays a frame-rate rumble trace through the same quantize + coalesce
     * path GamepadHandler uses and counts how many times it would hit
     * InputManager (each one an InputReader vibrate/cancel).
     */
    private fun inputReaderCalls(
        packets: List<Pair<Long, Int>>,       // (nanos, raw 16-bit motor)
        intervalNanos: Long,
        quantize: Boolean,
    ): Int {
        val throttle = ControllerLedThrottle(intervalNanos)
        val due = ArrayDeque<Long>()
        var calls = 0
        fun drain(until: Long) {
            while (due.isNotEmpty() && due.first() <= until) {
                val at = due.removeFirst()
                val v = throttle.takePending(1, at) ?: continue
                throttle.markApplied(1, v)
                calls++
            }
        }
        for ((t, raw) in packets) {
            drain(t)
            val low = if (quantize) ControllerRumblePolicy.quantize(raw) else raw
            val state = ControllerRumblePolicy.withMotors(0, low and 0xFF, low ushr 8)
            throttle.enqueue(1, state, t)?.let { due.addLast(t + it.delayMs * 1_000_000L) }
        }
        drain(Long.MAX_VALUE)
        return calls
    }

    /** 60 s of UE-style rumble: new value every frame, slow swell plus jitter. */
    private fun mortalShellLikeTrace(): List<Pair<Long, Int>> {
        val frame = 16_666_667L
        return (0 until 60 * 60).map { i ->
            val swell = (sin(i / 45.0) + 1.0) / 2.0             // 0..1 over ~5 s
            val jitter = ((i * 7919) % 97) / 97.0 * 0.04        // +-4 % frame noise
            val raw = ((swell * 0.9 + jitter) * 65535).toInt().coerceIn(0, 65535)
            i * frame to raw
        }
    }

    @Test
    fun `quantized pipeline makes far fewer input reader calls than raw forwarding`() {
        val trace = mortalShellLikeTrace()
        val raw = inputReaderCalls(trace, 40_000_000L, quantize = false)
        val quantized = inputReaderCalls(trace, 40_000_000L, quantize = true)

        // Raw forwarding: one call per 40 ms slot for the whole minute.
        assertTrue("raw=$raw", raw >= 1400)
        // Quantized: only level changes, a small fraction of that.
        assertTrue("quantized=$quantized raw=$raw", quantized * 5 < raw)
    }

    @Test
    fun `pipeline never exceeds the dispatch interval`() {
        val trace = mortalShellLikeTrace()
        val calls = inputReaderCalls(trace, 40_000_000L, quantize = true)
        assertTrue(calls <= 60_000 / 40 + 1)
    }

    @Test
    fun `steady rumble produces a single call`() {
        val frame = 16_666_667L
        val trace = (0 until 600).map { i -> i * frame to 40000 + (i % 3) } // tiny jitter
        assertEquals(1, inputReaderCalls(trace, 40_000_000L, quantize = true))
    }

    @Test
    fun `final value always lands after a burst`() {
        val frame = 16_666_667L
        val trace = (0 until 30).map { i -> i * frame to abs(30000 - i * 1000) } + (30 * frame to 0)
        val throttle = ControllerLedThrottle(40_000_000L)
        var last: Int? = null
        val due = ArrayDeque<Long>()
        for ((t, raw) in trace) {
            while (due.isNotEmpty() && due.first() <= t) {
                val at = due.removeFirst()
                throttle.takePending(1, at)?.let { throttle.markApplied(1, it); last = it }
            }
            val state = ControllerRumblePolicy.withMotors(0, ControllerRumblePolicy.quantize(raw), 0)
            throttle.enqueue(1, state, t)?.let { due.addLast(t + it.delayMs * 1_000_000L) }
        }
        while (due.isNotEmpty()) {
            val at = due.removeFirst()
            throttle.takePending(1, at)?.let { throttle.markApplied(1, it); last = it }
        }
        assertEquals(0, last)
    }
}
