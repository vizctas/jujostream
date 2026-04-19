// Direct AudioUnit output with SPSC lock-free ring buffer.
// Opus decoder thread → submit() → ring buffer → AudioUnit callback → HAL

#pragma once

#include <stdint.h>
#include <stdbool.h>

int  coreAudioRendererInit(int channelCount, int sampleRate, int samplesPerFrame);

void coreAudioRendererStart(void);

void coreAudioRendererStop(void);

void coreAudioRendererCleanup(void);

void coreAudioRendererSubmit(const int16_t *pcm, int sampleCount);
