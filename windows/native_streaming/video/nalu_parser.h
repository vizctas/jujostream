/**
 * nalu_parser.h
 *
 * Annex-B start code scanner and NAL unit classifier.
 * Zero-copy: NalUnit pointers reference the input buffer directly.
 *
 * NAL types (H.264):
 *   1=SLICE, 5=IDR, 7=SPS, 8=PPS
 * NAL types (HEVC, high nibble = nal_unit_type >> 1):
 *   0x01=TRAIL_N, 0x13=IDR_W_RADL, 0x20=VPS, 0x21=SPS, 0x22=PPS
 */
#pragma once

#include <cstdint>
#include <vector>

namespace jujostream {
namespace video {

// H.264 NAL types
static constexpr int kNalH264Slice = 1;
static constexpr int kNalH264Idr   = 5;
static constexpr int kNalH264Sps   = 7;
static constexpr int kNalH264Pps   = 8;

// HEVC NAL types (>> 1 of nal_unit_type field per spec)
static constexpr int kNalHevcVps   = 32;  // 0x20
static constexpr int kNalHevcSps   = 33;  // 0x21
static constexpr int kNalHevcPps   = 34;  // 0x22
static constexpr int kNalHevcIdr   = 19;  // 0x13 IDR_W_RADL

struct NalUnit {
    const uint8_t *data;   // points at first byte AFTER start code
    int            length;
    int            type;   // raw NAL unit type byte (H.264) or (nal_type>>1) for HEVC
};

class NaluParser {
public:
    /**
     * Split an Annex-B buffer into individual NAL units.
     * Handles both 3-byte {0,0,1} and 4-byte {0,0,0,1} start codes.
     * Returned NalUnit.data pointers are valid as long as the input buffer lives.
     */
    static std::vector<NalUnit> parse(const uint8_t *data, int length, bool isHevc = false);

    /**
     * Find SPS/PPS/VPS NAL units inside a parsed list.
     * Returns nullptr/0 if not found.
     */
    static const NalUnit *findSps(const std::vector<NalUnit> &units, bool isHevc = false);
    static const NalUnit *findPps(const std::vector<NalUnit> &units, bool isHevc = false);
    static const NalUnit *findVps(const std::vector<NalUnit> &units);

    /** True if any NAL unit in the list is an IDR frame */
    static bool containsIdr(const std::vector<NalUnit> &units, bool isHevc = false);
};

}  // namespace video
}  // namespace jujostream
