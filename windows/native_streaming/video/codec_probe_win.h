/**
 * codec_probe_win.h — Hardware codec detection via MFTEnumEx.
 */
#pragma once

#include <string>
#include <map>

namespace jujostream {
namespace video {

class CodecProbeWin {
public:
    static CodecProbeWin &instance();

    // Returns map: {best, h264, h265, av1} → "hardware"/"software"/"unsupported"
    std::map<std::string, std::string> probe(int width, int height, int fps, bool hdr);

private:
    CodecProbeWin() = default;
};

}  // namespace video
}  // namespace jujostream
