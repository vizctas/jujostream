package com.limelight.jujostream.native_bridge

/**
 * Computes CAPABILITY_SLICES_PER_FRAME bits for StreamConfiguration/VideoCallbacks.
 * Activates 4 slices only at >= 3/4 4K (6,220,800 px) for H.264/HEVC; never AV1.
 */
object SliceDeliveryPolicy {
    const val MIN_4K_SLICE_PIXELS = 6_220_800L
    const val RECOMMENDED_4K_SLICES = 4

    fun recommendedSlices(width: Int, height: Int, codec: String): Int {
        if (width <= 0 || height <= 0) return 1
        if (codec.equals("AV1", ignoreCase = true)) return 1
        val supported = codec.equals("H264", ignoreCase = true) ||
            codec.equals("H265", ignoreCase = true) ||
            codec.equals("HEVC", ignoreCase = true)
        if (!supported) return 1
        return if (width.toLong() * height.toLong() >= MIN_4K_SLICE_PIXELS) {
            RECOMMENDED_4K_SLICES
        } else {
            1
        }
    }

    fun capabilityMask(width: Int, height: Int, codec: String): Int {
        val slices = recommendedSlices(width, height, codec)
        return if (slices > 1) (slices and 0xFF) shl 24 else 0
    }
}
