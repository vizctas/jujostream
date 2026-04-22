package com.limelight.jujostream

import android.Manifest
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.content.Intent
import android.provider.Settings
import com.limelight.jujostream.native_bridge.PairingForegroundService
import android.util.Rational
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.limelight.jujostream.native_bridge.GamepadHandler
import com.limelight.jujostream.native_bridge.StreamingPlugin

class MainActivity : FlutterActivity() {
    private var gamepadHandler: GamepadHandler? = null

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1001
    }

    // Pending MethodChannel result for requestNotificationPermission.
    // Set before launching the system dialog, resolved in onRequestPermissionsResult.
    private var pendingPermissionResult: MethodChannel.Result? = null

    // ── Pairing state ────────────────────────────────────────────────────────
    // True while pair() is in-flight. The PairingForegroundService holds the
    // actual WifiLock + WakeLock — they survive Activity pause/stop because
    // they live in the Service, not the Activity.
    private var isPairingActive = false

    /**
     * Requests POST_NOTIFICATIONS permission on Android 13+ (API 33).
     * Without this, the FGS notification is invisible — the service still
     * runs but the user can't see the PIN in the notification shade.
     * Non-blocking: if already granted or pre-API 33, returns immediately.
     */
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST_CODE
                )
            }
        }
    }

    /**
     * Starts the Foreground Service to run the ENTIRE 5-phase pairing
     * handshake natively. All phases execute in a Java thread that survives
     * Dart VM pause — critical for same-device pairing where the user
     * backgrounds JUJO to enter the PIN in Chrome.
     */
    private fun startFullNativePairing(
        baseUrl: String,
        httpsPort: Int,
        uniqueId: String,
        pin: String,
        certPem: String,
        keyPem: String,
        timeoutMs: Long
    ) {
        isPairingActive = true
        PairingForegroundService.reset()

        try {
            val intent = Intent(this, PairingForegroundService::class.java).apply {
                putExtra("mode", "fullPairing")
                putExtra("baseUrl", baseUrl)
                putExtra("httpsPort", httpsPort)
                putExtra("uniqueId", uniqueId)
                putExtra("pin", pin)
                putExtra("certPem", certPem)
                putExtra("keyPem", keyPem)
                putExtra("timeoutMs", timeoutMs)
            }
            android.util.Log.i("PairingFGS", "Starting PairingForegroundService with mode=fullPairing")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            android.util.Log.i("PairingFGS", "PairingForegroundService started successfully")
        } catch (e: Exception) {
            android.util.Log.e("PairingFGS", "FAILED to start PairingForegroundService: $e", e)
            // Store error so Dart can detect the failure immediately
            PairingForegroundService.pairingResult.set(
                com.limelight.jujostream.native_bridge.NativePairingResult(
                    paired = false,
                    error = "Failed to start pairing service: ${e.message}"
                )
            )
        }
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
     * Returns the full pairing result as a Map, or null if still in progress.
     */
    private fun pollPairingResult(): Map<String, Any?>? {
        val result = PairingForegroundService.pairingResult.get() ?: return null
        return mapOf(
            "paired" to result.paired,
            "serverCertHex" to result.serverCertHex,
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
                    "startFullPairing" -> {
                        val baseUrl = call.argument<String>("baseUrl") ?: ""
                        val httpsPort = call.argument<Number>("httpsPort")?.toInt() ?: 47984
                        val uniqueId = call.argument<String>("uniqueId") ?: ""
                        val pin = call.argument<String>("pin") ?: ""
                        val certPem = call.argument<String>("certPem") ?: ""
                        val keyPem = call.argument<String>("keyPem") ?: ""
                        val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: 120_000L
                        startFullNativePairing(baseUrl, httpsPort, uniqueId, pin, certPem, keyPem, timeoutMs)
                        result.success(null)
                    }
                    "pollResult" -> {
                        result.success(pollPairingResult())
                    }
                    "release" -> {
                        releasePairingLocks()
                        result.success(null)
                    }
                    "checkNotificationPermission" -> {
                        // Returns "granted", "denied", or "not_required" (pre-API 33)
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            result.success("not_required")
                        } else {
                            val granted = ContextCompat.checkSelfPermission(
                                this, Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED
                            result.success(if (granted) "granted" else "denied")
                        }
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            result.success("not_required")
                        } else if (ContextCompat.checkSelfPermission(
                                this, Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success("granted")
                        } else {
                            // Store the result to resolve in onRequestPermissionsResult
                            pendingPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                NOTIFICATION_PERMISSION_REQUEST_CODE
                            )
                        }
                    }
                    "openNotificationSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Fallback: open general app settings
                            try {
                                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.fromParts("package", packageName, null)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Request notification permission early so the FGS notification is
        // visible when pairing starts. On Android 12 and below this is a no-op.
        ensureNotificationPermission()

        window.decorView.post { killFocusHighlightRecursive(window.decorView) }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(if (granted) "granted" else "denied")
            pendingPermissionResult = null
        }
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
