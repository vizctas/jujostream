// Swift-side singleton bridging moonlight-common-c callbacks to Flutter.

import Foundation
import FlutterMacOS

// MARK: - Callback sink protocol (implemented by StreamingPlugin)

protocol StreamingBridgeDelegate: AnyObject {
    func onConnectionStarted()
    func onConnectionTerminated(errorCode: Int32)
    func onStageStarting(stage: Int32)
    func onStageComplete(stage: Int32)
    func onStageFailed(stage: Int32, errorCode: Int32)
    func onConnectionStatusUpdate(status: Int32)
    func onRumble(controllerNumber: UInt16, lowFreqMotor: UInt16, highFreqMotor: UInt16)
    func onRumbleTriggers(controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16)
    func onSetMotionEventState(controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16)
    func onSetControllerLED(controllerNumber: UInt16, r: UInt8, g: UInt8, b: UInt8)
    func onSetHdrMode(enabled: Bool)
}

// MARK: - StreamingBridge

final class StreamingBridge {

    // MARK: Singleton
    static let shared = StreamingBridge()
    private init() {}

    // MARK: Public dependencies (set by StreamingPlugin during setup)
    weak var delegate: StreamingBridgeDelegate?
    var textureRegistry: FlutterTextureRegistry?

    // MARK: Private components
    fileprivate let videoDecoder = VideoDecoder()
    fileprivate let audioRenderer = AudioRendererMac()

    // MARK: - Bootstrap

    /// Call once at plugin attach time.
    func registerCBridgeCallbacks() {
        var cbs = JujostreamMacCallbacks()
        cbs.onVideoSetup    = cbVideoSetup
        cbs.onVideoStart    = cbVideoStart
        cbs.onVideoStop     = cbVideoStop
        cbs.onVideoCleanup  = cbVideoCleanup
        cbs.onVideoFrame    = cbVideoFrame

        cbs.onAudioInit     = cbAudioInit
        cbs.onAudioStart    = cbAudioStart
        cbs.onAudioStop     = cbAudioStop
        cbs.onAudioCleanup  = cbAudioCleanup
        cbs.onAudioSample   = cbAudioSample

        cbs.onConnectionStarted     = cbConnectionStarted
        cbs.onConnectionTerminated  = cbConnectionTerminated
        cbs.onStageStarting         = cbStageStarting
        cbs.onStageComplete         = cbStageComplete
        cbs.onStageFailed           = cbStageFailed
        cbs.onConnectionStatusUpdate = cbConnectionStatusUpdate
        cbs.onRumble                = cbRumble
        cbs.onRumbleTriggers        = cbRumbleTriggers
        cbs.onSetMotionEventState   = cbSetMotionEventState
        cbs.onSetControllerLED      = cbSetControllerLED
        cbs.onSetHdrMode            = cbSetHdrMode

        moonlightMacRegisterCallbacks(&cbs)
    }

    // MARK: - VideoDecoder access

    var videoTextureId: Int64 { videoDecoder.textureId }

    /// Expose decode latency and frame count for stats.
    var decodeTimeAvgMs: Double { videoDecoder.avgDecodeLatencyMs }
    var totalFramesDecoded: Int { videoDecoder.totalFramesDecoded }
    var totalFramesDropped: Int { videoDecoder.totalFramesDropped }

    /// Expose video dimensions for stats resolution string.
    var videoWidth:  Int { videoDecoder.videoWidth }
    var videoHeight: Int { videoDecoder.videoHeight }

    // MARK: - Cleanup

    func cleanupStreamResources() {
        videoDecoder.cleanup()
        audioRenderer.teardown()
    }
}

// MARK: - C-compatible top-level callbacks
// These are plain C function pointers — they cannot be closures or methods.
// They access StreamingBridge.shared which is safe because the singleton
// is initialised before any stream connection is attempted.

