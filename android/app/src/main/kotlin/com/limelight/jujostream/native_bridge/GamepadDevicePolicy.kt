package com.limelight.jujostream.native_bridge

internal object GamepadDevicePolicy {
    fun requiresJoyConOptIn(vendorId: Int, deviceName: String?): Boolean {
        val name = deviceName?.lowercase() ?: ""
        return name.contains("joy-con") || name.contains("joycon")
    }

    /**
     * Identity of one physical button, used by the blocked-button list.
     *
     * Both halves matter. The extra rear buttons on macro pads are often
     * shipped preset to mirror a face button, so they arrive with the same
     * keyCode as the real one and only the scanCode tells them apart.
     */
    fun buttonKey(keyCode: Int, scanCode: Int): Long =
        (keyCode.toLong() shl 32) or (scanCode.toLong() and 0xFFFFFFFFL)

    /** Which axes, if any, carry the analog triggers on a device. */
    enum class TriggerAxes { LTRIGGER_RTRIGGER, BRAKE_GAS, BRAKE_THROTTLE, Z_RZ, DIGITAL }

    /**
     * Decides the trigger axes from the motion ranges a device actually
     * reports.
     *
     * The Z/RZ case is the one that needs care: two incompatible conventions
     * use those axes. The old Xbox/Linux layout puts LT on Z and RT on RZ and
     * moves the right stick to RX/RY. Switch-style pads (real Pro Controllers
     * and the ONIKUMA-class clones that emulate them) do the opposite — the
     * RIGHT STICK is on Z/RZ, they expose no RX/RY at all, and ZL/ZR arrive as
     * digital BUTTON_L2/BUTTON_R2 keys.
     *
     * Requiring RX/RY before claiming Z/RZ tells them apart. Without it a
     * Switch-style pad loses its right stick (RX/RY read a constant 0) and,
     * worse, the right stick drives the trigger axes: the first flick sets
     * leftTriggerAxisUsed, and from then on every digital ZL/ZR press is
     * discarded — the reported "los triggers no responden".
     */
    fun triggerAxesFor(
        hasLTrigger: Boolean,
        hasRTrigger: Boolean,
        hasBrake: Boolean,
        hasGas: Boolean,
        hasThrottle: Boolean,
        hasZ: Boolean,
        hasRz: Boolean,
        hasRx: Boolean,
        hasRy: Boolean,
    ): TriggerAxes = when {
        hasLTrigger && hasRTrigger -> TriggerAxes.LTRIGGER_RTRIGGER
        hasBrake && hasGas -> TriggerAxes.BRAKE_GAS
        hasBrake && hasThrottle -> TriggerAxes.BRAKE_THROTTLE
        hasZ && hasRz && hasRx && hasRy -> TriggerAxes.Z_RZ
        else -> TriggerAxes.DIGITAL
    }
}
