package com.limelight.jujostream.native_bridge

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.util.Log

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

            if (!vidCaps.isSizeSupported(w, h)) continue

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                if (!vidCaps.areSizeAndRateSupported(w, h, fps.toDouble())) continue
            }

            val isHw = isHardwareDecoder(info)
            var score = 0

            if (isHw) score += 500
            score += when (mime) {
                "video/av01" -> 300  // best compression
                "video/hevc" -> 200  // good compression
                "video/avc"  -> 100  // universal fallback
                else -> 0
            }

            if (hdr && supportsHdr(caps)) score += 150

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
            codec = "",
            mime = mime,
            decoderName = topName,
            hwAccel = topHw,
            score = topScore
        )
    }

    private fun measurePerfHeadroom(
        vidCaps: MediaCodecInfo.VideoCapabilities,
        w: Int, h: Int, fps: Int
    ): Int {
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
        val name = info.name.lowercase()
        return !name.contains("omx.google.") &&
               !name.contains("c2.android.") &&
               !name.startsWith("omx.sec.")
    }

    private fun supportsHdr(caps: MediaCodecInfo.CodecCapabilities): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false

        val profiles = caps.profileLevels ?: return false
        for (pl in profiles) {
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
