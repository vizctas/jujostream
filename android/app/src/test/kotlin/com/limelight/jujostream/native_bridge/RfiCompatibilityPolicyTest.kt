package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RfiCompatibilityPolicyTest {
    @Test
    fun `disabled opt-in always returns zero capabilities`() {
        assertEquals(
            0,
            RfiCompatibilityPolicy.capabilityMask(
                enableRfi = false,
                codec = "H265",
                decoderName = "c2.qti.hevc.decoder.low_latency",
                mimeType = "video/hevc",
                hardware = "qcom",
                board = "kalama",
                sdkInt = 34,
                isHdr = false,
            ),
        )
    }

    @Test
    fun `blocks amlogic dolby vision legacy omx and pre-api30 tegra decoders`() {
        assertFalse(
            RfiCompatibilityPolicy.supportsRfi(
                enableRfi = true,
                decoderName = "c2.amlogic.hevc.decoder",
                mimeType = "video/hevc",
                hardware = "amlogic",
                board = "franklin",
                sdkInt = 33,
                isHdr = false,
            ),
        )
        assertFalse(
            RfiCompatibilityPolicy.supportsRfi(
                enableRfi = true,
                decoderName = "c2.qti.dv.decoder",
                mimeType = "video/dolby-vision",
                hardware = "qcom",
                board = "lahaina",
                sdkInt = 34,
                isHdr = true,
            ),
        )
        assertFalse(
            RfiCompatibilityPolicy.supportsRfi(
                enableRfi = true,
                decoderName = "OMX.qcom.video.decoder.avc",
                mimeType = "video/avc",
                hardware = "qcom",
                board = "msm8998",
                sdkInt = 31,
                isHdr = false,
            ),
        )
        assertFalse(
            RfiCompatibilityPolicy.supportsRfi(
                enableRfi = true,
                decoderName = "c2.nvidia.hevc.decoder",
                mimeType = "video/hevc",
                hardware = "tegra",
                board = "darcy",
                sdkInt = 29,
                isHdr = false,
            ),
        )
    }

    @Test
    fun `allows modern non-blacklisted codecs when opt-in enabled`() {
        assertTrue(
            RfiCompatibilityPolicy.supportsRfi(
                enableRfi = true,
                decoderName = "c2.nvidia.hevc.decoder",
                mimeType = "video/hevc",
                hardware = "tegra",
                board = "mdarcy",
                sdkInt = 30,
                isHdr = false,
            ),
        )
        assertEquals(
            RfiCompatibilityPolicy.CAP_REFERENCE_FRAME_INVALIDATION_AVC,
            RfiCompatibilityPolicy.capabilityMask(
                enableRfi = true,
                codec = "H264",
                decoderName = "c2.qti.avc.decoder.low_latency",
                mimeType = "video/avc",
                hardware = "qcom",
                board = "pineapple",
                sdkInt = 34,
                isHdr = false,
            ),
        )
        assertEquals(
            RfiCompatibilityPolicy.CAP_REFERENCE_FRAME_INVALIDATION_HEVC,
            RfiCompatibilityPolicy.capabilityMask(
                enableRfi = true,
                codec = "H265",
                decoderName = "c2.mtk.hevc.decoder.low_latency",
                mimeType = "video/hevc",
                hardware = "mt6893",
                board = "k6893",
                sdkInt = 33,
                isHdr = true,
            ),
        )
        assertEquals(
            RfiCompatibilityPolicy.CAP_REFERENCE_FRAME_INVALIDATION_AV1,
            RfiCompatibilityPolicy.capabilityMask(
                enableRfi = true,
                codec = "AV1",
                decoderName = "c2.exynos.av1.decoder",
                mimeType = "video/av01",
                hardware = "exynos2400",
                board = "s5e9945",
                sdkInt = 34,
                isHdr = false,
            ),
        )
    }
}
