// SPSC lock-free ring buffer for int16_t audio samples.
// Power-of-two capacity; acquire/release atomics for thread safety.

#pragma once

#include <atomic>
#include <cstdint>
#include <cstring>
#include <algorithm>

class LockFreeRingBuffer {
public:
    explicit LockFreeRingBuffer(int capacitySamples = 0)
        : mBuffer(nullptr), mCapacity(0), mMask(0),
          mWritePos(0), mReadPos(0) {
        if (capacitySamples > 0) resize(capacitySamples);
    }

    ~LockFreeRingBuffer() { delete[] mBuffer; }

    // Non-copyable
    LockFreeRingBuffer(const LockFreeRingBuffer&) = delete;
    LockFreeRingBuffer& operator=(const LockFreeRingBuffer&) = delete;

        void resize(int minSamples) {
        delete[] mBuffer;
        mCapacity = nextPow2(minSamples);
        mMask     = mCapacity - 1;
        mBuffer   = new int16_t[mCapacity]();
        mWritePos.store(0, std::memory_order_relaxed);
        mReadPos.store(0, std::memory_order_relaxed);
    }

        int write(const int16_t* src, int count) {
        if (count <= 0) return 0;
        
        uint32_t w = mWritePos.load(std::memory_order_relaxed);
        uint32_t r = mReadPos.load(std::memory_order_acquire);
        
        // Full buffer: drop oldest samples to stay current
        int available = mCapacity - (int)(w - r);
        if (count > available) {
            int overflow = count - available;
            mReadPos.store(r + overflow, std::memory_order_release);
            // Re-read after advancing
            r = mReadPos.load(std::memory_order_acquire);
        }
        
        const uint32_t startIdx = w & mMask;
        const int firstChunk = std::min(count, (int)(mCapacity - startIdx));
        std::memcpy(mBuffer + startIdx, src, firstChunk * sizeof(int16_t));
        if (firstChunk < count) {
            std::memcpy(mBuffer, src + firstChunk,
                        (count - firstChunk) * sizeof(int16_t));
        }

        mWritePos.store(w + count, std::memory_order_release);
        return count;
    }

        int read(int16_t* dst, int count) {
        const uint32_t r = mReadPos.load(std::memory_order_relaxed);
        const uint32_t w = mWritePos.load(std::memory_order_acquire);
        const int available = (int)(w - r);
        const int toRead    = std::min(count, available);
        if (toRead <= 0) return 0;

        const uint32_t startIdx = r & mMask;
        const int firstChunk = std::min(toRead, (int)(mCapacity - startIdx));
        std::memcpy(dst, mBuffer + startIdx, firstChunk * sizeof(int16_t));
        if (firstChunk < toRead) {
            std::memcpy(dst + firstChunk, mBuffer,
                        (toRead - firstChunk) * sizeof(int16_t));
        }

        mReadPos.store(r + toRead, std::memory_order_release);
        return toRead;
    }

    /** Number of samples available to read. */
    int availableToRead() const {
        return (int)(mWritePos.load(std::memory_order_acquire)
                   - mReadPos.load(std::memory_order_relaxed));
    }

    /** Reset read/write positions. NOT thread-safe. */
    void reset() {
        mWritePos.store(0, std::memory_order_relaxed);
        mReadPos.store(0, std::memory_order_relaxed);
    }

private:
    static uint32_t nextPow2(uint32_t v) {
        v--;
        v |= v >> 1; v |= v >> 2; v |= v >> 4;
        v |= v >> 8; v |= v >> 16;
        return v + 1;
    }

    int16_t*              mBuffer;
    uint32_t              mCapacity;
    uint32_t              mMask;
    std::atomic<uint32_t> mWritePos;
    std::atomic<uint32_t> mReadPos;
};
