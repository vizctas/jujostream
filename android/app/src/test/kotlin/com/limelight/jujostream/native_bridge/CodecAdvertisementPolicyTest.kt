package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CodecAdvertisementPolicyTest {
    private val candidates = listOf(
        CodecAdvertisementPolicy.DecoderCandidate("H264", "video/avc", "avc.decoder"),
        CodecAdvertisementPolicy.DecoderCandidate("H265", "video/hevc", "hevc.decoder"),
        CodecAdvertisementPolicy.DecoderCandidate("AV1", "video/av01", "av1.decoder"),
    )

    @Test
    fun `explicit codec advertises only the selected decoder contract`() {
        val decision = CodecAdvertisementPolicy.decide(
            requestedCodec = "H265",
            autoSelectedCodec = "AV1",
            weakDevice = false,
            enableHdr = false,
            candidates = candidates,
        )

        assertEquals("H265", decision.effectiveCodec)
        assertEquals(mapOf("video/hevc" to "hevc.decoder"), decision.decodersByMime)
        assertEquals(StreamConstants.VIDEO_FORMAT_H265, decision.supportedVideoFormats)
    }

    @Test
    fun `weak devices use one h264 contract even when an advanced codec was requested`() {
        val decision = CodecAdvertisementPolicy.decide(
            requestedCodec = "AV1",
            autoSelectedCodec = "AV1",
            weakDevice = true,
            enableHdr = true,
            candidates = candidates,
        )

        assertEquals("H264", decision.effectiveCodec)
        assertEquals(mapOf("video/avc" to "avc.decoder"), decision.decodersByMime)
        assertEquals(StreamConstants.VIDEO_FORMAT_H264, decision.supportedVideoFormats)
    }

    @Test
    fun `auto advertises all proven decoders and keeps its preferred format`() {
        val decision = CodecAdvertisementPolicy.decide(
            requestedCodec = "auto",
            autoSelectedCodec = "AV1",
            weakDevice = false,
            enableHdr = true,
            candidates = candidates,
        )

        assertEquals("AV1", decision.effectiveCodec)
        assertEquals(3, decision.decodersByMime.size)
        assertTrue(decision.supportedVideoFormats and StreamConstants.VIDEO_FORMAT_H264 != 0)
        assertTrue(decision.supportedVideoFormats and StreamConstants.VIDEO_FORMAT_H265_HDR != 0)
        assertTrue(decision.supportedVideoFormats and StreamConstants.VIDEO_FORMAT_AV1_HDR != 0)
    }

    @Test
    fun `missing explicit decoder falls back to proven h264`() {
        val decision = CodecAdvertisementPolicy.decide(
            requestedCodec = "AV1",
            autoSelectedCodec = "AV1",
            weakDevice = false,
            enableHdr = false,
            candidates = candidates.take(2),
        )

        assertEquals("H264", decision.effectiveCodec)
        assertEquals(mapOf("video/avc" to "avc.decoder"), decision.decodersByMime)
        assertEquals("requested_decoder_unavailable", decision.fallbackReason)
    }
}
