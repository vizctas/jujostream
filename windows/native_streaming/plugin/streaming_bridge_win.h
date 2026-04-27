/**
 * streaming_bridge_win.h
 *
 * Singleton orchestrator: owns VideoDecoder, AudioRenderer, C callbacks.
 * Mirrors StreamingBridge.swift (macOS).
 */
#pragma once

#include <flutter/texture_registrar.h>
#include <cstdint>
#include <atomic>
#include <string>
#include <thread>

namespace jujostream {

class StreamingBridgeWin {
public:
    static StreamingBridgeWin &instance();

    void initialize(flutter::TextureRegistrar *texture_registrar);

    int64_t getTextureId() const;

    // Mark stream lifecycle state
    void setStreaming(bool v) { streaming_.store(v); }
    bool isStreaming() const  { return streaming_.load(); }

    // Register C bridge callbacks (called once at init)
    void registerCBridgeCallbacks();

    // Called when video pipeline is set up (onVideoSetup)
    bool initVideo(int videoFormat, int width, int height, int fps);

    // Stats snapshot (called from stats timer on plugin thread)
    struct Stats {
        int      fps          = 0;
        int      decodeTimeMs = 0;
        uint64_t framesDecoded= 0;
        uint64_t framesDropped= 0;
        std::string codec;
        bool     isSoftwareDecoder = false;
        uint64_t packetsSubmitted = 0;
        uint64_t bytesSubmitted = 0;
        uint64_t inputsAccepted = 0;
        uint64_t idrFrames = 0;
        uint64_t outputSamples = 0;
        uint64_t dxgiFrames = 0;
        uint64_t dxgiMisses = 0;
        uint64_t processInputFailures = 0;
        uint64_t processOutputFailures = 0;
        uint64_t streamChanges = 0;
        uint64_t textureBlits = 0;
        uint64_t textureBlitFailures = 0;
        uint64_t textureFrameNotifications = 0;
        uint64_t textureDescriptorCallbacks = 0;
        uint64_t textureNullDescriptorCallbacks = 0;
    };
    Stats getVideoStats() const;
    void startStatsEmitter();
    void stopStatsEmitter();

private:
    StreamingBridgeWin() = default;
    void statsLoop();

    flutter::TextureRegistrar *texture_registrar_ = nullptr;
    std::atomic<bool>          streaming_{false};
    std::atomic<bool>          stats_running_{false};
    std::thread                stats_thread_;
};

}  // namespace jujostream
