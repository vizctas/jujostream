/**
 * wasapi_renderer.cpp — Real IAudioClient (shared mode, event-driven).
 */
#include "wasapi_renderer.h"
#include "audio_ring_buffer.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <objbase.h>
#include <ksmedia.h>
#include <mmreg.h>
#include <avrt.h>

#include <algorithm>
#include <cstdio>
#include <cstring>

#pragma comment(lib, "avrt.lib")

// Some SDKs forget to declare these when WAVE_FORMAT_EXTENSIBLE is in play.
#ifndef REFTIMES_PER_SEC
#  define REFTIMES_PER_SEC 10000000  // 100ns units -> 1 second
#endif

namespace jujostream {
namespace audio {

namespace {

// Ring buffer sized for ~400ms of worst-case 8ch/48kHz float audio.
// 48000 * 0.4 * 8 = 153600 samples -> rounds to 262144 (power of two).
constexpr std::size_t kRingCapacitySamples = 262144;

// Thread-local COM initialization helper.
struct ScopedCom {
    HRESULT hr;
    ScopedCom() { hr = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED); }
    ~ScopedCom() {
        if (SUCCEEDED(hr)) ::CoUninitialize();
    }
};

// Boost the render thread to "Pro Audio" MMCSS class when available.
struct MmcssTask {
    HANDLE handle = nullptr;
    MmcssTask() {
        DWORD taskIndex = 0;
        handle = ::AvSetMmThreadCharacteristicsW(L"Pro Audio", &taskIndex);
        if (!handle) {
            handle = ::AvSetMmThreadCharacteristicsW(L"Audio", &taskIndex);
        }
    }
    ~MmcssTask() {
        if (handle) ::AvRevertMmThreadCharacteristics(handle);
    }
};

// Safe COM release wrapper.
template <typename T>
inline void safeRelease(T *&p) {
    if (p) {
        p->Release();
        p = nullptr;
    }
}

// Convert a block of interleaved int16 samples into interleaved float32.
// Optionally remixes srcChannels -> dstChannels with a simple downmix/upmix.
// Returns the number of destination samples produced.
std::size_t convertInt16ToFloat(const int16_t *src, std::size_t srcSamples,
                                int srcChannels, int dstChannels,
                                float *dst) {
    if (srcChannels <= 0 || dstChannels <= 0) return 0;
    const float kScale = 1.0f / 32768.0f;
    const std::size_t frames = srcSamples / static_cast<std::size_t>(srcChannels);

    if (srcChannels == dstChannels) {
        for (std::size_t i = 0; i < srcSamples; ++i) {
            dst[i] = static_cast<float>(src[i]) * kScale;
        }
        return srcSamples;
    }

    // Multi-channel -> stereo downmix (keeps FL/FR, mixes everything else
    // into both channels at -3dB). Covers 5.1/7.1 -> stereo which is the
    // common case when the engine default is stereo.
    if (dstChannels == 2 && srcChannels >= 2) {
        constexpr float kMix = 0.707f;  // -3dB
        for (std::size_t f = 0; f < frames; ++f) {
            const int16_t *in = src + f * srcChannels;
            float l = static_cast<float>(in[0]) * kScale;
            float r = static_cast<float>(in[1]) * kScale;
            if (srcChannels >= 3) {  // front center
                const float c = static_cast<float>(in[2]) * kScale * kMix;
                l += c; r += c;
            }
            if (srcChannels >= 5) {  // rear L/R (skip LFE at index 3)
                l += static_cast<float>(in[4]) * kScale * kMix;
                if (srcChannels >= 6) {
                    r += static_cast<float>(in[5]) * kScale * kMix;
                }
            }
            dst[f * 2 + 0] = std::max(-1.0f, std::min(1.0f, l));
            dst[f * 2 + 1] = std::max(-1.0f, std::min(1.0f, r));
        }
        return frames * 2;
    }

    // Stereo -> multi-channel upmix (put L/R in FL/FR, zero the rest).
    if (srcChannels == 2 && dstChannels >= 3) {
        for (std::size_t f = 0; f < frames; ++f) {
            float *out = dst + f * dstChannels;
            std::memset(out, 0, dstChannels * sizeof(float));
            out[0] = static_cast<float>(src[f * 2 + 0]) * kScale;
            out[1] = static_cast<float>(src[f * 2 + 1]) * kScale;
        }
        return frames * dstChannels;
    }

    // Fallback: copy what fits, zero the rest.
    const int common = (srcChannels < dstChannels) ? srcChannels : dstChannels;
    for (std::size_t f = 0; f < frames; ++f) {
        float *out = dst + f * dstChannels;
        std::memset(out, 0, dstChannels * sizeof(float));
        for (int c = 0; c < common; ++c) {
            out[c] = static_cast<float>(src[f * srcChannels + c]) * kScale;
        }
    }
    return frames * dstChannels;
}

// Convert a block of interleaved int16 samples into interleaved int16 samples,
// performing a channel remap (for engines that accept int16 directly).
std::size_t remixInt16(const int16_t *src, std::size_t srcSamples,
                       int srcChannels, int dstChannels, int16_t *dst) {
    if (srcChannels == dstChannels) {
        std::memcpy(dst, src, srcSamples * sizeof(int16_t));
        return srcSamples;
    }
    const std::size_t frames = srcSamples / static_cast<std::size_t>(srcChannels);
    const int common = (srcChannels < dstChannels) ? srcChannels : dstChannels;
    for (std::size_t f = 0; f < frames; ++f) {
        int16_t *out = dst + f * dstChannels;
        std::memset(out, 0, dstChannels * sizeof(int16_t));
        for (int c = 0; c < common; ++c) {
            out[c] = src[f * srcChannels + c];
        }
    }
    return frames * dstChannels;
}

// Detect whether the engine mix format is float32.
bool isFloatFormat(const WAVEFORMATEX *fmt) {
    if (!fmt) return false;
    if (fmt->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return true;
    if (fmt->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
        const auto *ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE *>(fmt);
        return ext->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
    }
    return false;
}

}  // namespace

// ---------------------------------------------------------------------------
// Singleton
// ---------------------------------------------------------------------------

WasapiRenderer &WasapiRenderer::instance() {
    static WasapiRenderer inst;
    return inst;
}

WasapiRenderer::~WasapiRenderer() {
    shutdown();
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

bool WasapiRenderer::initialize(int channels, int sampleRate, int samplesPerFrame) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (state_.load() != State::Idle) {
        fprintf(stderr, "WasapiRenderer: already initialized\n");
        return true;
    }

    srcChannels_   = channels;
    srcSampleRate_ = sampleRate;

    if (!ring_) {
        ring_ = std::make_unique<AudioRingBuffer>(kRingCapacitySamples);
    } else {
        ring_->reset();
    }
    (void)samplesPerFrame;  // reserved for alignment tuning

    // Device acquisition runs on the render thread. We just flag state and
    // let the thread come up.
    state_.store(State::Initialized);
    needReinit_.store(true);

    if (!renderThread_.joinable()) {
        renderThread_ = std::thread(&WasapiRenderer::renderLoop, this);
    }
    return true;
}

void WasapiRenderer::start() {
    State expected = State::Initialized;
    state_.compare_exchange_strong(expected, State::Running);
}

void WasapiRenderer::stop() {
    // Keep resources warm — the stream may restart shortly. Move back to
    // Initialized so the render thread drains and sleeps.
    State cur = state_.load();
    if (cur == State::Running) {
        state_.compare_exchange_strong(cur, State::Initialized);
    }
    if (ring_) ring_->reset();
}

void WasapiRenderer::shutdown() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        state_.store(State::Stopping);
    }
    if (audioEvent_) {
        ::SetEvent(static_cast<HANDLE>(audioEvent_));  // wake the thread
    }
    if (renderThread_.joinable()) {
        renderThread_.join();
    }

