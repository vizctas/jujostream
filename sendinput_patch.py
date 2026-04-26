import sys

content = open("windows/native_streaming/input/xinput_handler.cpp", "r").read()

old_code = """                if (streaming_active_) {
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

                prev_buttons_[slot] = liButtons;"""

new_code = """                if (streaming_active_) {
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
                    // Send keyboard input to navigate UI
                    HWND foreground = GetForegroundWindow();
                    DWORD processId;
                    GetWindowThreadProcessId(foreground, &processId);
                    if (processId == GetCurrentProcessId()) {
                        int pressed = liButtons & ~prev_buttons_[slot];
                        int released = ~liButtons & prev_buttons_[slot];

                        auto sendKey = [](int flag, WORD vk, int pMask, int rMask) {
                            if (pMask & flag) {
                                INPUT input = {0};
                                input.type = INPUT_KEYBOARD;
                                input.ki.wVk = vk;
                                SendInput(1, &input, sizeof(INPUT));
                            }
                            if (rMask & flag) {
                                INPUT input = {0};
                                input.type = INPUT_KEYBOARD;
                                input.ki.wVk = vk;
                                input.ki.dwFlags = KEYEVENTF_KEYUP;
                                SendInput(1, &input, sizeof(INPUT));
                            }
                        };

                        sendKey(LI_UP, VK_UP, pressed, released);
                        sendKey(LI_DOWN, VK_DOWN, pressed, released);
                        sendKey(LI_LEFT, VK_LEFT, pressed, released);
                        sendKey(LI_RIGHT, VK_RIGHT, pressed, released);
                        sendKey(LI_A, VK_RETURN, pressed, released);
                        sendKey(LI_B, VK_ESCAPE, pressed, released);
                    }
                }

                prev_buttons_[slot] = liButtons;"""

content = content.replace(old_code, new_code)

open("windows/native_streaming/input/xinput_handler.cpp", "w").write(content)
