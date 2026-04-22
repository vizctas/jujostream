package com.limelight.jujostream

import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
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

    // ── Pairing network locks ────────────────────────────────────────────────
    // Acquired during Phase 1 (getservercert) to prevent Android from
    // throttling the CPU or killing the WiFi socket when the user switches
    // to Chrome to enter the pairing PIN.
    private var pairingWifiLock: WifiManager.WifiLock? = null
    private var pairingWakeLock: PowerManager.WakeLock? = null

    // True while pair() is in-flight. Allows tryEnterPip() to fire during
    // pairing so the app stays "foreground-visible" in a PiP window, which:
    //  1. Keeps WifiLock FULL_LOW_LATENCY effective (requires foreground)
    //  2. Prevents Android from killing the TCP socket on background
    //  3. Shows the PIN in a floating window while the user types in Chrome
    private var isPairingActive = false

    private fun acquirePairingLocks() {
        isPairingActive = true
        refreshPipParams() // re-register autoEnterEnabled=true for pairing

        // PARTIAL_WAKE_LOCK: keeps CPU active → Dart event loop processes
        // the HTTP response even if the screen turns off.
        runCatching {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            pairingWakeLock?.let { if (it.isHeld) it.release() }
            pairingWakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "jujostream:pairing"
            ).also { it.acquire(130_000L) } // 120s timeout + 10s margin
        }
        // WifiLock: always use HIGH_PERF.
        // FULL_LOW_LATENCY only works when the app is in the foreground — but
        // we enter PiP on background so the app IS foreground. However, use
        // HIGH_PERF as the safer fallback: it works even when fully backgrounded
        // (e.g., user dismisses PiP) and keeps the WiFi radio from sleeping.
        runCatching {
            val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            pairingWifiLock?.let { if (it.isHeld) it.release() }
            @Suppress("DEPRECATION")
            pairingWifiLock = wm.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "jujostream:pairing"
            ).also { it.acquire() }
        }
    }

    private fun releasePairingLocks() {
        isPairingActive = false
        refreshPipParams() // re-register autoEnterEnabled=false after pairing
        runCatching { pairingWifiLock?.let { if (it.isHeld) it.release() } }
        runCatching { pairingWakeLock?.let { if (it.isHeld) it.release() } }
        pairingWifiLock = null
        pairingWakeLock = null
    }

    // Updates the PiP parameters so Android knows when auto-enter is allowed.
    // Must be called whenever streaming/pairing state changes.
    private fun refreshPipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val active = StreamingPlugin.isStreamingActive || isPairingActive
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
                    "acquire" -> { acquirePairingLocks(); result.success(null) }
                    "release" -> { releasePairingLocks(); result.success(null) }
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
        if (!StreamingPlugin.isStreamingActive && !isPairingActive) return
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
