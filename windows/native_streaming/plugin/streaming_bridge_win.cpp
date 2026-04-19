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
#include "../input/wgi_handler.h"

extern "C" {
#include "moonlight_bridge_win.h"
}

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
    // Initialize GPU texture bridge first (registers with Flutter)
    auto &tb = video::TextureBridge::instance();
    if (!tb.initialize(texture_registrar_, width, height)) {
        fprintf(stderr, "StreamingBridgeWin: TextureBridge init failed\n");
        return false;
    }

    // Initialize MFT decoder, wire decoded frames to TextureBridge
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
    Stats s;
    s.fps           = dec.fps();
    s.decodeTimeMs  = static_cast<int>(dec.avgDecodeMsEma());
    s.framesDecoded = dec.framesDecoded();
    s.framesDropped = dec.framesDropped();
    return s;
}

// --- C callback trampolines ---

static int onVideoSetup(int videoFormat, int width, int height, int redrawRate) {
    fprintf(stderr, "StreamingBridgeWin: videoSetup fmt=%d %dx%d@%d\n",
            videoFormat, width, height, redrawRate);
    return StreamingBridgeWin::instance().initVideo(videoFormat, width, height, redrawRate)
           ? 0 : -1;
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
    const int channels = (audioConfig & 0xFF) > 0 ? (audioConfig & 0xFF) : 2;
    return audio::WasapiRenderer::instance().initialize(channels, sampleRate, samplesPerFrame)
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
    EventEmitter::instance().emitConnectionStarted();
}

static void onConnectionTerminated(int errorCode) {
    StreamingBridgeWin::instance().setStreaming(false);
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
