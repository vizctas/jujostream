package com.limelight.jujostream.native_bridge

/** Detects decode/presentation wedges from counter deltas, including zero-output startup. */
class RenderProgressWatchdog(
    private val stallThresholdSamples: Int,
) {
    enum class Action { NONE, RECOVER, RECONNECT }

    private var stagnantSamples = 0
    private var recoveryAttempted = false
    private var reconnectIssued = false

    init {
        require(stallThresholdSamples > 0)
    }

    @Synchronized
    fun observe(receivedDelta: Long, renderedDelta: Long): Action {
        if (renderedDelta > 0L) {
            reset()
            return Action.NONE
        }
        if (receivedDelta <= 0L) {
            stagnantSamples = 0
            return Action.NONE
        }
        if (reconnectIssued) return Action.NONE

        stagnantSamples++
        if (stagnantSamples < stallThresholdSamples) return Action.NONE

        stagnantSamples = 0
        return if (recoveryAttempted) {
            reconnectIssued = true
            Action.RECONNECT
        } else {
            recoveryAttempted = true
            Action.RECOVER
        }
    }

    @Synchronized
    fun reset() {
        stagnantSamples = 0
        recoveryAttempted = false
        reconnectIssued = false
    }
}
