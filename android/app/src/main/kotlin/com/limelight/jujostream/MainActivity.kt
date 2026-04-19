package com.limelight.jujostream

import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
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
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.decorView.post { killFocusHighlightRecursive(window.decorView) }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)

        window.decorView.post { killFocusHighlightRecursive(window.decorView) }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val streaming = StreamingPlugin.isStreamingActive
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .setAutoEnterEnabled(streaming)
                .build()
            try { setPictureInPictureParams(params) } catch (_: Exception) {}
        }
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
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
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
