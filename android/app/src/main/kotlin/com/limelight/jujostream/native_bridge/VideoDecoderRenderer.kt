package com.limelight.jujostream.native_bridge

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.TimeUnit

class VideoDecoderRenderer(
    private val textureEntry: TextureRegistry.SurfaceTextureEntry?,
    private val framePacingMode: Int = FRAME_PACING_BALANCED,
    private val enableHdr: Boolean = false,
    private val fullRange: Boolean = false,
    private val maxQueueDepth: Int = 0,
    private val useChoreographerVsync: Boolean = false,
    private val enableVrr: Boolean = false,
    private val externalSurface: Surface? = null,
    private val lowLatencyFrameBalance: Boolean = false,
    // TV-perf: map of MIME type → verified HW decoder name from CodecProbe.
    // The server can negotiate a different codec than what we preferred, so
    // we need the right decoder for *each* possible MIME type, not just one.
    private val decodersByMime: Map<String, String> = emptyMap(),
    // TV-perf: skip aggressive MediaFormat hints that overwhelm ARM32 chips
    private val isWeakDevice: Boolean = false
) {
    companion object {
        private const val TAG = "VideoDecoder"

        const val BUFFER_TYPE_PICDATA = 0
        const val BUFFER_TYPE_SPS = 1
        const val BUFFER_TYPE_PPS = 2
        const val BUFFER_TYPE_VPS = 3

        const val FRAME_TYPE_PFRAME = 0
        const val FRAME_TYPE_IDR = 1

        const val DR_OK = 0
        const val DR_NEED_IDR = -1

        const val FRAME_PACING_LATENCY    = 0
        const val FRAME_PACING_BALANCED   = 1
        const val FRAME_PACING_CAP_FPS    = 2
        const val FRAME_PACING_SMOOTHNESS = 3
        const val FRAME_PACING_ADAPTIVE   = 4

        private const val LATENCY_EMA_ALPHA = 0.05f

        private const val TIMING_RING_SIZE = 300
    }

    private var videoDecoder: MediaCodec? = null
    private var renderSurface: Surface? = null
    private var rendererThread: Thread? = null

    @Volatile private var stopping = false

    private var videoFormat = 0
    var initialWidth = 0
        private set
    var initialHeight = 0
        private set
    private var redrawRateFps = 60

    // when two IDR frames arrive in rapid succession (e.g. during reconnect).
    private val csdLock = Any()
    private var vpsBuffer: ByteArray? = null
    private var spsBuffer: ByteArray? = null
    private var ppsBuffer: ByteArray? = null
    private var submittedCsd = false

    @Volatile var totalFramesReceived = 0L
        private set
    @Volatile var totalFramesRendered = 0L
        private set
    @Volatile var totalFramesDropped = 0L
        private set
    @Volatile var avgDecodeLatencyMs = 0f
        private set

    private val frameTimingRing = FloatArray(TIMING_RING_SIZE)
    private var frameTimingIndex = 0
    private var frameTimingCount = 0
    private val interFrameRing = FloatArray(TIMING_RING_SIZE)
    private var interFrameIndex = 0
    private var interFrameCount = 0
    @Volatile private var lastRenderNs = 0L

    private var decoderName = "unknown"
    private var activeRenderPath = "texture"

    // ── Vendor quirk flags (resolved in setup() after decoder creation) ──
    private var isMediaTekDecoder = false
    private var isExynosDecoder = false

    // ── Zero-output watchdog state ──────────────────────────────────────
    @Volatile private var startTimeNs = 0L
    private var zeroOutputWarningEmitted = false

    private val queueTimestampNs = HashMap<Long, Long>(64)

    // Choreographer vsync: holds decoded buffer indices ready for presentation
    private data class PendingFrame(val bufferIndex: Int, val ptsUs: Long)
    private val pendingFrames = LinkedBlockingDeque<PendingFrame>(8)
    @Volatile private var vsyncPresenterThread: Thread? = null

    fun setup(videoFormat: Int, width: Int, height: Int, redrawRate: Int): Int {
        this.videoFormat = videoFormat
        this.initialWidth = width
        this.initialHeight = height
        this.redrawRateFps = redrawRate

        Log.i(TAG, "Setting up decoder: ${width}x${height}@${redrawRate}fps, " +
            "format=0x${videoFormat.toString(16)}, pacing=$framePacingMode, " +
            "hdr=$enableHdr, queueDepth=$maxQueueDepth, choreographer=$useChoreographerVsync, " +
            "lowLatencyFrameBalance=$lowLatencyFrameBalance")

        try {
            val mimeType = StreamConstants.mimeTypeForFormat(videoFormat) ?: run {
                Log.e(TAG, "Unknown video format: 0x${videoFormat.toString(16)}")
                return -1
            }

            renderSurface = if (externalSurface != null && externalSurface.isValid) {
                Log.i(TAG, "Using direct submit surface (SurfaceControl path)")
                activeRenderPath = if (useChoreographerVsync) "direct-submit-vsync" else "direct-submit"
                externalSurface
            } else {
                Log.i(TAG, "Using SurfaceTexture path")
                activeRenderPath = if (useChoreographerVsync) "texture-vsync" else "texture"
                Surface(textureEntry!!.surfaceTexture().apply { setDefaultBufferSize(width, height) })
            }

            // VRR: hint compositor about ideal cadence
            if (enableVrr && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    renderSurface!!.setFrameRate(
                        redrawRate.toFloat(),
                        Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                        Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS
                    )
                    Log.i(TAG, "VRR: Surface frame rate hint set to ${redrawRate}fps")
                } catch (e: Exception) {
                    Log.w(TAG, "VRR: setFrameRate failed: ${e.message}")
                }
            }

            // ── Step 1: Create decoder BEFORE configuring format ─────────
            // We need the decoder name to detect vendor quirks (MediaTek,
            // Exynos) that affect which MediaFormat keys are safe to use.
            val matchedDecoder = decodersByMime[mimeType]
            videoDecoder = if (!matchedDecoder.isNullOrBlank()) {
                try {
                    Log.i(TAG, "Using explicit decoder: $matchedDecoder (for $mimeType)")
                    MediaCodec.createByCodecName(matchedDecoder)
                } catch (e: Exception) {
                    Log.w(TAG, "Explicit decoder failed ($matchedDecoder): ${e.message} — type fallback")
                    MediaCodec.createDecoderByType(mimeType)
                }
            } else {
                Log.i(TAG, "No explicit decoder for $mimeType — using type fallback")
                MediaCodec.createDecoderByType(mimeType)
            }
            decoderName = videoDecoder!!.name

            // ── Step 2: Detect vendor quirks from decoder name ───────────
            val nameLower = decoderName.lowercase()
            isMediaTekDecoder = nameLower.contains("mtk") || nameLower.contains("mediatek")
            isExynosDecoder = nameLower.contains("exynos")

            // [G] Diagnostic: log device + decoder identity for remote debugging
            val socModel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL else "unknown"
            Log.i(TAG, "┌─── DECODER DIAGNOSTIC ───────────────────────────")
            Log.i(TAG, "│ Device: ${Build.MANUFACTURER} ${Build.MODEL}")
            Log.i(TAG, "│ SoC: hw=${Build.HARDWARE} board=${Build.BOARD} soc=$socModel")
            Log.i(TAG, "│ Android: API ${Build.VERSION.SDK_INT} (${Build.VERSION.RELEASE})")
            Log.i(TAG, "│ Decoder: $decoderName")
            Log.i(TAG, "│ MIME: $mimeType")
            Log.i(TAG, "│ Quirks: mtk=$isMediaTekDecoder exynos=$isExynosDecoder weak=$isWeakDevice")
            Log.i(TAG, "└──────────────────────────────────────────────────")

            // ── Step 3: Build MediaFormat with vendor-aware keys ─────────
            val format = MediaFormat.createVideoFormat(mimeType, width, height)

            // Pre-declare max resolution so the decoder allocates buffers at the right size
            format.setInteger(MediaFormat.KEY_MAX_WIDTH, width)
            format.setInteger(MediaFormat.KEY_MAX_HEIGHT, height)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                format.setInteger(MediaFormat.KEY_FRAME_RATE, redrawRate)
                // TV-perf: weak ARM32 SoCs (MT8696, Amlogic) cannot sustain
                // full-fps decode at realtime priority. Cap operating rate and
                // use background priority so the scheduler doesn't starve the
                // render thread. On capable devices keep original behavior.
                if (isWeakDevice) {
                    format.setFloat(MediaFormat.KEY_OPERATING_RATE, minOf(redrawRate, 30).toFloat())
                    format.setInteger(MediaFormat.KEY_PRIORITY, 1)
                } else {
                    // [C] Use Short.MAX_VALUE instead of exact FPS to avoid
                    // "guaranteed performance" mode that silently fails on some
                    // MediaTek Dimensity and Samsung Exynos C2 decoders.
                    // ExoPlayer uses this same approach in production.
                    format.setFloat(MediaFormat.KEY_OPERATING_RATE, Short.MAX_VALUE.toFloat())
                    format.setInteger(MediaFormat.KEY_PRIORITY, 0)
                }
            }

            // [B] KEY_LOW_LATENCY causes MediaTek C2 decoders (Dimensity) and
            // some Samsung Exynos C2 decoders to never produce output frames.
            // Moonlight upstream and ExoPlayer both skip this key on these vendors.
            // Only enable on known-good vendors (Qualcomm, Nvidia, etc.).
            val applyLowLatency = !isWeakDevice &&
                !isMediaTekDecoder &&
                !isExynosDecoder &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
            if (applyLowLatency) {
                format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }
            Log.i(TAG, "MediaFormat: lowLatency=$applyLowLatency opRate=${
                if (isWeakDevice) "capped" else "MAX"} priority=${if (isWeakDevice) 1 else 0}")

            // being hardcoded to LIMITED. When fullRange=true, the decoder
            // uses FULL range which preserves the complete 0-255 luma range.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val colorRange = if (fullRange) MediaFormat.COLOR_RANGE_FULL
                                 else MediaFormat.COLOR_RANGE_LIMITED

                if (enableHdr && (mimeType == "video/hevc" || mimeType == "video/av01")) {
                    format.setInteger(MediaFormat.KEY_COLOR_RANGE, colorRange)
                    format.setInteger(MediaFormat.KEY_COLOR_STANDARD,
                        MediaFormat.COLOR_STANDARD_BT2020)
                    format.setInteger(MediaFormat.KEY_COLOR_TRANSFER,
                        MediaFormat.COLOR_TRANSFER_ST2084)
                    Log.i(TAG, "HDR10 color metadata applied (BT.2020 / PQ, range=${if (fullRange) "FULL" else "LIMITED"})")
                } else {
                    format.setInteger(MediaFormat.KEY_COLOR_RANGE, colorRange)
                    format.setInteger(MediaFormat.KEY_COLOR_STANDARD,
                        MediaFormat.COLOR_STANDARD_BT709)
                    format.setInteger(MediaFormat.KEY_COLOR_TRANSFER,
                        MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
                    Log.i(TAG, "SDR color metadata applied (BT.709, range=${if (fullRange) "FULL" else "LIMITED"})")
                }
            }

            // ── Step 4: Configure and start ──────────────────────────────
            videoDecoder!!.configure(format, renderSurface, null, 0)
            videoDecoder!!.start()

            Log.i(TAG, "Decoder started: $decoderName via $activeRenderPath")
            return 0

        } catch (e: Exception) {
            Log.e(TAG, "Failed to set up decoder", e)
            return -1
        }
    }

    // reports accurate deltas instead of the entire previous session's count.
    fun resetStats() {
        totalFramesReceived = 0L
        totalFramesRendered = 0L
        totalFramesDropped = 0L
        avgDecodeLatencyMs = 0f
        frameTimingIndex = 0; frameTimingCount = 0
        interFrameIndex = 0; interFrameCount = 0
        lastRenderNs = 0L
        startTimeNs = System.nanoTime()
        zeroOutputWarningEmitted = false
        synchronized(queueTimestampNs) { queueTimestampNs.clear() }
    }

    fun start() {
        stopping = false
        pendingFrames.clear()

        if (useChoreographerVsync && Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            // Vsync-aligned: decoder thread fills queue, Choreographer presents
            rendererThread = Thread({
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_DISPLAY)
                decoderDrainLoop()
            }, "Video-Decoder-Drain").apply { start() }

            vsyncPresenterThread = Thread({
                // On weak single-core ARM32, two URGENT_DISPLAY threads
                // fight the scheduler — lower vsync presenter to DISPLAY
                val prio = if (isWeakDevice) android.os.Process.THREAD_PRIORITY_DISPLAY
                           else android.os.Process.THREAD_PRIORITY_URGENT_DISPLAY
                android.os.Process.setThreadPriority(prio)
                android.os.Looper.prepare()
                val choreographer = Choreographer.getInstance()
                val vsyncCallback = object : Choreographer.FrameCallback {
                    override fun doFrame(frameTimeNanos: Long) {
                        if (stopping) return
                        presentAtVsync(frameTimeNanos)
                        choreographer.postFrameCallback(this)
                    }
                }
                choreographer.postFrameCallback(vsyncCallback)
                android.os.Looper.loop()
            }, "Video-Vsync-Presenter").apply { start() }
        } else {
            rendererThread = Thread({
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_DISPLAY)
                when (framePacingMode) {
                    FRAME_PACING_LATENCY    -> renderLoopMinLatency()
                    FRAME_PACING_BALANCED   -> renderLoopBalanced()
                    FRAME_PACING_CAP_FPS    -> renderLoopCapFps()
                    FRAME_PACING_SMOOTHNESS -> renderLoopSmoothness()
                    FRAME_PACING_ADAPTIVE   -> renderLoopAdaptive()
                    else                    -> renderLoopBalanced()
                }
            }, "Video-Renderer").apply { start() }
        }
    }

    private fun renderLoopMinLatency() {
        val info = MediaCodec.BufferInfo()
        val decoder = videoDecoder ?: return

        while (!stopping) {
            try {
                // Block up to 2ms — the kernel wakes this thread the instant a frame is ready,
                // avoiding the OS scheduler overhead of Thread.sleep()
                val firstIdx = decoder.dequeueOutputBuffer(info, 2_000)
                if (firstIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    Log.i(TAG, "Output format changed: ${decoder.outputFormat}")
                    continue
                }
                if (firstIdx < 0) continue

                var newestIndex = firstIdx
                var newestPtsUs = info.presentationTimeUs

                // Non-blocking drain — only keep the freshest decoded frame
                while (true) {
                    val idx = decoder.dequeueOutputBuffer(info, 0)
                    when {
                        idx >= 0 -> {
                            decoder.releaseOutputBuffer(newestIndex, false)
                            totalFramesDropped++
                            updateDecodeLatency(newestPtsUs)
                            newestIndex = idx
                            newestPtsUs = info.presentationTimeUs
                        }
                        idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ->
                            Log.i(TAG, "Output format changed: ${decoder.outputFormat}")
                        else -> break
                    }
                }

                presentLowLatencyFrame(decoder, newestIndex, newestPtsUs)
            } catch (e: InterruptedException) {
                break
            } catch (e: IllegalStateException) {
                if (!stopping) Log.e(TAG, "Render error (minLatency)", e)
            }
        }
    }

    private fun renderLoopBalanced() {
        val info = MediaCodec.BufferInfo()
        val decoder = videoDecoder ?: return

        while (!stopping) {
            try {
                val outIndex = decoder.dequeueOutputBuffer(info, 5000)
                when {
                    outIndex >= 0 -> {

                        val presentNs = info.presentationTimeUs * 1000L
                        decoder.releaseOutputBuffer(outIndex, presentNs)
                        totalFramesRendered++
                        updateDecodeLatency(info.presentationTimeUs)
                    }
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ->
                        Log.i(TAG, "Output format changed: ${decoder.outputFormat}")

                }
            } catch (e: IllegalStateException) {
                if (!stopping) Log.e(TAG, "Render error (balanced)", e)
            }
        }
    }

    private fun renderLoopCapFps() {
        val info = MediaCodec.BufferInfo()
        val decoder = videoDecoder ?: return
        val vsyncPeriodUs = if (redrawRateFps > 0) 1_000_000L / redrawRateFps else 16_667L

        while (!stopping) {
            try {
                val outIndex = decoder.dequeueOutputBuffer(info, 5000)
                when {
                    outIndex >= 0 -> {
                        val nowUs = System.nanoTime() / 1000L
                        val ageUs = nowUs - info.presentationTimeUs
                        if (ageUs > vsyncPeriodUs) {

                            decoder.releaseOutputBuffer(outIndex, false)
                            totalFramesDropped++
                        } else {
                            decoder.releaseOutputBuffer(outIndex, info.presentationTimeUs * 1000L)
                            totalFramesRendered++
                            updateDecodeLatency(info.presentationTimeUs)
                        }
                    }
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ->
                        Log.i(TAG, "Output format changed: ${decoder.outputFormat}")
                }
            } catch (e: IllegalStateException) {
                if (!stopping) Log.e(TAG, "Render error (capFps)", e)
            }
        }
    }

    private fun renderLoopSmoothness() {
        val info = MediaCodec.BufferInfo()
        val decoder = videoDecoder ?: return

        while (!stopping) {
            try {
                val outIndex = decoder.dequeueOutputBuffer(info, 5000)
                when {
                    outIndex >= 0 -> {
                        decoder.releaseOutputBuffer(outIndex, true)
                        totalFramesRendered++
                        updateDecodeLatency(info.presentationTimeUs)
                    }
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ->
                        Log.i(TAG, "Output format changed: ${decoder.outputFormat}")
                }
            } catch (e: IllegalStateException) {
                if (!stopping) Log.e(TAG, "Render error (smoothness)", e)
            }
        }
    }

    private fun renderLoopAdaptive() {
        val info = MediaCodec.BufferInfo()
        val decoder = videoDecoder ?: return

        var consecutiveDrops = 0
        var consecutiveSmooth = 0
        var useLatencyMode = false

        while (!stopping) {
            try {
                if (useLatencyMode) {
                    // Drain to freshest frame
                    var lastIndex = -1
                    var lastPtsUs = 0L
                    while (true) {
                        val idx = decoder.dequeueOutputBuffer(info, 0)
                        when {
                            idx >= 0 -> {
                                if (lastIndex >= 0) {
                                    decoder.releaseOutputBuffer(lastIndex, false)
                                    totalFramesDropped++
                                    updateDecodeLatency(lastPtsUs)
                                }
                                lastIndex = idx
                                lastPtsUs = info.presentationTimeUs
                            }
                            idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ->
                                Log.i(TAG, "Output format changed: ${decoder.outputFormat}")
                            else -> break
                        }
                    }
                    if (lastIndex >= 0) {
                        presentLowLatencyFrame(decoder, lastIndex, lastPtsUs)
                        consecutiveSmooth++
                        consecutiveDrops = 0
                        // Wider hysteresis window prevents mode-thrashing
                        if (consecutiveSmooth > 50) {
                            useLatencyMode = false
                            consecutiveSmooth = 0
                        }
                    } else {
                        // Kernel-mediated wait rather than OS sleep for lower latency
                        val probe = decoder.dequeueOutputBuffer(info, 2_000)
                        if (probe >= 0) presentLowLatencyFrame(decoder, probe, info.presentationTimeUs)
                    }
                } else {
                    // Balanced mode with queue-depth monitoring
                    val outIndex = decoder.dequeueOutputBuffer(info, 5000)
                    when {
                        outIndex >= 0 -> {
                            val queueDepth = StreamingBridge.nativeGetPendingVideoFrames()
                            if (queueDepth > 2) {
                                consecutiveDrops++
                                // Require more consecutive drops before mode switch
                                if (consecutiveDrops > 5) {
                                    useLatencyMode = true
                                    consecutiveDrops = 0
                                    consecutiveSmooth = 0
                                }
                            } else {
                                consecutiveDrops = 0
                            }
                            val presentNs = info.presentationTimeUs * 1000L
                            decoder.releaseOutputBuffer(outIndex, presentNs)
                            totalFramesRendered++
                            updateDecodeLatency(info.presentationTimeUs)
                        }
                        outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ->
                            Log.i(TAG, "Output format changed: ${decoder.outputFormat}")
                    }
                }
            } catch (e: InterruptedException) {
                break
            } catch (e: IllegalStateException) {
                if (!stopping) Log.e(TAG, "Render error (adaptive)", e)
            }
        }
    }

    private fun decoderDrainLoop() {
        val info = MediaCodec.BufferInfo()
        val decoder = videoDecoder ?: return
        val effectiveDepth = if (maxQueueDepth > 0) maxQueueDepth else 2

        while (!stopping) {
            try {
                val idx = decoder.dequeueOutputBuffer(info, 8_000)
                when {
                    idx >= 0 -> {
                        val frame = PendingFrame(idx, info.presentationTimeUs)

                        // Enforce queue depth — shed oldest if over budget
                        while (pendingFrames.size >= effectiveDepth) {
                            val stale = pendingFrames.pollFirst() ?: break
                            try {
                                decoder.releaseOutputBuffer(stale.bufferIndex, false)
                            } catch (_: IllegalStateException) { }
                            totalFramesDropped++
                            updateDecodeLatency(stale.ptsUs)
                        }

                        pendingFrames.offerLast(frame)
                    }
                    idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ->
                        Log.i(TAG, "Output format changed: ${decoder.outputFormat}")
                }
            } catch (e: InterruptedException) {
                break
            } catch (e: IllegalStateException) {
                if (!stopping) Log.e(TAG, "Decoder drain error", e)
            }
        }

        // Flush remaining queued frames on shutdown
        while (true) {
            val leftover = pendingFrames.pollFirst() ?: break
            try {
                videoDecoder?.releaseOutputBuffer(leftover.bufferIndex, false)
            } catch (_: Exception) { }
        }
    }

    private fun presentAtVsync(vsyncNanos: Long) {
        val decoder = videoDecoder ?: return
        var chosen: PendingFrame? = null

        // Drain queue: keep only the newest available frame
        while (true) {
            val candidate = pendingFrames.pollFirst() ?: break
            if (chosen != null) {
                // Drop the previously selected — a newer one exists
                try {
                    decoder.releaseOutputBuffer(chosen.bufferIndex, false)
                } catch (_: IllegalStateException) { }
                totalFramesDropped++
                updateDecodeLatency(chosen.ptsUs)
            }
            chosen = candidate
        }

        if (chosen != null) {
            try {
                // Present with vsync timestamp for compositor alignment
                decoder.releaseOutputBuffer(chosen.bufferIndex, vsyncNanos)
                totalFramesRendered++
                updateDecodeLatency(chosen.ptsUs)
            } catch (e: IllegalStateException) {
                if (!stopping) Log.e(TAG, "Vsync present error", e)
            }
        }
    }

    private fun updateDecodeLatency(ptsUs: Long) {
        val nowNs = System.nanoTime()
        val queueNs = synchronized(queueTimestampNs) { queueTimestampNs.remove(ptsUs) } ?: return
        val latencyMs = (nowNs - queueNs) / 1_000_000f

        avgDecodeLatencyMs = if (avgDecodeLatencyMs == 0f) latencyMs
            else avgDecodeLatencyMs * (1f - LATENCY_EMA_ALPHA) + latencyMs * LATENCY_EMA_ALPHA

        frameTimingRing[frameTimingIndex] = latencyMs
        frameTimingIndex = (frameTimingIndex + 1) % TIMING_RING_SIZE
        if (frameTimingCount < TIMING_RING_SIZE) frameTimingCount++

        val prevNs = lastRenderNs
        lastRenderNs = nowNs
        if (prevNs > 0L) {
            val intervalMs = (nowNs - prevNs) / 1_000_000f
            interFrameRing[interFrameIndex] = intervalMs
            interFrameIndex = (interFrameIndex + 1) % TIMING_RING_SIZE
            if (interFrameCount < TIMING_RING_SIZE) interFrameCount++
        }
    }

    private fun presentLowLatencyFrame(decoder: MediaCodec, bufferIndex: Int, ptsUs: Long) {
        if (lowLatencyFrameBalance) {
            decoder.releaseOutputBuffer(bufferIndex, lowLatencyPresentationTimeNs(ptsUs))
        } else {
            decoder.releaseOutputBuffer(bufferIndex, true)
        }
        totalFramesRendered++
        updateDecodeLatency(ptsUs)
    }

    private fun lowLatencyPresentationTimeNs(ptsUs: Long): Long {
        val frameIntervalNs = if (redrawRateFps > 0) 1_000_000_000L / redrawRateFps else 16_666_667L
        val nowNs = System.nanoTime()
        val queuedAtNs = ptsUs * 1000L
        val queueAgeNs = (nowNs - queuedAtNs).coerceAtLeast(0L)
        if (queueAgeNs >= frameIntervalNs) {
            return nowNs
        }

        val cadenceSlackNs = (frameIntervalNs / 4L).coerceAtLeast(1_000_000L)
        return nowNs + cadenceSlackNs
    }

    fun submitDecodeUnit(
        data: java.nio.ByteBuffer, length: Int, bufferType: Int,
        frameNumber: Int, frameType: Int,
        receiveTimeMs: Long, enqueueTimeMs: Long
    ): Int {
        if (stopping) return DR_OK
        val decoder = videoDecoder ?: return DR_NEED_IDR
        totalFramesReceived++

        // [G] Zero-output watchdog: detect when the decoder is consuming
        // input but never producing output. This is the exact symptom on
        // MediaTek Dimensity and Samsung Exynos S25 Ultra devices.
        // Fires once after 5 seconds of receiving frames with 0 rendered.
        if (!zeroOutputWarningEmitted && totalFramesRendered == 0L &&
            totalFramesReceived > 60 && startTimeNs > 0L) {
            val elapsedNs = System.nanoTime() - startTimeNs
            if (elapsedNs > 5_000_000_000L) {
                zeroOutputWarningEmitted = true
                Log.e(TAG, "┌─── ⚠ ZERO OUTPUT DETECTED ────────────────────────")
                Log.e(TAG, "│ $totalFramesReceived frames received, 0 rendered after ${elapsedNs / 1_000_000}ms")
                Log.e(TAG, "│ Decoder: $decoderName")
                Log.e(TAG, "│ Quirks: mtk=$isMediaTekDecoder exynos=$isExynosDecoder weak=$isWeakDevice")
                Log.e(TAG, "│ CSD submitted: $submittedCsd")
                Log.e(TAG, "│ CSD sizes: vps=${vpsBuffer?.size ?: 0} sps=${spsBuffer?.size ?: 0} pps=${ppsBuffer?.size ?: 0}")
                Log.e(TAG, "│ Render path: $activeRenderPath")
                Log.e(TAG, "│ This decoder may not support the current MediaFormat configuration.")
                Log.e(TAG, "│ Check KEY_LOW_LATENCY, KEY_OPERATING_RATE, and CSD handling.")
                Log.e(TAG, "└───────────────────────────���───────────────────────")
            }
        }

        // [G] Periodic frame stats for remote debugging (every 300 frames)
        if (totalFramesReceived % 300 == 0L) {
            Log.i(TAG, "FRAME STATS: recv=$totalFramesReceived rendered=$totalFramesRendered " +
                "dropped=$totalFramesDropped latency=${avgDecodeLatencyMs.toInt()}ms decoder=$decoderName")
        }

        try {

            if (frameType == FRAME_TYPE_IDR) {
                if (bufferType != BUFFER_TYPE_PICDATA) {
                    val csdArray = ByteArray(length)
                    data.position(0)
                    data.limit(length)
                    data.get(csdArray)
                    when (bufferType) {
                        BUFFER_TYPE_VPS -> { synchronized(csdLock) { vpsBuffer = csdArray }; return DR_OK }
                        BUFFER_TYPE_SPS -> { synchronized(csdLock) { spsBuffer = csdArray }; return DR_OK }
                        BUFFER_TYPE_PPS -> { synchronized(csdLock) { ppsBuffer = csdArray }; return DR_OK }
                    }
                } else {
                    if (!submitCsdBuffers()) return DR_NEED_IDR
                    submittedCsd = true
                }
            }

            // On weak devices the old fixed 20ms timeout triggered IDR requests
            // too aggressively — each IDR costs 100-500ms of stall as the server
            // encodes a full keyframe. Progressive backoff: try a short wait first,
            // then retry with a longer one before giving up. This reduces IDR
            // cascade on overloaded SoCs while keeping latency low on capable ones.
            val inputIndex = acquireInputBuffer(decoder)
            if (inputIndex < 0) {
                return DR_NEED_IDR
            }

            val inputBuffer = decoder.getInputBuffer(inputIndex) ?: return DR_NEED_IDR
            inputBuffer.clear()
            
            // No JNI unboxing array copy needed! Massive CPU/Memory optimization for Android TV.
            data.position(0)
            data.limit(length)
            inputBuffer.put(data)

            val flags = if (frameType == FRAME_TYPE_IDR && bufferType == BUFFER_TYPE_PICDATA) MediaCodec.BUFFER_FLAG_SYNC_FRAME else 0
            val timestampUs = enqueueTimeMs * 1000L

            synchronized(queueTimestampNs) {
                queueTimestampNs[timestampUs] = System.nanoTime()

                // Tighter eviction on weak devices to bound memory
                val evictionThreshold = if (isWeakDevice) 32 else 128
                if (queueTimestampNs.size > evictionThreshold) {
                    val cutoffNs = System.nanoTime() - 1_000_000_000L // 1 second
                    queueTimestampNs.entries.removeAll { it.value < cutoffNs }
                }
            }

            decoder.queueInputBuffer(inputIndex, 0, length, timestampUs, flags)
            return DR_OK

        } catch (e: IllegalStateException) {
            Log.e(TAG, "Error submitting decode unit", e)
            return DR_NEED_IDR
        }
    }

    private fun acquireInputBuffer(decoder: MediaCodec): Int {
        val timeoutsUs = if (isWeakDevice)
            longArrayOf(5_000L, 15_000L, 30_000L)
        else
            longArrayOf(2_000L, 5_000L, 10_000L)

        for (i in timeoutsUs.indices) {
            val idx = decoder.dequeueInputBuffer(timeoutsUs[i])
            if (idx >= 0) return idx
        }

        val totalMs = timeoutsUs.sum() / 1000
        Log.w(TAG, "No input buffer after ${totalMs}ms (${timeoutsUs.size} attempts) — requesting IDR")
        return -1
    }

    private fun submitCsdBuffers(): Boolean {
        val decoder = videoDecoder ?: return false

        val (snapVps, snapSps, snapPps) = synchronized(csdLock) {
            Triple(vpsBuffer?.copyOf(), spsBuffer?.copyOf(), ppsBuffer?.copyOf())
        }

        if (snapSps == null && snapVps == null) {
            Log.w(TAG, "No CSD buffers available for IDR — requesting IDR")
            return false
        }
        try {
            // Match CSD timeout to weak-device timeout (20ms)
            val csdTimeoutUs = if (isWeakDevice) 20_000L else 10_000L
            val inputIndex = decoder.dequeueInputBuffer(csdTimeoutUs)
            if (inputIndex < 0) return false

            val inputBuffer = decoder.getInputBuffer(inputIndex) ?: return false
            inputBuffer.clear()

            snapVps?.let { inputBuffer.put(it) }
            snapSps?.let { inputBuffer.put(it) }
            snapPps?.let { inputBuffer.put(it) }

            val totalLength = inputBuffer.position()
            decoder.queueInputBuffer(inputIndex, 0, totalLength, 0,
                MediaCodec.BUFFER_FLAG_CODEC_CONFIG)

            Log.i(TAG, "Submitted CSD: vps=${vpsBuffer != null}, " +
                "sps=${spsBuffer?.size ?: 0}B, pps=${ppsBuffer?.size ?: 0}B")
            return true

        } catch (e: Exception) {
            Log.e(TAG, "Error submitting CSD", e)
            return false
        }
    }

    fun stop() {
        stopping = true
        rendererThread?.interrupt()
        try { rendererThread?.join(1000) } catch (_: InterruptedException) { }
        vsyncPresenterThread?.let { t ->
            t.interrupt()
            try { t.join(500) } catch (_: InterruptedException) { }
        }
        vsyncPresenterThread = null
    }

    fun cleanup() {
        pendingFrames.clear()
        try {
            videoDecoder?.stop()
            videoDecoder?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning up decoder", e)
        }
        videoDecoder = null
        // Only release Surface if we own it (SurfaceTexture path)
        if (externalSurface == null) {
            renderSurface?.release()
        }
        renderSurface = null
        textureEntry?.release()

        vpsBuffer = null
        spsBuffer = null
        ppsBuffer = null
        submittedCsd = false
        synchronized(queueTimestampNs) { queueTimestampNs.clear() }
    }

    fun getStats(): Map<String, Any> {
        // Optimize: Sort the timing arrays only once per stats fetch
        val decodeTimings = if (frameTimingCount > 0) {
            val copy = frameTimingRing.copyOf(frameTimingCount)
            copy.sort()
            copy
        } else null

        val interFrameTimings = if (interFrameCount > 0) {
            val copy = interFrameRing.copyOf(interFrameCount)
            copy.sort()
            copy
        } else null

        return mapOf(
            "framesReceived"  to totalFramesReceived,
            "framesRendered"  to totalFramesRendered,
            "framesDropped"   to totalFramesDropped,
            "decodeLatencyMs" to avgDecodeLatencyMs,
            "framePacingMode" to framePacingMode,
            "queueDepth"      to pendingFrames.size,
            "decoderName"     to decoderName,
            "renderPath"      to activeRenderPath,
            "p50" to calculatePercentile(decodeTimings, 50f),
            "p95" to calculatePercentile(decodeTimings, 95f),
            "p99" to calculatePercentile(decodeTimings, 99f),
            "interFrameP50" to calculatePercentile(interFrameTimings, 50f),
            "interFrameP95" to calculatePercentile(interFrameTimings, 95f),
            "interFrameP99" to calculatePercentile(interFrameTimings, 99f)
        )
    }

    private fun calculatePercentile(sortedArray: FloatArray?, percentile: Float): Double {
        if (sortedArray == null || sortedArray.isEmpty()) return 0.0
        val index = ((percentile / 100f) * (sortedArray.size - 1)).toInt().coerceIn(0, sortedArray.size - 1)
        return sortedArray[index].toDouble()
    }
}
