package com.limelight.jujostream.native_bridge

/**
 * Produces one internally consistent codec contract for RTSP negotiation and MediaCodec.
 * The server must never receive a format bit that has no matching decoder in this decision.
 */
object CodecAdvertisementPolicy {
    data class DecoderCandidate(
        val codec: String,
        val mime: String,
        val decoderName: String,
    )

    data class Decision(
        val effectiveCodec: String,
        val decodersByMime: Map<String, String>,
        val supportedVideoFormats: Int,
        val fallbackReason: String? = null,
    )

    fun decide(
        requestedCodec: String,
        autoSelectedCodec: String,
        weakDevice: Boolean,
        enableHdr: Boolean,
        candidates: List<DecoderCandidate>,
    ): Decision {
        val uniqueCandidates = candidates
            .map { it.copy(codec = normalize(it.codec)) }
            .distinctBy { it.codec }
        val requested = normalize(requestedCodec)
        val isAuto = requestedCodec.equals("auto", ignoreCase = true)
        val preferred = when {
            weakDevice -> "H264"
            isAuto -> normalize(autoSelectedCodec)
            else -> requested
        }

        val selected = uniqueCandidates.firstOrNull { it.codec == preferred }
            ?: uniqueCandidates.firstOrNull { it.codec == "H264" }
            ?: uniqueCandidates.firstOrNull()

        // H.264 remains the native library's universal last resort if probing yielded no
        // candidates. On real Android TV hardware a clear AVC decoder is mandatory.
        val effective = selected?.codec ?: "H264"
        val fallbackReason = when {
            weakDevice && effective != requested -> "weak_device_h264_safety"
            selected == null -> "no_proven_decoder"
            effective != preferred -> "requested_decoder_unavailable"
            else -> null
        }

        val advertised = if (isAuto && !weakDevice) {
            uniqueCandidates
        } else {
            selected?.let(::listOf).orEmpty()
        }
        val decoderMap = advertised.associate { it.mime to it.decoderName }
        val formatMask = advertised.fold(0) { mask, candidate ->
            mask or StreamConstants.videoFormatFor(candidate.codec, enableHdr)
        }.let { if (it == 0) StreamConstants.videoFormatFor(effective, enableHdr) else it }

        return Decision(
            effectiveCodec = effective,
            decodersByMime = decoderMap,
            supportedVideoFormats = formatMask,
            fallbackReason = fallbackReason,
        )
    }

    private fun normalize(codec: String): String = when (codec.uppercase()) {
        "HEVC", "H.265", "H265" -> "H265"
        "AV1", "AV01" -> "AV1"
        else -> "H264"
    }
}
