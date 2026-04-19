// JNI bridge between Kotlin and moonlight-common-c.

#include <Limelight.h>
#include <Limelight-internal.h>

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
};

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
    LiSendControllerMotionEvent((uint8_t)controllerNumber, (uint8_t)motionType, x, y, z);
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeStopConnection(
        JNIEnv* env, jclass clazz) {
    LOGI("Stopping connection");
    LiStopConnection();
}

JNIEXPORT void JNICALL
Java_com_limelight_jujostream_native_1bridge_StreamingBridge_nativeInterruptConnection(
        JNIEnv* env, jclass clazz) {
    LOGI("Interrupting connection");
    LiInterruptConnection();
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
