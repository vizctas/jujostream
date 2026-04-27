/**
 * streaming_plugin_win.cpp
 *
 * Entry point: registers streaming MethodChannel + EventChannel.
 *
 * Threading contract:
 *   - This file runs entirely on the Flutter platform (Win32 main) thread.
 *   - EventEmitter marshals moonlight background callbacks to this thread
 *     via PostThreadMessage + a Win32 message hook registered here.
 */
#include "streaming_plugin_win.h"
#include "method_handler.h"
#include "event_emitter.h"
#include "streaming_bridge_win.h"

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>
#include <windows.h>

extern "C" {
#include "moonlight_bridge_win.h"
}

namespace jujostream {

static const char *kMethodChannelName = "com.limelight.jujostream/streaming";
static const char *kEventChannelName  = "com.limelight.jujostream/streaming_stats";

// Custom Win32 message to drain pending EventEmitter events on the platform thread.
static constexpr UINT WM_JUJO_DRAIN_EVENTS = WM_APP + 0x42;

// Win32 sub-class message hook installed on the Flutter host window.
static WNDPROC g_originalWndProc = nullptr;
static HWND    g_hookHwnd        = nullptr;

static LRESULT CALLBACK JujoWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == WM_JUJO_DRAIN_EVENTS) {
        EventEmitter::instance().drainPendingEvents();
        return 0;
    }
    return CallWindowProcW(g_originalWndProc, hwnd, msg, wParam, lParam);
}

void StreamingPluginRegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {

    moonlightWinInitNetworking();

    // Tell EventEmitter which thread is the platform thread so it can post
    // WM_JUJO_DRAIN_EVENTS to wake us up from background moonlight threads.
    EventEmitter::instance().setPlatformThreadId(GetCurrentThreadId());

    // Install a Win32 WndProc hook on the Flutter host window so we can
    // intercept WM_JUJO_DRAIN_EVENTS and drain the event queue on the
    // platform thread.
    g_hookHwnd = registrar->GetView()->GetNativeWindow();
    if (g_hookHwnd) {
        g_originalWndProc = reinterpret_cast<WNDPROC>(
            SetWindowLongPtrW(g_hookHwnd, GWLP_WNDPROC,
                              reinterpret_cast<LONG_PTR>(JujoWndProc)));
    }

    auto messenger = registrar->messenger();

    // Method channel
    auto method_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, kMethodChannelName,
        &flutter::StandardMethodCodec::GetInstance());

    // Event channel
    auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        messenger, kEventChannelName,
        &flutter::StandardMethodCodec::GetInstance());

    // Initialize singleton bridge with texture registrar
    auto *texture_registrar = registrar->texture_registrar();
    StreamingBridgeWin::instance().initialize(texture_registrar);

    // Wire method handler
    auto &handler = MethodHandler::instance();
    method_channel->SetMethodCallHandler(
        [&handler](const flutter::MethodCall<flutter::EncodableValue> &call,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            handler.handleMethodCall(call, std::move(result));
        });

    // Wire event emitter — extract lambdas to explicit types first (MSVC C3536 workaround)
    auto &emitter = EventEmitter::instance();
    flutter::StreamHandlerListen<flutter::EncodableValue> on_listen =
        [&emitter](const flutter::EncodableValue *arguments,
                   std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            emitter.setEventSink(std::move(events));
            return nullptr;
        };
    flutter::StreamHandlerCancel<flutter::EncodableValue> on_cancel =
        [&emitter](const flutter::EncodableValue *arguments)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            emitter.clearEventSink();
            return nullptr;
        };
    auto stream_handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        std::move(on_listen), std::move(on_cancel));
    event_channel->SetStreamHandler(std::move(stream_handler));
}

}  // namespace jujostream
