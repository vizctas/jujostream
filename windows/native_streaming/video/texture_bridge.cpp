/**
 * texture_bridge.cpp
 *
 * GPU-path Flutter texture bridge.
 *
 * The MFT decoder produces NV12/P010 texture arrays.  Flutter's compositor
 * (ANGLE/D3D11) cannot consume NV12 directly — it expects a BGRA8 shared
 * handle.  This class inserts a D3D11 video processor blit (VideoProcessorBlt)
 * that converts each decoded frame to BGRA8 in a D3D11_RESOURCE_MISC_SHARED
 * output texture, then hands a stable DXGI shared handle to Flutter.
 */
#include "texture_bridge.h"
#include "d3d11_device.h"
#include <cstdio>
#include <cinttypes>

namespace jujostream {
namespace video {

// ---------------------------------------------------------------------------
TextureBridge &TextureBridge::instance() {
    static TextureBridge inst;
    return inst;
}

// ---------------------------------------------------------------------------
// initialize
// ---------------------------------------------------------------------------
bool TextureBridge::initialize(flutter::TextureRegistrar *registrar,
                                int width, int height) {
    if (initialized_) shutdown();
    if (!registrar) return false;

    registrar_ = registrar;
    width_     = width;
    height_    = height;
    frame_ready_.store(false, std::memory_order_relaxed);
    blits_ = 0;
    blit_failures_ = 0;
    frame_notifications_ = 0;
    descriptor_callbacks_ = 0;
    null_descriptor_callbacks_ = 0;

    auto *dev = D3D11Device::instance().device();
    if (!dev) {
        fprintf(stderr, "TextureBridge: D3D11Device not ready\n");
        return false;
    }

    // --- D3D11 video processor (NV12/P010 -> BGRA8) -------------------------
    if (!initVideoProcessor(dev, width, height)) {
        fprintf(stderr, "TextureBridge: video processor init failed\n");
        return false;
    }

    // --- Shared BGRA8 output texture -----------------------------------------
    // D3D11_RESOURCE_MISC_SHARED_NTHANDLE (+ _SHARED) is required for cross-adapter
    // access by Flutter's ANGLE/D3D11 backend. Legacy GetSharedHandle works on
    // same-adapter but silently fails when ANGLE creates a second D3D11 device.
    D3D11_TEXTURE2D_DESC td = {};
    td.Width            = static_cast<UINT>(width);
    td.Height           = static_cast<UINT>(height);
    td.MipLevels        = 1;
    td.ArraySize        = 1;
    td.Format           = DXGI_FORMAT_B8G8R8A8_UNORM;
    td.SampleDesc.Count = 1;
    td.Usage            = D3D11_USAGE_DEFAULT;
    td.BindFlags        = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    td.MiscFlags        = D3D11_RESOURCE_MISC_SHARED | D3D11_RESOURCE_MISC_SHARED_NTHANDLE;

    HRESULT hr = dev->CreateTexture2D(&td, nullptr, &output_tex_);
    if (FAILED(hr)) {
        fprintf(stderr, "TextureBridge: CreateTexture2D(BGRA8 shared NT) FAILED hr=0x%08lX\n", hr);
        shutdown();
        return false;
    }

    // Try the modern NT-handle path first (works cross-adapter with ANGLE)
    ComPtr<IDXGIResource1> dxgiRes1;
    if (SUCCEEDED(output_tex_->QueryInterface(__uuidof(IDXGIResource1), (void**)&dxgiRes1))) {
        hr = dxgiRes1->CreateSharedHandle(
            nullptr,                         // default security
            DXGI_SHARED_RESOURCE_READ | DXGI_SHARED_RESOURCE_WRITE,
            nullptr,                         // unnamed
            &output_handle_);
        if (SUCCEEDED(hr) && output_handle_) {
            fprintf(stderr, "TextureBridge: using NT shared handle\n");
        } else {
            output_handle_ = nullptr;
        }
    }

    // Legacy fallback: IDXGIResource::GetSharedHandle (same-adapter only)
    if (!output_handle_) {
        ComPtr<IDXGIResource> dxgiRes;
        hr = output_tex_->QueryInterface(__uuidof(IDXGIResource), (void**)&dxgiRes);
        if (FAILED(hr) || FAILED(dxgiRes->GetSharedHandle(&output_handle_)) || !output_handle_) {
            fprintf(stderr, "TextureBridge: GetSharedHandle (legacy) FAILED hr=0x%08lX\n", hr);
            shutdown();
            return false;
        }
        fprintf(stderr, "TextureBridge: using legacy DXGI shared handle\n");
    }

    // --- Pre-fill the descriptor (all fields stable after init) --------------
    gpu_desc_.struct_size    = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    gpu_desc_.handle         = output_handle_;
    gpu_desc_.width          = static_cast<size_t>(width_);
    gpu_desc_.height         = static_cast<size_t>(height_);
    gpu_desc_.visible_width  = gpu_desc_.width;
    gpu_desc_.visible_height = gpu_desc_.height;
    gpu_desc_.format         = kFlutterDesktopPixelFormatBGRA8888;
    gpu_desc_.release_callback = nullptr;
    gpu_desc_.release_context  = nullptr;

    // --- Register GPU surface texture with Flutter ---------------------------
    flutter::GpuSurfaceTexture::ObtainDescriptorCallback cb =
        [this](size_t w, size_t h) -> const FlutterDesktopGpuSurfaceDescriptor * {
            return gpuCallback(w, h);
        };
    texture_variant_ = std::make_unique<flutter::TextureVariant>(
        flutter::GpuSurfaceTexture(kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
                                   std::move(cb)));

    texture_id_ = registrar_->RegisterTexture(texture_variant_.get());
    if (texture_id_ < 0) {
        fprintf(stderr, "TextureBridge: RegisterTexture FAILED\n");
        shutdown();
        return false;
    }

    initialized_ = true;
    fprintf(stderr,
            "TextureBridge: ready — %dx%d BGRA8 shared handle=%p id=%" PRId64 "\n",
            width_, height_, output_handle_, texture_id_);
    return true;
}

// ---------------------------------------------------------------------------
// initVideoProcessor — create ID3D11VideoProcessor for NV12/P010 -> BGRA8
// ---------------------------------------------------------------------------
bool TextureBridge::initVideoProcessor(ID3D11Device *dev, int width, int height) {
    HRESULT hr = dev->QueryInterface(__uuidof(ID3D11VideoDevice), (void **)&vdev_);
    if (FAILED(hr) || !vdev_) {
        fprintf(stderr, "TextureBridge: ID3D11VideoDevice unavailable hr=0x%08lX\n", hr);
        return false;
    }

    auto *ctx = D3D11Device::instance().context();
    hr = ctx->QueryInterface(__uuidof(ID3D11VideoContext), (void **)&vctx_);
    if (FAILED(hr) || !vctx_) {
        fprintf(stderr, "TextureBridge: ID3D11VideoContext unavailable hr=0x%08lX\n", hr);
        return false;
    }

    D3D11_VIDEO_PROCESSOR_CONTENT_DESC vpdesc = {};
    vpdesc.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
    vpdesc.InputWidth       = static_cast<UINT>(width);
    vpdesc.InputHeight      = static_cast<UINT>(height);
    vpdesc.OutputWidth      = static_cast<UINT>(width);
    vpdesc.OutputHeight     = static_cast<UINT>(height);
    vpdesc.Usage            = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;

    hr = vdev_->CreateVideoProcessorEnumerator(&vpdesc, &vpe_);
    if (FAILED(hr) || !vpe_) {
        fprintf(stderr, "TextureBridge: CreateVideoProcessorEnumerator FAILED hr=0x%08lX\n", hr);
        return false;
    }

    hr = vdev_->CreateVideoProcessor(vpe_.Get(), 0, &vproc_);
    if (FAILED(hr) || !vproc_) {
        fprintf(stderr, "TextureBridge: CreateVideoProcessor FAILED hr=0x%08lX\n", hr);
        return false;
    }

    vp_ready_ = true;
    fprintf(stderr, "TextureBridge: video processor ready (%dx%d NV12/P010->BGRA8)\n",
            width, height);
    return true;
}

// ---------------------------------------------------------------------------
// gpuCallback — called by Flutter raster thread each time it needs a frame
// ---------------------------------------------------------------------------
const FlutterDesktopGpuSurfaceDescriptor *
TextureBridge::gpuCallback(size_t /*w*/, size_t /*h*/) {
    descriptor_callbacks_++;
    // output_handle_ and gpu_desc_ are immutable after initialize().
    // frame_ready_ guards against returning the descriptor before the first blit.
    if (!output_handle_ || !frame_ready_.load(std::memory_order_acquire)) {
        null_descriptor_callbacks_++;
        return nullptr;
    }
    return &gpu_desc_;
}

// ---------------------------------------------------------------------------
// onFrame — called from MFT drain thread on every decoded frame
// ---------------------------------------------------------------------------
void TextureBridge::onFrame(const DecodedFrame &frame) {
    if (!initialized_ || !vp_ready_ || !output_tex_) return;

    auto *ctx = D3D11Device::instance().context();

    // --- Input view: NV12/P010 array slice from the MFT ---------------------
    D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC ivd = {};
    ivd.FourCC                        = 0;  // Inferred from texture format
    ivd.ViewDimension                 = D3D11_VPIV_DIMENSION_TEXTURE2D;
    ivd.Texture2D.MipSlice            = 0;
    ivd.Texture2D.ArraySlice          = frame.subresource;

    ComPtr<ID3D11VideoProcessorInputView> iv;
    HRESULT hr = vdev_->CreateVideoProcessorInputView(
        frame.texture.Get(), vpe_.Get(), &ivd, &iv);
    if (FAILED(hr)) {
        fprintf(stderr, "TextureBridge: CreateVideoProcessorInputView FAILED hr=0x%08lX\n", hr);
        blit_failures_++;
        return;
    }

    // --- Output view: shared BGRA8 texture -----------------------------------
    D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC ovd = {};
    ovd.ViewDimension      = D3D11_VPOV_DIMENSION_TEXTURE2D;
    ovd.Texture2D.MipSlice = 0;

    ComPtr<ID3D11VideoProcessorOutputView> ov;
    hr = vdev_->CreateVideoProcessorOutputView(
        output_tex_.Get(), vpe_.Get(), &ovd, &ov);
    if (FAILED(hr)) {
        fprintf(stderr, "TextureBridge: CreateVideoProcessorOutputView FAILED hr=0x%08lX\n", hr);
        blit_failures_++;
        return;
    }

    // --- VideoProcessorBlt: NV12/P010 -> BGRA8 --------------------------------
    D3D11_VIDEO_PROCESSOR_STREAM stream = {};
    stream.Enable       = TRUE;
    stream.pInputSurface = iv.Get();

    hr = vctx_->VideoProcessorBlt(vproc_.Get(), ov.Get(), 0, 1, &stream);
    if (FAILED(hr)) {
        fprintf(stderr, "TextureBridge: VideoProcessorBlt FAILED hr=0x%08lX\n", hr);
        blit_failures_++;
        return;
    }
    blits_++;

    // Flush so GPU commands are queued before Flutter opens the shared handle.
    // ID3D11Multithread protection serialises this against MFT decode calls.
    ctx->Flush();

    // Signal Flutter that a new frame is available.
    // Flutter Desktop (Win32) documents MarkTextureFrameAvailable as
    // thread-safe — it internally posts to the raster thread queue.
    frame_ready_.store(true, std::memory_order_release);
    if (texture_id_ >= 0 && registrar_) {
        registrar_->MarkTextureFrameAvailable(texture_id_);
        frame_notifications_++;
    }
}

TextureBridge::Stats TextureBridge::stats() const {
    Stats s{};
    s.blits = blits_.load();
    s.blitFailures = blit_failures_.load();
    s.frameNotifications = frame_notifications_.load();
    s.descriptorCallbacks = descriptor_callbacks_.load();
    s.nullDescriptorCallbacks = null_descriptor_callbacks_.load();
    return s;
}

// ---------------------------------------------------------------------------
// shutdown
// ---------------------------------------------------------------------------
void TextureBridge::shutdown() {
    if (initialized_ && texture_id_ >= 0 && registrar_) {
        registrar_->UnregisterTexture(texture_id_);
    }

    vproc_.Reset();
    vpe_.Reset();
    vctx_.Reset();
    vdev_.Reset();
    vp_ready_ = false;

    output_tex_.Reset();
    output_handle_ = nullptr;

    texture_variant_.reset();
    texture_id_    = -1;
    registrar_     = nullptr;
    initialized_   = false;
    frame_ready_.store(false, std::memory_order_relaxed);
}

}  // namespace video
}  // namespace jujostream
