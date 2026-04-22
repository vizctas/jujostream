package com.limelight.jujostream.native_bridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.vizcorp.moonlight_jujo_stream.R
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Foreground Service that:
 *   1. Holds WifiLock + WakeLock during pairing
 *   2. Executes Phase 1 HTTP long-poll NATIVELY (survives Dart VM pause)
 *
 * WHY NATIVE HTTP:
 *   When Flutter goes to background, the Dart isolate is paused by Android.
 *   Any in-flight Dart http.Client request freezes → TCP socket times out.
 *   By running the Phase 1 long-poll in a native Java thread inside this
 *   Foreground Service, the HTTP connection survives app backgrounding.
 *
 * LIFECYCLE:
 *   Flutter "acquireAndPoll" → starts service + begins Phase 1 HTTP GET
 *   Server responds (user entered PIN) → result stored in AtomicReference
 *   Flutter "pollResult" → retrieves the result (or null if still waiting)
 *   Flutter "release" → stops service, releases locks
 */
class PairingForegroundService : Service() {

    companion object {
        private const val TAG = "PairingFGS"
        private const val CHANNEL_ID = "pairing_channel"
        private const val NOTIFICATION_ID = 1001
        private const val LOCK_TIMEOUT_MS = 310_000L // 5 min + margin

        // Phase 1 result — read by Flutter via MethodChannel "pollResult"
        val phase1Result = AtomicReference<Phase1Result?>(null)
        val phase1InProgress = AtomicBoolean(false)

        // Cancel flag — set by Flutter via MethodChannel "cancel"
        val cancelRequested = AtomicBoolean(false)

        fun reset() {
            phase1Result.set(null)
            phase1InProgress.set(false)
            cancelRequested.set(false)
        }
    }

    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var pollingThread: Thread? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        acquireLocks()

        // Start Phase 1 HTTP long-poll if URL was provided
        val phase1Url = intent?.getStringExtra("phase1Url")
        val timeoutMs = intent?.getLongExtra("timeoutMs", 120_000L) ?: 120_000L
        if (phase1Url != null && !phase1InProgress.get()) {
            startPhase1Poll(phase1Url, timeoutMs)
        }

        Log.i(TAG, "Foreground service started — locks acquired, phase1Url=${phase1Url != null}")
        return START_STICKY
    }

    override fun onDestroy() {
        cancelRequested.set(true)
        pollingThread?.interrupt()
        pollingThread = null
        releaseLocks()
        Log.i(TAG, "Foreground service destroyed — locks released")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Phase 1 Native HTTP Long-Poll ────────────────────────────────────────

    private fun startPhase1Poll(url: String, timeoutMs: Long) {
        reset()
        phase1InProgress.set(true)

        pollingThread = Thread {
            try {
                Log.i(TAG, "Phase 1 native poll started: $url (timeout=${timeoutMs}ms)")
                val conn = URL(url).openConnection() as HttpURLConnection
                conn.requestMethod = "GET"
                conn.connectTimeout = 15_000 // 15s connect timeout
                conn.readTimeout = timeoutMs.toInt() // long-poll read timeout
                conn.setRequestProperty("Connection", "close")

                try {
                    val responseCode = conn.responseCode
                    val body = if (responseCode in 200..299) {
                        conn.inputStream.bufferedReader().use { it.readText() }
                    } else {
                        conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                    }

                    if (cancelRequested.get()) {
                        Log.i(TAG, "Phase 1 completed but cancel was requested — discarding")
                        phase1Result.set(Phase1Result(
                            success = false,
                            error = "cancelled",
                            statusCode = responseCode,
                            body = body
                        ))
                    } else {
                        Log.i(TAG, "Phase 1 completed: HTTP $responseCode, body=${body.take(200)}")
                        phase1Result.set(Phase1Result(
                            success = responseCode in 200..299,
                            statusCode = responseCode,
                            body = body,
                            error = null
                        ))
                    }
                } finally {
                    conn.disconnect()
                }
            } catch (e: InterruptedException) {
                Log.i(TAG, "Phase 1 interrupted (service stopping)")
                phase1Result.set(Phase1Result(
                    success = false,
                    error = "interrupted"
                ))
            } catch (e: java.net.SocketTimeoutException) {
                Log.w(TAG, "Phase 1 timed out: $e")
                phase1Result.set(Phase1Result(
                    success = false,
                    error = "timeout: ${e.message}"
                ))
            } catch (e: Exception) {
                Log.e(TAG, "Phase 1 error: $e")
                phase1Result.set(Phase1Result(
                    success = false,
                    error = "error: ${e.message}"
                ))
            } finally {
                phase1InProgress.set(false)
            }
        }.apply {
            name = "PairingPhase1Poll"
            isDaemon = true
            start()
        }
    }

    // ── Lock Management ──────────────────────────────────────────────────────

    private fun acquireLocks() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "jujostream:pairing_fgs"
            ).apply {
                acquire(LOCK_TIMEOUT_MS)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire WakeLock: $e")
        }

        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wifiLock?.let { if (it.isHeld) it.release() }
            @Suppress("DEPRECATION")
            wifiLock = wm.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "jujostream:pairing_fgs"
            ).apply {
                acquire()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire WifiLock: $e")
        }
    }

    private fun releaseLocks() {
        try { wakeLock?.let { if (it.isHeld) it.release() } }
        catch (e: Exception) { Log.e(TAG, "Error releasing WakeLock: $e") }
        wakeLock = null

        try { wifiLock?.let { if (it.isHeld) it.release() } }
        catch (e: Exception) { Log.e(TAG, "Error releasing WifiLock: $e") }
        wifiLock = null
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Pairing Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps connection alive during PC pairing"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Pairing in Progress")
            .setContentText("Keeping connection alive…")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }
}

/** Result of the native Phase 1 HTTP long-poll. */
data class Phase1Result(
    val success: Boolean,
    val statusCode: Int = -1,
    val body: String = "",
    val error: String? = null
)
