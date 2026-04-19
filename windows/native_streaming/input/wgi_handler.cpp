/**
 * wgi_handler.cpp
 *
 * Windows.Gaming.Input — trigger rumble + controller LED.
 * Used alongside XInput for enhanced haptic feedback (trigger motors).
 * XInput handles standard left/right motor rumble natively.
 */
#include "wgi_handler.h"
#include <cstdio>
#include <roapi.h>
#include <wrl/wrappers/corewrappers.h>
#include <windows.gaming.input.h>

using namespace ABI::Windows::Gaming::Input;
using namespace ABI::Windows::Foundation::Collections;
using namespace Microsoft::WRL;
using namespace Microsoft::WRL::Wrappers;

namespace jujostream {
namespace input {

WgiHandler &WgiHandler::instance() {
    static WgiHandler inst;
    return inst;
}

bool WgiHandler::initialize() {
    // WGI requires Windows Runtime
    HRESULT hr = RoInitialize(RO_INIT_MULTITHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        fprintf(stderr, "WgiHandler: RoInitialize FAILED hr=0x%08lX\n", hr);
        return false;
    }

    // Get IGamepadStatics
    hr = RoGetActivationFactory(
        HStringReference(RuntimeClass_Windows_Gaming_Input_Gamepad).Get(),
        __uuidof(IGamepadStatics), (void**)&statics_);
    if (FAILED(hr)) {
        fprintf(stderr, "WgiHandler: IGamepadStatics not available (Win8.1+?)\n");
        return false;
    }

    initialized_ = true;
    fprintf(stderr, "WgiHandler: initialized\n");
    return true;
}

void WgiHandler::setVibration(int slot, uint16_t leftMotor, uint16_t rightMotor,
                                uint16_t leftTrigger, uint16_t rightTrigger) {
    if (!initialized_ || !statics_) return;

    ComPtr<IVectorView<Gamepad*>> pads;
    if (FAILED(statics_->get_Gamepads(&pads))) return;

    unsigned int count = 0;
    pads->get_Size(&count);
    if (slot >= (int)count) return;

    ComPtr<IGamepad> pad;
    if (FAILED(pads->GetAt(static_cast<unsigned>(slot), &pad))) return;

    // GamepadVibration includes LeftTrigger/RightTrigger since Windows 10 RS1
    // — IGamepad::put_Vibration is sufficient for trigger motor support
    GamepadVibration vib{};
    vib.LeftMotor   = leftMotor   / 65535.0;
    vib.RightMotor  = rightMotor  / 65535.0;
    vib.LeftTrigger = leftTrigger / 65535.0;
    vib.RightTrigger = rightTrigger / 65535.0;
    pad->put_Vibration(vib);
}

void WgiHandler::shutdown() {
    statics_.Reset();
    initialized_ = false;
}

}  // namespace input
}  // namespace jujostream
