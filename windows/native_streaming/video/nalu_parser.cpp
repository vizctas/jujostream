/**
 * nalu_parser.cpp
 *
 * Annex-B start code scanner. Zero-copy: NalUnit pointers reference input buffer.
 */
#include "nalu_parser.h"
#include <cstring>

namespace jujostream {
namespace video {

// Find the next Annex-B start code {0,0,1} or {0,0,0,1} starting at [pos, end).
// Returns pointer to the byte AFTER the start code, or nullptr if not found.
static const uint8_t *findNextStartCode(const uint8_t *p, const uint8_t *end) {
    while (p + 3 <= end) {
        if (p[0] == 0 && p[1] == 0) {
            if (p[2] == 1)               return p + 3;  // 3-byte
            if (p[2] == 0 && p + 4 <= end && p[3] == 1)
                                         return p + 4;  // 4-byte
        }
        ++p;
    }
    return nullptr;
}

std::vector<NalUnit> NaluParser::parse(const uint8_t *data, int length, bool isHevc) {
    std::vector<NalUnit> result;
    if (!data || length < 4) return result;

    const uint8_t *end  = data + length;
    const uint8_t *nal  = findNextStartCode(data, end);

    while (nal && nal < end) {
        const uint8_t *next = findNextStartCode(nal, end);
        int nalLen = (int)(next ? (next - 3 <= nal + 1 ? next : next - 3) - nal
                                 : end - nal);

        // Back-trim trailing zeros from 4-byte start code
        if (next && next[-4] == 0) {
            // 4-byte start: the slice before ends one byte earlier
            nalLen = (int)(next - 4 - nal);
            if (nalLen <= 0) { nal = next; continue; }
        } else if (next) {
            nalLen = (int)(next - 3 - nal);
            if (nalLen <= 0) { nal = next; continue; }
        } else {
            nalLen = (int)(end - nal);
        }

        if (nalLen > 0) {
            int rawType = isHevc ? ((nal[0] >> 1) & 0x3F) : (nal[0] & 0x1F);
            result.push_back({ nal, nalLen, rawType });
        }
        nal = next;
    }
    return result;
}

const NalUnit *NaluParser::findSps(const std::vector<NalUnit> &units, bool isHevc) {
    int spsType = isHevc ? kNalHevcSps : kNalH264Sps;
    for (auto &u : units) if (u.type == spsType) return &u;
    return nullptr;
}

const NalUnit *NaluParser::findPps(const std::vector<NalUnit> &units, bool isHevc) {
    int ppsType = isHevc ? kNalHevcPps : kNalH264Pps;
    for (auto &u : units) if (u.type == ppsType) return &u;
    return nullptr;
}

const NalUnit *NaluParser::findVps(const std::vector<NalUnit> &units) {
    for (auto &u : units) if (u.type == kNalHevcVps) return &u;
    return nullptr;
}

bool NaluParser::containsIdr(const std::vector<NalUnit> &units, bool isHevc) {
    int idrType = isHevc ? kNalHevcIdr : kNalH264Idr;
    for (auto &u : units) if (u.type == idrType) return true;
    return false;
}

}  // namespace video
}  // namespace jujostream
