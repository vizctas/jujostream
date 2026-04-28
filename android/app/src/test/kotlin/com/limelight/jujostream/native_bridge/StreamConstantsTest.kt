package com.limelight.jujostream.native_bridge

import org.junit.Assert.*
import org.junit.Test

/**
 * Local JVM unit tests for StreamConstants.
 * No Android framework required — pure Kotlin logic.
 */
class StreamConstantsTest {

    // ── videoFormatFor ──────────────────────────────────────────────────

    @Test
    fun `videoFormatFor H264 returns H264 bitmask regardless of HDR`() {
        assertEquals(StreamConstants.VIDEO_FORMAT_H264, StreamConstants.videoFormatFor("H264", false))
        assertEquals(StreamConstants.VIDEO_FORMAT_H264, StreamConstants.videoFormatFor("H264", true))
    }

    @Test
    fun `videoFormatFor H265 SDR returns H265 bitmask`() {
        assertEquals(StreamConstants.VIDEO_FORMAT_H265, StreamConstants.videoFormatFor("H265", false))
    }

    @Test
    fun `videoFormatFor H265 HDR returns combined SDR+HDR bitmask`() {
        val expected = StreamConstants.VIDEO_FORMAT_H265 or StreamConstants.VIDEO_FORMAT_H265_HDR
        assertEquals(expected, StreamConstants.videoFormatFor("H265", true))
    }

    @Test
    fun `videoFormatFor AV1 SDR returns AV1 bitmask`() {
        assertEquals(StreamConstants.VIDEO_FORMAT_AV1, StreamConstants.videoFormatFor("AV1", false))
    }

    @Test
    fun `videoFormatFor AV1 HDR returns combined SDR+HDR bitmask`() {
        val expected = StreamConstants.VIDEO_FORMAT_AV1 or StreamConstants.VIDEO_FORMAT_AV1_HDR
        assertEquals(expected, StreamConstants.videoFormatFor("AV1", true))
    }

    @Test
    fun `videoFormatFor unknown codec falls back to H264`() {
        assertEquals(StreamConstants.VIDEO_FORMAT_H264, StreamConstants.videoFormatFor("VP9", false))
        assertEquals(StreamConstants.VIDEO_FORMAT_H264, StreamConstants.videoFormatFor("", false))
    }

    // ── mimeTypeForFormat ───────────────────────────────────────────────

    @Test
    fun `mimeTypeForFormat resolves H264`() {
        assertEquals("video/avc", StreamConstants.mimeTypeForFormat(StreamConstants.VIDEO_FORMAT_H264))
    }

    @Test
    fun `mimeTypeForFormat resolves H265`() {
        assertEquals("video/hevc", StreamConstants.mimeTypeForFormat(StreamConstants.VIDEO_FORMAT_H265))
    }

    @Test
    fun `mimeTypeForFormat resolves H265 HDR`() {
        // H265_HDR (0x0F00) has the H265 bit (0x0100) set
        assertEquals("video/hevc", StreamConstants.mimeTypeForFormat(StreamConstants.VIDEO_FORMAT_H265_HDR))
    }

    @Test
    fun `mimeTypeForFormat resolves AV1`() {
        assertEquals("video/av01", StreamConstants.mimeTypeForFormat(StreamConstants.VIDEO_FORMAT_AV1))
    }

    @Test
    fun `mimeTypeForFormat resolves AV1 HDR`() {
        // AV1_HDR (0xF000) has the AV1 bit (0x1000) set
        assertEquals("video/av01", StreamConstants.mimeTypeForFormat(StreamConstants.VIDEO_FORMAT_AV1_HDR))
    }

    @Test
    fun `mimeTypeForFormat returns null for unknown format`() {
        assertNull(StreamConstants.mimeTypeForFormat(0))
        assertNull(StreamConstants.mimeTypeForFormat(0x0002))
    }

    // ── audioConfigFor ──────────────────────────────────────────────────

    @Test
    fun `audioConfigFor stereo`() {
        assertEquals(StreamConstants.AUDIO_CONFIG_STEREO, StreamConstants.audioConfigFor("stereo"))
    }

    @Test
    fun `audioConfigFor surround51`() {
        assertEquals(StreamConstants.AUDIO_CONFIG_SURROUND51, StreamConstants.audioConfigFor("surround51"))
    }

    @Test
    fun `audioConfigFor surround71`() {
        assertEquals(StreamConstants.AUDIO_CONFIG_SURROUND71, StreamConstants.audioConfigFor("surround71"))
    }

    @Test
    fun `audioConfigFor unknown falls back to stereo`() {
        assertEquals(StreamConstants.AUDIO_CONFIG_STEREO, StreamConstants.audioConfigFor("mono"))
        assertEquals(StreamConstants.AUDIO_CONFIG_STEREO, StreamConstants.audioConfigFor(""))
    }

    // ── Bitmask integrity ───────────────────────────────────────────────

    @Test
    fun `video format bitmasks do not overlap between codec families`() {
        // H264 bit should not be set in H265 or AV1 masks
        assertEquals(0, StreamConstants.VIDEO_FORMAT_H265 and StreamConstants.VIDEO_FORMAT_H264)
        assertEquals(0, StreamConstants.VIDEO_FORMAT_AV1 and StreamConstants.VIDEO_FORMAT_H264)
        // H265 and AV1 should not overlap
        assertEquals(0, StreamConstants.VIDEO_FORMAT_H265 and StreamConstants.VIDEO_FORMAT_AV1)
    }

    @Test
    fun `HDR videoFormatFor includes SDR base bits`() {
        // When HDR is requested, the returned bitmask must include the SDR base bit
        val h265Hdr = StreamConstants.videoFormatFor("H265", true)
        assertNotEquals(0, h265Hdr and StreamConstants.VIDEO_FORMAT_H265)
        assertNotEquals(0, h265Hdr and StreamConstants.VIDEO_FORMAT_H265_HDR)
        val av1Hdr = StreamConstants.videoFormatFor("AV1", true)
        assertNotEquals(0, av1Hdr and StreamConstants.VIDEO_FORMAT_AV1)
        assertNotEquals(0, av1Hdr and StreamConstants.VIDEO_FORMAT_AV1_HDR)
    }

    // ── Network defaults ────────────────────────────────────────────────

    @Test
    fun `default packet size is within valid MTU range`() {
        assertTrue(StreamConstants.DEFAULT_PACKET_SIZE in 500..1500)
    }

    @Test
    fun `streaming remotely auto is 2`() {
        assertEquals(2, StreamConstants.STREAMING_REMOTELY_AUTO)
    }
}
