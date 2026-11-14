/**
 * moonlight_bridge_win.c
 *
 * Windows implementation of the moonlight-common-c bridge.
 * Port of moonlight_bridge_mac.c — same logic, Windows naming.
 */

#include "moonlight_bridge_win.h"
#include "turbo_input_client.h"
#include <Limelight.h>
#include <Limelight-internal.h>
#include <enet/enet.h>
#include <string.h>
#include <stdio.h>

/* -----------------------------------------------------------------------
 * Networking init (WinSock / ENet) — called once from the C++ plugin
 * ----------------------------------------------------------------------- */
static int g_netInitialized = 0;

void moonlightWinInitNetworking(void) {
    if (g_netInitialized) return;
    if (enet_initialize() != 0) {
        fprintf(stderr, "moonlight_bridge_win: enet_initialize (WSAStartup) failed\n");
    } else {
        fprintf(stderr, "moonlight_bridge_win: ENet/WinSock initialized\n");
        g_netInitialized = 1;
    }
}

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

static char     g_turboHost[256] = {0};
static int      g_turboUdpPort   = 0;
static int      g_turboTcpPort   = 0;
static uint32_t g_turboSessionId = 0;
static char     g_turboKeyHex[96] = {0};

static void turboWinOnRumble(uint16_t cn, uint16_t low, uint16_t high) {
    if (g_winCallbacks.onRumble) g_winCallbacks.onRumble(cn, low, high);
}
static void turboWinOnRumbleTriggers(uint16_t cn, uint16_t lt, uint16_t rt) {
    if (g_winCallbacks.onRumbleTriggers) g_winCallbacks.onRumbleTriggers(cn, lt, rt);
}
static void turboWinOnMotionState(uint16_t cn, uint8_t mt, uint16_t hz) {
    if (g_winCallbacks.onSetMotionEventState) g_winCallbacks.onSetMotionEventState(cn, mt, hz);
}
static void turboWinOnLed(uint16_t cn, uint8_t r, uint8_t g, uint8_t b) {
    if (g_winCallbacks.onSetControllerLED) g_winCallbacks.onSetControllerLED(cn, r, g, b);
}
static void turboWinOnAdaptiveTriggers(
    uint16_t cn, uint8_t eventFlags, uint8_t typeLeft, uint8_t typeRight,
    const uint8_t *left, const uint8_t *right) {
    if (g_winCallbacks.onSetAdaptiveTriggers) {
        g_winCallbacks.onSetAdaptiveTriggers(cn, eventFlags, typeLeft, typeRight, left, right);
    }
}

void moonlightWinConfigureTurboInput(
    int udpPort, int tcpPort, uint32_t sessionId, const char *keyHex) {
    g_turboUdpPort   = udpPort;
    g_turboTcpPort   = tcpPort;
    g_turboSessionId = sessionId;
    if (keyHex) {
        snprintf(g_turboKeyHex, sizeof(g_turboKeyHex), "%s", keyHex);
    } else {
        g_turboKeyHex[0] = '\0';
    }
}

void moonlightWinOnConnectionStarted(void) {
    if (g_turboSessionId == 0 || g_turboHost[0] == '\0' || g_turboKeyHex[0] == '\0') {
        return;
    }
    TurboFeedbackCallbacks fb = {
        .onRumble              = turboWinOnRumble,
        .onRumbleTriggers      = turboWinOnRumbleTriggers,
        .onSetMotionEventState = turboWinOnMotionState,
        .onSetControllerLED    = turboWinOnLed,
        .onSetAdaptiveTriggers = turboWinOnAdaptiveTriggers,
    };
    const bool ok = turboClientStart(
        g_turboHost, g_turboUdpPort, g_turboTcpPort, g_turboSessionId, g_turboKeyHex, &fb);
    fprintf(stderr, "moonlight_bridge_win: turboClientStart ok=%d udp=%d tcp=%d sid=%u\n",
            ok ? 1 : 0, g_turboUdpPort, g_turboTcpPort, (unsigned)g_turboSessionId);
}

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

    if (address) {
        snprintf(g_turboHost, sizeof(g_turboHost), "%s", address);
    } else {
        g_turboHost[0] = '\0';
    }

    int ret = LiStartConnection(
        &serverInfo, &streamConfig,
        &BridgeWinConnCallbacks,
        &BridgeWinVideoCallbacks,
        &BridgeWinAudioCallbacks,
        NULL, 0,
        NULL, 0
    );

    if (ret != 0) {
        turboClientStop();
    }

    fprintf(stderr, "moonlight_bridge_win: LiStartConnection returned %d\n", ret);
    return ret;
}

void moonlightWinStopConnection(void) {
    turboClientStop();
    LiStopConnection();
}
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
    if (turboClientIsActive() &&
        cn >= 0 && cn < 8 &&
        turboClientSendGamepadState(
            (uint8_t)cn, (uint16_t)agm, (uint32_t)bf, lt, rt, lx, ly, rx, ry, 0)) {
        return 0;
    }
    return LiSendMultiControllerEvent(cn, agm, bf, lt, rt, lx, ly, rx, ry);
}
int moonlightWinSendControllerArrival(
    short cn, short agm, uint8_t ct, short caps, int sbf)
{
    if (turboClientIsActive() &&
        cn >= 0 && cn < 8 &&
        turboClientSendGamepadArrival(
            (uint8_t)cn, ct, (uint16_t)caps, (uint32_t)sbf)) {
        return 0;
    }
    return LiSendControllerArrivalEvent(
        (uint8_t)cn, (uint16_t)agm, ct, (uint32_t)sbf, (uint16_t)caps);
}
void moonlightWinSendUtf8Text(const char *text) {
    LiSendUtf8TextEvent(text, (int)strlen(text));
}
int moonlightWinSendTouchEvent(uint8_t eventType, uint32_t pointerId,
                                float x, float y,
                                float pressureOrDistance,
                                float contactAreaMajor,
                                float contactAreaMinor,
                                uint16_t rotation) {
    return LiSendTouchEvent(eventType, pointerId, x, y,
                            pressureOrDistance,
                            contactAreaMajor, contactAreaMinor,
                            rotation);
}

int moonlightWinGetVrrClockSyncStats(int64_t *offsetUs, uint64_t *rttUs, uint32_t *sampleCount) {
    return LiGetVrrClockSyncStats(offsetUs, rttUs, sampleCount) ? 1 : 0;
}

int moonlightWinTriggerRoam(void) {
    return LiTriggerConnectionRoam() ? 1 : 0;
}

int moonlightWinGetRoamingStats(int *supported, uint32_t *migrations, uint64_t *lastMigrationUs) {
    bool sup = false;
    bool ok = LiGetRoamingStats(&sup, migrations, lastMigrationUs);
    if (supported) {
        *supported = sup ? 1 : 0;
    }
    return ok ? 1 : 0;
}