private func cbVideoSetup(_ videoFormat: Int32, _ width: Int32,
                           _ height: Int32, _ redrawRate: Int32) -> Int32 {
    let bridge = StreamingBridge.shared
    guard let reg = bridge.textureRegistry else { return -1 }
    return Int32(bridge.videoDecoder.setup(
        videoFormat: videoFormat,
        width: Int(width),
        height: Int(height),
        fps: Int(redrawRate),
        registry: reg))
}

private func cbVideoStart() {}
private func cbVideoStop()  {}

private func cbVideoCleanup() {
    StreamingBridge.shared.videoDecoder.cleanup()
}

private func cbVideoFrame(_ data: UnsafePointer<UInt8>?,
                           _ length: Int32,
                           _ frameType: Int32,
                           _ frameNumber: Int32,
                           _ receiveTimeMs: Int64) -> Int32 {
    guard let ptr = data else { return 0 }
    return StreamingBridge.shared.videoDecoder.submitNAL(
        data: ptr,
        length: Int(length),
        bufferType: frameType,
        frameNumber: frameNumber,
        receiveTimeMs: receiveTimeMs)
}

private func cbAudioInit(_ audioConfig: Int32,
                          _ sampleRate: Int32,
                          _ samplesPerFrame: Int32) -> Int32 {
    return StreamingBridge.shared.audioRenderer.setup(
        audioConfig: audioConfig,
        sampleRate: sampleRate,
        samplesPerFrame: samplesPerFrame)
}

private func cbAudioStart()   { StreamingBridge.shared.audioRenderer.start() }
private func cbAudioStop()    { StreamingBridge.shared.audioRenderer.stop() }
private func cbAudioCleanup() { StreamingBridge.shared.audioRenderer.teardown() }

private func cbAudioSample(_ data: UnsafePointer<Int8>?, _ length: Int32) {
    guard let ptr = data else { return }
    StreamingBridge.shared.audioRenderer.submit(pcmData: ptr, byteCount: Int(length))
}

// MARK: Connection events — dispatch to main thread for EventSink safety

private func dispatchToDelegate(_ block: @escaping (StreamingBridgeDelegate) -> Void) {
    DispatchQueue.main.async {
        guard let d = StreamingBridge.shared.delegate else { return }
        block(d)
    }
}

private func cbConnectionStarted() {
    dispatchToDelegate { $0.onConnectionStarted() }
}

private func cbConnectionTerminated(_ errorCode: Int32) {
    dispatchToDelegate { $0.onConnectionTerminated(errorCode: errorCode) }
}

private func cbStageStarting(_ stage: Int32) {
    dispatchToDelegate { $0.onStageStarting(stage: stage) }
}

private func cbStageComplete(_ stage: Int32) {
    dispatchToDelegate { $0.onStageComplete(stage: stage) }
}

private func cbStageFailed(_ stage: Int32, _ errorCode: Int32) {
    dispatchToDelegate { $0.onStageFailed(stage: stage, errorCode: errorCode) }
}

private func cbConnectionStatusUpdate(_ status: Int32) {
    dispatchToDelegate { $0.onConnectionStatusUpdate(status: status) }
}

private func cbRumble(_ cn: UInt16, _ low: UInt16, _ high: UInt16) {
    dispatchToDelegate { $0.onRumble(controllerNumber: cn, lowFreqMotor: low, highFreqMotor: high) }
}

private func cbRumbleTriggers(_ cn: UInt16, _ lt: UInt16, _ rt: UInt16) {
    dispatchToDelegate { $0.onRumbleTriggers(controllerNumber: cn, leftTrigger: lt, rightTrigger: rt) }
}

private func cbSetMotionEventState(_ cn: UInt16, _ mt: UInt8, _ hz: UInt16) {
    dispatchToDelegate { $0.onSetMotionEventState(controllerNumber: cn, motionType: mt, reportRateHz: hz) }
}

private func cbSetControllerLED(_ cn: UInt16, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
    dispatchToDelegate { $0.onSetControllerLED(controllerNumber: cn, r: r, g: g, b: b) }
}

private func cbSetHdrMode(_ enabled: Bool) {
    dispatchToDelegate { $0.onSetHdrMode(enabled: enabled) }
}
