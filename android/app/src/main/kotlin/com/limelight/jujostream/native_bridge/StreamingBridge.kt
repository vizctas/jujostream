package com.limelight.jujostream.native_bridge

import android.util.Log

object StreamingBridge {
    private const val TAG = "StreamingBridge"

    var listener: StreamingListener? = null

    init {
        try {
            System.loadLibrary("jujostream_native")
            Log.i(TAG, "Native library loaded")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Failed to load native library: ${e.message}")
        }
    }

    @JvmStatic external fun nativeInit()

    @JvmStatic external fun nativeStartConnection(
        address: String, appVersion: String, gfeVersion: String?,
        rtspSessionUrl: String?, serverCodecModeSupport: Int,
        width: Int, height: Int, fps: Int,
        bitrate: Int, packetSize: Int, streamingRemotely: Int,
        audioConfiguration: Int, supportedVideoFormats: Int,
        clientRefreshRateX100: Int,
        riAesKey: ByteArray, riAesIv: ByteArray,
        videoCapabilities: Int,
        colorSpace: Int, colorRange: Int,
        slowOpusDecoder: Boolean,
        audioPacketDuration: Int
    ): Int

    @JvmStatic external fun nativeSendMouseMove(deltaX: Short, deltaY: Short)
    @JvmStatic external fun nativeSendMousePosition(x: Short, y: Short, refWidth: Short, refHeight: Short)
    @JvmStatic external fun nativeSendMouseButton(action: Byte, button: Byte)
    @JvmStatic external fun nativeSendKeyboard(keyCode: Short, keyAction: Byte, modifiers: Byte, flags: Byte)
    @JvmStatic external fun nativeSendScroll(scrollAmount: Short)
    @JvmStatic external fun nativeSendHighResHScroll(scrollAmount: Short)
    @JvmStatic external fun nativeSendControllerInput(
        controllerNumber: Short, activeGamepadMask: Short,
        buttonFlags: Int, leftTrigger: Byte, rightTrigger: Byte,
        leftStickX: Short, leftStickY: Short,
        rightStickX: Short, rightStickY: Short
    ): Int
    @JvmStatic external fun nativeSendControllerArrival(
        controllerNumber: Short,
        activeGamepadMask: Short,
        controllerType: Byte,
        capabilities: Short,
        supportedButtonFlags: Int
    ): Int
    @JvmStatic external fun nativeSendTouchEvent(
        eventType: Byte, pointerId: Int,
        x: Float, y: Float, pressureOrDistance: Float,
        contactAreaMajor: Float, contactAreaMinor: Float,
        rotation: Short
    ): Int
    @JvmStatic external fun nativeSendUtf8Text(text: String)
    @JvmStatic external fun nativeSendControllerMotionEvent(
        controllerNumber: Short, motionType: Byte,
        x: Float, y: Float, z: Float
    )
    @JvmStatic external fun nativeStopConnection()
    @JvmStatic external fun nativeInterruptConnection()
    @JvmStatic external fun nativeGetPendingVideoFrames(): Int
    @JvmStatic external fun nativeGetPendingAudioDuration(): Int
    @JvmStatic external fun nativeGetStageName(stage: Int): String
    @JvmStatic external fun nativeGetEstimatedRttInfo(): Long

    @JvmStatic fun onVideoSetup(videoFormat: Int, width: Int, height: Int, redrawRate: Int): Int {
        Log.i(TAG, "Video setup: ${width}x${height}@${redrawRate}, format=0x${videoFormat.toString(16)}")
        return listener?.onVideoSetup(videoFormat, width, height, redrawRate) ?: -1
    }

    @JvmStatic fun onVideoFrame(
        data: java.nio.ByteBuffer, length: Int, bufferType: Int,
        frameNumber: Int, frameType: Int,
        receiveTimeMs: Long, enqueueTimeMs: Long
    ): Int {
        return listener?.onVideoFrame(data, length, bufferType, frameNumber, frameType,
            receiveTimeMs, enqueueTimeMs) ?: 0
    }

