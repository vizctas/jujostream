#include "OboeMicCapturer.h"

#include <mutex>

#include <Limelight.h>
#include <android/log.h>
#include <opus_multistream.h>

#define LOG_TAG "OboeMic"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {
  // Fixed negotiated format, kept in sync with the server decoder (audio.cpp).
  constexpr int kSampleRate = 48000;
  constexpr int kChannels = 1;
  constexpr int kFrameSize = 960;  // 20 ms @ 48 kHz
  constexpr int kBitrate = 32000;  // voice; keeps Opus frames well under the
                                   // ~200-byte control-channel cap (LiSendMicPacket)
  constexpr int kMaxPacket = 400;
}  // namespace

OboeMicCapturer::~OboeMicCapturer() {
  stop();
}

int OboeMicCapturer::openStream() {
  oboe::AudioStreamBuilder builder;
  builder.setDirection(oboe::Direction::Input)
    ->setSharingMode(oboe::SharingMode::Shared)
    ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
    // VoiceCommunication enables the platform AEC/NS/AGC — important since the
    // host audio is playing out of the same device's speakers.
    ->setInputPreset(oboe::InputPreset::VoiceCommunication)
    ->setFormat(oboe::AudioFormat::I16)
    ->setFormatConversionAllowed(true)
    ->setSampleRate(kSampleRate)
    ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::Medium)
    ->setChannelCount(kChannels)
    ->setFramesPerDataCallback(kFrameSize)
    ->setDataCallback(this)
    ->setErrorCallback(this);

  oboe::Result result = builder.openStream(mStream);
  if (result != oboe::Result::OK) {
    LOGE("Failed to open mic stream: %s", oboe::convertToText(result));
    return -1;
  }

  result = mStream->requestStart();
  if (result != oboe::Result::OK) {
    LOGE("Failed to start mic stream: %s", oboe::convertToText(result));
    mStream->close();
    mStream.reset();
    return -1;
  }

  LOGI("Mic capture started: rate=%d ch=%d frame=%d", kSampleRate, kChannels, kFrameSize);
  return 0;
}

int OboeMicCapturer::start() {
  if (mStarted) {
    return 0;
  }

  int err = 0;
  mEncoder = opus_encoder_create(kSampleRate, kChannels, OPUS_APPLICATION_VOIP, &err);
  if (err != OPUS_OK || !mEncoder) {
    LOGE("opus_encoder_create failed: %s", opus_strerror(err));
    mEncoder = nullptr;
    return -1;
  }
  opus_encoder_ctl(mEncoder, OPUS_SET_BITRATE(kBitrate));
  opus_encoder_ctl(mEncoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
  opus_encoder_ctl(mEncoder, OPUS_SET_DTX(1));  // skip near-silent frames

  mPending.clear();
  mPending.reserve(kFrameSize * 2);
  mEncoded.resize(kMaxPacket);

  if (openStream() != 0) {
    opus_encoder_destroy(mEncoder);
    mEncoder = nullptr;
    return -1;
  }

  mStarted = true;
  return 0;
}

void OboeMicCapturer::stop() {
  if (mStream) {
    mStream->stop();
    mStream->close();
    mStream.reset();
  }
  if (mEncoder) {
    opus_encoder_destroy(mEncoder);
    mEncoder = nullptr;
  }
  mPending.clear();
  if (mStarted) {
    LOGI("Mic capture stopped");
  }
  mStarted = false;
}

void OboeMicCapturer::flushPending() {
  while (mPending.size() >= static_cast<size_t>(kFrameSize)) {
    int bytes = opus_encode(mEncoder, mPending.data(), kFrameSize,
                            mEncoded.data(), static_cast<opus_int32>(mEncoded.size()));
    if (bytes > 0) {
      LiSendMicPacket(reinterpret_cast<const char *>(mEncoded.data()), bytes);
    } else if (bytes < 0) {
      LOGW("opus_encode failed: %s", opus_strerror(bytes));
    }
    // else bytes == 0: DTX dropped this frame, nothing to send.
    mPending.erase(mPending.begin(), mPending.begin() + kFrameSize);
  }
}

oboe::DataCallbackResult OboeMicCapturer::onAudioReady(
  oboe::AudioStream * /*stream*/, void *audioData, int32_t numFrames) {
  if (!mEncoder) {
    return oboe::DataCallbackResult::Continue;
  }
  const int16_t *in = static_cast<const int16_t *>(audioData);
  mPending.insert(mPending.end(), in, in + numFrames * kChannels);
  flushPending();
  return oboe::DataCallbackResult::Continue;
}

void OboeMicCapturer::onErrorAfterClose(oboe::AudioStream * /*stream*/, oboe::Result error) {
  LOGW("Mic stream error: %s — reopening", oboe::convertToText(error));
  if (mStarted) {
    mStream.reset();
    openStream();  // best-effort restart (e.g. headset unplugged)
  }
}

// ---- C-linkage single-instance management -------------------------------

namespace {
  std::mutex g_mic_mutex;
  std::unique_ptr<OboeMicCapturer> g_capturer;
}  // namespace

extern "C" int MicCapturer_Start() {
  std::lock_guard<std::mutex> lock(g_mic_mutex);
  if (g_capturer) {
    return 0;  // already running
  }
  auto cap = std::make_unique<OboeMicCapturer>();
  if (cap->start() != 0) {
    return -1;
  }
  g_capturer = std::move(cap);
  return 0;
}

extern "C" void MicCapturer_Stop() {
  std::lock_guard<std::mutex> lock(g_mic_mutex);
  if (g_capturer) {
    g_capturer->stop();
    g_capturer.reset();
  }
}
