/**
 * audio_format_helper.cpp
 */
#include "audio_format_helper.h"

namespace jujostream {
namespace audio {

uint32_t AudioFormatHelper::channelMask(int channels) {
    switch (channels) {
        case 2:  return 0x00000003;  // SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT
        case 6:  return 0x0000003F;  // 5.1: FL FR FC LFE BL BR
        case 8:  return 0x000000FF;  // 7.1: FL FR FC LFE BL BR SL SR
        default: return 0x00000003;
    }
}

int AudioFormatHelper::channelCountFromConfig(int audioConfig) {
    // moonlight-common-c audio configuration constants
    // 0x0302CA = stereo, 0x3F06CA = 5.1, 0x63F08CA = 7.1
    switch (audioConfig & 0xFF) {
        case 2:  return 2;
        case 6:  return 6;
        case 8:  return 8;
        default: return 2;
    }
}

}  // namespace audio
}  // namespace jujostream
