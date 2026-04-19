package com.limelight.jujostream.native_bridge

import android.content.Context
import android.os.Build
import android.util.Log
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Provides a native SurfaceView to Flutter via Hybrid Composition.
 * When enabled, MediaCodec renders directly to this SurfaceView,
 * bypassing the SurfaceTexture GPU copy path. On API 29+ the
 * Android compositor handles composition via SurfaceControl.
 */
class DirectSubmitViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        private const val TAG = "DirectSubmit"
        const val VIEW_TYPE = "com.jujostream/direct_submit_surface"

        @Volatile
        var activeSurface: Surface? = null
            private set

        @Volatile
        private var surfaceLatch = CountDownLatch(1)

        fun awaitSurface(timeoutMs: Long): Surface? {
            if (activeSurface != null) return activeSurface
            surfaceLatch.await(timeoutMs, TimeUnit.MILLISECONDS)
            return activeSurface
        }

        fun reset() {
            activeSurface = null
            surfaceLatch = CountDownLatch(1)
        }
    }

    private var currentView: DirectSubmitPlatformView? = null

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        activeSurface = null
        surfaceLatch = CountDownLatch(1)
        val v = DirectSubmitPlatformView(context)
        currentView = v
        return v
    }

    inner class DirectSubmitPlatformView(context: Context) : PlatformView {
        private val surfaceView = SurfaceView(context)

        init {
            surfaceView.setZOrderOnTop(false)
            surfaceView.holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(holder: SurfaceHolder) {
                    activeSurface = holder.surface
                    surfaceLatch.countDown()
                    Log.i(TAG, "Direct submit surface ready " +
                        "(api=${Build.VERSION.SDK_INT}, " +
                        "hw=${Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q})")
                }

                override fun surfaceChanged(h: SurfaceHolder, fmt: Int, w: Int, ht: Int) {
                    Log.d(TAG, "Surface changed: ${w}x${ht} fmt=$fmt")
                }

                override fun surfaceDestroyed(holder: SurfaceHolder) {
                    Log.i(TAG, "Direct submit surface destroyed")
                    activeSurface = null
                }
            })
        }

        override fun getView(): View = surfaceView

        override fun dispose() {
            activeSurface = null
            surfaceLatch = CountDownLatch(1)
            currentView = null
        }
    }
}
