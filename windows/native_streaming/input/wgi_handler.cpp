/**
 * wgi_handler.cpp
 *
 * Windows.Gaming.Input — trigger rumble + controller LED.
 * Used alongside XInput for enhanced haptic feedback (trigger motors).
 * XInput handles standard left/right motor rumble natively.
 */
#include "wgi_handler.h"
#include <cstdio>
#include <vector>
#include <roapi.h>
#include <wrl/wrappers/corewrappers.h>
#include <windows.gaming.input.h>

static constexpr int LI_A      = 0x1000;
static constexpr int LI_B      = 0x2000;
static constexpr int LI_X      = 0x4000;
static constexpr int LI_Y      = 0x8000;
static constexpr int LI_UP     = 0x0001;
static constexpr int LI_DOWN   = 0x0002;
static constexpr int LI_LEFT   = 0x0004;
static constexpr int LI_RIGHT  = 0x0008;
static constexpr int LI_LB     = 0x0100;
static constexpr int LI_RB     = 0x0200;
static constexpr int LI_LS     = 0x0400;
static constexpr int LI_RS     = 0x0800;
static constexpr int LI_START  = 0x0010;
static constexpr int LI_BACK   = 0x0020;
static constexpr int LI_GUIDE  = 0x0040;


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
        
    // Get IRawGameControllerStatics (Win10 1607+)
    hr = RoGetActivationFactory(
        HStringReference(RuntimeClass_Windows_Gaming_Input_RawGameController).Get(),
        __uuidof(IRawGameControllerStatics), (void**)&raw_statics_);

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
    raw_statics_.Reset();
    initialized_ = false;
}

int WgiHandler::getRawControllerCount() {
    if (!initialized_ || !raw_statics_) return 0;
    ComPtr<IVectorView<RawGameController*>> pads;
    if (FAILED(raw_statics_->get_RawGameControllers(&pads))) return 0;
    unsigned int count = 0;
    pads->get_Size(&count);
    
    int rawCount = 0;
    for (unsigned int i = 0; i < count; ++i) {
        ComPtr<IRawGameController> raw;
        if (SUCCEEDED(pads->GetAt(i, &raw))) {
            ComPtr<IGameController> gc;
            if (SUCCEEDED(raw.As(&gc))) {
                ComPtr<IGamepadStatics2> statics2;
                if (statics_ && SUCCEEDED(statics_.As(&statics2))) {
                    ComPtr<IGamepad> gp;
                    if (SUCCEEDED(statics2->FromGameController(gc.Get(), &gp)) && gp) {
                        continue; // Skip XInput / standard WGI gamepad
                    }
                }
                rawCount++;
            }
        }
    }
    return rawCount;
}

