/**
 * mft_decoder.cpp
 *
 * Media Foundation Transform hardware video decoder.
 * H.264 / H.265(HEVC) / AV1 → ID3D11Texture2D (GPU memory, NV12/P010).
 *
 * Decode pipeline:
 *   submitFrame() [moonlight thread]
 *     → NaluParser::parse() → store SPS/PPS/VPS
 *     → IMFSample(Annex-B wrapped in IMFMediaBuffer) → ProcessInput
 *   drainLoop() [dedicated decode thread]
 *     → ProcessOutput → ID3D11Texture2D → onFrame_ callback → TextureBridge
 */
#include "mft_decoder.h"
#include "nalu_parser.h"
#include "d3d11_device.h"

#include <initguid.h>
#include <mfapi.h>
#include <mferror.h>
#include <codecapi.h>
#include <cstdio>
#include <cstring>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfuuid.lib")

// AV1 GUID — available Win10 20H1+ but MFT hardware decoder from 21H2+
DEFINE_GUID(MFVideoFormat_AV1_LOCAL,
    0x31305641, 0x0000, 0x0010, 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71);

namespace jujostream {
namespace video {

MftDecoder &MftDecoder::instance() {
    static MftDecoder inst;
    return inst;
}

// -------------------------------------------------------------------
// initialize
// -------------------------------------------------------------------
bool MftDecoder::initialize(int videoFormat, int width, int height, int fps,
                             FrameCallback onFrame) {
    if (initialized_) shutdown();

    width_   = width;
    height_  = height;
    fps_     = fps;
    on_frame_ = std::move(onFrame);
    isHevc_  = (videoFormat & (kVideoFormatH265 | kVideoFormatH265Hdr)) != 0;
    isAV1_   = (videoFormat & (kVideoFormatAV1  | kVideoFormatAV1Hdr))  != 0;

    QueryPerformanceFrequency(&perf_freq_);

    if (!D3D11Device::instance().isInitialized()) {
        if (!D3D11Device::instance().initialize()) {
            fprintf(stderr, "MftDecoder: D3D11Device init failed\n");
            return false;
        }
    }

    if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET))) {
        fprintf(stderr, "MftDecoder: MFStartup failed\n");
        return false;
    }

    GUID inputSubtype = MFVideoFormat_H264;
    if (isHevc_)      inputSubtype = MFVideoFormat_HEVC;
    else if (isAV1_)  inputSubtype = MFVideoFormat_AV1_LOCAL;

    if (!createTransform(inputSubtype)) {
        fprintf(stderr, "MftDecoder: no hardware MFT found for codec\n");
        MFShutdown();
        return false;
    }

    if (!setD3DManager())          { shutdown(); return false; }
    if (!configureInputType(inputSubtype, width, height, fps)) { shutdown(); return false; }
    if (!configureOutputType())    { shutdown(); return false; }

    HRESULT hr = transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
    if (FAILED(hr)) {
        fprintf(stderr, "MftDecoder: BEGIN_STREAMING failed hr=0x%08lX\n", hr);
        shutdown(); return false;
    }
    transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);

    // Start async drain thread
    drain_running_ = true;
    drain_thread_  = std::thread(&MftDecoder::drainLoop, this);

    initialized_ = true;
    fprintf(stderr, "MftDecoder: initialized %dx%d@%dfps codec=%s\n",
            width, height, fps, isHevc_ ? "H265" : (isAV1_ ? "AV1" : "H264"));
    return true;
}

// -------------------------------------------------------------------
// createTransform — enumerate hardware MFT for the requested codec
// -------------------------------------------------------------------
bool MftDecoder::createTransform(const GUID &inputSubtype) {
    MFT_REGISTER_TYPE_INFO inType  = { MFMediaType_Video, inputSubtype };
    MFT_REGISTER_TYPE_INFO outType = { MFMediaType_Video, MFVideoFormat_NV12 };

    UINT32 flags = MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_ASYNCMFT |
                   MFT_ENUM_FLAG_SORTANDFILTER;

    IMFActivate **activates = nullptr;
    UINT32 count = 0;
    HRESULT hr = MFTEnumEx(MFT_CATEGORY_VIDEO_DECODER, flags,
                            &inType, &outType, &activates, &count);
    if (FAILED(hr) || count == 0) {
        // Fallback: allow software + WDDM1.x non-async hardware
        flags = MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER;
        hr = MFTEnumEx(MFT_CATEGORY_VIDEO_DECODER, flags,
                        &inType, nullptr, &activates, &count);
        if (FAILED(hr) || count == 0) return false;
    }

    // Use first (highest-priority) activate
    hr = activates[0]->ActivateObject(__uuidof(IMFTransform), (void**)&transform_);
    for (UINT32 i = 0; i < count; ++i) activates[i]->Release();
    CoTaskMemFree(activates);

    if (FAILED(hr)) { transform_.Reset(); return false; }

    // Check if async: get IMediaEventGenerator for async MFT drain
    transform_->QueryInterface(__uuidof(IMFMediaEventGenerator),
                                (void**)&event_gen_);
    return true;
}

