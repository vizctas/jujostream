// moonlight-common-c callback implementations for macOS.
// Calls Swift via g_macCallbacks function pointers.

#include "moonlight_bridge_mac.h"
#include "CoreAudioRenderer.h"
#include <Limelight.h>
#include <opus_multistream.h>
#include <string.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

// Access the global callback table from moonlight_bridge_mac.c
extern JujostreamMacCallbacks *moonlightMacGetCallbacks(void);

// ---------------------------------------------------------------------------
// Video frame assembly buffer
// ---------------------------------------------------------------------------
static uint8_t *g_videoFrameBuf    = NULL;
static int      g_videoFrameBufLen = 0;

static int ensureVideoBuffer(int needed) {
    if (needed <= g_videoFrameBufLen) return 1;
    uint8_t *nb = (uint8_t *)realloc(g_videoFrameBuf, (size_t)needed);
    if (!nb) return 0;
    g_videoFrameBuf    = nb;
    g_videoFrameBufLen = needed;
    return 1;
}

// ---------------------------------------------------------------------------
// Video Decoder Callbacks
// ---------------------------------------------------------------------------

static int BridgeMacVideoSetup(int videoFormat, int width, int height,
                                int redrawRate, void *context, int drFlags) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onVideoSetup)
        return cbs->onVideoSetup(videoFormat, width, height, redrawRate);
    return -1;
}

static void BridgeMacVideoStart(void) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onVideoStart) cbs->onVideoStart();
}

static void BridgeMacVideoStop(void) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onVideoStop) cbs->onVideoStop();
}

static void BridgeMacVideoCleanup(void) {
    free(g_videoFrameBuf);
    g_videoFrameBuf    = NULL;
    g_videoFrameBufLen = 0;

    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onVideoCleanup) cbs->onVideoCleanup();
}

static int BridgeMacVideoSubmitDecodeUnit(PDECODE_UNIT decodeUnit) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (!cbs->onVideoFrame) return DR_OK;

    if (!ensureVideoBuffer(decodeUnit->fullLength)) return DR_OK;

    PLENTRY entry  = decodeUnit->bufferList;
    int     offset = 0;
    int     ret    = DR_OK;

    while (entry != NULL) {
        if (entry->bufferType != BUFFER_TYPE_PICDATA) {
            // Forward parameter-set NALUs immediately
            ret = cbs->onVideoFrame(
                (const uint8_t *)entry->data,
                entry->length,
                entry->bufferType,
                decodeUnit->frameNumber,
                (int64_t)(decodeUnit->receiveTimeUs / 1000));
            if (ret != DR_OK) return ret;
        } else {
            // Accumulate picture data
            memcpy(g_videoFrameBuf + offset, entry->data, (size_t)entry->length);
            offset += entry->length;
        }
        entry = entry->next;
    }

    if (offset > 0) {
        ret = cbs->onVideoFrame(
            g_videoFrameBuf,
            offset,
            BUFFER_TYPE_PICDATA,
            decodeUnit->frameNumber,
            (int64_t)(decodeUnit->receiveTimeUs / 1000));
    }

    return ret;
}

// ---------------------------------------------------------------------------
// Audio Renderer Callbacks
// ---------------------------------------------------------------------------

static OpusMSDecoder             *g_opusDecoder   = NULL;
static OPUS_MULTISTREAM_CONFIGURATION g_opusConfig;
static int16_t                   *g_pcmBuf        = NULL;
static int                        g_pcmBufSamples = 0; // total PCM samples (ch * spf)

// CoreAudio direct path flag (set during init)
static bool g_useCoreAudioDirect = false;
static uint64_t g_audioDecodeCount = 0;
static uint64_t g_audioDecodeErrors = 0;

