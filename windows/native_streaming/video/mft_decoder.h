/**
 * mft_decoder.h
 *
 * Media Foundation Transform (MFT) hardware video decoder.
 * Supports H.264, H.265/HEVC, and AV1 (Win10 21H2+).
 * Decodes to ID3D11Texture2D via D3D11 device manager — zero GPU→CPU copy.
 *
 * Thread safety: submitFrame() is called from the moonlight network thread.
 * The MFT async output loop runs on its own thread. TextureBridge is notified
 * from the decode thread via the onFrameDecoded callback.
 */
#pragma once

#include <cstdint>
#include <functional>
#include <atomic>
#include <mutex>
#include <thread>
#include <vector>

#include <d3d11.h>
#include <mfidl.h>
#include <mftransform.h>
#include <wrl/client.h>

namespace jujostream {
namespace video {

using Microsoft::WRL::ComPtr;

// videoFormat values from moonlight-common-c (Limelight.h)
static constexpr int kVideoFormatH264  = 0x0001;
static constexpr int kVideoFormatH265  = 0x0100;
static constexpr int kVideoFormatH265Hdr = 0x0200;
static constexpr int kVideoFormatAV1   = 0x1000;
static constexpr int kVideoFormatAV1Hdr= 0x2000;

// DR return codes (Limelight.h)
static constexpr int DR_OK           = 0;
static constexpr int DR_NEED_IDR     = -1;

struct DecodedFrame {
    ComPtr<ID3D11Texture2D> texture;
    UINT                    subresource;  // array index for MFT texture arrays
};

class MftDecoder {
public:
    static MftDecoder &instance();

    using FrameCallback = std::function<void(const DecodedFrame &)>;

    /**
     * Initialize MFT hardware decoder for the given format/resolution.
     * @param videoFormat  moonlight format bitmask (kVideoFormatH264 etc.)
     * @param width/height stream resolution
     * @param fps          stream frame rate (used for MFT MediaType)
     * @param onFrame      called on every successfully decoded frame
     */
    bool initialize(int videoFormat, int width, int height, int fps,
                    FrameCallback onFrame);
    void shutdown();

    /**
     * Submit one Annex-B NAL blob for decoding.
     * Returns DR_OK or DR_NEED_IDR.
     * Called from moonlight callback thread — must not block.
     */
    int submitFrame(const uint8_t *data, int length, int frameType,
                    int frameNumber, int64_t receiveTimeMs);

    bool isInitialized() const { return initialized_; }

    // Stats (atomic reads, safe from any thread)
    int      fps()           const { return fps_reported_.load(); }
    double   avgDecodeMsEma() const { return decode_ema_ms_; }  // read on stats thread; approximate
    uint64_t framesDecoded() const { return frames_decoded_.load(); }
    uint64_t framesDropped() const { return frames_dropped_.load(); }

private:
    MftDecoder() = default;
    ~MftDecoder() { shutdown(); }

    bool createTransform(const GUID &inputSubtype);
    bool configureInputType(const GUID &inputSubtype, int width, int height, int fps);
    bool configureOutputType();
    bool setD3DManager();
    void drainLoop();  // runs on drain_thread_

    ComPtr<IMFTransform>   transform_;
    ComPtr<IMFMediaEventGenerator> event_gen_;  // for async MFT

    FrameCallback  on_frame_;
    std::thread    drain_thread_;
    std::atomic<bool> drain_running_{false};

    int   width_      = 0;
    int   height_     = 0;
    int   fps_        = 60;
    bool  isHevc_     = false;
    bool  isAV1_      = false;
    bool  initialized_ = false;

    // Codec config (SPS/PPS/VPS bytes, stored for IDR re-injection)
    std::vector<uint8_t> sps_bytes_;
    std::vector<uint8_t> pps_bytes_;
    std::vector<uint8_t> vps_bytes_;
    std::mutex           config_mutex_;

    // Stats
    std::atomic<int>      fps_reported_{0};
    std::atomic<uint64_t> frames_decoded_{0};
    std::atomic<uint64_t> frames_dropped_{0};
    double                decode_ema_ms_ = 0.0;
    LARGE_INTEGER         perf_freq_{};
};

}  // namespace video
}  // namespace jujostream