// -------------------------------------------------------------------
// setD3DManager — connect D3D11 device to the MFT for GPU decode
// -------------------------------------------------------------------
bool MftDecoder::setD3DManager() {
    auto *mgr = D3D11Device::instance().dxgiManager();
    if (!mgr) return false;

    HRESULT hr = transform_->ProcessMessage(
        MFT_MESSAGE_SET_D3D_MANAGER,
        reinterpret_cast<ULONG_PTR>(mgr));

    if (FAILED(hr)) {
        // Some software MFTs don't accept it — that's fine, proceed without GPU
        fprintf(stderr, "MftDecoder: SET_D3D_MANAGER hr=0x%08lX (non-fatal, CPU path)\n", hr);
    }
    return true;
}

// -------------------------------------------------------------------
// configureInputType
// -------------------------------------------------------------------
bool MftDecoder::configureInputType(const GUID &inputSubtype, int w, int h, int fps) {
    ComPtr<IMFMediaType> mt;
    HRESULT hr = MFCreateMediaType(&mt);
    if (FAILED(hr)) return false;

    mt->SetGUID(MF_MT_MAJOR_TYPE,  MFMediaType_Video);
    mt->SetGUID(MF_MT_SUBTYPE,     inputSubtype);
    MFSetAttributeSize(mt.Get(),   MF_MT_FRAME_SIZE, w, h);
    MFSetAttributeRatio(mt.Get(),  MF_MT_FRAME_RATE, fps, 1);
    mt->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);

    hr = transform_->SetInputType(0, mt.Get(), 0);
    if (FAILED(hr)) {
        fprintf(stderr, "MftDecoder: SetInputType FAILED hr=0x%08lX\n", hr);
        return false;
    }
    return true;
}

// -------------------------------------------------------------------
// configureOutputType — select NV12 (or P010 for HDR) hardware surface
// -------------------------------------------------------------------
bool MftDecoder::configureOutputType() {
    // Enumerate available output types and pick NV12 or P010
    for (DWORD i = 0; ; ++i) {
        ComPtr<IMFMediaType> mt;
        HRESULT hr = transform_->GetOutputAvailableType(0, i, &mt);
        if (hr == MF_E_NO_MORE_TYPES) break;
        if (FAILED(hr)) continue;

        GUID subtype = GUID_NULL;
        mt->GetGUID(MF_MT_SUBTYPE, &subtype);
        if (subtype == MFVideoFormat_NV12 || subtype == MFVideoFormat_P010) {
            hr = transform_->SetOutputType(0, mt.Get(), 0);
            if (SUCCEEDED(hr)) {
                fprintf(stderr, "MftDecoder: output type selected (NV12/P010)\n");
                return true;
            }
        }
    }
    fprintf(stderr, "MftDecoder: no acceptable output type found\n");
    return false;
}

