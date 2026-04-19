// Hardware H.264 / H.265 / AV1 decoder for macOS using VideoToolbox.

import Foundation
import VideoToolbox
import CoreVideo
import CoreMedia
import FlutterMacOS

final class VideoDecoder: NSObject, FlutterTexture {

    // MARK: - Public state
    private(set) var textureId: Int64 = -1

    // MARK: - Private
    private var session:            VTDecompressionSession?
    private var formatDescription:  CMVideoFormatDescription?
    private let pixelBufferLock     = NSLock()
    private var latestPixelBuffer:  CVPixelBuffer?
    private weak var textureRegistry: FlutterTextureRegistry?

    // Format metadata
    private var videoFormat: Int32 = 0
    private var width:       Int   = 0
    private var height:      Int   = 0
    private var fps:         Int   = 0

    var videoWidth:  Int { width }
    var videoHeight: Int { height }

    // Old isHEVC() used (videoFormat & 0xFF00) != 0 which incorrectly
    // matched AV1 formats (0x1000/0xF000) as HEVC.
    private enum VideoCodecType { case h264, hevc, av1 }
    private var detectedCodec: VideoCodecType {
        if (videoFormat & 0xF000) != 0 { return .av1 }   // 0x1000 SDR, 0xF000 HDR
        if (videoFormat & 0x0F00) != 0 { return .hevc }   // 0x0100 SDR, 0x0F00 HDR
        return .h264                                       // 0x0001 SDR
    }

    // H.264 parameter sets
    private var spsData: Data?
    private var ppsData: Data?

    // H.265 parameter sets
    private var vpsData: Data?
    private var h265SpsData: Data?
    private var h265PpsData: Data?

    // Moonlight frequently sends parameter sets in IDR frames to aid recovery.
    // Blindly rebuilding the VT session on every PPS destroys the decoder pipeline,
    // leading to massive frame drops. We only rebuild if the data actively changes.
    private var h264NeedsRebuild = false
    private var hevcNeedsRebuild = false

    // After `kMaxConsecutiveErrors` failures, submitNAL returns DR_NEED_IDR (-1)
    // so moonlight-common-c requests a new keyframe from the server.
    private var consecutiveDecodeErrors: Int = 0
    private static let kMaxConsecutiveErrors = 5
    private static let drNeedIDR: Int32 = -1

    // Stores the submit timestamp (mach_absolute_time) keyed by frame refcon.
    // The VT callback computes the delta to produce avgDecodeLatencyMs.
    private var lastSubmitTimeNs: UInt64 = 0
    private var decodeLatencySumMs: Double = 0
    private var decodeLatencyCount: Int = 0
    private let latencyLock = NSLock()
    /// Rolling average decode latency in milliseconds.
    var avgDecodeLatencyMs: Double {
        latencyLock.lock()
        defer { latencyLock.unlock() }
        return decodeLatencyCount > 0 ? decodeLatencySumMs / Double(decodeLatencyCount) : 0
    }
    /// Total frames decoded (for stats).
    private(set) var totalFramesDecoded: Int = 0
    /// Total frames dropped (for stats).
    /// Includes both decode errors and presentation drops (when a new decoded
    /// frame overwrites a previous one that Flutter's raster thread never consumed).
    private(set) var totalFramesDropped: Int = 0
    /// Tracks whether the last decoded frame was consumed by copyPixelBuffer().
    /// If a new frame arrives before the previous one was consumed, it's a drop.
    private var lastFrameConsumed: Bool = true

    // MARK: - Setup

    /// Called from StreamingBridge.onVideoSetup
    func setup(videoFormat: Int32,
               width: Int,
               height: Int,
               fps: Int,
               registry: FlutterTextureRegistry) -> Int {
        self.videoFormat = videoFormat
        self.width       = width
        self.height      = height
        self.fps         = fps
        self.textureRegistry = registry

        spsData = nil; ppsData = nil
        vpsData = nil; h265SpsData = nil; h265PpsData = nil
        h264NeedsRebuild = false; hevcNeedsRebuild = false
        invalidateSession()

        textureId = registry.register(self)
        NSLog("VideoDecoder: setup videoFormat=0x%04X %dx%d@%dfps codec=%@ textureId=%lld",
              videoFormat, width, height, fps,
              detectedCodec == .av1 ? "AV1" : (detectedCodec == .hevc ? "HEVC" : "H264"),
              textureId)
        return 0
    }

