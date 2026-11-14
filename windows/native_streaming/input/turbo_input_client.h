#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TurboFeedbackCallbacks {
    void (*onRumble)(uint16_t controllerNumber, uint16_t lowFreqMotor, uint16_t highFreqMotor);
    void (*onRumbleTriggers)(uint16_t controllerNumber, uint16_t leftTrigger, uint16_t rightTrigger);
    void (*onSetMotionEventState)(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz);
    void (*onSetControllerLED)(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b);
    void (*onSetAdaptiveTriggers)(
        uint16_t controllerNumber,
        uint8_t eventFlags,
        uint8_t typeLeft,
        uint8_t typeRight,
        const uint8_t *left,
        const uint8_t *right);
} TurboFeedbackCallbacks;

typedef struct TurboClientStats {
    bool active;
    bool usingTcp;
    uint32_t sessionId;
    uint64_t packetsSent;
    uint64_t packetsRecv;
    uint64_t authFailures;
    uint64_t feedbackRecv;
    uint32_t lastRttUs;
} TurboClientStats;

bool turboClientStart(
    const char *host,
    int udpPort,
    int tcpPort,
    uint32_t sessionId,
    const char *keyHex,
    const TurboFeedbackCallbacks *callbacks);

void turboClientStop(void);
bool turboClientIsActive(void);
TurboClientStats turboClientGetStats(void);

bool turboClientSendGamepadArrival(
    uint8_t controllerNumber,
    uint8_t controllerType,
    uint16_t capabilities,
    uint32_t supportedButtons);

bool turboClientSendGamepadState(
    uint8_t controllerNumber,
    uint16_t activeMask,
    uint32_t buttons,
    uint8_t leftTrigger,
    uint8_t rightTrigger,
    int16_t leftStickX,
    int16_t leftStickY,
    int16_t rightStickX,
    int16_t rightStickY,
    uint8_t flags);

bool turboClientSendGamepadMotion(
    uint8_t controllerNumber,
    uint8_t motionType,
    float x,
    float y,
    float z);

bool turboClientSendGamepadTouch(
    uint8_t controllerNumber,
    uint8_t eventType,
    uint32_t pointerId,
    float x,
    float y,
    float pressure);

#ifdef __cplusplus
}
#endif