    std::lock_guard<std::mutex> lock(mutex_);
    releaseDevice();
    ring_.reset();
    state_.store(State::Idle);
}

void WasapiRenderer::submitPcm(const int16_t *data, int sampleCount) {
    if (!data || sampleCount <= 0) return;
    if (state_.load() == State::Idle || !ring_) return;

    // Worst case: every src sample produces one dst sample (same channel count).
    // Buffer sized generously; we allocate on stack for small bursts.
    static constexpr std::size_t kScratchSamples = 8192;
    float scratch[kScratchSamples];

    const int dstCh = engineChannels_ > 0 ? engineChannels_ : srcChannels_;
    std::size_t remaining = static_cast<std::size_t>(sampleCount);
    const int16_t *srcPtr = data;

    while (remaining > 0) {
        // Process frame-aligned chunks.
        const std::size_t srcFramesBudget =
            kScratchSamples / static_cast<std::size_t>(std::max(dstCh, 1));
        const std::size_t srcSamplesPerFrame = static_cast<std::size_t>(srcChannels_);
        const std::size_t framesAvailable = remaining / srcSamplesPerFrame;
        if (framesAvailable == 0) break;
        const std::size_t framesThisPass = std::min(framesAvailable, srcFramesBudget);
        const std::size_t srcSamples     = framesThisPass * srcSamplesPerFrame;

        const std::size_t produced = convertInt16ToFloat(
            srcPtr, srcSamples, srcChannels_, dstCh, scratch);

        ring_->write(scratch, produced);

        srcPtr    += srcSamples;
        remaining -= srcSamples;
    }
}

