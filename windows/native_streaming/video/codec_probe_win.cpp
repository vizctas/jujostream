/**
 * codec_probe_win.cpp
 *
 * Hardware codec detection via MFTEnumEx.
 * Probes H.264, H.265, AV1 in preference order.
 * Returns a map identical in shape to Android's CodecProbe.probeAsMap().
 */
#include "codec_probe_win.h"
#include <initguid.h>
#include <mfapi.h>
#include <mferror.h>
#include <cstdio>

#pragma comment(lib, "mfplat.lib")

// AV1 GUID (same as in mft_decoder.cpp)
DEFINE_GUID(MFVideoFormat_AV1_PROBE,
    0x31305641, 0x0000, 0x0010, 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71);

namespace jujostream {
namespace video {

CodecProbeWin &CodecProbeWin::instance() {
    static CodecProbeWin inst;
    return inst;
}

static std::string probeCodec(const GUID &inputSubtype) {
    MFT_REGISTER_TYPE_INFO inType = { MFMediaType_Video, inputSubtype };

    IMFActivate **activates = nullptr;
    UINT32 count = 0;
    HRESULT hr = MFTEnumEx(
        MFT_CATEGORY_VIDEO_DECODER,
        MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER,
        &inType, nullptr, &activates, &count);

    bool hasHw = SUCCEEDED(hr) && count > 0;
    for (UINT32 i = 0; i < count; ++i) activates[i]->Release();
    CoTaskMemFree(activates);

    if (hasHw) return "hardware";

    // Check for software fallback
    activates = nullptr; count = 0;
    hr = MFTEnumEx(
        MFT_CATEGORY_VIDEO_DECODER,
        MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_SORTANDFILTER,
        &inType, nullptr, &activates, &count);
    bool hasSw = SUCCEEDED(hr) && count > 0;
    for (UINT32 i = 0; i < count; ++i) activates[i]->Release();
    CoTaskMemFree(activates);

    return hasSw ? "software" : "unsupported";
}

std::map<std::string, std::string> CodecProbeWin::probe(
    int /*width*/, int /*height*/, int /*fps*/, bool /*hdr*/) {

    // MFStartup needed for MFTEnumEx
    bool started = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET));

    std::string h264 = probeCodec(MFVideoFormat_H264);
    std::string h265 = probeCodec(MFVideoFormat_HEVC);
    std::string av1  = probeCodec(MFVideoFormat_AV1_PROBE);

    // Pick best hardware codec in preference order: AV1 > H265 > H264
    std::string best = "H264";
    if (h265 == "hardware") best = "H265";
    if (av1  == "hardware") best = "AV1";

    if (started) MFShutdown();

    fprintf(stderr, "CodecProbeWin: h264=%s h265=%s av1=%s best=%s\n",
            h264.c_str(), h265.c_str(), av1.c_str(), best.c_str());

    return {
        {"best", best},
        {"h264", h264},
        {"h265", h265},
        {"av1",  av1 },
    };
}

}  // namespace video
}  // namespace jujostream