// -------------------------------------------------------------------
// submitFrame — called from moonlight network thread
// -------------------------------------------------------------------
int MftDecoder::submitFrame(const uint8_t *data, int length, int frameType,
                             int frameNumber, int64_t receiveTimeMs) {
    if (!initialized_ || !transform_) return DR_OK;

    bool hevc = isHevc_;
    auto nals = NaluParser::parse(data, length, isAV1_ ? false : hevc);

    // Cache SPS/PPS/VPS when we see them
    {
        std::lock_guard<std::mutex> lk(config_mutex_);
        for (auto &u : nals) {
            if (!isHevc_ && !isAV1_) {
                if (u.type == kNalH264Sps) sps_bytes_.assign(u.data, u.data + u.length);
                if (u.type == kNalH264Pps) pps_bytes_.assign(u.data, u.data + u.length);
            } else if (isHevc_) {
                if (u.type == kNalHevcVps) vps_bytes_.assign(u.data, u.data + u.length);
                if (u.type == kNalHevcSps) sps_bytes_.assign(u.data, u.data + u.length);
                if (u.type == kNalHevcPps) pps_bytes_.assign(u.data, u.data + u.length);
            }
        }
    }

    // Create MF media buffer from Annex-B data
    ComPtr<IMFMediaBuffer> buf;
    HRESULT hr = MFCreateMemoryBuffer(static_cast<DWORD>(length), &buf);
    if (FAILED(hr)) { frames_dropped_++; return DR_OK; }

    BYTE *ptr = nullptr; DWORD maxLen = 0;
    buf->Lock(&ptr, &maxLen, nullptr);
    memcpy(ptr, data, length);
    buf->Unlock();
    buf->SetCurrentLength(static_cast<DWORD>(length));

    ComPtr<IMFSample> sample;
    MFCreateSample(&sample);
    sample->AddBuffer(buf.Get());

    LARGE_INTEGER t0; QueryPerformanceCounter(&t0);
    sample->SetSampleTime(receiveTimeMs * 10000LL);  // 100ns units
    sample->SetSampleDuration(10000000LL / fps_);

    hr = transform_->ProcessInput(0, sample.Get(), 0);
    if (hr == MF_E_NOTACCEPTING) {
        // Decoder queue full; drain is running. This is transient; drop frame.
        frames_dropped_++;
        return DR_OK;
    }
    if (FAILED(hr)) {
        fprintf(stderr, "MftDecoder: ProcessInput FAILED hr=0x%08lX\n", hr);
        frames_dropped_++;
        return DR_OK;
    }

    return DR_OK;
}

// -------------------------------------------------------------------
// drainLoop — runs on dedicated thread, pumps ProcessOutput
// -------------------------------------------------------------------
void MftDecoder::drainLoop() {
    while (drain_running_) {
        // For async MFT: wait for METransformHaveOutput event
        if (event_gen_) {
            ComPtr<IMFMediaEvent> event;
            HRESULT hr = event_gen_->GetEvent(0, &event);
            if (FAILED(hr)) {
                if (!drain_running_) break;
                Sleep(1);
                continue;
            }
            MediaEventType type = MEUnknown;
            event->GetType(&type);
            if (type != METransformHaveOutput) continue;
        }

        // Poll for output
        MFT_OUTPUT_DATA_BUFFER out = {};
        out.dwStreamID = 0;

        DWORD status = 0;
        HRESULT hr = transform_->ProcessOutput(0, 1, &out, &status);

        if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) {
            if (!event_gen_) Sleep(1);
            continue;
        }

        if (FAILED(hr)) {
            if (out.pSample) out.pSample->Release();
            if (!event_gen_) Sleep(1);
            continue;
        }

        if (out.pSample) {
            ComPtr<IMFSample> sample(out.pSample);
            out.pSample->Release();

            // Extract D3D11 texture from sample buffer
            ComPtr<IMFMediaBuffer> buf;
            if (SUCCEEDED(sample->GetBufferByIndex(0, &buf))) {
                ComPtr<IMFDXGIBuffer> dxgiBuf;
                if (SUCCEEDED(buf->QueryInterface(__uuidof(IMFDXGIBuffer), (void**)&dxgiBuf))) {
                    ComPtr<ID3D11Texture2D> tex;
                    UINT subIdx = 0;
                    if (SUCCEEDED(dxgiBuf->GetResource(__uuidof(ID3D11Texture2D), (void**)&tex)) &&
                        SUCCEEDED(dxgiBuf->GetSubresourceIndex(&subIdx))) {
                        DecodedFrame frame{ tex, subIdx };
                        if (on_frame_) on_frame_(frame);
                    }
                }
            }
            frames_decoded_++;
        }

        if (out.pEvents) out.pEvents->Release();
    }
}

// -------------------------------------------------------------------
// shutdown
// -------------------------------------------------------------------
void MftDecoder::shutdown() {
    drain_running_ = false;
    if (drain_thread_.joinable()) drain_thread_.join();

    if (transform_) {
        transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
        transform_->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH,         0);
    }

    event_gen_.Reset();
    transform_.Reset();

    {
        std::lock_guard<std::mutex> lk(config_mutex_);
        sps_bytes_.clear(); pps_bytes_.clear(); vps_bytes_.clear();
    }

    frames_decoded_ = 0;
    frames_dropped_ = 0;
    decode_ema_ms_  = 0.0;
    initialized_    = false;
    MFShutdown();
}

}  // namespace video
}  // namespace jujostream
