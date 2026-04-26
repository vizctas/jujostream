/**
 * method_handler.cpp
 *
 * MethodChannel dispatcher for the streaming plugin.
 * All methods are fully wired to moonlight-common-c and subsystems.
 */
#include "method_handler.h"
#include "streaming_bridge_win.h"
#include "../video/codec_probe_win.h"
#include "../video/mft_decoder.h"
#include "../video/texture_bridge.h"
#include "../audio/wasapi_renderer.h"

#include <string>
#include <vector>
#include <cstring>
#include <thread>

extern "C" {
#include "moonlight_bridge_win.h"
}

namespace jujostream {

// --- Arg extraction helpers ---

static int getInt(const flutter::EncodableMap &m, const std::string &key, int def = 0) {
    auto it = m.find(flutter::EncodableValue(key));
    if (it == m.end()) return def;
    if (auto *v = std::get_if<int32_t>(&it->second)) return *v;
    if (auto *v = std::get_if<int64_t>(&it->second)) return static_cast<int>(*v);
    return def;
}

static bool getBool(const flutter::EncodableMap &m, const std::string &key, bool def = false) {
    auto it = m.find(flutter::EncodableValue(key));
    if (it == m.end()) return def;
    if (auto *v = std::get_if<bool>(&it->second)) return *v;
    return def;
}

static std::string getString(const flutter::EncodableMap &m, const std::string &key,
                              const std::string &def = "") {
    auto it = m.find(flutter::EncodableValue(key));
    if (it == m.end()) return def;
    if (auto *v = std::get_if<std::string>(&it->second)) return *v;
    return def;
}

static double getDouble(const flutter::EncodableMap &m, const std::string &key, double def = 0.0) {
    auto it = m.find(flutter::EncodableValue(key));
    if (it == m.end()) return def;
    if (auto *v = std::get_if<double>(&it->second)) return *v;
    if (auto *v = std::get_if<int32_t>(&it->second)) return (double)*v;
    return def;
}

// Decode hex string "aabbccdd..." to bytes (up to maxLen bytes)
static std::vector<uint8_t> hexToBytes(const std::string &hex, int maxLen) {
    std::vector<uint8_t> out;
    out.reserve(maxLen);
    for (int i = 0; i + 1 < (int)hex.size() && (int)out.size() < maxLen; i += 2) {
        out.push_back(static_cast<uint8_t>(std::stoi(hex.substr(i, 2), nullptr, 16)));
    }
    while ((int)out.size() < maxLen) out.push_back(0);
    return out;
}

// -------------------------------------------------------------------

MethodHandler &MethodHandler::instance() {
    static MethodHandler inst;
    return inst;
}

void MethodHandler::handleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    const auto &m = call.method_name();

    if      (m == "startStream")            handleStartStream(call.arguments(), std::move(result));
    else if (m == "stopStream")             handleStopStream(std::move(result));
    else if (m == "getTextureId")           handleGetTextureId(std::move(result));
    else if (m == "sendMouseMove")          handleSendMouseMove(call.arguments(), std::move(result));
    else if (m == "sendMousePosition")      handleSendMousePosition(call.arguments(), std::move(result));
    else if (m == "sendMouseButton")        handleSendMouseButton(call.arguments(), std::move(result));
    else if (m == "sendKeyboardInput")      handleSendKeyboard(call.arguments(), std::move(result));
    else if (m == "sendScroll")             handleSendScroll(call.arguments(), std::move(result));
    else if (m == "sendHighResHScroll")     handleSendHighResHScroll(call.arguments(), std::move(result));
    else if (m == "sendGamepadInput")       handleSendGamepadInput(call.arguments(), std::move(result));
    else if (m == "sendControllerArrival")  handleSendControllerArrival(call.arguments(), std::move(result));
    else if (m == "sendTouchEvent")         handleSendTouchEvent(call.arguments(), std::move(result));
    else if (m == "sendUtf8Text")           handleSendUtf8Text(call.arguments(), std::move(result));
    else if (m == "getStats")              handleGetStats(std::move(result));
    else if (m == "probeCodec")            handleProbeCodec(call.arguments(), std::move(result));
    else if (m == "isDirectSubmitActive")  result->Success(flutter::EncodableValue(false));
    else if (m == "enterPiP")             result->Success(flutter::EncodableValue(false));
    else                                   result->NotImplemented();
}

