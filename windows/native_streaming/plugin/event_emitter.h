/**
 * event_emitter.h
 *
 * Manages the EventSink for streaming_stats EventChannel.
 * Thread-safe: callbacks from moonlight threads can emit events.
 */
#pragma once

#include <flutter/event_channel.h>
#include <flutter/standard_method_codec.h>
#include <mutex>
#include <memory>

namespace jujostream {

class EventEmitter {
public:
    static EventEmitter &instance();

    void setEventSink(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);
    void clearEventSink();

    // Thread-safe event emission
    void emitEvent(const flutter::EncodableMap &event);

    // Convenience helpers for common events
    void emitConnectionStarted();
    void emitConnectionTerminated(int errorCode);
    void emitStageStarting(int stage, const std::string &stageName);
    void emitStageComplete(int stage);
    void emitStageFailed(int stage, int errorCode, const std::string &stageName);
    void emitConnectionStatusUpdate(int status);
    void emitRumble(int controllerNumber, int lowFreq, int highFreq);
    void emitRumbleTriggers(int controllerNumber, int left, int right);
    void emitSetHdrMode(bool enabled);
    void emitStats(const flutter::EncodableMap &stats);

private:
    EventEmitter() = default;
    std::mutex mutex_;
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
};

}  // namespace jujostream
