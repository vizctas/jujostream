/**
 * event_emitter.cpp
 */
#include "event_emitter.h"

namespace jujostream {

EventEmitter &EventEmitter::instance() {
    static EventEmitter inst;
    return inst;
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

void EventEmitter::emitEvent(const flutter::EncodableMap &event) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (sink_) {
        sink_->Success(flutter::EncodableValue(event));
    }
}

void EventEmitter::emitConnectionStarted() {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")] = flutter::EncodableValue("connectionStarted");
    emitEvent(m);
}

void EventEmitter::emitConnectionTerminated(int errorCode) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]      = flutter::EncodableValue("connectionTerminated");
    m[flutter::EncodableValue("errorCode")] = flutter::EncodableValue(errorCode);
    emitEvent(m);
}

void EventEmitter::emitStageStarting(int stage, const std::string &stageName) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]      = flutter::EncodableValue("stageStarting");
    m[flutter::EncodableValue("stage")]     = flutter::EncodableValue(stage);
    m[flutter::EncodableValue("stageName")] = flutter::EncodableValue(stageName);
    emitEvent(m);
}

void EventEmitter::emitStageComplete(int stage) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]  = flutter::EncodableValue("stageComplete");
    m[flutter::EncodableValue("stage")] = flutter::EncodableValue(stage);
    emitEvent(m);
}

void EventEmitter::emitStageFailed(int stage, int errorCode, const std::string &stageName) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]      = flutter::EncodableValue("stageFailed");
    m[flutter::EncodableValue("stage")]     = flutter::EncodableValue(stage);
    m[flutter::EncodableValue("errorCode")] = flutter::EncodableValue(errorCode);
    m[flutter::EncodableValue("stageName")] = flutter::EncodableValue(stageName);
    emitEvent(m);
}

void EventEmitter::emitConnectionStatusUpdate(int status) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]   = flutter::EncodableValue("connectionStatusUpdate");
    m[flutter::EncodableValue("status")] = flutter::EncodableValue(status);
    emitEvent(m);
}

void EventEmitter::emitRumble(int controllerNumber, int lowFreq, int highFreq) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]             = flutter::EncodableValue("rumble");
    m[flutter::EncodableValue("controllerNumber")] = flutter::EncodableValue(controllerNumber);
    m[flutter::EncodableValue("lowFreqMotor")]     = flutter::EncodableValue(lowFreq);
    m[flutter::EncodableValue("highFreqMotor")]    = flutter::EncodableValue(highFreq);
    emitEvent(m);
}

void EventEmitter::emitRumbleTriggers(int controllerNumber, int left, int right) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]             = flutter::EncodableValue("rumbleTriggers");
    m[flutter::EncodableValue("controllerNumber")] = flutter::EncodableValue(controllerNumber);
    m[flutter::EncodableValue("leftTrigger")]      = flutter::EncodableValue(left);
    m[flutter::EncodableValue("rightTrigger")]     = flutter::EncodableValue(right);
    emitEvent(m);
}

void EventEmitter::emitSetHdrMode(bool enabled) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("type")]    = flutter::EncodableValue("hdrMode");
    m[flutter::EncodableValue("enabled")] = flutter::EncodableValue(enabled);
    emitEvent(m);
}

void EventEmitter::emitStats(const flutter::EncodableMap &stats) {
    emitEvent(stats);
}

}  // namespace jujostream
