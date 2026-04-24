// Pull-model audio renderer using Google Oboe.

#include "OboeAudioRenderer.h"
#include <android/log.h>
#include <cstring>
#include <sys/system_properties.h>

#define LOG_TAG "OboeAudioRenderer"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

OboeAudioRenderer::~OboeAudioRenderer() {
    stop();
}

int OboeAudioRenderer::start(int channelCount, int sampleRate, int samplesPerFrame) {
    mChannelCount    = channelCount;
    mSampleRate      = sampleRate;
    mSamplesPerFrame = samplesPerFrame;

    // Ring buffer: ~100 ms of audio (20 frames of 5 ms each)
    int ringCapacity = channelCount * samplesPerFrame * 20;
    mRingBuffer.resize(ringCapacity);

    openStream();

    if (!mStream) {
        LOGE("Failed to open Oboe stream");
        return -1;
    }

    mStarted = true;
    LOGI("Oboe started: ch=%d rate=%d spf=%d ringCap=%d sharing=%s perf=%s",
         channelCount, sampleRate, samplesPerFrame, ringCapacity,
         mStream->getSharingMode() == oboe::SharingMode::Exclusive ? "Exclusive" : "Shared",
         mStream->getPerformanceMode() == oboe::PerformanceMode::LowLatency ? "LowLatency" : "None");

    return 0;
}

void OboeAudioRenderer::openStream() {
    bool amlogic = false;
    char hardware[PROP_VALUE_MAX] = {0};
    if (__system_property_get("ro.hardware", hardware) > 0) {
        if (strstr(hardware, "amlogic") != nullptr || strstr(hardware, "amls") != nullptr) {
            amlogic = true;
        }
    }

    oboe::AudioStreamBuilder builder;
    builder.setDirection(oboe::Direction::Output)
           ->setPerformanceMode(amlogic ? oboe::PerformanceMode::None : oboe::PerformanceMode::LowLatency)
           ->setSharingMode(oboe::SharingMode::Shared)
           ->setFormat(oboe::AudioFormat::I16)
           ->setChannelCount(mChannelCount)
           ->setSampleRate(mSampleRate)
           ->setDataCallback(this)
           ->setErrorCallback(this)
           ->setUsage(oboe::Usage::Media)
           ->setContentType(oboe::ContentType::Movie)
           ->setSpatializationBehavior(oboe::SpatializationBehavior::Auto);

    auto result = builder.openStream(mStream);
    if (result != oboe::Result::OK) {
        LOGE("openStream failed: %s", oboe::convertToText(result));
        mStream = nullptr;
        return;
    }

    result = mStream->requestStart();
    if (result != oboe::Result::OK) {
        LOGE("requestStart failed: %s", oboe::convertToText(result));
        mStream->close();
        mStream = nullptr;
    }
}

void OboeAudioRenderer::stop() {
    mStarted = false;
    if (mStream) {
        mStream->requestStop();
        mStream->close();
        mStream = nullptr;
    }
    mRingBuffer.reset();
    LOGI("Oboe stopped");
}

void OboeAudioRenderer::submitSamples(const int16_t* pcm, int sampleCount) {
    int written = mRingBuffer.write(pcm, sampleCount);
    if (written < sampleCount) {
        // Ring buffer overflow — drop oldest by advancing read, then retry
        // This is better than dropping the newest packet
        LOGW("Ring buffer overflow: wanted %d, wrote %d", sampleCount, written);
    }
}

oboe::DataCallbackResult OboeAudioRenderer::onAudioReady(
        oboe::AudioStream* stream, void* audioData, int32_t numFrames) {
    auto* dst = static_cast<int16_t*>(audioData);
    int totalSamples = numFrames * stream->getChannelCount();
    int read = mRingBuffer.read(dst, totalSamples);

    if (read < totalSamples) {
        // Underrun: zero-fill remainder (silence)
        std::memset(dst + read, 0,
                    (totalSamples - read) * sizeof(int16_t));
    }

    return oboe::DataCallbackResult::Continue;
}

void OboeAudioRenderer::onErrorAfterClose(oboe::AudioStream* stream,
                                           oboe::Result error) {
    LOGW("Oboe stream error: %s — attempting restart", oboe::convertToText(error));
    if (mStarted) {
        mRingBuffer.reset();
        openStream();
        if (mStream) {
            LOGI("Oboe stream restarted successfully");
        } else {
            LOGE("Oboe stream restart failed");
        }
    }
}

// ============================================================================
// C-ABI wrappers for callbacks.c
// ============================================================================

extern "C" {

void* OboeRenderer_Create() {
    return new OboeAudioRenderer();
}

void OboeRenderer_Destroy(void* renderer) {
    if (renderer) {
        delete static_cast<OboeAudioRenderer*>(renderer);
    }
}

int OboeRenderer_Start(void* renderer, int channelCount, int sampleRate, int samplesPerFrame) {
    if (!renderer) return -1;
    return static_cast<OboeAudioRenderer*>(renderer)->start(channelCount, sampleRate, samplesPerFrame);
}

void OboeRenderer_Stop(void* renderer) {
    if (!renderer) return;
    static_cast<OboeAudioRenderer*>(renderer)->stop();
}

void OboeRenderer_SubmitSamples(void* renderer, const int16_t* pcm, int sampleCount) {
    if (!renderer) return;
    static_cast<OboeAudioRenderer*>(renderer)->submitSamples(pcm, sampleCount);
}

} // extern "C"