    func cleanup() {
        invalidateSession()
        if textureId >= 0 {
            textureRegistry?.unregisterTexture(textureId)
            textureId = -1
        }
        pixelBufferLock.lock()
        latestPixelBuffer = nil
        pixelBufferLock.unlock()
    }

    // MARK: - NAL Unit submission

        private static let bufferTypePicData:      Int32 = 0x00  // BUFFER_TYPE_PICDATA
    private static let bufferTypeSPS:          Int32 = 0x01  // BUFFER_TYPE_SPS
    private static let bufferTypePPS:          Int32 = 0x02  // BUFFER_TYPE_PPS
    private static let bufferTypeVPS:          Int32 = 0x03  // BUFFER_TYPE_VPS

        @discardableResult
    func submitNAL(data: UnsafePointer<UInt8>, length: Int,
                   bufferType: Int32, frameNumber: Int32,
                   receiveTimeMs: Int64) -> Int32 {

        let rawData = Data(bytes: data, count: length)

        switch detectedCodec {
        case .av1:
            // AV1 uses OBU format — no separate SPS/PPS/VPS.
            // All data arrives as PICDATA. The first keyframe contains
            // a Sequence Header OBU that VideoToolbox parses internally.
            if bufferType == VideoDecoder.bufferTypePicData {
                return decodeAV1Picture(rawData)
            }
            // AV1 may still receive SPS/VPS/PPS buffer types from
            // moonlight-common-c for compatibility — ignore them.
            return 0

        case .hevc:
            switch bufferType {
            case VideoDecoder.bufferTypeVPS:
                let newVps = stripStartCode(rawData)
                if newVps != vpsData { vpsData = newVps; hevcNeedsRebuild = true }
                return 0
            case VideoDecoder.bufferTypeSPS:
                let newSps = stripStartCode(rawData)
                if newSps != h265SpsData { h265SpsData = newSps; hevcNeedsRebuild = true }
                return 0
            case VideoDecoder.bufferTypePPS:
                let newPps = stripStartCode(rawData)
                if newPps != h265PpsData { h265PpsData = newPps; hevcNeedsRebuild = true }
                if hevcNeedsRebuild, let vps = vpsData, let sps = h265SpsData, let pps = h265PpsData {
                    rebuildHEVCSession(vps: vps, sps: sps, pps: pps)
                    hevcNeedsRebuild = false
                }
                return 0
            case VideoDecoder.bufferTypePicData:
                return decodePicture(rawData)
            default:
                return 0
            }

        case .h264:
            switch bufferType {
            case VideoDecoder.bufferTypeSPS:
                let newSps = stripStartCode(rawData)
                if newSps != spsData { spsData = newSps; h264NeedsRebuild = true }
                return 0
            case VideoDecoder.bufferTypePPS:
                let newPps = stripStartCode(rawData)
                if newPps != ppsData { ppsData = newPps; h264NeedsRebuild = true }
                if h264NeedsRebuild, let sps = spsData, let pps = ppsData {
                    rebuildH264Session(sps: sps, pps: pps)
                    h264NeedsRebuild = false
                }
                return 0
            case VideoDecoder.bufferTypePicData:
                return decodePicture(rawData)
            default:
                return 0
            }
        }
    }

    // MARK: - H.264 session

