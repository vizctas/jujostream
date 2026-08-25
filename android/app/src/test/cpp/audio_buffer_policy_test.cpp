#include <cassert>

#include "../../main/cpp/bridge/AudioBufferPolicy.h"

int main() {
    // Chromecast HD / Amlogic: AudioFlinger exposes 2048-frame output bursts.
    // The PCM queue must cover two complete bursts, never less than one callback.
    const auto chromecast = AudioBufferPolicy::plan(48000, 240, 2048);
    assert(chromecast.callbackFrames == 240);
    assert(chromecast.ringCapacityFrames == 4096);
    assert(chromecast.ringCapacityFrames >= chromecast.outputBurstFrames * 2);

    // Low-latency devices keep the 40 ms target instead of inheriting a
    // needlessly large queue from a small hardware burst.
    const auto lowLatency = AudioBufferPolicy::plan(48000, 240, 192);
    assert(lowLatency.callbackFrames == 240);
    assert(lowLatency.ringCapacityFrames == 1920);

    // Unknown/invalid platform values still produce a safe bounded plan.
    const auto unknownBurst = AudioBufferPolicy::plan(48000, 240, 0);
    assert(unknownBurst.outputBurstFrames == 240);
    assert(unknownBurst.ringCapacityFrames == 1920);

    return 0;
}
