package com.limelight.jujostream.native_bridge

internal data class ControllerLedSchedule(val delayMs: Long)

/**
 * Coalesces high-rate controller LED feedback without losing the newest color.
 *
 * Games can update a virtual DS4 light bar once per frame. Android lights are
 * Binder-backed and do not benefit from receiving more than 30 updates/sec.
 * This class is deliberately Android-free so the scheduling policy is covered
 * by ordinary JVM tests.
 */
internal class ControllerLedThrottle(
    private val minIntervalNanos: Long = 33_000_000L,
) {
    private data class State(
        var pendingColor: Int? = null,
        var appliedColor: Int? = null,
        var scheduled: Boolean = false,
        var lastDispatchNanos: Long? = null,
    )

    private val states = mutableMapOf<Int, State>()

    fun enqueue(deviceId: Int, color: Int, nowNanos: Long): ControllerLedSchedule? {
        val state = states.getOrPut(deviceId) { State() }

        if (color == state.pendingColor) return null
        if (!state.scheduled && color == state.appliedColor) return null

        state.pendingColor = color
        if (state.scheduled) return null

        state.scheduled = true
        val remainingNanos = state.lastDispatchNanos?.let { last ->
            (minIntervalNanos - (nowNanos - last)).coerceAtLeast(0L)
        } ?: 0L
        val delayMs = (remainingNanos + 999_999L) / 1_000_000L
        return ControllerLedSchedule(delayMs)
    }

    fun takePending(deviceId: Int, nowNanos: Long): Int? {
        val state = states[deviceId] ?: return null
        if (!state.scheduled) return null

        state.scheduled = false
        state.lastDispatchNanos = nowNanos
        val color = state.pendingColor
        state.pendingColor = null
        return color?.takeUnless { it == state.appliedColor }
    }

    fun markApplied(deviceId: Int, color: Int) {
        states[deviceId]?.appliedColor = color
    }

    fun clear(deviceId: Int) {
        states.remove(deviceId)
    }

    fun clearAll() {
        states.clear()
    }
}
