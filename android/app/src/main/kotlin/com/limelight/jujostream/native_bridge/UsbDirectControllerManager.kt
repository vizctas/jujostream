package com.limelight.jujostream.native_bridge

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt

/** Pure byte-level parser and builder for USB DualSense HID reports (0x01 / 0x02). */
internal object DualSenseUsbCodec {
    const val VENDOR_SONY = 0x054C
    const val PRODUCT_DUALSENSE = 0x0CE6
    const val PRODUCT_DUALSENSE_EDGE = 0x0DF2

    const val INPUT_REPORT_ID: Byte = 0x01
    const val OUTPUT_REPORT_ID: Byte = 0x02
    const val MIN_USB_INPUT_BYTES = 48
    const val USB_OUTPUT_REPORT_BYTES = 48

    private const val EARTH_G = 9.80665f
    private const val DS_ACC_RES_PER_G = 8192.0f
    private const val DS_GYRO_RES_PER_DPS = 16.0f

    private const val TOUCHPAD_MAX_X = 1919.0f
    private const val TOUCHPAD_MAX_Y = 1079.0f

    private const val A_FLAG = 0x1000
    private const val B_FLAG = 0x2000
    private const val X_FLAG = 0x4000
    private const val Y_FLAG = 0x8000
    private const val UP_FLAG = 0x0001
    private const val DOWN_FLAG = 0x0002
    private const val LEFT_FLAG = 0x0004
    private const val RIGHT_FLAG = 0x0008
    private const val LB_FLAG = 0x0100
    private const val RB_FLAG = 0x0200
    private const val PLAY_FLAG = 0x0010
    private const val BACK_FLAG = 0x0020
    private const val LS_CLK_FLAG = 0x0040
    private const val RS_CLK_FLAG = 0x0080
    private const val SPECIAL_FLAG = 0x0400
    private const val TOUCHPAD_FLAG = 0x100000
    private const val MISC_FLAG = 0x200000

    data class TouchPoint(
        val active: Boolean,
        val trackingId: Int,
        val x: Float,
        val y: Float,
    )

    data class ParsedDualSenseInput(
        val buttonFlags: Int,
        val leftTrigger: Int,
        val rightTrigger: Int,
        val lx: Short,
        val ly: Short,
        val rx: Short,
        val ry: Short,
        val gyroX: Float,
        val gyroY: Float,
        val gyroZ: Float,
        val accelX: Float,
        val accelY: Float,
        val accelZ: Float,
        val touch0: TouchPoint,
        val touch1: TouchPoint,
        val batteryPercent: Int,
        val charging: Boolean,
    )

    data class DualSenseOutputState(
        val slot: Int = 0,
        val lowFreqMotor: Int = 0,
        val highFreqMotor: Int = 0,
        val ledR: Int = 0,
        val ledG: Int = 0,
        val ledB: Int = 255,
        val hasLed: Boolean = false,
        val eventFlags: Int = 0,
        val triggerTypeLeft: Int = 0,
        val triggerTypeRight: Int = 0,
        val triggerLeft: ByteArray = ByteArray(10),
        val triggerRight: ByteArray = ByteArray(10),
    )

    fun isSupportedDualSense(vendorId: Int, productId: Int): Boolean =
        vendorId == VENDOR_SONY && (productId == PRODUCT_DUALSENSE || productId == PRODUCT_DUALSENSE_EDGE)

    private fun axisUnsignedToSigned(u: Int, invert: Boolean): Short {
        val centered = u - 128
        val signed = ((centered / 127.0f) * 32767.0f).roundToInt().coerceIn(-32767, 32767)
        val out = if (invert) -signed else signed
        return out.toShort()
    }

    private fun readI16Le(buf: ByteArray, offset: Int): Int {
        val lo = buf[offset].toInt() and 0xFF
        val hi = buf[offset + 1].toInt()
        return (hi shl 8) or lo
    }

