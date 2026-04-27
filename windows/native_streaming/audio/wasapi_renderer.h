/**
 * wasapi_renderer.h — Event-driven WASAPI PCM renderer (shared mode).
 *
 * Responsibilities:
 *   - Acquire default render endpoint via IMMDeviceEnumerator.
 *   - Initialize IAudioClient with a WASAPI-supported source or endpoint format.
 *   - Spin a render thread that waits on the audio event handle and pumps
 *     float samples from `AudioRingBuffer` into `IAudioRenderClient`.
 *   - Convert int16 input samples to float32 on the producer side.
 *   - Transparently recover from `AUDCLNT_E_DEVICE_INVALIDATED`
 *     (default endpoint change, disconnect, sample rate change).
 *
 * Thread model:
 *   - `submitPcm` is called from the moonlight callback thread.
 *   - The render thread is owned by this class and outlives any single stream
 *     connection (it parks on an event when the client is stopped).
 *
 * This is a process-wide singleton; lifetime mirrors StreamingBridgeWin.
 */
#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <thread>

struct IAudioClient;
struct IAudioRenderClient;
struct IMMDeviceEnumerator;
struct IMMDevice;
typedef struct tWAVEFORMATEX WAVEFORMATEX;

namespace jujostream {
namespace audio {

class AudioRingBuffer;

class WasapiRenderer {
public:
    static WasapiRenderer &instance();

    // Called from moonlight audio-init callback. `channels` comes from the
    // Opus config; `samplesPerFrame` is the per-channel frame size.
    bool initialize(int channels, int sampleRate, int samplesPerFrame);

    void start();
    void stop();
    void shutdown();

    // Producer: int16 interleaved PCM from the Opus decoder.
    // `sampleCount` is total samples across all channels.
    void submitPcm(const int16_t *data, int sampleCount);

    bool isInitialized() const { return state_.load() != State::Idle; }

    // Telemetry snapshot (approximate — atomics, no lock).
    struct Stats {
        uint64_t droppedSamples;
        uint64_t submittedSamples;
        uint64_t underruns;
        uint64_t reinitCount;
        int      channels;
        int      sampleRate;
    };
    Stats stats() const;

private:
    WasapiRenderer() = default;
    ~WasapiRenderer();

    WasapiRenderer(const WasapiRenderer &)            = delete;
    WasapiRenderer &operator=(const WasapiRenderer &) = delete;

    enum class State { Idle, Initialized, Running, Stopping };

    // Acquire/release COM state for the audio client. Called on the render
    // thread (and on initialize for the first activation).
    bool acquireDevice();
    void releaseDevice();

    // Render thread entry point.
    void renderLoop();

    // --- State protected by `mutex_` during setup / teardown ---
    mutable std::mutex            mutex_;
    IMMDeviceEnumerator          *enumerator_   = nullptr;
    IMMDevice                    *device_       = nullptr;
    IAudioClient                 *audioClient_  = nullptr;
    IAudioRenderClient           *renderClient_ = nullptr;
    WAVEFORMATEX                 *engineFormat_ = nullptr;  // CoTaskMemFree'd
    void                         *audioEvent_   = nullptr;  // HANDLE (event)
    uint32_t                      bufferFrames_ = 0;
    int                           engineChannels_   = 0;
    int                           engineSampleRate_ = 0;

    // Source (stream) format — what moonlight gives us.
    int srcChannels_    = 0;
    int srcSampleRate_  = 0;

    std::unique_ptr<AudioRingBuffer> ring_;
    std::thread                      renderThread_;
    std::atomic<State>               state_{State::Idle};
    std::atomic<bool>                needReinit_{false};
    std::atomic<uint64_t>            reinitCount_{0};
    std::atomic<uint64_t>            submittedSamples_{0};
};

}  // namespace audio
}  // namespace jujostream
