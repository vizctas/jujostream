import sys

content = open("windows/native_streaming/input/xinput_handler.cpp", "r").read()

new_includes = """#include "xinput_handler.h"
#include "wgi_handler.h"
#include "combo_detector.h"
"""

content = content.replace("""#include "xinput_handler.h"
#include "combo_detector.h"
""", new_includes)


old_get_count = """int XInputHandler::getConnectedCount() const {
    int count = 0;
    for (int i = 0; i < XUSER_MAX_COUNT; ++i) {
        XINPUT_STATE s{}; if (XInputGetState(i, &s) == ERROR_SUCCESS) ++count;
    }
    return count;
}"""

new_get_count = """int XInputHandler::getConnectedCount() const {
    int count = 0;
    for (int i = 0; i < XUSER_MAX_COUNT; ++i) {
        XINPUT_STATE s{}; if (XInputGetState(i, &s) == ERROR_SUCCESS) ++count;
    }
    if (WgiHandler::instance().isInitialized()) {
        count += WgiHandler::instance().getRawControllerCount();
    }
    return count;
}"""

content = content.replace(old_get_count, new_get_count)

old_poll = """        for (int slot = 0; slot < XUSER_MAX_COUNT; ++slot) {
            XINPUT_STATE state{};
            bool connected = (XInputGetState(slot, &state) == ERROR_SUCCESS);

            // Connect/disconnect events
            if (connected != prev_connected_[slot]) {
                prev_connected_[slot] = connected;
                if (connected) {
                    fprintf(stderr, "XInputHandler: controller %d connected\\n", slot);
                    if (onControllerConnected) onControllerConnected(slot);
                } else {
                    fprintf(stderr, "XInputHandler: controller %d disconnected\\n", slot);
                    if (onControllerDisconnected) onControllerDisconnected(slot);
                    prev_buttons_[slot] = 0;
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

            // Stream input forwarding
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
            }

            prev_buttons_[slot] = state.Gamepad.wButtons;
        }"""

new_poll = """        for (int slot = 0; slot < XUSER_MAX_COUNT; ++slot) {
            XINPUT_STATE state{};
            bool connected = (XInputGetState(slot, &state) == ERROR_SUCCESS);

            // Connect/disconnect events
            if (connected != prev_connected_[slot]) {
                prev_connected_[slot] = connected;
                if (connected) {
                    fprintf(stderr, "XInputHandler: controller %d connected\\n", slot);
                    if (onControllerConnected) onControllerConnected(slot);
                } else {
                    fprintf(stderr, "XInputHandler: controller %d disconnected\\n", slot);
                    if (onControllerDisconnected) onControllerDisconnected(slot);
                    prev_buttons_[slot] = 0;
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

            // Stream input forwarding
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
            }

            prev_buttons_[slot] = state.Gamepad.wButtons;
        }

        // WGI RawGameControllers (DualSense, DS4, Switch Pro, etc)
        if (WgiHandler::instance().isInitialized()) {
            bool wgi_connected[4] = {false, false, false, false};

            WgiHandler::instance().pollRawControllers(XUSER_MAX_COUNT, [&](int slot, int liButtons, uint8_t lt, uint8_t rt, int16_t lx, int16_t ly, int16_t rx, int16_t ry) {
                if (slot >= 8) return; 
                wgi_connected[slot - XUSER_MAX_COUNT] = true;
                
                if (!prev_connected_[slot]) {
                    prev_connected_[slot] = true;
                    fprintf(stderr, "XInputHandler: WGI raw controller %d connected\\n", slot);
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
                }

                prev_buttons_[slot] = liButtons;
            });

            // Handle WGI disconnects
            for (int i = 0; i < 4; ++i) {
                int slot = XUSER_MAX_COUNT + i;
                if (prev_connected_[slot] && !wgi_connected[i]) {
                    prev_connected_[slot] = false;
                    prev_buttons_[slot] = 0;
                    fprintf(stderr, "XInputHandler: WGI raw controller %d disconnected\\n", slot);
                    if (onControllerDisconnected) onControllerDisconnected(slot);
                }
            }
        }"""

content = content.replace(old_poll, new_poll)

open("windows/native_streaming/input/xinput_handler.cpp", "w").write(content)