// -------------------------------------------------------------------
// startStream  — IMPORTANT: LiStartConnection blocks for seconds.
//   Running it on the Flutter platform thread deadlocks the Win32
//   message pump which kills the debug log reader and the channel.
//   We capture all params by value, move the result ptr into a
//   shared_ptr, and reply from a detached background thread.
// -------------------------------------------------------------------
void MethodHandler::handleStartStream(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    if (!args || !std::get_if<flutter::EncodableMap>(args)) {
        result->Error("INVALID_ARGS", "startStream requires a map", nullptr);
        return;
    }
    const auto &m = *std::get_if<flutter::EncodableMap>(args);

    std::string host       = getString(m, "host");
    std::string appVersion = getString(m, "appVersion", "7.1.431.-1");
    std::string gfeVersion = getString(m, "gfeVersion", "");
    std::string rtspUrl    = getString(m, "rtspSessionUrl", "");
    std::string riKeyHex   = getString(m, "riKey", "");
    std::string videoCodec = getString(m, "videoCodec", "H264");

    int width               = getInt(m, "width",  1920);
    int height              = getInt(m, "height", 1080);
    int fps                 = getInt(m, "fps",    60);
    int bitrate             = getInt(m, "bitrate", 20000);
    int serverCodecMode     = getInt(m, "serverCodecModeSupport", 0x0F);
    int riKeyId             = getInt(m, "riKeyId", 0);
    int colorSpace          = getBool(m, "enableHdr", false)  ? 1 : 0;
    int colorRange          = getBool(m, "fullRange", false)   ? 1 : 0;
    std::string audioConfig = getString(m, "audioConfig", "stereo");
    int audioConfiguration  = (audioConfig == "surround51") ? 0x003F06CA :
                              (audioConfig == "surround71") ? 0x063F08CA : 0x000302CA;

    // Probe hardware/software codec availability before advertising to server.
    bool hdr = colorSpace != 0;
    auto probe = video::CodecProbeWin::instance().probe(width, height, fps, hdr);
    auto codecStatus = [&](const std::string &key) -> std::string {
        auto it = probe.find(key);
        return it != probe.end() ? it->second : "unsupported";
    };
    bool h265TextureUsable = (codecStatus("h265") == "hardware");
    bool av1TextureUsable  = (codecStatus("av1")  == "hardware");
    fprintf(stderr, "handleStartStream: codec probe h264=%s h265=%s av1=%s\n",
            codecStatus("h264").c_str(), codecStatus("h265").c_str(),
            codecStatus("av1").c_str());

    int supportedVideoFormats = 0x0001; // H264 always
    if ((videoCodec == "H265" || videoCodec == "auto") && h265TextureUsable)
        supportedVideoFormats |= (hdr ? 0x0F00 : 0x0100);
    if ((videoCodec == "AV1"  || videoCodec == "auto") && av1TextureUsable)
        supportedVideoFormats |= (hdr ? 0xF000 : 0x1000);
    if ((videoCodec == "H265" || videoCodec == "auto") &&
        codecStatus("h265") == "software") {
        fprintf(stderr,
                "handleStartStream: HEVC probe is software-only; not advertising until "
                "system-memory decode frames can be uploaded to the Windows texture path\n");
    }
    if ((videoCodec == "AV1" || videoCodec == "auto") &&
        codecStatus("av1") == "software") {
        fprintf(stderr,
                "handleStartStream: AV1 probe is software-only; not advertising until "
                "system-memory decode frames can be uploaded to the Windows texture path\n");
    }

    // riKey: 32 hex chars = 16 bytes
    auto riAesKey = hexToBytes(riKeyHex, 16);

    // riAesIv from riKeyId (big-endian)
    uint8_t riAesIv[16] = {};
    riAesIv[0] = (riKeyId >> 24) & 0xFF;
    riAesIv[1] = (riKeyId >> 16) & 0xFF;
    riAesIv[2] = (riKeyId >>  8) & 0xFF;
    riAesIv[3] = (riKeyId)       & 0xFF;

    // Copy riAesIv into a vector for capture
    std::vector<uint8_t> riAesIvVec(riAesIv, riAesIv + 16);

    // Move result into shared_ptr so it can be captured by the lambda
    auto sharedResult = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
        std::move(result));

    std::thread([
        host, appVersion, gfeVersion, rtspUrl,
        serverCodecMode, width, height, fps, bitrate,
        audioConfiguration, supportedVideoFormats,
        riAesKey, riAesIvVec, colorSpace, colorRange,
        sharedResult
    ]() mutable {
        // MFT/COM requires apartment init on this new thread
        CoInitializeEx(nullptr, COINIT_MULTITHREADED);

        fprintf(stderr, "moonlight_startStream_thread: addr=%s %dx%d@%d bitrate=%d codec=0x%X\n",
                host.c_str(), width, height, fps, bitrate, supportedVideoFormats);

        int status = moonlightWinStartConnection(
            host.c_str(),
            appVersion.c_str(),
            gfeVersion.empty() ? nullptr : gfeVersion.c_str(),
            rtspUrl.empty()    ? nullptr : rtspUrl.c_str(),
            serverCodecMode,
            width, height, fps, bitrate,
            1392,     // packetSize
            2,        // streamingRemotely (AUTO)
            audioConfiguration,
            supportedVideoFormats,
            fps * 100,
            riAesKey.data(), riAesIvVec.data(),
            0,         // videoCapabilities
            colorSpace, colorRange
        );

        fprintf(stderr, "moonlight_startStream_thread: LiStartConnection returned %d\n", status);

        if (status == 0) {
            sharedResult->Success(flutter::EncodableValue(true));
        } else {
            sharedResult->Error("STREAM_FAILED",
                std::string("Connection failed code=") + std::to_string(status),
                flutter::EncodableValue(status));
        }

        CoUninitialize();
    }).detach();
}


