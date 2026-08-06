package com.limelight.jujostream.native_bridge

internal data class DecoderRatePolicy(
    val operatingRate: Float,
    val priority: Int,
)

/** Keeps the proven Fire TV budget while avoiding a 30 fps cap on Amlogic. */
internal object WeakDeviceDecoderPolicy {
    fun forDecoder(redrawRate: Int, isAmlogicDecoder: Boolean): DecoderRatePolicy {
        return if (isAmlogicDecoder) {
            DecoderRatePolicy(redrawRate.toFloat(), 0)
        } else {
            DecoderRatePolicy(minOf(redrawRate, 30).toFloat(), 1)
        }
    }
}
