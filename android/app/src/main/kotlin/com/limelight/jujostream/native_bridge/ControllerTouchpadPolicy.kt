package com.limelight.jujostream.native_bridge

import android.view.MotionEvent

/** Wire values and maths for a controller's own touchpad (LiSendControllerTouchEvent). */
internal object ControllerTouchpadPolicy {
    // LI_TOUCH_EVENT_* from Limelight.h. UP and MOVE are easy to swap; they were.
    const val EVENT_DOWN: Byte = 0x01
    const val EVENT_UP: Byte = 0x02
    const val EVENT_MOVE: Byte = 0x03
    const val EVENT_CANCEL_ALL: Byte = 0x07

    private const val SONY_VENDOR_ID = 0x054c

    /** Event type for the pointer that [actionMasked] is about, or null if it carries no touch. */
    fun eventType(actionMasked: Int): Byte? = when (actionMasked) {
        MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> EVENT_DOWN
        MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> EVENT_UP
        MotionEvent.ACTION_MOVE -> EVENT_MOVE
        MotionEvent.ACTION_CANCEL -> EVENT_CANCEL_ALL
        else -> null
    }

    /** DOWN and UP describe one finger; only MOVE reports every finger on the pad. */
    fun reportsAllPointers(actionMasked: Int): Boolean = actionMasked == MotionEvent.ACTION_MOVE

    /** Raw axis value to the 0..1 range the host scales onto the emulated pad. */
    fun normalize(value: Float, min: Float, max: Float): Float {
        val span = max - min
        if (!value.isFinite() || !span.isFinite() || span <= 0f) return 0f
        return ((value - min) / span).coerceIn(0f, 1f)
    }

    /**
     * Whether a pointing device is the touchpad of the given controller.
     * ponytail: Sony only, so a combo keyboard/mouse/gamepad never loses its
     * mouse. Add vendors here if a third-party PS pad needs it.
     */
    fun isTouchpadOf(
        pointerVendorId: Int,
        pointerProductId: Int,
        controllerVendorId: Int,
        controllerProductId: Int,
    ): Boolean = pointerVendorId == SONY_VENDOR_ID &&
        pointerVendorId == controllerVendorId &&
        pointerProductId == controllerProductId
}
