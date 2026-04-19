/**
 * callbacks_win.c
 *
 * moonlight-common-c callback implementations for Windows.
 * Port of callbacks_mac.c — same video frame assembly + Opus decode.
 * Audio decoded in C (libopus) → PCM forwarded to C++ WASAPI renderer.
 */

#include "moonlight_bridge_win.h"
#include <Limelight.h>
#include <opus_multistream.h>
#include <string.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

extern JujostreamWinCallbacks *moonlightWinGetCallbacks(void);

/* --- Video frame assembly buffer --- */
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

/* --- Video Decoder Callbacks --- */

static int BridgeWinVideoSetup(int videoFormat, int width, int height,
                                int redrawRate, void *context, int drFlags) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onVideoSetup)
        return cbs->onVideoSetup(videoFormat, width, height, redrawRate);
    return -1;
}

static void BridgeWinVideoStart(void) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onVideoStart) cbs->onVideoStart();
}

static void BridgeWinVideoStop(void) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onVideoStop) cbs->onVideoStop();
}

static void BridgeWinVideoCleanup(void) {
    free(g_videoFrameBuf);
    g_videoFrameBuf    = NULL;
    g_videoFrameBufLen = 0;
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onVideoCleanup) cbs->onVideoCleanup();
}

static int BridgeWinVideoSubmitDecodeUnit(PDECODE_UNIT decodeUnit) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (!cbs->onVideoFrame) return DR_OK;
    if (!ensureVideoBuffer(decodeUnit->fullLength)) return DR_OK;

    PLENTRY entry  = decodeUnit->bufferList;
    int     offset = 0;
    int     ret    = DR_OK;

    while (entry != NULL) {
        if (entry->bufferType != BUFFER_TYPE_PICDATA) {
            ret = cbs->onVideoFrame(
                (const uint8_t *)entry->data, entry->length,
                entry->bufferType, decodeUnit->frameNumber,
                (int64_t)(decodeUnit->receiveTimeUs / 1000));
            if (ret != DR_OK) return ret;
        } else {
            memcpy(g_videoFrameBuf + offset, entry->data, (size_t)entry->length);
            offset += entry->length;
        }
        entry = entry->next;
    }

    if (offset > 0) {
        ret = cbs->onVideoFrame(
            g_videoFrameBuf, offset,
            BUFFER_TYPE_PICDATA, decodeUnit->frameNumber,
            (int64_t)(decodeUnit->receiveTimeUs / 1000));
    }
    return ret;
}

/* --- Audio Renderer Callbacks --- */

static OpusMSDecoder                  *g_opusDecoder   = NULL;
static OPUS_MULTISTREAM_CONFIGURATION  g_opusConfig;
static int16_t                        *g_pcmBuf        = NULL;
static int                             g_pcmBufSamples = 0;
static uint64_t g_audioDecodeCount  = 0;
static uint64_t g_audioDecodeErrors = 0;

static int BridgeWinAudioInit(int audioConfiguration,
                               POPUS_MULTISTREAM_CONFIGURATION opusConfig,
                               void *context, int flags) {
    memcpy(&g_opusConfig, opusConfig, sizeof(OPUS_MULTISTREAM_CONFIGURATION));

    int opusErr = 0;
    g_opusDecoder = opus_multistream_decoder_create(
        opusConfig->sampleRate, opusConfig->channelCount,
        opusConfig->streams, opusConfig->coupledStreams,
        opusConfig->mapping, &opusErr);
    if (!g_opusDecoder) return -1;

    opus_multistream_decoder_ctl(g_opusDecoder, OPUS_SET_INBAND_FEC(1));

    g_pcmBufSamples = opusConfig->channelCount * opusConfig->samplesPerFrame;
    g_pcmBuf = (int16_t *)malloc((size_t)g_pcmBufSamples * sizeof(int16_t));
    if (!g_pcmBuf) {
        opus_multistream_decoder_destroy(g_opusDecoder);
        g_opusDecoder = NULL;
        return -1;
    }

    g_audioDecodeCount  = 0;
    g_audioDecodeErrors = 0;

    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
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

static void BridgeWinAudioStart(void) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onAudioStart) cbs->onAudioStart();
}

static void BridgeWinAudioStop(void) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onAudioStop) cbs->onAudioStop();
}

static void BridgeWinAudioCleanup(void) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onAudioCleanup) cbs->onAudioCleanup();

    if (g_opusDecoder) {
        opus_multistream_decoder_destroy(g_opusDecoder);
        g_opusDecoder = NULL;
    }
    free(g_pcmBuf);
    g_pcmBuf = NULL;
    g_pcmBufSamples = 0;
}