WasapiRenderer::Stats WasapiRenderer::stats() const {
    Stats s{};
    if (ring_) {
        s.droppedSamples = ring_->droppedSamples();
        s.underruns      = ring_->underruns();
    }
    s.reinitCount = reinitCount_.load(std::memory_order_relaxed);
    s.channels    = engineChannels_;
    s.sampleRate  = engineSampleRate_;
    return s;
}

// ---------------------------------------------------------------------------
// Device lifecycle
// ---------------------------------------------------------------------------

bool WasapiRenderer::acquireDevice() {
    releaseDevice();

    HRESULT hr = ::CoCreateInstance(
        __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void **>(&enumerator_));
    if (FAILED(hr)) {
        fprintf(stderr, "WasapiRenderer: CoCreateInstance enumerator hr=0x%08lX\n", hr);
        return false;
    }

    hr = enumerator_->GetDefaultAudioEndpoint(eRender, eConsole, &device_);
    if (FAILED(hr)) {
        fprintf(stderr, "WasapiRenderer: GetDefaultAudioEndpoint hr=0x%08lX\n", hr);
        return false;
    }

    hr = device_->Activate(
        __uuidof(IAudioClient), CLSCTX_ALL, nullptr,
        reinterpret_cast<void **>(&audioClient_));
    if (FAILED(hr)) {
        fprintf(stderr, "WasapiRenderer: Activate IAudioClient hr=0x%08lX\n", hr);
        return false;
    }

    // Always match the engine mix format — avoids format conversion errors
    // for exotic devices (Dolby Atmos endpoints, HDMI receivers, etc.).
    hr = audioClient_->GetMixFormat(&engineFormat_);
    if (FAILED(hr) || !engineFormat_) {
        fprintf(stderr, "WasapiRenderer: GetMixFormat hr=0x%08lX\n", hr);
        return false;
    }

    engineChannels_   = engineFormat_->nChannels;
    engineSampleRate_ = static_cast<int>(engineFormat_->nSamplesPerSec);

    // ~30ms buffer — good tradeoff between latency and dropout resilience.
    const REFERENCE_TIME requestedDuration = 30 * 10000;  // 30ms in 100ns units

    hr = audioClient_->Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
            AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
        requestedDuration, 0, engineFormat_, nullptr);
    if (hr == AUDCLNT_E_BUFFER_SIZE_NOT_ALIGNED) {
        UINT32 frames = 0;
        if (SUCCEEDED(audioClient_->GetBufferSize(&frames)) && frames > 0) {
            const REFERENCE_TIME aligned =
                static_cast<REFERENCE_TIME>(
                    static_cast<double>(REFTIMES_PER_SEC) * frames /
                    engineFormat_->nSamplesPerSec + 0.5);
            hr = audioClient_->Initialize(
                AUDCLNT_SHAREMODE_SHARED,
                AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
                    AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                    AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                aligned, 0, engineFormat_, nullptr);
        }
    }
    if (FAILED(hr)) {
        fprintf(stderr, "WasapiRenderer: IAudioClient::Initialize hr=0x%08lX\n", hr);
        return false;
    }

    hr = audioClient_->GetBufferSize(&bufferFrames_);
    if (FAILED(hr)) {
        fprintf(stderr, "WasapiRenderer: GetBufferSize hr=0x%08lX\n", hr);
        return false;
    }

    audioEvent_ = ::CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!audioEvent_) {
        fprintf(stderr, "WasapiRenderer: CreateEvent failed\n");
        return false;
    }
    hr = audioClient_->SetEventHandle(static_cast<HANDLE>(audioEvent_));
    if (FAILED(hr)) {
        fprintf(stderr, "WasapiRenderer: SetEventHandle hr=0x%08lX\n", hr);
        return false;
    }

    hr = audioClient_->GetService(
        __uuidof(IAudioRenderClient),
        reinterpret_cast<void **>(&renderClient_));
    if (FAILED(hr)) {
        fprintf(stderr, "WasapiRenderer: GetService(IAudioRenderClient) hr=0x%08lX\n", hr);
        return false;
    }

    // Prime with silence so the first event arrives immediately.
    BYTE *prime = nullptr;
    if (SUCCEEDED(renderClient_->GetBuffer(bufferFrames_, &prime)) && prime) {
        std::memset(prime, 0, bufferFrames_ * engineFormat_->nBlockAlign);
        renderClient_->ReleaseBuffer(bufferFrames_, AUDCLNT_BUFFERFLAGS_SILENT);
    }

    hr = audioClient_->Start();
    if (FAILED(hr)) {
        fprintf(stderr, "WasapiRenderer: IAudioClient::Start hr=0x%08lX\n", hr);
        return false;
    }

    fprintf(stderr,
            "WasapiRenderer: endpoint opened — %d ch, %d Hz, %u buffer frames, %s\n",
            engineChannels_, engineSampleRate_, bufferFrames_,
            isFloatFormat(engineFormat_) ? "float" : "int");

    return true;
}

