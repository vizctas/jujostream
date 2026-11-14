package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Test

class SliceDeliveryPolicyTest {
    @Test
    fun `enables 4 slices only for h264 or hevc at 4k or 3_4 4k`() {
        assertEquals(4, SliceDeliveryPolicy.recommendedSlices(3840, 2160, "H264"))
        assertEquals(4, SliceDeliveryPolicy.recommendedSlices(3840, 2160, "H265"))
        assertEquals(4, SliceDeliveryPolicy.recommendedSlices(2880, 2160, "HEVC"))
        assertEquals(4 shl 24, SliceDeliveryPolicy.capabilityMask(3840, 2160, "H265"))
    }

    @Test
    fun `disables slices below 3_4 4k and for av1`() {
        assertEquals(1, SliceDeliveryPolicy.recommendedSlices(2560, 1440, "H265"))
        assertEquals(0, SliceDeliveryPolicy.capabilityMask(1920, 1080, "H264"))
        assertEquals(1, SliceDeliveryPolicy.recommendedSlices(3840, 2160, "AV1"))
        assertEquals(0, SliceDeliveryPolicy.capabilityMask(3840, 2160, "AV1"))
    }
}
