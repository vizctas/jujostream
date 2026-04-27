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
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.interfaces.RSAPrivateKey
import java.security.spec.PKCS8EncodedKeySpec
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager


class PairingForegroundService : Service() {

    companion object {
        private const val TAG = "PairingFGS"

        private const val CHANNEL_ID = "pairing_pin_channel"
        private const val NOTIFICATION_ID = 1001
        private const val LOCK_TIMEOUT_MS = 310_000L // 5 min + margin

        val pairingResult = AtomicReference<NativePairingResult?>(null)
        val pairingInProgress = AtomicBoolean(false)

        val cancelRequested = AtomicBoolean(false)

        fun reset() {
            pairingResult.set(null)
            pairingInProgress.set(false)
            cancelRequested.set(false)
        }
    }

    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var pairingThread: Thread? = null

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

        val mode = intent?.getStringExtra("mode")
        if (mode == "fullPairing" && !pairingInProgress.get()) {
            val baseUrl = intent.getStringExtra("baseUrl") ?: ""
            val httpsPort = intent.getIntExtra("httpsPort", 47984)
            val uniqueId = intent.getStringExtra("uniqueId") ?: ""
            val pin = intent.getStringExtra("pin") ?: ""
            val certPem = intent.getStringExtra("certPem") ?: ""
            val keyPem = intent.getStringExtra("keyPem") ?: ""
            val timeoutMs = intent.getLongExtra("timeoutMs", 120_000L)

            if (baseUrl.isNotEmpty() && uniqueId.isNotEmpty() && pin.isNotEmpty()) {
                // Update notification to show the PIN so the user can see it
                // from the notification shade while in Chrome.
                updateNotificationWithPin(pin)
                startFullPairing(baseUrl, httpsPort, uniqueId, pin, certPem, keyPem, timeoutMs)
            } else {
                Log.e(TAG, "Missing required pairing parameters")
                pairingResult.set(NativePairingResult(
                    paired = false,
                    error = "Missing required pairing parameters"
                ))
            }
        }

