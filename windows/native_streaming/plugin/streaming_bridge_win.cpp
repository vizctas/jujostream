/**
 * streaming_bridge_win.cpp
 *
 * Singleton orchestrator. Registers C callback table, owns decoder + audio + texture.
 */
#include "streaming_bridge_win.h"
#include "event_emitter.h"
#include "../audio/wasapi_renderer.h"
#include "../video/mft_decoder.h"
#include "../video/texture_bridge.h"
#include "../video/d3d11_device.h"
#include "../input/wgi_handler.h"

extern "C" {
#include "moonlight_bridge_win.h"
}

#include <flutter/standard_method_codec.h>
#include <chrono>
#include <cstdio>

namespace jujostream {

StreamingBridgeWin &StreamingBridgeWin::instance() {
    static StreamingBridgeWin inst;
    return inst;
}

void StreamingBridgeWin::initialize(flutter::TextureRegistrar *texture_registrar) {
    texture_registrar_ = texture_registrar;
    registerCBridgeCallbacks();
}

int64_t StreamingBridgeWin::getTextureId() const {
    return video::TextureBridge::instance().textureId();
}

bool StreamingBridgeWin::initVideo(int videoFormat, int width, int height, int fps) {
    // 1. D3D11Device MUST come first — TextureBridge and MftDecoder both depend on it.
    auto &d3d = video::D3D11Device::instance();
    if (!d3d.isInitialized()) {
        if (!d3d.initialize()) {
            fprintf(stderr, "StreamingBridgeWin: D3D11Device init failed\n");
            return false;
        }
    }

    // 2. Initialize GPU texture bridge (registers with Flutter compositor)
    auto &tb = video::TextureBridge::instance();
    if (!tb.initialize(texture_registrar_, width, height)) {
        fprintf(stderr, "StreamingBridgeWin: TextureBridge init failed\n");
        return false;
    }

    // 3. Initialize MFT decoder, wire decoded frames to TextureBridge
    auto &dec = video::MftDecoder::instance();
    bool ok = dec.initialize(videoFormat, width, height, fps,
        [](const video::DecodedFrame &frame) {
            video::TextureBridge::instance().onFrame(frame);
        });

    if (!ok) {
        fprintf(stderr, "StreamingBridgeWin: MftDecoder init failed\n");
        tb.shutdown();
        return false;
    }
    return true;
}

StreamingBridgeWin::Stats StreamingBridgeWin::getVideoStats() const {
    auto &dec = video::MftDecoder::instance();
    auto &tb = video::TextureBridge::instance();
    auto dt = dec.telemetry();
    auto ts = tb.stats();
    Stats s;
    s.fps           = dec.fps();
    s.decodeTimeMs  = static_cast<int>(dec.avgDecodeMsEma());
    s.framesDecoded = dec.framesDecoded();
    s.framesDropped = dec.framesDropped();
    s.codec = dec.codecName();
    s.isSoftwareDecoder = dec.isSoftware();
    s.packetsSubmitted = dt.packetsSubmitted;
    s.bytesSubmitted = dt.bytesSubmitted;
    s.inputsAccepted = dt.inputsAccepted;
    s.idrFrames = dt.idrFrames;
    s.outputSamples = dt.outputSamples;
    s.dxgiFrames = dt.dxgiFrames;
    s.dxgiMisses = dt.dxgiMisses;
    s.processInputFailures = dt.processInputFailures;
    s.processOutputFailures = dt.processOutputFailures;
    s.streamChanges = dt.streamChanges;
    s.textureBlits = ts.blits;
    s.textureBlitFailures = ts.blitFailures;
    s.textureFrameNotifications = ts.frameNotifications;
    s.textureDescriptorCallbacks = ts.descriptorCallbacks;
    s.textureNullDescriptorCallbacks = ts.nullDescriptorCallbacks;
    return s;
}

void StreamingBridgeWin::startStatsEmitter() {
    bool expected = false;
    if (!stats_running_.compare_exchange_strong(expected, true)) return;
    stats_thread_ = std::thread(&StreamingBridgeWin::statsLoop, this);
}

void StreamingBridgeWin::stopStatsEmitter() {
    stats_running_.store(false);
    if (stats_thread_.joinable()) stats_thread_.join();
}

void StreamingBridgeWin::statsLoop() {
    using namespace std::chrono_literals;
    while (stats_running_.load()) {
        std::this_thread::sleep_for(1000ms);
        if (!stats_running_.load() || !isStreaming()) continue;

        auto vs = getVideoStats();
        auto as = audio::WasapiRenderer::instance().stats();

        flutter::EncodableMap stats;
        stats[flutter::EncodableValue("type")] = flutter::EncodableValue("stats");
        stats[flutter::EncodableValue("platform")] = flutter::EncodableValue(std::string("windows"));
        stats[flutter::EncodableValue("fps")] = flutter::EncodableValue(vs.fps);
        stats[flutter::EncodableValue("decodeTime")] = flutter::EncodableValue(vs.decodeTimeMs);
        stats[flutter::EncodableValue("dropRate")] = flutter::EncodableValue(
            vs.framesDecoded + vs.framesDropped > 0
                ? (int)((vs.framesDropped * 100) / (vs.framesDecoded + vs.framesDropped))
                : 0);
        stats[flutter::EncodableValue("totalRendered")] = flutter::EncodableValue((int64_t)vs.framesDecoded);
        stats[flutter::EncodableValue("totalDropped")] = flutter::EncodableValue((int64_t)vs.framesDropped);
        stats[flutter::EncodableValue("codec")] = flutter::EncodableValue(vs.codec);
        stats[flutter::EncodableValue("isSoftwareDecoder")] = flutter::EncodableValue(vs.isSoftwareDecoder);
        stats[flutter::EncodableValue("packetsSubmitted")] = flutter::EncodableValue((int64_t)vs.packetsSubmitted);
        stats[flutter::EncodableValue("bytesSubmitted")] = flutter::EncodableValue((int64_t)vs.bytesSubmitted);
        stats[flutter::EncodableValue("inputsAccepted")] = flutter::EncodableValue((int64_t)vs.inputsAccepted);
        stats[flutter::EncodableValue("idrFrames")] = flutter::EncodableValue((int64_t)vs.idrFrames);
        stats[flutter::EncodableValue("outputSamples")] = flutter::EncodableValue((int64_t)vs.outputSamples);
        stats[flutter::EncodableValue("dxgiFrames")] = flutter::EncodableValue((int64_t)vs.dxgiFrames);
        stats[flutter::EncodableValue("dxgiMisses")] = flutter::EncodableValue((int64_t)vs.dxgiMisses);
        stats[flutter::EncodableValue("processInputFailures")] = flutter::EncodableValue((int64_t)vs.processInputFailures);
        stats[flutter::EncodableValue("processOutputFailures")] = flutter::EncodableValue((int64_t)vs.processOutputFailures);
        stats[flutter::EncodableValue("streamChanges")] = flutter::EncodableValue((int64_t)vs.streamChanges);
        stats[flutter::EncodableValue("textureBlits")] = flutter::EncodableValue((int64_t)vs.textureBlits);
        stats[flutter::EncodableValue("textureBlitFailures")] = flutter::EncodableValue((int64_t)vs.textureBlitFailures);
        stats[flutter::EncodableValue("textureFrameNotifications")] = flutter::EncodableValue((int64_t)vs.textureFrameNotifications);
        stats[flutter::EncodableValue("textureDescriptorCallbacks")] = flutter::EncodableValue((int64_t)vs.textureDescriptorCallbacks);
        stats[flutter::EncodableValue("textureNullDescriptorCallbacks")] = flutter::EncodableValue((int64_t)vs.textureNullDescriptorCallbacks);
        stats[flutter::EncodableValue("pendingAudioMs")] = flutter::EncodableValue(moonlightWinGetPendingAudioDuration());
        stats[flutter::EncodableValue("audioSubmittedSamples")] = flutter::EncodableValue((int64_t)as.submittedSamples);
        stats[flutter::EncodableValue("audioDroppedSamples")] = flutter::EncodableValue((int64_t)as.droppedSamples);
        stats[flutter::EncodableValue("audioUnderruns")] = flutter::EncodableValue((int64_t)as.underruns);
        stats[flutter::EncodableValue("audioReinitCount")] = flutter::EncodableValue((int64_t)as.reinitCount);
        stats[flutter::EncodableValue("audioChannels")] = flutter::EncodableValue(as.channels);
        stats[flutter::EncodableValue("audioSampleRate")] = flutter::EncodableValue(as.sampleRate);
        EventEmitter::instance().emitStats(stats);
    }
}

// --- C callback trampolines ---

static int onVideoSetup(int videoFormat, int width, int height, int redrawRate) {
    fprintf(stderr, "StreamingBridgeWin: videoSetup fmt=%d %dx%d@%d\n",
            videoFormat, width, height, redrawRate);
    // This callback fires on moonlight-common-c's video thread.
    // COM/MFT require the calling thread to have an initialized apartment.
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    int ret = StreamingBridgeWin::instance().initVideo(videoFormat, width, height, redrawRate)
              ? 0 : -1;
    // NOTE: Do NOT call CoUninitialize here — the MFT drain thread uses this
    // COM apartment. The thread exits via moonlight shutdown (LiStopConnection).
    return ret;
}

static void onVideoStart() {
    fprintf(stderr, "StreamingBridgeWin: videoStart\n");
}

static void onVideoStop() {
    fprintf(stderr, "StreamingBridgeWin: videoStop\n");
    video::MftDecoder::instance().shutdown();
}

static void onVideoCleanup() {
    fprintf(stderr, "StreamingBridgeWin: videoCleanup\n");
    video::TextureBridge::instance().shutdown();
}

static int onVideoFrame(const uint8_t *data, int length,
                         int frameType, int frameNumber,
                         int64_t receiveTimeMs) {
    return video::MftDecoder::instance().submitFrame(
        data, length, frameType, frameNumber, receiveTimeMs);
}

static int onAudioInit(int audioConfig, int sampleRate, int samplesPerFrame) {
    fprintf(stderr, "StreamingBridgeWin: audioInit config=0x%X rate=%d spf=%d\n",
            audioConfig, sampleRate, samplesPerFrame);
    // WASAPI requires a COM MTA apartment on the calling thread.
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    // CRITICAL FIX: CHANNEL_COUNT_FROM_AUDIO_CONFIGURATION = (audioConfig >> 8) & 0xFF
    // The low byte (audioConfig & 0xFF) is the 0xCA magic marker — NOT the channel count!
    const int channels    = (audioConfig >> 8) & 0xFF;
    const int channelMask = (audioConfig >> 16) & 0xFFFF;
    const int ch = (channels > 0) ? channels : 2;
    fprintf(stderr, "StreamingBridgeWin: audio channels=%d mask=0x%X\n", ch, channelMask);
    return audio::WasapiRenderer::instance().initialize(ch, sampleRate, samplesPerFrame)
           ? 0 : -1;
}

static void onAudioStart() {
    audio::WasapiRenderer::instance().start();
}

static void onAudioStop() {
    audio::WasapiRenderer::instance().stop();
}

static void onAudioCleanup() {
    audio::WasapiRenderer::instance().shutdown();
}

static void onAudioSample(const char *data, int length) {
    if (!data || length <= 0) return;
    const int16_t *pcm    = reinterpret_cast<const int16_t *>(data);
    const int      samples = length / static_cast<int>(sizeof(int16_t));
    audio::WasapiRenderer::instance().submitPcm(pcm, samples);
}

static void onConnectionStarted() {
    StreamingBridgeWin::instance().setStreaming(true);
    StreamingBridgeWin::instance().startStatsEmitter();
    EventEmitter::instance().emitConnectionStarted();
}

static void onConnectionTerminated(int errorCode) {
    StreamingBridgeWin::instance().setStreaming(false);
    StreamingBridgeWin::instance().stopStatsEmitter();
    EventEmitter::instance().emitConnectionTerminated(errorCode);
}

static void onStageStarting(int stage) {
    const char *name = moonlightWinGetStageName(stage);
    EventEmitter::instance().emitStageStarting(stage, name ? name : "");
}

static void onStageComplete(int stage) {
    EventEmitter::instance().emitStageComplete(stage);
}

static void onStageFailed(int stage, int errorCode) {
    const char *name = moonlightWinGetStageName(stage);
    EventEmitter::instance().emitStageFailed(stage, errorCode, name ? name : "");
}

static void onConnectionStatusUpdate(int status) {
    EventEmitter::instance().emitConnectionStatusUpdate(status);
}

static uint16_t g_rumbleLow[4] = {0};
static uint16_t g_rumbleHigh[4] = {0};
static uint16_t g_rumbleLT[4] = {0};
static uint16_t g_rumbleRT[4] = {0};

static void onRumble(uint16_t cn, uint16_t low, uint16_t high) {
    if (cn < 4) { g_rumbleLow[cn] = low; g_rumbleHigh[cn] = high; }
    input::WgiHandler::instance().setVibration(cn, low, high,
        cn < 4 ? g_rumbleLT[cn] : 0, cn < 4 ? g_rumbleRT[cn] : 0);
    EventEmitter::instance().emitRumble(cn, low, high);
}

static void onRumbleTriggers(uint16_t cn, uint16_t lt, uint16_t rt) {
    if (cn < 4) { g_rumbleLT[cn] = lt; g_rumbleRT[cn] = rt; }
    input::WgiHandler::instance().setVibration(cn,
        cn < 4 ? g_rumbleLow[cn] : 0, cn < 4 ? g_rumbleHigh[cn] : 0,
        lt, rt);
    EventEmitter::instance().emitRumbleTriggers(cn, lt, rt);
}

static void onSetMotionEventState(uint16_t /*cn*/, uint8_t /*mt*/, uint16_t /*hz*/) {}

static void onSetControllerLED(uint16_t /*cn*/, uint8_t /*r*/, uint8_t /*g*/, uint8_t /*b*/) {}

static void onSetHdrMode(bool enabled) {
    EventEmitter::instance().emitSetHdrMode(enabled);
}

void StreamingBridgeWin::registerCBridgeCallbacks() {
    JujostreamWinCallbacks cbs = {};
    cbs.onVideoSetup             = onVideoSetup;
    cbs.onVideoStart             = onVideoStart;
    cbs.onVideoStop              = onVideoStop;
    cbs.onVideoCleanup           = onVideoCleanup;
    cbs.onVideoFrame             = onVideoFrame;
    cbs.onAudioInit              = onAudioInit;
    cbs.onAudioStart             = onAudioStart;
    cbs.onAudioStop              = onAudioStop;
    cbs.onAudioCleanup           = onAudioCleanup;
    cbs.onAudioSample            = onAudioSample;
    cbs.onConnectionStarted      = onConnectionStarted;
    cbs.onConnectionTerminated   = onConnectionTerminated;
    cbs.onStageStarting          = onStageStarting;
    cbs.onStageComplete          = onStageComplete;
    cbs.onStageFailed            = onStageFailed;
    cbs.onConnectionStatusUpdate = onConnectionStatusUpdate;
    cbs.onRumble                 = onRumble;
    cbs.onRumbleTriggers         = onRumbleTriggers;
    cbs.onSetMotionEventState    = onSetMotionEventState;
    cbs.onSetControllerLED       = onSetControllerLED;
    cbs.onSetHdrMode             = onSetHdrMode;
    moonlightWinRegisterCallbacks(&cbs);
    fprintf(stderr, "StreamingBridgeWin: all callbacks registered\n");
}

}  // namespace jujostream
