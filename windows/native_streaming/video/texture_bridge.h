/**
 * texture_bridge.h
 *
 * GPU-path Flutter texture bridge.
 *
 * Pipeline (per frame):
 *   onFrame(DecodedFrame [NV12/P010 texture array slice])
 *     → ID3D11VideoProcessor converts NV12/P010 → BGRA8
 *     → result written to output_tex_ (D3D11_RESOURCE_MISC_SHARED)
 *     → Flush() submitted, MarkTextureFrameAvailable called
 *   Flutter engine (raster thread)
 *     → gpuCallback → returns &gpu_desc_ (stable DXGI shared handle)
 *
 * Lifecycle:
 *   initialize() → creates video processor + shared BGRA8 texture + registers
 *   onFrame()    → colour-converts + signals Flutter
 *   shutdown()   → unregisters + releases all COM objects
 *
 * Note: a single output_tex_ is used (no double-buffer). The Flush() before
 * MarkTextureFrameAvailable ensures the GPU work is queued before Flutter
 * opens the shared handle.  For zero-tearing, replace with IDXGIKeyedMutex.
 */
#pragma once

#include <atomic>
#include <cstdint>

#include <d3d11.h>
#include <d3d11_1.h>
#include <wrl/client.h>
#include <flutter/texture_registrar.h>

#include "mft_decoder.h"

namespace jujostream {
namespace video {

using Microsoft::WRL::ComPtr;

class TextureBridge {
public:
    static TextureBridge &instance();

    /**
     * Register a GPU surface texture with Flutter.
     * Creates D3D11 video processor (NV12/P010 → BGRA8) and a shared
     * BGRA8 output texture.  Must be called after D3D11Device is ready.
     */
    bool initialize(flutter::TextureRegistrar *registrar, int width, int height);

    /** Called by MftDecoder on every decoded frame (MFT drain thread) */
    void onFrame(const DecodedFrame &frame);

    /** Unregister texture and release all D3D11/COM references */
    void shutdown();

    int64_t textureId()    const { return texture_id_; }
    int     width()        const { return width_; }
    int     height()       const { return height_; }
    bool    isInitialized() const { return initialized_; }
    struct Stats {
        uint64_t blits;
        uint64_t blitFailures;
        uint64_t frameNotifications;
        uint64_t descriptorCallbacks;
        uint64_t nullDescriptorCallbacks;
    };
    Stats stats() const;

private:
    TextureBridge() = default;
    ~TextureBridge() { shutdown(); }

    bool initVideoProcessor(ID3D11Device *dev, int width, int height);
    const FlutterDesktopGpuSurfaceDescriptor *gpuCallback(size_t w, size_t h);

    // Flutter texture registration
    flutter::TextureRegistrar               *registrar_     = nullptr;
    std::unique_ptr<flutter::TextureVariant> texture_variant_;
    int64_t                                  texture_id_    = -1;

    // D3D11 video processor (NV12/P010 → BGRA8)
    ComPtr<ID3D11VideoDevice>              vdev_;
    ComPtr<ID3D11VideoContext>             vctx_;
    ComPtr<ID3D11VideoProcessorEnumerator> vpe_;
    ComPtr<ID3D11VideoProcessor>           vproc_;
    bool                                   vp_ready_ = false;

    // Shared BGRA8 output texture — stable handle for the session
    ComPtr<ID3D11Texture2D>            output_tex_;
    HANDLE                             output_handle_ = nullptr;

    // GPU surface descriptor returned to Flutter (populated in initialize)
    FlutterDesktopGpuSurfaceDescriptor gpu_desc_{};

    // Set to true after the first successful VideoProcessorBlt
    std::atomic<bool> frame_ready_{false};
    std::atomic<uint64_t> blits_{0};
    std::atomic<uint64_t> blit_failures_{0};
    std::atomic<uint64_t> frame_notifications_{0};
    std::atomic<uint64_t> descriptor_callbacks_{0};
    std::atomic<uint64_t> null_descriptor_callbacks_{0};

    int  width_       = 0;
    int  height_      = 0;
    bool initialized_ = false;
};

}  // namespace video
}  // namespace jujostream
