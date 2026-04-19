// Direct AudioUnit output with SPSC lock-free ring buffer for macOS.

#include "CoreAudioRenderer.h"
#include <AudioToolbox/AudioToolbox.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ═══════════════════════════════════════════════════════════════════════════════
// SPSC Ring Buffer (C11 atomics — single producer, single consumer)
// ═══════════════════════════════════════════════════════════════════════════════

typedef struct {
    int16_t          *buffer;
    uint32_t          capacity;   // always power of 2
    uint32_t          mask;       // capacity - 1
    _Atomic uint32_t  writePos;
    _Atomic uint32_t  readPos;
} SPSCRingBuffer;

static uint32_t nextPow2(uint32_t v) {
    v--;
    v |= v >> 1;  v |= v >> 2;  v |= v >> 4;
    v |= v >> 8;  v |= v >> 16;
    return v + 1;
}

static void ringInit(SPSCRingBuffer *rb, int minSamples) {
    rb->capacity = nextPow2((uint32_t)minSamples);
    rb->mask     = rb->capacity - 1;
    rb->buffer   = (int16_t *)calloc(rb->capacity, sizeof(int16_t));
    atomic_store_explicit(&rb->writePos, 0, memory_order_relaxed);
    atomic_store_explicit(&rb->readPos,  0, memory_order_relaxed);
}

static void ringFree(SPSCRingBuffer *rb) {
    free(rb->buffer);
    rb->buffer   = NULL;
    rb->capacity = 0;
    rb->mask     = 0;
}

static int ringWrite(SPSCRingBuffer *rb, const int16_t *src, int count) {
    uint32_t w = atomic_load_explicit(&rb->writePos, memory_order_relaxed);
    uint32_t r = atomic_load_explicit(&rb->readPos,  memory_order_acquire);

    int available = (int)(rb->capacity - (w - r));
    int toWrite   = count < available ? count : available;
    if (toWrite <= 0) return 0;

    uint32_t startIdx  = w & rb->mask;
    int firstChunk = (int)(rb->capacity - startIdx);
    if (firstChunk > toWrite) firstChunk = toWrite;

    memcpy(rb->buffer + startIdx, src, (size_t)firstChunk * sizeof(int16_t));
    if (firstChunk < toWrite) {
        memcpy(rb->buffer, src + firstChunk,
               (size_t)(toWrite - firstChunk) * sizeof(int16_t));
    }

    atomic_store_explicit(&rb->writePos, w + (uint32_t)toWrite, memory_order_release);
    return toWrite;
}

static int ringRead(SPSCRingBuffer *rb, int16_t *dst, int count) {
    uint32_t r = atomic_load_explicit(&rb->readPos,  memory_order_relaxed);
    uint32_t w = atomic_load_explicit(&rb->writePos, memory_order_acquire);

    int available = (int)(w - r);
    int toRead    = count < available ? count : available;
    if (toRead <= 0) return 0;

    uint32_t startIdx  = r & rb->mask;
    int firstChunk = (int)(rb->capacity - startIdx);
    if (firstChunk > toRead) firstChunk = toRead;

    memcpy(dst, rb->buffer + startIdx, (size_t)firstChunk * sizeof(int16_t));
    if (firstChunk < toRead) {
        memcpy(dst + firstChunk, rb->buffer,
               (size_t)(toRead - firstChunk) * sizeof(int16_t));
    }

    atomic_store_explicit(&rb->readPos, r + (uint32_t)toRead, memory_order_release);
    return toRead;
}

static void ringReset(SPSCRingBuffer *rb) {
    atomic_store_explicit(&rb->writePos, 0, memory_order_relaxed);
    atomic_store_explicit(&rb->readPos,  0, memory_order_relaxed);
}

// ═══════════════════════════════════════════════════════════════════════════════
// CoreAudio State
// ═══════════════════════════════════════════════════════════════════════════════

static AudioComponentInstance g_audioUnit = NULL;
static SPSCRingBuffer         g_ring;
static int                    g_channelCount = 2;
static bool                   g_started = false;

// Diagnostic counters for audio debugging
static _Atomic uint64_t g_submitCount = 0;
static _Atomic uint64_t g_renderCount = 0;
static _Atomic uint64_t g_underrunCount = 0;

// ═══════════════════════════════════════════════════════════════════════════════
// AudioUnit Render Callback (HAL thread — must be lock-free)
// ═══════════════════════════════════════════════════════════════════════════════

