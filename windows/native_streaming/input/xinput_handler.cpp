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

static constexpr int    kPollHz         = 125;
static constexpr DWORD  kPollIntervalMs = 1000 / kPollHz;  // 8ms

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

static void dispatchUiNavigation(
    const std::function<void(const std::string&)>& navCb,
    int pressed,
    int released) {
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
    fprintf(stderr, "XInputHandler: polling started @ %dHz\n", kPollHz);
}

void XInputHandler::stopPolling() {
    poll_running_ = false;
    if (poll_thread_.joinable()) poll_thread_.join();
}

void XInputHandler::setDeadzone(int percent)       { deadzone_percent_ = percent; }
void XInputHandler::setResponseCurve(double curve) { response_curve_   = curve;   }

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

void XInputHandler::pollLoop() {
    timeBeginPeriod(1);  // 1ms timer resolution for accurate 8ms sleep

    // Track active mask across all slots
    short activeMask = 0;

    while (poll_running_) {
        activeMask = 0;

        for (int slot = 0; slot < XUSER_MAX_COUNT; ++slot) {
            XINPUT_STATE state{};
            bool connected = (XInputGetState(slot, &state) == ERROR_SUCCESS);

            // Connect/disconnect events
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
                }
            }

            if (!connected) continue;
            activeMask |= (1 << slot);

            // Dpad overlay navigation when overlay is open
            if (overlay_visible_ && overlay_dpad_cb_) {
                WORD xi = state.Gamepad.wButtons;
                if ((xi & XINPUT_GAMEPAD_DPAD_UP)    && !(prev_buttons_[slot] & XINPUT_GAMEPAD_DPAD_UP))
                    overlay_dpad_cb_("up");
                if ((xi & XINPUT_GAMEPAD_DPAD_DOWN)  && !(prev_buttons_[slot] & XINPUT_GAMEPAD_DPAD_DOWN))
                    overlay_dpad_cb_("down");
                if ((xi & XINPUT_GAMEPAD_DPAD_LEFT)  && !(prev_buttons_[slot] & XINPUT_GAMEPAD_DPAD_LEFT))
                    overlay_dpad_cb_("left");
                if ((xi & XINPUT_GAMEPAD_DPAD_RIGHT) && !(prev_buttons_[slot] & XINPUT_GAMEPAD_DPAD_RIGHT))
                    overlay_dpad_cb_("right");
            }

            // Combo detection (overlay trigger, mouse mode)
            int liButtons = xinputToMoonlight(state.Gamepad.wButtons);
            ComboDetector::instance().update(static_cast<uint32_t>(liButtons));

            // Stream input forwarding / UI navigation
            if (streaming_active_) {
                SHORT lx = state.Gamepad.sThumbLX;
                SHORT ly = state.Gamepad.sThumbLY;
                SHORT rx = state.Gamepad.sThumbRX;
                SHORT ry = state.Gamepad.sThumbRY;
                applyDeadzone(lx, ly, deadzone_percent_, response_curve_);
                applyDeadzone(rx, ry, deadzone_percent_, response_curve_);

                moonlightWinSendControllerInput(
                    static_cast<short>(slot),
                    activeMask,
                    liButtons,
                    state.Gamepad.bLeftTrigger,
                    state.Gamepad.bRightTrigger,
                    lx, ly, rx, ry);
            } else {
                int pressed = liButtons & ~static_cast<int>(prev_li_buttons_[slot]);
                int released = static_cast<int>(prev_li_buttons_[slot]) & ~liButtons;
                dispatchUiNavigation(nav_input_cb_, pressed, released);
            }

            prev_buttons_[slot] = state.Gamepad.wButtons;
            prev_li_buttons_[slot] = liButtons;
        }

        // WGI RawGameControllers (DualSense, DS4, Switch Pro, etc)
        if (WgiHandler::instance().isInitialized()) {
            bool wgi_connected[4] = {false, false, false, false};

            WgiHandler::instance().pollRawControllers(XUSER_MAX_COUNT, [&](int slot, int liButtons, uint8_t lt, uint8_t rt, int16_t lx, int16_t ly, int16_t rx, int16_t ry) {
                if (slot >= 8) return; 
                wgi_connected[slot - XUSER_MAX_COUNT] = true;
                
                if (!prev_connected_[slot]) {
                    prev_connected_[slot] = true;
                    fprintf(stderr, "XInputHandler: WGI raw controller %d connected\n", slot);
                    if (onControllerConnected) onControllerConnected(slot);
                }
                
                activeMask |= (1 << slot);

                // Dpad overlay navigation
                if (overlay_visible_ && overlay_dpad_cb_) {
                    if ((liButtons & LI_UP)    && !(prev_buttons_[slot] & LI_UP))    overlay_dpad_cb_("up");
                    if ((liButtons & LI_DOWN)  && !(prev_buttons_[slot] & LI_DOWN))  overlay_dpad_cb_("down");
                    if ((liButtons & LI_LEFT)  && !(prev_buttons_[slot] & LI_LEFT))  overlay_dpad_cb_("left");
                    if ((liButtons & LI_RIGHT) && !(prev_buttons_[slot] & LI_RIGHT)) overlay_dpad_cb_("right");
                }

                ComboDetector::instance().update(static_cast<uint32_t>(liButtons));

                if (streaming_active_) {
                    SHORT slx = lx, sly = ly, srx = rx, sry = ry;
                    applyDeadzone(slx, sly, deadzone_percent_, response_curve_);
                    applyDeadzone(srx, sry, deadzone_percent_, response_curve_);

                    moonlightWinSendControllerInput(
                        static_cast<short>(slot),
                        activeMask,
                        liButtons,
                        lt, rt,
                        slx, sly, srx, sry);
                } else {
                    int pressed = liButtons & ~static_cast<int>(prev_li_buttons_[slot]);
                    int released = static_cast<int>(prev_li_buttons_[slot]) & ~liButtons;
                    dispatchUiNavigation(nav_input_cb_, pressed, released);
                }

                prev_buttons_[slot] = liButtons;
                prev_li_buttons_[slot] = liButtons;
            });

            // Handle WGI disconnects
            for (int i = 0; i < 4; ++i) {
                int slot = XUSER_MAX_COUNT + i;
                if (prev_connected_[slot] && !wgi_connected[i]) {
                    prev_connected_[slot] = false;
                    prev_buttons_[slot] = 0;
                    prev_li_buttons_[slot] = 0;
                    fprintf(stderr, "XInputHandler: WGI raw controller %d disconnected\n", slot);
                    if (onControllerDisconnected) onControllerDisconnected(slot);
                }
            }
        }

        Sleep(kPollIntervalMs);
    }

    timeEndPeriod(1);
}

}  // namespace input
}  // namespace jujostream
