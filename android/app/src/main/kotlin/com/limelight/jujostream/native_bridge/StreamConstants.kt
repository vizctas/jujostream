package com.limelight.jujostream.native_bridge


object StreamConstants {

    const val VIDEO_FORMAT_H264      = 0x0001
    const val VIDEO_FORMAT_H265      = 0x0100
    const val VIDEO_FORMAT_H265_HDR  = 0x0200 // HEVC Main10 Profile
    const val VIDEO_FORMAT_AV1       = 0x1000 // AV1 Main 8-bit profile
    const val VIDEO_FORMAT_AV1_HDR   = 0x2000 // AV1 Main 10-bit profile

    /** Resolve the video format bitmask for a codec tag + HDR flag. */
    fun videoFormatFor(codec: String, hdr: Boolean): Int = when (codec) {
        "H265" -> if (hdr) VIDEO_FORMAT_H265_HDR else VIDEO_FORMAT_H265
        "AV1"  -> if (hdr) VIDEO_FORMAT_AV1_HDR  else VIDEO_FORMAT_AV1
        else   -> VIDEO_FORMAT_H264
    }

    fun mimeTypeForFormat(videoFormat: Int): String? = when {
        videoFormat and VIDEO_FORMAT_H264 != 0 -> "video/avc"
        videoFormat and (VIDEO_FORMAT_H265 or VIDEO_FORMAT_H265_HDR) != 0 -> "video/hevc"
        videoFormat and (VIDEO_FORMAT_AV1 or VIDEO_FORMAT_AV1_HDR) != 0 -> "video/av01"
        else -> null
    }


    const val AUDIO_CONFIG_STEREO     = 0x000302CA
    const val AUDIO_CONFIG_SURROUND51 = 0x003F06CA
    const val AUDIO_CONFIG_SURROUND71 = 0x063F08CA

    fun audioConfigFor(tag: String): Int = when (tag) {
        "surround51" -> AUDIO_CONFIG_SURROUND51
        "surround71" -> AUDIO_CONFIG_SURROUND71
        else         -> AUDIO_CONFIG_STEREO
    }

    const val DEFAULT_PACKET_SIZE = 1392
    const val STREAMING_REMOTELY_AUTO = 2
}
