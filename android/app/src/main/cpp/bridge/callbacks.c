// moonlight-common-c callback implementations.
// Forwards video/audio/connection events to Kotlin via JNI.

#include <Limelight.h>

#include <jni.h>
#include <android/log.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#define LOG_TAG "JujostreamCallbacks"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern void* OboeRenderer_Create();
extern void OboeRenderer_Destroy(void* renderer);
extern int OboeRenderer_Start(void* renderer, int channelCount, int sampleRate, int samplesPerFrame);
extern void OboeRenderer_Stop(void* renderer);
extern void OboeRenderer_SubmitSamples(void* renderer, const int16_t* pcm, int sampleCount);

// Oboe renderer instance (managed from JNI, see moonlight_bridge.c)
extern void* g_oboeRenderer;  // void* when Oboe is active, NULL otherwise

// Globals from moonlight_bridge.c
extern JavaVM* g_jvm;
extern jclass g_bridgeClass;
extern jmethodID g_onVideoSetup;
extern jmethodID g_onVideoFrame;
extern jmethodID g_onAudioInit;
extern jmethodID g_onAudioSample;
extern jmethodID g_onAudioSampleShort;
extern jmethodID g_onConnectionStarted;
extern jmethodID g_onConnectionTerminated;
extern jmethodID g_onStageStarting;
extern jmethodID g_onStageComplete;
extern jmethodID g_onStageFailed;
extern jmethodID g_onConnectionStatusUpdate;
extern jmethodID g_onRumble;
extern jmethodID g_onRumbleTriggers;
extern jmethodID g_onSetMotionEventState;
extern jmethodID g_onSetControllerLED;
extern jobject g_videoFrameBuffer;
void* g_videoFrameData = NULL;
int g_videoFrameCapacity = 0;
extern JNIEnv* GetThreadEnv(void);

// ============================================================================
// Video Decoder Callbacks
// ============================================================================

int BridgeVideoSetup(int videoFormat, int width, int height, int redrawRate,
                     void* context, int drFlags) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass || !g_onVideoSetup) return -1;

    LOGI("Video setup: %dx%d@%d, format=0x%x", width, height, redrawRate, videoFormat);

    int err = (*env)->CallStaticIntMethod(env, g_bridgeClass, g_onVideoSetup,
        videoFormat, width, height, redrawRate);

    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
        return -1;
    }

    if (err == 0) {
        // Pre-allocate a 1MB direct byte buffer to avoid frequent resizing and JNI array copies
        // Guard against memory leaks if BridgeVideoSetup is called multiple times
        if (g_videoFrameData == NULL) {
            g_videoFrameCapacity = 1024 * 1024;
            g_videoFrameData = malloc(g_videoFrameCapacity);
            if (g_videoFrameData) {
                jobject localBuf = (*env)->NewDirectByteBuffer(env, g_videoFrameData, g_videoFrameCapacity);
                g_videoFrameBuffer = (*env)->NewGlobalRef(env, localBuf);
                (*env)->DeleteLocalRef(env, localBuf);
            } else {
                LOGE("Failed to allocate direct byte buffer memory!");
                return -1;
            }
        }
    }

    return err;
}

void BridgeVideoStart(void) {
    LOGI("Video decoder started");
}

void BridgeVideoStop(void) {
    LOGI("Video decoder stopped");
}

void BridgeVideoCleanup(void) {
    JNIEnv* env = GetThreadEnv();
    if (env && g_videoFrameBuffer) {
        (*env)->DeleteGlobalRef(env, g_videoFrameBuffer);
        g_videoFrameBuffer = NULL;
    }
    if (g_videoFrameData) {
        free(g_videoFrameData);
        g_videoFrameData = NULL;
        g_videoFrameCapacity = 0;
    }
    LOGI("Video decoder cleaned up");
}