        Log.i(TAG, "Foreground service started — locks acquired, mode=$mode")
        return START_STICKY
    }

    override fun onDestroy() {
        cancelRequested.set(true)
        pairingThread?.interrupt()
        pairingThread = null
        releaseLocks()
        Log.i(TAG, "Foreground service destroyed — locks released")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startFullPairing(
        baseUrl: String,
        httpsPort: Int,
        uniqueId: String,
        pin: String,
        certPem: String,
        keyPem: String,
        timeoutMs: Long
    ) {
        reset()
        pairingInProgress.set(true)

        pairingThread = Thread {
            try {
                val result = runFullPairingHandshake(
                    baseUrl, httpsPort, uniqueId, pin, certPem, keyPem, timeoutMs
                )
                pairingResult.set(result)
            } catch (e: InterruptedException) {
                Log.i(TAG, "Pairing interrupted (service stopping)")
                pairingResult.set(NativePairingResult(paired = false, error = "interrupted"))
            } catch (e: Exception) {
                Log.e(TAG, "Pairing error: $e", e)
                pairingResult.set(NativePairingResult(paired = false, error = "error: ${e.message}"))
            } finally {
                pairingInProgress.set(false)
            }
        }.apply {
            name = "PairingFullHandshake"
            isDaemon = true
            start()
        }
    }

    /**
     * Executes the complete Moonlight/Sunshine 5-phase pairing protocol natively.
     *
     * This is a direct port of PairingService.pair() from Dart, running entirely
     * in a Java thread that survives Dart VM pause.
     */
    private fun runFullPairingHandshake(
        baseUrl: String,
        httpsPort: Int,
        uniqueId: String,
        pin: String,
        certPem: String,
        keyPem: String,
        timeoutMs: Long
    ): NativePairingResult {
        Log.i(TAG, "Starting full native pairing handshake")

        val clientPrivateKey = parsePkcs8PrivateKey(keyPem)
        val clientCertPemBytes = certPem.toByteArray(Charsets.UTF_8)
        val clientCertSignature = extractX509Signature(certPem)

        Log.d(TAG, "Client cert PEM bytes length: ${clientCertPemBytes.size}")
        Log.d(TAG, "Client cert signature length: ${clientCertSignature.size}")
        Log.d(TAG, "Client cert sig first 8 bytes: ${bytesToHex(clientCertSignature.take(8).toByteArray())}")

       
        try {
            httpGet("$baseUrl/unpair?uniqueid=$uniqueId", connectTimeout = 4000, readTimeout = 4000)
        } catch (_: Exception) {}
        Thread.sleep(1500)

        val salt = randomBytes(16)
        val aesKey = deriveAesKey(salt, pin)

        val phase1Url = "$baseUrl/pair" +
                "?uniqueid=$uniqueId" +
                "&devicename=Jujostream+Flutter" +
                "&updateState=1" +
                "&phrase=getservercert" +
                "&salt=${bytesToHex(salt)}" +
                "&clientcert=${bytesToHex(clientCertPemBytes)}"

        Log.i(TAG, "Phase 1: getservercert (waiting for user to enter PIN)...")

        var phase1Xml: String? = null
        var phase1Accepted = false

        // Outer: 0 = normal attempt, 1 = self-heal (unpair + retry on rejection)
        for (selfHeal in 0..1) {
            if (phase1Accepted) break
            if (cancelRequested.get()) return NativePairingResult(paired = false, error = "cancelled")

            if (selfHeal == 1) {
                Log.w(TAG, "Phase 1 rejected. Self-healing: unpair + retry.")
                try {
                    httpGet("$baseUrl/unpair?uniqueid=$uniqueId", connectTimeout = 5000, readTimeout = 5000)
                } catch (_: Exception) {}
                Thread.sleep(2500)
            }

            for (attempt in 0..3) {
                if (cancelRequested.get()) return NativePairingResult(paired = false, error = "cancelled")
                try {
                    val body = httpGet(
                        phase1Url,
                        connectTimeout = 15_000,
                        readTimeout = timeoutMs.toInt()
                    )
                    phase1Xml = body

                    if (extractXmlValue(body, "paired") == "1") {
                        phase1Accepted = true
                        break
                    }

                    Log.w(TAG, "Phase 1 returned paired=0 on attempt ${attempt + 1} (selfHeal=$selfHeal)")
                    break // break inner loop, try self-heal
                } catch (e: java.net.SocketTimeoutException) {
                    Log.w(TAG, "Phase 1 attempt ${attempt + 1}/4 timed out: $e")
                    if (attempt == 3) return NativePairingResult(paired = false, error = "Phase 1 timed out")
                } catch (e: Exception) {
                    val msg = e.message?.lowercase() ?: ""
                    val isSocketErr = msg.contains("connection abort") ||
                            msg.contains("software caused") ||
                            msg.contains("connection reset") ||
                            msg.contains("connection refused") ||
                            msg.contains("connection closed") ||
                            msg.contains("broken pipe")
                    if (isSocketErr && attempt < 3) {
                        Log.w(TAG, "Phase 1 socket error attempt ${attempt + 1}/4: $e. Retrying in 2s...")
                        Thread.sleep(2000)
                        continue
                    }
                    throw e
                }
            }
        }

        if (!phase1Accepted || phase1Xml == null) {
            return NativePairingResult(paired = false, error = "Server rejected pairing request")
        }

        val serverCertHex = extractXmlValue(phase1Xml, "plaincert") ?: ""
        if (serverCertHex.isEmpty()) {
            try {
                httpGet("$baseUrl/unpair?uniqueid=$uniqueId", connectTimeout = 5000, readTimeout = 5000)
            } catch (_: Exception) {}
            return NativePairingResult(
                paired = false,
                error = "No server certificate returned (pairing already in progress?)"
            )
        }

        val serverCertPemBytes = hexToBytes(serverCertHex)
        val serverCertPemString = String(serverCertPemBytes, Charsets.UTF_8)
        val serverCertSignature = extractX509Signature(serverCertPemString)

        Log.i(TAG, "Phase 1 complete — server cert received. Running Phases 2-5 immediately.")
        Log.d(TAG, "Server cert signature length: ${serverCertSignature.size}")
        Log.d(TAG, "Server cert sig first 8 bytes: ${bytesToHex(serverCertSignature.take(8).toByteArray())}")
        Log.d(TAG, "AES key: ${bytesToHex(aesKey)}")
        Log.d(TAG, "Salt: ${bytesToHex(salt)}")

        if (cancelRequested.get()) return NativePairingResult(paired = false, error = "cancelled")

        val clientChallenge = randomBytes(16)
        val encryptedChallenge = aesEcbEncrypt(clientChallenge, aesKey)

        val phase2Url = "$baseUrl/pair" +
                "?uniqueid=$uniqueId" +
                "&devicename=Jujostream+Flutter" +
                "&updateState=1" +
                "&clientchallenge=${bytesToHex(encryptedChallenge)}"

        Log.i(TAG, "Phase 2: sending client challenge")
        Log.d(TAG, "Phase 2 encrypted challenge hex: ${bytesToHex(encryptedChallenge)}")
        val phase2Body = httpGetWithRetry("Phase 2", phase2Url)
        Log.d(TAG, "Phase 2 response (first 300): ${phase2Body.take(300)}")

        if (extractXmlValue(phase2Body, "paired") != "1") {
            return NativePairingResult(paired = false, error = "Server rejected challenge (wrong PIN?)")
        }

        val serverChallengeHex = extractXmlValue(phase2Body, "challengeresponse") ?: ""
        if (serverChallengeHex.isEmpty()) {
            return NativePairingResult(paired = false, error = "No challenge response from server")
        }

        val serverChallengeResponse = aesEcbDecrypt(hexToBytes(serverChallengeHex), aesKey)
        if (serverChallengeResponse.size < 48) {
            return NativePairingResult(paired = false, error = "Malformed challenge response from server")
        }

        val serverResponse = serverChallengeResponse.sliceArray(0 until 32)
        val serverChallenge = serverChallengeResponse.sliceArray(32 until 48)

        if (cancelRequested.get()) return NativePairingResult(paired = false, error = "cancelled")

        val clientSecret = randomBytes(16)
        val clientHash = sha256(serverChallenge + clientCertSignature + clientSecret)
        val encryptedClientHash = aesEcbEncrypt(clientHash, aesKey)

        val phase3Url = "$baseUrl/pair" +
                "?uniqueid=$uniqueId" +
                "&devicename=Jujostream+Flutter" +
                "&updateState=1" +
                "&serverchallengeresp=${bytesToHex(encryptedClientHash)}"

        Log.i(TAG, "Phase 3: sending server challenge response")
        val phase3Body = httpGetWithRetry("Phase 3", phase3Url)

        if (extractXmlValue(phase3Body, "paired") != "1") {
            return NativePairingResult(paired = false, error = "Server rejected secret (wrong PIN?)")
        }

        val pairingSecretHex = extractXmlValue(phase3Body, "pairingsecret") ?: ""
        if (pairingSecretHex.isEmpty()) {
            return NativePairingResult(paired = false, error = "No pairing secret from server")
        }

        val pairingSecret = hexToBytes(pairingSecretHex)
        if (pairingSecret.size <= 16) {
            return NativePairingResult(paired = false, error = "Invalid pairing secret from server")
        }

        val serverSecret = pairingSecret.sliceArray(0 until 16)
        val expectedServerResponse = sha256(clientChallenge + serverCertSignature + serverSecret)
        if (!constantTimeEquals(serverResponse, expectedServerResponse)) {
            return NativePairingResult(paired = false, error = "PIN incorrect or pairing state invalid")
        }

        if (cancelRequested.get()) return NativePairingResult(paired = false, error = "cancelled")

        val clientSignature = signSha256Rsa(clientSecret, clientPrivateKey)
        val clientPairingSecret = clientSecret + clientSignature

        val phase4Url = "$baseUrl/pair" +
                "?uniqueid=$uniqueId" +
                "&devicename=Jujostream+Flutter" +
                "&updateState=1" +
                "&clientpairingsecret=${bytesToHex(clientPairingSecret)}"

        Log.i(TAG, "Phase 4: sending client pairing secret")
        val phase4Body = httpGetWithRetry("Phase 4", phase4Url)

        if (extractXmlValue(phase4Body, "paired") != "1") {
            return NativePairingResult(paired = false, error = "Server rejected client pairing secret")
        }

        if (cancelRequested.get()) return NativePairingResult(paired = false, error = "cancelled")

        val address = baseUrl.removePrefix("http://").substringBefore(":")
        val httpsBaseUrl = "https://$address:$httpsPort"

        val httpsPairChallengeUrl = "$httpsBaseUrl/pair" +
                "?uniqueid=$uniqueId" +
                "&devicename=Jujostream+Flutter" +
                "&updateState=1" +
                "&phrase=pairchallenge"
        val httpPairChallengeUrl = "$baseUrl/pair" +
                "?uniqueid=$uniqueId" +
                "&devicename=Jujostream+Flutter" +
                "&updateState=1" +
                "&phrase=pairchallenge"

        var phase5Completed = false

        Log.i(TAG, "Phase 5 (HTTPS): pairchallenge")
        try {
            val body = httpsGetWithClientCert(httpsPairChallengeUrl, certPem, keyPem, 5000, serverCertPemString)
            if (extractXmlValue(body, "paired") == "1") {
                phase5Completed = true
            } else {
                Log.w(TAG, "Phase 5 HTTPS pairchallenge not accepted")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Phase 5 HTTPS pairchallenge failed: $e")
        }

        if (!phase5Completed) {
            Log.i(TAG, "Phase 5 fallback (HTTP): pairchallenge")
            try {
                val body = httpGet(httpPairChallengeUrl, connectTimeout = 5000, readTimeout = 5000)
                if (extractXmlValue(body, "paired") == "1") {
                    phase5Completed = true
                }
            } catch (e: Exception) {
                Log.w(TAG, "Phase 5 HTTP pairchallenge failed: $e")
            }
        }

        if (!phase5Completed) {
            Log.w(TAG, "Phase 5 challenge failed, verifying via HTTPS serverinfo")
            try {
                val serverInfoUrl = "$httpsBaseUrl/serverinfo?uniqueid=$uniqueId"
                val body = httpsGetWithClientCert(serverInfoUrl, certPem, keyPem, 5000, serverCertPemString)
                val pairStatus = extractXmlValue(body, "PairStatus")
                if (pairStatus == "1") {
                    phase5Completed = true
                } else if (pairStatus == "0") {
                    Log.e(TAG, "Phase 5: server returned PairStatus=0 — pairing explicitly rejected")
                    return NativePairingResult(
                        paired = false,
                        error = "Server rejected pairing after handshake"
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "Phase 5 serverinfo verification failed: $e")
            }
        }

        if (!phase5Completed) {
            Log.w(TAG, "Phase 5 unconfirmed (network only); accepting because Phase 4 completed")
        }

        Log.i(TAG, "Pairing successful!")
        return NativePairingResult(paired = true, serverCertHex = serverCertHex)
    }

    private fun httpGet(url: String, connectTimeout: Int = 15_000, readTimeout: Int = 60_000): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = connectTimeout
        conn.readTimeout = readTimeout
        conn.setRequestProperty("Connection", "close")
        try {
            val code = conn.responseCode
            val body = if (code in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
            }
            if (code !in 200..299) {
                throw Exception("HTTP $code: $body")
            }
            return body
        } finally {
            conn.disconnect()
        }
    }

    private fun httpGetWithRetry(
        phaseName: String,
        url: String,
        maxDurationMs: Long = 60_000
    ): String {
        val startTime = System.currentTimeMillis()
        while (true) {
            if (cancelRequested.get()) throw InterruptedException("$phaseName cancelled")

            val elapsed = System.currentTimeMillis() - startTime
            val remaining = maxDurationMs - elapsed
            if (remaining <= 0) throw Exception("$phaseName timed out")

            try {
                return httpGet(url, readTimeout = remaining.toInt().coerceAtMost(60_000))
            } catch (e: java.net.SocketTimeoutException) {
                throw Exception("$phaseName timed out: ${e.message}")
            } catch (e: Exception) {
                if (e is InterruptedException) throw e
                val msg = e.message?.lowercase() ?: ""
                val isSocketErr = msg.contains("connection abort") ||
                        msg.contains("software caused") ||
                        msg.contains("connection reset") ||
                        msg.contains("connection refused") ||
                        msg.contains("connection closed") ||
                        msg.contains("broken pipe")
                if (isSocketErr) {
                    Log.w(TAG, "$phaseName socket dropped: $e. Retrying in 1s...")
                    Thread.sleep(1000)
                    continue
                }
                throw e
            }
        }
    }

    /**
     * Performs an HTTPS GET using the client certificate for mutual TLS,
     * pinning trust to the server certificate obtained during Phase 1.
     *
     * This avoids an unsafe "trust-all" TrustManager (Play Store policy
     * violation) by only accepting the exact server certificate we already
     * received and validated during the pairing handshake.
     */
    private fun httpsGetWithClientCert(
        url: String,
        certPem: String,
        keyPem: String,
        timeoutMs: Int,
        pinnedServerCertPem: String? = null
    ): String {
        // --- TrustManager: pin to the known server certificate ----------
        val trustManagers: Array<TrustManager> = if (pinnedServerCertPem != null) {
            // Build a TrustStore containing only the server cert from Phase 1
            val certFactory = CertificateFactory.getInstance("X.509")
            val serverCert = certFactory.generateCertificate(
                ByteArrayInputStream(pinnedServerCertPem.toByteArray(Charsets.UTF_8))
            ) as X509Certificate

            val trustStore = java.security.KeyStore.getInstance(java.security.KeyStore.getDefaultType())
            trustStore.load(null, null)
            trustStore.setCertificateEntry("pinnedServer", serverCert)

            val tmf = javax.net.ssl.TrustManagerFactory.getInstance(
                javax.net.ssl.TrustManagerFactory.getDefaultAlgorithm()
            )
            tmf.init(trustStore)
            tmf.trustManagers
        } else {
            // Fallback: use system default trust store (public CAs).
            // This path is only hit if we somehow lack the server cert,
            // and will correctly reject untrusted certificates.
            val tmf = javax.net.ssl.TrustManagerFactory.getInstance(
                javax.net.ssl.TrustManagerFactory.getDefaultAlgorithm()
            )
            tmf.init(null as java.security.KeyStore?)
            tmf.trustManagers
        }

        // --- KeyManager: client cert + key for mutual TLS ---------------
        val keyStore = java.security.KeyStore.getInstance("PKCS12")
        keyStore.load(null, null)

        val privateKey = parsePkcs8PrivateKey(keyPem)
        val certFactory = CertificateFactory.getInstance("X.509")
        val cert = certFactory.generateCertificate(
            ByteArrayInputStream(certPem.toByteArray(Charsets.UTF_8))
        ) as X509Certificate
        keyStore.setKeyEntry("client", privateKey, charArrayOf(), arrayOf(cert))

        val kmf = javax.net.ssl.KeyManagerFactory.getInstance(
            javax.net.ssl.KeyManagerFactory.getDefaultAlgorithm()
        )
        kmf.init(keyStore, charArrayOf())

        // --- SSLContext with pinned trust + client identity --------------
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(kmf.keyManagers, trustManagers, java.security.SecureRandom())

        val conn = URL(url).openConnection() as HttpsURLConnection
        conn.sslSocketFactory = sslContext.socketFactory
        // Hostname verification is relaxed because the self-signed server
        // cert's CN/SAN won't match the LAN IP. Trust is established via
        // certificate pinning above, not hostname matching.
        conn.hostnameVerifier = javax.net.ssl.HostnameVerifier { _, session ->
            if (pinnedServerCertPem == null) return@HostnameVerifier false
            try {
                val peerCerts = session.peerCertificates
                if (peerCerts.isNullOrEmpty()) return@HostnameVerifier false
                val peerCert = peerCerts[0] as X509Certificate
                val cf = CertificateFactory.getInstance("X.509")
                val expected = cf.generateCertificate(
                    ByteArrayInputStream(pinnedServerCertPem.toByteArray(Charsets.UTF_8))
                ) as X509Certificate
                peerCert.encoded.contentEquals(expected.encoded)
            } catch (e: Exception) {
                Log.w(TAG, "Hostname verifier cert comparison failed: $e")
                false
            }
        }
        conn.connectTimeout = timeoutMs
        conn.readTimeout = timeoutMs
        conn.setRequestProperty("Connection", "close")

        try {
            val code = conn.responseCode
            return if (code in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
            }
        } finally {
            conn.disconnect()
        }
    }

    private fun randomBytes(length: Int): ByteArray {
        val bytes = ByteArray(length)
        java.security.SecureRandom().nextBytes(bytes)
        return bytes
    }

    private fun sha256(data: ByteArray): ByteArray {
        return MessageDigest.getInstance("SHA-256").digest(data)
    }

    private fun deriveAesKey(salt: ByteArray, pin: String): ByteArray {
        val pinBytes = pin.toByteArray(Charsets.UTF_8)
        val combined = salt + pinBytes
        val hash = sha256(combined)
        return hash.sliceArray(0 until 16)
    }

    private fun aesEcbEncrypt(data: ByteArray, key: ByteArray): ByteArray {
        return aesEcbTransform(data, key, Cipher.ENCRYPT_MODE)
    }

    private fun aesEcbDecrypt(data: ByteArray, key: ByteArray): ByteArray {
        return aesEcbTransform(data, key, Cipher.DECRYPT_MODE)
    }

    private fun aesEcbTransform(data: ByteArray, key: ByteArray, mode: Int): ByteArray {
        val cipher = Cipher.getInstance("AES/ECB/NoPadding")
        cipher.init(mode, SecretKeySpec(key, "AES"))
        // Pad to block size (16 bytes)
        val blockSize = 16
        val roundedSize = ((data.size + blockSize - 1) / blockSize) * blockSize
        val input = ByteArray(roundedSize)
        System.arraycopy(data, 0, input, 0, data.size)
        return cipher.doFinal(input)
    }

    private fun signSha256Rsa(data: ByteArray, privateKey: RSAPrivateKey): ByteArray {
        val sig = Signature.getInstance("SHA256withRSA")
        sig.initSign(privateKey)
        sig.update(data)
        return sig.sign()
    }

    private fun parsePkcs8PrivateKey(pem: String): RSAPrivateKey {
        val base64 = pem
            .replace("\r", "")
            .split("\n")
            .filter { !it.startsWith("-----") && it.trim().isNotEmpty() }
            .joinToString("")
        val der = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
        val keySpec = PKCS8EncodedKeySpec(der)
        val keyFactory = KeyFactory.getInstance("RSA")
        return keyFactory.generatePrivate(keySpec) as RSAPrivateKey
    }

    private data class DerElement(val tag: Int, val contentOffset: Int, val contentLength: Int, val totalLength: Int)

    private fun readDerElement(data: ByteArray, offset: Int): DerElement {
        val tag = data[offset].toInt() and 0xFF
        val firstLenByte = data[offset + 1].toInt() and 0xFF

        val contentLength: Int
        val lengthBytes: Int

        if ((firstLenByte and 0x80) == 0) {
            contentLength = firstLenByte
            lengthBytes = 1
        } else {
            val byteCount = firstLenByte and 0x7F
            var len = 0
            for (i in 0 until byteCount) {
                len = (len shl 8) or (data[offset + 2 + i].toInt() and 0xFF)
            }
            contentLength = len
            lengthBytes = 1 + byteCount
        }

        val headerLength = 1 + lengthBytes
        val totalLength = headerLength + contentLength
        return DerElement(tag, offset + headerLength, contentLength, totalLength)
    }

    private fun extractX509Signature(certPem: String): ByteArray {
        try {
            val base64 = certPem
                .replace("\r", "")
                .split("\n")
                .filter { !it.startsWith("-----") && it.trim().isNotEmpty() }
                .joinToString("")
            val der = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)

            // Parse the outer SEQUENCE
            val outer = readDerElement(der, 0)
            var cursor = outer.contentOffset

            // Skip tbsCertificate
            val tbs = readDerElement(der, cursor)
            cursor += tbs.totalLength

            // Skip signatureAlgorithm
            val sigAlg = readDerElement(der, cursor)
            cursor += sigAlg.totalLength

            // Read signatureValue (BIT STRING)
            val sigVal = readDerElement(der, cursor)
            if (sigVal.tag != 0x03 || sigVal.contentLength <= 1) return ByteArray(0)

            // Skip the first byte (unused bits count) of the BIT STRING
            return der.sliceArray((sigVal.contentOffset + 1) until (sigVal.contentOffset + sigVal.contentLength))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to extract X509 signature: $e")
            return ByteArray(0)
        }
    }

    private fun extractXmlValue(xml: String, tag: String): String? {
        val regex = Regex("<$tag>(.*?)</$tag>", RegexOption.DOT_MATCHES_ALL)
        return regex.find(xml)?.groupValues?.get(1)?.trim()
    }


    private fun bytesToHex(bytes: ByteArray): String {
        return bytes.joinToString("") { "%02x".format(it.toInt() and 0xFF) }
    }

    private fun hexToBytes(hex: String): ByteArray {
        return ByteArray(hex.length / 2) { i ->
            hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
    }

    private fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean {
        if (a.size != b.size) return false
        var diff = 0
        for (i in a.indices) {
            diff = diff or (a[i].toInt() xor b[i].toInt())
        }
        return diff == 0
    }

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

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager


            manager.deleteNotificationChannel("pairing_channel")

            val channel = NotificationChannel(
                CHANNEL_ID,
                "Pairing Service",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Shows PIN and keeps connection alive during PC pairing"
                setShowBadge(false)
                // No sound for this channel — it's informational
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private var currentPin: String? = null

    private fun buildNotification(pin: String? = currentPin): Notification {
        val title = if (pin != null) "PIN: $pin" else "Pairing in Progress"
        val text = if (pin != null) {
            "Enter this PIN in Sunshine to pair"
        } else {
            "Keeping connection alive…"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotificationWithPin(pin: String) {
        currentPin = pin
        val notification = buildNotification(pin)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }
}
data class NativePairingResult(
    val paired: Boolean,
    val serverCertHex: String = "",
    val error: String? = null
)
