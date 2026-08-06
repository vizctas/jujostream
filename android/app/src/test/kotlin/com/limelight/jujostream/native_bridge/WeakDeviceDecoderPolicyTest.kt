package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Test

class WeakDeviceDecoderPolicyTest {

    @Test
    fun `weak Amlogic decoder receives actual 60 fps operating rate`() {
        val policy = WeakDeviceDecoderPolicy.forDecoder(
            redrawRate = 60,
            isAmlogicDecoder = true,
        )

        assertEquals(60f, policy.operatingRate)
        assertEquals(0, policy.priority)
    }

    @Test
    fun `weak non-Amlogic decoder preserves Fire TV rate budget`() {
        val policy = WeakDeviceDecoderPolicy.forDecoder(
            redrawRate = 60,
            isAmlogicDecoder = false,
        )

        assertEquals(30f, policy.operatingRate)
        assertEquals(1, policy.priority)
    }

    @Test
    fun `weak non-Amlogic rate never exceeds low frame rate content`() {
        val policy = WeakDeviceDecoderPolicy.forDecoder(
            redrawRate = 24,
            isAmlogicDecoder = false,
        )

        assertEquals(24f, policy.operatingRate)
    }
}
