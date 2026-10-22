package com.limelight.jujostream.native_bridge

/** Position-to-relative conversion shared by mouse hover and drag events. */
internal class MouseMotionAccumulator(private val send: (Short, Short) -> Unit) {
    private var deviceId: Int? = null
    private var lastX = 0f
    private var lastY = 0f
    private var remainderX = 0.0
    private var remainderY = 0.0

    fun reset() {
        deviceId = null
        remainderX = 0.0
        remainderY = 0.0
    }

    fun seed(deviceId: Int, x: Float, y: Float) {
        if (!x.isFinite() || !y.isFinite()) {
            reset()
            return
        }
        if (this.deviceId != deviceId) reset()
        this.deviceId = deviceId
        lastX = x
        lastY = y
    }

    fun move(deviceId: Int, x: Float, y: Float, sensitivity: Float) {
        if (!x.isFinite() || !y.isFinite() || !sensitivity.isFinite()) {
            reset()
            return
        }
        if (this.deviceId == deviceId) {
            val motionX = (x.toDouble() - lastX) * sensitivity + remainderX
            val motionY = (y.toDouble() - lastY) * sensitivity + remainderY
            val wholeX = kotlin.math.truncate(motionX)
            val wholeY = kotlin.math.truncate(motionY)
            // Retain subpixel precision, but never replay a clipped large jump later.
            remainderX = motionX - wholeX
            remainderY = motionY - wholeY
            val dx = wholeX.coerceIn(-32767.0, 32767.0).toInt().toShort()
            val dy = wholeY.coerceIn(-32767.0, 32767.0).toInt().toShort()
            if (dx.toInt() != 0 || dy.toInt() != 0) send(dx, dy)
        }
        seed(deviceId, x, y)
    }
}