static OSStatus renderCallback(
        void                        *inRefCon,
        AudioUnitRenderActionFlags  *ioActionFlags,
        const AudioTimeStamp        *inTimeStamp,
        UInt32                       inBusNumber,
        UInt32                       inNumberFrames,
        AudioBufferList             *ioData)
{
    (void)inRefCon; (void)ioActionFlags; (void)inTimeStamp; (void)inBusNumber;

    uint64_t rc = atomic_fetch_add_explicit(&g_renderCount, 1, memory_order_relaxed);

    for (UInt32 buf = 0; buf < ioData->mNumberBuffers; buf++) {
        int16_t *dst       = (int16_t *)ioData->mBuffers[buf].mData;
        int totalSamples   = (int)inNumberFrames * g_channelCount;
        int samplesRead    = ringRead(&g_ring, dst, totalSamples);

        // Zero-fill any underrun gap (silence > stale data)
        if (samplesRead < totalSamples) {
            memset(dst + samplesRead, 0,
                   (size_t)(totalSamples - samplesRead) * sizeof(int16_t));
            if (samplesRead == 0) {
                atomic_fetch_add_explicit(&g_underrunCount, 1, memory_order_relaxed);
            }
        }
    }

    // Log diagnostics every ~5 seconds (assuming ~187 callbacks/sec at 256 frames @ 48kHz)
    if (rc > 0 && (rc % 1000) == 0) {
        uint64_t sc = atomic_load_explicit(&g_submitCount, memory_order_relaxed);
        uint64_t uc = atomic_load_explicit(&g_underrunCount, memory_order_relaxed);
        fprintf(stderr, "CoreAudioRenderer: renders=%llu submits=%llu underruns=%llu\n",
                rc, sc, uc);
    }
    return noErr;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Public API
// ═══════════════════════════════════════════════════════════════════════════════

int coreAudioRendererInit(int channelCount, int sampleRate, int samplesPerFrame) {
    g_channelCount = channelCount;

    // Ring buffer sized for ~100 ms of audio (20 × 5 ms frames)
    int ringCapacity = channelCount * samplesPerFrame * 20;
    ringInit(&g_ring, ringCapacity);

    // ── Find default output AudioComponent ──────────────────────────────
    AudioComponentDescription desc = {
        .componentType         = kAudioUnitType_Output,
        .componentSubType      = kAudioUnitSubType_DefaultOutput,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
        .componentFlags        = 0,
        .componentFlagsMask    = 0,
    };

    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) {
        fprintf(stderr, "CoreAudioRenderer: AudioComponentFindNext failed\n");
        ringFree(&g_ring);
        return -1;
    }

    OSStatus status = AudioComponentInstanceNew(comp, &g_audioUnit);
    if (status != noErr) {
        fprintf(stderr, "CoreAudioRenderer: AudioComponentInstanceNew: %d\n", (int)status);
        ringFree(&g_ring);
        return -1;
    }

    // ── Set stream format: interleaved int16 PCM ────────────────────────
    AudioStreamBasicDescription asbd = {
        .mSampleRate       = (Float64)sampleRate,
        .mFormatID         = kAudioFormatLinearPCM,
        .mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        .mBytesPerPacket   = (UInt32)(channelCount * 2),
        .mFramesPerPacket  = 1,
        .mBytesPerFrame    = (UInt32)(channelCount * 2),
        .mChannelsPerFrame = (UInt32)channelCount,
        .mBitsPerChannel   = 16,
        .mReserved         = 0,
    };

    status = AudioUnitSetProperty(g_audioUnit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input, 0,
        &asbd, sizeof(asbd));
    if (status != noErr) {
        fprintf(stderr, "CoreAudioRenderer: SetProperty StreamFormat: %d\n", (int)status);
        AudioComponentInstanceDispose(g_audioUnit);
        g_audioUnit = NULL;
        ringFree(&g_ring);
        return -1;
    }

    // ── Set channel layout for surround configurations ──────────────────
    if (channelCount == 6) {
        // Vorbis order: FL, FR, C, LFE, BL, BR → MPEG_5_1_A
        AudioChannelLayout layout = {
            .mChannelLayoutTag          = kAudioChannelLayoutTag_MPEG_5_1_A,
            .mChannelBitmap             = 0,
            .mNumberChannelDescriptions = 0,
        };
        AudioUnitSetProperty(g_audioUnit,
            kAudioUnitProperty_AudioChannelLayout,
            kAudioUnitScope_Input, 0,
            &layout, sizeof(layout));
    } else if (channelCount == 8) {
        // Vorbis order: FL, FR, C, LFE, BL, BR, SL, SR → MPEG_7_1_A
        AudioChannelLayout layout = {
            .mChannelLayoutTag          = kAudioChannelLayoutTag_MPEG_7_1_A,
            .mChannelBitmap             = 0,
            .mNumberChannelDescriptions = 0,
        };
        AudioUnitSetProperty(g_audioUnit,
            kAudioUnitProperty_AudioChannelLayout,
            kAudioUnitScope_Input, 0,
            &layout, sizeof(layout));
    }

    // ── Set render callback ─────────────────────────────────────────────
    AURenderCallbackStruct callbackStruct = {
        .inputProc       = renderCallback,
        .inputProcRefCon = NULL,
    };

    status = AudioUnitSetProperty(g_audioUnit,
        kAudioUnitProperty_SetRenderCallback,
        kAudioUnitScope_Input, 0,
        &callbackStruct, sizeof(callbackStruct));
    if (status != noErr) {
        fprintf(stderr, "CoreAudioRenderer: SetProperty RenderCallback: %d\n", (int)status);
        AudioComponentInstanceDispose(g_audioUnit);
        g_audioUnit = NULL;
        ringFree(&g_ring);
        return -1;
    }

    // ── Prefer small buffer size (~256 frames @ 48 kHz ≈ 5.3 ms) ───────
    UInt32 maxFrames = 256;
    AudioUnitSetProperty(g_audioUnit,
        kAudioUnitProperty_MaximumFramesPerSlice,
        kAudioUnitScope_Global, 0,
        &maxFrames, sizeof(maxFrames));

    // ── Initialize AudioUnit ────────────────────────────────────────────
    status = AudioUnitInitialize(g_audioUnit);
    if (status != noErr) {
        fprintf(stderr, "CoreAudioRenderer: AudioUnitInitialize: %d\n", (int)status);
        AudioComponentInstanceDispose(g_audioUnit);
        g_audioUnit = NULL;
        ringFree(&g_ring);
        return -1;
    }

    fprintf(stderr, "CoreAudioRenderer: init ok — ch=%d rate=%d spf=%d ring=%u\n",
            channelCount, sampleRate, samplesPerFrame, g_ring.capacity);
    return 0;
}

