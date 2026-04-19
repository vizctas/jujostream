/**
 * audio_ring_buffer.h — Single-producer / single-consumer lock-free ring.
 *
 * Holds interleaved float32 PCM samples. Producer = moonlight callback thread
 * (converts int16 -> float32 before enqueue). Consumer = WASAPI render thread.
 *
 * Capacity is rounded up to the next power of two for branchless masking.
 * When the buffer overruns the oldest samples are discarded (monotonic drop
 * counter exposed for telemetry) — this trades glitches over stalling the
 * audio engine, which is the correct behaviour for a live stream.
 */
#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>

namespace jujostream {
namespace audio {

class AudioRingBuffer {
public:
    // capacitySamples is the *requested* capacity in float samples (all channels).
    // Actual capacity is the next power of two >= capacitySamples.
    explicit AudioRingBuffer(std::size_t capacitySamples);

    // Not copyable, not movable (owns raw atomics).
    AudioRingBuffer(const AudioRingBuffer &) = delete;
    AudioRingBuffer &operator=(const AudioRingBuffer &) = delete;

    // Producer: enqueue `n` float samples. Returns number actually written.
    // If the buffer is full, oldest samples are dropped (counter incremented)
    // and the new block is accepted in full.
    std::size_t write(const float *src, std::size_t n);

    // Consumer: dequeue up to `n` float samples. Returns number actually read.
    // If fewer samples are available, the tail is zero-filled (silence) when
    // `padWithSilence` is true — this keeps WASAPI happy during underruns.
    std::size_t read(float *dst, std::size_t n, bool padWithSilence);

    // Observers (approximate — indices are atomic but change concurrently).
    std::size_t available() const;
    std::size_t capacity() const { return capacity_; }

    // Telemetry.
    uint64_t droppedSamples() const { return dropped_.load(std::memory_order_relaxed); }
    uint64_t underruns() const      { return underruns_.load(std::memory_order_relaxed); }

    // Producer/consumer reset (e.g. on format change). Must not be called while
    // the other side is running.
    void reset();

private:
    const std::size_t              capacity_;   // power of two
    const std::size_t              mask_;       // capacity_ - 1
    std::unique_ptr<float[]>       buffer_;

    // Indices in sample count (not masked). Use modulo at access time.
    alignas(64) std::atomic<std::size_t> writeIdx_{0};
    alignas(64) std::atomic<std::size_t> readIdx_{0};

    std::atomic<uint64_t> dropped_{0};
    std::atomic<uint64_t> underruns_{0};
};

}  // namespace audio
}  // namespace jujostream
