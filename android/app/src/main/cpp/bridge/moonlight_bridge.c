// JNI bridge between Kotlin and moonlight-common-c.

#include <Limelight.h>
#include <Limelight-internal.h>
#include "turbo_input_client.h"

#include <jni.h>
#include <android/log.h>
#include <string.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <pthread.h>

#define LOG_TAG "JujostreamBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

// ============================================================================
// Global state (shared with callbacks.c)
// ============================================================================

// Oboe renderer instance
void* g_oboeRenderer = NULL;
extern int OboeRenderer_GetQueuedDurationMs(void* renderer);
extern uint64_t OboeRenderer_GetOverflowPackets(void* renderer);
extern uint64_t OboeRenderer_GetUnderrunCallbacks(void* renderer);

JavaVM* g_jvm = NULL;
jclass g_bridgeClass = NULL;

// Callback method IDs (Kotlin static methods called from C)
jmethodID g_onVideoSetup = NULL;
jmethodID g_onVideoStart = NULL;
jmethodID g_onVideoStop = NULL;
jmethodID g_onVideoCleanup = NULL;
jmethodID g_onVideoFrame = NULL;
jmethodID g_onAudioInit = NULL;
jmethodID g_onAudioStart = NULL;
jmethodID g_onAudioStop = NULL;
jmethodID g_onAudioCleanup = NULL;
jmethodID g_onAudioSample = NULL;
jmethodID g_onAudioSampleShort = NULL;
jmethodID g_onConnectionStarted = NULL;
jmethodID g_onConnectionTerminated = NULL;
jmethodID g_onStageStarting = NULL;
jmethodID g_onStageComplete = NULL;
jmethodID g_onStageFailed = NULL;
jmethodID g_onConnectionStatusUpdate = NULL;
jmethodID g_onRumble = NULL;
jmethodID g_onRumbleTriggers = NULL;
jmethodID g_onSetMotionEventState = NULL;
jmethodID g_onSetControllerLED = NULL;
jmethodID g_onSetAdaptiveTriggers = NULL;
jmethodID g_onSetHdrMode = NULL;

// Video frame buffer (reusable, grows as needed)
jobject g_videoFrameBuffer = NULL;

// ============================================================================
// Thread-local JNIEnv management
// ============================================================================
static pthread_key_t g_jniEnvKey;
static pthread_once_t g_jniEnvKeyOnce = PTHREAD_ONCE_INIT;

static void detachThread(void* unused) {
    (*g_jvm)->DetachCurrentThread(g_jvm);
}

static void initJniEnvKey(void) {
    pthread_key_create(&g_jniEnvKey, detachThread);
}

JNIEnv* GetThreadEnv(void) {
    JNIEnv* env;

    // Already attached?
    if ((*g_jvm)->GetEnv(g_jvm, (void**)&env, JNI_VERSION_1_6) == JNI_OK) {
        return env;
    }

    // Create TLS key
    pthread_once(&g_jniEnvKeyOnce, initJniEnvKey);

    // Check TLS
    env = pthread_getspecific(g_jniEnvKey);
    if (env) return env;

    // Attach this thread
    (*g_jvm)->AttachCurrentThread(g_jvm, &env, NULL);
    pthread_setspecific(g_jniEnvKey, env);

    return env;
}

// ============================================================================
// JNI_OnLoad
// ============================================================================
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_jvm = vm;
    LOGI("jujostream_native library loaded");
    return JNI_VERSION_1_6;
}

