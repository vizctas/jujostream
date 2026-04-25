package com.limelight.jujostream.native_bridge

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.input.InputManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sqrt

class GamepadHandler(
    private val context: Context,
    binaryMessenger: BinaryMessenger
) : InputManager.InputDeviceListener, SensorEventListener {

    companion object {
        private const val TAG = "GamepadHandler"
        private const val CHANNEL = "com.jujostream/gamepad"

        private const val A_FLAG      = 0x1000
        private const val B_FLAG      = 0x2000
        private const val X_FLAG      = 0x4000
        private const val Y_FLAG      = 0x8000
        private const val UP_FLAG     = 0x0001
        private const val DOWN_FLAG   = 0x0002
        private const val LEFT_FLAG   = 0x0004
        private const val RIGHT_FLAG  = 0x0008
        private const val LB_FLAG     = 0x0100
        private const val RB_FLAG     = 0x0200
        private const val PLAY_FLAG   = 0x0010
        private const val BACK_FLAG   = 0x0020
        private const val LS_CLK_FLAG = 0x0040
        private const val RS_CLK_FLAG = 0x0080
        private const val SPECIAL_FLAG = 0x0400

        private const val TOUCHPAD_FLAG = 0x100000
        private const val MISC_FLAG     = 0x200000

        // Virtual flags for analog triggers (not part of moonlight buttonFlags,
        // used only for overlay trigger combo detection)
        private const val LT_VIRTUAL_FLAG = 0x10000
        private const val RT_VIRTUAL_FLAG = 0x20000

        private const val ALL_STANDARD_BUTTONS =
            A_FLAG or B_FLAG or X_FLAG or Y_FLAG or
            UP_FLAG or DOWN_FLAG or LEFT_FLAG or RIGHT_FLAG or
            LB_FLAG or RB_FLAG or PLAY_FLAG or BACK_FLAG or
            LS_CLK_FLAG or RS_CLK_FLAG or SPECIAL_FLAG

        private const val DPAD_MASK = UP_FLAG or DOWN_FLAG or LEFT_FLAG or RIGHT_FLAG

        private const val QUIT_COMBO_MASK = BACK_FLAG or PLAY_FLAG or LB_FLAG or RB_FLAG
        private const val EMULATING_SPECIAL = 0x1
        private const val EMULATING_SELECT  = 0x2

        private const val MAXIMUM_BUMPER_UP_DELAY_MS = 100L
        private const val START_DOWN_TIME_MOUSE_MODE_MS = 1500L
        private const val REMAP_IGNORE = -1
        private const val REMAP_CONSUME = -2
        private const val MAX_GAMEPADS = 4

        private const val LI_CTYPE_XBOX: Byte = 0x01
        private const val LI_CTYPE_PS: Byte = 0x02
        private const val LI_CTYPE_NINTENDO: Byte = 0x03

        private const val LI_CCAP_ANALOG_TRIGGERS: Int = 0x01
        private const val LI_CCAP_RUMBLE: Int = 0x02
        private const val LI_CCAP_TRIGGER_RUMBLE: Int = 0x04
        private const val LI_CCAP_TOUCHPAD: Int = 0x08
        private const val LI_CCAP_ACCEL: Int = 0x10
        private const val LI_CCAP_GYRO: Int = 0x20
        private const val LI_CCAP_RGB_LED: Int = 0x80

        private const val DRIVER_AUTO = 0
        private const val DRIVER_XBOX360 = 1
        private const val DRIVER_DUALSHOCK = 2
        private const val DRIVER_DUALSENSE = 3

        private const val BACK_ACTION_DEFAULT = 0
        private const val BACK_ACTION_META = 1
        private const val BACK_ACTION_GUIDE = 2

        private const val STICK_MAX = 32767f

        private const val MOUSE_PRESS: Byte  = 0x07
        private const val MOUSE_RELEASE: Byte = 0x08
        private const val MOUSE_BTN_LEFT: Byte   = 0x01
        private const val MOUSE_BTN_MIDDLE: Byte = 0x02
        private const val MOUSE_BTN_RIGHT: Byte  = 0x03

        @Volatile
        @JvmStatic
        var instance: GamepadHandler? = null
            private set
    }

    var isStreaming = false
        private set
    var overlayVisible = false

    private val methodChannel = MethodChannel(binaryMessenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var overlayTriggerCombo: Int = LS_CLK_FLAG or RS_CLK_FLAG
    private var overlayTriggerHoldMs: Long = 2000L

    private var mouseModeCombo: Int = BACK_FLAG
    private var mouseModeHoldMs: Long = 2000L

    private class ControllerState {
        var buttonFlags: Int = 0
        var leftTrigger: Byte = 0
        var rightTrigger: Byte = 0
        var leftStickX: Short = 0
        var leftStickY: Short = 0
        var rightStickX: Short = 0
        var rightStickY: Short = 0

        var emulatingButtonFlags: Int = 0
        var hasSelect: Boolean = false
        var hasMode: Boolean = false

        var vendorId: Int = 0
        var productId: Int = 0
        var deviceName: String = ""

        var isNonStandardDualShock4: Boolean = false
        var usesLinuxGamepadStandardFaceButtons: Boolean = false

        var leftTriggerAxis: Int = MotionEvent.AXIS_LTRIGGER
        var rightTriggerAxis: Int = MotionEvent.AXIS_RTRIGGER
        var triggersIdleNegative: Boolean = false
        var leftTriggerAxisUsed: Boolean = false
        var rightTriggerAxisUsed: Boolean = false

        var rightStickXAxis: Int = MotionEvent.AXIS_Z
        var rightStickYAxis: Int = MotionEvent.AXIS_RZ

        var ignoreBack: Boolean = true

        var l3Down: Boolean = false
        var r3Down: Boolean = false

        var lastLbUpTime: Long = 0
        var lastRbUpTime: Long = 0

        var startDownTime: Long = 0
        var selectDownTime: Long = 0

        var pendingComboFlags: Int = 0

        var pendingExit: Boolean = false

        var lastTouchX: Float = -1f
        var lastTouchY: Float = -1f

        var supportedButtonFlags: Int = ALL_STANDARD_BUTTONS

        var arrivalSent: Boolean = false

        var hasSentInput: Boolean = false
        var lastSentButtonFlags: Int = 0
        var lastSentLeftTrigger: Byte = 0
        var lastSentRightTrigger: Byte = 0
        var lastSentLeftStickX: Short = 0
        var lastSentLeftStickY: Short = 0
        var lastSentRightStickX: Short = 0
        var lastSentRightStickY: Short = 0
    }

    private val controllers = mutableMapOf<Int, ControllerState>()
    private val deviceSlots = mutableMapOf<Int, Int>()
    private var currentControllers: Short = 0
    private var isDetecting = false

    private var deadzonePercent: Int = 5
    private var triggerDeadzonePercent: Int = 2
    private var responseCurve: Float = 1.0f
    private var buttonRemapTable: Map<Int, Int>? = null
    private var touchpadAsMouse: Boolean = false
    private var motionSensorsEnabled: Boolean = false
    private var motionFallbackEnabled: Boolean = false
    private var mouseSensitivity: Float = 1.0f
    private var scrollSensitivity: Float = 1.0f
    private var controllerDriverMode: Int = DRIVER_AUTO
    private var backButtonAction: Int = BACK_ACTION_DEFAULT
    private var forceQwertyLayoutEnabled: Boolean = true
    private var usbDriverEnabled: Boolean = true
    private var usbBindAllEnabled: Boolean = false
    private var joyConEnabled: Boolean = false
    private var rumbleEnabled: Boolean = true
    private var rumbleFallbackEnabled: Boolean = false
    private var deviceRumbleEnabled: Boolean = false
    private var rumbleFallbackStrength: Int = 100

    var mouseEmulationActive: Boolean = false
        private set
    private var mouseEmuLeftButtonDown: Boolean = false
    private var mouseEmuRightButtonDown: Boolean = false
    private var mouseEmuMiddleButtonDown: Boolean = false
    private var mouseEmulationSpeed: Float = 8.0f

    private var mouseEmuADownTime: Long = 0L
    private var mouseEmuAHoldFired: Boolean = false
    private var mouseEmuAHoldRunnable: Runnable? = null
    private val mouseEmuAHoldThresholdMs: Long = 350L

    private var lastMouseX: Float = -1f
    private var lastMouseY: Float = -1f
    private var prevMouseButtonState: Int = 0

    private var lastOverlayHatDir: String? = null

    private var comboHeldRunnable: Runnable? = null
    private var mouseModeHeldRunnable: Runnable? = null

    // Panic combo — emergency session kill
    private var panicCombo: Int = 0  // 0 = disabled (NONE)
    private var panicHoldMs: Long = 2000L
    private var panicHeldRunnable: Runnable? = null

    private var sensorManager: SensorManager? = null
    private var motionReportRateHz: Int = 0
    private var motionControllerNumber: Int = 0

    init {
        instance = this

        val inputManager = context.getSystemService(Context.INPUT_SERVICE) as? InputManager
        inputManager?.registerInputDeviceListener(this, mainHandler)

        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setStreamingActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    Log.i(TAG, "STREAM_STATE: setStreamingActive($active) — was $isStreaming")
                    isStreaming = active
                    if (active) {
                        val count = detectControllers()
                        result.success(count)
                    } else {
                        stopMotionSensors()
                        controllers.clear()
                        deviceSlots.clear()
                        currentControllers = 0
                        lastMouseX = -1f
                        lastMouseY = -1f
                        prevMouseButtonState = 0
                        result.success(0)
                    }
                }
                "redetectControllers" -> {

                    if (isStreaming) {

                        for ((_, state) in controllers) {
                            state.arrivalSent = false
                        }
                        val count = detectControllers()
                        result.success(count)
                    } else {
                        result.success(0)
                    }
                }
                "setOverlayVisible" -> {
                    overlayVisible = call.argument<Boolean>("visible") ?: false
                    result.success(null)
                }
                "getConnectedGamepadCount" -> {
                    result.success(countGamepads())
                }
                "setDeadzone" -> {
                    deadzonePercent = (call.argument<Int>("percent") ?: 5).coerceIn(-20, 20)
                    result.success(null)
                }
                "setResponseCurve" -> {
                    responseCurve = (call.argument<Double>("curve") ?: 1.0).toFloat().coerceIn(0.5f, 3.0f)
                    result.success(null)
                }
                "setTouchpadAsMouse" -> {
                    touchpadAsMouse = call.argument<Boolean>("enabled") ?: false
                    result.success(null)
                }
                "setMotionSensors" -> {
                    motionSensorsEnabled = call.argument<Boolean>("enabled") ?: false
                    motionFallbackEnabled = call.argument<Boolean>("fallback") ?: false
                    result.success(null)
                }
                "setControllerPreferences" -> {
                    val backAsMeta = call.argument<Boolean>("backButtonAsMeta") ?: false
                    val backAsGuide = call.argument<Boolean>("backButtonAsGuide") ?: false
                    backButtonAction = when {
                        backAsMeta -> BACK_ACTION_META
                        backAsGuide -> BACK_ACTION_GUIDE
                        else -> BACK_ACTION_DEFAULT
                    }
                    controllerDriverMode =
                        (call.argument<Int>("controllerDriver") ?: DRIVER_AUTO)
                            .coerceIn(DRIVER_AUTO, DRIVER_DUALSENSE)
                    refreshControllerArrivals()
                    result.success(null)
                }
                "setInputPreferences" -> {
                    forceQwertyLayoutEnabled = call.argument<Boolean>("forceQwertyLayout") ?: true
                    usbDriverEnabled = call.argument<Boolean>("usbDriverEnabled") ?: true
                    usbBindAllEnabled = call.argument<Boolean>("usbBindAll") ?: false
                    joyConEnabled = call.argument<Boolean>("joyConEnabled") ?: false
                    val count = if (isStreaming) detectControllers() else countGamepads()
                    result.success(count)
                }
                "setRumbleConfig" -> {
                    rumbleEnabled = call.argument<Boolean>("enabled") ?: true
                    rumbleFallbackEnabled = call.argument<Boolean>("fallback") ?: false
                    deviceRumbleEnabled = call.argument<Boolean>("deviceRumble") ?: false
                    rumbleFallbackStrength =
                        (call.argument<Int>("strength") ?: 100).coerceIn(0, 100)
                    if (!rumbleEnabled) {
                        cancelDeviceRumble()
                    }
                    result.success(null)
                }
                "setButtonRemap" -> {
                    val raw = call.argument<Map<*, *>>("remap")
                    buttonRemapTable = if (raw != null) {
                        raw.entries.associate { (k, v) ->
                            ((k as? Number)?.toInt() ?: 0) to ((v as? Number)?.toInt() ?: 0)
                        }
                    } else null
                    result.success(null)
                }
                "setMouseSensitivity" -> {
                    mouseSensitivity = (call.argument<Double>("sensitivity") ?: 1.0)
                        .toFloat().coerceIn(0.1f, 5.0f)
                    result.success(null)
                }
                "setMouseEmulationSpeed" -> {

                    val factor = (call.argument<Double>("factor") ?: 1.0)
                        .toFloat().coerceIn(0.5f, 5.0f)
                    mouseEmulationSpeed = 8.0f * factor
                    result.success(null)
                }
                "setScrollSensitivity" -> {
                    scrollSensitivity = (call.argument<Double>("sensitivity") ?: 1.0)
                        .toFloat().coerceIn(0.1f, 5.0f)
                    result.success(null)
                }
                "setTriggerDeadzone" -> {
                    triggerDeadzonePercent = (call.argument<Int>("percent") ?: 2).coerceIn(0, 20)
                    result.success(null)
                }
                "setMouseEmulation" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    mouseEmulationActive = enabled
                    if (!enabled) {
                        if (mouseEmuLeftButtonDown) {
                            StreamingBridge.nativeSendMouseButton(MOUSE_RELEASE, MOUSE_BTN_LEFT)
                            mouseEmuLeftButtonDown = false
                        }
                        if (mouseEmuRightButtonDown) {
                            StreamingBridge.nativeSendMouseButton(MOUSE_RELEASE, MOUSE_BTN_RIGHT)
                            mouseEmuRightButtonDown = false
                        }
                        if (mouseEmuMiddleButtonDown) {
                            StreamingBridge.nativeSendMouseButton(MOUSE_RELEASE, MOUSE_BTN_MIDDLE)
                            mouseEmuMiddleButtonDown = false
                        }
                        mouseEmuAHoldRunnable?.let { mainHandler.removeCallbacks(it) }
                        mouseEmuAHoldRunnable = null
                        mouseEmuAHoldFired = false
                    }
                    Log.i(TAG, "MOUSE_EMULATION: active=$mouseEmulationActive")
                    result.success(null)
                }
                "getMouseEmulation" -> {
                    result.success(mouseEmulationActive)
                }
                "getControllerInfo" -> {
                    val infoList = mutableListOf<Map<String, Any>>()
                    for ((deviceId, state) in controllers) {
                        val slot = deviceSlots[deviceId] ?: continue
                        val dev = InputDevice.getDevice(deviceId)
                        infoList.add(mapOf(
                            "slot" to slot,
                            "vendorId" to state.vendorId,
                            "productId" to state.productId,
                            "name" to (dev?.name ?: state.deviceName),
                            "isNonStandardDualShock4" to state.isNonStandardDualShock4,
                            "usesLinuxGamepadStandard" to state.usesLinuxGamepadStandardFaceButtons,
                            "supportedButtonFlags" to state.supportedButtonFlags
                        ))
                    }
                    result.success(infoList)
                }
                "setOverlayTriggerConfig" -> {
                    val combo = call.argument<Int>("combo") ?: (LS_CLK_FLAG or RS_CLK_FLAG)
                    val holdMs = call.argument<Int>("holdMs") ?: 2000
                    overlayTriggerCombo = combo
                    overlayTriggerHoldMs = holdMs.toLong().coerceIn(300, 8000)
                    comboHeldRunnable?.let { mainHandler.removeCallbacks(it) }
                    comboHeldRunnable = null
                    Log.i(TAG, "OVERLAY_TRIGGER: combo=0x${combo.toString(16)}, holdMs=$overlayTriggerHoldMs")
                    result.success(null)
                }
                "setMouseModeConfig" -> {
                    val combo = call.argument<Int>("combo") ?: BACK_FLAG
                    val holdMs = call.argument<Int>("holdMs") ?: 2000
                    mouseModeCombo = combo
                    mouseModeHoldMs = holdMs.toLong().coerceIn(300, 8000)
                    mouseModeHeldRunnable?.let { mainHandler.removeCallbacks(it) }
                    mouseModeHeldRunnable = null
                    Log.i(TAG, "MOUSE_MODE_TRIGGER: combo=0x${combo.toString(16)}, holdMs=$mouseModeHoldMs")
                    result.success(null)
                }
                "setPanicComboConfig" -> {
                    val combo = call.argument<Int>("combo") ?: 0
                    val holdMs = call.argument<Int>("holdMs") ?: 2000
                    panicCombo = combo
                    panicHoldMs = holdMs.toLong().coerceIn(300, 8000)
                    panicHeldRunnable?.let { mainHandler.removeCallbacks(it) }
                    panicHeldRunnable = null
                    Log.i(TAG, "PANIC_COMBO: combo=0x${combo.toString(16)}, holdMs=$panicHoldMs")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun countGamepads(): Int {
        return InputDevice.getDeviceIds().count { id ->
            val dev = InputDevice.getDevice(id) ?: return@count false
            isGamepadDevice(dev)
        }
    }

    private fun detectControllers(): Int {
        controllers.clear()
        deviceSlots.clear()
        currentControllers = 0

        isDetecting = true
        for (id in InputDevice.getDeviceIds()) {
            val dev = InputDevice.getDevice(id) ?: continue
            if (isGamepadDevice(dev)) {
                ensureController(id, dev)
                if (Integer.bitCount(currentControllers.toInt()) >= MAX_GAMEPADS) break
            }
        }
        isDetecting = false

        if (isStreaming) {
            val sentSlots = mutableSetOf<Int>()
            for ((deviceId, state) in controllers) {
                val slot = deviceSlots[deviceId] ?: continue
                if (slot in sentSlots) continue
                sentSlots.add(slot)
                if (!state.arrivalSent) {
                    sendNativeControllerArrival(deviceId, slot, state)
                }
            }
        }
        val uniqueControllers = Integer.bitCount(currentControllers.toInt())
        Log.i(TAG, "Detected $uniqueControllers gamepad(s), mask=0x${currentControllers.toInt().toString(16)}")
        return uniqueControllers
    }

    private fun isGamepadDevice(dev: InputDevice): Boolean {
        val name = dev.name?.lowercase() ?: ""

        if (name.contains("remote")) return false

        if (name.contains("pair")) return false

        val joyConDevice = isJoyConDevice(dev)
        if (joyConDevice && !joyConEnabled) return false

        val src = dev.sources
        val hasGamepadSource  = (src and InputDevice.SOURCE_GAMEPAD)  == InputDevice.SOURCE_GAMEPAD
        val hasJoystickSource = (src and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
        val hasDpadSource = (src and InputDevice.SOURCE_DPAD) == InputDevice.SOURCE_DPAD

        if (!hasGamepadSource && !hasJoystickSource && !hasDpadSource) return false

        // Some BT HID stacks (e.g. Chromecast GTV) report axes under SOURCE_GAMEPAD
        // instead of SOURCE_JOYSTICK. Check both so we don't miss the controller.
        val hasLeftStick =
            (dev.getMotionRange(MotionEvent.AXIS_X, InputDevice.SOURCE_JOYSTICK) != null ||
             (hasGamepadSource && dev.getMotionRange(MotionEvent.AXIS_X, InputDevice.SOURCE_GAMEPAD) != null)) &&
            (dev.getMotionRange(MotionEvent.AXIS_Y, InputDevice.SOURCE_JOYSTICK) != null ||
             (hasGamepadSource && dev.getMotionRange(MotionEvent.AXIS_Y, InputDevice.SOURCE_GAMEPAD) != null))
        val hasDpadAxes  =
            (dev.getMotionRange(MotionEvent.AXIS_HAT_X, InputDevice.SOURCE_JOYSTICK) != null ||
             (hasGamepadSource && dev.getMotionRange(MotionEvent.AXIS_HAT_X, InputDevice.SOURCE_GAMEPAD) != null)) &&
            (dev.getMotionRange(MotionEvent.AXIS_HAT_Y, InputDevice.SOURCE_JOYSTICK) != null ||
             (hasGamepadSource && dev.getMotionRange(MotionEvent.AXIS_HAT_Y, InputDevice.SOURCE_GAMEPAD) != null))

        val hasFaceButtons = hasGamepadSource && dev.hasKeys(
            KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_BUTTON_B,
            KeyEvent.KEYCODE_BUTTON_X, KeyEvent.KEYCODE_BUTTON_Y
        ).any { it }

        // Sony PS controllers (vendor 0x054C) are always gamepads — some TV BT stacks
        // don't fully report sources/keycodes so use vendor ID as authoritative fallback.
        val isSonyController = dev.vendorId == 0x054C && hasGamepadSource

        if (hasLeftStick || hasDpadAxes || hasFaceButtons || isSonyController) return true
        if (joyConDevice && joyConEnabled) return true
        return isRelaxedUsbGamepad(dev)
    }

    private fun isJoyConDevice(dev: InputDevice): Boolean {
        val name = dev.name?.lowercase() ?: ""
        return name.contains("joy-con") ||
            name.contains("joycon") ||
            (dev.vendorId == 0x057e && name.contains("nintendo"))
    }

    private fun isRelaxedUsbGamepad(dev: InputDevice): Boolean {
        if (!usbDriverEnabled) return false

        val src = dev.sources
        val hasDpadSource = (src and InputDevice.SOURCE_DPAD) == InputDevice.SOURCE_DPAD
        val hasGamepadSource = (src and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
        val hasJoystickSource = (src and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
        val likelyExternal = dev.isExternal || dev.vendorId != 0

        if (!likelyExternal) return false
        if (!hasDpadSource && !hasGamepadSource && !hasJoystickSource) return false

        return usbBindAllEnabled || hasGamepadButtons(dev)
    }

    private fun isPhysicalKeyboard(dev: InputDevice): Boolean {
        val src = dev.sources

        return (src and InputDevice.SOURCE_KEYBOARD) == InputDevice.SOURCE_KEYBOARD &&
               dev.keyboardType == InputDevice.KEYBOARD_TYPE_ALPHABETIC &&
               !isGamepadDevice(dev)
    }

    fun handleKeyEvent(event: KeyEvent): Boolean {

        if (isStreaming && event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            Log.i(TAG, "STREAM_KEY: keyCode=${event.keyCode}(${KeyEvent.keyCodeToString(event.keyCode)}), scanCode=${event.scanCode}, deviceId=${event.deviceId}, overlay=$overlayVisible")
        }
        if (!isStreaming) return false

        val device = InputDevice.getDevice(event.deviceId) ?: return false

        if (isPhysicalKeyboard(device)) {

            if (overlayVisible) return false
            return handlePhysicalKeyboardEvent(event)
        }

        if (!isGamepadDevice(device)) return false

        if (overlayVisible) return false

        val deviceId = event.deviceId
        ensureController(deviceId, device)
        val state = controllers[deviceId] ?: return false
        val slot = deviceSlots[deviceId] ?: 0

        val remappedKeyCode = handleRemapping(event, state)
        if (remappedKeyCode < 0) {
            return remappedKeyCode == REMAP_CONSUME
        }

        val btnFlag = keyToFlag(remappedKeyCode)

        if (remappedKeyCode == KeyEvent.KEYCODE_BUTTON_THUMBL) {
            state.l3Down = event.action == KeyEvent.ACTION_DOWN
            if (mouseEmulationActive) {
                when (event.action) {
                    KeyEvent.ACTION_DOWN -> {
                        if (!mouseEmuMiddleButtonDown) {
                            mouseEmuMiddleButtonDown = true
                            StreamingBridge.nativeSendMouseButton(MOUSE_PRESS, MOUSE_BTN_MIDDLE)
                        }
                    }
                    KeyEvent.ACTION_UP -> {
                        if (mouseEmuMiddleButtonDown) {
                            mouseEmuMiddleButtonDown = false
                            StreamingBridge.nativeSendMouseButton(MOUSE_RELEASE, MOUSE_BTN_MIDDLE)
                        }
                    }
                }
                checkMouseModeCombo(state)
                return true
            }
            if (btnFlag != null) {
                when (event.action) {
                    KeyEvent.ACTION_DOWN -> { state.buttonFlags = state.buttonFlags or btnFlag; sendInput(slot, state) }
                    KeyEvent.ACTION_UP   -> { state.buttonFlags = state.buttonFlags and btnFlag.inv(); sendInput(slot, state) }
                }
            }
            checkOverlayTriggerCombo(state)
            checkMouseModeCombo(state)
            return true
        }
        if (remappedKeyCode == KeyEvent.KEYCODE_BUTTON_THUMBR) {
            state.r3Down = event.action == KeyEvent.ACTION_DOWN
            if (btnFlag != null) {
                when (event.action) {
                    KeyEvent.ACTION_DOWN -> { state.buttonFlags = state.buttonFlags or btnFlag; sendInput(slot, state) }
                    KeyEvent.ACTION_UP   -> { state.buttonFlags = state.buttonFlags and btnFlag.inv(); sendInput(slot, state) }
                }
            }
            checkOverlayTriggerCombo(state)
            checkMouseModeCombo(state)
            return true
        }

        if (remappedKeyCode == KeyEvent.KEYCODE_BUTTON_L2) {
            if (state.leftTriggerAxis == -1 || !state.leftTriggerAxisUsed) {
                state.leftTrigger = if (event.action == KeyEvent.ACTION_DOWN) 0xFF.toByte() else 0
                sendInput(slot, state)
            }
            checkOverlayTriggerCombo(state)
            checkMouseModeCombo(state)
            return true
        }
        if (remappedKeyCode == KeyEvent.KEYCODE_BUTTON_R2) {
            if (state.rightTriggerAxis == -1 || !state.rightTriggerAxisUsed) {
                state.rightTrigger = if (event.action == KeyEvent.ACTION_DOWN) 0xFF.toByte() else 0
                sendInput(slot, state)
            }
            checkOverlayTriggerCombo(state)
            checkMouseModeCombo(state)
            return true
        }

        val flag = keyToFlag(remappedKeyCode) ?: return false

        when (event.action) {
            KeyEvent.ACTION_DOWN -> return handleButtonDown(event, state, slot, flag)
            KeyEvent.ACTION_UP   -> return handleButtonUp(event, state, slot, flag)
        }
        return false
    }

    private fun runEmulationChecks(state: ControllerState, eventTime: Long) {

        if (!state.hasSelect) {
            if (state.buttonFlags == (PLAY_FLAG or LB_FLAG) ||
                (state.buttonFlags == PLAY_FLAG &&
                 eventTime - state.lastLbUpTime <= MAXIMUM_BUMPER_UP_DELAY_MS)) {
                state.buttonFlags = state.buttonFlags and (PLAY_FLAG or LB_FLAG).inv()
                state.buttonFlags = state.buttonFlags or BACK_FLAG
                state.emulatingButtonFlags = state.emulatingButtonFlags or EMULATING_SELECT
            }
        }

        if (!state.hasMode) {
            if (state.hasSelect) {
                if (state.buttonFlags == (PLAY_FLAG or BACK_FLAG)) {
                    state.buttonFlags = state.buttonFlags and (PLAY_FLAG or BACK_FLAG).inv()
                    state.buttonFlags = state.buttonFlags or SPECIAL_FLAG
                    state.emulatingButtonFlags = state.emulatingButtonFlags or EMULATING_SPECIAL
                }
            } else {
                if (state.buttonFlags == (PLAY_FLAG or RB_FLAG) ||
                    (state.buttonFlags == PLAY_FLAG &&
                     eventTime - state.lastRbUpTime <= MAXIMUM_BUMPER_UP_DELAY_MS)) {
                    state.buttonFlags = state.buttonFlags and (PLAY_FLAG or RB_FLAG).inv()
                    state.buttonFlags = state.buttonFlags or SPECIAL_FLAG
                    state.emulatingButtonFlags = state.emulatingButtonFlags or EMULATING_SPECIAL
                }
            }
        }
    }

    private fun flushPendingCombo(state: ControllerState, slot: Int, eventTime: Long) {
        if (state.pendingComboFlags == 0) return
        state.buttonFlags = state.buttonFlags or state.pendingComboFlags
        state.pendingComboFlags = 0
        runEmulationChecks(state, eventTime)
        sendInput(slot, state)
    }

    private fun checkOverlayTriggerCombo(state: ControllerState) {
        if (overlayTriggerCombo == 0) return
        // Build effective flags including virtual trigger bits
        var effective = state.buttonFlags
        if (state.leftTrigger.toInt() and 0xFF > 100) effective = effective or LT_VIRTUAL_FLAG
        if (state.rightTrigger.toInt() and 0xFF > 100) effective = effective or RT_VIRTUAL_FLAG
        val allHeld = (effective and overlayTriggerCombo) == overlayTriggerCombo
        if (allHeld) {
            if (comboHeldRunnable == null) {
                comboHeldRunnable = Runnable {
                    comboHeldRunnable = null
                    var eff = state.buttonFlags
                    if (state.leftTrigger.toInt() and 0xFF > 100) eff = eff or LT_VIRTUAL_FLAG
                    if (state.rightTrigger.toInt() and 0xFF > 100) eff = eff or RT_VIRTUAL_FLAG
                    if ((eff and overlayTriggerCombo) == overlayTriggerCombo) {
                        overlayVisible = true
                        mainHandler.post {
                            methodChannel.invokeMethod("onComboDetected", null)
                        }
                    }
                }
                mainHandler.postDelayed(comboHeldRunnable!!, overlayTriggerHoldMs)
            }
        } else {
            comboHeldRunnable?.let { mainHandler.removeCallbacks(it) }
            comboHeldRunnable = null
        }
    }

    private fun checkMouseModeCombo(state: ControllerState) {
        if (mouseModeCombo == 0) return
        var effective = state.buttonFlags
        if (state.leftTrigger.toInt() and 0xFF > 100) effective = effective or LT_VIRTUAL_FLAG
        if (state.rightTrigger.toInt() and 0xFF > 100) effective = effective or RT_VIRTUAL_FLAG
        val allHeld = (effective and mouseModeCombo) == mouseModeCombo
        if (allHeld) {
            if (mouseModeHeldRunnable == null) {
                mouseModeHeldRunnable = Runnable {
                    mouseModeHeldRunnable = null
                    var eff = state.buttonFlags
                    if (state.leftTrigger.toInt() and 0xFF > 100) eff = eff or LT_VIRTUAL_FLAG
                    if (state.rightTrigger.toInt() and 0xFF > 100) eff = eff or RT_VIRTUAL_FLAG
                    if ((eff and mouseModeCombo) == mouseModeCombo) {
                        Log.i(TAG, "MOUSE_MODE_TOGGLE: combo triggered after ${mouseModeHoldMs}ms hold")
                        mainHandler.post {
                            methodChannel.invokeMethod("onMouseModeToggle", null)
                        }
                    }
                }
                mainHandler.postDelayed(mouseModeHeldRunnable!!, mouseModeHoldMs)
            }
        } else {
            mouseModeHeldRunnable?.let { mainHandler.removeCallbacks(it) }
            mouseModeHeldRunnable = null
        }
    }

    private fun checkPanicCombo(state: ControllerState) {
        if (panicCombo == 0) return
        var effective = state.buttonFlags
        if (state.leftTrigger.toInt() and 0xFF > 100) effective = effective or LT_VIRTUAL_FLAG
        if (state.rightTrigger.toInt() and 0xFF > 100) effective = effective or RT_VIRTUAL_FLAG
        val allHeld = (effective and panicCombo) == panicCombo
        if (allHeld) {
            if (panicHeldRunnable == null) {
                panicHeldRunnable = Runnable {
                    panicHeldRunnable = null
                    var eff = state.buttonFlags
                    if (state.leftTrigger.toInt() and 0xFF > 100) eff = eff or LT_VIRTUAL_FLAG
                    if (state.rightTrigger.toInt() and 0xFF > 100) eff = eff or RT_VIRTUAL_FLAG
                    if ((eff and panicCombo) == panicCombo) {
                        Log.i(TAG, "PANIC_COMBO: triggered after ${panicHoldMs}ms hold — emergency session kill")
                        mainHandler.post {
                            methodChannel.invokeMethod("onPanicComboDetected", null)
                        }
                    }
                }
                mainHandler.postDelayed(panicHeldRunnable!!, panicHoldMs)
            }
        } else {
            panicHeldRunnable?.let { mainHandler.removeCallbacks(it) }
            panicHeldRunnable = null
        }
    }

    private fun handleButtonDown(event: KeyEvent, state: ControllerState, slot: Int, flag: Int): Boolean {

        if (mouseEmulationActive) {
            when (flag) {
                A_FLAG -> {
                    mouseEmuADownTime = event.eventTime
                    mouseEmuAHoldFired = false
                    mouseEmuAHoldRunnable?.let { mainHandler.removeCallbacks(it) }
                    mouseEmuAHoldRunnable = Runnable {
                        mouseEmuAHoldRunnable = null
                        mouseEmuAHoldFired = true
                        if (!mouseEmuRightButtonDown) {
                            mouseEmuRightButtonDown = true
                            StreamingBridge.nativeSendMouseButton(MOUSE_PRESS, MOUSE_BTN_RIGHT)
                        }
                    }
                    mainHandler.postDelayed(mouseEmuAHoldRunnable!!, mouseEmuAHoldThresholdMs)
                    return true
                }
                B_FLAG -> {
                    StreamingBridge.nativeSendMouseButton(MOUSE_PRESS, MOUSE_BTN_RIGHT)
                    return true
                }
            }
        }

        if (flag == BACK_FLAG && backButtonAction == BACK_ACTION_META && event.repeatCount == 0) {
            sendMetaKey(true)
        }

        if (flag == PLAY_FLAG && event.repeatCount == 0) {
            state.startDownTime = event.eventTime
        }
        if (flag == BACK_FLAG && event.repeatCount == 0) {
            state.selectDownTime = event.eventTime
        }

        if (flag == BACK_FLAG) state.hasSelect = true
        if (flag == SPECIAL_FLAG) state.hasMode = true

        state.buttonFlags = state.buttonFlags or flag

        if (state.buttonFlags and QUIT_COMBO_MASK == QUIT_COMBO_MASK) {
            state.pendingExit = true
        }

        runEmulationChecks(state, event.eventTime)

        sendInput(slot, state)
        checkOverlayTriggerCombo(state)
        checkMouseModeCombo(state)
        checkPanicCombo(state)
        return true
    }

    private fun handleButtonUp(event: KeyEvent, state: ControllerState, slot: Int, flag: Int): Boolean {

        if (mouseEmulationActive) {
            when (flag) {
                A_FLAG -> {
                    mouseEmuAHoldRunnable?.let { mainHandler.removeCallbacks(it) }
                    mouseEmuAHoldRunnable = null
                    if (mouseEmuAHoldFired) {
                        if (mouseEmuRightButtonDown) {
                            mouseEmuRightButtonDown = false
                            StreamingBridge.nativeSendMouseButton(MOUSE_RELEASE, MOUSE_BTN_RIGHT)
                        }
                    } else {
                        StreamingBridge.nativeSendMouseButton(MOUSE_PRESS, MOUSE_BTN_LEFT)
                        StreamingBridge.nativeSendMouseButton(MOUSE_RELEASE, MOUSE_BTN_LEFT)
                    }
                    mouseEmuAHoldFired = false
                    return true
                }
                B_FLAG -> {
                    StreamingBridge.nativeSendMouseButton(MOUSE_RELEASE, MOUSE_BTN_RIGHT)
                    return true
                }
            }
        }

        if (flag == BACK_FLAG && backButtonAction == BACK_ACTION_META) {
            sendMetaKey(false)
        }

        if (flag == PLAY_FLAG) {
            val holdMs = event.eventTime - state.startDownTime
            Log.i(TAG, "START_RELEASE: holdMs=$holdMs, " +
                "startDownTime=${state.startDownTime}, eventTime=${event.eventTime}, " +
                "buttonFlags=0x${state.buttonFlags.toString(16)}, pendingExit=${state.pendingExit}")
        }

        if (flag == LB_FLAG) state.lastLbUpTime = event.eventTime
        if (flag == RB_FLAG) state.lastRbUpTime = event.eventTime

        state.buttonFlags = state.buttonFlags and flag.inv()

        if ((state.emulatingButtonFlags and EMULATING_SELECT) != 0) {
            if ((state.buttonFlags and PLAY_FLAG) == 0 ||
                (state.buttonFlags and LB_FLAG) == 0) {
                state.buttonFlags = state.buttonFlags and BACK_FLAG.inv()
                state.emulatingButtonFlags = state.emulatingButtonFlags and EMULATING_SELECT.inv()
            }
        }

        if ((state.emulatingButtonFlags and EMULATING_SPECIAL) != 0) {
            if ((state.buttonFlags and PLAY_FLAG) == 0 ||
                ((state.buttonFlags and BACK_FLAG) == 0 &&
                 (state.buttonFlags and RB_FLAG) == 0)) {
                state.buttonFlags = state.buttonFlags and SPECIAL_FLAG.inv()
                state.emulatingButtonFlags = state.emulatingButtonFlags and EMULATING_SPECIAL.inv()
            }
        }

        if (state.pendingExit) {
            if ((state.buttonFlags and QUIT_COMBO_MASK) == 0) {

                state.pendingExit = false
                state.buttonFlags = 0
                sendInput(slot, state)
                overlayVisible = true
                mainHandler.post {
                    methodChannel.invokeMethod("onComboDetected", null)
                }
                return true
            }
        }

        sendInput(slot, state)
        checkOverlayTriggerCombo(state)
        checkMouseModeCombo(state)
        return true
    }

    fun handleMotionEvent(event: MotionEvent): Boolean {
        if (!isStreaming) return false

        val source = event.source

        val isMouse = (source and InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE
        if (isMouse) {

            if (overlayVisible) return false

            val action = event.actionMasked

            if (action == MotionEvent.ACTION_HOVER_MOVE ||
                action == MotionEvent.ACTION_MOVE) {
                val x = event.x
                val y = event.y
                if (lastMouseX >= 0f) {
                    val rawDx = (x - lastMouseX) * mouseSensitivity
                    val rawDy = (y - lastMouseY) * mouseSensitivity
                    val dx = rawDx.toInt().coerceIn(-32767, 32767).toShort()
                    val dy = rawDy.toInt().coerceIn(-32767, 32767).toShort()
                    if (dx != 0.toShort() || dy != 0.toShort()) {
                        StreamingBridge.nativeSendMouseMove(dx, dy)
                    }
                }
                lastMouseX = x
                lastMouseY = y
                return true
            }

            if (action == MotionEvent.ACTION_HOVER_ENTER ||
                action == MotionEvent.ACTION_HOVER_EXIT) {
                lastMouseX = event.x
                lastMouseY = event.y
                return true
            }

            if (action == MotionEvent.ACTION_BUTTON_PRESS ||
                action == MotionEvent.ACTION_BUTTON_RELEASE) {
                val androidBtn = event.actionButton
                val moonBtn = androidMouseButtonToMoonlight(androidBtn)
                if (moonBtn != null) {
                    val btnAction: Byte =
                        if (action == MotionEvent.ACTION_BUTTON_PRESS) 0x07 else 0x08
                    StreamingBridge.nativeSendMouseButton(btnAction, moonBtn)
                }
                prevMouseButtonState = event.buttonState
                return true
            }

            if (action == MotionEvent.ACTION_SCROLL) {
                val vScroll = event.getAxisValue(MotionEvent.AXIS_VSCROLL)
                if (vScroll != 0f) {

                    val scrollTicks = (vScroll * 120f * scrollSensitivity)
                        .toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    StreamingBridge.nativeSendScroll(scrollTicks)
                }
                val hScroll = event.getAxisValue(MotionEvent.AXIS_HSCROLL)
                if (hScroll != 0f) {
                    val hTicks = (hScroll * 120f * scrollSensitivity)
                        .toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    StreamingBridge.nativeSendHighResHScroll(hTicks)
                }
                return true
            }

            return false
        }

        // Route touchpad motion events (PS controller touchpad) to the dedicated handler
        val isTouchpad = (source and InputDevice.SOURCE_TOUCHPAD) == InputDevice.SOURCE_TOUCHPAD
        if (isTouchpad) return handleTouchpadEvent(event)

        val isGamepad = (source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK ||
                        (source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
        if (!isGamepad) return false

        if (overlayVisible) {
            val hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X)
            val hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
            val stickX = event.getAxisValue(MotionEvent.AXIS_X)
            val stickY = event.getAxisValue(MotionEvent.AXIS_Y)

            val dir = when {
                hatY < -0.5f || stickY < -0.6f -> "up"
                hatY > 0.5f  || stickY > 0.6f  -> "down"
                hatX < -0.5f || stickX < -0.6f -> "left"
                hatX > 0.5f  || stickX > 0.6f  -> "right"
                else -> null
            }
            if (dir != null && dir != lastOverlayHatDir) {
                lastOverlayHatDir = dir
                mainHandler.post {
                    methodChannel.invokeMethod("onOverlayDpad", dir)
                }
            } else if (dir == null) {
                lastOverlayHatDir = null
            }
            return true
        }

        val deviceId = event.deviceId
        ensureController(deviceId)
        val state = controllers[deviceId] ?: return false
        val slot = deviceSlots[deviceId] ?: 0

        if (mouseEmulationActive) {
            val lx = event.getAxisValue(MotionEvent.AXIS_X)
            val ly = event.getAxisValue(MotionEvent.AXIS_Y)
            val rx = event.getAxisValue(state.rightStickXAxis)
            val ry = event.getAxisValue(state.rightStickYAxis)

            val dzFraction = deadzonePercent.coerceIn(0, 50) / 100f
            val lMag = sqrt(lx * lx + ly * ly)
            val rMag = sqrt(rx * rx + ry * ry)

            if (lMag > dzFraction) {
                val scale = ((lMag - dzFraction) / (1f - dzFraction)).coerceIn(0f, 1f)
                val nx = lx / lMag * scale
                val ny = ly / lMag * scale
                val dx = (nx * mouseEmulationSpeed * mouseSensitivity).toInt().toShort()
                val dy = (ny * mouseEmulationSpeed * mouseSensitivity).toInt().toShort()
                if (dx.toInt() != 0 || dy.toInt() != 0) {
                    StreamingBridge.nativeSendMouseMove(dx, dy)
                }
            }

            if (rMag > dzFraction) {
                val scale = ((rMag - dzFraction) / (1f - dzFraction)).coerceIn(0f, 1f)
                val ny = ry / rMag * scale
                val scrollY = (-ny * scrollSensitivity * 3f).toInt().toShort()
                if (scrollY.toInt() != 0) {
                    StreamingBridge.nativeSendScroll(scrollY)
                }
            }

            val hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X)
            val hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
            state.buttonFlags = state.buttonFlags and DPAD_MASK.inv()
            if (hatX < -0.5f) state.buttonFlags = state.buttonFlags or LEFT_FLAG
            else if (hatX > 0.5f) state.buttonFlags = state.buttonFlags or RIGHT_FLAG
            if (hatY < -0.5f) state.buttonFlags = state.buttonFlags or UP_FLAG
            else if (hatY > 0.5f) state.buttonFlags = state.buttonFlags or DOWN_FLAG

            state.leftStickX = 0
            state.leftStickY = 0
            state.rightStickX = 0
            state.rightStickY = 0
            state.leftTrigger = 0
            state.rightTrigger = 0
            sendInput(slot, state)
            return true
        }

        if (state.pendingComboFlags != 0) {
            flushPendingCombo(state, slot, android.os.SystemClock.uptimeMillis())
        }

        val lx = event.getAxisValue(MotionEvent.AXIS_X)
        val ly = -event.getAxisValue(MotionEvent.AXIS_Y)
        val rx = event.getAxisValue(state.rightStickXAxis)
        val ry = -event.getAxisValue(state.rightStickYAxis)
        val (dlx, dly) = applyDeadzoneAndCurve(lx, ly)
        val (drx, dry) = applyDeadzoneAndCurve(rx, ry)
        state.leftStickX  = dlx
        state.leftStickY  = dly
        state.rightStickX = drx
        state.rightStickY = dry

        if (state.leftTriggerAxis != -1) {
            var ltVal = event.getAxisValue(state.leftTriggerAxis)
            if (state.triggersIdleNegative) ltVal = (ltVal + 1f) / 2f
            ltVal = applyTriggerDeadzone(ltVal)
            state.leftTrigger = (ltVal * 255f).toInt().coerceIn(0, 255).toByte()
            if (ltVal > 0f) state.leftTriggerAxisUsed = true
        }
        if (state.rightTriggerAxis != -1) {
            var rtVal = event.getAxisValue(state.rightTriggerAxis)
            if (state.triggersIdleNegative) rtVal = (rtVal + 1f) / 2f
            rtVal = applyTriggerDeadzone(rtVal)
            state.rightTrigger = (rtVal * 255f).toInt().coerceIn(0, 255).toByte()
            if (rtVal > 0f) state.rightTriggerAxisUsed = true
        }

        val hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X)
        val hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
        state.buttonFlags = state.buttonFlags and DPAD_MASK.inv()
        if (hatX < -0.5f) state.buttonFlags = state.buttonFlags or LEFT_FLAG
        else if (hatX > 0.5f) state.buttonFlags = state.buttonFlags or RIGHT_FLAG
        if (hatY < -0.5f) state.buttonFlags = state.buttonFlags or UP_FLAG
        else if (hatY > 0.5f) state.buttonFlags = state.buttonFlags or DOWN_FLAG

        sendInput(slot, state)
        checkOverlayTriggerCombo(state)
        checkMouseModeCombo(state)
        checkPanicCombo(state)
        return true
    }

    fun handleTouchpadEvent(event: MotionEvent): Boolean {
        if (!isStreaming || overlayVisible) return false

        val source = event.source
        val isTouchpad = (source and InputDevice.SOURCE_TOUCHPAD) == InputDevice.SOURCE_TOUCHPAD
        if (!isTouchpad) return false

        val deviceId = event.deviceId
        val state = controllers[deviceId]

        if (touchpadAsMouse) {

            val x = event.getAxisValue(MotionEvent.AXIS_X)
            val y = event.getAxisValue(MotionEvent.AXIS_Y)
            val touchState = state ?: ControllerState()

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    touchState.lastTouchX = x
                    touchState.lastTouchY = y
                }
                MotionEvent.ACTION_MOVE -> {
                    if (touchState.lastTouchX >= 0f) {
                        val dx = (x - touchState.lastTouchX).toInt().toShort()
                        val dy = (y - touchState.lastTouchY).toInt().toShort()
                        if (dx != 0.toShort() || dy != 0.toShort()) {
                            StreamingBridge.nativeSendMouseMove(dx, dy)
                        }
                    }
                    touchState.lastTouchX = x
                    touchState.lastTouchY = y
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    touchState.lastTouchX = -1f
                    touchState.lastTouchY = -1f
                }
            }
        } else {

            val eventType: Byte = when (event.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> 0x01
                MotionEvent.ACTION_MOVE -> 0x02
                MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> 0x03
                MotionEvent.ACTION_CANCEL -> 0x04
                else -> return false
            }

            // LiSendTouchEvent expects normalized 0.0–1.0 coordinates.
            // Touchpad coords are in the device's raw axis range (e.g.
            // 0–1920 for DualSense). Normalize using the axis max values.
            val tpDevice = event.device
            val xRange = tpDevice?.getMotionRange(MotionEvent.AXIS_X, event.source)
            val yRange = tpDevice?.getMotionRange(MotionEvent.AXIS_Y, event.source)
            val xMax = xRange?.max?.coerceAtLeast(1f) ?: 1f
            val yMax = yRange?.max?.coerceAtLeast(1f) ?: 1f

            for (i in 0 until event.pointerCount) {
                val nx = (event.getX(i) / xMax).coerceIn(0f, 1f)
                val ny = (event.getY(i) / yMax).coerceIn(0f, 1f)
                StreamingBridge.nativeSendTouchEvent(
                    eventType,
                    event.getPointerId(i),
                    nx, ny,
                    event.getPressure(i),
                    event.getTouchMajor(i), event.getTouchMinor(i),
                    event.getOrientation(i).toInt().toShort()
                )
            }
        }
        return true
    }

    private fun applyTriggerDeadzone(raw: Float): Float {
        val dz = triggerDeadzonePercent.toFloat() / 100f
        if (raw <= dz) return 0f
        return ((raw - dz) / (1f - dz)).coerceIn(0f, 1f)
    }

    private fun applyDeadzoneAndCurve(rawX: Float, rawY: Float): Pair<Short, Short> {
        val mag = sqrt(rawX * rawX + rawY * rawY)
        if (mag < 0.001f) return Pair(0, 0)

        val dzFraction = deadzonePercent.toFloat() / 100f
        val dzRadius = dzFraction.coerceAtLeast(0f)

        if (mag <= dzRadius) return Pair(0, 0)

        val cappedMag = mag.coerceAtMost(1.0f)
        val rescaled = if (dzRadius < 1.0f) {
            (cappedMag - dzRadius) / (1.0f - dzRadius)
        } else {
            0f
        }

        val curved = rescaled.toDouble().pow(responseCurve.toDouble()).toFloat()

        val normX = rawX / mag
        val normY = rawY / mag
        val outX = (normX * curved * STICK_MAX).toInt().coerceIn(-32767, 32767).toShort()
        val outY = (normY * curved * STICK_MAX).toInt().coerceIn(-32767, 32767).toShort()
        return Pair(outX, outY)
    }

    fun handleRumble(controllerNumber: Int, lowFreqMotor: Int, highFreqMotor: Int) {
        if (!rumbleEnabled) return

        val deviceId = deviceSlots.entries.firstOrNull { it.value == controllerNumber }?.key
            ?: return
        val device = InputDevice.getDevice(deviceId) ?: return
        var handledByController = false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {

            val vm = device.vibratorManager
            val vibratorIds = vm.vibratorIds
            if (vibratorIds.isNotEmpty()) {
                handledByController = true

                val lfAmp = (lowFreqMotor * 255 / 65535).coerceIn(0, 255)
                val hfAmp = (highFreqMotor * 255 / 65535).coerceIn(0, 255)

                if (lfAmp > 0 || hfAmp > 0) {

                    if (lfAmp > 0) {
                        vm.getVibrator(vibratorIds[0]).vibrate(
                            VibrationEffect.createOneShot(120, lfAmp)
                        )
                    } else {
                        vm.getVibrator(vibratorIds[0]).cancel()
                    }

                    if (vibratorIds.size >= 2) {
                        if (hfAmp > 0) {
                            vm.getVibrator(vibratorIds[1]).vibrate(
                                VibrationEffect.createOneShot(80, hfAmp)
                            )
                        } else {
                            vm.getVibrator(vibratorIds[1]).cancel()
                        }
                    }

                    for (i in 2 until vibratorIds.size) {
                        vm.getVibrator(vibratorIds[i]).cancel()
                    }
                } else {
                    for (id in vibratorIds) {
                        vm.getVibrator(id).cancel()
                    }
                }
            }
        }

        val controllerVibrator = device.vibrator
        if (!handledByController && controllerVibrator.hasVibrator()) {
            handledByController = true
            val amplitude = ((lowFreqMotor + highFreqMotor) / 2).coerceIn(0, 65535)
            val normalizedAmplitude = (amplitude * 255 / 65535).coerceIn(0, 255)
            if (normalizedAmplitude > 0) {
                controllerVibrator.vibrate(VibrationEffect.createOneShot(100, normalizedAmplitude))
            } else {
                controllerVibrator.cancel()
            }
        }

        if ((!handledByController && rumbleFallbackEnabled) || deviceRumbleEnabled) {
            val deviceAmplitude = scaledFallbackAmplitude((lowFreqMotor + highFreqMotor) / 2)
            applyDeviceRumble(deviceAmplitude, 100L)
        }
    }

    fun handleRumbleTriggers(controllerNumber: Int, leftTrigger: Int, rightTrigger: Int) {
        if (!rumbleEnabled) return

        val deviceId = deviceSlots.entries.firstOrNull { it.value == controllerNumber }?.key
            ?: return
        val device = InputDevice.getDevice(deviceId) ?: return
        var handledByController = false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = device.vibratorManager
            val vibratorIds = vm.vibratorIds

            if (vibratorIds.size >= 4) {
                handledByController = true
                val leftAmp = (leftTrigger * 255 / 65535).coerceIn(0, 255)
                val rightAmp = (rightTrigger * 255 / 65535).coerceIn(0, 255)
                if (leftAmp > 0) {
                    vm.getVibrator(vibratorIds[2]).vibrate(VibrationEffect.createOneShot(100, leftAmp))
                } else {
                    vm.getVibrator(vibratorIds[2]).cancel()
                }
                if (rightAmp > 0) {
                    vm.getVibrator(vibratorIds[3]).vibrate(VibrationEffect.createOneShot(100, rightAmp))
                } else {
                    vm.getVibrator(vibratorIds[3]).cancel()
                }
            }
        }

        if ((!handledByController && rumbleFallbackEnabled) || deviceRumbleEnabled) {
            applyDeviceRumble(scaledFallbackAmplitude(max(leftTrigger, rightTrigger)), 90L)
        }
    }

    private fun scaledFallbackAmplitude(rawAmplitude: Int): Int {
        val normalizedAmplitude = (rawAmplitude.coerceIn(0, 65535) * 255 / 65535).coerceIn(0, 255)
        return (normalizedAmplitude * rumbleFallbackStrength / 100).coerceIn(0, 255)
    }

    private fun applyDeviceRumble(amplitude: Int, durationMs: Long) {
        val vibrator = getDeviceVibrator() ?: return
        if (!vibrator.hasVibrator()) return
        if (amplitude > 0) {
            vibrator.vibrate(VibrationEffect.createOneShot(durationMs, amplitude))
        } else {
            vibrator.cancel()
        }
    }

    private fun cancelDeviceRumble() {
        getDeviceVibrator()?.cancel()
    }

    private fun getDeviceVibrator(): Vibrator? {
        @Suppress("DEPRECATION")
        return context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    fun handleSetControllerLED(controllerNumber: Int, r: Int, g: Int, b: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return

        val deviceId = deviceSlots.entries.firstOrNull { it.value == controllerNumber }?.key
            ?: return
        val device = InputDevice.getDevice(deviceId) ?: return

        val lm = device.lightsManager ?: return
        val lights = lm.lights
        if (lights.isEmpty()) return

        val color = android.graphics.Color.rgb(r, g, b)
        val request = android.hardware.lights.LightsRequest.Builder()
        for (light in lights) {
            if (light.hasRgbControl()) {
                request.addLight(light, android.hardware.lights.LightState.Builder()
                    .setColor(color)
                    .build())
            }
        }
        try {
            val session = lm.openSession()
            session.requestLights(request.build())

        } catch (e: Exception) {
            Log.w(TAG, "Failed to set controller LED: ${e.message}")
        }
    }

    fun handleSetMotionEventState(controllerNumber: Int, motionType: Int, reportRateHz: Int) {
        motionControllerNumber = controllerNumber
        motionReportRateHz = reportRateHz

        if (reportRateHz > 0) {
            startMotionSensors(motionType, reportRateHz)
        } else {
            stopMotionSensors()
        }
    }

    private fun startMotionSensors(motionType: Int, rateHz: Int) {
        val sm = sensorManager ?: return
        val delayUs = if (rateHz > 0) 1_000_000 / rateHz else SensorManager.SENSOR_DELAY_GAME

        if (motionType == 0x01 || motionType == 0x03) {
            val accel = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            if (accel != null) sm.registerListener(this, accel, delayUs)
        }
        if (motionType == 0x02 || motionType == 0x03) {
            val gyro = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
            if (gyro != null) sm.registerListener(this, gyro, delayUs)
        }
        Log.i(TAG, "Motion sensors started: type=$motionType, rate=${rateHz}Hz")
    }

    private fun stopMotionSensors() {
        sensorManager?.unregisterListener(this)
        Log.i(TAG, "Motion sensors stopped")
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (!isStreaming) return
        val motionType: Byte = when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> 0x01
            Sensor.TYPE_GYROSCOPE -> 0x02
            else -> return
        }
        StreamingBridge.nativeSendControllerMotionEvent(
            motionControllerNumber.toShort(),
            motionType,
            event.values[0], event.values[1], event.values[2]
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {  }

    override fun onInputDeviceAdded(deviceId: Int) {
        val dev = InputDevice.getDevice(deviceId) ?: return
        if (!isGamepadDevice(dev)) return

        ensureController(deviceId, dev)
        val slot = deviceSlots[deviceId] ?: return
        Log.i(TAG, "Hot-plug: controller added at slot $slot (${dev.name})")
        if (isStreaming) {

            mainHandler.post {
                methodChannel.invokeMethod("onControllerConnected", slot)
            }
        }
    }

    override fun onInputDeviceRemoved(deviceId: Int) {
        val slot = deviceSlots[deviceId]
        if (slot != null) {

            currentControllers = (currentControllers.toInt() and (1 shl slot).inv()).toShort()
            controllers.remove(deviceId)
            deviceSlots.remove(deviceId)
            Log.i(TAG, "Controller removed from slot $slot, mask=0x${currentControllers.toInt().toString(16)}")
            if (isStreaming) {
                mainHandler.post {
                    methodChannel.invokeMethod("onControllerDisconnected", slot)
                }
            }
        }
    }

    override fun onInputDeviceChanged(deviceId: Int) {

        val dev = InputDevice.getDevice(deviceId) ?: return
        if (isGamepadDevice(dev) && controllers.containsKey(deviceId)) {
            val state = controllers[deviceId] ?: return
            val keys = dev.hasKeys(
                KeyEvent.KEYCODE_BUTTON_MODE,
                KeyEvent.KEYCODE_BUTTON_SELECT,
                KeyEvent.KEYCODE_BACK
            )
            state.hasMode = keys[0]
            state.hasSelect = keys[1] || keys[2]
        }
    }

    private fun getActiveControllerMask(): Short = currentControllers

    private fun refreshControllerArrivals() {
        if (!isStreaming) return

        val refreshedSlots = mutableSetOf<Int>()
        for ((deviceId, state) in controllers) {
            val slot = deviceSlots[deviceId] ?: continue
            if (!refreshedSlots.add(slot)) continue
            state.arrivalSent = false
            sendNativeControllerArrival(deviceId, slot, state)
        }
    }

    private fun computeControllerType(state: ControllerState): Byte = when (controllerDriverMode) {
        DRIVER_XBOX360 -> LI_CTYPE_XBOX
        DRIVER_DUALSHOCK, DRIVER_DUALSENSE -> LI_CTYPE_PS
        else -> when (state.vendorId) {
            0x054c -> LI_CTYPE_PS
            0x045e -> LI_CTYPE_XBOX
            0x057e -> LI_CTYPE_NINTENDO
            else -> LI_CTYPE_XBOX
        }
    }

    private fun computeCapabilities(dev: InputDevice, state: ControllerState, type: Byte): Short {
        var caps = 0
        if (state.leftTriggerAxis != -1 || state.rightTriggerAxis != -1) {
            caps = caps or LI_CCAP_ANALOG_TRIGGERS
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val vm = dev.vibratorManager
                val ids = vm?.vibratorIds
                if (ids != null && ids.isNotEmpty()) {
                    caps = caps or LI_CCAP_RUMBLE
                    if (ids.size >= 4) caps = caps or LI_CCAP_TRIGGER_RUMBLE
                }
            } catch (_: Exception) { }
        }
        if ((caps and LI_CCAP_RUMBLE) == 0) {
            try { if (dev.vibrator?.hasVibrator() == true) caps = caps or LI_CCAP_RUMBLE }
            catch (_: Exception) { }
        }
        if ((dev.sources and InputDevice.SOURCE_TOUCHPAD) == InputDevice.SOURCE_TOUCHPAD) {
            caps = caps or LI_CCAP_TOUCHPAD
        }

        when {
            controllerDriverMode == DRIVER_DUALSHOCK -> {
                caps = caps or LI_CCAP_RUMBLE or LI_CCAP_TOUCHPAD
            }
            controllerDriverMode == DRIVER_DUALSENSE -> {
                caps = caps or LI_CCAP_RUMBLE or LI_CCAP_TRIGGER_RUMBLE or
                    LI_CCAP_TOUCHPAD or LI_CCAP_ACCEL or LI_CCAP_GYRO or LI_CCAP_RGB_LED
            }
        }

        if (type == LI_CTYPE_PS && controllerDriverMode == DRIVER_AUTO) {
            caps = caps or LI_CCAP_RUMBLE or LI_CCAP_TRIGGER_RUMBLE or LI_CCAP_TOUCHPAD
            if (state.productId == 0x0ce6 || state.productId == 0x0df2) {
                caps = caps or LI_CCAP_ACCEL or LI_CCAP_GYRO or LI_CCAP_RGB_LED
            }
        }
        return caps.toShort()
    }

    private fun sendNativeControllerArrival(deviceId: Int, slot: Int, state: ControllerState) {
        val dev = InputDevice.getDevice(deviceId) ?: return
        val type = computeControllerType(state)
        val capabilities = computeCapabilities(dev, state, type)
        val mask = getActiveControllerMask()
        val rc = StreamingBridge.nativeSendControllerArrival(
            slot.toShort(), mask, type, capabilities, state.supportedButtonFlags
        )
        state.arrivalSent = true
        Log.i(TAG, "ARRIVAL: slot=$slot mask=0x${mask.toInt().toString(16)} " +
            "type=$type caps=0x${capabilities.toInt().toString(16)} " +
            "btnFlags=0x${state.supportedButtonFlags.toString(16)} rc=$rc")
    }

    private fun toHostButtonFlags(state: ControllerState): Int {
        var hostFlags = state.buttonFlags
        val hasBackFlag = (hostFlags and BACK_FLAG) != 0
        val usesEmulatedSelect = (state.emulatingButtonFlags and EMULATING_SELECT) != 0

        if (hasBackFlag && !usesEmulatedSelect) {
            when (backButtonAction) {
                BACK_ACTION_META -> hostFlags = hostFlags and BACK_FLAG.inv()
                BACK_ACTION_GUIDE -> {
                    hostFlags = hostFlags and BACK_FLAG.inv()
                    hostFlags = hostFlags or SPECIAL_FLAG
                }
            }
        }

        return hostFlags
    }

    private fun sendMetaKey(down: Boolean) {
        val action: Byte = if (down) 0x03 else 0x04
        StreamingBridge.nativeSendKeyboard(0x5B.toShort(), action, 0, 0)
    }

    private fun sendInput(slot: Int, state: ControllerState) {
        val hostButtonFlags = toHostButtonFlags(state)

        if (!state.arrivalSent) {
            val deviceId = deviceSlots.entries.firstOrNull { it.value == slot }?.key
            if (deviceId != null) {
                sendNativeControllerArrival(deviceId, slot, state)
            }
        }

        if (state.hasSentInput &&
            state.lastSentButtonFlags  == hostButtonFlags &&
            state.lastSentLeftTrigger  == state.leftTrigger &&
            state.lastSentRightTrigger == state.rightTrigger &&
            state.lastSentLeftStickX   == state.leftStickX &&
            state.lastSentLeftStickY   == state.leftStickY &&
            state.lastSentRightStickX  == state.rightStickX &&
            state.lastSentRightStickY  == state.rightStickY) {
            return
        }
        state.hasSentInput          = true
        state.lastSentButtonFlags   = hostButtonFlags
        state.lastSentLeftTrigger   = state.leftTrigger
        state.lastSentRightTrigger  = state.rightTrigger
        state.lastSentLeftStickX    = state.leftStickX
        state.lastSentLeftStickY    = state.leftStickY
        state.lastSentRightStickX   = state.rightStickX
        state.lastSentRightStickY   = state.rightStickY

        val mask = getActiveControllerMask()
        val rc = StreamingBridge.nativeSendControllerInput(
            slot.toShort(), mask,
            hostButtonFlags, state.leftTrigger, state.rightTrigger,
            state.leftStickX, state.leftStickY,
            state.rightStickX, state.rightStickY
        )
    }

    private fun ensureController(deviceId: Int, device: InputDevice? = null) {
        if (!controllers.containsKey(deviceId)) {

            val mergeDev = device ?: InputDevice.getDevice(deviceId)
            if (mergeDev != null && mergeDev.vendorId != 0) {
                val newDescriptor = mergeDev.descriptor
                val existing = controllers.entries.firstOrNull { (existingDeviceId, state) ->
                    if (state.vendorId != mergeDev.vendorId || state.productId != mergeDev.productId) {
                        false
                    } else {

                        val existingDev = InputDevice.getDevice(existingDeviceId)
                        existingDev != null && existingDev.descriptor == newDescriptor
                    }
                }
                if (existing != null) {
                    val mergeSlot = deviceSlots[existing.key] ?: return
                    controllers[deviceId] = existing.value
                    deviceSlots[deviceId] = mergeSlot
                    Log.i(TAG, "Merged deviceId=$deviceId into slot $mergeSlot " +
                        "(same physical device: descriptor=$newDescriptor, " +
                        "vendor=0x${mergeDev.vendorId.toString(16)}, product=0x${mergeDev.productId.toString(16)})")
                    return
                } else if (controllers.entries.any { (_, state) ->
                    state.vendorId == mergeDev.vendorId && state.productId == mergeDev.productId
                }) {
                    Log.i(TAG, "Same VID/PID but DIFFERENT descriptor — treating as separate controller " +
                        "(deviceId=$deviceId, descriptor=$newDescriptor, " +
                        "vendor=0x${mergeDev.vendorId.toString(16)}, product=0x${mergeDev.productId.toString(16)})")
                }
            }

            var slot = -1
            for (i in 0 until MAX_GAMEPADS) {
                if ((currentControllers.toInt() and (1 shl i)) == 0) {
                    slot = i
                    currentControllers = (currentControllers.toInt() or (1 shl i)).toShort()
                    break
                }
            }
            if (slot < 0) return
            val state = ControllerState()

            val dev = device ?: InputDevice.getDevice(deviceId)
            if (dev != null) {

                state.vendorId = dev.vendorId
                state.productId = dev.productId
                state.deviceName = dev.name ?: ""

                val keys = dev.hasKeys(
                    KeyEvent.KEYCODE_BUTTON_MODE,
                    KeyEvent.KEYCODE_BUTTON_SELECT,
                    KeyEvent.KEYCODE_BACK
                )
                state.hasMode = keys[0]
                state.hasSelect = keys[1] || keys[2]

                if (dev.vendorId == 0x054c) {
                    val hasButtonC = dev.hasKeys(KeyEvent.KEYCODE_BUTTON_C)[0]
                    val hasRxRy = getMotionRange(dev, MotionEvent.AXIS_RX) != null &&
                                  getMotionRange(dev, MotionEvent.AXIS_RY) != null
                    val hasZRz = getMotionRange(dev, MotionEvent.AXIS_Z) != null &&
                                 getMotionRange(dev, MotionEvent.AXIS_RZ) != null

                    if (hasButtonC) {

                        state.isNonStandardDualShock4 = true
                        state.hasSelect = true
                        state.hasMode = true

                        if (hasRxRy) {
                            state.leftTriggerAxis = MotionEvent.AXIS_RX
                            state.rightTriggerAxis = MotionEvent.AXIS_RY
                            state.triggersIdleNegative = true

                        } else if (hasZRz) {

                            state.leftTriggerAxis = MotionEvent.AXIS_Z
                            state.rightTriggerAxis = MotionEvent.AXIS_RZ
                            state.triggersIdleNegative = true
                        }

                        state.supportedButtonFlags = ALL_STANDARD_BUTTONS or TOUCHPAD_FLAG or MISC_FLAG

                        Log.i(TAG, "Detected non-standard Sony (HID report order, hasButtonC=true, " +
                            "hasZRz=$hasZRz, hasRxRy=$hasRxRy, " +
                            "triggerAxes=${state.leftTriggerAxis}/${state.rightTriggerAxis})")
                    } else {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                            state.usesLinuxGamepadStandardFaceButtons = true
                            Log.i(TAG, "Detected Sony standard on Android < 12 (no hasButtonC, linuxStd applied)")
                        } else {
                            Log.i(TAG, "Detected Sony standard on Android 12+ (relying on native OS mapping)")
                        }
                        state.supportedButtonFlags = ALL_STANDARD_BUTTONS
                    }
                }

                if (!state.isNonStandardDualShock4) {
                    val hasLT = getMotionRange(dev, MotionEvent.AXIS_LTRIGGER) != null
                    val hasRT = getMotionRange(dev, MotionEvent.AXIS_RTRIGGER) != null
                    val hasBrake = getMotionRange(dev, MotionEvent.AXIS_BRAKE) != null
                    val hasGas = getMotionRange(dev, MotionEvent.AXIS_GAS) != null
                    val hasThrottle = getMotionRange(dev, MotionEvent.AXIS_THROTTLE) != null
                    val hasZ = getMotionRange(dev, MotionEvent.AXIS_Z) != null
                    val hasRZ = getMotionRange(dev, MotionEvent.AXIS_RZ) != null

                    when {
                        hasLT && hasRT -> {
                            state.leftTriggerAxis = MotionEvent.AXIS_LTRIGGER
                            state.rightTriggerAxis = MotionEvent.AXIS_RTRIGGER
                        }
                        hasBrake && hasGas -> {
                            state.leftTriggerAxis = MotionEvent.AXIS_BRAKE
                            state.rightTriggerAxis = MotionEvent.AXIS_GAS
                        }
                        hasBrake && hasThrottle -> {
                            state.leftTriggerAxis = MotionEvent.AXIS_BRAKE
                            state.rightTriggerAxis = MotionEvent.AXIS_THROTTLE
                        }
                        hasZ && hasRZ -> {
                            state.leftTriggerAxis = MotionEvent.AXIS_Z
                            state.rightTriggerAxis = MotionEvent.AXIS_RZ
                            state.rightStickXAxis = MotionEvent.AXIS_RX
                            state.rightStickYAxis = MotionEvent.AXIS_RY
                            if (dev.vendorId == 0x054c) {
                                state.triggersIdleNegative = true
                            }
                        }
                        else -> {
                            state.leftTriggerAxis = -1
                            state.rightTriggerAxis = -1
                        }
                    }
                }

                state.ignoreBack = shouldIgnoreBack(dev)

                Log.i(TAG, "Controller context: vendor=0x${dev.vendorId.toString(16)}, " +
                    "product=0x${dev.productId.toString(16)}, name='${dev.name}', " +
                    "ds4NonStd=${state.isNonStandardDualShock4}, linuxStd=${state.usesLinuxGamepadStandardFaceButtons}, " +
                    "triggerAxes=${state.leftTriggerAxis}/${state.rightTriggerAxis}, " +
                    "triggersIdleNeg=${state.triggersIdleNegative}, ignoreBack=${state.ignoreBack}")
            }

            controllers[deviceId] = state
            deviceSlots[deviceId] = slot
            Log.i(TAG, "New controller at slot $slot (deviceId=$deviceId, " +
                "hasSelect=${state.hasSelect}, hasMode=${state.hasMode})")

            if (isStreaming && !isDetecting) {
                sendNativeControllerArrival(deviceId, slot, state)
            }
        }
    }

    private fun getMotionRange(dev: InputDevice, axis: Int): InputDevice.MotionRange? {
        return dev.getMotionRange(axis, InputDevice.SOURCE_JOYSTICK)
    }

    private fun shouldIgnoreBack(dev: InputDevice): Boolean {
        val name = dev.name ?: ""

        if (name.contains("Razer Serval")) return true

        if (!hasJoystickAxes(dev) && name.lowercase().contains("remote")) return false

        return hasJoystickAxes(dev) || hasGamepadButtons(dev)
    }

    private fun hasJoystickAxes(dev: InputDevice): Boolean {
        return getMotionRange(dev, MotionEvent.AXIS_X) != null ||
               getMotionRange(dev, MotionEvent.AXIS_HAT_X) != null
    }

    private fun hasGamepadButtons(dev: InputDevice): Boolean {
        val keys = dev.hasKeys(
            KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_BUTTON_B,
            KeyEvent.KEYCODE_BUTTON_X, KeyEvent.KEYCODE_BUTTON_Y
        )
        return keys.any { it }
    }

    private fun androidMouseButtonToMoonlight(androidButton: Int): Byte? = when (androidButton) {
        MotionEvent.BUTTON_PRIMARY   -> 0x01
        MotionEvent.BUTTON_SECONDARY -> 0x03
        MotionEvent.BUTTON_TERTIARY  -> 0x02
        MotionEvent.BUTTON_BACK      -> 0x04
        MotionEvent.BUTTON_FORWARD   -> 0x05
        else -> null
    }

    private fun handlePhysicalKeyboardEvent(event: KeyEvent): Boolean {
        val vk = when {
            forceQwertyLayoutEnabled -> scanCodeToQwertyVk(event.scanCode) ?: androidKeyToVk(event.keyCode)
            else -> androidKeyToVk(event.keyCode)
        } ?: return false
        val action: Byte = when (event.action) {
            KeyEvent.ACTION_DOWN -> 0x03
            KeyEvent.ACTION_UP   -> 0x04
            else -> return false
        }
        val modifiers = buildModifiers(event)
        StreamingBridge.nativeSendKeyboard(vk.toShort(), action, modifiers, 0)
        return true
    }

    private fun scanCodeToQwertyVk(scanCode: Int): Int? = when (scanCode) {
        2 -> 0x31; 3 -> 0x32; 4 -> 0x33; 5 -> 0x34; 6 -> 0x35
        7 -> 0x36; 8 -> 0x37; 9 -> 0x38; 10 -> 0x39; 11 -> 0x30
        12 -> 0xBD; 13 -> 0xBB
        16 -> 0x51; 17 -> 0x57; 18 -> 0x45; 19 -> 0x52; 20 -> 0x54
        21 -> 0x59; 22 -> 0x55; 23 -> 0x49; 24 -> 0x4F; 25 -> 0x50
        26 -> 0xDB; 27 -> 0xDD
        30 -> 0x41; 31 -> 0x53; 32 -> 0x44; 33 -> 0x46; 34 -> 0x47
        35 -> 0x48; 36 -> 0x4A; 37 -> 0x4B; 38 -> 0x4C
        39 -> 0xBA; 40 -> 0xDE; 41 -> 0xC0; 43 -> 0xDC
        44 -> 0x5A; 45 -> 0x58; 46 -> 0x43; 47 -> 0x56; 48 -> 0x42
        49 -> 0x4E; 50 -> 0x4D
        51 -> 0xBC; 52 -> 0xBE; 53 -> 0xBF
        57 -> 0x20
        else -> null
    }

    private fun buildModifiers(event: KeyEvent): Byte {
        var mods = 0
        if (event.isShiftPressed) mods = mods or 0x01
        if (event.isCtrlPressed)  mods = mods or 0x02
        if (event.isAltPressed)   mods = mods or 0x04
        if (event.isMetaPressed)  mods = mods or 0x08
        return mods.toByte()
    }

    private fun androidKeyToVk(keyCode: Int): Int? = when (keyCode) {

        KeyEvent.KEYCODE_A -> 0x41;  KeyEvent.KEYCODE_B -> 0x42
        KeyEvent.KEYCODE_C -> 0x43;  KeyEvent.KEYCODE_D -> 0x44
        KeyEvent.KEYCODE_E -> 0x45;  KeyEvent.KEYCODE_F -> 0x46
        KeyEvent.KEYCODE_G -> 0x47;  KeyEvent.KEYCODE_H -> 0x48
        KeyEvent.KEYCODE_I -> 0x49;  KeyEvent.KEYCODE_J -> 0x4A
        KeyEvent.KEYCODE_K -> 0x4B;  KeyEvent.KEYCODE_L -> 0x4C
        KeyEvent.KEYCODE_M -> 0x4D;  KeyEvent.KEYCODE_N -> 0x4E
        KeyEvent.KEYCODE_O -> 0x4F;  KeyEvent.KEYCODE_P -> 0x50
        KeyEvent.KEYCODE_Q -> 0x51;  KeyEvent.KEYCODE_R -> 0x52
        KeyEvent.KEYCODE_S -> 0x53;  KeyEvent.KEYCODE_T -> 0x54
        KeyEvent.KEYCODE_U -> 0x55;  KeyEvent.KEYCODE_V -> 0x56
        KeyEvent.KEYCODE_W -> 0x57;  KeyEvent.KEYCODE_X -> 0x58
        KeyEvent.KEYCODE_Y -> 0x59;  KeyEvent.KEYCODE_Z -> 0x5A

        KeyEvent.KEYCODE_0 -> 0x30;  KeyEvent.KEYCODE_1 -> 0x31
        KeyEvent.KEYCODE_2 -> 0x32;  KeyEvent.KEYCODE_3 -> 0x33
        KeyEvent.KEYCODE_4 -> 0x34;  KeyEvent.KEYCODE_5 -> 0x35
        KeyEvent.KEYCODE_6 -> 0x36;  KeyEvent.KEYCODE_7 -> 0x37
        KeyEvent.KEYCODE_8 -> 0x38;  KeyEvent.KEYCODE_9 -> 0x39

        KeyEvent.KEYCODE_F1  -> 0x70; KeyEvent.KEYCODE_F2  -> 0x71
        KeyEvent.KEYCODE_F3  -> 0x72; KeyEvent.KEYCODE_F4  -> 0x73
        KeyEvent.KEYCODE_F5  -> 0x74; KeyEvent.KEYCODE_F6  -> 0x75
        KeyEvent.KEYCODE_F7  -> 0x76; KeyEvent.KEYCODE_F8  -> 0x77
        KeyEvent.KEYCODE_F9  -> 0x78; KeyEvent.KEYCODE_F10 -> 0x79
        KeyEvent.KEYCODE_F11 -> 0x7A; KeyEvent.KEYCODE_F12 -> 0x7B

        KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> 0x0D
        KeyEvent.KEYCODE_DEL          -> 0x08
        KeyEvent.KEYCODE_FORWARD_DEL  -> 0x2E
        KeyEvent.KEYCODE_TAB          -> 0x09
        KeyEvent.KEYCODE_SPACE        -> 0x20
        KeyEvent.KEYCODE_ESCAPE       -> 0x1B
        KeyEvent.KEYCODE_PAGE_UP      -> 0x21
        KeyEvent.KEYCODE_PAGE_DOWN    -> 0x22
        KeyEvent.KEYCODE_MOVE_END     -> 0x23
        KeyEvent.KEYCODE_MOVE_HOME    -> 0x24
        KeyEvent.KEYCODE_DPAD_LEFT    -> 0x25
        KeyEvent.KEYCODE_DPAD_UP      -> 0x26
        KeyEvent.KEYCODE_DPAD_RIGHT   -> 0x27
        KeyEvent.KEYCODE_DPAD_DOWN    -> 0x28
        KeyEvent.KEYCODE_INSERT       -> 0x2D

        KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SHIFT_RIGHT -> 0x10
        KeyEvent.KEYCODE_CTRL_LEFT,  KeyEvent.KEYCODE_CTRL_RIGHT  -> 0x11
        KeyEvent.KEYCODE_ALT_LEFT,   KeyEvent.KEYCODE_ALT_RIGHT   -> 0x12
        KeyEvent.KEYCODE_META_LEFT   -> 0x5B
        KeyEvent.KEYCODE_META_RIGHT  -> 0x5C
        KeyEvent.KEYCODE_CAPS_LOCK   -> 0x14
        KeyEvent.KEYCODE_NUM_LOCK    -> 0x90
        KeyEvent.KEYCODE_SCROLL_LOCK -> 0x91
        KeyEvent.KEYCODE_BREAK       -> 0x13
        KeyEvent.KEYCODE_SYSRQ        -> 0x2C

        KeyEvent.KEYCODE_MINUS         -> 0xBD
        KeyEvent.KEYCODE_EQUALS        -> 0xBB
        KeyEvent.KEYCODE_LEFT_BRACKET  -> 0xDB
        KeyEvent.KEYCODE_RIGHT_BRACKET -> 0xDD
        KeyEvent.KEYCODE_BACKSLASH     -> 0xDC
        KeyEvent.KEYCODE_SEMICOLON     -> 0xBA
        KeyEvent.KEYCODE_APOSTROPHE    -> 0xDE
        KeyEvent.KEYCODE_GRAVE         -> 0xC0
        KeyEvent.KEYCODE_COMMA         -> 0xBC
        KeyEvent.KEYCODE_PERIOD        -> 0xBE
        KeyEvent.KEYCODE_SLASH         -> 0xBF

        KeyEvent.KEYCODE_NUMPAD_0 -> 0x60; KeyEvent.KEYCODE_NUMPAD_1 -> 0x61
        KeyEvent.KEYCODE_NUMPAD_2 -> 0x62; KeyEvent.KEYCODE_NUMPAD_3 -> 0x63
        KeyEvent.KEYCODE_NUMPAD_4 -> 0x64; KeyEvent.KEYCODE_NUMPAD_5 -> 0x65
        KeyEvent.KEYCODE_NUMPAD_6 -> 0x66; KeyEvent.KEYCODE_NUMPAD_7 -> 0x67
        KeyEvent.KEYCODE_NUMPAD_8 -> 0x68; KeyEvent.KEYCODE_NUMPAD_9 -> 0x69
        KeyEvent.KEYCODE_NUMPAD_MULTIPLY -> 0x6A
        KeyEvent.KEYCODE_NUMPAD_ADD      -> 0x6B
        KeyEvent.KEYCODE_NUMPAD_SUBTRACT -> 0x6D
        KeyEvent.KEYCODE_NUMPAD_DOT      -> 0x6E
        KeyEvent.KEYCODE_NUMPAD_DIVIDE   -> 0x6F
        else -> null
    }

    private fun handleRemapping(event: KeyEvent, state: ControllerState): Int {
        val keyCode = event.keyCode

        if (state.ignoreBack && keyCode == KeyEvent.KEYCODE_BACK) {
            return REMAP_IGNORE
        }

        if (state.isNonStandardDualShock4) {

            return when (event.scanCode) {
                304 -> KeyEvent.KEYCODE_BUTTON_X
                305 -> KeyEvent.KEYCODE_BUTTON_A
                306 -> KeyEvent.KEYCODE_BUTTON_B
                307 -> KeyEvent.KEYCODE_BUTTON_Y
                308 -> KeyEvent.KEYCODE_BUTTON_L1
                309 -> KeyEvent.KEYCODE_BUTTON_R1

                312 -> KeyEvent.KEYCODE_BUTTON_SELECT
                313 -> KeyEvent.KEYCODE_BUTTON_START
                314 -> KeyEvent.KEYCODE_BUTTON_THUMBL
                315 -> KeyEvent.KEYCODE_BUTTON_THUMBR
                316 -> KeyEvent.KEYCODE_BUTTON_MODE
                else -> REMAP_CONSUME
            }
        }
        if (state.usesLinuxGamepadStandardFaceButtons) {

            return when (event.scanCode) {
                307 -> KeyEvent.KEYCODE_BUTTON_Y
                308 -> KeyEvent.KEYCODE_BUTTON_X
                else -> keyCode
            }
        }
        return keyCode
    }

    private fun keyToFlag(keyCode: Int): Int? {
        val baseFlag = when (keyCode) {
            KeyEvent.KEYCODE_BUTTON_A -> A_FLAG
            KeyEvent.KEYCODE_BUTTON_B -> B_FLAG
            KeyEvent.KEYCODE_BUTTON_X -> X_FLAG
            KeyEvent.KEYCODE_BUTTON_Y -> Y_FLAG
            KeyEvent.KEYCODE_DPAD_UP -> UP_FLAG
            KeyEvent.KEYCODE_DPAD_DOWN -> DOWN_FLAG
            KeyEvent.KEYCODE_DPAD_LEFT -> LEFT_FLAG
            KeyEvent.KEYCODE_DPAD_RIGHT -> RIGHT_FLAG
            KeyEvent.KEYCODE_BUTTON_L1 -> LB_FLAG
            KeyEvent.KEYCODE_BUTTON_R1 -> RB_FLAG
            KeyEvent.KEYCODE_BUTTON_START, KeyEvent.KEYCODE_MENU -> PLAY_FLAG
            KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BACK -> BACK_FLAG
            KeyEvent.KEYCODE_BUTTON_THUMBL -> LS_CLK_FLAG
            KeyEvent.KEYCODE_BUTTON_THUMBR -> RS_CLK_FLAG
            KeyEvent.KEYCODE_BUTTON_MODE -> SPECIAL_FLAG
            else -> null
        } ?: return null

        return buttonRemapTable?.get(baseFlag) ?: baseFlag
    }

    fun remapKeyEventForFlutter(event: KeyEvent): KeyEvent {
        val device = InputDevice.getDevice(event.deviceId) ?: return event
        if (!isGamepadDevice(device)) return event

        ensureController(event.deviceId, device)
        val state = controllers[event.deviceId] ?: return event

        val remappedKeyCode = handleRemapping(event, state)

        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            Log.i(TAG, "UI KEY: keyCode=${event.keyCode}(${KeyEvent.keyCodeToString(event.keyCode)}), " +
                "scanCode=${event.scanCode}, remapped=${KeyEvent.keyCodeToString(remappedKeyCode.coerceAtLeast(0))}, " +
                "device='${device.name}', vendor=0x${state.vendorId.toString(16)}, " +
                "ds4NonStd=${state.isNonStandardDualShock4}, linuxStd=${state.usesLinuxGamepadStandardFaceButtons}")
        }

        if (remappedKeyCode == REMAP_IGNORE) return event
        if (remappedKeyCode == REMAP_CONSUME) {

            if (state.isNonStandardDualShock4) {
                val launcherKeyCode = when (event.scanCode) {
                    310 -> KeyEvent.KEYCODE_BUTTON_L2
                    311 -> KeyEvent.KEYCODE_BUTTON_R2
                    else -> return event
                }
                return KeyEvent(
                    event.downTime, event.eventTime,
                    event.action, launcherKeyCode,
                    event.repeatCount, event.metaState,
                    event.deviceId, event.scanCode,
                    event.flags, event.source
                )
            }
            return event
        }
        if (remappedKeyCode == event.keyCode) return event

        return KeyEvent(
            event.downTime, event.eventTime,
            event.action, remappedKeyCode,
            event.repeatCount, event.metaState,
            event.deviceId, event.scanCode,
            event.flags, event.source
        )
    }

    fun dispose() {
        instance = null
        stopMotionSensors()
        val inputManager = context.getSystemService(Context.INPUT_SERVICE) as? InputManager
        inputManager?.unregisterInputDeviceListener(this)
        methodChannel.setMethodCallHandler(null)
    }
}
