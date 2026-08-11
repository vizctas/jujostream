package com.limelight.jujostream

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

internal object AppUpdaterBridge {
    fun register(activity: FlutterActivity, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jujostream/app_updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            activity.packageManager.canRequestPackageInstalls()
                    )
                    "openInstallPermission" -> openInstallPermission(activity, result)
                    "installApk" -> installApk(activity, call.argument("path"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun openInstallPermission(activity: FlutterActivity, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(true)
            return
        }
        try {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
            )
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun installApk(
        activity: FlutterActivity,
        path: String?,
        result: MethodChannel.Result,
    ) {
        if (path.isNullOrBlank()) {
            result.error("invalid_path", "APK path is missing", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            result.error("permission_required", "Install permission is required", null)
            return
        }
        try {
            val apk = File(path)
            if (!apk.isFile || apk.extension.lowercase() != "apk") {
                result.error("invalid_apk", "APK file does not exist", null)
                return
            }
            val preflightError = verifyUpdate(activity, apk)
            if (preflightError != null) {
                apk.delete()
                result.error("rejected_apk", preflightError, null)
                return
            }
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.update_provider",
                apk,
            )
            activity.startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            result.success(true)
        } catch (error: Exception) {
            result.error("install_failed", error.message, null)
        }
    }

    private fun verifyUpdate(activity: FlutterActivity, apk: File): String? {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        val candidate = activity.packageManager.getPackageArchiveInfo(apk.path, flags)
            ?: return "Android could not parse the downloaded APK"
        if (candidate.packageName != activity.packageName) {
            return "Downloaded APK package does not match JUJO Stream"
        }
        val installed = activity.packageManager.getPackageInfo(activity.packageName, flags)
        if (longVersionCode(candidate) <= longVersionCode(installed)) {
            return "Downloaded APK is not a newer version"
        }
        val candidateSigners = signerDigests(candidate)
        val installedSigners = signerDigests(installed)
        if (candidateSigners.isEmpty() || candidateSigners != installedSigners) {
            return "Downloaded APK signer does not match the installed app"
        }
        return null
    }

    private fun longVersionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }

    private fun signerDigests(info: PackageInfo): Set<String> {
        val signatures: Array<Signature> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners ?: emptyArray()
        } else {
            @Suppress("DEPRECATION")
            info.signatures ?: emptyArray()
        }
        return signatures.mapTo(mutableSetOf()) { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }
    }
}