    private func rebuildH264Session(sps: Data, pps: Data) {
        invalidateSession()

        var parameterSets: [UnsafePointer<UInt8>?]  = []
        var parameterSizes: [Int] = []

        sps.withUnsafeBytes { parameterSets.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
        pps.withUnsafeBytes { parameterSets.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
        parameterSizes = [sps.count, pps.count]

        var fmtDesc: CMVideoFormatDescription?
        let err = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: nil,
            parameterSetCount: 2,
            parameterSetPointers: parameterSets.map { $0! },
            parameterSetSizes: parameterSizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &fmtDesc)

        guard err == noErr, let fmt = fmtDesc else {
            NSLog("VideoDecoder: H.264 format description failed: %d (sps=%d pps=%d bytes)",
                  err, sps.count, pps.count)
            return
        }
        self.formatDescription = fmt
        createDecompressionSession(format: fmt)
        NSLog("VideoDecoder: H.264 session created (sps=%d pps=%d bytes, session=%@)",
              sps.count, pps.count, session != nil ? "OK" : "FAILED")
    }

    // MARK: - HEVC session

    private func rebuildHEVCSession(vps: Data, sps: Data, pps: Data) {
        invalidateSession()

        var parameterSets: [UnsafePointer<UInt8>?] = []
        var parameterSizes: [Int] = []

        vps.withUnsafeBytes { parameterSets.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
        sps.withUnsafeBytes { parameterSets.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
        pps.withUnsafeBytes { parameterSets.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
        parameterSizes = [vps.count, sps.count, pps.count]

        var fmtDesc: CMVideoFormatDescription?
        if #available(macOS 11.0, *) {
            let err = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: nil,
                parameterSetCount: 3,
                parameterSetPointers: parameterSets.map { $0! },
                parameterSetSizes: parameterSizes,
                nalUnitHeaderLength: 4,
                extensions: nil,
                formatDescriptionOut: &fmtDesc)
            guard err == noErr, let fmt = fmtDesc else { return }
            self.formatDescription = fmt
            createDecompressionSession(format: fmt)
        }
    }

    // MARK: - AV1 session

        private func decodeAV1Picture(_ data: Data) -> Int32 {
        // Lazy session creation: build on first frame (which contains Sequence Header OBU)
        if session == nil {
            rebuildAV1Session()
        }
        guard let session = session, let fmt = formatDescription else { return 0 }

        if consecutiveDecodeErrors >= VideoDecoder.kMaxConsecutiveErrors {
            consecutiveDecodeErrors = 0
            NSLog("VideoDecoder: requesting IDR after consecutive AV1 errors")
            return VideoDecoder.drNeedIDR
        }

        // AV1 OBU data goes directly into CMBlockBuffer — no start code conversion
        var blockBuffer: CMBlockBuffer?
        var err = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard err == noErr, let bb = blockBuffer else { return 0 }

        err = data.withUnsafeBytes { ptr -> OSStatus in
            CMBlockBufferReplaceDataBytes(
                with: ptr.baseAddress!,
                blockBuffer: bb,
                offsetIntoDestination: 0,
                dataLength: data.count)
        }
        guard err == noErr else { return 0 }

        var sampleBuffer: CMSampleBuffer?
        let sbErr = CMSampleBufferCreateReady(
            allocator: nil,
            dataBuffer: bb,
            formatDescription: fmt,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer)
        guard sbErr == noErr, let sb = sampleBuffer else { return 0 }

        lastSubmitTimeNs = mach_absolute_time()

        let flags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sb,
            flags: flags,
            frameRefcon: nil,
            infoFlagsOut: nil)

        return 0 // DR_OK
    }

    private func rebuildAV1Session() {
        invalidateSession()

        // kCMVideoCodecType_AV1 is available on macOS 14.0+ (Sonoma).
        // On older macOS or non-M3 hardware, this will fail gracefully.
        if #available(macOS 14.0, *) {
            var fmtDesc: CMVideoFormatDescription?
            let err = CMVideoFormatDescriptionCreate(
                allocator: nil,
                codecType: kCMVideoCodecType_AV1,
                width: Int32(width),
                height: Int32(height),
                extensions: nil,
                formatDescriptionOut: &fmtDesc)

            guard err == noErr, let fmt = fmtDesc else {
                NSLog("VideoDecoder: AV1 format description creation failed: \(err)")
                return
            }
            self.formatDescription = fmt
            createDecompressionSession(format: fmt)

            if session != nil {
                NSLog("VideoDecoder: AV1 session created (\(width)x\(height))")
            } else {
                NSLog("VideoDecoder: AV1 session creation failed — hardware may not support AV1")
            }
        } else {
            NSLog("VideoDecoder: AV1 requires macOS 14.0+ (current system too old)")
        }
    }

    // MARK: - Decompression session