    private fun parseTouchPoint(buf: ByteArray, offset: Int): TouchPoint {
        val contact = buf[offset].toInt() and 0xFF
        val active = (contact and 0x80) == 0
        val id = contact and 0x7F
        val b1 = buf[offset + 1].toInt() and 0xFF
        val b2 = buf[offset + 2].toInt() and 0xFF
        val b3 = buf[offset + 3].toInt() and 0xFF
        val rawX = ((b2 and 0x0F) shl 8) or b1
        val rawY = (b3 shl 4) or ((b2 ushr 4) and 0x0F)
        return TouchPoint(
            active = active,
            trackingId = id,
            x = (rawX / TOUCHPAD_MAX_X).coerceIn(0f, 1f),
            y = (rawY / TOUCHPAD_MAX_Y).coerceIn(0f, 1f),
        )
    }

    fun parseUsbInputReport01(report: ByteArray, length: Int = report.size): ParsedDualSenseInput? {
        if (length < MIN_USB_INPUT_BYTES || report.size < MIN_USB_INPUT_BYTES) return null
        if (report[0] != INPUT_REPORT_ID) return null

        val lx = axisUnsignedToSigned(report[1].toInt() and 0xFF, invert = false)
        // Sony HID Y=0 is up and Y=255 is down; Moonlight expects +32767 up.
        val ly = axisUnsignedToSigned(report[2].toInt() and 0xFF, invert = true)
        val rx = axisUnsignedToSigned(report[3].toInt() and 0xFF, invert = false)
        val ry = axisUnsignedToSigned(report[4].toInt() and 0xFF, invert = true)

        val lt = report[5].toInt() and 0xFF
        val rt = report[6].toInt() and 0xFF

        val b8 = report[8].toInt() and 0xFF
        val b9 = report[9].toInt() and 0xFF
        val b10 = report[10].toInt() and 0xFF

        var buttons = when (b8 and 0x0F) {
            0 -> UP_FLAG
            1 -> UP_FLAG or RIGHT_FLAG
            2 -> RIGHT_FLAG
            3 -> DOWN_FLAG or RIGHT_FLAG
            4 -> DOWN_FLAG
            5 -> DOWN_FLAG or LEFT_FLAG
            6 -> LEFT_FLAG
            7 -> UP_FLAG or LEFT_FLAG
            else -> 0
        }

        if ((b8 and 0x10) != 0) buttons = buttons or X_FLAG
        if ((b8 and 0x20) != 0) buttons = buttons or A_FLAG
        if ((b8 and 0x40) != 0) buttons = buttons or B_FLAG
        if ((b8 and 0x80) != 0) buttons = buttons or Y_FLAG

        if ((b9 and 0x01) != 0) buttons = buttons or LB_FLAG
        if ((b9 and 0x02) != 0) buttons = buttons or RB_FLAG
        if ((b9 and 0x10) != 0) buttons = buttons or BACK_FLAG
        if ((b9 and 0x20) != 0) buttons = buttons or PLAY_FLAG
        if ((b9 and 0x40) != 0) buttons = buttons or LS_CLK_FLAG
        if ((b9 and 0x80) != 0) buttons = buttons or RS_CLK_FLAG

        if ((b10 and 0x01) != 0) buttons = buttons or SPECIAL_FLAG
        if ((b10 and 0x02) != 0) buttons = buttons or TOUCHPAD_FLAG
        if ((b10 and 0x04) != 0) buttons = buttons or MISC_FLAG

        val gx = readI16Le(report, 16) / DS_GYRO_RES_PER_DPS
        val gy = readI16Le(report, 18) / DS_GYRO_RES_PER_DPS
        val gz = readI16Le(report, 20) / DS_GYRO_RES_PER_DPS

        val ax = readI16Le(report, 22) * (EARTH_G / DS_ACC_RES_PER_G)
        val ay = readI16Le(report, 24) * (EARTH_G / DS_ACC_RES_PER_G)
        val az = readI16Le(report, 26) * (EARTH_G / DS_ACC_RES_PER_G)

        val touch0 = parseTouchPoint(report, 33)
        val touch1 = parseTouchPoint(report, 37)

        var batteryPct = 100
        var charging = true
        if (length >= 55 && report.size >= 55) {
            val statusByte = report[53].toInt() and 0xFF
            val levelNibble = statusByte and 0x0F
            val stateNibble = (statusByte ushr 4) and 0x0F
            batteryPct = (levelNibble * 10 + 5).coerceIn(0, 100)
            charging = stateNibble == 0x01 || stateNibble == 0x02
        }

        return ParsedDualSenseInput(
            buttonFlags = buttons,
            leftTrigger = lt,
            rightTrigger = rt,
            lx = lx,
            ly = ly,
            rx = rx,
            ry = ry,
            gyroX = gx,
            gyroY = gy,
            gyroZ = gz,
            accelX = ax,
            accelY = ay,
            accelZ = az,
            touch0 = touch0,
            touch1 = touch1,
            batteryPercent = batteryPct,
            charging = charging,
        )
    }

