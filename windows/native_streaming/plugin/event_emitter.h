/**
 * event_emitter.h
 *
 * Thread-safe EventChannel emitter for streaming_stats.
 *
 * moonlight-common-c fires all connection callbacks on its own internal threads,
 * never on the Flutter platform thread.  Flutter's EventChannel sink MUST be
 * called on the platform thread or it will crash with:
 *   "channel sent a message from native to Flutter on a non-platform thread"
 *
 * Solution: background threads enqueue events into a lock-protected queue and
 * signal a hidden Win32 HWND via PostMessage.  The HWND's WndProc runs on the
 * platform (main UI) thread, dequeues all pending events, and calls the sink.
 */
#pragma once

#include <flutter/event_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <mutex>
#include <memory>
#include <deque>

namespace jujostream {

class EventEmitter {
public:
    static EventEmitter &instance();

    // Called from platform thread (plugin register).
    void setPlatformThreadId(DWORD threadId);

    void setEventSink(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);
    void clearEventSink();

    // Safe to call from any thread — posts to the platform thread.
    void emitEvent(flutter::EncodableMap event);

    // Convenience helpers — all thread-safe.
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

    // Called by the platform thread to drain the pending queue into the sink.
    void drainPendingEvents();

private:
    EventEmitter() = default;

    std::mutex mutex_;
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;

    // Cross-thread pending queue
    std::mutex queue_mutex_;
    std::deque<flutter::EncodableMap> pending_;

    DWORD platform_thread_id_ = 0;
};

}  // namespace jujostream
