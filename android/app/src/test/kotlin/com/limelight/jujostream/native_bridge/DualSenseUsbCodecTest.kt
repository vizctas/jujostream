package com.limelight.jujostream.native_bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DualSenseUsbCodecTest {
    @Test
    fun parsesSticksTriggersButtonsTouchpadAndImuFromReport01() {
        val report = ByteArray(64)
        report[0] = 0x01
        report[1] = 0xFF.toByte() // LX right (+32767)
        report[2] = 0x00 // LY top (must invert to +32767)
        report[3] = 0x80.toByte() // RX center (0)
        report[4] = 0xFF.toByte() // RY bottom (must invert to -32767)
        report[5] = 0xAA.toByte() // L2
        report[6] = 0x55 // R2
        report[8] = (0x20 or 0x02).toByte() // Cross (A) + DPad East (2)
        report[9] = (0x01 or 0x20).toByte() // L1 + Options
        report[10] = 0x02 // Touchpad click

        // Gyro X = +160 raw -> 10.0 deg/s
        report[16] = 160.toByte()
        report[17] = 0
        // Accel Y = +8192 raw -> 1g (9.80665 m/s^2)
        report[24] = 0x00
        report[25] = 0x20

        // Touch 0 active at ~(960, 540)
        report[33] = 0x05 // active (bit7=0), id=5
        val rawX = 960
        val rawY = 540
        report[34] = (rawX and 0xFF).toByte()
        report[35] = (((rawX ushr 8) and 0x0F) or ((rawY and 0x0F) shl 4)).toByte()
        report[36] = ((rawY ushr 4) and 0xFF).toByte()

        // Touch 1 inactive
        report[37] = 0x80.toByte()

        val parsed = DualSenseUsbCodec.parseUsbInputReport01(report)
        assertNotNull(parsed)
        parsed!!

        assertEquals(32767.toShort(), parsed.lx)
        assertEquals(32767.toShort(), parsed.ly)
        assertEquals(0.toShort(), parsed.rx)
        assertEquals((-32767).toShort(), parsed.ry)
        assertEquals(0xAA, parsed.leftTrigger)
        assertEquals(0x55, parsed.rightTrigger)

        assertTrue((parsed.buttonFlags and 0x1000) != 0) // Cross
        assertTrue((parsed.buttonFlags and 0x0008) != 0) // DPad East
        assertTrue((parsed.buttonFlags and 0x0100) != 0) // L1
        assertTrue((parsed.buttonFlags and 0x0010) != 0) // Options
        assertTrue((parsed.buttonFlags and 0x100000) != 0) // Touchpad click

        assertEquals(10.0f, parsed.gyroX, 0.01f)
        assertEquals(9.80665f, parsed.accelY, 0.01f)

        assertTrue(parsed.touch0.active)
        assertEquals(5, parsed.touch0.trackingId)
        assertEquals(0.5f, parsed.touch0.x, 0.002f)
        assertEquals(0.5f, parsed.touch0.y, 0.002f)
        assertFalse(parsed.touch1.active)
    }

    @Test
    fun rejectsShortOrWrongReportId() {
        assertNull(DualSenseUsbCodec.parseUsbInputReport01(ByteArray(32)))
        val badId = ByteArray(64).also { it[0] = 0x31 }
        assertNull(DualSenseUsbCodec.parseUsbInputReport01(badId))
    }

    @Test
    fun buildsOutputReport02WithRumbleLedAndAdaptiveTriggers() {
        val leftParams = ByteArray(10) { (it + 1).toByte() }
        val rightParams = ByteArray(10) { (it + 11).toByte() }
        val out = DualSenseUsbCodec.buildUsbOutputReport02(
            DualSenseUsbCodec.DualSenseOutputState(
                slot = 0,
                lowFreqMotor = 0xABCD,
                highFreqMotor = 0x1234,
                ledR = 0x10,
                ledG = 0x20,
                ledB = 0xFF,
                hasLed = true,
                eventFlags = 0x0C,
                triggerTypeLeft = 0x02,
                triggerTypeRight = 0x26,
                triggerLeft = leftParams,
                triggerRight = rightParams,
            ),
        )

        assertEquals(48, out.size)
        assertEquals(0x02.toByte(), out[0])
        assertEquals(0x0F.toByte(), out[1]) // rumble + R trigger + L trigger
        assertEquals(0x14.toByte(), out[2]) // LED + player LED
        assertEquals(0x12.toByte(), out[3]) // high motor MSB
        assertEquals(0xAB.toByte(), out[4]) // low motor MSB
        assertEquals(0x26.toByte(), out[11]) // right trigger mode
        assertEquals(11.toByte(), out[12]) // right param 0
        assertEquals(0x02.toByte(), out[22]) // left trigger mode
        assertEquals(1.toByte(), out[23]) // left param 0
        assertEquals(0x04.toByte(), out[44]) // player 1 LED
        assertEquals(0x10.toByte(), out[45]) // R
        assertEquals(0x20.toByte(), out[46]) // G
        assertEquals(0xFF.toByte(), out[47]) // B
    }
}
