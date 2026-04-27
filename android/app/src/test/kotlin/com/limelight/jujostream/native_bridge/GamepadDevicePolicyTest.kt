package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertFalse
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
}
