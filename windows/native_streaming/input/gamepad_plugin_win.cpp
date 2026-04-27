/**
 * gamepad_plugin_win.cpp — Registers gamepad MethodChannel.
 */
#include "gamepad_plugin_win.h"
#include "gamepad_method_handler.h"
#include "xinput_handler.h"
#include "wgi_handler.h"

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

    HWND hwnd = registrar->GetView()->GetNativeWindow();
    if (hwnd) hwnd = GetAncestor(hwnd, GA_ROOT);
    handler.setHwnd(hwnd);

    registrar->RegisterTopLevelWindowProcDelegate(
        [&handler](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) -> std::optional<LRESULT> {
            if (message == WM_APP + 100) {
                handler.drainQueue();
                return 0;
            }
            return std::nullopt;
        });

    channel->SetMethodCallHandler(
        [&handler](const flutter::MethodCall<flutter::EncodableValue> &call,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            handler.handleMethodCall(call, std::move(result));
        });

    // Channel must outlive the handler — transfer ownership
    handler.takeChannelOwnership(std::move(channel));

    // Start polling immediately so UI nav events fire before the first stream session.
    input::WgiHandler::instance().initialize();
    input::XInputHandler::instance().startPolling();
}

}  // namespace jujostream