// -------------------------------------------------------------------
// stopStream
// -------------------------------------------------------------------
void MethodHandler::handleStopStream(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    moonlightWinStopConnection();
    StreamingBridgeWin::instance().setStreaming(false);
    result->Success();
}

// -------------------------------------------------------------------
// getTextureId
// -------------------------------------------------------------------
void MethodHandler::handleGetTextureId(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    int64_t tid = StreamingBridgeWin::instance().getTextureId();
    if (tid >= 0) result->Success(flutter::EncodableValue(tid));
    else          result->Error("NO_TEXTURE", "Texture not registered", nullptr);
}

// -------------------------------------------------------------------
// Input methods
// -------------------------------------------------------------------
void MethodHandler::handleSendMouseMove(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (!args) { result->Success(); return; }
    const auto &m = *std::get_if<flutter::EncodableMap>(args);
    moonlightWinSendMouseMove(
        static_cast<short>(getInt(m, "deltaX")),
        static_cast<short>(getInt(m, "deltaY")));
    result->Success();
}

void MethodHandler::handleSendMousePosition(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (!args) { result->Success(); return; }
    const auto &m = *std::get_if<flutter::EncodableMap>(args);
    moonlightWinSendMousePosition(
        static_cast<short>(getInt(m, "x")),
        static_cast<short>(getInt(m, "y")),
        static_cast<short>(getInt(m, "refWidth",  1920)),
        static_cast<short>(getInt(m, "refHeight", 1080)));
    result->Success();
}

void MethodHandler::handleSendMouseButton(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (!args) { result->Success(); return; }
    const auto &m = *std::get_if<flutter::EncodableMap>(args);
    bool  pressed = getBool(m, "pressed");
    uint8_t btn   = static_cast<uint8_t>(getInt(m, "button", 1));
    uint8_t act   = pressed ? 0x07 : 0x08;
    moonlightWinSendMouseButton(act, btn);
    result->Success();
}

void MethodHandler::handleSendKeyboard(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (!args) { result->Success(); return; }
    const auto &m = *std::get_if<flutter::EncodableMap>(args);
    bool pressed  = getBool(m, "pressed");
    short keyCode = static_cast<short>(getInt(m, "keyCode"));
    moonlightWinSendKeyboard(keyCode, pressed ? 0x03 : 0x04, 0, 0);
    result->Success();
}

void MethodHandler::handleSendScroll(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (!args) { result->Success(); return; }
    const auto &m = *std::get_if<flutter::EncodableMap>(args);
    moonlightWinSendScroll(static_cast<short>(getInt(m, "scrollAmount")));
    result->Success();
}

void MethodHandler::handleSendHighResHScroll(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (!args) { result->Success(); return; }
    const auto &m = *std::get_if<flutter::EncodableMap>(args);
    moonlightWinSendHighResHScroll(static_cast<short>(getInt(m, "scrollAmount")));
    result->Success();
}

