package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GamepadDevicePolicyTest {

    @Test
    fun `Nintendo Switch Pro style controllers are not gated by Joy-Con opt-in`() {
        assertFalse(
            GamepadDevicePolicy.requiresJoyConOptIn(
                vendorId = 0x057e,
                deviceName = "Nintendo Switch Pro Controller",
            )
        )
    }

    @Test
    fun `split Joy-Con devices remain gated by Joy-Con opt-in`() {
        assertTrue(
            GamepadDevicePolicy.requiresJoyConOptIn(
                vendorId = 0x057e,
                deviceName = "Joy-Con (L)",
            )
        )
        assertTrue(
            GamepadDevicePolicy.requiresJoyConOptIn(
                vendorId = 0x057e,
                deviceName = "Nintendo Joy-Con (R)",
            )
        )
    }

    // A Switch-style pad (real Pro Controller and the ONIKUMA-class clones
    // that emulate one): right stick on Z/RZ, no RX/RY, ZL/ZR as digital keys.
    @Test
    fun `Switch-style pad keeps Z-RZ as the right stick and uses digital triggers`() {
        assertEquals(
            GamepadDevicePolicy.TriggerAxes.DIGITAL,
            GamepadDevicePolicy.triggerAxesFor(
                hasLTrigger = false, hasRTrigger = false,
                hasBrake = false, hasGas = false, hasThrottle = false,
                hasZ = true, hasRz = true,
                hasRx = false, hasRy = false,
            )
        )
    }

    // The old Xbox/Linux layout: LT on Z, RT on RZ, right stick moved to RX/RY.
    @Test
    fun `Z-RZ are triggers only when RX-RY carry the right stick`() {
        assertEquals(
            GamepadDevicePolicy.TriggerAxes.Z_RZ,
            GamepadDevicePolicy.triggerAxesFor(
                hasLTrigger = false, hasRTrigger = false,
                hasBrake = false, hasGas = false, hasThrottle = false,
                hasZ = true, hasRz = true,
                hasRx = true, hasRy = true,
            )
        )
    }

    @Test
    fun `dedicated trigger axes win over every fallback`() {
        assertEquals(
            GamepadDevicePolicy.TriggerAxes.LTRIGGER_RTRIGGER,
            GamepadDevicePolicy.triggerAxesFor(
                hasLTrigger = true, hasRTrigger = true,
                hasBrake = true, hasGas = true, hasThrottle = true,
                hasZ = true, hasRz = true,
                hasRx = true, hasRy = true,
            )
        )
    }

    @Test
    fun `pedal axes are used when no dedicated trigger axis exists`() {
        assertEquals(
            GamepadDevicePolicy.TriggerAxes.BRAKE_GAS,
            GamepadDevicePolicy.triggerAxesFor(
                hasLTrigger = false, hasRTrigger = false,
                hasBrake = true, hasGas = true, hasThrottle = false,
                hasZ = false, hasRz = false, hasRx = false, hasRy = false,
            )
        )
        assertEquals(
            GamepadDevicePolicy.TriggerAxes.BRAKE_THROTTLE,
            GamepadDevicePolicy.triggerAxesFor(
                hasLTrigger = false, hasRTrigger = false,
                hasBrake = true, hasGas = false, hasThrottle = true,
                hasZ = false, hasRz = false, hasRx = false, hasRy = false,
            )
        )
    }

    @Test
    fun `button identity separates a mirrored macro button from the real one`() {
        // Same keyCode, different scanCode: a rear button preset to mirror A.
        assertNotEquals(
            GamepadDevicePolicy.buttonKey(keyCode = 96, scanCode = 304),
            GamepadDevicePolicy.buttonKey(keyCode = 96, scanCode = 656),
        )
        assertEquals(
            GamepadDevicePolicy.buttonKey(keyCode = 96, scanCode = 304),
            GamepadDevicePolicy.buttonKey(keyCode = 96, scanCode = 304),
        )
    }
}
