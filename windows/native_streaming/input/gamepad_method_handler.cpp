/**
 * gamepad_method_handler.cpp
 *
 * Wires all Dart gamepad MethodChannel calls to real XInput/WGI/Combo subsystems.
 * Also wires combo/connect callbacks back to Dart.
 */
#include "gamepad_method_handler.h"
#include "xinput_handler.h"
#include "combo_detector.h"
#include "wgi_handler.h"

#include <cstdio>

namespace jujostream {

static int getInt(const flutter::EncodableMap &m, const std::string &key, int def = 0) {
    auto it = m.find(flutter::EncodableValue(key));
    if (it == m.end()) return def;
    if (auto *v = std::get_if<int32_t>(&it->second)) return *v;
    if (auto *v = std::get_if<int64_t>(&it->second)) return static_cast<int>(*v);
    return def;
}

static bool getBool(const flutter::EncodableMap &m, const std::string &key, bool def = false) {
    auto it = m.find(flutter::EncodableValue(key));
    if (it == m.end()) return def;
    if (auto *v = std::get_if<bool>(&it->second)) return *v;
    return def;
}

static double getDouble(const flutter::EncodableMap &m, const std::string &key, double def = 0.0) {
    auto it = m.find(flutter::EncodableValue(key));
    if (it == m.end()) return def;
    if (auto *v = std::get_if<double>(&it->second)) return *v;
    if (auto *v = std::get_if<int32_t>(&it->second)) return (double)*v;
    return def;
}

// -------------------------------------------------------------------

GamepadMethodHandler &GamepadMethodHandler::instance() {
    static GamepadMethodHandler inst;
    return inst;
}

void GamepadMethodHandler::setChannel(
    flutter::MethodChannel<flutter::EncodableValue> *channel) {
    channel_ = channel;
    wireCallbacks();
}

void GamepadMethodHandler::takeChannelOwnership(
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel) {
    owned_channel_ = std::move(channel);
    channel_       = owned_channel_.get();
    wireCallbacks();
}

// Wire XInput/Combo callbacks → Dart invoke calls
void GamepadMethodHandler::wireCallbacks() {
    auto &xi = input::XInputHandler::instance();
    auto &cd = input::ComboDetector::instance();

    // Combo → overlay open
    cd.onComboDetected = [this]() { invokeComboDetected(); };

    // Mouse mode toggle
    cd.onMouseModeToggle = [this]() { invokeMouseModeToggle(); };

    // Dpad navigation while overlay is visible
    xi.setOverlayDpadCallback([this](const std::string &dir) { invokeOverlayDpad(dir); });

    // UI navigation when NOT streaming (D-Pad + A/B → Dart focus system)
    xi.setNavInputCallback([this](const std::string &key) { invokeNavInput(key); });

    // Controller connect/disconnect
    xi.onControllerConnected    = [this](int s){ invokeControllerConnected(s); };
    xi.onControllerDisconnected = [this](int s){ invokeControllerDisconnected(s); };
}

// -------------------------------------------------------------------

void GamepadMethodHandler::handleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    const auto &m  = call.method_name();
    const auto *pArgs = call.arguments();
    const flutter::EncodableMap *args = pArgs
        ? std::get_if<flutter::EncodableMap>(pArgs) : nullptr;

