// Client microphone capture using Google Oboe (input stream).
// Oboe input callback → accumulate 20 ms frames → Opus encode → LiSendMicPacket.
//
// Counterpart to OboeAudioRenderer (which plays host audio). This captures the
// local mic, encodes to Opus, and tunnels frames to the host over the control
// channel (Jujo client mic passthrough, classic protocol).

#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include <oboe/Oboe.h>

struct OpusEncoder;

class OboeMicCapturer: public oboe::AudioStreamDataCallback,
                       public oboe::AudioStreamErrorCallback {
public:
  OboeMicCapturer() = default;
  ~OboeMicCapturer() override;

  OboeMicCapturer(const OboeMicCapturer &) = delete;
  OboeMicCapturer &operator=(const OboeMicCapturer &) = delete;

  // Open the mic + Opus encoder and start capturing. Returns 0 on success.
  int start();
  void stop();

  // oboe::AudioStreamDataCallback — mic samples arrive here.
  oboe::DataCallbackResult onAudioReady(
    oboe::AudioStream *stream, void *audioData, int32_t numFrames) override;

  // oboe::AudioStreamErrorCallback — reopen on disconnect (e.g. headset unplug).
  void onErrorAfterClose(oboe::AudioStream *stream, oboe::Result error) override;

private:
  int openStream();
  void flushPending();  // encode + send full 20 ms frames from mPending

  std::shared_ptr<oboe::AudioStream> mStream;
  OpusEncoder *mEncoder = nullptr;
  std::vector<int16_t> mPending;   // accumulates until kFrameSize samples
  std::vector<uint8_t> mEncoded;   // scratch for one Opus frame
  bool mStarted = false;
};

#ifdef __cplusplus
extern "C" {
#endif

// C-linkage wrappers for use from moonlight_bridge.c (JNI layer).
// A single process-wide capturer instance is managed here.
int MicCapturer_Start();
void MicCapturer_Stop();

#ifdef __cplusplus
}
#endif
