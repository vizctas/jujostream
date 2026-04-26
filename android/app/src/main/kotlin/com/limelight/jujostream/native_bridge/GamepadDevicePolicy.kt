package com.limelight.jujostream.native_bridge

internal object GamepadDevicePolicy {
    fun requiresJoyConOptIn(vendorId: Int, deviceName: String?): Boolean {
        val name = deviceName?.lowercase() ?: ""
        return name.contains("joy-con") || name.contains("joycon")
    }
}
