/**
 * audio_format_helper.h — Channel layout mapping (stereo/5.1/7.1).
 */
#pragma once

#include <cstdint>

namespace jujostream {
namespace audio {

class AudioFormatHelper {
public:
    // Returns WAVEFORMATEXTENSIBLE channel mask for given channel count
    static uint32_t channelMask(int channels);

    // Returns channel count from moonlight audio configuration
    static int channelCountFromConfig(int audioConfig);
};

}  // namespace audio
}  // namespace jujostream
