// Pull-model audio renderer using Google Oboe.

#include "OboeAudioRenderer.h"
#include <android/log.h>
#include <cstring>
#include <sys/system_properties.h>

#define LOG_TAG "OboeAudioRenderer"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {
std::atomic<int> gQueuedDurationMs{0};
std::atomic<uint64_t> gOverflowPackets{0};
std::atomic<uint64_t> gUnderrunCallbacks{0};
}

OboeAudioRenderer::~OboeAudioRenderer() {
    stop();
}

int OboeAudioRenderer::start(int channelCount, int sampleRate, int samplesPerFrame) {
    std::lock_guard<std::mutex> lock(mStreamMutex);
    if (mStarted.load(std::memory_order_acquire)) return 0;

    mChannelCount    = channelCount;
    mSampleRate      = sampleRate;
    mSamplesPerFrame = samplesPerFrame;

    // Bound queued PCM to roughly 40 ms. Extra packets are dropped atomically;
    // latency can never grow into the hundreds of milliseconds.
    int ringCapacity = channelCount * samplesPerFrame * 8;
    mRingBuffer.resize(ringCapacity);
    mOverflowPackets.store(0, std::memory_order_relaxed);
    mUnderrunCallbacks.store(0, std::memory_order_relaxed);
    gQueuedDurationMs.store(0, std::memory_order_relaxed);
    gOverflowPackets.store(0, std::memory_order_relaxed);
    gUnderrunCallbacks.store(0, std::memory_order_relaxed);

    mStarted.store(true, std::memory_order_release);
    openStreamLocked();

    if (!mStream) {
        mStarted.store(false, std::memory_order_release);
        LOGE("Failed to open Oboe stream");
        return -1;
    }

    LOGI("Oboe started: ch=%d rate=%d spf=%d ringCap=%d sharing=%s perf=%s",
         channelCount, sampleRate, samplesPerFrame, ringCapacity,
         mStream->getSharingMode() == oboe::SharingMode::Exclusive ? "Exclusive" : "Shared",
         mStream->getPerformanceMode() == oboe::PerformanceMode::LowLatency ? "LowLatency" : "None");

    return 0;
}

void OboeAudioRenderer::openStreamLocked() {
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
    std::lock_guard<std::mutex> lock(mStreamMutex);
    const bool wasStarted = mStarted.exchange(false, std::memory_order_acq_rel);
    if (mStream) {
        mStream->requestStop();
        mStream->close();
        mStream = nullptr;
    }
    const int queuedBeforeReset = mRingBuffer.availableToRead();
    mRingBuffer.reset();
    gQueuedDurationMs.store(0, std::memory_order_relaxed);
    if (wasStarted) {
        LOGI("Oboe stopped: queued=%d overflowPackets=%llu underrunCallbacks=%llu",
             queuedBeforeReset,
             static_cast<unsigned long long>(overflowPackets()),
             static_cast<unsigned long long>(underrunCallbacks()));
    }
}

void OboeAudioRenderer::submitSamples(const int16_t* pcm, int sampleCount) {
    int written = mRingBuffer.write(pcm, sampleCount);
    gQueuedDurationMs.store(queuedDurationMs(), std::memory_order_relaxed);
    if (written < sampleCount) {
        const uint64_t count = mOverflowPackets.fetch_add(1, std::memory_order_relaxed) + 1;
        gOverflowPackets.store(count, std::memory_order_relaxed);
        if ((count & (count - 1)) == 0) {
            LOGW("Ring overflow: dropped packet samples=%d queued=%d count=%llu",
                 sampleCount, mRingBuffer.availableToRead(),
                 static_cast<unsigned long long>(count));
        }
    }
}

oboe::DataCallbackResult OboeAudioRenderer::onAudioReady(
        oboe::AudioStream* stream, void* audioData, int32_t numFrames) {
    auto* dst = static_cast<int16_t*>(audioData);
    int totalSamples = numFrames * stream->getChannelCount();
    int read = mRingBuffer.read(dst, totalSamples);
    gQueuedDurationMs.store(queuedDurationMs(), std::memory_order_relaxed);

    if (read < totalSamples) {
        const uint64_t count = mUnderrunCallbacks.fetch_add(1, std::memory_order_relaxed) + 1;
        gUnderrunCallbacks.store(count, std::memory_order_relaxed);
        // Underrun: zero-fill remainder (silence)
        std::memset(dst + read, 0,
                    (totalSamples - read) * sizeof(int16_t));
    }

    return oboe::DataCallbackResult::Continue;
}

void OboeAudioRenderer::onErrorAfterClose(oboe::AudioStream* stream,
                                           oboe::Result error) {
    LOGW("Oboe stream error: %s — attempting restart", oboe::convertToText(error));
    std::lock_guard<std::mutex> lock(mStreamMutex);
    if (!mStarted.load(std::memory_order_acquire)) return;
    if (mStream && mStream.get() != stream) return;

    mStream.reset();
    mRingBuffer.reset();
    openStreamLocked();
    if (mStream) {
        LOGI("Oboe stream restarted successfully");
    } else {
        LOGE("Oboe stream restart failed");
    }
}

int OboeAudioRenderer::queuedSamples() const {
    return mRingBuffer.availableToRead();
}

int OboeAudioRenderer::queuedDurationMs() const {
    const int samplesPerSecond = mChannelCount * mSampleRate;
    if (samplesPerSecond <= 0) return 0;
    return static_cast<int>((static_cast<int64_t>(queuedSamples()) * 1000) / samplesPerSecond);
}

uint64_t OboeAudioRenderer::overflowPackets() const {
    return mOverflowPackets.load(std::memory_order_relaxed);
}

uint64_t OboeAudioRenderer::underrunCallbacks() const {
    return mUnderrunCallbacks.load(std::memory_order_relaxed);
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

int OboeRenderer_GetQueuedSamples(void* renderer) {
    if (!renderer) return 0;
    return static_cast<OboeAudioRenderer*>(renderer)->queuedSamples();
}

int OboeRenderer_GetQueuedDurationMs(void* renderer) {
    (void)renderer;
    return gQueuedDurationMs.load(std::memory_order_relaxed);
}

uint64_t OboeRenderer_GetOverflowPackets(void* renderer) {
    (void)renderer;
    return gOverflowPackets.load(std::memory_order_relaxed);
}

uint64_t OboeRenderer_GetUnderrunCallbacks(void* renderer) {
    (void)renderer;
    return gUnderrunCallbacks.load(std::memory_order_relaxed);
}

} // extern "C"