void MethodHandler::handleSendGamepadInput(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (!args) { result->Success(); return; }
    const auto &m = *std::get_if<flutter::EncodableMap>(args);
    moonlightWinSendControllerInput(
        static_cast<short>(getInt(m, "controllerNumber")),
        static_cast<short>(getInt(m, "activeGamepadMask", 1)),
        getInt(m, "buttonFlags"),
        static_cast<uint8_t>(getInt(m, "leftTrigger")),
        static_cast<uint8_t>(getInt(m, "rightTrigger")),
        static_cast<short>(getInt(m, "leftStickX")),
        static_cast<short>(getInt(m, "leftStickY")),
        static_cast<short>(getInt(m, "rightStickX")),
        static_cast<short>(getInt(m, "rightStickY")));
    result->Success();
}

void MethodHandler::handleSendControllerArrival(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (!args) { result->Success(flutter::EncodableValue(true)); return; }
    const auto &m = *std::get_if<flutter::EncodableMap>(args);
    int rc = moonlightWinSendControllerArrival(
        static_cast<short>(getInt(m, "controllerNumber")),
        static_cast<short>(getInt(m, "activeGamepadMask", 1)),
        static_cast<uint8_t>(getInt(m, "controllerType", 1)),
        static_cast<short>(getInt(m, "capabilities")),
        getInt(m, "supportedButtonFlags"));
    result->Success(flutter::EncodableValue(rc == 0));
}

void MethodHandler::handleSendTouchEvent(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (!args) { result->Success(); return; }
    const auto &m = *std::get_if<flutter::EncodableMap>(args);

    // The Dart side sends raw pixel coordinates relative to the stream widget.
    // LiSendTouchEvent expects normalised coords in [0, 1].
    // We use TextureBridge stream dimensions for normalisation.
    const int tw = video::TextureBridge::instance().width();
    const int th = video::TextureBridge::instance().height();
    const float normX = (tw > 0)
        ? static_cast<float>(getDouble(m, "x")) / static_cast<float>(tw) : 0.5f;
    const float normY = (th > 0)
        ? static_cast<float>(getDouble(m, "y")) / static_cast<float>(th) : 0.5f;

    const int rc = moonlightWinSendTouchEvent(
        static_cast<uint8_t>(getInt(m, "eventType")),
        static_cast<uint32_t>(getInt(m, "pointerId")),
        normX, normY,
        static_cast<float>(getDouble(m, "pressure", 1.0)),
        static_cast<float>(getDouble(m, "contactMajor")),
        static_cast<float>(getDouble(m, "contactMinor")),
        static_cast<uint16_t>(getInt(m, "orientation")));

    // LI_ERR_UNSUPPORTED (-8) means the host (GFE < 7.1.431) doesn't support
    // touch events — treat as success so the Dart layer doesn't log an error.
    if (rc != 0 && rc != -8) {
        fprintf(stderr, "handleSendTouchEvent: LiSendTouchEvent returned %d\n", rc);
    }
    result->Success();
}

void MethodHandler::handleSendUtf8Text(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (!args) { result->Success(); return; }
    const auto &m = *std::get_if<flutter::EncodableMap>(args);
    std::string text = getString(m, "text");
    if (!text.empty()) moonlightWinSendUtf8Text(text.c_str());
    result->Success();
}

