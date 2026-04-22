package com.limelight.jujostream

import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.content.Intent
import com.limelight.jujostream.native_bridge.PairingForegroundService
import android.util.Rational
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.limelight.jujostream.native_bridge.GamepadHandler
import com.limelight.jujostream.native_bridge.StreamingPlugin

class MainActivity : FlutterActivity() {
    private var gamepadHandler: GamepadHandler? = null

    // ── Pairing state ────────────────────────────────────────────────────────
    // True while pair() is in-flight. The PairingForegroundService holds the
    // actual WifiLock + WakeLock — they survive Activity pause/stop because
    // they live in the Service, not the Activity.
    private var isPairingActive = false

    /**
     * Starts the Foreground Service with Phase 1 URL for native long-poll.
     * The service acquires WifiLock + WakeLock AND runs the HTTP GET in a
     * native Java thread that survives Dart VM pause.
     */
    private fun acquireAndPoll(phase1Url: String, timeoutMs: Long) {
        isPairingActive = true
        PairingForegroundService.reset()

        try {
            val intent = Intent(this, PairingForegroundService::class.java).apply {
                putExtra("phase1Url", phase1Url)
                putExtra("timeoutMs", timeoutMs)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {}
    }

    private fun releasePairingLocks() {
        isPairingActive = false
        refreshPipParams()

        PairingForegroundService.cancelRequested.set(true)
        try {
            val intent = Intent(this, PairingForegroundService::class.java)
            stopService(intent)
        } catch (_: Exception) {}
    }

    /**
     * Returns the Phase 1 result as a Map, or null if still in progress.
     */
    private fun pollPhase1Result(): Map<String, Any?>? {
        val result = PairingForegroundService.phase1Result.get() ?: return null
        return mapOf(
            "success" to result.success,
            "statusCode" to result.statusCode,
            "body" to result.body,
            "error" to result.error
        )
    }

    // Updates the PiP parameters so Android knows when auto-enter is allowed.
    // Must be called whenever streaming/pairing state changes.
    private fun refreshPipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val active = StreamingPlugin.isStreamingActive
        val ratio = if (StreamingPlugin.isStreamingActive) Rational(16, 9) else Rational(9, 16)
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(ratio)
            .setAutoEnterEnabled(active)
            .build()
        runCatching { setPictureInPictureParams(params) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.plugins.add(StreamingPlugin())

        gamepadHandler = GamepadHandler(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jujostream/tv_detector")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAndroidTV" -> {
                        val isTV = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                        result.success(isTV)
                    }
                    "isLowRamDevice" -> {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        result.success(am.isLowRamDevice)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jujostream/pairing_locks")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireAndPoll" -> {
                        val url = call.argument<String>("url") ?: ""
                        val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: 120_000L
                        acquireAndPoll(url, timeoutMs)
                        result.success(null)
                    }
                    "pollResult" -> {
                        result.success(pollPhase1Result())
                    }
                    "release" -> {
                        releasePairingLocks()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.decorView.post { killFocusHighlightRecursive(window.decorView) }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)

        window.decorView.post { killFocusHighlightRecursive(window.decorView) }

        refreshPipParams()
    }

    private fun killFocusHighlightRecursive(view: View) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            view.defaultFocusHighlightEnabled = false
        }

        if (view === window.decorView) {
            view.foreground = null
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                killFocusHighlightRecursive(view.getChildAt(i))
            }
        }
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (gamepadHandler?.handleMotionEvent(event) == true) return true
        return super.dispatchGenericMotionEvent(event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (gamepadHandler?.handleKeyEvent(event) == true) return true

        val remapped = gamepadHandler?.remapKeyEventForFlutter(event) ?: event
        return super.dispatchKeyEvent(remapped)
    }

    override fun onDestroy() {
        releasePairingLocks() // safety: release any held locks if activity is destroyed
        gamepadHandler?.dispose()
        gamepadHandler = null
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        tryEnterPip()
    }

    override fun onPause() {
        super.onPause()
        if (!isFinishing) tryEnterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPicture: Boolean,
        newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPicture, newConfig)
        StreamingPlugin.isPipMode = isInPicture
        if (!isInPicture && StreamingPlugin.reconnectAfterPip) {
            StreamingPlugin.reconnectAfterPip = false
            StreamingPlugin.notifyReconnectNeeded()
        }
    }

    private fun tryEnterPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!StreamingPlugin.isStreamingActive) return
        if (isInPictureInPictureMode) return
        val ratio = if (StreamingPlugin.isStreamingActive) Rational(16, 9) else Rational(9, 16)
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(ratio)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setAutoEnterEnabled(true)
                }
            }
            .build()
        try {
            enterPictureInPictureMode(params)
        } catch (_: Exception) {

        }
    }
}