    private func createDecompressionSession(format: CMVideoFormatDescription) {
        // VideoToolbox natively outputs NV12 — requesting BGRA forces an
        // internal color-space conversion on every frame. Flutter's Metal
        // engine has a dedicated wrapNV12ExternalPixelBuffer path that
        // handles NV12 via a dual-plane Metal shader, so no CPU copy occurs.
        // Combined with IOSurface backing, this is a true zero-copy path:
        //   VT decoder → IOSurface (NV12) → CVMetalTexture → Flutter GPU
        //
        // Use FullRange for HDR content, VideoRange for SDR.
        let isHDR = (videoFormat & 0x0F00) == 0x0F00 || (videoFormat & 0xF000) == 0xF000
        let nv12Format: OSType = isHDR
            ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: nv12Format,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]

        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { (decompressionOutputRefCon, _, status, _, imageBuffer, _, _) in
                guard let ref = decompressionOutputRefCon else { return }
                let decoder = Unmanaged<VideoDecoder>.fromOpaque(ref).takeUnretainedValue()
                decoder.handleDecodedFrame(status: status, imageBuffer: imageBuffer)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        // VideoToolbox may silently fall back to software decoding on some
        // Mac configurations, causing high CPU usage and frame drops.
        let decoderSpec: [CFString: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ]

        var sess: VTDecompressionSession?
        var err = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: format,
            decoderSpecification: decoderSpec as CFDictionary,
            imageBufferAttributes: pixelBufferAttributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &sess)

        // Fallback: if HW-only fails (e.g. unsupported profile), retry without constraint
        if err != noErr {
            NSLog("VideoDecoder: HW-only session failed (%d), retrying without constraint", err)
            err = VTDecompressionSessionCreate(
                allocator: nil,
                formatDescription: format,
                decoderSpecification: nil,
                imageBufferAttributes: pixelBufferAttributes as CFDictionary,
                outputCallback: &outputCallback,
                decompressionSessionOut: &sess)
        }

