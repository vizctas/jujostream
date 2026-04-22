package com.limelight.jujostream.native_bridge

import android.app.Activity
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Rational
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import io.flutter.view.TextureRegistry
import java.util.Timer
import java.util.TimerTask

class StreamingPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, StreamingListener, ActivityAware {

    private var activity: Activity? = null

    companion object {
        private const val TAG = "StreamingPlugin"
        private const val METHOD_CHANNEL = "com.limelight.jujostream/streaming"
        private const val EVENT_CHANNEL = "com.limelight.jujostream/streaming_stats"

        @Volatile var isStreamingActive = false

        @Volatile var isPipMode = false
        @Volatile var reconnectAfterPip = false

        var instance: StreamingPlugin? = null

        fun notifyReconnectNeeded() {
            instance?.sendEvent(mapOf("type" to "reconnectNeeded"))
        }

        // SoC identifiers for devices known to handle 1080p60 HEVC decode
        // without conservative settings. Matches against Build.HARDWARE,
        // Build.BOARD, and Build.MODEL (lowercased).
        private val CAPABLE_SOC_PATTERNS = listOf(
            "tegra",       // Nvidia Shield TV (Tegra X1/X1+)
            "darcy",       // Shield TV 2017 board name
            "foster",      // Shield TV 2015 board name
            "mdarcy",      // Shield TV Pro board name
            "sif",         // Shield TV 2019 board name
            "qualcomm",    // Qualcomm SoCs (phones, some TVs)
            "snapdragon",  // Qualcomm branding
            "exynos",      // Samsung high-end
            "tensor",      // Google Pixel
            "kirin",       // Huawei high-end
            "dimensity",   // MediaTek high-end (Dimensity 9000+)
            "mt6893",      // Dimensity 1200
            "mt6895",      // Dimensity 8100
            "mt6983",      // Dimensity 9000
        )
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var textureRegistry: TextureRegistry? = null

    private var videoRenderer: VideoDecoderRenderer? = null
    private var audioRenderer: AudioRenderer? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var directSubmitActive = false

    private var statsTimer: Timer? = null
    private var lastFramesRendered = 0L
    private var lastFramesDropped = 0L
    private var configuredBitrateKbps = 20000
    private var activeCodecName = "unknown"

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.i(TAG, "Plugin attached to engine")
        instance = this

        textureRegistry = binding.textureRegistry

        binding.platformViewRegistry.registerViewFactory(
            DirectSubmitViewFactory.VIEW_TYPE,
            DirectSubmitViewFactory()
        )

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }

