/**
 * d3d11_device.cpp
 *
 * D3D11 device singleton with VIDEO_SUPPORT + IMFDXGIDeviceManager for hardware MFT.
 */
#include "d3d11_device.h"
#include <d3d11_4.h>
#include <mfapi.h>
#include <cstdio>

#pragma comment(lib, "mfplat.lib")

namespace jujostream {
namespace video {

D3D11Device &D3D11Device::instance() {
    static D3D11Device inst;
    return inst;
}

bool D3D11Device::initialize() {
    if (initialized_) return true;

    // Feature levels: prefer 11.1 then 11.0
    D3D_FEATURE_LEVEL featureLevels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
    };
    D3D_FEATURE_LEVEL chosenLevel;

    UINT createFlags = D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
#ifdef _DEBUG
    createFlags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

    HRESULT hr = D3D11CreateDevice(
        nullptr,                       // default adapter
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        createFlags,
        featureLevels, ARRAYSIZE(featureLevels),
        D3D11_SDK_VERSION,
        &device_, &chosenLevel, &context_
    );

    if (FAILED(hr)) {
        // Try without debug flag on release devices
        hr = D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_HARDWARE,
            nullptr,
            D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
            featureLevels, ARRAYSIZE(featureLevels),
            D3D11_SDK_VERSION,
            &device_, &chosenLevel, &context_
        );
    }

    if (FAILED(hr)) {
        fprintf(stderr, "D3D11Device: D3D11CreateDevice FAILED hr=0x%08lX\n", hr);
        return false;
    }

    // Enable multithread protection — MFT calls context on decode thread
    ComPtr<ID3D11Multithread> mt;
    if (SUCCEEDED(device_->QueryInterface(__uuidof(ID3D11Multithread), (void**)&mt))) {
        mt->SetMultithreadProtected(TRUE);
    }

    // Create DXGI device manager for MFT D3D11 awareness
    hr = MFCreateDXGIDeviceManager(&reset_token_, &manager_);
    if (FAILED(hr)) {
        fprintf(stderr, "D3D11Device: MFCreateDXGIDeviceManager FAILED hr=0x%08lX\n", hr);
        return false;
    }

    hr = manager_->ResetDevice(device_.Get(), reset_token_);
    if (FAILED(hr)) {
        fprintf(stderr, "D3D11Device: IDXGIDeviceManager::ResetDevice FAILED hr=0x%08lX\n", hr);
        return false;
    }

    initialized_ = true;
    fprintf(stderr, "D3D11Device: initialized (feature level 0x%X)\n", (unsigned)chosenLevel);
    return true;
}

void D3D11Device::shutdown() {
    manager_.Reset();
    context_.Reset();
    device_.Reset();
    reset_token_  = 0;
    initialized_  = false;
}

}  // namespace video
}  // namespace jujostream