    fun buildUsbOutputReport02(state: DualSenseOutputState): ByteArray {
        val out = ByteArray(USB_OUTPUT_REPORT_BYTES)
        out[0] = OUTPUT_REPORT_ID

        // valid_flag0: bit0=compatible rumble, bit1=enable haptic rumble, bit2=R trigger, bit3=L trigger
        var flag0 = 0x03
        if ((state.eventFlags and 0x04) != 0 || state.triggerTypeRight != 0) {
            flag0 = flag0 or 0x04
        }
        if ((state.eventFlags and 0x08) != 0 || state.triggerTypeLeft != 0) {
            flag0 = flag0 or 0x08
        }
        out[1] = flag0.toByte()

        // valid_flag1: bit2=lightbar LEDs, bit4=player LEDs
        out[2] = (if (state.hasLed) (0x04 or 0x10) else 0x10).toByte()

        out[3] = ((state.highFreqMotor ushr 8) and 0xFF).toByte()
        out[4] = ((state.lowFreqMotor ushr 8) and 0xFF).toByte()

        // Right trigger effect block at bytes 11..21
        out[11] = (state.triggerTypeRight and 0xFF).toByte()
        val rLen = minOf(state.triggerRight.size, 10)
        System.arraycopy(state.triggerRight, 0, out, 12, rLen)

        // Left trigger effect block at bytes 22..32
        out[22] = (state.triggerTypeLeft and 0xFF).toByte()
        val lLen = minOf(state.triggerLeft.size, 10)
        System.arraycopy(state.triggerLeft, 0, out, 23, lLen)

        // Lightbar fade-out disabled (immediate LED update) + player indicator + RGB
        out[42] = 0x02
        out[44] = when (state.slot and 0x03) {
            0 -> 0x04
            1 -> 0x0A
            2 -> 0x15
            else -> 0x1B
        }.toByte()
        if (state.hasLed) {
            out[45] = (state.ledR and 0xFF).toByte()
            out[46] = (state.ledG and 0xFF).toByte()
            out[47] = (state.ledB and 0xFF).toByte()
        }
        return out
    }
}

/**
 * Direct USB Host OTG controller driver for DualSense (0x0CE6 / 0x0DF2).
 * Claims exclusive kernel HID ownership during streaming to eliminate Android InputReader jitter
 * and unlock full 250-1000Hz sticks, gyro/accel, 2-finger touchpad, RGB LED & adaptive triggers.
 */
