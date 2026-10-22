package com.limelight.jujostream.native_bridge

/**
 * How controller rumble may reach Android's InputManager.
 *
 * Every controller vibrate()/cancel() becomes an InputReader::vibrate or
 * cancelVibrate call in system_server. On AOSP android14-release those run
 * notifyAll() on the Binder thread while InputReader::loopOnce() flushes the
 * same QueuedInputListener outside mLock; the racing push_back corrupts the
 * queue and system_server aborts in QueuedInputListener::flush with
 * bad_variant_access, soft-rebooting the box (fixed in 14 QPR1 by queueing
 * into mPendingArgs under the lock). Chromecast HD (boreal, UTTC.250917.004)
 * ships that base code: tombstones on 2026-09-09 (Marvel Tokon, unthrottled)
 * and 2026-09-30 17:22:49 (Mortal Shell II, already throttled to 80 ms). The
 * race is per call, so no rate is safe there. Everywhere else fewer calls is
 * still less Binder traffic and less exposure to the same class of bug.
 *
 * Android-free so the policy runs in plain JVM tests.
 */
internal object ControllerRumblePolicy {
    /** Amplitude steps per channel. Games ramp rumble every frame; 8 steps feel the same. */
    const val LEVELS = 8

    /** Long enough to hold a steady rumble, short enough to bound a missed stop. */
    const val HOLD_MS = 60_000L

    // ponytail: exact device match; add other Android 14 base builds here when a
    // tombstone shows QueuedInputListener::flush -> bad_variant_access on them.
    fun inputVibrationSafe(sdkInt: Int, device: String): Boolean =
        !(sdkInt == 34 && device.startsWith("boreal"))

    /** 16-bit motor value -> 0..255 amplitude snapped to [levels] steps; nonzero stays nonzero. */
    fun quantize(raw: Int, levels: Int = LEVELS): Int {
        if (raw <= 0) return 0
        val amp = raw.coerceAtMost(65535) * 255 / 65535
        val step = ((amp * levels + 254) / 255).coerceIn(1, levels)
        return step * 255 / levels
    }

    // One Int per controller holds all four 8-bit channels, so a trigger update
    // can never cancel motor rumble (a combined vibration replaces them all).
    fun withMotors(state: Int, low: Int, high: Int): Int =
        (state and 0x0000FFFF) or ((low and 0xFF) shl 24) or ((high and 0xFF) shl 16)

    fun withTriggers(state: Int, left: Int, right: Int): Int =
        (state and 0xFFFF0000.toInt()) or ((left and 0xFF) shl 8) or (right and 0xFF)

    fun low(state: Int): Int = (state ushr 24) and 0xFF
    fun high(state: Int): Int = (state ushr 16) and 0xFF
    fun leftTrigger(state: Int): Int = (state ushr 8) and 0xFF
    fun rightTrigger(state: Int): Int = state and 0xFF
}
