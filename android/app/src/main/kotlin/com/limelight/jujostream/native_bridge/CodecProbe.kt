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

    fun safeDecoderNameForMime(mime: String, width: Int, height: Int, fps: Int, hdr: Boolean): String? {
        val mcl = MediaCodecList(MediaCodecList.ALL_CODECS)
        return findBestDecoder(mcl, mime, width, height, fps, hdr)?.decoderName
    }

    /**
     * Two-pass decoder selection (modeled after moonlight-android's findKnownSafeDecoder):
     *
     * Pass 1: Only consider decoders that advertise FEATURE_LowLatency.
     *   These are guaranteed to output frames immediately in streaming mode.
     *   On Tensor/Exynos, the low-latency variant (e.g. c2.exynos.*.decoder.low_latency)
     *   is listed AFTER the standard one — this two-pass approach ensures we pick it.
     *
     * Pass 2: If no FEATURE_LowLatency decoder found, consider all HW decoders.
     *   Vendor low-latency keys (vdec-lowlatency, vendor.rtc-ext-dec-low-latency.enable)
     *   will be applied at configure() time by VideoDecoderRenderer.
     *
     * This prevents selecting a decoder that silently buffers frames (black screen).
     */
    private fun findBestDecoder(
        mcl: MediaCodecList,
        mime: String,
        w: Int, h: Int, fps: Int,
        hdr: Boolean
    ): CodecScore? {
        // Pass 1: prefer decoders with FEATURE_LowLatency
        val pass1 = findBestDecoderInternal(mcl, mime, w, h, fps, hdr, requireLowLatency = true)
        if (pass1 != null) {
            Log.i(TAG, "Pass 1 (FEATURE_LowLatency): selected ${pass1.decoderName} score=${pass1.score}")
            return pass1
        }

        // Pass 2: all eligible HW decoders
        val pass2 = findBestDecoderInternal(mcl, mime, w, h, fps, hdr, requireLowLatency = false)
        if (pass2 != null) {
            Log.i(TAG, "Pass 2 (all HW): selected ${pass2.decoderName} score=${pass2.score}")
        }
        return pass2
    }

    private fun findBestDecoderInternal(
        mcl: MediaCodecList,
        mime: String,
        w: Int, h: Int, fps: Int,
        hdr: Boolean,
        requireLowLatency: Boolean
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

            if (!isClearPlaybackDecoder(info, caps)) continue

            // Pass 1 filter: only decoders that advertise FEATURE_LowLatency
            if (requireLowLatency && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val hasLowLatency = try {
                    caps.isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency)
                } catch (_: Exception) { false }
                if (!hasLowLatency) continue
            } else if (requireLowLatency) {
                // FEATURE_LowLatency not available before Android R — skip pass 1
                continue
            }

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

            // Bonus for FEATURE_LowLatency support (even in pass 2)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val hasLowLatency = try {
                    caps.isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency)
                } catch (_: Exception) { false }
                if (hasLowLatency) score += 250
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

    private fun isClearPlaybackDecoder(
        info: MediaCodecInfo,
        caps: MediaCodecInfo.CodecCapabilities
    ): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && info.isAlias) {
            return false
        }

        val decoderName = info.name.lowercase()
        if (decoderName.contains(".secure") || decoderName.contains(".tunneled")) {
            return false
        }

        return try {
            val requiresSecure = caps.isFeatureRequired(
                MediaCodecInfo.CodecCapabilities.FEATURE_SecurePlayback)
            // Tunneled-playback decoders (e.g. some MediaTek/Dimensity .tunneled variants)
            // require a HW_AV_SYNC_ID that streaming apps never provide. They will accept
            // CSD + frames but render zero output — same black-screen symptom as .secure.
            val requiresTunneled = caps.isFeatureRequired(
                MediaCodecInfo.CodecCapabilities.FEATURE_TunneledPlayback)
            !requiresSecure && !requiresTunneled
        } catch (_: Exception) {
            true
        }
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
