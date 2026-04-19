package com.limelight.jujostream.native_bridge

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.util.Log

/**
 * Queries hardware decoder capabilities to find the best codec
 * for a given resolution and frame rate. Uses PerformancePoint API
 * on Android 10+ and falls back to isSizeSupported/areSizeAndRateSupported
 * on older versions.
 */
object CodecProbe {
    private const val TAG = "CodecProbe"

    data class CodecScore(
        val codec: String,       // "H264", "H265", "AV1"
        val mime: String,        // MIME type
        val decoderName: String, // MediaCodec name
        val hwAccel: Boolean,
        val score: Int           // higher = better fit
    )

    private val codecCandidates = listOf(
        "H264" to "video/avc",
        "H265" to "video/hevc",
        "AV1"  to "video/av01"
    )

    /**
     * Returns a ranked list of codecs that can handle [width]x[height]@[fps].
     * Best candidate first. Empty list = nothing can handle it.
     */
    fun rankCodecs(width: Int, height: Int, fps: Int, hdr: Boolean): List<CodecScore> {
        val mcl = MediaCodecList(MediaCodecList.ALL_CODECS)
        val results = mutableListOf<CodecScore>()

        for ((tag, mime) in codecCandidates) {
            val best = findBestDecoder(mcl, mime, width, height, fps, hdr)
            if (best != null) results.add(best.copy(codec = tag))
        }

        results.sortByDescending { it.score }
        Log.i(TAG, "Codec ranking for ${width}x${height}@${fps}fps hdr=$hdr:")
        results.forEachIndexed { i, s ->
            Log.i(TAG, "  #$i ${s.codec} (${s.decoderName}) score=${s.score} hw=${s.hwAccel}")
        }
        return results
    }

    /**
     * Pick the single best codec for the target config. Returns codec tag
     * ("H264", "H265", "AV1") or null if nothing works.
     */
    fun selectBest(width: Int, height: Int, fps: Int, hdr: Boolean): String? {
        val ranked = rankCodecs(width, height, fps, hdr)
        return ranked.firstOrNull()?.codec
    }

    private fun findBestDecoder(
        mcl: MediaCodecList,
        mime: String,
        w: Int, h: Int, fps: Int,
        hdr: Boolean
    ): CodecScore? {
        var topScore = -1
        var topName = ""
        var topHw = false

        for (info in mcl.codecInfos) {
            if (info.isEncoder) continue

            val types = info.supportedTypes
            if (types.none { it.equals(mime, ignoreCase = true) }) continue

            val caps = try {
                info.getCapabilitiesForType(mime) ?: continue
            } catch (_: Exception) { continue }

            val vidCaps = caps.videoCapabilities ?: continue

            // Check basic resolution support
            if (!vidCaps.isSizeSupported(w, h)) continue

            // Check resolution + fps combo
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                if (!vidCaps.areSizeAndRateSupported(w, h, fps.toDouble())) continue
            }

            val isHw = isHardwareDecoder(info)
            var score = 0

            // hw decoders get big bonus
            if (isHw) score += 500

            // Codec efficiency tier bonus
            score += when (mime) {
                "video/av01" -> 300  // best compression
                "video/hevc" -> 200  // good compression
                "video/avc"  -> 100  // universal fallback
                else -> 0
            }

            // HDR compatibility bonus
            if (hdr && supportsHdr(caps)) score += 150

            // PerformancePoint headroom on API 29+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val headroom = measurePerfHeadroom(vidCaps, w, h, fps)
                score += headroom
            }

            if (score > topScore) {
                topScore = score
                topName = info.name
                topHw = isHw
            }
        }

        if (topScore < 0) return null
        return CodecScore(
            codec = "", // caller fills in
            mime = mime,
            decoderName = topName,
            hwAccel = topHw,
            score = topScore
        )
    }

    /**
     * Estimate headroom by probing progressively higher demands.
     * Uses areSizeAndRateSupported which works across all API levels.
     */
    private fun measurePerfHeadroom(
        vidCaps: MediaCodecInfo.VideoCapabilities,
        w: Int, h: Int, fps: Int
    ): Int {
        // Probe escalating demands to gauge spare capacity
        val probes = listOf(
            Triple(w, h, fps * 2),         // same res, 2x fps
            Triple(w * 3 / 2, h * 3 / 2, fps), // 1.5x res, same fps
            Triple(w * 2, h * 2, fps),     // 2x res, same fps
            Triple(w * 2, h * 2, fps * 2)  // 2x res, 2x fps
        )
        val scores = intArrayOf(50, 100, 150, 200)

        var best = 0
        for (i in probes.indices) {
            val (pw, ph, pf) = probes[i]
            try {
                if (vidCaps.areSizeAndRateSupported(pw, ph, pf.toDouble())) {
                    best = scores[i]
                }
            } catch (_: Exception) { /* size out of supported range */ }
        }
        return best
    }

    private fun isHardwareDecoder(info: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return info.isHardwareAccelerated
        }
        // Heuristic for older APIs
        val name = info.name.lowercase()
        return !name.contains("omx.google.") &&
               !name.contains("c2.android.") &&
               !name.startsWith("omx.sec.") // some Samsung SW decoders
    }

    private fun supportsHdr(caps: MediaCodecInfo.CodecCapabilities): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false

        val profiles = caps.profileLevels ?: return false
        for (pl in profiles) {
            // HEVC Main10 HDR / AV1 Main10
            if (pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 ||
                pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10) {
                return true
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (pl.profile == MediaCodecInfo.CodecProfileLevel.AV1ProfileMain10 ||
                    pl.profile == MediaCodecInfo.CodecProfileLevel.AV1ProfileMain10HDR10) {
                    return true
                }
            }
        }
        return false
    }

    /**
     * Returns a summary map suitable for sending over MethodChannel.
     */
    fun probeAsMap(width: Int, height: Int, fps: Int, hdr: Boolean): Map<String, Any> {
        val ranked = rankCodecs(width, height, fps, hdr)
        val best = ranked.firstOrNull()

        return mapOf(
            "bestCodec" to (best?.codec ?: "H264"),
            "bestDecoder" to (best?.decoderName ?: "unknown"),
            "hwAccelerated" to (best?.hwAccel ?: false),
            "rankings" to ranked.map { s ->
                mapOf(
                    "codec" to s.codec,
                    "decoder" to s.decoderName,
                    "hw" to s.hwAccel,
                    "score" to s.score
                )
            }
        )
    }
}
