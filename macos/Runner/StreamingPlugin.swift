// Flutter plugin for macOS streaming.
// Exposes MethodChannel + EventChannel matching the Android contract.

import Foundation
import FlutterMacOS
import VideoToolbox

final class StreamingPlugin: NSObject,
                              FlutterPlugin,
                              FlutterStreamHandler,
                              StreamingBridgeDelegate {

    // MARK: - Constants
    private static let kMethodChannel  = "com.limelight.jujostream/streaming"
    private static let kEventChannel   = "com.limelight.jujostream/streaming_stats"

    // MARK: - Private state
    private var eventSink: FlutterEventSink?
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel:  FlutterEventChannel?
    private var statsTimer:    Timer?

    // Streaming diagnostics
    private var configuredBitrateKbps = 20000
    private var activeCodecName       = "h264"
    private var isStreamingActive     = false

    private var lastFramesDecoded: Int = 0
    private var lastFramesDropped: Int = 0

    // MARK: - Registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = StreamingPlugin()

        instance.methodChannel = FlutterMethodChannel(
            name: kMethodChannel,
            binaryMessenger: registrar.messenger)
        instance.methodChannel?.setMethodCallHandler(instance.handle)

        instance.eventChannel = FlutterEventChannel(
            name: kEventChannel,
            binaryMessenger: registrar.messenger)
        instance.eventChannel?.setStreamHandler(instance)

        let bridge = StreamingBridge.shared
        bridge.textureRegistry = registrar.textures
        bridge.delegate       = instance
        bridge.registerCBridgeCallbacks()
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - MethodCallHandler

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startStream":         handleStartStream(call, result: result)
        case "stopStream":          handleStopStream(result: result)
        case "getTextureId":        result(StreamingBridge.shared.videoTextureId)
        case "sendMouseMove":       handleSendMouseMove(call, result: result)
        case "sendMousePosition":   handleSendMousePosition(call, result: result)
        case "sendMouseButton":     handleSendMouseButton(call, result: result)
        case "sendKeyboardInput":   handleSendKeyboard(call, result: result)
        case "sendScroll":          handleSendScroll(call, result: result)
        case "sendHighResHScroll":  handleSendHighResHScroll(call, result: result)
        case "sendGamepadInput":    handleSendGamepadInput(call, result: result)
        case "sendControllerArrival": handleSendControllerArrival(call, result: result)
        case "sendUtf8Text":        handleSendUtf8Text(call, result: result)
        case "getStats":            handleGetStats(result: result)
        case "probeCodec":          handleProbeCodec(call, result: result)
        case "isDirectSubmitActive": result(false)  // macOS always uses texture path
        default:                    result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - startStream

    private func handleStartStream(_ call: FlutterMethodCall,
                                   result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "BAD_ARGS", message: "Missing arguments", details: nil))
            return
        }

        let host                  = args["host"] as? String ?? ""
        let width                 = args["width"] as? Int ?? 1920
        let height                = args["height"] as? Int ?? 1080
        let fps                   = args["fps"] as? Int ?? 60
        let bitrate               = args["bitrate"] as? Int ?? 20000
        configuredBitrateKbps     = bitrate
        let videoCodec            = args["videoCodec"] as? String ?? "H264"
        let enableHdr             = args["enableHdr"] as? Bool ?? false
        let fullRange             = args["fullRange"] as? Bool ?? false
        let audioConfig           = args["audioConfig"] as? String ?? "stereo"
        let audioQuality          = args["audioQuality"] as? String ?? "high"
        let riKeyHex              = args["riKey"] as? String ?? ""
        let riKeyId               = args["riKeyId"] as? Int ?? 0
        let rtspSessionUrl        = args["rtspSessionUrl"] as? String
        let appVersion            = args["appVersion"] as? String ?? "7.1.431.-1"
        let gfeVersion            = args["gfeVersion"] as? String ?? ""
        let serverCodecModeSupport = args["serverCodecModeSupport"] as? Int ?? 0x0F

        // Resolve codec
        let resolvedCodec: String
        if videoCodec == "auto" || videoCodec == "H265" {
            resolvedCodec = "H265"
        } else if videoCodec == "AV1" {
            resolvedCodec = "AV1"
        } else {
            resolvedCodec = "H264"
        }
        activeCodecName = resolvedCodec

        let colorSpace = enableHdr ? 1 : 0
        let colorRange = fullRange  ? 1 : 0

        let audioConfiguration: Int
        switch audioConfig {
        case "surround51": audioConfiguration = 0x003F06CA
        case "surround71": audioConfiguration = 0x063F08CA
        default:           audioConfiguration = 0x000302CA
        }

        let supportedVideoFormats: Int
        switch resolvedCodec {
        case "H265": supportedVideoFormats = enableHdr ? 0x0F00 : 0x0100
        case "AV1":  supportedVideoFormats = enableHdr ? 0xF000 : 0x1000
        default:     supportedVideoFormats = 0x0001
        }

        // Build AES key / IV
        var riAesKey = [UInt8](repeating: 0, count: 16)
        var riAesIv  = [UInt8](repeating: 0, count: 16)

        if riKeyHex.count >= 32 {
            for i in 0..<16 {
                let start = riKeyHex.index(riKeyHex.startIndex, offsetBy: i * 2)
                let end   = riKeyHex.index(start, offsetBy: 2)
                riAesKey[i] = UInt8(riKeyHex[start..<end], radix: 16) ?? 0
            }
        }
        riAesIv[0] = UInt8((riKeyId >> 24) & 0xFF)
        riAesIv[1] = UInt8((riKeyId >> 16) & 0xFF)
        riAesIv[2] = UInt8((riKeyId >>  8) & 0xFF)
        riAesIv[3] = UInt8( riKeyId        & 0xFF)

        isStreamingActive = true

        // Wire audio quality → slow Opus decoder capability
        moonlightMacSetSlowOpusDecoder(audioQuality != "high")

        NSLog("StreamingPlugin: startStream host=%@ codec=%@ %dx%d@%dfps bitrate=%d",
              host, resolvedCodec, width, height, fps, bitrate)
        NSLog("StreamingPlugin: audioConfig=0x%08X videoFormats=0x%04X colorSpace=%d colorRange=%d",
              audioConfiguration, supportedVideoFormats, colorSpace, colorRange)
        NSLog("StreamingPlugin: riKeyHex=%d chars riKeyId=%d rtspSessionUrl=%@",
              riKeyHex.count, riKeyId, rtspSessionUrl ?? "nil")
        NSLog("StreamingPlugin: appVersion=%@ gfeVersion=%@ serverCodecModeSupport=0x%02X",
              appVersion, gfeVersion, serverCodecModeSupport)

        // Run on background thread (LiStartConnection blocks until connected or failed)
        DispatchQueue.global(qos: .userInteractive).async { [weak self, result] in
            guard let self = self else { return }

            let status = moonlightMacStartConnection(
                host,
                appVersion,
                gfeVersion.isEmpty ? nil : gfeVersion,
                rtspSessionUrl,
                Int32(serverCodecModeSupport),
                Int32(width), Int32(height), Int32(fps),
                Int32(bitrate), 1392 /*packetSize*/,
                2 /*streamingRemotely*/,
                Int32(audioConfiguration),
                Int32(supportedVideoFormats),
                Int32(fps * 100),
                riAesKey,
                riAesIv,
                0 /*videoCapabilities*/,
                Int32(colorSpace),
                Int32(colorRange))

            DispatchQueue.main.async {
                if status == 0 {
                    self.startStatsTimer()
                    result(true)
                } else {
                    self.isStreamingActive = false
                    StreamingBridge.shared.cleanupStreamResources()
                    result(FlutterError(
                        code: "CONNECT_FAILED",
                        message: "LiStartConnection returned \(status)",
                        details: Int(status)))
                }
            }
        }
    }

    // MARK: - stopStream

    private func handleStopStream(result: @escaping FlutterResult) {
        stopStatsTimer()
        moonlightMacInterruptConnection()
        DispatchQueue.global(qos: .userInitiated).async {
            moonlightMacStopConnection()
            DispatchQueue.main.async {
                self.isStreamingActive = false
                StreamingBridge.shared.cleanupStreamResources()
                result(nil)
            }
        }
    }

    // MARK: - Input forwarding

    private func handleSendMouseMove(_ call: FlutterMethodCall, result: FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        moonlightMacSendMouseMove(Int16(args["deltaX"] as? Int ?? 0),
                                   Int16(args["deltaY"] as? Int ?? 0))
        result(nil)
    }

    private func handleSendMousePosition(_ call: FlutterMethodCall, result: FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        moonlightMacSendMousePosition(
            Int16(args["x"]         as? Int ?? 0),
            Int16(args["y"]         as? Int ?? 0),
            Int16(args["refWidth"]  as? Int ?? 1920),
            Int16(args["refHeight"] as? Int ?? 1080))
        result(nil)
    }

    /// Dart sends `{button: int, pressed: bool}`.
    /// Moonlight action constants: 0x07 = BUTTON_ACTION_PRESS, 0x08 = BUTTON_ACTION_RELEASE.
    private func handleSendMouseButton(_ call: FlutterMethodCall, result: FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let pressed = args["pressed"] as? Bool ?? false
        let action: UInt8 = pressed ? 0x07 : 0x08
        let button = UInt8(args["button"] as? Int ?? 1)
        moonlightMacSendMouseButton(action, button)
        result(nil)
    }

    /// Dart sends `{keyCode: int, pressed: bool}`.
    /// Moonlight key action: 0x03 = KEY_ACTION_DOWN, 0x04 = KEY_ACTION_UP.
    private func handleSendKeyboard(_ call: FlutterMethodCall, result: FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let keyCode   = Int16(args["keyCode"]   as? Int ?? 0)
        let pressed   = args["pressed"] as? Bool ?? false
        let keyAction: UInt8 = pressed ? 0x03 : 0x04
        let modifiers = UInt8(args["modifiers"] as? Int ?? 0)
        let flags     = UInt8(args["flags"]     as? Int ?? 0)
        moonlightMacSendKeyboard(keyCode, keyAction, modifiers, flags)
        result(nil)
    }

    private func handleSendScroll(_ call: FlutterMethodCall, result: FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        moonlightMacSendScroll(Int16(args["scrollAmount"] as? Int ?? 0))
        result(nil)
    }

    private func handleSendHighResHScroll(_ call: FlutterMethodCall, result: FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        moonlightMacSendHighResHScroll(Int16(args["scrollAmount"] as? Int ?? 0))
        result(nil)
    }

    private func handleSendGamepadInput(_ call: FlutterMethodCall, result: FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let _ = moonlightMacSendControllerInput(
            Int16(args["controllerNumber"]    as? Int ?? 0),
            Int16(args["activeGamepadMask"]   as? Int ?? 0),
            Int32(args["buttonFlags"]         as? Int ?? 0),
            UInt8(args["leftTrigger"]         as? Int ?? 0),
            UInt8(args["rightTrigger"]        as? Int ?? 0),
            Int16(args["leftStickX"]          as? Int ?? 0),
            Int16(args["leftStickY"]          as? Int ?? 0),
            Int16(args["rightStickX"]         as? Int ?? 0),
            Int16(args["rightStickY"]         as? Int ?? 0))
        result(nil)
    }

    private func handleSendControllerArrival(_ call: FlutterMethodCall,
                                              result: FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let _ = moonlightMacSendControllerArrival(
            Int16(args["controllerNumber"]     as? Int ?? 0),
            Int16(args["activeGamepadMask"]    as? Int ?? 0),
            UInt8(args["controllerType"]       as? Int ?? 0),
            Int16(args["capabilities"]         as? Int ?? 0),
            Int32(args["supportedButtonFlags"] as? Int ?? 0))
        result(nil)
    }

    private func handleSendUtf8Text(_ call: FlutterMethodCall, result: FlutterResult) {
        if let text = (call.arguments as? [String: Any])?["text"] as? String {
            moonlightMacSendUtf8Text(text)
        }
        result(nil)
    }

    // MARK: - Stats

    private func handleGetStats(result: FlutterResult) {
        result(buildStatsMap())
    }

    /// Returns a full codec probe map consistent with Android's CodecProbe.probeAsMap.
    /// Dart receives: { "best": "H265", "h264": true, "h265": true, "av1": false }
    private func handleProbeCodec(_ call: FlutterMethodCall, result: FlutterResult) {
        let args   = call.arguments as? [String: Any] ?? [:]
        let width  = args["width"] as? Int ?? 1920
        let height = args["height"] as? Int ?? 1080
        let fps    = args["fps"] as? Int ?? 60

        let h264ok = VideoToolboxProbe.supports(codec: "H264", width: width, height: height, fps: fps)
        let h265ok = VideoToolboxProbe.supports(codec: "H265", width: width, height: height, fps: fps)
        let av1ok  = VideoToolboxProbe.supports(codec: "AV1",  width: width, height: height, fps: fps)

        // Pick best: AV1 > H265 > H264 (same ranking as Android CodecProbe)
        let best: String
        if av1ok       { best = "AV1" }
        else if h265ok { best = "H265" }
        else           { best = "H264" }

        result([
            "best": best,
            "h264": h264ok,
            "h265": h265ok,
            "av1":  av1ok,
        ] as [String: Any])
    }

    // MARK: - Stats timer

    private func startStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.emitStats()
        }
    }

    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    private func emitStats() {
        let statsMap = buildStatsMap()
        var event = statsMap
        event["type"] = "stats"
        eventSink?(event)
    }

    /// Builds stats map with keys matching Android format for Dart metrics.
    /// Computes FPS as delta of framesDecoded between 1-second ticks.
    private func buildStatsMap() -> [String: Any] {
        let bridge = StreamingBridge.shared
        let pendingFrames  = Int(moonlightMacGetPendingVideoFrames())
        let pendingAudioMs = Int(moonlightMacGetPendingAudioDuration())
        let rttInfo        = Int(moonlightMacGetEstimatedRttInfo())
        let rttMs          = rttInfo & 0xFFFF
        let rttVarianceMs  = (rttInfo >> 16) & 0xFFFF

        // Compute FPS and drop rate as delta since last tick (1 second interval)
        let currentDecoded = bridge.totalFramesDecoded
        let currentDropped = bridge.totalFramesDropped
        let fps = max(0, currentDecoded - lastFramesDecoded)
        let dropped = max(0, currentDropped - lastFramesDropped)
        let dropRate = (fps + dropped) > 0
            ? (dropped * 100) / (fps + dropped)
            : 0
        lastFramesDecoded = currentDecoded
        lastFramesDropped = currentDropped

        // Bitrate in Mbps (configured is in Kbps)
        let bitrateMbps = configuredBitrateKbps / 1000

        return [
            // Keys matching Android format (used by Dart _recordSessionMetrics)
            "fps":               fps,
            "decodeTime":        bridge.decodeTimeAvgMs,
            "bitrate":           bitrateMbps,
            "dropRate":          dropRate,
            "resolution":        "\(bridge.videoWidth)x\(bridge.videoHeight)",
            "codec":             activeCodecName,
            "queueDepth":        pendingFrames,
            "pendingAudioMs":    pendingAudioMs,
            "rttMs":             rttMs,
            "rttVarianceMs":     rttVarianceMs,
            "totalRendered":     currentDecoded,
            "totalDropped":      currentDropped,
            "decoderName":       "VideoToolbox",
            "renderPath":        "texture",
            "platform":          "macos",
        ]
    }

    // MARK: - StreamingBridgeDelegate

    func onConnectionStarted() {
        sendEvent(["type": "connectionStarted"])
    }

    func onConnectionTerminated(errorCode: Int32) {
        isStreamingActive = false
        stopStatsTimer()
        StreamingBridge.shared.cleanupStreamResources()
        sendEvent(["type": "connectionTerminated", "errorCode": Int(errorCode)])
    }

    func onStageStarting(stage: Int32) {
        sendEvent(["type": "stageStarting", "stage": Int(stage),
                   "stageName": String(cString: moonlightMacGetStageName(stage))])
    }

    func onStageComplete(stage: Int32) {
        sendEvent(["type": "stageComplete", "stage": Int(stage)])
    }

    func onStageFailed(stage: Int32, errorCode: Int32) {
        sendEvent(["type": "stageFailed", "stage": Int(stage),
                   "errorCode": Int(errorCode),
                   "stageName": String(cString: moonlightMacGetStageName(stage))])
    }

    func onConnectionStatusUpdate(status: Int32) {
        sendEvent(["type": "connectionStatusUpdate", "status": Int(status)])
    }

    func onRumble(controllerNumber: UInt16,
                  lowFreqMotor: UInt16, highFreqMotor: UInt16) {
        sendEvent(["type": "rumble",
                   "controllerNumber": Int(controllerNumber),
                   "lowFreqMotor":     Int(lowFreqMotor),
                   "highFreqMotor":    Int(highFreqMotor)])
    }

    func onRumbleTriggers(controllerNumber: UInt16,
                          leftTrigger: UInt16, rightTrigger: UInt16) {
        sendEvent(["type": "rumbleTriggers",
                   "controllerNumber": Int(controllerNumber),
                   "leftTrigger":      Int(leftTrigger),
                   "rightTrigger":     Int(rightTrigger)])
    }

    func onSetMotionEventState(controllerNumber: UInt16,
                               motionType: UInt8, reportRateHz: UInt16) {
        sendEvent(["type": "setMotionEventState",
                   "controllerNumber": Int(controllerNumber),
                   "motionType":       Int(motionType),
                   "reportRateHz":     Int(reportRateHz)])
    }

    func onSetControllerLED(controllerNumber: UInt16,
                            r: UInt8, g: UInt8, b: UInt8) {
        sendEvent(["type": "setControllerLED",
                   "controllerNumber": Int(controllerNumber),
                   "r": Int(r), "g": Int(g), "b": Int(b)])
    }

    func onSetHdrMode(enabled: Bool) {
        sendEvent(["type": "hdrMode", "enabled": enabled])
    }

    // MARK: - Helpers

    private func sendEvent(_ event: [String: Any]) {
        // Already on main thread (dispatched by StreamingBridge)
        eventSink?(event)
    }
}

// MARK: - VideoToolbox codec probe helper

private enum VideoToolboxProbe {
    static func supports(codec: String, width: Int, height: Int, fps: Int) -> Bool {
        let codecType: CMVideoCodecType
        switch codec {
        case "H265": codecType = kCMVideoCodecType_HEVC
        case "AV1":
            if #available(macOS 13.0, *) { codecType = kCMVideoCodecType_AV1 }
            else { return false }
        default:     codecType = kCMVideoCodecType_H264
        }
        return VTIsHardwareDecodeSupported(codecType)
    }
}
