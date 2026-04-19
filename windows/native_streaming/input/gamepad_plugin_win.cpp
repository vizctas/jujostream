/**
 * gamepad_plugin_win.cpp — Registers gamepad MethodChannel.
 */
#include "gamepad_plugin_win.h"
#include "gamepad_method_handler.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

namespace jujostream {

static const char *kGamepadChannelName = "com.jujostream/gamepad";

void GamepadPluginRegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {

    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), kGamepadChannelName,
        &flutter::StandardMethodCodec::GetInstance());

    auto &handler = GamepadMethodHandler::instance();

    // Store channel reference for Native→Dart calls
    handler.setChannel(channel.get());

    channel->SetMethodCallHandler(
        [&handler](const flutter::MethodCall<flutter::EncodableValue> &call,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            handler.handleMethodCall(call, std::move(result));
        });

    // Channel must outlive the handler — transfer ownership
    handler.takeChannelOwnership(std::move(channel));
}

}  // namespace jujostream
