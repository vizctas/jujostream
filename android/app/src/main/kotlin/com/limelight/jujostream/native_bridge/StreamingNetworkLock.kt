package com.limelight.jujostream.native_bridge

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log

internal enum class StreamingWifiMode {
    LOW_LATENCY,
    HIGH_PERFORMANCE,
}

internal object StreamingWifiModePolicy {
    fun forSdk(sdk: Int): StreamingWifiMode =
        if (sdk >= Build.VERSION_CODES.Q) {
            StreamingWifiMode.LOW_LATENCY
        } else {
            StreamingWifiMode.HIGH_PERFORMANCE
        }
}

/** Keeps Android Wi-Fi power saving out of an active interactive stream. */
internal class StreamingNetworkLock(context: Context) {
    companion object {
        private const val TAG = "StreamingNetworkLock"
        private const val LOCK_TAG = "jujostream:stream_transport"
    }

    private val wifiManager =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private var wifiLock: WifiManager.WifiLock? = null

    @Synchronized
    fun acquire() {
        if (wifiLock?.isHeld == true) return

        try {
            @Suppress("DEPRECATION")
            val mode = when (StreamingWifiModePolicy.forSdk(Build.VERSION.SDK_INT)) {
                StreamingWifiMode.LOW_LATENCY -> WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                StreamingWifiMode.HIGH_PERFORMANCE -> WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            @Suppress("DEPRECATION")
            wifiLock = wifiManager.createWifiLock(mode, LOCK_TAG).apply {
                setReferenceCounted(false)
                acquire()
            }
            Log.i(TAG, "Acquired session Wi-Fi lock (${StreamingWifiModePolicy.forSdk(Build.VERSION.SDK_INT)})")
        } catch (error: RuntimeException) {
            wifiLock = null
            Log.w(TAG, "Unable to acquire session Wi-Fi lock", error)
        }
    }

    @Synchronized
    fun release() {
        val lock = wifiLock ?: return
        try {
            if (lock.isHeld) lock.release()
        } catch (error: RuntimeException) {
            Log.w(TAG, "Unable to release session Wi-Fi lock", error)
        } finally {
            wifiLock = null
        }
    }
}