static int BridgeMacAudioInit(int audioConfiguration,
                               POPUS_MULTISTREAM_CONFIGURATION opusConfig,
                               void *context, int flags) {
    // Always create Opus decoder first (needed by both render paths)
    memcpy(&g_opusConfig, opusConfig, sizeof(OPUS_MULTISTREAM_CONFIGURATION));

    int opusErr = 0;
    g_opusDecoder = opus_multistream_decoder_create(
        opusConfig->sampleRate,
        opusConfig->channelCount,
        opusConfig->streams,
        opusConfig->coupledStreams,
        opusConfig->mapping,
        &opusErr);
    if (!g_opusDecoder) return -1;

    // Enable in-band FEC decoding for loss recovery
    opus_multistream_decoder_ctl(g_opusDecoder, OPUS_SET_INBAND_FEC(1));

    g_pcmBufSamples = opusConfig->channelCount * opusConfig->samplesPerFrame;
    g_pcmBuf = (int16_t *)malloc((size_t)g_pcmBufSamples * sizeof(int16_t));
    if (!g_pcmBuf) {
        opus_multistream_decoder_destroy(g_opusDecoder);
        g_opusDecoder = NULL;
        return -1;
    }

    // CoreAudio direct path disabled — using Swift AVAudioEngine instead
    
    // Fallback: Swift AVAudioEngine path
    g_useCoreAudioDirect = false;
    fprintf(stderr, "callbacks_mac: Falling back to AVAudioEngine\n");
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onAudioInit) {
        int err = cbs->onAudioInit(audioConfiguration,
                                    opusConfig->sampleRate,
                                    opusConfig->samplesPerFrame);
        if (err != 0) {
            free(g_pcmBuf); g_pcmBuf = NULL;
            opus_multistream_decoder_destroy(g_opusDecoder);
            g_opusDecoder = NULL;
            return -1;
        }
    }
    return 0;
}

static void BridgeMacAudioStart(void) {
    fprintf(stderr, "callbacks_mac: BridgeMacAudioStart called — coreAudioDirect=%d\n", g_useCoreAudioDirect);
    if (g_useCoreAudioDirect) {
        coreAudioRendererStart();
    } else {
        JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
        if (cbs->onAudioStart) cbs->onAudioStart();
    }
}

static void BridgeMacAudioStop(void) {
    if (g_useCoreAudioDirect) {
        coreAudioRendererStop();
    } else {
        JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
        if (cbs->onAudioStop) cbs->onAudioStop();
    }
}

static void BridgeMacAudioCleanup(void) {
    // Clean up the active renderer
    if (g_useCoreAudioDirect) {
        coreAudioRendererCleanup();
        g_useCoreAudioDirect = false;
    } else {
        JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
        if (cbs->onAudioCleanup) cbs->onAudioCleanup();
    }

    // Always clean up Opus decoder and PCM buffer
    if (g_opusDecoder) {
        opus_multistream_decoder_destroy(g_opusDecoder);
        g_opusDecoder = NULL;
    }
    free(g_pcmBuf);
    g_pcmBuf = NULL;
    g_pcmBufSamples = 0;
}

static void BridgeMacAudioDecodeAndPlaySample(char *sampleData, int sampleLength) {
    if (!g_opusDecoder || !g_pcmBuf) return;

    int frames = opus_multistream_decode(
        g_opusDecoder,
        (const unsigned char *)sampleData,
        sampleLength,
        g_pcmBuf,
        g_opusConfig.samplesPerFrame,
        sampleData == NULL ? 1 : 0);

    g_audioDecodeCount++;
    if (frames <= 0) {
        g_audioDecodeErrors++;
        // Log first few errors and then every 100th
        if (g_audioDecodeErrors <= 5 || (g_audioDecodeErrors % 100) == 0) {
            fprintf(stderr, "callbacks_mac: Opus decode error %d (total errors=%llu, decodes=%llu)\n",
                    frames, (unsigned long long)g_audioDecodeErrors,
                    (unsigned long long)g_audioDecodeCount);
        }
        return;
    }

    // Log first successful decode and then every ~5 seconds (200 frames at 48kHz/240spf)
    if (g_audioDecodeCount == 1 || (g_audioDecodeCount % 1000) == 0) {
        fprintf(stderr, "callbacks_mac: audio decode #%llu — %d frames, %d ch, coreAudio=%d\n",
                (unsigned long long)g_audioDecodeCount, frames,
                g_opusConfig.channelCount, g_useCoreAudioDirect);
    }

    int totalSamples = frames * g_opusConfig.channelCount;

    if (g_useCoreAudioDirect) {
        // Direct to ring buffer → AudioUnit HAL
        coreAudioRendererSubmit(g_pcmBuf, totalSamples);
    } else {
        // Fallback: Swift AVAudioEngine path (~25 ms latency)
        JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
        if (cbs->onAudioSample) {
            cbs->onAudioSample((const char *)g_pcmBuf,
                               totalSamples * (int)sizeof(int16_t));
        }
    }
}

