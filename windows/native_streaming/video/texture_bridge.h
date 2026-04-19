/**
 * texture_bridge.h
 *
 * GPU-path Flutter texture bridge.
 * Uses FlutterDesktopGpuSurfaceDescriptor (zero-copy) — hands the
 * ID3D11Texture2D directly to the Flutter engine without any CPU readback.
 *
 * Lifecycle:
 *   initialize(registrar, w, h) → registers FlutterDesktopGpuSurfaceTexture
 *   onFrame(DecodedFrame)       → stores latest texture, calls markFrameAvailable
 *   Flutter engine              → calls gpuCallback_ → returns descriptor
 *   shutdown()                  → unregisters texture, releases D3D11 refs
 */
#pragma once

#include <cstdint>
#include <mutex>
#include <functional>

#include <d3d11.h>
#include <wrl/client.h>
#include <flutter/texture_registrar.h>

#include "mft_decoder.h"   // for DecodedFrame

namespace jujostream {
namespace video {

using Microsoft::WRL::ComPtr;

class TextureBridge {
public:
    static TextureBridge &instance();

    /**
     * Register a GPU surface texture with Flutter.
     * Must be called after D3D11Device is initialized.
     * @return true on success
     */
    bool initialize(flutter::TextureRegistrar *registrar, int width, int height);

    /** Called by MftDecoder on every decoded frame (decode thread) */
    void onFrame(const DecodedFrame &frame);

    /** Unregister texture and release D3D11 references */
    void shutdown();

    int64_t textureId() const { return texture_id_; }
    int     width()     const { return width_; }
    int     height()    const { return height_; }

    bool isInitialized() const { return initialized_; }

private:
    TextureBridge() = default;
    ~TextureBridge() { shutdown(); }

    // Called by Flutter engine on UI thread when it wants the next frame
    const FlutterDesktopGpuSurfaceDescriptor *gpuCallback(size_t width, size_t height);

    flutter::TextureRegistrar                 *registrar_    = nullptr;
    std::unique_ptr<flutter::TextureVariant>   texture_variant_;
    int64_t                                    texture_id_   = -1;

    // Latest decoded frame (swap under lock, then markFrameAvailable)
    std::mutex               frame_mutex_;
    ComPtr<ID3D11Texture2D>  latest_texture_;
    UINT                     latest_subresource_ = 0;

    FlutterDesktopGpuSurfaceDescriptor gpu_desc_{};

    int  width_       = 0;
    int  height_      = 0;
    bool initialized_ = false;
};

}  // namespace video
}  // namespace jujostream