void WgiHandler::pollRawControllers(
    int startingSlot,
    std::function<void(int slot, uint16_t vid, uint16_t pid, int moonlightButtons, uint8_t lt, uint8_t rt, int16_t lx, int16_t ly, int16_t rx, int16_t ry)> callback) {
    
    if (!initialized_ || !raw_statics_ || !callback) return;
    
    ComPtr<IVectorView<RawGameController*>> pads;
    if (FAILED(raw_statics_->get_RawGameControllers(&pads))) return;
    
    unsigned int count = 0;
    pads->get_Size(&count);
    
    int currentSlot = startingSlot;
    
    for (unsigned int i = 0; i < count; ++i) {
        ComPtr<IRawGameController> raw;
        if (FAILED(pads->GetAt(i, &raw))) continue;
        
        ComPtr<IGameController> gc;
        if (FAILED(raw.As(&gc))) continue;
        
        ComPtr<IGamepadStatics2> statics2;
        if (statics_ && SUCCEEDED(statics_.As(&statics2))) {
            ComPtr<IGamepad> gp;
            if (SUCCEEDED(statics2->FromGameController(gc.Get(), &gp)) && gp) {
                continue; 
            }
        }
        
        int buttonCount = 0, axisCount = 0, switchCount = 0;
        raw->get_ButtonCount(&buttonCount);
        raw->get_AxisCount(&axisCount);
        raw->get_SwitchCount(&switchCount);
        
        std::vector<boolean> buttons(buttonCount);
        std::vector<double> axes(axisCount);
        std::vector<GameControllerSwitchPosition> switches(switchCount);
        
        uint64_t timestamp = 0;
        raw->GetCurrentReading(
            buttonCount, buttons.data(),
            switchCount, switches.data(),
            axisCount, axes.data(),
            &timestamp);
            
        int li = 0;
        
        if (switchCount > 0) {
            auto sw = switches[0];
            if (sw == GameControllerSwitchPosition_Up || sw == GameControllerSwitchPosition_UpRight || sw == GameControllerSwitchPosition_UpLeft) li |= LI_UP;
            if (sw == GameControllerSwitchPosition_Down || sw == GameControllerSwitchPosition_DownRight || sw == GameControllerSwitchPosition_DownLeft) li |= LI_DOWN;
            if (sw == GameControllerSwitchPosition_Left || sw == GameControllerSwitchPosition_UpLeft || sw == GameControllerSwitchPosition_DownLeft) li |= LI_LEFT;
            if (sw == GameControllerSwitchPosition_Right || sw == GameControllerSwitchPosition_UpRight || sw == GameControllerSwitchPosition_DownRight) li |= LI_RIGHT;
        }
        
        if (buttonCount > 0 && buttons[0]) li |= LI_X; 
        if (buttonCount > 1 && buttons[1]) li |= LI_A; 
        if (buttonCount > 2 && buttons[2]) li |= LI_B; 
        if (buttonCount > 3 && buttons[3]) li |= LI_Y; 
        if (buttonCount > 4 && buttons[4]) li |= LI_LB; 
        if (buttonCount > 5 && buttons[5]) li |= LI_RB; 
        if (buttonCount > 8 && buttons[8]) li |= LI_BACK; 
        if (buttonCount > 9 && buttons[9]) li |= LI_START; 
        if (buttonCount > 10 && buttons[10]) li |= LI_LS; 
        if (buttonCount > 11 && buttons[11]) li |= LI_RS; 
        if (buttonCount > 12 && buttons[12]) li |= LI_GUIDE; 
        
        uint16_t vid = 0, pid = 0;
        raw->get_HardwareVendorId(&vid);
        raw->get_HardwareProductId(&pid);
        
        int16_t lx = 0, ly = 0, rx = 0, ry = 0;
        uint8_t lt = 0, rt = 0;
        
        auto getAxis = [&](int index) -> int16_t {
            if (index >= axisCount) return 0;
            double v = axes[index];
            v = (v - 0.5) * 2.0; 
            return static_cast<int16_t>(v * 32767.0);
        };
        
        auto getTrigger = [&](int index) -> uint8_t {
            if (index >= axisCount) return 0;
            double v = axes[index];
            return static_cast<uint8_t>(v * 255.0);
        };
        
        if (vid == 0x054C) { 
            lx = getAxis(0);
            ly = -getAxis(1); 
            
            if (pid == 0x0CE6) { 
                rx = getAxis(2);
                ry = -getAxis(3);
                lt = getTrigger(4);
                rt = getTrigger(5);
            } else {
                rx = getAxis(3);
                ry = -getAxis(4);
                lt = getTrigger(2);
                rt = getTrigger(5);
            }
        } else {
            lx = getAxis(0);
            ly = -getAxis(1);
            rx = getAxis(2);
            ry = -getAxis(3);
            lt = getTrigger(4);
            rt = getTrigger(5);
        }
        
        callback(currentSlot++, vid, pid, li, lt, rt, lx, ly, rx, ry);
    }
}


}  // namespace input
}  // namespace jujostream
