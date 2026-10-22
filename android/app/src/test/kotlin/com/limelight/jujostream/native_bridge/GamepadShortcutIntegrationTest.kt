package com.limelight.jujostream.native_bridge

import android.content.Context
import android.hardware.input.InputManager
import android.os.Looper
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implements
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowInputDevice
import org.robolectric.util.ReflectionHelpers

/** Exercises Android key dispatch, emulation, hold timers and the Flutter channel. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30], manifest = Config.NONE, shadows = [NoNativeGamepadBridge::class])
@LooperMode(LooperMode.Mode.PAUSED)
class GamepadShortcutIntegrationTest {
    private val messenger = RecordingGamepadMessenger()
    private lateinit var handler: GamepadHandler

    @Before fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        val inputs = shadowOf(context.getSystemService(Context.INPUT_SERVICE) as InputManager)
        for (id in 1..2) {
            val device = ShadowInputDevice.makeInputDeviceNamed("DualSense Wireless Controller")
            ReflectionHelpers.setField(device, "mId", id)
            ReflectionHelpers.setField(device, "mDescriptor", "controller-$id")
            ReflectionHelpers.setField(device, "mIsExternal", true)
            ReflectionHelpers.setField(device, "mSources", InputDevice.SOURCE_GAMEPAD or InputDevice.SOURCE_JOYSTICK)
            ReflectionHelpers.setField(device, "mMotionRanges", arrayListOf<InputDevice.MotionRange>())
            shadowOf(device).setVendorId(0x054c)
            shadowOf(device).setProductId(0x0ce6)
            inputs.addInputDevice(device)
            // Fire OS ships Sony's fallback key layout on this Android 11 device.
            inputs.addInputDeviceKeys(id, intArrayOf(KeyEvent.KEYCODE_BUTTON_A,
                KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BUTTON_START,
                KeyEvent.KEYCODE_BUTTON_L1, KeyEvent.KEYCODE_BUTTON_R1, KeyEvent.KEYCODE_BUTTON_MODE))
        }
        handler = GamepadHandler(context, messenger)
        messenger.call("setOverlayTriggerConfig", mapOf("combo" to 0x0330, "holdMs" to 0))
        messenger.call("setStreamingActive", mapOf("active" to true))
        shadowOf(Looper.getMainLooper()).idle()
        messenger.outgoing.clear()
    }

    @After fun tearDown() { if (::handler.isInitialized) handler.dispose() }

    private fun key(code: Int, down: Boolean = true, device: Int = 1) {
        val now = SystemClock.uptimeMillis()
        val scan = when (code) {
            KeyEvent.KEYCODE_BUTTON_SELECT -> 312
            KeyEvent.KEYCODE_BUTTON_START -> 313
            KeyEvent.KEYCODE_BUTTON_L1 -> 308
            KeyEvent.KEYCODE_BUTTON_R1 -> 309
            else -> 0
        }
        handler.handleKeyEvent(KeyEvent(now, now,
            if (down) KeyEvent.ACTION_DOWN else KeyEvent.ACTION_UP,
            code, 0, 0, device, scan, 0, InputDevice.SOURCE_GAMEPAD))
    }

    @Test fun `default overlay opens for every button order with Fire OS Sony key layout`() {
        val buttons = listOf(KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BUTTON_START,
            KeyEvent.KEYCODE_BUTTON_L1, KeyEvent.KEYCODE_BUTTON_R1)
        for (device in 1..2) for (order in permutations(buttons)) {
            messenger.outgoing.clear()
            order.forEach { key(it, device = device); shadowOf(Looper.getMainLooper()).idle() }
            assertEquals("device=$device order=$order", 1, messenger.outgoing.count { it == "onComboDetected" })
            messenger.call("setOverlayVisible", mapOf("visible" to false))
            order.forEach { key(it, down = false, device = device) }
            shadowOf(Looper.getMainLooper()).idle()
        }
    }

    @Test fun `legacy Linux face-button correction is retained`() {
        assertEquals(KeyEvent.KEYCODE_BUTTON_Y, remapped(KeyEvent.KEYCODE_BUTTON_X, 307))
        assertEquals(KeyEvent.KEYCODE_BUTTON_X, remapped(KeyEvent.KEYCODE_BUTTON_Y, 308))
    }

    @Test fun `already translated Sony fallback buttons remain unchanged`() {
        val pairs = listOf(304 to KeyEvent.KEYCODE_BUTTON_X, 305 to KeyEvent.KEYCODE_BUTTON_A,
            306 to KeyEvent.KEYCODE_BUTTON_B, 307 to KeyEvent.KEYCODE_BUTTON_Y,
            308 to KeyEvent.KEYCODE_BUTTON_L1, 309 to KeyEvent.KEYCODE_BUTTON_R1)
        for ((scan, code) in pairs) assertEquals("scan=$scan", code, remapped(code, scan))
    }

    @Test fun `partial shortcut and buttons split across controllers do not open overlay`() {
        key(KeyEvent.KEYCODE_BUTTON_SELECT)
        key(KeyEvent.KEYCODE_BUTTON_START)
        key(KeyEvent.KEYCODE_BUTTON_L1, device = 2)
        key(KeyEvent.KEYCODE_BUTTON_R1, device = 2)
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(messenger.outgoing.contains("onComboDetected"))
    }

    @Test fun `custom hold waits and cancels when released`() {
        messenger.call("setOverlayTriggerConfig", mapOf("combo" to 0x0330, "holdMs" to 500))
        val buttons = listOf(KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BUTTON_START,
            KeyEvent.KEYCODE_BUTTON_L1, KeyEvent.KEYCODE_BUTTON_R1)
        buttons.forEach { key(it) }
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(499))
        assertFalse(messenger.outgoing.contains("onComboDetected"))
        key(KeyEvent.KEYCODE_BUTTON_L1, down = false)
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(2))
        assertFalse(messenger.outgoing.contains("onComboDetected"))
        key(KeyEvent.KEYCODE_BUTTON_L1)
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(500))
        assertEquals(1, messenger.outgoing.count { it == "onComboDetected" })
    }

    private fun remapped(code: Int, scan: Int): Int {
        val now = SystemClock.uptimeMillis()
        return handler.remapKeyEventForFlutter(KeyEvent(now, now, KeyEvent.ACTION_DOWN,
            code, 0, 0, 1, scan, 0, InputDevice.SOURCE_GAMEPAD)).keyCode
    }

    private fun permutations(values: List<Int>): List<List<Int>> =
        if (values.isEmpty()) listOf(emptyList()) else values.flatMap { first ->
            permutations(values - first).map { listOf(first) + it }
        }
}

/** Only the transport boundary is replaced; all controller logic runs unchanged. */
@Implements(value = StreamingBridge::class, callNativeMethodsByDefault = false)
class NoNativeGamepadBridge

private class RecordingGamepadMessenger : BinaryMessenger {
    val outgoing = mutableListOf<String>()
    private var incoming: BinaryMessenger.BinaryMessageHandler? = null
    override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)
    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
        if (channel == "com.jujostream/gamepad" && message != null) {
            message.flip()
            outgoing.add(StandardMethodCodec.INSTANCE.decodeMethodCall(message).method)
        }
        callback?.reply(null)
    }
    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
        if (channel == "com.jujostream/gamepad") incoming = handler
    }
    fun call(method: String, args: Map<String, Any>) {
        val buffer = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, args))
        buffer.flip()
        incoming!!.onMessage(buffer) { }
    }
}
