package com.limelight.jujostream.native_bridge

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.os.Build
import android.util.Log

class AudioRenderer(
    private val enableAudioFx: Boolean = false,
    private val isWeakDevice: Boolean = false
) {
    companion object {
        private const val TAG = "AudioRenderer"

        const val AUDIO_CONFIGURATION_STEREO = 1
        const val AUDIO_CONFIGURATION_51_SURROUND = 2
        const val AUDIO_CONFIGURATION_71_SURROUND = 3

        private const val MIN_BUF_FRAMES = 2
        private const val MAX_BUF_FRAMES = 8
        private const val INITIAL_BUF_FRAMES = 4
        private const val UNDERRUN_THRESHOLD = 3
        private const val STABLE_MS_THRESHOLD = 5000L
    }

    private var audioTrack: AudioTrack? = null
    private var sampleRate = 48000
    private var channelCount = 2
    private var samplesPerFrame = 240
    private var channelConfig = AudioFormat.CHANNEL_OUT_STEREO

    private var bufferFrames = INITIAL_BUF_FRAMES
    private var underrunCount = 0
    private var lastStableTs = 0L
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var virtualizer: Virtualizer? = null

    fun init(audioConfig: Int, sampleRate: Int, samplesPerFrame: Int): Int {
        this.sampleRate = sampleRate
        this.samplesPerFrame = samplesPerFrame

        val extractedChannels = (audioConfig shr 8) and 0xFF
        channelCount = if (extractedChannels in 1..8) extractedChannels else 2

        channelConfig = when (channelCount) {
            6 -> AudioFormat.CHANNEL_OUT_5POINT1
            8 -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                     AudioFormat.CHANNEL_OUT_7POINT1_SURROUND
                 else AudioFormat.CHANNEL_OUT_STEREO
            else -> {
                channelCount = 2
                AudioFormat.CHANNEL_OUT_STEREO
            }
        }

        Log.i(TAG, "Initializing audio: rate=$sampleRate, channels=$channelCount, spf=$samplesPerFrame")
        bufferFrames = INITIAL_BUF_FRAMES
        return buildAudioTrack()
    }

    private fun buildAudioTrack(): Int {
        try {
            releaseAudioEffects()
            audioTrack?.release()

            val minBuf = AudioTrack.getMinBufferSize(sampleRate, channelConfig,
                AudioFormat.ENCODING_PCM_16BIT)
            val frameBuf = channelCount * samplesPerFrame * 2 * bufferFrames
            val actualBuf = maxOf(minBuf, frameBuf)

            audioTrack = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val audioAttributesBuilder = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    audioAttributesBuilder.setSpatializationBehavior(AudioAttributes.SPATIALIZATION_BEHAVIOR_AUTO)
                }

                val builder = AudioTrack.Builder()
                    .setAudioAttributes(audioAttributesBuilder.build())
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate)
                            .setChannelMask(channelConfig)
                            .build()
                    )
                    .setBufferSizeInBytes(actualBuf)
                    .setTransferMode(AudioTrack.MODE_STREAM)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                }
                builder.build()
            } else {
                @Suppress("DEPRECATION")
                AudioTrack(
                    AudioManager.STREAM_MUSIC, sampleRate, channelConfig,
                    AudioFormat.ENCODING_PCM_16BIT, actualBuf, AudioTrack.MODE_STREAM)
            }

            configureAudioEffects()

            Log.i(TAG, "AudioTrack created: buf=$actualBuf, frames=$bufferFrames")
            return 0
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize audio", e)
            return -1
        }
    }

    fun start() {
        try {
            audioTrack?.play()
            lastStableTs = System.currentTimeMillis()
            underrunCount = 0
            Log.i(TAG, "Audio playback started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start audio", e)
        }
    }

    fun playSample(pcmData: ByteArray, length: Int) {
        try {
            val track = audioTrack ?: return
            val written = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                track.write(pcmData, 0, length, AudioTrack.WRITE_NON_BLOCKING)
            } else {
                @Suppress("DEPRECATION")
                track.write(pcmData, 0, length)
            }
            adaptBuffer(written, length)
        } catch (e: Exception) {
            Log.e(TAG, "Error writing audio sample", e)
        }
    }

    fun playSample(pcmData: ShortArray) {
        try {
            val track = audioTrack ?: return
            val written = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                track.write(pcmData, 0, pcmData.size, AudioTrack.WRITE_NON_BLOCKING)
            } else {
                @Suppress("DEPRECATION")
                track.write(pcmData, 0, pcmData.size)
            }
            adaptBuffer(written, pcmData.size * 2)
        } catch (e: Exception) {
            Log.e(TAG, "Error writing audio sample", e)
        }
    }

    private fun adaptBuffer(written: Int, expected: Int) {
        if (written == 0) {
            underrunCount++
            if (underrunCount >= UNDERRUN_THRESHOLD && bufferFrames < MAX_BUF_FRAMES) {
                bufferFrames++
                underrunCount = 0
                lastStableTs = System.currentTimeMillis()
                Log.i(TAG, "Buffer underrun detected — growing to $bufferFrames frames")
                rebuildTrack()
            }
        } else {
            val now = System.currentTimeMillis()
            if (now - lastStableTs > STABLE_MS_THRESHOLD && bufferFrames > MIN_BUF_FRAMES) {
                bufferFrames--
                lastStableTs = now
                Log.i(TAG, "Stable playback — shrinking to $bufferFrames frames")
                rebuildTrack()
            }
        }
    }

    private fun rebuildTrack() {
        val wasPlaying = audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING
        buildAudioTrack()
        if (wasPlaying) audioTrack?.play()
    }

    private fun configureAudioEffects() {
        // Skip effects entirely on weak devices to preserve CPU headroom
        if (!enableAudioFx || isWeakDevice || Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
            if (isWeakDevice) Log.i(TAG, "Audio FX: skipped on weak device")
            return
        }

        val sessionId = audioTrack?.audioSessionId ?: return
        if (sessionId == AudioManager.ERROR) {
            return
        }

        try {
            loudnessEnhancer = LoudnessEnhancer(sessionId).apply {
                setTargetGain(300)
                enabled = true
            }
        } catch (e: Exception) {
            Log.w(TAG, "Audio FX: LoudnessEnhancer unavailable: ${e.message}")
            loudnessEnhancer = null
        }

        // API 32+: Android system Spatializer handles virtualization automatically
        // for streams marked CONTENT_TYPE_MOVIE — no per-session Virtualizer needed
        if (channelCount == 2 && Build.VERSION.SDK_INT < 32) {
            try {
                virtualizer = Virtualizer(0, sessionId).apply {
                    setStrength(300.toShort())
                    enabled = true
                }
            } catch (e: Exception) {
                Log.w(TAG, "Audio FX: Virtualizer unavailable: ${e.message}")
                virtualizer = null
            }
        } else if (Build.VERSION.SDK_INT >= 32) {
            Log.i(TAG, "Spatial audio: system Spatializer active (API ${Build.VERSION.SDK_INT})")
        }
    }

    private fun releaseAudioEffects() {
        try {
            loudnessEnhancer?.release()
        } catch (_: Exception) { }
        loudnessEnhancer = null

        try {
            virtualizer?.release()
        } catch (_: Exception) { }
        virtualizer = null
    }

    fun stop() {
        try {
            audioTrack?.pause()
            audioTrack?.flush()
            Log.i(TAG, "Audio playback stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping audio", e)
        }
    }

    fun cleanup() {
        try {
            releaseAudioEffects()
            audioTrack?.stop()
            audioTrack?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning up audio", e)
        }
        audioTrack = null
        Log.i(TAG, "Audio cleaned up")
    }
}
