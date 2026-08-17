package com.limelight.jujostream.native_bridge

import java.util.concurrent.atomic.AtomicLong

/**
 * Owns all transitions around moonlight-common-c's process-global connection.
 * Startup may be interrupted from another thread, but stop and the next start
 * are serialized until the blocking native start call has returned.
 */
class NativeStreamCoordinator(
    private val nativeInterrupt: () -> Unit,
    private val nativeStop: () -> Unit,
    private val onIdle: () -> Unit,
) {
    data class StartResult(
        val status: Int,
        val accepted: Boolean,
        val error: Throwable? = null,
    )

    private val lifecycle = NativeStreamLifecycle()
    private val idleNotificationLock = Any()
    private val lastIdleGeneration = AtomicLong(0L)

    @Volatile
    private var startThread: Thread? = null

    fun start(nativeStart: () -> Int, onComplete: (StartResult) -> Unit): Boolean {
        val generation = try {
            lifecycle.beginStart()
        } catch (_: IllegalStateException) {
            return false
        }

        val thread = Thread({
            var error: Throwable? = null
            val status = try {
                nativeStart()
            } catch (t: Throwable) {
                error = t
                Int.MIN_VALUE
            }

            val completion = lifecycle.completeStart(generation, status)
            if (completion.stopNative) {
                runCatching(nativeStop)
                    .onFailure { if (error == null) error = it }
                lifecycle.completeStop(generation)
            }

            if (lifecycle.phase() == NativeStreamLifecycle.Phase.IDLE) {
                notifyIdleOnce(generation)
            }

            onComplete(StartResult(status, completion.accepted, error))
            if (startThread === Thread.currentThread()) startThread = null
        }, "Native-Stream-Start")

        startThread = thread
        thread.isDaemon = true
        thread.start()
        return true
    }

    fun stop(): NativeStreamLifecycle.StopDirective {
        val generation = lifecycle.currentGeneration()
        return when (val directive = lifecycle.requestStop()) {
            NativeStreamLifecycle.StopDirective.NONE -> directive
            NativeStreamLifecycle.StopDirective.INTERRUPT_START -> {
                runCatching(nativeInterrupt)
                directive
            }
            NativeStreamLifecycle.StopDirective.STOP_ACTIVE -> {
                Thread({
                    runCatching(nativeStop)
                    lifecycle.completeStop(generation)
                    notifyIdleOnce(generation)
                }, "Native-Stream-Stop").apply {
                    isDaemon = true
                    start()
                }
                directive
            }
            NativeStreamLifecycle.StopDirective.WAIT_FOR_STOP -> directive
        }
    }

    fun phase(): NativeStreamLifecycle.Phase = lifecycle.phase()

    private fun notifyIdleOnce(generation: Long) {
        synchronized(idleNotificationLock) {
            if (lastIdleGeneration.get() == generation) return
            lastIdleGeneration.set(generation)
        }
        onIdle()
    }
}