// -------------------------------------------------------------------
// Stats
// -------------------------------------------------------------------
void MethodHandler::handleGetStats(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    auto vs = StreamingBridgeWin::instance().getVideoStats();
    auto &ar = audio::WasapiRenderer::instance();

    flutter::EncodableMap stats;
    stats[flutter::EncodableValue("type")]         = flutter::EncodableValue("stats");
    stats[flutter::EncodableValue("platform")]     = flutter::EncodableValue(std::string("windows"));
    stats[flutter::EncodableValue("fps")]          = flutter::EncodableValue(vs.fps);
    stats[flutter::EncodableValue("decodeTime")]   = flutter::EncodableValue(vs.decodeTimeMs);
    stats[flutter::EncodableValue("dropRate")]     = flutter::EncodableValue(
        vs.framesDecoded + vs.framesDropped > 0
            ? (int)((vs.framesDropped * 100) / (vs.framesDecoded + vs.framesDropped))
            : 0);
    stats[flutter::EncodableValue("totalRendered")]      = flutter::EncodableValue((int64_t)vs.framesDecoded);
    stats[flutter::EncodableValue("totalDropped")]       = flutter::EncodableValue((int64_t)vs.framesDropped);
    stats[flutter::EncodableValue("codec")]              = flutter::EncodableValue(vs.codec);
    stats[flutter::EncodableValue("isSoftwareDecoder")]  = flutter::EncodableValue(vs.isSoftwareDecoder);
    stats[flutter::EncodableValue("packetsSubmitted")]   = flutter::EncodableValue((int64_t)vs.packetsSubmitted);
    stats[flutter::EncodableValue("bytesSubmitted")]     = flutter::EncodableValue((int64_t)vs.bytesSubmitted);
    stats[flutter::EncodableValue("inputsAccepted")]     = flutter::EncodableValue((int64_t)vs.inputsAccepted);
    stats[flutter::EncodableValue("idrFrames")]          = flutter::EncodableValue((int64_t)vs.idrFrames);
    stats[flutter::EncodableValue("outputSamples")]      = flutter::EncodableValue((int64_t)vs.outputSamples);
    stats[flutter::EncodableValue("dxgiFrames")]         = flutter::EncodableValue((int64_t)vs.dxgiFrames);
    stats[flutter::EncodableValue("dxgiMisses")]         = flutter::EncodableValue((int64_t)vs.dxgiMisses);
    stats[flutter::EncodableValue("processInputFailures")] = flutter::EncodableValue((int64_t)vs.processInputFailures);
    stats[flutter::EncodableValue("processOutputFailures")] = flutter::EncodableValue((int64_t)vs.processOutputFailures);
    stats[flutter::EncodableValue("streamChanges")]      = flutter::EncodableValue((int64_t)vs.streamChanges);
    stats[flutter::EncodableValue("textureBlits")]       = flutter::EncodableValue((int64_t)vs.textureBlits);
    stats[flutter::EncodableValue("textureBlitFailures")] = flutter::EncodableValue((int64_t)vs.textureBlitFailures);
    stats[flutter::EncodableValue("textureFrameNotifications")] = flutter::EncodableValue((int64_t)vs.textureFrameNotifications);
    stats[flutter::EncodableValue("textureDescriptorCallbacks")] = flutter::EncodableValue((int64_t)vs.textureDescriptorCallbacks);
    stats[flutter::EncodableValue("textureNullDescriptorCallbacks")] = flutter::EncodableValue((int64_t)vs.textureNullDescriptorCallbacks);
    stats[flutter::EncodableValue("pendingAudioMs")]     = flutter::EncodableValue(
        moonlightWinGetPendingAudioDuration());
    auto audioStats = ar.stats();
    stats[flutter::EncodableValue("audioSubmittedSamples")] = flutter::EncodableValue((int64_t)audioStats.submittedSamples);
    stats[flutter::EncodableValue("audioDroppedSamples")] = flutter::EncodableValue((int64_t)audioStats.droppedSamples);
    stats[flutter::EncodableValue("audioUnderruns")] = flutter::EncodableValue((int64_t)audioStats.underruns);
    stats[flutter::EncodableValue("audioReinitCount")] = flutter::EncodableValue((int64_t)audioStats.reinitCount);
    stats[flutter::EncodableValue("audioChannels")] = flutter::EncodableValue(audioStats.channels);
    stats[flutter::EncodableValue("audioSampleRate")] = flutter::EncodableValue(audioStats.sampleRate);
    result->Success(flutter::EncodableValue(stats));
}

// -------------------------------------------------------------------
// probeCodec
// -------------------------------------------------------------------
void MethodHandler::handleProbeCodec(const flutter::EncodableValue *args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    int w = 1920, h = 1080, fps = 60; bool hdr = false;
    if (args) {
        const auto &m = *std::get_if<flutter::EncodableMap>(args);
        w   = getInt(m, "width",  1920);
        h   = getInt(m, "height", 1080);
        fps = getInt(m, "fps",    60);
        hdr = getBool(m, "hdr",   false);
    }
    auto probeMap = video::CodecProbeWin::instance().probe(w, h, fps, hdr);
    flutter::EncodableMap out;
    for (auto &kv : probeMap) {
        out[flutter::EncodableValue(kv.first)] = flutter::EncodableValue(kv.second);
    }
    result->Success(flutter::EncodableValue(out));
}

}  // namespace jujostream
