// Pull-model audio renderer using Google Oboe.
// Decoder thread → submitSamples() → ring buffer → Oboe callback → HAL

#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <oboe/Oboe.h>
#include "LockFreeRingBuffer.h"

class OboeAudioRenderer : public oboe::AudioStreamDataCallback,
                          public oboe::AudioStreamErrorCallback {
public:
    OboeAudioRenderer() = default;
    ~OboeAudioRenderer() override;

    // Non-copyable
    OboeAudioRenderer(const OboeAudioRenderer&) = delete;
    OboeAudioRenderer& operator=(const OboeAudioRenderer&) = delete;

    int start(int channelCount, int sampleRate, int samplesPerFrame);

    void stop();

    void submitSamples(const int16_t* pcm, int sampleCount);

    int queuedSamples() const;
    int queuedDurationMs() const;
    uint64_t overflowPackets() const;
    uint64_t underrunCallbacks() const;

    // oboe::AudioStreamDataCallback
    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream* stream, void* audioData,
        int32_t numFrames) override;

    // oboe::AudioStreamErrorCallback — auto-restart on disconnect
    void onErrorAfterClose(oboe::AudioStream* stream,
                           oboe::Result error) override;

private:
    void openStreamLocked();

    std::shared_ptr<oboe::AudioStream> mStream;
    LockFreeRingBuffer mRingBuffer;
    mutable std::mutex mStreamMutex;

    int mChannelCount    = 2;
    int mSampleRate      = 48000;
    int mSamplesPerFrame = 240;

    // Track whether we were asked to start (for error recovery restart)
    std::atomic<bool> mStarted{false};
    std::atomic<uint64_t> mOverflowPackets{0};
    std::atomic<uint64_t> mUnderrunCallbacks{0};
};

#ifdef __cplusplus
extern "C" {
#endif

// C-linkage wrappers for use in callbacks.c
void* OboeRenderer_Create();
void OboeRenderer_Destroy(void* renderer);
int OboeRenderer_Start(void* renderer, int channelCount, int sampleRate, int samplesPerFrame);
void OboeRenderer_Stop(void* renderer);
void OboeRenderer_SubmitSamples(void* renderer, const int16_t* pcm, int sampleCount);
int OboeRenderer_GetQueuedSamples(void* renderer);
int OboeRenderer_GetQueuedDurationMs(void* renderer);
uint64_t OboeRenderer_GetOverflowPackets(void* renderer);
uint64_t OboeRenderer_GetUnderrunCallbacks(void* renderer);

#ifdef __cplusplus
}
#endif
