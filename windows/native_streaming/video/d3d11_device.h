/**
 * d3d11_device.h
 *
 * D3D11 device + device manager singleton.
 * VIDEO_SUPPORT flag enables the hardware video decoder path.
 * Must be initialized before MftDecoder.
 */
#pragma once

#include <d3d11.h>
#include <d3d11_4.h>
#include <dxgi.h>
#include <mfidl.h>
#include <wrl/client.h>

namespace jujostream {
namespace video {

using Microsoft::WRL::ComPtr;

class D3D11Device {
public:
    static D3D11Device &instance();

    /**
     * Create D3D11 device with D3D11_CREATE_DEVICE_VIDEO_SUPPORT.
     * Enables hardware video decoder (DXVA2/D3D11VA) via IMFDXGIDeviceManager.
     * Sets ID3D11Multithread protection for cross-thread texture safety.
     */
    bool initialize();
    void shutdown();

    ID3D11Device        *device()       const { return device_.Get(); }
    ID3D11DeviceContext *context()      const { return context_.Get(); }
    IMFDXGIDeviceManager *dxgiManager() const { return manager_.Get(); }
    UINT                 resetToken()   const { return reset_token_; }

    bool isInitialized() const { return initialized_; }

private:
    D3D11Device() = default;
    ~D3D11Device() { shutdown(); }

    ComPtr<ID3D11Device>         device_;
    ComPtr<ID3D11DeviceContext>  context_;
    ComPtr<IMFDXGIDeviceManager> manager_;
    UINT                         reset_token_  = 0;
    bool                         initialized_  = false;
};

}  // namespace video
}  // namespace jujostream