void coreAudioRendererStart(void) {
    if (!g_audioUnit || g_started) return;
    OSStatus status = AudioOutputUnitStart(g_audioUnit);
    if (status == noErr) {
        g_started = true;
        fprintf(stderr, "CoreAudioRenderer: started\n");
    } else {
        fprintf(stderr, "CoreAudioRenderer: start failed: %d\n", (int)status);
    }
}

void coreAudioRendererStop(void) {
    if (!g_audioUnit || !g_started) return;
    AudioOutputUnitStop(g_audioUnit);
    g_started = false;
    fprintf(stderr, "CoreAudioRenderer: stopped\n");
}

void coreAudioRendererCleanup(void) {
    if (g_audioUnit) {
        if (g_started) {
            AudioOutputUnitStop(g_audioUnit);
            g_started = false;
        }
        AudioUnitUninitialize(g_audioUnit);
        AudioComponentInstanceDispose(g_audioUnit);
        g_audioUnit = NULL;
    }
    ringFree(&g_ring);
    fprintf(stderr, "CoreAudioRenderer: cleanup\n");
}

void coreAudioRendererSubmit(const int16_t *pcm, int sampleCount) {
    atomic_fetch_add_explicit(&g_submitCount, 1, memory_order_relaxed);
    int written = ringWrite(&g_ring, pcm, sampleCount);
    if (written < sampleCount) {
        // Overflow: drop oldest samples to make room (better than dropping newest)
        uint32_t drop = (uint32_t)(sampleCount - written);
        uint32_t r = atomic_load_explicit(&g_ring.readPos, memory_order_relaxed);
        atomic_store_explicit(&g_ring.readPos, r + drop, memory_order_release);
        // Retry with freed space
        ringWrite(&g_ring, pcm + written, sampleCount - written);
    }
}
