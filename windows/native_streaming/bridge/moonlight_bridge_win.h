/**
 * moonlight_bridge_win.h
 *
 * Public C interface for the Windows moonlight-common-c bridge.
 * Mirrors moonlight_bridge_mac.h — same callback struct pattern,
 * same function signatures, Windows-specific naming.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    int  (*onVideoSetup)(int videoFormat, int width, int height, int redrawRate);
    void (*onVideoStart)(void);
    void (*onVideoStop)(void);
    void (*onVideoCleanup)(void);
    int  (*onVideoFrame)(const uint8_t *data, int length,
                         int frameType, int frameNumber,
                         int64_t receiveTimeMs);
    int  (*onAudioInit)(int audioConfig, int sampleRate, int samplesPerFrame);
    void (*onAudioStart)(void);
    void (*onAudioStop)(void);
    void (*onAudioCleanup)(void);
    void (*onAudioSample)(const char *data, int length);
    void (*onConnectionStarted)(void);
    void (*onConnectionTerminated)(int errorCode);
    void (*onStageStarting)(int stage);
    void (*onStageComplete)(int stage);
    void (*onStageFailed)(int stage, int errorCode);
    void (*onConnectionStatusUpdate)(int connectionStatus);
    void (*onRumble)(uint16_t controllerNumber, uint16_t lowFreqMotor, uint16_t highFreqMotor);
    void (*onRumbleTriggers)(uint16_t controllerNumber, uint16_t leftTrigger, uint16_t rightTrigger);
    void (*onSetMotionEventState)(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz);
    void (*onSetControllerLED)(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b);
    void (*onSetHdrMode)(bool enabled);
} JujostreamWinCallbacks;

void moonlightWinRegisterCallbacks(const JujostreamWinCallbacks *cbs);

// Must be called once at plugin startup (initialises WinSock / ENet).
// Safe to call multiple times — subsequent calls are no-ops.
void moonlightWinInitNetworking(void);

int  moonlightWinStartConnection(
    const char *address, const char *appVersion, const char *gfeVersion,
    const char *rtspSessionUrl, int serverCodecModeSupport,
    int width, int height, int fps, int bitrate, int packetSize,
    int streamingRemotely, int audioConfiguration, int supportedVideoFormats,
    int clientRefreshRateX100, const uint8_t *riAesKey, const uint8_t *riAesIv,
    int videoCapabilities, int colorSpace, int colorRange);

void moonlightWinStopConnection(void);
void moonlightWinInterruptConnection(void);
int  moonlightWinGetPendingVideoFrames(void);
int  moonlightWinGetPendingAudioDuration(void);
const char *moonlightWinGetStageName(int stage);
long long   moonlightWinGetEstimatedRttInfo(void);

void moonlightWinSendMouseMove(short deltaX, short deltaY);
void moonlightWinSendMousePosition(short x, short y, short refWidth, short refHeight);
void moonlightWinSendMouseButton(uint8_t action, uint8_t button);
void moonlightWinSendKeyboard(short keyCode, uint8_t keyAction, uint8_t modifiers, uint8_t flags);
void moonlightWinSendScroll(short scrollAmount);
void moonlightWinSendHighResHScroll(short scrollAmount);
int  moonlightWinSendControllerInput(
    short controllerNumber, short activeGamepadMask,
    int buttonFlags, uint8_t leftTrigger, uint8_t rightTrigger,
    short leftStickX, short leftStickY, short rightStickX, short rightStickY);
int  moonlightWinSendControllerArrival(
    short controllerNumber, short activeGamepadMask,
    uint8_t controllerType, short capabilities, int supportedButtonFlags);
void moonlightWinSendUtf8Text(const char *text);

// Touch event — normalized coords [0,1] relative to stream output area.
// Returns 0 on success, LI_ERR_UNSUPPORTED if the host does not support
// touch (GFE < 7.1.431; fall back to mouse events in that case).
int  moonlightWinSendTouchEvent(uint8_t eventType, uint32_t pointerId,
                                 float x, float y,
                                 float pressureOrDistance,
                                 float contactAreaMajor,
                                 float contactAreaMinor,
                                 uint16_t rotation);

#ifdef __cplusplus
}
#endif