        if err == noErr {
            session = sess
            // Allow B-frames in the decode queue
            VTSessionSetProperty(sess!, key: kVTDecompressionPropertyKey_ThreadCount,
                                 value: NSNumber(value: 0))
        }
    }

    private func invalidateSession() {
        if let s = session {
            VTDecompressionSessionInvalidate(s)
            session = nil
        }
        formatDescription = nil
        // a frame from the old session while the new one initializes.
        pixelBufferLock.lock()
        latestPixelBuffer = nil
        pixelBufferLock.unlock()
    }

    // MARK: - Picture decoding

    private func decodePicture(_ data: Data) -> Int32 {
        guard let session = session else { return 0 }

        if consecutiveDecodeErrors >= VideoDecoder.kMaxConsecutiveErrors {
            consecutiveDecodeErrors = 0
            NSLog("VideoDecoder: requesting IDR after consecutive errors")
            return VideoDecoder.drNeedIDR
        }

        // Convert Annex-B (start codes) to AVCC/HVCC (4-byte length prefix)
        guard let sampleBuffer = makeAVCCSampleBuffer(from: data) else { return 0 }

        lastSubmitTimeNs = mach_absolute_time()

        let flags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: flags,
            frameRefcon: nil,
            infoFlagsOut: nil)

        return 0 // DR_OK
    }

    // MARK: - Frame callback

        private func handleDecodedFrame(status: OSStatus, imageBuffer: CVImageBuffer?) {
        if status != noErr || imageBuffer == nil {
            consecutiveDecodeErrors += 1
            totalFramesDropped += 1
            if consecutiveDecodeErrors == VideoDecoder.kMaxConsecutiveErrors {
                NSLog("VideoDecoder: \(consecutiveDecodeErrors) consecutive decode errors — will request IDR")
            }
            return
        }
        // Success — reset error counter
        if consecutiveDecodeErrors > 0 {
            consecutiveDecodeErrors = 0
        }

        let submitTime = lastSubmitTimeNs
        if submitTime > 0 {
            let now = mach_absolute_time()
            let deltaTicks = now - submitTime
            var info = mach_timebase_info_data_t()
            mach_timebase_info(&info)
            let deltaMs = Double(deltaTicks) * Double(info.numer) / Double(info.denom) / 1_000_000.0
            latencyLock.lock()
            // Exponential moving average (α=0.1) for smooth reporting
            if decodeLatencyCount == 0 {
                decodeLatencySumMs = deltaMs
            } else {
                decodeLatencySumMs = decodeLatencySumMs * 0.9 + deltaMs * 0.1
            }
            decodeLatencyCount = 1 // EMA always uses count=1
            latencyLock.unlock()
        }
        totalFramesDecoded += 1

        pixelBufferLock.lock()
        // Track presentation drops: if the previous frame was never consumed
        // by Flutter's raster thread (copyPixelBuffer), it's a dropped frame.
        if !lastFrameConsumed && latestPixelBuffer != nil {
            totalFramesDropped += 1
        }
        latestPixelBuffer = imageBuffer
        lastFrameConsumed = false
        pixelBufferLock.unlock()
        textureRegistry?.textureFrameAvailable(textureId)
    }

    // MARK: - FlutterTexture

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        pixelBufferLock.lock()
        defer { pixelBufferLock.unlock() }
        guard let pb = latestPixelBuffer else { return nil }
        lastFrameConsumed = true
        return Unmanaged.passRetained(pb)
    }

    // MARK: - Helpers

        private func stripStartCode(_ data: Data) -> Data {
        if data.count >= 4 && data[0] == 0 && data[1] == 0 &&
           data[2] == 0 && data[3] == 1 {
            return data.dropFirst(4)
        }
        if data.count >= 3 && data[0] == 0 && data[1] == 0 && data[2] == 1 {
            return data.dropFirst(3)
        }
        return data
    }

        private func makeAVCCSampleBuffer(from annexB: Data) -> CMSampleBuffer? {
        guard let fmt = formatDescription else { return nil }

        // Split the Annex-B stream into individual NAL units and convert to AVCC
        let avccData = annexBToAVCC(annexB)
        guard !avccData.isEmpty else { return nil }

        var blockBuffer: CMBlockBuffer?

        var err = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,           // let CM allocate
            blockLength: avccData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccData.count,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard err == noErr, let bb = blockBuffer else { return nil }

        // Copy the AVCC data into the block buffer's owned memory
        err = avccData.withUnsafeBytes { ptr -> OSStatus in
            CMBlockBufferReplaceDataBytes(
                with: ptr.baseAddress!,
                blockBuffer: bb,
                offsetIntoDestination: 0,
                dataLength: avccData.count)
        }
        guard err == noErr else { return nil }

        var sampleBuffer: CMSampleBuffer?
        let sbErr = CMSampleBufferCreateReady(
            allocator: nil,
            dataBuffer: bb,
            formatDescription: fmt,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer)

        return sbErr == noErr ? sampleBuffer : nil
    }

        private func annexBToAVCC(_ data: Data) -> Data {
        var result = Data(capacity: data.count)
        let bytes = [UInt8](data)
        let count = bytes.count
        var i = 0

        // Find all NAL unit boundaries (start code positions)
        var nalStarts: [Int] = []
        while i < count {
            // Check for 4-byte start code: 0x00000001
            if i + 3 < count && bytes[i] == 0 && bytes[i+1] == 0 &&
               bytes[i+2] == 0 && bytes[i+3] == 1 {
                nalStarts.append(i + 4)
                i += 4
            }
            // Check for 3-byte start code: 0x000001
            else if i + 2 < count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 1 {
                nalStarts.append(i + 3)
                i += 3
            }
            else {
                i += 1
            }
        }

        // If no start codes found, treat entire data as a single NAL unit
        if nalStarts.isEmpty {
            var length = CFSwapInt32HostToBig(UInt32(count))
            result.append(contentsOf: withUnsafeBytes(of: &length, Array.init))
            result.append(contentsOf: bytes)
            return result
        }

        // Convert each NAL unit: replace start code with 4-byte length prefix
        for (idx, start) in nalStarts.enumerated() {
            let end: Int
            if idx + 1 < nalStarts.count {
                // Find the start code position of the next NAL
                // The start code is either 3 or 4 bytes before nalStarts[idx+1]
                let nextNalDataStart = nalStarts[idx + 1]
                // Check if it was a 4-byte or 3-byte start code
                if nextNalDataStart >= 4 && bytes[nextNalDataStart - 4] == 0 &&
                   bytes[nextNalDataStart - 3] == 0 && bytes[nextNalDataStart - 2] == 0 &&
                   bytes[nextNalDataStart - 1] == 1 {
                    end = nextNalDataStart - 4
                } else {
                    end = nextNalDataStart - 3
                }
            } else {
                end = count
            }

            let nalLength = end - start
            if nalLength > 0 {
                var length = CFSwapInt32HostToBig(UInt32(nalLength))
                result.append(contentsOf: withUnsafeBytes(of: &length, Array.init))
                result.append(contentsOf: bytes[start..<end])
            }
        }

        return result
    }
}