// ---------------------------------------------------------------------------
// Connection Listener Callbacks
// ---------------------------------------------------------------------------

static void BridgeMacConnectionStarted(void) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onConnectionStarted) cbs->onConnectionStarted();
}

static void BridgeMacConnectionTerminated(int errorCode) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onConnectionTerminated) cbs->onConnectionTerminated(errorCode);
}

static void BridgeMacStageStarting(int stage) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onStageStarting) cbs->onStageStarting(stage);
}

static void BridgeMacStageComplete(int stage) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onStageComplete) cbs->onStageComplete(stage);
}

static void BridgeMacStageFailed(int stage, int errorCode) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onStageFailed) cbs->onStageFailed(stage, errorCode);
}

static void BridgeMacConnectionStatusUpdate(int status) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onConnectionStatusUpdate) cbs->onConnectionStatusUpdate(status);
}

static void BridgeMacRumble(unsigned short cn, unsigned short low, unsigned short high) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onRumble) cbs->onRumble(cn, low, high);
}

static void BridgeMacSetHdrMode(bool enabled) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onSetHdrMode) cbs->onSetHdrMode(enabled);
}

static void BridgeMacRumbleTriggers(uint16_t cn, uint16_t lt, uint16_t rt) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onRumbleTriggers) cbs->onRumbleTriggers(cn, lt, rt);
}

static void BridgeMacSetMotionEventState(uint16_t cn, uint8_t mt, uint16_t hz) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onSetMotionEventState) cbs->onSetMotionEventState(cn, mt, hz);
}

static void BridgeMacSetControllerLED(uint16_t cn, uint8_t r, uint8_t g, uint8_t b) {
    JujostreamMacCallbacks *cbs = moonlightMacGetCallbacks();
    if (cbs->onSetControllerLED) cbs->onSetControllerLED(cn, r, g, b);
}

static void BridgeMacLogMessage(const char *format, ...) {
    va_list va;
    va_start(va, format);
    vfprintf(stderr, format, va);
    va_end(va);
    fprintf(stderr, "\n");
}

// ---------------------------------------------------------------------------
// Exported callback struct instances (referenced by moonlight_bridge_mac.c)
// ---------------------------------------------------------------------------
DECODER_RENDERER_CALLBACKS BridgeMacVideoCallbacks = {
    .setup           = BridgeMacVideoSetup,
    .start           = BridgeMacVideoStart,
    .stop            = BridgeMacVideoStop,
    .cleanup         = BridgeMacVideoCleanup,
    .submitDecodeUnit = BridgeMacVideoSubmitDecodeUnit,
    .capabilities    = 0,
};

AUDIO_RENDERER_CALLBACKS BridgeMacAudioCallbacks = {
    .init                = BridgeMacAudioInit,
    .start               = BridgeMacAudioStart,
    .stop                = BridgeMacAudioStop,
    .cleanup             = BridgeMacAudioCleanup,
    .decodeAndPlaySample = BridgeMacAudioDecodeAndPlaySample,
    .capabilities        = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION,
};

CONNECTION_LISTENER_CALLBACKS BridgeMacConnCallbacks = {
    .stageStarting        = BridgeMacStageStarting,
    .stageComplete        = BridgeMacStageComplete,
    .stageFailed          = BridgeMacStageFailed,
    .connectionStarted    = BridgeMacConnectionStarted,
    .connectionTerminated = BridgeMacConnectionTerminated,
    .logMessage           = BridgeMacLogMessage,
    .rumble               = BridgeMacRumble,
    .connectionStatusUpdate = BridgeMacConnectionStatusUpdate,
    .setHdrMode           = BridgeMacSetHdrMode,
    .rumbleTriggers       = BridgeMacRumbleTriggers,
    .setMotionEventState  = BridgeMacSetMotionEventState,
    .setControllerLED     = BridgeMacSetControllerLED,
};
