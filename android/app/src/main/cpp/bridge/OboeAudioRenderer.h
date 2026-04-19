// Pull-model audio renderer using Google Oboe.
// Decoder thread → submitSamples() → ring buffer → Oboe callback → HAL

#pragma once

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

    // oboe::AudioStreamDataCallback
    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream* stream, void* audioData,
        int32_t numFrames) override;

    // oboe::AudioStreamErrorCallback — auto-restart on disconnect
    void onErrorAfterClose(oboe::AudioStream* stream,
                           oboe::Result error) override;

private:
    void openStream();

    std::shared_ptr<oboe::AudioStream> mStream;
    LockFreeRingBuffer mRingBuffer;

    int mChannelCount    = 2;
    int mSampleRate      = 48000;
    int mSamplesPerFrame = 240;

    // Track whether we were asked to start (for error recovery restart)
    bool mStarted = false;
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

#ifdef __cplusplus
}
#endif