// ============================================================================
// Initialization
// ============================================================================
JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeInit(
        JNIEnv* env, jclass clazz) {
    LOGI("Initializing native bridge");

    g_bridgeClass = (*env)->NewGlobalRef(env, clazz);

    // Video callbacks
    g_onVideoSetup = (*env)->GetStaticMethodID(env, clazz, "onVideoSetup", "(IIII)I");
    g_onVideoFrame = (*env)->GetStaticMethodID(env, g_bridgeClass, "onVideoFrame", "(Ljava/nio/ByteBuffer;IIIIJJ)I");

    // Audio callbacks
    g_onAudioInit = (*env)->GetStaticMethodID(env, clazz, "onAudioInit", "(III)I");
    g_onAudioSample = (*env)->GetStaticMethodID(env, clazz, "onAudioSample", "([BI)V");
    g_onAudioSampleShort = (*env)->GetStaticMethodID(env, clazz, "onAudioSampleShort", "([SI)V");

    // Connection callbacks
    g_onConnectionStarted = (*env)->GetStaticMethodID(env, clazz, "onConnectionStarted", "()V");
    g_onConnectionTerminated = (*env)->GetStaticMethodID(env, clazz, "onConnectionTerminated", "(I)V");
    g_onStageStarting = (*env)->GetStaticMethodID(env, clazz, "onStageStarting", "(I)V");
    g_onStageComplete = (*env)->GetStaticMethodID(env, clazz, "onStageComplete", "(I)V");
    g_onStageFailed = (*env)->GetStaticMethodID(env, clazz, "onStageFailed", "(II)V");
    g_onConnectionStatusUpdate = (*env)->GetStaticMethodID(env, clazz, "onConnectionStatusUpdate", "(I)V");
    g_onRumble = (*env)->GetStaticMethodID(env, clazz, "onRumble", "(SSS)V");
    g_onRumbleTriggers = (*env)->GetStaticMethodID(env, clazz, "onRumbleTriggers", "(SSS)V");
    g_onSetMotionEventState = (*env)->GetStaticMethodID(env, clazz, "onSetMotionEventState", "(SBS)V");
    g_onSetControllerLED = (*env)->GetStaticMethodID(env, clazz, "onSetControllerLED", "(SBBB)V");
    g_onSetAdaptiveTriggers = (*env)->GetStaticMethodID(env, clazz, "onSetAdaptiveTriggers", "(SBBB[B[B)V");

    LOGI("Native bridge initialized - all method IDs resolved");
}

// ============================================================================
// Forward declarations for callbacks (defined in callbacks.c)
// ============================================================================
extern int BridgeVideoSetup(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags);
extern void BridgeVideoStart(void);
extern void BridgeVideoStop(void);
extern void BridgeVideoCleanup(void);
extern int BridgeVideoSubmitDecodeUnit(PDECODE_UNIT decodeUnit);
extern int BridgeAudioInit(int audioConfiguration, POPUS_MULTISTREAM_CONFIGURATION opusConfig, void* context, int flags);
extern void BridgeAudioStart(void);
extern void BridgeAudioStop(void);
extern void BridgeAudioCleanup(void);
extern void BridgeAudioDecodeAndPlaySample(char* sampleData, int sampleLength);
extern void BridgeConnectionStarted(void);
extern void BridgeConnectionTerminated(int errorCode);
extern void BridgeStageStarting(int stage);
extern void BridgeStageComplete(int stage);
extern void BridgeStageFailed(int stage, int errorCode);
extern void BridgeConnectionStatusUpdate(int connectionStatus);
extern void BridgeRumble(unsigned short controllerNumber, unsigned short lowFreqMotor, unsigned short highFreqMotor);
extern void BridgeLogMessage(const char* format, ...);
extern void BridgeSetHdrMode(bool enabled);
extern void BridgeRumbleTriggers(uint16_t controllerNumber, uint16_t leftTrigger, uint16_t rightTrigger);
extern void BridgeSetMotionEventState(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz);
extern void BridgeSetControllerLED(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b);
extern void BridgeSetAdaptiveTriggers(uint16_t controllerNumber, uint8_t eventFlags, uint8_t typeLeft, uint8_t typeRight, uint8_t* left, uint8_t* right);

// ============================================================================
// Callback struct instances
// ============================================================================
static DECODER_RENDERER_CALLBACKS BridgeVideoCallbacks = {
    .setup = BridgeVideoSetup,
    .start = BridgeVideoStart,
    .stop = BridgeVideoStop,
    .cleanup = BridgeVideoCleanup,
    .submitDecodeUnit = BridgeVideoSubmitDecodeUnit,
};

static AUDIO_RENDERER_CALLBACKS BridgeAudioCallbacks = {
    .init = BridgeAudioInit,
    .start = BridgeAudioStart,
    .stop = BridgeAudioStop,
    .cleanup = BridgeAudioCleanup,
    .decodeAndPlaySample = BridgeAudioDecodeAndPlaySample,
    .capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION,
};

static CONNECTION_LISTENER_CALLBACKS BridgeConnCallbacks = {
    .stageStarting = BridgeStageStarting,
    .stageComplete = BridgeStageComplete,
    .stageFailed = BridgeStageFailed,
    .connectionStarted = BridgeConnectionStarted,
    .connectionTerminated = BridgeConnectionTerminated,
    .logMessage = BridgeLogMessage,
    .rumble = BridgeRumble,
    .connectionStatusUpdate = BridgeConnectionStatusUpdate,
    .setHdrMode = BridgeSetHdrMode,
    .rumbleTriggers = BridgeRumbleTriggers,
    .setMotionEventState = BridgeSetMotionEventState,
    .setControllerLED = BridgeSetControllerLED,
    .setAdaptiveTriggers = BridgeSetAdaptiveTriggers,
};

