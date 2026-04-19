/**
 * wgi_handler.h
 *
 * Windows.Gaming.Input handler for trigger rumble and enhanced vibration.
 * Supplements XInput with trigger + LED support.
 */
#pragma once

#include <cstdint>
#include <wrl/client.h>
#include <windows.gaming.input.h>

namespace jujostream {
namespace input {

class WgiHandler {
public:
    static WgiHandler &instance();

    bool initialize();
    void shutdown();

    /**
     * Set vibration for a specific controller slot.
     * Values 0-65535 (normalize to 0.0-1.0 for WGI).
     */
    void setVibration(int slot,
                      uint16_t leftMotor, uint16_t rightMotor,
                      uint16_t leftTrigger, uint16_t rightTrigger);

    bool isInitialized() const { return initialized_; }

private:
    WgiHandler() = default;
    ~WgiHandler() { shutdown(); }

    Microsoft::WRL::ComPtr<ABI::Windows::Gaming::Input::IGamepadStatics> statics_;
    bool initialized_ = false;
};

}  // namespace input
}  // namespace jujostream
