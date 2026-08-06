package com.limelight.jujostream.native_bridge

/**
 * Serializes native stream-stat reads against native connection teardown.
 *
 * [stopAndAwait] first rejects new reads, then waits for any read already
 * holding the monitor. Native teardown is safe after it returns.
 */
internal class StreamStatsGuard {
    private val monitor = Any()

    @Volatile
    private var active = false

    fun startSession() {
        synchronized(monitor) {
            active = true
        }
    }

    fun <T> runIfActive(block: () -> T): T? = synchronized(monitor) {
        if (!active) null else block()
    }

    fun stopAndAwait() {
        active = false
        synchronized(monitor) {
            // Monitor acquisition is the in-flight native-call barrier.
        }
    }
}
