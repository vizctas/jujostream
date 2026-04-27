/**
 * event_emitter.cpp
 *
 * Thread-safe event emission via Win32 PostThreadMessage to marshal
 * moonlight-common-c callbacks (background threads) onto the Flutter
 * platform thread before calling the EventChannel sink.
 */
#include "event_emitter.h"
#include <cstdio>

namespace jujostream {

// Custom WM message for "drain pending events"
static constexpr UINT WM_JUJO_DRAIN_EVENTS = WM_APP + 0x42;

EventEmitter &EventEmitter::instance() {
    static EventEmitter inst;
    return inst;
}

void EventEmitter::setPlatformThreadId(DWORD threadId) {
    platform_thread_id_ = threadId;
}

void EventEmitter::setEventSink(
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
    std::lock_guard<std::mutex> lock(mutex_);
    sink_ = std::move(sink);
}

void EventEmitter::clearEventSink() {
    std::lock_guard<std::mutex> lock(mutex_);
    sink_.reset();
}

// Called from ANY thread — enqueues and wakes the platform thread.
void EventEmitter::emitEvent(flutter::EncodableMap event) {
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        pending_.push_back(std::move(event));
    }

    if (platform_thread_id_ != 0) {
        // PostThreadMessage is safe from any thread and doesn't require a HWND.
        // The Flutter Win32 event loop processes WM messages — our WndProc hook
        // (set up in streaming_plugin_win.cpp) intercepts WM_JUJO_DRAIN_EVENTS.
        PostThreadMessageW(platform_thread_id_, WM_JUJO_DRAIN_EVENTS, 0, 0);
    }
}

// Called by the platform thread Win32 message hook to flush the queue.
void EventEmitter::drainPendingEvents() {
    std::deque<flutter::EncodableMap> local;
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        local.swap(pending_);
    }

    std::lock_guard<std::mutex> lock(mutex_);
    if (!sink_) return;
    for (auto &ev : local) {
        sink_->Success(flutter::EncodableValue(ev));
    }
}

// ---------------------------------------------------------------------------
// Convenience helpers
// ---------------------------------------------------------------------------

void EventEmitter::emitConnectionStarted() {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")] = flutter::EncodableValue("connectionStarted");
    emitEvent(std::move(m));
}

void EventEmitter::emitConnectionTerminated(int errorCode) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]      = flutter::EncodableValue("connectionTerminated");
    m[flutter::EncodableValue("errorCode")] = flutter::EncodableValue(errorCode);
    emitEvent(std::move(m));
}

void EventEmitter::emitStageStarting(int stage, const std::string &stageName) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]      = flutter::EncodableValue("stageStarting");
    m[flutter::EncodableValue("stage")]     = flutter::EncodableValue(stage);
    m[flutter::EncodableValue("stageName")] = flutter::EncodableValue(stageName);
    emitEvent(std::move(m));
}

void EventEmitter::emitStageComplete(int stage) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]  = flutter::EncodableValue("stageComplete");
    m[flutter::EncodableValue("stage")] = flutter::EncodableValue(stage);
    emitEvent(std::move(m));
}

void EventEmitter::emitStageFailed(int stage, int errorCode, const std::string &stageName) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]      = flutter::EncodableValue("stageFailed");
    m[flutter::EncodableValue("stage")]     = flutter::EncodableValue(stage);
    m[flutter::EncodableValue("errorCode")] = flutter::EncodableValue(errorCode);
    m[flutter::EncodableValue("stageName")] = flutter::EncodableValue(stageName);
    emitEvent(std::move(m));
}

void EventEmitter::emitConnectionStatusUpdate(int status) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]   = flutter::EncodableValue("connectionStatusUpdate");
    m[flutter::EncodableValue("status")] = flutter::EncodableValue(status);
    emitEvent(std::move(m));
}

void EventEmitter::emitRumble(int controllerNumber, int lowFreq, int highFreq) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]             = flutter::EncodableValue("rumble");
    m[flutter::EncodableValue("controllerNumber")] = flutter::EncodableValue(controllerNumber);
    m[flutter::EncodableValue("lowFreqMotor")]     = flutter::EncodableValue(lowFreq);
    m[flutter::EncodableValue("highFreqMotor")]    = flutter::EncodableValue(highFreq);
    emitEvent(std::move(m));
}

void EventEmitter::emitRumbleTriggers(int controllerNumber, int left, int right) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]             = flutter::EncodableValue("rumbleTriggers");
    m[flutter::EncodableValue("controllerNumber")] = flutter::EncodableValue(controllerNumber);
    m[flutter::EncodableValue("leftTrigger")]      = flutter::EncodableValue(left);
    m[flutter::EncodableValue("rightTrigger")]     = flutter::EncodableValue(right);
    emitEvent(std::move(m));
}

void EventEmitter::emitSetHdrMode(bool enabled) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]    = flutter::EncodableValue("hdrMode");
    m[flutter::EncodableValue("enabled")] = flutter::EncodableValue(enabled);
    emitEvent(std::move(m));
}

void EventEmitter::emitStats(const flutter::EncodableMap &stats) {
    emitEvent(flutter::EncodableMap(stats));
}

}  // namespace jujostream
