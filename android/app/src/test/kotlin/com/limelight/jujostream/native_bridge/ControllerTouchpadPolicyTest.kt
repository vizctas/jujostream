package com.limelight.jujostream.native_bridge

import android.view.MotionEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ControllerTouchpadPolicyTest {
    @Test
    fun eventTypesMatchLimelightWireValues() {
        assertEquals(0x01.toByte(), ControllerTouchpadPolicy.eventType(MotionEvent.ACTION_DOWN))
        assertEquals(0x01.toByte(), ControllerTouchpadPolicy.eventType(MotionEvent.ACTION_POINTER_DOWN))
        assertEquals(0x02.toByte(), ControllerTouchpadPolicy.eventType(MotionEvent.ACTION_UP))
        assertEquals(0x02.toByte(), ControllerTouchpadPolicy.eventType(MotionEvent.ACTION_POINTER_UP))
        assertEquals(0x03.toByte(), ControllerTouchpadPolicy.eventType(MotionEvent.ACTION_MOVE))
        assertEquals(0x07.toByte(), ControllerTouchpadPolicy.eventType(MotionEvent.ACTION_CANCEL))
        assertNull(ControllerTouchpadPolicy.eventType(MotionEvent.ACTION_HOVER_MOVE))
        assertNull(ControllerTouchpadPolicy.eventType(MotionEvent.ACTION_BUTTON_PRESS))
    }

    @Test
    fun onlyMoveReportsEveryFinger() {
        assertTrue(ControllerTouchpadPolicy.reportsAllPointers(MotionEvent.ACTION_MOVE))
        assertFalse(ControllerTouchpadPolicy.reportsAllPointers(MotionEvent.ACTION_POINTER_UP))
        assertFalse(ControllerTouchpadPolicy.reportsAllPointers(MotionEvent.ACTION_DOWN))
    }

    @Test
    fun normalizeUsesTheAxisRangeAndClamps() {
        assertEquals(0.5f, ControllerTouchpadPolicy.normalize(960f, 0f, 1920f), 0.0001f)
        assertEquals(0.25f, ControllerTouchpadPolicy.normalize(0f, -100f, 300f), 0.0001f)
        assertEquals(1f, ControllerTouchpadPolicy.normalize(5000f, 0f, 1920f), 0f)
        assertEquals(0f, ControllerTouchpadPolicy.normalize(-5f, 0f, 1920f), 0f)
        assertEquals(0f, ControllerTouchpadPolicy.normalize(10f, 0f, 0f), 0f)
        assertEquals(0f, ControllerTouchpadPolicy.normalize(Float.NaN, 0f, 1920f), 0f)
    }

    @Test
    fun onlyASonyPadOwnsAPointerSharingItsIds() {
        assertTrue(ControllerTouchpadPolicy.isTouchpadOf(0x054c, 0x0ce6, 0x054c, 0x0ce6))
        // A DualSense touchpad does not belong to a DualShock 4 on the same box.
        assertFalse(ControllerTouchpadPolicy.isTouchpadOf(0x054c, 0x0ce6, 0x054c, 0x09cc))
        // A combo device keeps its mouse.
        assertFalse(ControllerTouchpadPolicy.isTouchpadOf(0x2dc8, 0x3106, 0x2dc8, 0x3106))
        assertFalse(ControllerTouchpadPolicy.isTouchpadOf(0x046d, 0xc077, 0x054c, 0x0ce6))
    }
}