class UsbDirectControllerManager(
    private val context: Context,
    private val acquireSlot: (vendorId: Int, productId: Int) -> Int?,
    private val releaseSlot: (slot: Int) -> Unit,
    private val activeMaskProvider: () -> Short,
    private val onControllerChanged: () -> Unit,
) {
    companion object {
        private const val TAG = "UsbDirectController"
        private const val ACTION_USB_PERMISSION = "com.limelight.jujostream.USB_DIRECT_PERMISSION"
        private const val LI_CTYPE_PS: Byte = 0x02
        private const val LI_CCAP_ALL_DUALSENSE: Short =
            (0x01 or 0x02 or 0x04 or 0x08 or 0x10 or 0x20 or 0x40 or 0x80).toShort()
        private const val ALL_PS_BUTTONS = 0xFFFF or 0x100000 or 0x200000
        private const val HEARTBEAT_MS = 200L
        private const val MAX_PACKET_SIZE = 64
    }

    private data class ActiveDevice(
        val device: UsbDevice,
        val slot: Int,
        val connection: UsbDeviceConnection,
        val iface: UsbInterface,
        val epIn: UsbEndpoint,
        val epOut: UsbEndpoint?,
        val running: AtomicBoolean = AtomicBoolean(true),
        @Volatile var outputState: DualSenseUsbCodec.DualSenseOutputState,
        var thread: Thread? = null,
    )

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
    private val activeByDeviceId = ConcurrentHashMap<Int, ActiveDevice>()
    private val activeBySlot = ConcurrentHashMap<Int, ActiveDevice>()
    private val permissionRequested = ConcurrentHashMap.newKeySet<Int>()
    private val txExecutor = Executors.newSingleThreadExecutor()

    @Volatile
    private var streamingActive = false
    private var receiverRegistered = false

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            }

            when (action) {
                ACTION_USB_PERMISSION -> {
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    device?.let { permissionRequested.remove(it.deviceId) }
                    if (granted && device != null && streamingActive) {
                        tryAttachDevice(device)
                        onControllerChanged()
                    }
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    if (device != null && streamingActive &&
                        DualSenseUsbCodec.isSupportedDualSense(device.vendorId, device.productId)) {
                        tryAttachDevice(device)
                        onControllerChanged()
                    }
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    if (device != null) {
                        detachDevice(device.deviceId)
                        onControllerChanged()
                    }
                }
            }
        }
    }

    fun register() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(ACTION_USB_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(usbReceiver, filter)
        }
        receiverRegistered = true
    }

    fun dispose() {
        setStreamingActive(false)
        if (receiverRegistered) {
            runCatching { context.unregisterReceiver(usbReceiver) }
            receiverRegistered = false
        }
        txExecutor.shutdownNow()
    }

    fun setStreamingActive(active: Boolean): Int {
        streamingActive = active
        if (!active) {
            stopAll()
            return 0
        }
        register()
        scanAttachedDevices()
        return activeBySlot.size
    }

    fun ownsSlot(slot: Int): Boolean = activeBySlot.containsKey(slot)

    fun ownsDevice(vendorId: Int, productId: Int): Boolean =
        activeByDeviceId.values.any {
            it.device.vendorId == vendorId && it.device.productId == productId
        }

    fun claimedSlotMask(): Int {
        var mask = 0
        for (slot in activeBySlot.keys) {
            mask = mask or (1 shl slot)
        }
        return mask
    }

    fun updateRumble(slot: Int, lowFreq: Int, highFreq: Int): Boolean {
        val dev = activeBySlot[slot] ?: return false
        dev.outputState = dev.outputState.copy(lowFreqMotor = lowFreq, highFreqMotor = highFreq)
        sendOutputReportAsync(dev)
        return true
    }

    fun updateLed(slot: Int, r: Int, g: Int, b: Int): Boolean {
        val dev = activeBySlot[slot] ?: return false
        dev.outputState = dev.outputState.copy(ledR = r, ledG = g, ledB = b, hasLed = true)
        sendOutputReportAsync(dev)
        return true
    }

    fun updateAdaptiveTriggers(
        slot: Int,
        eventFlags: Int,
        typeLeft: Int,
        typeRight: Int,
        left: ByteArray,
        right: ByteArray,
    ): Boolean {
        val dev = activeBySlot[slot] ?: return false
        dev.outputState = dev.outputState.copy(
            eventFlags = eventFlags,
            triggerTypeLeft = typeLeft,
            triggerTypeRight = typeRight,
            triggerLeft = left.copyOf(10),
            triggerRight = right.copyOf(10),
        )
        sendOutputReportAsync(dev)
        return true
    }

    private fun scanAttachedDevices() {
        val mgr = usbManager ?: return
        for (device in mgr.deviceList.values) {
            if (DualSenseUsbCodec.isSupportedDualSense(device.vendorId, device.productId)) {
                tryAttachDevice(device)
            }
        }
    }

    private fun tryAttachDevice(device: UsbDevice) {
        val mgr = usbManager ?: return
        if (activeByDeviceId.containsKey(device.deviceId)) return

        if (!mgr.hasPermission(device)) {
            if (permissionRequested.add(device.deviceId)) {
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_MUTABLE
                } else {
                    0
                }
                val intent = Intent(ACTION_USB_PERMISSION).apply {
                    setPackage(context.packageName)
                }
                val pi = PendingIntent.getBroadcast(context, device.deviceId, intent, flags)
                mgr.requestPermission(device, pi)
                Log.i(TAG, "Requested USB permission for ${device.productName ?: device.deviceName}")
            }
            return
        }

        val endpoints = findHidInterface(device) ?: return
        val (iface, epIn, epOut) = endpoints

        val connection = mgr.openDevice(device) ?: return
        if (!connection.claimInterface(iface, true)) {
            connection.close()
            Log.w(TAG, "Failed to claim HID interface on ${device.deviceName}")
            return
        }

        val slot = acquireSlot(device.vendorId, device.productId)
        if (slot == null) {
            connection.releaseInterface(iface)
            connection.close()
            return
        }

        val active = ActiveDevice(
            device = device,
            slot = slot,
            connection = connection,
            iface = iface,
            epIn = epIn,
            epOut = epOut,
            outputState = DualSenseUsbCodec.DualSenseOutputState(slot = slot),
        )
        activeByDeviceId[device.deviceId] = active
        activeBySlot[slot] = active

        val mask = (activeMaskProvider().toInt() or (1 shl slot)).toShort()
        StreamingBridge.nativeSendControllerArrival(
            slot.toShort(),
            mask,
            LI_CTYPE_PS,
            LI_CCAP_ALL_DUALSENSE,
            ALL_PS_BUTTONS,
        )

        active.thread = Thread({ readerLoop(active) }, "UsbDirectDS-$slot").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
        Log.i(
            TAG,
            "USB Direct DualSense attached on slot=$slot (vid=0x${device.vendorId.toString(16)} " +
                "pid=0x${device.productId.toString(16)}, epOut=${epOut != null})",
        )
    }

    private fun detachDevice(deviceId: Int) {
        val active = activeByDeviceId.remove(deviceId) ?: return
        activeBySlot.remove(active.slot)
        active.running.set(false)
        runCatching { active.connection.releaseInterface(active.iface) }
        runCatching { active.connection.close() }
        runCatching { active.thread?.join(200) }
        releaseSlot(active.slot)
        Log.i(TAG, "USB Direct DualSense detached from slot=${active.slot}")
    }

    private fun stopAll() {
        for (id in activeByDeviceId.keys.toList()) {
            detachDevice(id)
        }
    }

    private fun findHidInterface(device: UsbDevice): Triple<UsbInterface, UsbEndpoint, UsbEndpoint?>? {
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass != UsbConstants.USB_CLASS_HID) continue
            var epIn: UsbEndpoint? = null
            var epOut: UsbEndpoint? = null
            for (j in 0 until iface.endpointCount) {
                val ep = iface.getEndpoint(j)
                if (ep.type != UsbConstants.USB_ENDPOINT_XFER_INT) continue
                if (ep.direction == UsbConstants.USB_DIR_IN && epIn == null) {
                    epIn = ep
                } else if (ep.direction == UsbConstants.USB_DIR_OUT && epOut == null) {
                    epOut = ep
                }
            }
            if (epIn != null) {
                return Triple(iface, epIn, epOut)
            }
        }
        return null
    }

    private fun sendOutputReportAsync(active: ActiveDevice) {
        val epOut = active.epOut ?: return
        if (!active.running.get() || txExecutor.isShutdown) return
        val payload = DualSenseUsbCodec.buildUsbOutputReport02(active.outputState)
        runCatching {
            txExecutor.execute {
                if (!active.running.get()) return@execute
                active.connection.bulkTransfer(epOut, payload, payload.size, 15)
            }
        }
    }

    private fun readerLoop(active: ActiveDevice) {
        val buf = ByteArray(maxOf(active.epIn.maxPacketSize, MAX_PACKET_SIZE))
        var hasLast = false
        var lastButtons = 0
        var lastLt = 0
        var lastRt = 0
        var lastLx: Short = 0
        var lastLy: Short = 0
        var lastRx: Short = 0
        var lastRy: Short = 0
        var lastSentMs = 0L
        var lastBatteryMs = 0L
        var prevTouch0Active = false
        var prevTouch1Active = false

        while (active.running.get() && streamingActive) {
            val n = active.connection.bulkTransfer(active.epIn, buf, buf.size, 8)
            if (n <= 0) continue

            val parsed = DualSenseUsbCodec.parseUsbInputReport01(buf, n) ?: continue
            val nowMs = SystemClock.elapsedRealtime()
            val mask = (activeMaskProvider().toInt() or (1 shl active.slot)).toShort()

            val changed = !hasLast ||
                parsed.buttonFlags != lastButtons ||
                parsed.leftTrigger != lastLt ||
                parsed.rightTrigger != lastRt ||
                parsed.lx != lastLx ||
                parsed.ly != lastLy ||
                parsed.rx != lastRx ||
                parsed.ry != lastRy ||
                (nowMs - lastSentMs) >= HEARTBEAT_MS

            if (changed) {
                StreamingBridge.nativeSendControllerInput(
                    active.slot.toShort(),
                    mask,
                    parsed.buttonFlags,
                    parsed.leftTrigger.toByte(),
                    parsed.rightTrigger.toByte(),
                    parsed.lx,
                    parsed.ly,
                    parsed.rx,
                    parsed.ry,
                )
                hasLast = true
                lastButtons = parsed.buttonFlags
                lastLt = parsed.leftTrigger
                lastRt = parsed.rightTrigger
                lastLx = parsed.lx
                lastLy = parsed.ly
                lastRx = parsed.rx
                lastRy = parsed.ry
                lastSentMs = nowMs
            }

            StreamingBridge.nativeSendControllerMotionEvent(
                active.slot.toShort(), 0x02, parsed.gyroX, parsed.gyroY, parsed.gyroZ)
            StreamingBridge.nativeSendControllerMotionEvent(
                active.slot.toShort(), 0x01, parsed.accelX, parsed.accelY, parsed.accelZ)

            prevTouch0Active = emitTouchDelta(active.slot, 0, parsed.touch0, prevTouch0Active)
            prevTouch1Active = emitTouchDelta(active.slot, 1, parsed.touch1, prevTouch1Active)

            if (nowMs - lastBatteryMs >= 10_000L) {
                lastBatteryMs = nowMs
                val st: Byte = if (parsed.charging) 0x03 else 0x02
                StreamingBridge.nativeSendControllerBattery(
                    active.slot.toShort(), st, parsed.batteryPercent.toByte())
            }
        }
    }

    private fun emitTouchDelta(
        slot: Int,
        pointerId: Int,
        tp: DualSenseUsbCodec.TouchPoint,
        wasActive: Boolean,
    ): Boolean {
        if (tp.active) {
            val evt: Byte = if (wasActive) 0x03 else 0x01 // MOVE vs DOWN
            StreamingBridge.nativeSendControllerTouchEvent(
                slot.toShort(), evt, pointerId, tp.x, tp.y, 1.0f)
            return true
        }
        if (wasActive) {
            StreamingBridge.nativeSendControllerTouchEvent(
                slot.toShort(), 0x02, pointerId, tp.x, tp.y, 0.0f) // UP
        }
        return false
    }
}

