package com.limelight.jujostream.native_bridge

/** Bounded timings for frames released for rendering, not discarded codec outputs. */
internal class FrameTimingWindow(private val capacity: Int = 300) {
    private val decode = FloatArray(capacity)
    private val intervals = FloatArray(capacity)
    private var decodeIndex = 0
    private var decodeCount = 0
    private var intervalIndex = 0
    private var intervalCount = 0
    private var lastRenderNs = 0L
    @Volatile var averageMs = 0f
        private set

    @Synchronized
    fun record(queueNs: Long, releaseNs: Long, rendered: Boolean) {
        if (!rendered) return
        val latencyMs = (releaseNs - queueNs) / 1_000_000f
        averageMs = if (averageMs == 0f) latencyMs else averageMs * 0.95f + latencyMs * 0.05f
        decode[decodeIndex] = latencyMs
        decodeIndex = (decodeIndex + 1) % capacity
        decodeCount = (decodeCount + 1).coerceAtMost(capacity)
        if (lastRenderNs > 0L) {
            intervals[intervalIndex] = (releaseNs - lastRenderNs) / 1_000_000f
            intervalIndex = (intervalIndex + 1) % capacity
            intervalCount = (intervalCount + 1).coerceAtMost(capacity)
        }
        lastRenderNs = releaseNs
    }

    @Synchronized
    fun snapshot(): Pair<FloatArray, FloatArray> =
        decode.copyOf(decodeCount) to intervals.copyOf(intervalCount)

    @Synchronized
    fun reset() {
        decodeIndex = 0
        decodeCount = 0
        intervalIndex = 0
        intervalCount = 0
        lastRenderNs = 0L
        averageMs = 0f
    }
}
