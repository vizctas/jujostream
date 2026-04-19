/**
 * method_handler.h
 *
 * Dispatches all MethodChannel calls for the streaming plugin.
 */
#pragma once

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

namespace jujostream {

class MethodHandler {
public:
    static MethodHandler &instance();

    void handleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue> &call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

private:
    MethodHandler() = default;

    void handleStartStream(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleStopStream(
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleGetTextureId(
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleSendMouseMove(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleSendMousePosition(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleSendMouseButton(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleSendKeyboard(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleSendScroll(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleSendHighResHScroll(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleSendGamepadInput(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleSendControllerArrival(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleSendTouchEvent(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleSendUtf8Text(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleGetStats(
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void handleProbeCodec(const flutter::EncodableValue *args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace jujostream
