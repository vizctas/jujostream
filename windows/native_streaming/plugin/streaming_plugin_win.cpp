/**
 * streaming_plugin_win.cpp
 *
 * Entry point: registers streaming MethodChannel + EventChannel.
 */
#include "streaming_plugin_win.h"
#include "method_handler.h"
#include "event_emitter.h"
#include "streaming_bridge_win.h"

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>

namespace jujostream {

static const char *kMethodChannelName = "com.limelight.jujostream/streaming";
static const char *kEventChannelName  = "com.limelight.jujostream/streaming_stats";

void StreamingPluginRegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {

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
