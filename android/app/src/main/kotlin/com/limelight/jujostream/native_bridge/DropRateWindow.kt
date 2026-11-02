package com.limelight.jujostream.native_bridge

/**
 * HUD drop percentage over the last [samples] stats ticks (5 s at 200 ms).
 * Per tick only ~12 frames exist, so one stray drop read as 8% and two as
 * 14% even when a whole session lost 3 frames in 27k.
 */
internal class DropRateWindow(private val samples: Int = 25) {
    private val rendered = LongArray(samples)
    private val dropped = LongArray(samples)
    private var index = 0

    fun add(renderedDelta: Long, droppedDelta: Long): Int {
        rendered[index] = renderedDelta
        dropped[index] = droppedDelta
        index = (index + 1) % samples
        val drops = dropped.sum()
        val total = rendered.sum() + drops
        return if (total > 0) ((drops * 100) / total).toInt().coerceIn(0, 100) else 0
    }

    fun reset() {
        rendered.fill(0)
        dropped.fill(0)
        index = 0
    }
}