    if (m == "setStreamingActive") {
        bool active = args ? getBool(*args, "active", false) : false;
        auto &xi = input::XInputHandler::instance();
        xi.setStreamingActive(active);
        // NEVER stop polling when streaming ends — the thread must stay alive
        // so that D-Pad/A/B inputs continue to fire Dart UI navigation events.
        // Start it only if it hasn't been started yet.
        if (!xi.isPolling()) xi.startPolling();
        result->Success(flutter::EncodableValue(xi.getConnectedCount()));

    } else if (m == "setOverlayVisible") {
        bool visible = args ? getBool(*args, "visible", false) : false;
        input::XInputHandler::instance().setOverlayVisible(visible);
        result->Success();

    } else if (m == "getConnectedGamepadCount") {
        result->Success(flutter::EncodableValue(
            input::XInputHandler::instance().getConnectedCount()));

    } else if (m == "redetectControllers") {
        result->Success(flutter::EncodableValue(
            input::XInputHandler::instance().getConnectedCount()));

    } else if (m == "setDeadzone") {
        if (args) input::XInputHandler::instance().setDeadzone(getInt(*args, "percent", 10));
        result->Success();

    } else if (m == "setResponseCurve") {
        if (args) input::XInputHandler::instance().setResponseCurve(getDouble(*args, "curve", 1.0));
        result->Success();

    } else if (m == "setMouseEmulationSpeed") {
        if (args) input::XInputHandler::instance().setMouseEmulationSpeed(
            getDouble(*args, "factor", 1.0));
        result->Success();

    } else if (m == "setRumbleConfig") {
        // WGI init is cheap and safe to call multiple times
        bool enabled = args ? getBool(*args, "enabled", true) : true;
        if (enabled && !input::WgiHandler::instance().isInitialized()) {
            input::WgiHandler::instance().initialize();
        }
        result->Success();

    } else if (m == "setOverlayTriggerConfig") {
        if (args) {
            int combo  = getInt(*args, "combo", 0);
            int holdMs = getInt(*args, "holdMs", 1500);
            input::ComboDetector::instance().setOverlayCombo(combo, holdMs);
        }
        result->Success();

    } else if (m == "setMouseModeConfig") {
        if (args) {
            int combo  = getInt(*args, "combo", 0);
            int holdMs = getInt(*args, "holdMs", 1500);
            input::ComboDetector::instance().setMouseModeCombo(combo, holdMs);
        }
        result->Success();

    } else if (m == "getControllerInfo") {
        flutter::EncodableList list;
        for (int i = 0; i < 8; ++i) {
            bool connected = input::XInputHandler::instance().isSlotConnected(i);
            flutter::EncodableMap info;
            info[flutter::EncodableValue("slot")]      = flutter::EncodableValue(i);
            info[flutter::EncodableValue("type")]      = flutter::EncodableValue(i < 4 ? 1 : 2); // 1=Xbox, 2=Generic/PS
            info[flutter::EncodableValue("connected")] = flutter::EncodableValue(connected);
            list.push_back(flutter::EncodableValue(info));
        }
        result->Success(flutter::EncodableValue(list));

    } else if (m == "setMouseEmulation") {
        result->Success();
    } else if (m == "getMouseEmulation") {
        result->Success(flutter::EncodableValue(false));

    // Accept-without-error: settings pushed but not needed on Windows
    } else if (m == "setTouchpadAsMouse" || m == "setMotionSensors" ||
               m == "setControllerPreferences" || m == "setInputPreferences" ||
               m == "setButtonRemap" || m == "setMouseSensitivity" ||
               m == "setScrollSensitivity" || m == "setTriggerDeadzone") {
        result->Success();

    } else {
        result->NotImplemented();
    }
}

// --- Main thread dispatch ---

void GamepadMethodHandler::drainQueue() {
    std::vector<std::function<void()>> local_queue;
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        local_queue.swap(task_queue_);
    }
    for (auto &task : local_queue) {
        task();
    }
}

void GamepadMethodHandler::dispatchToMainThread(std::function<void()> task) {
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        task_queue_.push_back(std::move(task));
    }
    // WM_APP + 100 will be hooked in plugin registration
    if (hwnd_) {
        PostMessage(hwnd_, WM_APP + 100, 0, 0);
    }
}


// --- Native→Dart invocations ---

void GamepadMethodHandler::invokeComboDetected() {
    dispatchToMainThread([this]() {
        if (channel_) channel_->InvokeMethod("onComboDetected", nullptr);
    });
}

void GamepadMethodHandler::invokeOverlayDpad(const std::string &direction) {
    dispatchToMainThread([this, direction]() {
        if (channel_) channel_->InvokeMethod("onOverlayDpad",
            std::make_unique<flutter::EncodableValue>(direction));
    });
}

void GamepadMethodHandler::invokeMouseModeToggle() {
    dispatchToMainThread([this]() {
        if (channel_) channel_->InvokeMethod("onMouseModeToggle", nullptr);
    });
}

void GamepadMethodHandler::invokeControllerConnected(int slot) {
    dispatchToMainThread([this, slot]() {
        if (!channel_) return;
        flutter::EncodableMap args;
        args[flutter::EncodableValue("slot")] = flutter::EncodableValue(slot);
        channel_->InvokeMethod("onControllerConnected",
            std::make_unique<flutter::EncodableValue>(args));
    });
}

void GamepadMethodHandler::invokeControllerDisconnected(int slot) {
    dispatchToMainThread([this, slot]() {
        if (!channel_) return;
        flutter::EncodableMap args;
        args[flutter::EncodableValue("slot")] = flutter::EncodableValue(slot);
        channel_->InvokeMethod("onControllerDisconnected",
            std::make_unique<flutter::EncodableValue>(args));
    });
}

void GamepadMethodHandler::invokeNavInput(const std::string &key) {
    dispatchToMainThread([this, key]() {
        if (channel_) channel_->InvokeMethod("onNavInput",
            std::make_unique<flutter::EncodableValue>(key));
    });
}

}  // namespace jujostream
