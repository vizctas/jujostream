#include <cassert>
#include <cstdint>

#include "../../main/cpp/bridge/LockFreeRingBuffer.h"

int main() {
    LockFreeRingBuffer ring(8);
    const int16_t first[] = {1, 2, 3, 4, 5, 6};
    const int16_t overflow[] = {7, 8, 9, 10};
    int16_t output[8] = {};

    assert(ring.write(first, 6) == 6);
    // A packet is atomic. The producer must never move the consumer cursor.
    assert(ring.write(overflow, 4) == 0);
    assert(ring.availableToRead() == 6);
    assert(ring.read(output, 8) == 6);
    for (int i = 0; i < 6; ++i) assert(output[i] == first[i]);

    // Verify wrap-around after both cursors have advanced.
    assert(ring.write(overflow, 4) == 4);
    assert(ring.read(output, 2) == 2);
    assert(ring.write(first, 6) == 6);
    assert(ring.read(output, 8) == 8);
    assert(output[0] == 9 && output[1] == 10);
    for (int i = 0; i < 6; ++i) assert(output[i + 2] == first[i]);

    return 0;
}