int BridgeVideoSubmitDecodeUnit(PDECODE_UNIT decodeUnit) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass || !g_onVideoFrame) return DR_OK;

    // Grow the direct buffer if needed
    if (decodeUnit->fullLength > g_videoFrameCapacity) {
        (*env)->DeleteGlobalRef(env, g_videoFrameBuffer);
        free(g_videoFrameData);
        
        g_videoFrameCapacity = decodeUnit->fullLength * 2; // double capacity to avoid frequent allocs
        g_videoFrameData = malloc(g_videoFrameCapacity);
        if (!g_videoFrameData) {
            LOGE("Failed to grow direct byte buffer to %d bytes", g_videoFrameCapacity);
            return DR_NEED_IDR; // Can't submit this frame, drop and request IDR
        }
        
        jobject localBuf = (*env)->NewDirectByteBuffer(env, g_videoFrameData, g_videoFrameCapacity);
        g_videoFrameBuffer = (*env)->NewGlobalRef(env, localBuf);
        (*env)->DeleteLocalRef(env, localBuf);
        
        LOGI("Video direct buffer grew to %d bytes", g_videoFrameCapacity);
    }

    PLENTRY currentEntry = decodeUnit->bufferList;
    int offset = 0;
    int ret;

    while (currentEntry != NULL) {
        // Submit parameter set NALUs (SPS/PPS/VPS) separately from picture data
        if (currentEntry->bufferType != BUFFER_TYPE_PICDATA) {
            // Copy this parameter set to the beginning of the buffer using fast memcpy
            memcpy(g_videoFrameData, currentEntry->data, currentEntry->length);

            ret = (*env)->CallStaticIntMethod(env, g_bridgeClass, g_onVideoFrame,
                g_videoFrameBuffer, currentEntry->length, currentEntry->bufferType,
                decodeUnit->frameNumber, decodeUnit->frameType,
                (jlong)decodeUnit->receiveTimeMs, (jlong)decodeUnit->enqueueTimeMs);

            if ((*env)->ExceptionCheck(env)) {
                (*env)->ExceptionClear(env);
                return DR_OK;
            }
            if (ret != DR_OK) return ret;
        } else {
            // Accumulate picture data
            memcpy((char*)g_videoFrameData + offset, currentEntry->data, currentEntry->length);
            offset += currentEntry->length;
        }

        currentEntry = currentEntry->next;
    }

    // Submit the accumulated picture data
    if (offset > 0) {
        ret = (*env)->CallStaticIntMethod(env, g_bridgeClass, g_onVideoFrame,
            g_videoFrameBuffer, offset, BUFFER_TYPE_PICDATA,
            decodeUnit->frameNumber, decodeUnit->frameType,
            (jlong)decodeUnit->receiveTimeMs, (jlong)decodeUnit->enqueueTimeMs);

        if ((*env)->ExceptionCheck(env)) {
            (*env)->ExceptionClear(env);
            return DR_OK;
        }
        return ret;
    }

    return DR_OK;
}

// ============================================================================
// Audio Renderer Callbacks
// ============================================================================

// Opus decoder state (audio is decoded in C, PCM sent to Kotlin)
#include <opus_multistream.h>
static OpusMSDecoder* g_opusDecoder = NULL;
static OPUS_MULTISTREAM_CONFIGURATION g_opusConfig;
static jshortArray g_decodedAudioBuffer = NULL;

int BridgeAudioInit(int audioConfiguration,
                    POPUS_MULTISTREAM_CONFIGURATION opusConfig,
                    void* context, int flags) {
    LOGI("Audio init: config=%d, rate=%d, channels=%d, spf=%d",
         audioConfiguration, opusConfig->sampleRate,
         opusConfig->channelCount, opusConfig->samplesPerFrame);

    // Save Opus config and create decoder (needed for both Oboe and AudioTrack paths)
    memcpy(&g_opusConfig, opusConfig, sizeof(g_opusConfig));

    int opusErr;
    g_opusDecoder = opus_multistream_decoder_create(
        opusConfig->sampleRate,
        opusConfig->channelCount,
        opusConfig->streams,
        opusConfig->coupledStreams,
        opusConfig->mapping,
        &opusErr);

    if (g_opusDecoder == NULL) {
        LOGE("Failed to create Opus decoder: %d", opusErr);
        return -1;
    }

    // Enable in-band FEC decoding for loss recovery
    opus_multistream_decoder_ctl(g_opusDecoder, OPUS_SET_INBAND_FEC(1));

    // If Oboe renderer is active, start it directly
    if (!g_oboeRenderer) {
        g_oboeRenderer = OboeRenderer_Create();
    }

    if (g_oboeRenderer) {
        int err = OboeRenderer_Start(g_oboeRenderer,
                              opusConfig->channelCount,
                              opusConfig->sampleRate,
                              opusConfig->samplesPerFrame);
        if (err == 0) {
            LOGI("Oboe audio renderer started — bypassing AudioTrack");
            return 0;
        }
        LOGW("Oboe start failed — falling back to AudioTrack");
        OboeRenderer_Destroy(g_oboeRenderer);
        g_oboeRenderer = NULL;
    }

    // Fallback: Tell Kotlin to set up AudioTrack
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass || !g_onAudioInit) return -1;

    int err = (*env)->CallStaticIntMethod(env, g_bridgeClass, g_onAudioInit,
        audioConfiguration, opusConfig->sampleRate, opusConfig->samplesPerFrame);

    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
        return -1;
    }

    if (err == 0) {
        // Pre-allocate decoded audio buffer for JNI path
        g_decodedAudioBuffer = (*env)->NewGlobalRef(env,
            (*env)->NewShortArray(env,
                opusConfig->channelCount * opusConfig->samplesPerFrame));
        LOGI("Opus decoder + AudioTrack created successfully");
    }

    return err;
}

void BridgeAudioStart(void) {
    LOGI("Audio renderer started");
}

void BridgeAudioStop(void) {
    LOGI("Audio renderer stopped");
}

