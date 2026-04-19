// macOS moonlight-common-c bridge implementation.
// Uses C function pointers to forward events to Swift.

#include "moonlight_bridge_mac.h"
#include <Limelight.h>
#include <Limelight-internal.h>
#include <string.h>
#include <stdio.h>

// ---------------------------------------------------------------------------
// Global callback table (set once by Swift at startup)
// ---------------------------------------------------------------------------
static JujostreamMacCallbacks g_macCallbacks;

void moonlightMacRegisterCallbacks(const JujostreamMacCallbacks *cbs) {
    if (cbs) {
        g_macCallbacks = *cbs;
    }
}

// ---------------------------------------------------------------------------
// Forward declarations for callback structs (defined in callbacks_mac.c)
// ---------------------------------------------------------------------------
extern DECODER_RENDERER_CALLBACKS BridgeMacVideoCallbacks;
extern AUDIO_RENDERER_CALLBACKS   BridgeMacAudioCallbacks;
extern CONNECTION_LISTENER_CALLBACKS BridgeMacConnCallbacks;

// Expose the callback table to callbacks_mac.c
JujostreamMacCallbacks *moonlightMacGetCallbacks(void) {
    return &g_macCallbacks;
}

// Slow Opus decoder flag (set from Swift before starting connection)
static bool g_slowOpusDecoder = false;

void moonlightMacSetSlowOpusDecoder(bool slow) {
    g_slowOpusDecoder = slow;
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------
int moonlightMacStartConnection(
    const char *address,
    const char *appVersion,
    const char *gfeVersion,
    const char *rtspSessionUrl,
    int  serverCodecModeSupport,
    int  width, int height, int fps,
    int  bitrate, int packetSize, int streamingRemotely,
    int  audioConfiguration, int supportedVideoFormats,
    int  clientRefreshRateX100,
    const uint8_t *riAesKey,
    const uint8_t *riAesIv,
    int  videoCapabilities,
    int  colorSpace, int colorRange)
{
    SERVER_INFORMATION serverInfo;
    LiInitializeServerInformation(&serverInfo);
    serverInfo.address               = address;
    serverInfo.serverInfoAppVersion  = appVersion;
    serverInfo.serverInfoGfeVersion  = gfeVersion;
    serverInfo.rtspSessionUrl        = rtspSessionUrl;
    serverInfo.serverCodecModeSupport = serverCodecModeSupport;

    STREAM_CONFIGURATION streamConfig;
    LiInitializeStreamConfiguration(&streamConfig);
    streamConfig.width                 = width;
    streamConfig.height                = height;
    streamConfig.fps                   = fps;
    streamConfig.bitrate               = bitrate;
    streamConfig.packetSize            = packetSize;
    streamConfig.streamingRemotely     = streamingRemotely;
    streamConfig.audioConfiguration    = audioConfiguration;
    streamConfig.supportedVideoFormats = supportedVideoFormats;
    streamConfig.clientRefreshRateX100 = clientRefreshRateX100;
    streamConfig.colorSpace            = colorSpace;
    streamConfig.colorRange            = colorRange;
    streamConfig.encryptionFlags       = ENCFLG_ALL;

    if (riAesKey)
        memcpy(streamConfig.remoteInputAesKey, riAesKey,
               sizeof(streamConfig.remoteInputAesKey));
    if (riAesIv)
        memcpy(streamConfig.remoteInputAesIv, riAesIv,
               sizeof(streamConfig.remoteInputAesIv));

    BridgeMacVideoCallbacks.capabilities = videoCapabilities;

    // Set audio capabilities
    BridgeMacAudioCallbacks.capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;
    if (g_slowOpusDecoder) {
        BridgeMacAudioCallbacks.capabilities |= CAPABILITY_SLOW_OPUS_DECODER;
    }

    fprintf(stderr, "moonlight_bridge_mac: LiStartConnection addr=%s appVer=%s "
            "gfeVer=%s rtsp=%s codecMode=0x%X %dx%d@%dfps bitrate=%d "
            "audioConfig=0x%X videoFmts=0x%X enc=0x%X\n",
            address ? address : "(null)",
            appVersion ? appVersion : "(null)",
            gfeVersion ? gfeVersion : "(null)",
            rtspSessionUrl ? rtspSessionUrl : "(null)",
            serverCodecModeSupport,
            width, height, fps, bitrate,
            audioConfiguration, supportedVideoFormats,
            streamConfig.encryptionFlags);

    int ret = LiStartConnection(
        &serverInfo, &streamConfig,
        &BridgeMacConnCallbacks,
        &BridgeMacVideoCallbacks,
        &BridgeMacAudioCallbacks,
        NULL, 0,
        NULL, 0
    );

    fprintf(stderr, "moonlight_bridge_mac: LiStartConnection returned %d\n", ret);
    return ret;
}

void moonlightMacStopConnection(void)      { LiStopConnection(); }
void moonlightMacInterruptConnection(void) { LiInterruptConnection(); }
int  moonlightMacGetPendingVideoFrames(void)    { return LiGetPendingVideoFrames(); }
int  moonlightMacGetPendingAudioDuration(void)  { return LiGetPendingAudioDuration(); }
const char *moonlightMacGetStageName(int stage) { return LiGetStageName(stage); }
long long   moonlightMacGetEstimatedRttInfo(void) {
    uint32_t rtt = 0, rttVariance = 0;
    if (LiGetEstimatedRttInfo(&rtt, &rttVariance)) {
        return (long long)rtt;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------
void moonlightMacSendMouseMove(short dx, short dy) {
    LiSendMouseMoveEvent(dx, dy);
}
void moonlightMacSendMousePosition(short x, short y, short rw, short rh) {
    LiSendMousePositionEvent(x, y, rw, rh);
}
void moonlightMacSendMouseButton(uint8_t action, uint8_t button) {
    LiSendMouseButtonEvent(action, button);
}
void moonlightMacSendKeyboard(short keyCode, uint8_t keyAction,
                              uint8_t modifiers, uint8_t flags) {
    LiSendKeyboardEvent2(keyCode, keyAction, modifiers, flags);
}
void moonlightMacSendScroll(short scrollAmount) {
    LiSendHighResScrollEvent(scrollAmount);
}
void moonlightMacSendHighResHScroll(short scrollAmount) {
    LiSendHighResHScrollEvent(scrollAmount);
}
int moonlightMacSendControllerInput(
    short cn, short agm, int bf, uint8_t lt, uint8_t rt,
    short lx, short ly, short rx, short ry)
{
    return LiSendMultiControllerEvent(cn, agm, bf, lt, rt, lx, ly, rx, ry);
}
int moonlightMacSendControllerArrival(
    short cn, short agm, uint8_t ct, short caps, int sbf)
{
    return LiSendControllerArrivalEvent(
        (uint8_t)cn, (uint16_t)agm, ct, (uint32_t)sbf, (uint16_t)caps);
}
int moonlightMacSendTouchEvent(
    uint8_t et, int pid, float x, float y, float pod,
    float cam, float cami, short rotation)
{
    return LiSendTouchEvent(et, pid, x, y, pod, cam, cami, rotation);
}
void moonlightMacSendUtf8Text(const char *text) {
    LiSendUtf8TextEvent(text, (int)strlen(text));
}
void moonlightMacSendControllerMotionEvent(
    short cn, uint8_t mt, float x, float y, float z)
{
    LiSendControllerMotionEvent((uint8_t)cn, mt, x, y, z);
}