static void BridgeWinAudioDecodeAndPlaySample(char *sampleData, int sampleLength) {
    if (!g_opusDecoder || !g_pcmBuf) return;

    int frames = opus_multistream_decode(
        g_opusDecoder,
        (const unsigned char *)sampleData, sampleLength,
        g_pcmBuf, g_opusConfig.samplesPerFrame,
        sampleData == NULL ? 1 : 0);

    g_audioDecodeCount++;
    if (frames <= 0) {
        g_audioDecodeErrors++;
        if (g_audioDecodeErrors <= 5 || (g_audioDecodeErrors % 100) == 0) {
            fprintf(stderr, "callbacks_win: Opus error %d (err=%llu tot=%llu)\n",
                    frames, (unsigned long long)g_audioDecodeErrors,
                    (unsigned long long)g_audioDecodeCount);
        }
        return;
    }

    int totalSamples = frames * g_opusConfig.channelCount;
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onAudioSample) {
        cbs->onAudioSample((const char *)g_pcmBuf,
                           totalSamples * (int)sizeof(int16_t));
    }
}

/* --- Connection Listener Callbacks --- */

static void BridgeWinConnectionStarted(void) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onConnectionStarted) cbs->onConnectionStarted();
}
static void BridgeWinConnectionTerminated(int errorCode) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onConnectionTerminated) cbs->onConnectionTerminated(errorCode);
}
static void BridgeWinStageStarting(int stage) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onStageStarting) cbs->onStageStarting(stage);
}
static void BridgeWinStageComplete(int stage) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onStageComplete) cbs->onStageComplete(stage);
}
static void BridgeWinStageFailed(int stage, int errorCode) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onStageFailed) cbs->onStageFailed(stage, errorCode);
}
static void BridgeWinConnectionStatusUpdate(int status) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onConnectionStatusUpdate) cbs->onConnectionStatusUpdate(status);
}
static void BridgeWinRumble(unsigned short cn, unsigned short low, unsigned short high) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onRumble) cbs->onRumble(cn, low, high);
}
static void BridgeWinSetHdrMode(bool enabled) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onSetHdrMode) cbs->onSetHdrMode(enabled);
}
static void BridgeWinRumbleTriggers(uint16_t cn, uint16_t lt, uint16_t rt) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onRumbleTriggers) cbs->onRumbleTriggers(cn, lt, rt);
}
static void BridgeWinSetMotionEventState(uint16_t cn, uint8_t mt, uint16_t hz) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onSetMotionEventState) cbs->onSetMotionEventState(cn, mt, hz);
}
static void BridgeWinSetControllerLED(uint16_t cn, uint8_t r, uint8_t g, uint8_t b) {
    JujostreamWinCallbacks *cbs = moonlightWinGetCallbacks();
    if (cbs->onSetControllerLED) cbs->onSetControllerLED(cn, r, g, b);
}
static void BridgeWinLogMessage(const char *format, ...) {
    va_list va;
    va_start(va, format);
    vfprintf(stderr, format, va);
    va_end(va);
    fprintf(stderr, "\n");
}

/* --- Exported callback struct instances --- */

DECODER_RENDERER_CALLBACKS BridgeWinVideoCallbacks = {
    .setup            = BridgeWinVideoSetup,
    .start            = BridgeWinVideoStart,
    .stop             = BridgeWinVideoStop,
    .cleanup          = BridgeWinVideoCleanup,
    .submitDecodeUnit = BridgeWinVideoSubmitDecodeUnit,
    .capabilities     = 0,
};

AUDIO_RENDERER_CALLBACKS BridgeWinAudioCallbacks = {
    .init                = BridgeWinAudioInit,
    .start               = BridgeWinAudioStart,
    .stop                = BridgeWinAudioStop,
    .cleanup             = BridgeWinAudioCleanup,
    .decodeAndPlaySample = BridgeWinAudioDecodeAndPlaySample,
    .capabilities        = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION,
};

CONNECTION_LISTENER_CALLBACKS BridgeWinConnCallbacks = {
    .stageStarting          = BridgeWinStageStarting,
    .stageComplete          = BridgeWinStageComplete,
    .stageFailed            = BridgeWinStageFailed,
    .connectionStarted      = BridgeWinConnectionStarted,
    .connectionTerminated   = BridgeWinConnectionTerminated,
    .logMessage             = BridgeWinLogMessage,
    .rumble                 = BridgeWinRumble,
    .connectionStatusUpdate = BridgeWinConnectionStatusUpdate,
    .setHdrMode             = BridgeWinSetHdrMode,
    .rumbleTriggers         = BridgeWinRumbleTriggers,
    .setMotionEventState    = BridgeWinSetMotionEventState,
    .setControllerLED       = BridgeWinSetControllerLED,
};
