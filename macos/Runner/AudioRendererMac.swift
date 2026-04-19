// PCM audio playback for macOS using AVAudioEngine.

import Foundation
import AVFoundation

final class AudioRendererMac {

    // MARK: - Private state
    private let audioLock = NSLock()
    private var engine:          AVAudioEngine?
    private var playerNode:      AVAudioPlayerNode?
    private var audioFormat:     AVAudioFormat?
    private var channelCount:    Int = 2
    private var sampleRate:      Double = 48000
    private var samplesPerFrame: Int = 240
    
    // O(1) buffer pool to prevent memory allocation jitter during callbacks
    private var bufferPool: [AVAudioPCMBuffer] = []
    private var poolIndex:  Int = 0

    // MARK: - Lifecycle

    /// Called from onAudioInit.  Returns 0 on success, -1 on failure.
    func setup(audioConfig: Int32,
               sampleRate: Int32,
               samplesPerFrame: Int32) -> Int32 {
        teardown()

        self.channelCount    = audioConfigChannelCount(audioConfig)
        self.sampleRate      = Double(sampleRate)
        self.samplesPerFrame = Int(samplesPerFrame)

        // Use AVAudioFormat standard Float32 Non-Interleaved format
        // which is the only reliable format for AVAudioPlayerNode scheduleBuffer.
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: self.sampleRate,
            channels: AVAudioChannelCount(channelCount)
        ) else { return -1 }

        self.audioFormat = format

        // Preallocate 64 buffers to cycle through (plenty for 5ms slices)
        // 4096 frames capacity covers any reasonable samplesPerFrame configuration.
        bufferPool.removeAll()
        for _ in 0..<64 {
            if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) {
                bufferPool.append(buf)
            }
        }
        self.poolIndex = 0

        let eng = AVAudioEngine()
        let player = AVAudioPlayerNode()
        eng.attach(player)

        // Connect the player to the mixer with our exact Standard format
        eng.connect(player, to: eng.mainMixerNode, format: format)

        do {
            try eng.start()
        } catch {
            NSLog("AudioRendererMac: AVAudioEngine start failed: \(error)")
            return -1
        }

        self.engine     = eng
        self.playerNode = player
        
        // Note: Do NOT call player.play() here. The queue is empty, so it will 
        // immediately reach EOF and silently stop. We must call play() after providing buffers.

        return 0
    }

    func start() { playerNode?.play() }

    func stop() { playerNode?.stop() }

    func teardown() {
        audioLock.lock()
        defer { audioLock.unlock() }
        playerNode?.stop()
        engine?.stop()
        engine          = nil
        playerNode      = nil
        audioFormat     = nil
        bufferPool.removeAll()
    }

    // MARK: - Audio feed (called from C callback, any thread)

    /// pcmData contains raw little-endian int16 PCM interleaved samples (LRLRLR...).
    func submit(pcmData: UnsafePointer<Int8>, byteCount: Int) {
        audioLock.lock()
        defer { audioLock.unlock() }

        guard let player = playerNode,
              !bufferPool.isEmpty else { return }

        // Each frame = channelCount * 2 bytes (one int16 per channel)
        let frameCount = byteCount / (channelCount * 2)
        guard frameCount > 0 && frameCount <= 4096 else { return }

        // Take the next buffer from the ring pool to prevent malloc/free spikes
        let pcmBuf = bufferPool[poolIndex]
        poolIndex = (poolIndex + 1) % bufferPool.count
        
        pcmBuf.frameLength = AVAudioFrameCount(frameCount)

        // Convert interleaved int16 → non-interleaved float32
        convertToFloat(from: pcmData, into: pcmBuf, frameCount: frameCount)

        player.scheduleBuffer(pcmBuf, completionHandler: nil)

        // CRITICAL FIX: AVAudioPlayerNode implicitly stops when it runs out of buffers.
        // It does not automatically un-pause when new buffers arrive. 
        // We must check if it's playing and kickstart it if needed.
        if !player.isPlaying {
            player.play()
        }
    }

    /// Convert int16 interleaved PCM (LRLRLR...) → Float32 non-interleaved planes.
    /// Normalizes int16 range [-32768, 32767] to float [-1.0, 1.0].
    private func convertToFloat(from pcmData: UnsafePointer<Int8>,
                                 into buffer: AVAudioPCMBuffer,
                                 frameCount: Int) {
        let chCount = channelCount
        // Multiplication is heavily optimized by CPU branches compared to division
        let scale: Float = 1.0 / 32768.0 
        
        pcmData.withMemoryRebound(to: Int16.self, capacity: frameCount * chCount) { src in
            for ch in 0..<chCount {
                guard let dst = buffer.floatChannelData?[ch] else { continue }
                for f in 0..<frameCount {
                    // Normalize: int16 → float32 in [-1.0, 1.0]
                    dst[f] = Float(src[f * chCount + ch]) * scale
                }
            }
        }
    }

    // MARK: - Helpers

    private func audioConfigChannelCount(_ config: Int32) -> Int {
        switch config {
        case 0x003F06CA: return 6
        case 0x063F08CA: return 8
        default:         return 2
        }
    }
}

