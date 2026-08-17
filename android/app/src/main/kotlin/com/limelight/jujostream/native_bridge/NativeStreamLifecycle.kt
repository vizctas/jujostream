package com.limelight.jujostream.native_bridge

/**
 * Thread-safe state machine for the process-global moonlight-common-c session.
 *
 * moonlight-common-c permits interruption while LiStartConnection() is running,
 * but teardown and another start must wait until that call returns. Keeping the
 * invariant here prevents UI timeouts and reconnects from overlapping native
 * global state.
 */
class NativeStreamLifecycle {
    enum class Phase { IDLE, STARTING, ACTIVE, INTERRUPTING, STOPPING }

    enum class StopDirective {
        NONE,
        INTERRUPT_START,
        STOP_ACTIVE,
        WAIT_FOR_STOP,
    }

    data class StartCompletion(
        val accepted: Boolean,
        val stopNative: Boolean,
    )

    private val lock = Any()
    private var currentPhase = Phase.IDLE
    private var generation = 0L

    fun beginStart(): Long = synchronized(lock) {
        check(currentPhase == Phase.IDLE) {
            "Native stream is ${currentPhase.name.lowercase()}"
        }
        currentPhase = Phase.STARTING
        ++generation
    }

    fun requestStop(): StopDirective = synchronized(lock) {
        when (currentPhase) {
            Phase.IDLE -> StopDirective.NONE
            Phase.STARTING -> {
                currentPhase = Phase.INTERRUPTING
                StopDirective.INTERRUPT_START
            }
            Phase.ACTIVE -> {
                currentPhase = Phase.STOPPING
                StopDirective.STOP_ACTIVE
            }
            Phase.INTERRUPTING,
            Phase.STOPPING -> StopDirective.WAIT_FOR_STOP
        }
    }

    fun completeStart(startGeneration: Long, status: Int): StartCompletion = synchronized(lock) {
        if (startGeneration != generation) {
            return@synchronized StartCompletion(accepted = false, stopNative = status == 0)
        }

        when (currentPhase) {
            Phase.STARTING -> {
                if (status == 0) {
                    currentPhase = Phase.ACTIVE
                    StartCompletion(accepted = true, stopNative = false)
                } else {
                    currentPhase = Phase.IDLE
                    StartCompletion(accepted = false, stopNative = false)
                }
            }
            Phase.INTERRUPTING -> {
                if (status == 0) {
                    currentPhase = Phase.STOPPING
                    StartCompletion(accepted = false, stopNative = true)
                } else {
                    currentPhase = Phase.IDLE
                    StartCompletion(accepted = false, stopNative = false)
                }
            }
            Phase.IDLE,
            Phase.ACTIVE,
            Phase.STOPPING -> StartCompletion(accepted = false, stopNative = status == 0)
        }
    }

    fun completeStop(stopGeneration: Long) = synchronized(lock) {
        if (stopGeneration == generation) {
            currentPhase = Phase.IDLE
        }
    }

    fun phase(): Phase = synchronized(lock) { currentPhase }

    fun currentGeneration(): Long = synchronized(lock) { generation }
}
