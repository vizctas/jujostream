/**
 * gamepad_method_handler.h — Dispatches gamepad MethodChannel calls.
 */
#pragma once

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

namespace jujostream {

class GamepadMethodHandler {
public:
    static GamepadMethodHandler &instance();

    void handleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue> &call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // For Native→Dart invocations (onComboDetected, onOverlayDpad, etc.)
    void setChannel(flutter::MethodChannel<flutter::EncodableValue> *channel);
    void takeChannelOwnership(
        std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);

    // Native→Dart callbacks
    void invokeComboDetected();
    void invokeOverlayDpad(const std::string &direction);
    void invokeMouseModeToggle();
    void invokeControllerConnected(int slot);
    void invokeControllerDisconnected(int slot);

private:
    GamepadMethodHandler() = default;
    void wireCallbacks();  // wires XInput/Combo callbacks → Dart
    flutter::MethodChannel<flutter::EncodableValue> *channel_ = nullptr;
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> owned_channel_;
};

}  // namespace jujostream