    @JvmStatic fun onAudioInit(audioConfig: Int, sampleRate: Int, samplesPerFrame: Int): Int {
        Log.i(TAG, "Audio init: config=$audioConfig, rate=$sampleRate, spf=$samplesPerFrame")
        return listener?.onAudioInit(audioConfig, sampleRate, samplesPerFrame) ?: -1
    }

    @JvmStatic fun onAudioSample(data: ByteArray, length: Int) {
        listener?.onAudioSample(data, length)
    }

    @JvmStatic fun onAudioSampleShort(data: ShortArray, sampleCount: Int) {
        listener?.onAudioSampleShort(data, sampleCount)
    }

    @JvmStatic fun onConnectionStarted() {
        Log.i(TAG, "Connection started")
        listener?.onConnectionStarted()
    }

    @JvmStatic fun onConnectionTerminated(errorCode: Int) {
        Log.e(TAG, "Connection terminated: $errorCode")
        listener?.onConnectionTerminated(errorCode)
    }

    @JvmStatic fun onStageStarting(stage: Int) { listener?.onStageStarting(stage) }
    @JvmStatic fun onStageComplete(stage: Int) { listener?.onStageComplete(stage) }
    @JvmStatic fun onStageFailed(stage: Int, errorCode: Int) {
        Log.e(TAG, "Stage $stage failed: $errorCode")
        listener?.onStageFailed(stage, errorCode)
    }
    @JvmStatic fun onConnectionStatusUpdate(connectionStatus: Int) { listener?.onConnectionStatusUpdate(connectionStatus) }
    @JvmStatic fun onRumble(controllerNumber: Short, lowFreqMotor: Short, highFreqMotor: Short) {
        listener?.onRumble(controllerNumber, lowFreqMotor, highFreqMotor)
    }
    @JvmStatic fun onRumbleTriggers(controllerNumber: Short, leftTrigger: Short, rightTrigger: Short) {
        listener?.onRumbleTriggers(controllerNumber, leftTrigger, rightTrigger)
    }
    @JvmStatic fun onSetMotionEventState(controllerNumber: Short, motionType: Byte, reportRateHz: Short) {
        listener?.onSetMotionEventState(controllerNumber, motionType, reportRateHz)
    }
    @JvmStatic fun onSetControllerLED(controllerNumber: Short, r: Byte, g: Byte, b: Byte) {
        listener?.onSetControllerLED(controllerNumber, r, g, b)
    }

    fun getEstimatedRtt(): Pair<Int, Int>? {
        val info = nativeGetEstimatedRttInfo()
        if (info == -1L) return null
        val rtt = (info shr 32).toInt()
        val variance = info.toInt()
        return Pair(rtt, variance)
    }
}

interface StreamingListener {
    fun onVideoSetup(videoFormat: Int, width: Int, height: Int, redrawRate: Int): Int
    fun onVideoFrame(data: java.nio.ByteBuffer, length: Int, bufferType: Int,
                     frameNumber: Int, frameType: Int,
                     receiveTimeMs: Long, enqueueTimeMs: Long): Int
    fun onAudioInit(audioConfig: Int, sampleRate: Int, samplesPerFrame: Int): Int
    fun onAudioSample(data: ByteArray, length: Int)
    fun onAudioSampleShort(data: ShortArray, sampleCount: Int)
    fun onConnectionStarted()
    fun onConnectionTerminated(errorCode: Int)
    fun onStageStarting(stage: Int)
    fun onStageComplete(stage: Int)
    fun onStageFailed(stage: Int, errorCode: Int)
    fun onConnectionStatusUpdate(connectionStatus: Int)
    fun onRumble(controllerNumber: Short, lowFreqMotor: Short, highFreqMotor: Short)
    fun onRumbleTriggers(controllerNumber: Short, leftTrigger: Short, rightTrigger: Short)
    fun onSetMotionEventState(controllerNumber: Short, motionType: Byte, reportRateHz: Short)
    fun onSetControllerLED(controllerNumber: Short, r: Byte, g: Byte, b: Byte)
}
