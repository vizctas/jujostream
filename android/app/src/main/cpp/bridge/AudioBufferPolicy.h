#pragma once

#include <algorithm>
#include <cstdint>

class AudioBufferPolicy {
public:
    struct Plan {
        int callbackFrames;
        int outputBurstFrames;
        int ringCapacityFrames;
    };

    /**
     * Keep 40 ms on genuine low-latency outputs, but never provision less
     * than two complete output bursts. The callback is packet-sized so Oboe
     * performs any required block adaptation instead of asking our FIFO for
     * a block larger than it can ever contain.
     */
    static Plan plan(int sampleRate, int samplesPerFrame, int outputBurstFrames) noexcept {
        const int safeRate = sampleRate > 0 ? sampleRate : 48000;
        const int safePacketFrames = samplesPerFrame > 0 ? samplesPerFrame : 240;
        const int safeBurstFrames = outputBurstFrames > 0
            ? outputBurstFrames
            : safePacketFrames;
        const auto targetFrames64 =
            (static_cast<std::int64_t>(safeRate) * 40 + 999) / 1000;
        const auto burstFrames64 = static_cast<std::int64_t>(safeBurstFrames) * 2;
        const int ringFrames = static_cast<int>(std::max(targetFrames64, burstFrames64));

        return {
            safePacketFrames,
            safeBurstFrames,
            ringFrames,
        };
    }
};
