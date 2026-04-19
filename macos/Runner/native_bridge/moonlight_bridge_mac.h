// Public C interface for the macOS moonlight-common-c bridge.
// Imported via Swift bridging header.

#pragma once

#include <stdint.h>
#include <stdbool.h>

// ---------------------------------------------------------------------------
// Callback function-pointer table (populated from Swift via registerMacCallbacks)
// ---------------------------------------------------------------------------
typedef struct {
    // Video
    int  (*onVideoSetup)(int videoFormat, int width, int height, int redrawRate);
    void (*onVideoStart)(void);
    void (*onVideoStop)(void);
    void (*onVideoCleanup)(void);
    /// Called per decode unit. data = concatenated NAL unit bytes.
    int  (*onVideoFrame)(const uint8_t *data, int length,
                         int frameType, int frameNumber,
                         int64_t receiveTimeMs);
    // Audio
    int  (*onAudioInit)(int audioConfig, int sampleRate, int samplesPerFrame);
    void (*onAudioStart)(void);
    void (*onAudioStop)(void);
    void (*onAudioCleanup)(void);
    void (*onAudioSample)(const char *data, int length);

    // Connection events
    void (*onConnectionStarted)(void);
    void (*onConnectionTerminated)(int errorCode);
    void (*onStageStarting)(int stage);
    void (*onStageComplete)(int stage);
    void (*onStageFailed)(int stage, int errorCode);
    void (*onConnectionStatusUpdate)(int connectionStatus);

    // Controller feedback
    void (*onRumble)(uint16_t controllerNumber,
                     uint16_t lowFreqMotor,
                     uint16_t highFreqMotor);
    void (*onRumbleTriggers)(uint16_t controllerNumber,
                             uint16_t leftTrigger,
                             uint16_t rightTrigger);
    void (*onSetMotionEventState)(uint16_t controllerNumber,
                                  uint8_t  motionType,
                                  uint16_t reportRateHz);
    void (*onSetControllerLED)(uint16_t controllerNumber,
                               uint8_t r, uint8_t g, uint8_t b);
    void (*onSetHdrMode)(bool enabled);
} JujostreamMacCallbacks;

// ---------------------------------------------------------------------------
// Register Swift-side callback pointers (called once at plugin init)
// ---------------------------------------------------------------------------
void moonlightMacRegisterCallbacks(const JujostreamMacCallbacks *cbs);

// ---------------------------------------------------------------------------
// Connection control (called from Swift)
// ---------------------------------------------------------------------------
int  moonlightMacStartConnection(
    const char *address,
    const char *appVersion,
    const char *gfeVersion,       // may be NULL
    const char *rtspSessionUrl,   // may be NULL
    int  serverCodecModeSupport,
    int  width,
    int  height,
    int  fps,
    int  bitrate,
    int  packetSize,
    int  streamingRemotely,
    int  audioConfiguration,
    int  supportedVideoFormats,
    int  clientRefreshRateX100,
    const uint8_t *riAesKey,      // 16 bytes
    const uint8_t *riAesIv,       // 16 bytes
    int  videoCapabilities,
    int  colorSpace,
    int  colorRange
);

void moonlightMacSetSlowOpusDecoder(bool slow);
void moonlightMacStopConnection(void);
void moonlightMacInterruptConnection(void);
int  moonlightMacGetPendingVideoFrames(void);
int  moonlightMacGetPendingAudioDuration(void);
const char *moonlightMacGetStageName(int stage);
long long   moonlightMacGetEstimatedRttInfo(void);

// ---------------------------------------------------------------------------
// Input (called from Swift)
// ---------------------------------------------------------------------------
void moonlightMacSendMouseMove(short deltaX, short deltaY);
void moonlightMacSendMousePosition(short x, short y, short refWidth, short refHeight);
void moonlightMacSendMouseButton(uint8_t action, uint8_t button);
void moonlightMacSendKeyboard(short keyCode, uint8_t keyAction, uint8_t modifiers, uint8_t flags);
void moonlightMacSendScroll(short scrollAmount);
void moonlightMacSendHighResHScroll(short scrollAmount);
int  moonlightMacSendControllerInput(
    short controllerNumber, short activeGamepadMask,
    int buttonFlags, uint8_t leftTrigger, uint8_t rightTrigger,
    short leftStickX, short leftStickY,
    short rightStickX, short rightStickY
);
int  moonlightMacSendControllerArrival(
    short  controllerNumber,
    short  activeGamepadMask,
    uint8_t controllerType,
    short  capabilities,
    int    supportedButtonFlags
);
int  moonlightMacSendTouchEvent(
    uint8_t eventType, int pointerId,
    float x, float y, float pressureOrDistance,
    float contactAreaMajor, float contactAreaMinor,
    short rotation
);
void moonlightMacSendUtf8Text(const char *text);
void moonlightMacSendControllerMotionEvent(
    short controllerNumber, uint8_t motionType,
    float x, float y, float z
);
