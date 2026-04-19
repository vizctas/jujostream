/**
 * texture_bridge.cpp
 *
 * GPU-path zero-copy texture bridge.
 * Registers a FlutterDesktopGpuSurfaceTexture with the engine.
 * The Flutter compositor reads directly from the D3D11 texture on the GPU.
 */
#include "texture_bridge.h"
#include "d3d11_device.h"
#include <cstdio>
#include <cinttypes>

namespace jujostream {
namespace video {

TextureBridge &TextureBridge::instance() {
    static TextureBridge inst;
    return inst;
}

bool TextureBridge::initialize(flutter::TextureRegistrar *registrar,
                                int width, int height) {
    if (initialized_) shutdown();
    if (!registrar) return false;

    registrar_ = registrar;
    width_     = width;
    height_    = height;

    // Register a GPU surface texture with Flutter.
    // The engine calls the callback on the raster thread to obtain the surface.
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
        return false;
    }

    initialized_ = true;
    fprintf(stderr, "TextureBridge: GPU texture registered id=%" PRId64 " %dx%d\n",
            texture_id_, width_, height_);
    return true;
}

const FlutterDesktopGpuSurfaceDescriptor *
TextureBridge::gpuCallback(size_t /*width*/, size_t /*height*/) {
    std::lock_guard<std::mutex> lk(frame_mutex_);
    if (!latest_texture_) return nullptr;

    // Get the shared handle for the texture so Flutter can consume it cross-context
    ComPtr<IDXGIResource> dxgiRes;
    HANDLE sharedHandle = nullptr;
    if (SUCCEEDED(latest_texture_->QueryInterface(__uuidof(IDXGIResource),
                                                   (void**)&dxgiRes))) {
        dxgiRes->GetSharedHandle(&sharedHandle);
    }

    gpu_desc_.struct_size  = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    gpu_desc_.handle       = sharedHandle;
    gpu_desc_.width        = static_cast<size_t>(width_);
    gpu_desc_.height       = static_cast<size_t>(height_);
    gpu_desc_.visible_width  = gpu_desc_.width;
    gpu_desc_.visible_height = gpu_desc_.height;
    gpu_desc_.format       = kFlutterDesktopPixelFormatNone;  // native format kept
    gpu_desc_.release_callback   = nullptr;
    gpu_desc_.release_context    = nullptr;
    return &gpu_desc_;
}

void TextureBridge::onFrame(const DecodedFrame &frame) {
    {
        std::lock_guard<std::mutex> lk(frame_mutex_);
        latest_texture_     = frame.texture;
        latest_subresource_ = frame.subresource;
    }
    if (initialized_ && texture_id_ >= 0) {
        registrar_->MarkTextureFrameAvailable(texture_id_);
    }
}

void TextureBridge::shutdown() {
    if (initialized_ && texture_id_ >= 0 && registrar_) {
        registrar_->UnregisterTexture(texture_id_);
    }
    {
        std::lock_guard<std::mutex> lk(frame_mutex_);
        latest_texture_.Reset();
    }
    texture_variant_.reset();
    texture_id_   = -1;
    registrar_    = nullptr;
    initialized_  = false;
}

}  // namespace video
}  // namespace jujostream
