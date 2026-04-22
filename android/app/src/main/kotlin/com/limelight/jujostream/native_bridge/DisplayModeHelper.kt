package com.limelight.jujostream.native_bridge

import android.app.Activity
import android.os.Build
import android.util.Log
import android.view.Surface
import android.view.Window
import android.view.WindowManager


object DisplayModeHelper {
    private const val TAG = "DisplayMode"

    private var savedModeId: Int = 0
    private var applied = false

    fun apply(activity: Activity, targetFps: Int, surface: Surface?) {
        if (applied) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            Log.d(TAG, "API < 23, skipping display mode switch")
            return
        }

        try {
            val window = activity.window ?: return
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                activity.display
            } else {
                @Suppress("DEPRECATION")
                window.windowManager.defaultDisplay
            } ?: return

            val currentMode = display.mode
            savedModeId = currentMode.modeId
            val nativeW = currentMode.physicalWidth
            val nativeH = currentMode.physicalHeight

            val candidateModes = display.supportedModes
                .filter { it.physicalWidth == nativeW && it.physicalHeight == nativeH }
                .sortedBy { kotlin.math.abs(it.refreshRate - targetFps.toFloat()) }

            if (candidateModes.isEmpty()) {
                Log.w(TAG, "No compatible display modes found")
                return
            }

            val bestMode = candidateModes.first()
            val delta = kotlin.math.abs(bestMode.refreshRate - targetFps.toFloat())

            if (delta <= 2f && bestMode.modeId != currentMode.modeId) {
                val attrs = window.attributes
                attrs.preferredDisplayModeId = bestMode.modeId
                window.attributes = attrs
                Log.i(TAG, "Switched display mode: ${currentMode.refreshRate}Hz -> " +
                    "${bestMode.refreshRate}Hz (target=${targetFps}fps, modeId=${bestMode.modeId})")
                applied = true
            } else if (bestMode.modeId == currentMode.modeId) {
                Log.d(TAG, "Current mode already optimal: ${currentMode.refreshRate}Hz")
                applied = true
            } else {
                Log.d(TAG, "No mode close enough to ${targetFps}fps " +
                    "(best=${bestMode.refreshRate}Hz, delta=${delta}Hz)")
            }

            // Also set frame rate hint on VRR panels (API 30+)
            applyFrameRateHint(surface, targetFps)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply display mode", e)
        }
    }

    /**
     * On API 30+ use Surface.setFrameRate to hint the compositor.
     * This is non-disruptive and works on both VRR and fixed-rate panels.
     */
    private fun applyFrameRateHint(surface: Surface?, targetFps: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || surface == null) return
        try {
            surface.setFrameRate(
                targetFps.toFloat(),
                Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS
            )
            Log.i(TAG, "Set Surface frame rate hint: ${targetFps}fps (seamless)")
        } catch (e: Exception) {
            Log.w(TAG, "setFrameRate failed: ${e.message}")
        }
    }

    fun restore(activity: Activity?) {
        if (!applied) return
        applied = false

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        try {
            val window = activity?.window ?: return
            val attrs = window.attributes
            if (savedModeId != 0 && attrs.preferredDisplayModeId != savedModeId) {
                attrs.preferredDisplayModeId = savedModeId
                window.attributes = attrs
                Log.i(TAG, "Restored display mode to modeId=$savedModeId")
            }
            savedModeId = 0
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restore display mode", e)
        }
    }
}
