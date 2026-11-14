/**
 * xinput_handler.cpp
 *
 * 125Hz XInput polling thread.
 * Applies radial deadzone, response curve, and forwards to moonlight-common-c.
 * Fires Dart callbacks on connect/disconnect and combo detection.
 */
#include "xinput_handler.h"
#include "wgi_handler.h"
#include "combo_detector.h"

extern "C" {
#include "moonlight_bridge_win.h"
#include "Limelight.h"
}

#include <xinput.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <timeapi.h>
#include <windows.h>

#pragma comment(lib, "xinput.lib")
#pragma comment(lib, "winmm.lib")

namespace jujostream {
namespace input {

static constexpr uint64_t kControllerHeartbeatMs = 200;

static void classifyWgiController(
    uint16_t vid, uint16_t /*pid*/, uint8_t &type, short &capabilities, int &supportedButtons) {
    if (vid == 0x054C) {
        type = LI_CTYPE_PS;
        capabilities = LI_CCAP_ANALOG_TRIGGERS | LI_CCAP_RUMBLE | LI_CCAP_RGB_LED;
        supportedButtons = 0xFFFF | TOUCHPAD_FLAG | MISC_FLAG;
    } else if (vid == 0x057E) {
        type = LI_CTYPE_NINTENDO;
        capabilities = LI_CCAP_RUMBLE;
        supportedButtons = 0xFFFF;
    } else {
        type = LI_CTYPE_XBOX;
        capabilities = LI_CCAP_ANALOG_TRIGGERS | LI_CCAP_RUMBLE;
        supportedButtons = 0xFFFF;
    }
}

// Xinput button → moonlight button flag mapping
// moonlight-common-c button flags (from Limelight.h)
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

static int xinputToMoonlight(WORD xi) {
    int li = 0;
    if (xi & XINPUT_GAMEPAD_A)              li |= LI_A;
    if (xi & XINPUT_GAMEPAD_B)              li |= LI_B;
    if (xi & XINPUT_GAMEPAD_X)              li |= LI_X;
    if (xi & XINPUT_GAMEPAD_Y)              li |= LI_Y;
    if (xi & XINPUT_GAMEPAD_DPAD_UP)        li |= LI_UP;
    if (xi & XINPUT_GAMEPAD_DPAD_DOWN)      li |= LI_DOWN;
    if (xi & XINPUT_GAMEPAD_DPAD_LEFT)      li |= LI_LEFT;
    if (xi & XINPUT_GAMEPAD_DPAD_RIGHT)     li |= LI_RIGHT;
    if (xi & XINPUT_GAMEPAD_LEFT_SHOULDER)  li |= LI_LB;
    if (xi & XINPUT_GAMEPAD_RIGHT_SHOULDER) li |= LI_RB;
    if (xi & XINPUT_GAMEPAD_LEFT_THUMB)     li |= LI_LS;
    if (xi & XINPUT_GAMEPAD_RIGHT_THUMB)    li |= LI_RS;
    if (xi & XINPUT_GAMEPAD_START)          li |= LI_START;
    if (xi & XINPUT_GAMEPAD_BACK)           li |= LI_BACK;
    return li;
}

static bool isCurrentProcessForeground() {
    HWND foreground = GetForegroundWindow();
    if (!foreground) return false;

    DWORD processId = 0;
    GetWindowThreadProcessId(foreground, &processId);
    return processId == GetCurrentProcessId();
}

static void sendKeyboardEdge(WORD vk, bool down) {
    INPUT input{};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = vk;
    input.ki.dwFlags = down ? 0 : KEYEVENTF_KEYUP;
    SendInput(1, &input, sizeof(INPUT));
}

static void sendUiKeyEdges(int pressed, int released) {
    struct Mapping {
        int flag;
        WORD vk;
    };

    static constexpr Mapping mappings[] = {
        {LI_UP, VK_UP},
        {LI_DOWN, VK_DOWN},
        {LI_LEFT, VK_LEFT},
        {LI_RIGHT, VK_RIGHT},
        {LI_A, VK_RETURN},
        {LI_B, VK_ESCAPE},
    };

    for (const auto& mapping : mappings) {
        if (pressed & mapping.flag) sendKeyboardEdge(mapping.vk, true);
        if (released & mapping.flag) sendKeyboardEdge(mapping.vk, false);
    }
}

static void emitDartNavEdges(
    const std::function<void(const std::string&)>& navCb,
    int pressed) {
    if (!navCb) return;
    if (pressed & LI_UP)    navCb("up");
    if (pressed & LI_DOWN)  navCb("down");
    if (pressed & LI_LEFT)  navCb("left");
    if (pressed & LI_RIGHT) navCb("right");
    if (pressed & LI_A)     navCb("select");
    if (pressed & LI_B)     navCb("back");
}

// Aux buttons have no VK equivalent in the UI scheme; deliver them to Dart
// regardless of foreground state so opted-in screens (cloud auth) can use them.
static void emitAuxDartEdges(
    const std::function<void(const std::string&)>& navCb,
    int pressed) {
    if (!navCb) return;
    if (pressed & LI_X)     navCb("x");
    if (pressed & LI_Y)     navCb("y");
    if (pressed & LI_LB)    navCb("lb");
    if (pressed & LI_RB)    navCb("rb");
    if (pressed & LI_START) navCb("start");
}

static void dispatchUiNavigation(
    const std::function<void(const std::string&)>& navCb,
    int pressed,
    int released) {
    emitAuxDartEdges(navCb, pressed);
    if (isCurrentProcessForeground()) {
        sendUiKeyEdges(pressed, released);
        return;
    }
    emitDartNavEdges(navCb, pressed);
}

// Radial deadzone + response curve on a single axis pair
static void applyDeadzone(SHORT &x, SHORT &y, int deadzonePercent, double curve) {
    double fx = x / 32767.0;
    double fy = y / 32767.0;
    double mag = std::sqrt(fx*fx + fy*fy);
    double dz  = deadzonePercent / 100.0;
    if (mag < dz) { x = y = 0; return; }
    double scale = (mag - dz) / (1.0 - dz);
    scale = std::pow(scale, curve);
    double norm = scale / mag;
    x = static_cast<SHORT>(std::clamp(fx * norm * 32767.0, -32767.0, 32767.0));
    y = static_cast<SHORT>(std::clamp(fy * norm * 32767.0, -32767.0, 32767.0));
}

XInputHandler &XInputHandler::instance() {
    static XInputHandler inst;
    return inst;
}

void XInputHandler::startPolling() {
    if (poll_running_) return;
    poll_running_ = true;
    poll_thread_  = std::thread(&XInputHandler::pollLoop, this);
    fprintf(stderr, "XInputHandler: polling started @ %dHz\n", poll_hz_.load());
}

void XInputHandler::stopPolling() {
    poll_running_ = false;
    if (poll_thread_.joinable()) poll_thread_.join();
}

void XInputHandler::setDeadzone(int percent)       { deadzone_percent_ = percent; }
void XInputHandler::setResponseCurve(double curve) { response_curve_   = curve;   }
void XInputHandler::setPollingRate(int hz)         { poll_hz_.store(std::clamp(hz, 60, 1000)); }

int XInputHandler::getConnectedCount() const {
    int count = 0;
    for (int i = 0; i < XUSER_MAX_COUNT; ++i) {
        XINPUT_STATE s{}; if (XInputGetState(i, &s) == ERROR_SUCCESS) ++count;
    }
    if (WgiHandler::instance().isInitialized()) {
        count += WgiHandler::instance().getRawControllerCount();
    }
    return count;
}

void XInputHandler::dispatchSlotOverlayAndNav(int slot, int liButtons) {
    if (overlay_visible_ && overlay_dpad_cb_) {
        if ((liButtons & LI_UP)    && !(prev_li_buttons_[slot] & LI_UP))    overlay_dpad_cb_("up");
        if ((liButtons & LI_DOWN)  && !(prev_li_buttons_[slot] & LI_DOWN))  overlay_dpad_cb_("down");
        if ((liButtons & LI_LEFT)  && !(prev_li_buttons_[slot] & LI_LEFT))  overlay_dpad_cb_("left");
        if ((liButtons & LI_RIGHT) && !(prev_li_buttons_[slot] & LI_RIGHT)) overlay_dpad_cb_("right");
    }
    if (streaming_active_.load()) return;

    int pressed = liButtons & ~static_cast<int>(prev_li_buttons_[slot]);
    int released = static_cast<int>(prev_li_buttons_[slot]) & ~liButtons;
    dispatchUiNavigation(nav_input_cb_, pressed, released);
}

void XInputHandler::sendSlotIfChanged(
    int slot, short activeMask, uint8_t controllerType, short capabilities,
    int supportedButtons, int liButtons, uint8_t lt, uint8_t rt,
    int16_t lx, int16_t ly, int16_t rx, int16_t ry) {
    if (!arrival_sent_[slot]) {
        moonlightWinSendControllerArrival(
            static_cast<short>(slot), activeMask, controllerType, capabilities, supportedButtons);
        arrival_sent_[slot] = true;
    }

    const uint64_t nowMs = GetTickCount64();
    SentControllerState &prev = last_sent_[slot];
    const bool changed = !prev.valid ||
        prev.activeMask != activeMask ||
        prev.buttons != liButtons ||
        prev.lt != lt || prev.rt != rt ||
        prev.lx != lx || prev.ly != ly ||
        prev.rx != rx || prev.ry != ry ||
        (nowMs - prev.lastSentMs) >= kControllerHeartbeatMs;

    if (!changed) return;

    moonlightWinSendControllerInput(
        static_cast<short>(slot), activeMask, liButtons, lt, rt, lx, ly, rx, ry);
    prev = {true, activeMask, liButtons, lt, rt, lx, ly, rx, ry, nowMs};
}

void XInputHandler::pollLoop() {
    timeBeginPeriod(1);  // 1ms timer resolution fallback
#ifdef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
    HANDLE waitTimer = CreateWaitableTimerExW(
        nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
#else
    HANDLE waitTimer = nullptr;
#endif

    struct SlotReading {
        bool connected = false;
        uint8_t type = LI_CTYPE_XBOX;
        short capabilities = LI_CCAP_ANALOG_TRIGGERS | LI_CCAP_RUMBLE;
        int supportedButtons = 0xFFFF;
        int liButtons = 0;
        uint8_t lt = 0;
        uint8_t rt = 0;
        SHORT lx = 0;
        SHORT ly = 0;
        SHORT rx = 0;
        SHORT ry = 0;
    };

    while (poll_running_) {
        const bool streamingActive = streaming_active_.load();
        if (!streamingActive) {
            for (int i = 0; i < 8; ++i) {
                arrival_sent_[i] = false;
                last_sent_[i].valid = false;
            }
        }

        SlotReading slots[8] = {};
        bool justDisconnected[8] = {};
        short activeMask = 0;

        for (int slot = 0; slot < XUSER_MAX_COUNT; ++slot) {
            XINPUT_STATE state{};
            const bool connected = (XInputGetState(slot, &state) == ERROR_SUCCESS);

            if (connected != prev_connected_[slot]) {
                prev_connected_[slot] = connected;
                if (connected) {
                    fprintf(stderr, "XInputHandler: controller %d connected\n", slot);
                    if (onControllerConnected) onControllerConnected(slot);
                } else {
                    fprintf(stderr, "XInputHandler: controller %d disconnected\n", slot);
                    if (onControllerDisconnected) onControllerDisconnected(slot);
                    prev_buttons_[slot] = 0;
                    prev_li_buttons_[slot] = 0;
                    arrival_sent_[slot] = false;
                    last_sent_[slot].valid = false;
                    justDisconnected[slot] = true;
                }
            }

            if (!connected) continue;
            activeMask |= static_cast<short>(1 << slot);

            slots[slot].connected = true;
            slots[slot].liButtons = xinputToMoonlight(state.Gamepad.wButtons);
            slots[slot].lt = state.Gamepad.bLeftTrigger;
            slots[slot].rt = state.Gamepad.bRightTrigger;
            slots[slot].lx = state.Gamepad.sThumbLX;
            slots[slot].ly = state.Gamepad.sThumbLY;
            slots[slot].rx = state.Gamepad.sThumbRX;
            slots[slot].ry = state.Gamepad.sThumbRY;
        }

        // WGI RawGameControllers (DualSense, DS4, Switch Pro, etc)
        if (WgiHandler::instance().isInitialized()) {
            bool wgiConnected[4] = {false, false, false, false};

            WgiHandler::instance().pollRawControllers(
                XUSER_MAX_COUNT,
                [&](int slot, uint16_t vid, uint16_t pid, int liButtons,
                    uint8_t lt, uint8_t rt, int16_t lx, int16_t ly, int16_t rx, int16_t ry) {
                    if (slot < XUSER_MAX_COUNT || slot >= 8) return;
                    wgiConnected[slot - XUSER_MAX_COUNT] = true;

                    if (!prev_connected_[slot]) {
                        prev_connected_[slot] = true;
                        fprintf(stderr, "XInputHandler: WGI raw controller %d connected (vid=0x%04X pid=0x%04X)\n",
                                slot, vid, pid);
                        if (onControllerConnected) onControllerConnected(slot);
                    }

                    activeMask |= static_cast<short>(1 << slot);
                    SlotReading &r = slots[slot];
                    r.connected = true;
                    classifyWgiController(vid, pid, r.type, r.capabilities, r.supportedButtons);
                    r.liButtons = liButtons;
                    r.lt = lt;
                    r.rt = rt;
                    r.lx = lx;
                    r.ly = ly;
                    r.rx = rx;
                    r.ry = ry;
                });

            for (int i = 0; i < 4; ++i) {
                const int slot = XUSER_MAX_COUNT + i;
                if (prev_connected_[slot] && !wgiConnected[i]) {
                    prev_connected_[slot] = false;
                    prev_buttons_[slot] = 0;
                    prev_li_buttons_[slot] = 0;
                    arrival_sent_[slot] = false;
                    last_sent_[slot].valid = false;
                    justDisconnected[slot] = true;
                    fprintf(stderr, "XInputHandler: WGI raw controller %d disconnected\n", slot);
                    if (onControllerDisconnected) onControllerDisconnected(slot);
                }
            }
        }

        for (int slot = 0; slot < 8; ++slot) {
            if (streamingActive && justDisconnected[slot]) {
                moonlightWinSendControllerInput(static_cast<short>(slot), activeMask, 0, 0, 0, 0, 0, 0, 0);
            }
            if (!slots[slot].connected) continue;

            SlotReading &r = slots[slot];
            ComboDetector::instance().update(static_cast<uint32_t>(r.liButtons));

            if (streamingActive) {
                if (overlay_visible_) {
                    dispatchSlotOverlayAndNav(slot, r.liButtons);
                }
                SHORT lx = r.lx, ly = r.ly, rx = r.rx, ry = r.ry;
                applyDeadzone(lx, ly, deadzone_percent_, response_curve_);
                applyDeadzone(rx, ry, deadzone_percent_, response_curve_);
                sendSlotIfChanged(
                    slot, activeMask, r.type, r.capabilities, r.supportedButtons,
                    r.liButtons, r.lt, r.rt, lx, ly, rx, ry);
            } else {
                dispatchSlotOverlayAndNav(slot, r.liButtons);
            }

            prev_buttons_[slot] = static_cast<uint32_t>(r.liButtons);
            prev_li_buttons_[slot] = static_cast<uint32_t>(r.liButtons);
        }

        const int hz = std::clamp(poll_hz_.load(), 60, 1000);
        if (waitTimer) {
            LARGE_INTEGER due{};
            due.QuadPart = -(10000000LL / hz);
            if (SetWaitableTimer(waitTimer, &due, 0, nullptr, nullptr, FALSE)) {
                WaitForSingleObject(waitTimer, INFINITE);
            } else {
                Sleep(std::max<DWORD>(1, 1000 / hz));
            }
        } else {
            Sleep(std::max<DWORD>(1, 1000 / hz));
        }
    }

    if (waitTimer) CloseHandle(waitTimer);
    timeEndPeriod(1);
}

}  // namespace input
}  // namespace jujostream