static char     g_turboHost[256] = {0};
static int      g_turboUdpPort   = 0;
static int      g_turboTcpPort   = 0;
static uint32_t g_turboSessionId = 0;
static char     g_turboKeyHex[96] = {0};

static void turboAndroidOnAdaptiveTriggers(
        uint16_t controllerNumber,
        uint8_t eventFlags,
        uint8_t typeLeft,
        uint8_t typeRight,
        const uint8_t* left,
        const uint8_t* right) {
    BridgeSetAdaptiveTriggers(
        controllerNumber, eventFlags, typeLeft, typeRight,
        (uint8_t*)left, (uint8_t*)right);
}

void moonlightAndroidOnConnectionStarted(void) {
    if (g_turboSessionId == 0 || g_turboHost[0] == '\0' || g_turboKeyHex[0] == '\0') {
        return;
    }
    TurboFeedbackCallbacks fb = {
        .onRumble = BridgeRumble,
        .onRumbleTriggers = BridgeRumbleTriggers,
        .onSetMotionEventState = BridgeSetMotionEventState,
        .onSetControllerLED = BridgeSetControllerLED,
        .onSetAdaptiveTriggers = turboAndroidOnAdaptiveTriggers,
    };
    bool ok = turboClientStart(
        g_turboHost, g_turboUdpPort, g_turboTcpPort, g_turboSessionId, g_turboKeyHex, &fb);
    LOGI("turboClientStart ok=%d udp=%d tcp=%d sid=%u",
         ok ? 1 : 0, g_turboUdpPort, g_turboTcpPort, (unsigned)g_turboSessionId);
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeConfigureTurboInput(
        JNIEnv* env, jclass clazz,
        jint udpPort, jint tcpPort, jlong sessionId, jstring keyHex) {
    (void)clazz;
    g_turboUdpPort = udpPort;
    g_turboTcpPort = tcpPort;
    g_turboSessionId = sessionId > 0 ? (uint32_t)sessionId : 0;
    if (keyHex) {
        const char* chars = (*env)->GetStringUTFChars(env, keyHex, NULL);
        if (chars) {
            snprintf(g_turboKeyHex, sizeof(g_turboKeyHex), "%s", chars);
            (*env)->ReleaseStringUTFChars(env, keyHex, chars);
        } else {
            g_turboKeyHex[0] = '\0';
        }
    } else {
        g_turboKeyHex[0] = '\0';
    }
}

JNIEXPORT jlongArray JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeGetTurboInputStats(
        JNIEnv* env, jclass clazz) {
    (void)clazz;
    TurboClientStats s = turboClientGetStats();
    jlong vals[5] = {
        s.active ? 1 : 0,
        s.usingTcp ? 1 : 0,
        (jlong)s.lastRttUs,
        (jlong)s.packetsSent,
        (jlong)s.packetsRecv
    };
    jlongArray arr = (*env)->NewLongArray(env, 5);
    if (arr != NULL) {
        (*env)->SetLongArrayRegion(env, arr, 0, 5, vals);
    }
    return arr;
}

// ============================================================================
// Start Connection - The main entry point to begin streaming
// ============================================================================
JNIEXPORT jint JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeStartConnection(
        JNIEnv* env, jclass clazz,
        jstring address, jstring appVersion, jstring gfeVersion,
        jstring rtspSessionUrl, jint serverCodecModeSupport,
        jint width, jint height, jint fps,
        jint bitrate, jint packetSize, jint streamingRemotely,
        jint audioConfiguration, jint supportedVideoFormats,
        jint clientRefreshRateX100,
        jbyteArray riAesKey, jbyteArray riAesIv,
        jint videoCapabilities,
        jint colorSpace, jint colorRange,
        jboolean slowOpusDecoder,
        jint audioPacketDuration) {

    LOGI("Starting connection: %dx%d@%dfps, bitrate=%d", width, height, fps, bitrate);

    SERVER_INFORMATION serverInfo;
    LiInitializeServerInformation(&serverInfo);
    serverInfo.address = (*env)->GetStringUTFChars(env, address, NULL);
    serverInfo.serverInfoAppVersion = (*env)->GetStringUTFChars(env, appVersion, NULL);
    serverInfo.serverInfoGfeVersion = gfeVersion ? (*env)->GetStringUTFChars(env, gfeVersion, NULL) : NULL;
    serverInfo.rtspSessionUrl = rtspSessionUrl ? (*env)->GetStringUTFChars(env, rtspSessionUrl, NULL) : NULL;
    serverInfo.serverCodecModeSupport = serverCodecModeSupport;

    STREAM_CONFIGURATION streamConfig;
    LiInitializeStreamConfiguration(&streamConfig);
    streamConfig.width = width;
    streamConfig.height = height;
    streamConfig.fps = fps;
    streamConfig.bitrate = bitrate;
    streamConfig.packetSize = packetSize;
    streamConfig.streamingRemotely = streamingRemotely;
    streamConfig.audioConfiguration = audioConfiguration;
    // audioPacketDuration not supported in this version of moonlight-common-c
    (void)audioPacketDuration;
    streamConfig.supportedVideoFormats = supportedVideoFormats;
    streamConfig.clientRefreshRateX100 = clientRefreshRateX100;
    streamConfig.colorSpace = colorSpace;
    streamConfig.colorRange = colorRange;
    streamConfig.encryptionFlags = ENCFLG_ALL; // Match macOS: support all encryption modes for Sunshine compatibility

    // Copy AES key and IV
    if (riAesKey) {
        jbyte* keyBuf = (*env)->GetByteArrayElements(env, riAesKey, NULL);
        memcpy(streamConfig.remoteInputAesKey, keyBuf, sizeof(streamConfig.remoteInputAesKey));
        (*env)->ReleaseByteArrayElements(env, riAesKey, keyBuf, JNI_ABORT);
    }
    if (riAesIv) {
        jbyte* ivBuf = (*env)->GetByteArrayElements(env, riAesIv, NULL);
        memcpy(streamConfig.remoteInputAesIv, ivBuf, sizeof(streamConfig.remoteInputAesIv));
        (*env)->ReleaseByteArrayElements(env, riAesIv, ivBuf, JNI_ABORT);
    }

    // Set video capabilities
    BridgeVideoCallbacks.capabilities = videoCapabilities;

    // Set audio capabilities
    BridgeAudioCallbacks.capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;
    if (slowOpusDecoder) {
        BridgeAudioCallbacks.capabilities |= CAPABILITY_SLOW_OPUS_DECODER;
    }

    if (serverInfo.address) {
        snprintf(g_turboHost, sizeof(g_turboHost), "%s", serverInfo.address);
    } else {
        g_turboHost[0] = '\0';
    }

    // Start the connection!
    int ret = LiStartConnection(
        &serverInfo,
        &streamConfig,
        &BridgeConnCallbacks,
        &BridgeVideoCallbacks,
        &BridgeAudioCallbacks,
        NULL, 0,   // renderContext, drFlags
        NULL, 0    // audioContext, arFlags
    );

    if (ret != 0) {
        turboClientStop();
    }

    // Release strings
    (*env)->ReleaseStringUTFChars(env, address, serverInfo.address);
    (*env)->ReleaseStringUTFChars(env, appVersion, serverInfo.serverInfoAppVersion);
    if (gfeVersion) (*env)->ReleaseStringUTFChars(env, gfeVersion, serverInfo.serverInfoGfeVersion);
    if (rtspSessionUrl) (*env)->ReleaseStringUTFChars(env, rtspSessionUrl, serverInfo.rtspSessionUrl);

    LOGI("LiStartConnection returned: %d", ret);
    LOGI("AppVersionQuad: [%d, %d, %d, %d], IS_SUNSHINE=%d",
         AppVersionQuad[0], AppVersionQuad[1], AppVersionQuad[2], AppVersionQuad[3],
         IS_SUNSHINE() ? 1 : 0);
    return ret;
}

// ============================================================================
// Input sending functions
// ============================================================================

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendMouseMove(
        JNIEnv* env, jclass clazz, jshort deltaX, jshort deltaY) {
    LiSendMouseMoveEvent(deltaX, deltaY);
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendMousePosition(
        JNIEnv* env, jclass clazz, jshort x, jshort y, jshort refWidth, jshort refHeight) {
    LiSendMousePositionEvent(x, y, refWidth, refHeight);
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendMouseButton(
        JNIEnv* env, jclass clazz, jbyte action, jbyte button) {
    LiSendMouseButtonEvent(action, button);
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendKeyboard(
        JNIEnv* env, jclass clazz, jshort keyCode, jbyte keyAction, jbyte modifiers, jbyte flags) {
    LiSendKeyboardEvent2(keyCode, keyAction, modifiers, flags);
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendScroll(
        JNIEnv* env, jclass clazz, jshort scrollAmount) {
    LiSendHighResScrollEvent(scrollAmount);
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendHighResHScroll(
        JNIEnv* env, jclass clazz, jshort scrollAmount) {
    LiSendHighResHScrollEvent(scrollAmount);
}

JNIEXPORT jint JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendControllerInput(
        JNIEnv* env, jclass clazz,
        jshort controllerNumber, jshort activeGamepadMask,
        jint buttonFlags, jbyte leftTrigger, jbyte rightTrigger,
        jshort leftStickX, jshort leftStickY,
        jshort rightStickX, jshort rightStickY) {
    if (turboClientIsActive() &&
        controllerNumber >= 0 && controllerNumber < 8 &&
        turboClientSendGamepadState(
            (uint8_t)controllerNumber, (uint16_t)activeGamepadMask,
            (uint32_t)buttonFlags, (uint8_t)leftTrigger, (uint8_t)rightTrigger,
            leftStickX, leftStickY, rightStickX, rightStickY, 0)) {
        return 0;
    }
    return LiSendMultiControllerEvent(controllerNumber, activeGamepadMask, buttonFlags,
        leftTrigger, rightTrigger, leftStickX, leftStickY, rightStickX, rightStickY);
}

JNIEXPORT jint JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendControllerArrival(
        JNIEnv* env, jclass clazz,
        jshort controllerNumber, jshort activeGamepadMask,
        jbyte controllerType, jshort capabilities,
        jint supportedButtonFlags) {
    LOGI("ARRIVAL(C): slot=%d mask=0x%x type=%d btnFlags=0x%x caps=0x%x IS_SUNSHINE=%d",
         (int)controllerNumber, (int)activeGamepadMask, (int)controllerType,
         (int)supportedButtonFlags, (int)capabilities,
         IS_SUNSHINE() ? 1 : 0);
    if (turboClientIsActive() &&
        controllerNumber >= 0 && controllerNumber < 8 &&
        turboClientSendGamepadArrival(
            (uint8_t)controllerNumber, (uint8_t)controllerType,
            (uint16_t)capabilities, (uint32_t)supportedButtonFlags)) {
        return 0;
    }
    return LiSendControllerArrivalEvent(
        (uint8_t)controllerNumber,
        (uint16_t)activeGamepadMask,
        (uint8_t)controllerType,
        (uint32_t)supportedButtonFlags,
        (uint16_t)capabilities
    );
}

JNIEXPORT jint JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendTouchEvent(
        JNIEnv* env, jclass clazz,
        jbyte eventType, jint pointerId,
        jfloat x, jfloat y, jfloat pressureOrDistance,
        jfloat contactAreaMajor, jfloat contactAreaMinor,
        jshort rotation) {
    return LiSendTouchEvent(eventType, pointerId, x, y, pressureOrDistance,
                            contactAreaMajor, contactAreaMinor, rotation);
}

JNIEXPORT jint JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendControllerTouchEvent(
        JNIEnv* env, jclass clazz,
        jshort controllerNumber, jbyte eventType, jint pointerId,
        jfloat x, jfloat y, jfloat pressure) {
    if (turboClientIsActive() &&
        controllerNumber >= 0 && controllerNumber < 8 &&
        turboClientSendGamepadTouch(
            (uint8_t)controllerNumber, (uint8_t)eventType, (uint32_t)pointerId, x, y, pressure)) {
        return 0;
    }
    return LiSendControllerTouchEvent((uint8_t)controllerNumber, (uint8_t)eventType,
                                      (uint32_t)pointerId, x, y, pressure);
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendUtf8Text(
        JNIEnv* env, jclass clazz, jstring text) {
    const char* utf8Text = (*env)->GetStringUTFChars(env, text, NULL);
    LiSendUtf8TextEvent(utf8Text, strlen(utf8Text));
    (*env)->ReleaseStringUTFChars(env, text, utf8Text);
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendControllerMotionEvent(
        JNIEnv* env, jclass clazz,
        jshort controllerNumber, jbyte motionType,
        jfloat x, jfloat y, jfloat z) {
    if (turboClientIsActive() &&
        controllerNumber >= 0 && controllerNumber < 8 &&
        turboClientSendGamepadMotion(
            (uint8_t)controllerNumber, (uint8_t)motionType, x, y, z)) {
        return;
    }
    LiSendControllerMotionEvent((uint8_t)controllerNumber, (uint8_t)motionType, x, y, z);
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeSendControllerBattery(
        JNIEnv* env, jclass clazz,
        jshort controllerNumber, jbyte batteryState, jbyte batteryPercentage) {
    LiSendControllerBatteryEvent((uint8_t)controllerNumber, (uint8_t)batteryState, (uint8_t)batteryPercentage);
}

// Client microphone passthrough (Oboe capture -> Opus -> LiSendMicPacket).
extern int MicCapturer_Start(void);
extern void MicCapturer_Stop(void);

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeStopConnection(
        JNIEnv* env, jclass clazz) {
    LOGI("Stopping connection");
    turboClientStop();
    MicCapturer_Stop();  // safety net in case the app didn't stop it explicitly
    LiStopConnection();
}

JNIEXPORT jint JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeStartMicCapture(
        JNIEnv* env, jclass clazz) {
    LOGI("Starting mic capture");
    return MicCapturer_Start();
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeStopMicCapture(
        JNIEnv* env, jclass clazz) {
    LOGI("Stopping mic capture");
    MicCapturer_Stop();
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeInterruptConnection(
        JNIEnv* env, jclass clazz) {
    LOGI("Interrupting connection");
    LiInterruptConnection();
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeRequestIdrFrame(
        JNIEnv* env, jclass clazz) {
    LOGI("Requesting fresh IDR frame for privacy reveal");
    LiRequestIdrFrame();
}

JNIEXPORT jint JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeGetPendingVideoFrames(
        JNIEnv* env, jclass clazz) {
    return LiGetPendingVideoFrames();
}

JNIEXPORT jint JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeGetPendingAudioDuration(
        JNIEnv* env, jclass clazz) {
    return LiGetPendingAudioDuration();
}

JNIEXPORT jlongArray JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeGetAudioRendererMetrics(
        JNIEnv* env, jclass clazz) {
    jlong values[3] = {0, 0, 0};
    // These access process-wide atomics, so renderer destruction cannot race metrics reads.
    values[0] = OboeRenderer_GetQueuedDurationMs(NULL);
    values[1] = (jlong)OboeRenderer_GetOverflowPackets(NULL);
    values[2] = (jlong)OboeRenderer_GetUnderrunCallbacks(NULL);
    jlongArray result = (*env)->NewLongArray(env, 3);
    if (result != NULL) {
        (*env)->SetLongArrayRegion(env, result, 0, 3, values);
    }
    return result;
}

JNIEXPORT jstring JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeGetStageName(
        JNIEnv* env, jclass clazz, jint stage) {
    return (*env)->NewStringUTF(env, LiGetStageName(stage));
}

JNIEXPORT jlong JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeGetEstimatedRttInfo(
        JNIEnv* env, jclass clazz) {
    uint32_t rtt, variance;
    if (!LiGetEstimatedRttInfo(&rtt, &variance)) {
        return -1;
    }
    return ((uint64_t)rtt << 32U) | variance;
}

JNIEXPORT jlongArray JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeGetVrrClockSyncStats(
        JNIEnv* env, jclass clazz) {
    int64_t offsetUs = 0;
    uint64_t rttUs = 0;
    uint32_t sampleCount = 0;
    if (!LiGetVrrClockSyncStats(&offsetUs, &rttUs, &sampleCount)) {
        return NULL;
    }
    jlongArray arr = (*env)->NewLongArray(env, 3);
    if (arr == NULL) {
        return NULL;
    }
    jlong vals[3] = {
        (jlong)offsetUs,
        (jlong)rttUs,
        (jlong)sampleCount
    };
    (*env)->SetLongArrayRegion(env, arr, 0, 3, vals);
    return arr;
}

JNIEXPORT jboolean JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeTriggerRoam(
        JNIEnv* env, jclass clazz) {
    return LiTriggerConnectionRoam() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlongArray JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeGetRoamingStats(
        JNIEnv* env, jclass clazz) {
    bool supported = false;
    uint32_t migrations = 0;
    uint64_t lastMigrationUs = 0;
    LiGetRoamingStats(&supported, &migrations, &lastMigrationUs);
    jlongArray arr = (*env)->NewLongArray(env, 3);
    if (arr == NULL) {
        return NULL;
    }
    jlong vals[3] = {
        supported ? 1 : 0,
        (jlong)migrations,
        (jlong)lastMigrationUs
    };
    (*env)->SetLongArrayRegion(env, arr, 0, 3, vals);
    return arr;
}
