/**
 * moonlight_bridge_win.c
 *
 * Windows implementation of the moonlight-common-c bridge.
 * Port of moonlight_bridge_mac.c — same logic, Windows naming.
 */

#include "moonlight_bridge_win.h"
#include <Limelight.h>
#include <Limelight-internal.h>
#include <string.h>
#include <stdio.h>

/* -----------------------------------------------------------------------
 * Global callback table (set once by C++ at startup)
 * ----------------------------------------------------------------------- */
static JujostreamWinCallbacks g_winCallbacks;

void moonlightWinRegisterCallbacks(const JujostreamWinCallbacks *cbs) {
    if (cbs) {
        g_winCallbacks = *cbs;
    }
}

/* -----------------------------------------------------------------------
 * Forward declarations for callback structs (defined in callbacks_win.c)
 * ----------------------------------------------------------------------- */
extern DECODER_RENDERER_CALLBACKS    BridgeWinVideoCallbacks;
extern AUDIO_RENDERER_CALLBACKS      BridgeWinAudioCallbacks;
extern CONNECTION_LISTENER_CALLBACKS BridgeWinConnCallbacks;

/* Expose the callback table to callbacks_win.c */
JujostreamWinCallbacks *moonlightWinGetCallbacks(void) {
    return &g_winCallbacks;
}

static bool g_slowOpusDecoder = false;

/* -----------------------------------------------------------------------
 * Connection
 * ----------------------------------------------------------------------- */
int moonlightWinStartConnection(
    const char *address, const char *appVersion, const char *gfeVersion,
    const char *rtspSessionUrl, int serverCodecModeSupport,
    int width, int height, int fps, int bitrate, int packetSize,
    int streamingRemotely, int audioConfiguration, int supportedVideoFormats,
    int clientRefreshRateX100, const uint8_t *riAesKey, const uint8_t *riAesIv,
    int videoCapabilities, int colorSpace, int colorRange)
{
    SERVER_INFORMATION serverInfo;
    LiInitializeServerInformation(&serverInfo);
    serverInfo.address                = address;
    serverInfo.serverInfoAppVersion   = appVersion;
    serverInfo.serverInfoGfeVersion   = gfeVersion;
    serverInfo.rtspSessionUrl         = rtspSessionUrl;
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

    BridgeWinVideoCallbacks.capabilities = videoCapabilities;

    BridgeWinAudioCallbacks.capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;
    if (g_slowOpusDecoder) {
        BridgeWinAudioCallbacks.capabilities |= CAPABILITY_SLOW_OPUS_DECODER;
    }

    fprintf(stderr, "moonlight_bridge_win: LiStartConnection addr=%s "
            "%dx%d@%dfps bitrate=%d audioConfig=0x%X videoFmts=0x%X\n",
            address ? address : "(null)",
            width, height, fps, bitrate,
            audioConfiguration, supportedVideoFormats);

    int ret = LiStartConnection(
        &serverInfo, &streamConfig,
        &BridgeWinConnCallbacks,
        &BridgeWinVideoCallbacks,
        &BridgeWinAudioCallbacks,
        NULL, 0,
        NULL, 0
    );

    fprintf(stderr, "moonlight_bridge_win: LiStartConnection returned %d\n", ret);
    return ret;
}

void moonlightWinStopConnection(void)      { LiStopConnection(); }
void moonlightWinInterruptConnection(void) { LiInterruptConnection(); }
int  moonlightWinGetPendingVideoFrames(void)    { return LiGetPendingVideoFrames(); }
int  moonlightWinGetPendingAudioDuration(void)  { return LiGetPendingAudioDuration(); }
const char *moonlightWinGetStageName(int stage) { return LiGetStageName(stage); }
long long   moonlightWinGetEstimatedRttInfo(void) {
    uint32_t rtt = 0, rttVariance = 0;
    if (LiGetEstimatedRttInfo(&rtt, &rttVariance)) {
        return (long long)rtt;
    }
    return 0;
}

/* -----------------------------------------------------------------------
 * Input
 * ----------------------------------------------------------------------- */
void moonlightWinSendMouseMove(short dx, short dy) {
    LiSendMouseMoveEvent(dx, dy);
}
void moonlightWinSendMousePosition(short x, short y, short rw, short rh) {
    LiSendMousePositionEvent(x, y, rw, rh);
}
void moonlightWinSendMouseButton(uint8_t action, uint8_t button) {
    LiSendMouseButtonEvent(action, button);
}
void moonlightWinSendKeyboard(short keyCode, uint8_t keyAction,
                              uint8_t modifiers, uint8_t flags) {
    LiSendKeyboardEvent2(keyCode, keyAction, modifiers, flags);
}
void moonlightWinSendScroll(short scrollAmount) {
    LiSendHighResScrollEvent(scrollAmount);
}
void moonlightWinSendHighResHScroll(short scrollAmount) {
    LiSendHighResHScrollEvent(scrollAmount);
}
int moonlightWinSendControllerInput(
    short cn, short agm, int bf, uint8_t lt, uint8_t rt,
    short lx, short ly, short rx, short ry)
{
    return LiSendMultiControllerEvent(cn, agm, bf, lt, rt, lx, ly, rx, ry);
}
int moonlightWinSendControllerArrival(
    short cn, short agm, uint8_t ct, short caps, int sbf)
{
    return LiSendControllerArrivalEvent(
        (uint8_t)cn, (uint16_t)agm, ct, (uint32_t)sbf, (uint16_t)caps);
}
void moonlightWinSendUtf8Text(const char *text) {
    LiSendUtf8TextEvent(text, (int)strlen(text));
}
