package com.limelight.jujostream.native_bridge

/**
 * Hardware decoder errata gate for Reference Frame Invalidation (RFI / LI_CAP_REFERENCE_FRAME_INVALIDATION).
 * Blocks decoders known to corrupt frames or hang on dynamically invalidated DPB entries:
 *   - Amlogic MediaCodec decoders (known DPB/NAL corruption under RFI)
 *   - Dolby Vision decoders / profiles (non-standard HDR reference signaling)
 *   - Legacy OMX (`omx.*`) software/vendor shims without MediaCodec2/C2 guarantees
 *   - NVIDIA Tegra / Shield on Android API < 30 (pre-Android 11 driver errata)
 */
object RfiCompatibilityPolicy {
    const val CAP_REFERENCE_FRAME_INVALIDATION_AVC = 1
    const val CAP_REFERENCE_FRAME_INVALIDATION_HEVC = 2
    const val CAP_REFERENCE_FRAME_INVALIDATION_AV1 = 4

    fun supportsRfi(
        enableRfi: Boolean,
        decoderName: String,
        mimeType: String,
        hardware: String,
        board: String,
        sdkInt: Int,
        isHdr: Boolean,
    ): Boolean {
        if (!enableRfi) {
            return false
        }
        val dec = decoderName.lowercase()
        val mime = mimeType.lowercase()
        val hw = hardware.lowercase()
        val brd = board.lowercase()

        // Legacy OpenMAX decoders lack reliable DPB invalidation handling.
        if (dec.startsWith("omx.")) {
            return false
        }
        // Amlogic MediaCodec decoders exhibit corruption/freezes with dynamic RFI.
        if (dec.contains("amlogic") || dec.contains(".am.") || hw.contains("amlogic") || brd.contains("amlogic")) {
            return false
        }
        // Dolby Vision streams/decoders use extended RPU/EL semantics incompatible with Moonlight RFI.
        if (mime.contains("dolby-vision") || dec.contains("dolby") || (isHdr && dec.contains(".dv."))) {
            return false
        }
        // Tegra devices below Android 11 (API 30) suffer driver stalls on RFI.
        if (sdkInt < 30 && (dec.contains("nvidia") || hw.contains("tegra") || brd.contains("tegra"))) {
            return false
        }
        return true
    }

    fun capabilityMask(
        enableRfi: Boolean,
        codec: String,
        decoderName: String,
        mimeType: String,
        hardware: String,
        board: String,
        sdkInt: Int,
        isHdr: Boolean,
    ): Int {
        if (!supportsRfi(enableRfi, decoderName, mimeType, hardware, board, sdkInt, isHdr)) {
            return 0
        }
        return when (codec.uppercase()) {
            "AV1", "AV01" -> CAP_REFERENCE_FRAME_INVALIDATION_AV1
            "HEVC", "H.265", "H265" -> CAP_REFERENCE_FRAME_INVALIDATION_HEVC
            else -> CAP_REFERENCE_FRAME_INVALIDATION_AVC
        }
    }
}