void WasapiRenderer::releaseDevice() {
    if (audioClient_) {
        audioClient_->Stop();
    }
    safeRelease(renderClient_);
    safeRelease(audioClient_);
    safeRelease(device_);
    safeRelease(enumerator_);
    if (engineFormat_) {
        ::CoTaskMemFree(engineFormat_);
        engineFormat_ = nullptr;
    }
    if (audioEvent_) {
        ::CloseHandle(static_cast<HANDLE>(audioEvent_));
        audioEvent_ = nullptr;
    }
    bufferFrames_   = 0;
    engineChannels_ = 0;
}

// ---------------------------------------------------------------------------
// Render thread
// ---------------------------------------------------------------------------

void WasapiRenderer::renderLoop() {
    ScopedCom com;
    MmcssTask mmcss;

    // Scratch conversion buffer, grown on demand. Sized for one WASAPI period.
    std::unique_ptr<float[]>   floatScratch;
    std::unique_ptr<int16_t[]> intScratch;
    std::size_t scratchFrames = 0;

    while (true) {
        const State st = state_.load(std::memory_order_acquire);
        if (st == State::Stopping) break;

        if (needReinit_.exchange(false)) {
            std::lock_guard<std::mutex> lock(mutex_);
            if (!acquireDevice()) {
                // Retry after a short nap — avoid hot-loop if audio is down.
                ::Sleep(200);
                needReinit_.store(true);
                continue;
            }
            reinitCount_.fetch_add(1, std::memory_order_relaxed);
            scratchFrames = 0;  // force re-alloc with new block align
        }

        if (!audioEvent_ || !audioClient_ || !renderClient_) {
            ::Sleep(10);
            continue;
        }

        // Wait for WASAPI to ask for more samples (or for a shutdown nudge).
        const DWORD waitRes = ::WaitForSingleObject(
            static_cast<HANDLE>(audioEvent_), 200);
        if (state_.load(std::memory_order_acquire) == State::Stopping) break;
        if (waitRes == WAIT_TIMEOUT) continue;

        UINT32 padding = 0;
        HRESULT hr = audioClient_->GetCurrentPadding(&padding);
        if (hr == AUDCLNT_E_DEVICE_INVALIDATED) {
            fprintf(stderr, "WasapiRenderer: device invalidated, reacquiring\n");
            needReinit_.store(true);
            continue;
        }
        if (FAILED(hr)) continue;

        const UINT32 framesAvail = bufferFrames_ - padding;
        if (framesAvail == 0) continue;

        BYTE *buf = nullptr;
        hr = renderClient_->GetBuffer(framesAvail, &buf);
        if (hr == AUDCLNT_E_DEVICE_INVALIDATED) {
            needReinit_.store(true);
            continue;
        }
        if (FAILED(hr) || !buf) continue;

        const int ch = engineChannels_;
        const std::size_t samplesNeeded =
            static_cast<std::size_t>(framesAvail) * static_cast<std::size_t>(ch);

        // Only pump audio when running — during Idle/Initialized fill silence.
        const bool running = state_.load() == State::Running;

        if (running && isFloatFormat(engineFormat_)) {
            if (!floatScratch || scratchFrames < framesAvail) {
                floatScratch.reset(new float[samplesNeeded]);
                scratchFrames = framesAvail;
            }
            ring_->read(floatScratch.get(), samplesNeeded, /*padWithSilence=*/true);
            std::memcpy(buf, floatScratch.get(), samplesNeeded * sizeof(float));
            renderClient_->ReleaseBuffer(framesAvail, 0);
        } else if (running) {
            // Int16 (or other PCM) engine path — convert float ring -> int16.
            if (!floatScratch || scratchFrames < framesAvail) {
                floatScratch.reset(new float[samplesNeeded]);
                scratchFrames = framesAvail;
            }
            ring_->read(floatScratch.get(), samplesNeeded, /*padWithSilence=*/true);

            const int bits = engineFormat_->wBitsPerSample;
            if (bits == 16) {
                int16_t *out = reinterpret_cast<int16_t *>(buf);
                for (std::size_t i = 0; i < samplesNeeded; ++i) {
                    float v = floatScratch[i];
                    if (v > 1.0f) v = 1.0f; else if (v < -1.0f) v = -1.0f;
                    out[i] = static_cast<int16_t>(v * 32767.0f);
                }
            } else {
                // Unknown bit depth — silence is safer than garbage.
                std::memset(buf, 0,
                    static_cast<size_t>(framesAvail) * engineFormat_->nBlockAlign);
            }
            renderClient_->ReleaseBuffer(framesAvail, 0);
        } else {
            renderClient_->ReleaseBuffer(framesAvail, AUDCLNT_BUFFERFLAGS_SILENT);
        }
    }

    std::lock_guard<std::mutex> lock(mutex_);
    releaseDevice();
    (void)intScratch;  // reserved for future int-only fast path
}

}  // namespace audio
}  // namespace jujostream
