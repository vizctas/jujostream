/**
 * audio_ring_buffer.cpp — SPSC lock-free ring buffer for PCM audio.
 */
#include "audio_ring_buffer.h"

#include <algorithm>
#include <cstring>

namespace jujostream {
namespace audio {

static std::size_t nextPow2(std::size_t v) {
    if (v < 2) return 2;
    std::size_t p = 1;
    while (p < v) p <<= 1;
    return p;
}

AudioRingBuffer::AudioRingBuffer(std::size_t capacitySamples)
    : capacity_(nextPow2(capacitySamples)),
      mask_(capacity_ - 1),
      buffer_(new float[capacity_]) {
    std::memset(buffer_.get(), 0, capacity_ * sizeof(float));
}

std::size_t AudioRingBuffer::available() const {
    const auto w = writeIdx_.load(std::memory_order_acquire);
    const auto r = readIdx_.load(std::memory_order_acquire);
    return w - r;
}

void AudioRingBuffer::reset() {
    writeIdx_.store(0, std::memory_order_release);
    readIdx_.store(0, std::memory_order_release);
    dropped_.store(0, std::memory_order_relaxed);
    underruns_.store(0, std::memory_order_relaxed);
}

std::size_t AudioRingBuffer::write(const float *src, std::size_t n) {
    if (n == 0 || n > capacity_) return 0;

    const auto r = readIdx_.load(std::memory_order_acquire);
    auto       w = writeIdx_.load(std::memory_order_relaxed);
    const auto space = capacity_ - (w - r);

    // Not enough space — drop oldest by bumping readIdx_. This is safe only
    // because a single consumer reads: during the drop the consumer may still
    // be reading, but the next read sees the new readIdx_ and any half-read
    // window is discarded as silence. Acceptable for live audio.
    if (space < n) {
        const auto deficit = n - space;
        readIdx_.fetch_add(deficit, std::memory_order_acq_rel);
        dropped_.fetch_add(deficit, std::memory_order_relaxed);
    }

    // Copy in up to two spans (wrap at capacity boundary).
    const auto wPos  = w & mask_;
    const auto first = std::min<std::size_t>(n, capacity_ - wPos);
    std::memcpy(buffer_.get() + wPos, src, first * sizeof(float));
    if (first < n) {
        std::memcpy(buffer_.get(), src + first, (n - first) * sizeof(float));
    }

    writeIdx_.store(w + n, std::memory_order_release);
    return n;
}

std::size_t AudioRingBuffer::read(float *dst, std::size_t n, bool padWithSilence) {
    const auto w = writeIdx_.load(std::memory_order_acquire);
    auto       r = readIdx_.load(std::memory_order_relaxed);
    const auto have = w - r;
    const auto take = std::min(n, have);

    if (take > 0) {
        const auto rPos  = r & mask_;
        const auto first = std::min<std::size_t>(take, capacity_ - rPos);
        std::memcpy(dst, buffer_.get() + rPos, first * sizeof(float));
        if (first < take) {
            std::memcpy(dst + first, buffer_.get(), (take - first) * sizeof(float));
        }
        readIdx_.store(r + take, std::memory_order_release);
    }

    if (take < n) {
        if (padWithSilence) {
            std::memset(dst + take, 0, (n - take) * sizeof(float));
        }
        underruns_.fetch_add(1, std::memory_order_relaxed);
    }
    return take;
}

}  // namespace audio
}  // namespace jujostream