void BridgeAudioCleanup(void) {
    if (g_oboeRenderer) {
        OboeRenderer_Stop(g_oboeRenderer);
        OboeRenderer_Destroy(g_oboeRenderer);
        g_oboeRenderer = NULL;
        LOGI("Oboe audio renderer stopped and destroyed");
    }

    if (g_opusDecoder) {
        opus_multistream_decoder_destroy(g_opusDecoder);
        g_opusDecoder = NULL;
    }

    JNIEnv* env = GetThreadEnv();
    if (env && g_decodedAudioBuffer) {
        (*env)->DeleteGlobalRef(env, g_decodedAudioBuffer);
        g_decodedAudioBuffer = NULL;
    }

    LOGI("Audio renderer cleaned up");
}

void BridgeAudioDecodeAndPlaySample(char* sampleData, int sampleLength) {
    if (!g_opusDecoder) return;

    // Oboe path: decode into stack buffer and push to ring buffer
    if (g_oboeRenderer) {
        int16_t decodeBuf[8 * 480];  // max: 8ch * 480 spf (10ms @ 48kHz)
        int decodeLen = opus_multistream_decode(
            g_opusDecoder,
            (const unsigned char*)sampleData,
            sampleLength,
            decodeBuf,
            g_opusConfig.samplesPerFrame,
            sampleData == NULL ? 1 : 0);

        if (decodeLen > 0) {
            int sampleCount = decodeLen * g_opusConfig.channelCount;
            OboeRenderer_SubmitSamples(g_oboeRenderer, decodeBuf, sampleCount);
        }
        return;
    }

    // Fallback: JNI → AudioTrack path
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_decodedAudioBuffer) return;

    jshort* decodedData = (*env)->GetPrimitiveArrayCritical(env, g_decodedAudioBuffer, NULL);

    int decodeLen = opus_multistream_decode(
        g_opusDecoder,
        (const unsigned char*)sampleData,
        sampleLength,
        decodedData,
        g_opusConfig.samplesPerFrame,
        sampleData == NULL ? 1 : 0);

    if (decodeLen > 0) {
        (*env)->ReleasePrimitiveArrayCritical(env, g_decodedAudioBuffer, decodedData, 0);

        int sampleCount = decodeLen * g_opusConfig.channelCount;
        (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_onAudioSampleShort,
            g_decodedAudioBuffer, sampleCount);

        if ((*env)->ExceptionCheck(env)) {
            (*env)->ExceptionClear(env);
        }
    } else {
        (*env)->ReleasePrimitiveArrayCritical(env, g_decodedAudioBuffer, decodedData, JNI_ABORT);
    }
}

// ============================================================================
// Connection Listener Callbacks
// ============================================================================

void BridgeStageStarting(int stage) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass) return;
    (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_onStageStarting, stage);
    LOGI("Stage starting: %d (%s)", stage, LiGetStageName(stage));
}

void BridgeStageComplete(int stage) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass) return;
    (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_onStageComplete, stage);
    LOGI("Stage complete: %d", stage);
}

void BridgeStageFailed(int stage, int errorCode) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass) return;
    (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_onStageFailed, stage, errorCode);
    LOGE("Stage %d failed: %d", stage, errorCode);
}

void BridgeConnectionStarted(void) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass) return;
    (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_onConnectionStarted);
    LOGI("Connection started successfully");
}

void BridgeConnectionTerminated(int errorCode) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass) return;
    (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_onConnectionTerminated, errorCode);
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
    }
    LOGE("Connection terminated: %d", errorCode);
}

void BridgeConnectionStatusUpdate(int connectionStatus) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass) return;
    (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_onConnectionStatusUpdate, connectionStatus);
}

void BridgeRumble(unsigned short controllerNumber, unsigned short lowFreqMotor, unsigned short highFreqMotor) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass) return;
    (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_onRumble,
        (jshort)controllerNumber, (jshort)lowFreqMotor, (jshort)highFreqMotor);
}

void BridgeSetHdrMode(bool enabled) {
    LOGI("HDR mode: %s", enabled ? "enabled" : "disabled");
    // Not yet implemented: forward to Kotlin for HDR display mode switching
}

void BridgeRumbleTriggers(uint16_t controllerNumber, uint16_t leftTrigger, uint16_t rightTrigger) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass || !g_onRumbleTriggers) return;
    (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_onRumbleTriggers,
        (jshort)controllerNumber, (jshort)leftTrigger, (jshort)rightTrigger);
}

void BridgeSetMotionEventState(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass || !g_onSetMotionEventState) return;
    (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_onSetMotionEventState,
        (jshort)controllerNumber, (jbyte)motionType, (jshort)reportRateHz);
}

void BridgeSetControllerLED(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b) {
    JNIEnv* env = GetThreadEnv();
    if (!env || !g_bridgeClass || !g_onSetControllerLED) return;
    (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_onSetControllerLED,
        (jshort)controllerNumber, (jbyte)r, (jbyte)g, (jbyte)b);
}

void BridgeLogMessage(const char* format, ...) {
    va_list va;
    va_start(va, format);
    __android_log_vprint(ANDROID_LOG_INFO, "moonlight-common-c", format, va);
    va_end(va);
}

#ifdef __cplusplus
}  // extern "C"
#endif
