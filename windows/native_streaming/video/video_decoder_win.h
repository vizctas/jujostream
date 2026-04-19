/**
 * video_decoder_win.h
 *
 * Public interface for Windows video decoding pipeline.
 * Components: MftDecoder, D3D11Device, NaluParser, TextureBridge, CodecProbe.
 */
#pragma once

namespace jujostream {
namespace video {

// Forward declarations — each component has its own header
class MftDecoder;
class D3D11Device;
class NaluParser;
class TextureBridge;
class CodecProbeWin;

}  // namespace video
}  // namespace jujostream
