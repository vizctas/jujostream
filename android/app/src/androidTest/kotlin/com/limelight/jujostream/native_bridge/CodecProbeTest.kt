package com.limelight.jujostream.native_bridge

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumented tests for CodecProbe.
 * Must run on a real device or emulator (uses MediaCodecList).
 *
 * Run with: ./gradlew connectedAndroidTest
 */
@RunWith(AndroidJUnit4::class)
class CodecProbeTest {

    // ── rankCodecs ──────────────────────────────────────────────────────

    @Test
    fun rankCodecs_1080p60_returnsNonEmpty() {
        val ranked = CodecProbe.rankCodecs(1920, 1080, 60, hdr = false)
        assertTrue("Device must support at least one codec for 1080p60", ranked.isNotEmpty())
    }

    @Test
    fun rankCodecs_1080p60_firstIsHardware() {
        val ranked = CodecProbe.rankCodecs(1920, 1080, 60, hdr = false)
        if (ranked.isNotEmpty()) {
            assertTrue("Best codec should be HW-accelerated", ranked.first().hwAccel)
        }
    }

    @Test
    fun rankCodecs_1080p60_alwaysIncludesH264() {
        val ranked = CodecProbe.rankCodecs(1920, 1080, 60, hdr = false)
        val hasH264 = ranked.any { it.codec == "H264" }
        assertTrue("H264 must be supported on all Android devices", hasH264)
    }

    @Test
    fun rankCodecs_scoresDescending() {
        val ranked = CodecProbe.rankCodecs(1920, 1080, 60, hdr = false)
        for (i in 0 until ranked.size - 1) {
            assertTrue(
                "Rankings must be sorted descending by score",
                ranked[i].score >= ranked[i + 1].score
            )
        }
    }

    @Test
    fun rankCodecs_720p30_returnsNonEmpty() {
        val ranked = CodecProbe.rankCodecs(1280, 720, 30, hdr = false)
        assertTrue("720p30 should be universally supported", ranked.isNotEmpty())
    }

    // ── selectBest ──────────────────────────────────────────────────────

    @Test
    fun selectBest_1080p60_returnsValidCodec() {
        val best = CodecProbe.selectBest(1920, 1080, 60, hdr = false)
        assertNotNull("selectBest must return a codec for 1080p60", best)
        assertTrue(
            "selectBest must return H264, H265, or AV1",
            best in listOf("H264", "H265", "AV1")
        )
    }

    @Test
    fun selectBest_4k60_returnsNullOrValid() {
        // 4K60 may not be supported on all devices
        val best = CodecProbe.selectBest(3840, 2160, 60, hdr = false)
        if (best != null) {
            assertTrue(best in listOf("H264", "H265", "AV1"))
        }
    }

    // ── probeAsMap ──────────────────────────────────────────────────────

    @Test
    fun probeAsMap_containsRequiredKeys() {
        val map = CodecProbe.probeAsMap(1920, 1080, 60, hdr = false)
        assertTrue(map.containsKey("bestCodec"))
        assertTrue(map.containsKey("bestDecoder"))
        assertTrue(map.containsKey("hwAccelerated"))
        assertTrue(map.containsKey("rankings"))
    }

    @Test
    fun probeAsMap_bestCodecIsString() {
        val map = CodecProbe.probeAsMap(1920, 1080, 60, hdr = false)
        val bestCodec = map["bestCodec"]
        assertTrue("bestCodec must be a String", bestCodec is String)
        assertTrue(
            "bestCodec must be H264, H265, or AV1",
            bestCodec in listOf("H264", "H265", "AV1")
        )
    }

    @Test
    fun probeAsMap_rankingsIsList() {
        val map = CodecProbe.probeAsMap(1920, 1080, 60, hdr = false)
        val rankings = map["rankings"]
        assertTrue("rankings must be a List", rankings is List<*>)
        @Suppress("UNCHECKED_CAST")
        val list = rankings as List<Map<String, Any>>
        assertTrue("rankings must not be empty", list.isNotEmpty())
        // Each entry must have codec, decoder, hw, score
        val first = list.first()
        assertTrue(first.containsKey("codec"))
        assertTrue(first.containsKey("decoder"))
        assertTrue(first.containsKey("hw"))
        assertTrue(first.containsKey("score"))
    }

    // ── CodecScore contract ───────────────���─────────────────────────────

    @Test
    fun codecScore_hwDecoderScoresHigherThanSw() {
        val ranked = CodecProbe.rankCodecs(1920, 1080, 60, hdr = false)
        val hwScores = ranked.filter { it.hwAccel }.map { it.score }
        val swScores = ranked.filter { !it.hwAccel }.map { it.score }
        if (hwScores.isNotEmpty() && swScores.isNotEmpty()) {
            assertTrue(
                "HW decoder score should exceed SW decoder score",
                hwScores.max() > swScores.max()
            )
        }
    }

    @Test
    fun codecScore_decoderNameNotEmpty() {
        val ranked = CodecProbe.rankCodecs(1920, 1080, 60, hdr = false)
        for (entry in ranked) {
            assertTrue(
                "Decoder name must not be empty for ${entry.codec}",
                entry.decoderName.isNotEmpty()
            )
        }
    }

    @Test
    fun codecScore_mimeMatchesCodecTag() {
        val ranked = CodecProbe.rankCodecs(1920, 1080, 60, hdr = false)
        for (entry in ranked) {
            val expectedMime = when (entry.codec) {
                "H264" -> "video/avc"
                "H265" -> "video/hevc"
                "AV1" -> "video/av01"
                else -> fail("Unexpected codec tag: ${entry.codec}")
            }
            assertEquals(
                "MIME must match codec tag for ${entry.codec}",
                expectedMime,
                entry.mime
            )
        }
    }
}