        try {
            StreamingBridge.nativeInit()
            StreamingBridge.listener = this
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to initialize native bridge — streaming unavailable", e)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.i(TAG, "Plugin detached from engine")
        instance = null
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        cleanup()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startStream" -> handleStartStream(call, result)
            "stopStream" -> handleStopStream(result)
            "enterPiP" -> handleEnterPiP(result)
            "getTextureId" -> handleGetTextureId(result)
            "sendMouseMove" -> handleSendMouseMove(call, result)
            "sendMousePosition" -> handleSendMousePosition(call, result)
            "sendMouseButton" -> handleSendMouseButton(call, result)
            "sendKeyboardInput" -> handleSendKeyboardInput(call, result)
            "sendScroll" -> handleSendScroll(call, result)
            "sendHighResHScroll" -> handleSendHighResHScroll(call, result)
            "sendGamepadInput" -> handleSendGamepadInput(call, result)
            "sendControllerArrival" -> handleSendControllerArrival(call, result)
            "sendTouchEvent" -> handleSendTouchEvent(call, result)
            "sendUtf8Text" -> handleSendUtf8Text(call, result)
            "getStats" -> handleGetStats(result)
            "probeCodec" -> handleProbeCodec(call, result)
            "isDirectSubmitActive" -> result.success(directSubmitActive)
            else -> result.notImplemented()
        }
    }

    private fun handleStartStream(call: MethodCall, result: MethodChannel.Result) {
        val host = call.argument<String>("host") ?: ""
        val width = call.argument<Int>("width") ?: 1920
        val height = call.argument<Int>("height") ?: 1080
        val fps = call.argument<Int>("fps") ?: 60
        val bitrate = call.argument<Int>("bitrate") ?: 20000
        configuredBitrateKbps = bitrate
        val videoCodec = call.argument<String>("videoCodec") ?: "H264"
        val enableHdr = call.argument<Boolean>("enableHdr") ?: false
        val resolvedCodec = if (videoCodec == "auto") {
            val picked = CodecProbe.selectBest(width, height, fps, enableHdr)
            Log.i(TAG, "Auto-codec resolved: $picked (for ${width}x${height}@${fps}fps hdr=$enableHdr)")
            picked ?: "H264"
        } else videoCodec
        // activeCodecName set later after weak-device override (see effectiveCodec)
        val fullRange = call.argument<Boolean>("fullRange") ?: false
        val audioConfig = call.argument<String>("audioConfig") ?: "stereo"
        val audioQuality = call.argument<String>("audioQuality") ?: "high"
        val enableAudioFx = call.argument<Boolean>("enableAudioFx") ?: false
        val riKeyHex = call.argument<String>("riKey") ?: ""
        val riKeyId = call.argument<Int>("riKeyId") ?: 0
        val rtspSessionUrl = call.argument<String>("rtspSessionUrl")
        val appVersion = call.argument<String>("appVersion") ?: "7.1.431.-1"
        val gfeVersion = call.argument<String>("gfeVersion") ?: ""
        val serverCodecModeSupport = call.argument<Int>("serverCodecModeSupport") ?: 0x0F
        val framePacingStr = call.argument<String>("framePacing") ?: "balanced"
        val frameQueueDepth = call.argument<Int>("frameQueueDepth") ?: 0
        val choreographerVsync = call.argument<Boolean>("choreographerVsync") ?: false
        val enableVrr = call.argument<Boolean>("enableVrr") ?: false
        val directSubmit = call.argument<Boolean>("directSubmit") ?: false
        val lowLatencyFrameBalance = call.argument<Boolean>("lowLatencyFrameBalance") ?: false

        val framePacingMode = when (framePacingStr) {
            "latency"    -> VideoDecoderRenderer.FRAME_PACING_LATENCY
            "balanced"   -> VideoDecoderRenderer.FRAME_PACING_BALANCED
            "capFps"     -> VideoDecoderRenderer.FRAME_PACING_CAP_FPS
            "smoothness" -> VideoDecoderRenderer.FRAME_PACING_SMOOTHNESS
            "adaptive"   -> VideoDecoderRenderer.FRAME_PACING_ADAPTIVE
            else         -> VideoDecoderRenderer.FRAME_PACING_BALANCED
        }

        val colorSpace = if (enableHdr) 1 else 0
        val colorRange = if (fullRange) 1 else 0

        val audioConfiguration = StreamConstants.audioConfigFor(audioConfig)

        val allSupported = CodecProbe.rankCodecs(width, height, fps, enableHdr)

        val weakDevice = detectWeakDevice()
        val effectiveCodec = when {
            weakDevice && videoCodec == "auto" -> {
                Log.w(TAG, "Weak TV device detected — forcing H264 (was $resolvedCodec)")
                "H264"
            }
            else -> resolvedCodec
        }
        activeCodecName = effectiveCodec

        val decodersByMime = mutableMapOf<String, String>()
        for (cs in allSupported) {
            val mime = when (cs.codec) {
                "H264" -> "video/avc"
                "H265" -> "video/hevc"
                "AV1"  -> "video/av01"
                else -> continue
            }
            if (mime !in decodersByMime) {
                decodersByMime[mime] = cs.decoderName
            }
        }
        Log.i(TAG, "Decoder map: $decodersByMime (weakDevice=$weakDevice, preferred=$effectiveCodec)")

        if (weakDevice && effectiveCodec == "H264") {
            val avcDecoder = decodersByMime["video/avc"]
            decodersByMime.keys.retainAll(setOf("video/avc"))
            Log.i(TAG, "Weak device: stripped codec map to avc-only → $decodersByMime")
        }

        val primaryFormat = StreamConstants.videoFormatFor(effectiveCodec, enableHdr)
        var supportedVideoFormats = primaryFormat
        for (codec in allSupported) {
            supportedVideoFormats = supportedVideoFormats or
                StreamConstants.videoFormatFor(codec.codec, enableHdr)
        }

        val effectiveFramePacingMode = if (weakDevice && framePacingMode != VideoDecoderRenderer.FRAME_PACING_LATENCY) {
            Log.w(TAG, "Weak device — overriding frame pacing to LATENCY (was $framePacingMode)")
            VideoDecoderRenderer.FRAME_PACING_LATENCY
        } else framePacingMode

        val videoCapabilities = 0

        Log.i(TAG, "═══ NATIVE STREAM CONFIG DIAGNOSTIC ═══")
        Log.i(TAG, "Host: $host")
        Log.i(TAG, "Resolution: ${width}x${height} @ ${fps}fps")
        Log.i(TAG, "Bitrate: $bitrate Kbps")
        Log.i(TAG, "Video Codec (arg): $videoCodec → resolved: $effectiveCodec")
        Log.i(TAG, "Video Format (resolved): 0x${supportedVideoFormats.toString(16)}")
        Log.i(TAG, "HDR Enabled: $enableHdr, colorSpace=$colorSpace, colorRange=$colorRange")
        Log.i(TAG, "Frame Pacing: $framePacingStr → mode=$effectiveFramePacingMode (weakDevice=$weakDevice)")
        Log.i(TAG, "Audio Config (arg): $audioConfig")
        Log.i(TAG, "Audio Quality: $audioQuality (streamingRemotely=AUTO, audioFx=$enableAudioFx)")
        Log.i(TAG, "Audio Configuration (resolved): 0x${audioConfiguration.toString(16)}")
        Log.i(TAG, "Video Capabilities: $videoCapabilities")
        Log.i(TAG, "App Version: $appVersion")
        Log.i(TAG, "VRR: $enableVrr, DirectSubmit: $directSubmit, LowLatencyFrameBalance: $lowLatencyFrameBalance")
        Log.i(TAG, "═══════════════════════════════════════")


        val directSurface = if (directSubmit && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val ds = DirectSubmitViewFactory.awaitSurface(3000)
            if (ds != null) {
                Log.i(TAG, "Direct submit surface acquired — zero-copy path active")
            } else {
                Log.w(TAG, "Direct submit surface not ready, falling back to SurfaceTexture")
            }
            ds
        } else null
        directSubmitActive = directSurface != null

        if (directSurface == null) {
            textureEntry = textureRegistry?.createSurfaceTexture()
            if (textureEntry == null) {
                result.error("TEXTURE_ERROR", "Failed to create texture", null)
                return
            }
        }

        val effectiveQueueDepth = if (weakDevice) minOf(frameQueueDepth.coerceIn(0, 6), 1) else frameQueueDepth.coerceIn(0, 6)
        videoRenderer = VideoDecoderRenderer(
            if (directSurface != null) null else textureEntry!!,
            effectiveFramePacingMode,
            enableHdr,
            fullRange = fullRange,
            maxQueueDepth = effectiveQueueDepth,
            useChoreographerVsync = choreographerVsync,
            enableVrr = enableVrr,
            externalSurface = directSurface,
            lowLatencyFrameBalance = lowLatencyFrameBalance,
            decodersByMime = decodersByMime,
            isWeakDevice = weakDevice
        )

        if (enableVrr) {
            activity?.let { act ->
                DisplayModeHelper.apply(act, fps, null)
            }
        }

        audioRenderer = AudioRenderer(enableAudioFx = enableAudioFx, isWeakDevice = weakDevice)

        val riAesKey: ByteArray = if (riKeyHex.length >= 32) {
            ByteArray(16) { i ->
                riKeyHex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
        } else {
            ByteArray(16)
        }

        val riAesIv = ByteArray(16)
        riAesIv[0] = (riKeyId shr 24).toByte()
        riAesIv[1] = (riKeyId shr 16).toByte()
        riAesIv[2] = (riKeyId shr 8).toByte()
        riAesIv[3] = riKeyId.toByte()

        val replied = AtomicBoolean(false)

        isStreamingActive = true
        Thread {
            try {
                val packetDuration = if (weakDevice) 20 else 5

                val status = StreamingBridge.nativeStartConnection(
                    address = host,
                    appVersion = appVersion,
                    gfeVersion = if (gfeVersion.isEmpty()) null else gfeVersion,
                    rtspSessionUrl = rtspSessionUrl,
                    serverCodecModeSupport = serverCodecModeSupport,
                    width = width,
                    height = height,
                    fps = fps,
                    bitrate = bitrate,
                    packetSize = 1392,
                    streamingRemotely = 2,
                    audioConfiguration = audioConfiguration,
                    supportedVideoFormats = supportedVideoFormats,
                    clientRefreshRateX100 = fps * 100,
                    riAesKey = riAesKey,
                    riAesIv = riAesIv,
                    videoCapabilities = videoCapabilities,
                    colorSpace = colorSpace,
                    colorRange = colorRange,
                    slowOpusDecoder = (audioQuality != "high"),
                    audioPacketDuration = packetDuration
                )
                mainHandler.post {
                    if (!replied.compareAndSet(false, true)) {
                        Log.w(TAG, "startStream result already replied — Dart timeout likely fired")
                        if (status != 0) cleanup()
                        return@post
                    }
                    if (status == 0) {
                        result.success(true)
                    } else {
                        Log.e(TAG, "nativeStartConnection failed: $status")
                        cleanup()
                        result.error("STREAM_FAILED", "Connection failed with code $status", status)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Exception in nativeStartConnection", e)
                mainHandler.post {
                    if (!replied.compareAndSet(false, true)) {
                        Log.w(TAG, "startStream result already replied on exception path")
                        cleanup()
                        return@post
                    }
                    cleanup()
                    result.error("STREAM_EXCEPTION", e.message, null)
                }
            }
        }.also { it.name = "StreamingThread"; it.isDaemon = true }.start()
    }

    private fun detectWeakDevice(): Boolean {
        val ctx: Context = activity ?: return false
        val pm = ctx.packageManager
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager

        val isArm32Only = Build.SUPPORTED_ABIS.isNotEmpty() &&
                          !Build.SUPPORTED_ABIS.contains("arm64-v8a")
        val isLowRam = am?.isLowRamDevice ?: false

        if (isArm32Only || isLowRam) {
            Log.i(TAG, "detectWeakDevice: arm32=$isArm32Only lowRam=$isLowRam → true (tier-1)")
            return true
        }

        val isTv = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                   pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION)

        val soc = Build.HARDWARE.lowercase()
        val board = Build.BOARD.lowercase()
        val model = Build.MODEL.lowercase()
        val isCapableSoc = CAPABLE_SOC_PATTERNS.any { pattern ->
            soc.contains(pattern) || board.contains(pattern) || model.contains(pattern)
        }
        if (isCapableSoc) {
            Log.i(TAG, "detectWeakDevice: capable SoC (hw=$soc board=$board) → false (tier-2)")
            return false
        }

        if (isTv) {
            val memInfo = ActivityManager.MemoryInfo()
            am?.getMemoryInfo(memInfo)
            val totalRamMb = memInfo.totalMem / (1024 * 1024)
            val isLimitedRam = totalRamMb < 2800
            Log.i(TAG, "detectWeakDevice: tv=true ram=${totalRamMb}MB hw=$soc → $isLimitedRam (tier-3)")
            return isLimitedRam
        }

        Log.i(TAG, "detectWeakDevice: non-TV arm64 → false (tier-4)")
        return false
    }

    private fun handleStopStream(result: MethodChannel.Result) {
        Log.i(TAG, "Stopping stream")

        try {
            StreamingBridge.nativeStopConnection()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping native connection", e)
        }

        cleanup()
        result.success(null)
    }

    private fun handleEnterPiP(result: MethodChannel.Result) {
        val act = activity
        if (act == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(false)
            return
        }
        if (!isStreamingActive) {
            result.success(false)
            return
        }
        try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            act.enterPictureInPictureMode(params)
            result.success(true)
        } catch (e: Exception) {
            Log.w(TAG, "PiP not supported on this device", e)
            result.success(false)
        }
    }

    private fun handleGetTextureId(result: MethodChannel.Result) {
        val id = textureEntry?.id()
        if (id != null) {
            result.success(id)
        } else {
            result.error("NO_TEXTURE", "No texture available", null)
        }
    }

    private fun handleSendMouseMove(call: MethodCall, result: MethodChannel.Result) {
        val deltaX = (call.argument<Int>("deltaX") ?: 0).toShort()
        val deltaY = (call.argument<Int>("deltaY") ?: 0).toShort()
        StreamingBridge.nativeSendMouseMove(deltaX, deltaY)
        result.success(null)
    }

    private fun handleSendMousePosition(call: MethodCall, result: MethodChannel.Result) {
        val x = (call.argument<Int>("x") ?: 0).toShort()
        val y = (call.argument<Int>("y") ?: 0).toShort()
        val refWidth = (call.argument<Int>("refWidth") ?: 1920).toShort()
        val refHeight = (call.argument<Int>("refHeight") ?: 1080).toShort()
        StreamingBridge.nativeSendMousePosition(x, y, refWidth, refHeight)
        result.success(null)
    }

    private fun handleSendMouseButton(call: MethodCall, result: MethodChannel.Result) {
        val button = (call.argument<Int>("button") ?: 1).toByte()
        val pressed = call.argument<Boolean>("pressed") ?: false
        val action: Byte = if (pressed) 0x07 else 0x08
        StreamingBridge.nativeSendMouseButton(action, button)
        result.success(null)
    }

    private fun handleSendKeyboardInput(call: MethodCall, result: MethodChannel.Result) {
        val keyCode = (call.argument<Int>("keyCode") ?: 0).toShort()
        val pressed = call.argument<Boolean>("pressed") ?: false
        val action: Byte = if (pressed) 0x03 else 0x04
        StreamingBridge.nativeSendKeyboard(keyCode, action, 0, 0)
        result.success(null)
    }

    private fun handleSendUtf8Text(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text") ?: ""
        if (text.isNotEmpty()) {
            StreamingBridge.nativeSendUtf8Text(text)
        }
        result.success(null)
    }

    private fun handleSendScroll(call: MethodCall, result: MethodChannel.Result) {
        val amount = (call.argument<Int>("scrollAmount") ?: 0).toShort()
        StreamingBridge.nativeSendScroll(amount)
        result.success(null)
    }

    private fun handleSendHighResHScroll(call: MethodCall, result: MethodChannel.Result) {
        val amount = (call.argument<Int>("scrollAmount") ?: 0).toShort()
        StreamingBridge.nativeSendHighResHScroll(amount)
        result.success(null)
    }

    private fun handleSendGamepadInput(call: MethodCall, result: MethodChannel.Result) {
        val controllerNumber = (call.argument<Int>("controllerNumber") ?: 0).toShort()
        val activeGamepadMask = (call.argument<Int>("activeGamepadMask") ?: 1).toShort()
        val buttonFlags = call.argument<Int>("buttonFlags") ?: 0
        val leftTrigger = (call.argument<Int>("leftTrigger") ?: 0).toByte()
        val rightTrigger = (call.argument<Int>("rightTrigger") ?: 0).toByte()
        val leftStickX = (call.argument<Int>("leftStickX") ?: 0).toShort()
        val leftStickY = (call.argument<Int>("leftStickY") ?: 0).toShort()
        val rightStickX = (call.argument<Int>("rightStickX") ?: 0).toShort()
        val rightStickY = (call.argument<Int>("rightStickY") ?: 0).toShort()

        StreamingBridge.nativeSendControllerInput(
            controllerNumber, activeGamepadMask, buttonFlags, leftTrigger, rightTrigger,
            leftStickX, leftStickY, rightStickX, rightStickY
        )
        result.success(null)
    }

    private fun handleSendControllerArrival(call: MethodCall, result: MethodChannel.Result) {
        val controllerNumber = (call.argument<Int>("controllerNumber") ?: 0).toShort()
        val activeGamepadMask = (call.argument<Int>("activeGamepadMask") ?: 1).toShort()
        val controllerType = (call.argument<Int>("controllerType") ?: 1).toByte()
        val capabilities = (call.argument<Int>("capabilities") ?: 0).toShort()
        val supportedButtonFlags = call.argument<Int>("supportedButtonFlags") ?: 0

        val rc = StreamingBridge.nativeSendControllerArrival(
            controllerNumber,
            activeGamepadMask,
            controllerType,
            capabilities,
            supportedButtonFlags
        )
        Log.i(TAG, "ARRIVAL: slot=$controllerNumber mask=0x${activeGamepadMask.toInt().toString(16)} " +
            "type=$controllerType caps=0x${capabilities.toInt().toString(16)} " +
            "btnFlags=0x${supportedButtonFlags.toString(16)} rc=$rc")
        result.success(rc == 0)
    }

    private fun handleSendTouchEvent(call: MethodCall, result: MethodChannel.Result) {
        val eventType = (call.argument<Int>("eventType") ?: 0).toByte()
        val pointerId = call.argument<Int>("pointerId") ?: 0
        val x = (call.argument<Double>("x") ?: 0.0).toFloat()
        val y = (call.argument<Double>("y") ?: 0.0).toFloat()
        val pressure = (call.argument<Double>("pressure") ?: 0.0).toFloat()
        val contactMajor = (call.argument<Double>("contactMajor") ?: 0.0).toFloat()
        val contactMinor = (call.argument<Double>("contactMinor") ?: 0.0).toFloat()
        val orientation = (call.argument<Int>("orientation") ?: 0).toShort()

        StreamingBridge.nativeSendTouchEvent(
            eventType, pointerId,
            x, y, pressure,
            contactMajor, contactMinor, orientation
        )
        result.success(null)
    }

    private fun handleGetStats(result: MethodChannel.Result) {
        val stats = videoRenderer?.getStats() ?: mapOf(
            "framesReceived"  to 0L,
            "framesRendered"  to 0L,
            "framesDropped"   to 0L,
            "decodeLatencyMs" to 0.0,
            "framePacingMode" to 0
        )
        result.success(stats)
    }

    private fun handleProbeCodec(call: MethodCall, result: MethodChannel.Result) {
        val w = call.argument<Int>("width") ?: 1920
        val h = call.argument<Int>("height") ?: 1080
        val fps = call.argument<Int>("fps") ?: 60
        val hdr = call.argument<Boolean>("hdr") ?: false
        result.success(CodecProbe.probeAsMap(w, h, fps, hdr))
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun sendEvent(event: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }

    override fun onVideoSetup(videoFormat: Int, width: Int, height: Int, redrawRate: Int): Int {
        return videoRenderer?.setup(videoFormat, width, height, redrawRate) ?: -1
    }

    override fun onVideoFrame(
        data: java.nio.ByteBuffer, length: Int, bufferType: Int,
        frameNumber: Int, frameType: Int,
        receiveTimeMs: Long, enqueueTimeMs: Long
    ): Int {
        return videoRenderer?.submitDecodeUnit(
            data, length, bufferType, frameNumber, frameType,
            receiveTimeMs, enqueueTimeMs
        ) ?: 0
    }

    override fun onAudioInit(audioConfig: Int, sampleRate: Int, samplesPerFrame: Int): Int {
        return audioRenderer?.init(audioConfig, sampleRate, samplesPerFrame) ?: -1
    }

    override fun onAudioSample(data: ByteArray, length: Int) {
        audioRenderer?.playSample(data, length)
    }

    override fun onAudioSampleShort(data: ShortArray, sampleCount: Int) {
        audioRenderer?.playSample(data)
    }

    override fun onConnectionStarted() {
        videoRenderer?.resetStats()
        videoRenderer?.start()
        audioRenderer?.start()
        sendEvent(mapOf("type" to "connectionStarted"))

        lastFramesRendered = 0L
        lastFramesDropped = 0L
        statsTimer?.cancel()
        statsTimer = Timer("StreamStats", true).also { timer ->
            timer.scheduleAtFixedRate(object : TimerTask() {
                override fun run() {
                    val renderer = videoRenderer ?: return
                    val currentFrames = renderer.totalFramesRendered
                    val currentDropped = renderer.totalFramesDropped
                    val renderedDelta = (currentFrames - lastFramesRendered).coerceAtLeast(0)
                    val droppedDelta = (currentDropped - lastFramesDropped).coerceAtLeast(0)
                    val fps = (renderedDelta * 5).toInt()
                    val totalDelta = renderedDelta + droppedDelta
                    val dropRate = if (totalDelta > 0)
                        ((droppedDelta.toFloat() / totalDelta.toFloat()) * 100).toInt().coerceIn(0, 100)
                    else 0
                    lastFramesRendered = currentFrames
                    lastFramesDropped = currentDropped
                    val decodeTime = renderer.avgDecodeLatencyMs.toInt()
                    val bitrateM = (configuredBitrateKbps / 1000.0).toInt().coerceAtLeast(1)
                    val resolution = "${renderer.initialWidth}x${renderer.initialHeight}"
                    val pendingAudioMs = StreamingBridge.nativeGetPendingAudioDuration().coerceAtLeast(0)
                    val rttInfo = StreamingBridge.getEstimatedRtt()
                    val rttMs = rttInfo?.first ?: -1
                    val rttVarianceMs = rttInfo?.second ?: -1

                    val statsMap = renderer.getStats()
                    val queueDepth = statsMap["queueDepth"] as? Int ?: 0
                    val decoderName = statsMap["decoderName"] as? String ?: "unknown"
                    val renderPath = statsMap["renderPath"] as? String
                        ?: if (directSubmitActive) "direct-submit" else "texture"

                    sendEvent(mapOf(
                        "fps"        to fps,
                        "decodeTime" to decodeTime,
                        "bitrate"    to bitrateM,
                        "dropRate"   to dropRate,
                        "resolution" to resolution,
                        "codec"      to activeCodecName,
                        "queueDepth" to queueDepth,
                        "pendingAudioMs" to pendingAudioMs,
                        "decoderName" to decoderName,
                        "renderPath" to renderPath,
                        "rttMs" to rttMs,
                        "rttVarianceMs" to rttVarianceMs,
                        "totalRendered" to currentFrames,
                        "totalDropped"  to currentDropped,
                    ))
                }
            }, 200L, 200L)
        }
    }

    override fun onConnectionTerminated(errorCode: Int) {
        if (isPipMode) {
            Log.i(TAG, "onConnectionTerminated during PiP — deferring to PiP exit (errorCode=$errorCode)")
            cleanup()
            reconnectAfterPip = true
            return
        }

        stopNativeConnection()
        sendEvent(mapOf("type" to "connectionTerminated", "errorCode" to errorCode))
        cleanup()
    }

    override fun onStageStarting(stage: Int) {
        val stageName = try { StreamingBridge.nativeGetStageName(stage) } catch (e: Exception) { "Stage $stage" }
        sendEvent(mapOf("type" to "stageStarting", "stage" to stage, "stageName" to stageName))
    }

    override fun onStageComplete(stage: Int) {
        sendEvent(mapOf("type" to "stageComplete", "stage" to stage))
    }

    override fun onStageFailed(stage: Int, errorCode: Int) {
        sendEvent(mapOf("type" to "stageFailed", "stage" to stage, "errorCode" to errorCode))
    }

    override fun onConnectionStatusUpdate(connectionStatus: Int) {
        sendEvent(mapOf("type" to "statusUpdate", "status" to connectionStatus))
    }

    override fun onRumble(controllerNumber: Short, lowFreqMotor: Short, highFreqMotor: Short) {

        GamepadHandler.instance?.handleRumble(
            controllerNumber.toInt(),
            lowFreqMotor.toInt() and 0xFFFF,
            highFreqMotor.toInt() and 0xFFFF
        )

        sendEvent(mapOf(
            "type" to "rumble",
            "controller" to controllerNumber.toInt(),
            "lowFreq" to lowFreqMotor.toInt(),
            "highFreq" to highFreqMotor.toInt()
        ))
    }

    override fun onRumbleTriggers(controllerNumber: Short, leftTrigger: Short, rightTrigger: Short) {
        GamepadHandler.instance?.handleRumbleTriggers(
            controllerNumber.toInt(),
            leftTrigger.toInt() and 0xFFFF,
            rightTrigger.toInt() and 0xFFFF
        )
    }

    override fun onSetMotionEventState(controllerNumber: Short, motionType: Byte, reportRateHz: Short) {
        GamepadHandler.instance?.handleSetMotionEventState(
            controllerNumber.toInt(),
            motionType.toInt() and 0xFF,
            reportRateHz.toInt() and 0xFFFF
        )
    }

    override fun onSetControllerLED(controllerNumber: Short, r: Byte, g: Byte, b: Byte) {
        GamepadHandler.instance?.handleSetControllerLED(
            controllerNumber.toInt(),
            r.toInt() and 0xFF,
            g.toInt() and 0xFF,
            b.toInt() and 0xFF
        )
    }

    private fun cleanup() {
        isStreamingActive = false
        directSubmitActive = false
        DisplayModeHelper.restore(activity)
        DirectSubmitViewFactory.reset()
        statsTimer?.cancel()
        statsTimer = null
        videoRenderer?.stop()
        videoRenderer?.cleanup()
        videoRenderer = null

        audioRenderer?.stop()
        audioRenderer?.cleanup()
        audioRenderer = null

        textureEntry?.release()
        textureEntry = null
    }

    private fun stopNativeConnection() {
        try {
            StreamingBridge.nativeStopConnection()
        } catch (e: Exception) {
            Log.w(TAG, "stopNativeConnection: ignored — $e")
        }
    }
}
