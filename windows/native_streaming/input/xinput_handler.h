/**
 * xinput_handler.h — XInput polling thread (125Hz) with radial deadzone + response curve.
 */
#pragma once

#include <cstdint>
#include <atomic>
#include <string>
#include <thread>
#include <functional>

namespace jujostream {
namespace input {

class XInputHandler {
public:
    static XInputHandler &instance();

    // Start/stop high-frequency polling thread (configurable 60..1000Hz, default 500Hz)
    void startPolling();
    void stopPolling();

    void setDeadzone(int percent);
    void setResponseCurve(double curve);
    void setPollingRate(int hz);
    int  getPollingRate() const { return poll_hz_.load(); }
    void setMouseEmulationSpeed(double factor) { mouse_emu_speed_ = factor; }
    void setStreamingActive(bool active)       { streaming_active_.store(active); }
    void setOverlayVisible(bool visible)       { overlay_visible_.store(visible); }

    int getConnectedCount() const;
    bool isPolling() const { return poll_running_.load(); }
    bool isSlotConnected(int slot) const { return slot >= 0 && slot < 8 ? prev_connected_[slot] : false; }

    // Filled by poll thread, read by gamepad method handler for getControllerInfo
    struct ControllerInfo {
        int  slot     = 0;
        bool connected= false;
        int  type     = 1;  // 1 = Xbox
    };

    // Callbacks into Dart (set by GamepadMethodHandler at startup)
    std::function<void(int)> onControllerConnected;
    std::function<void(int)> onControllerDisconnected;

    // Called by ComboDetector (dpad navigation while overlay is open)
    void setOverlayDpadCallback(std::function<void(const std::string&)> cb) {
        overlay_dpad_cb_ = std::move(cb);
    }

    // Called when not streaming — fires UI nav events to Dart (D-Pad, A, B)
    void setNavInputCallback(std::function<void(const std::string&)> cb) {
        nav_input_cb_ = std::move(cb);
    }

private:
    XInputHandler() = default;
    ~XInputHandler() { stopPolling(); }

    void pollLoop();
    void dispatchSlotOverlayAndNav(int slot, int liButtons);
    void sendSlotIfChanged(
        int slot, short activeMask, uint8_t controllerType, short capabilities,
        int supportedButtons, int liButtons, uint8_t lt, uint8_t rt,
        int16_t lx, int16_t ly, int16_t rx, int16_t ry);

    struct SentControllerState {
        bool     valid = false;
        short    activeMask = 0;
        int      buttons = 0;
        uint8_t  lt = 0;
        uint8_t  rt = 0;
        int16_t  lx = 0;
        int16_t  ly = 0;
        int16_t  rx = 0;
        int16_t  ry = 0;
        uint64_t lastSentMs = 0;
    };

    std::thread       poll_thread_;
    std::atomic<bool> poll_running_{false};
    std::atomic<bool> streaming_active_{false};
    std::atomic<bool> overlay_visible_{false};
    std::atomic<int>  poll_hz_{500};

    int    deadzone_percent_  = 10;
    double response_curve_    = 1.0;
    double mouse_emu_speed_   = 1.0;

    // Previous raw and Moonlight button state per slot (0-3 XInput, 4-7 WGI)
    uint32_t prev_buttons_[8] = {};
    uint32_t prev_li_buttons_[8] = {};
    bool     prev_connected_[8] = {};
    bool     arrival_sent_[8] = {};
    SentControllerState last_sent_[8] = {};

    std::function<void(const std::string&)> overlay_dpad_cb_;
    std::function<void(const std::string&)> nav_input_cb_;
};

}  // namespace input
}  // namespace jujostream
