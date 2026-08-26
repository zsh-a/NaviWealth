package com.naviwealth.naviwealth

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.Locale

/**
 * Installs a verified APK downloaded by the Flutter GitHub update client.
 *
 * The package manager remains the authority for installation. This bridge
 * only validates the archive, exposes it through FileProvider, and launches
 * the system confirmation UI; it never attempts a silent install.
 */
internal class AndroidNativeUpdateBridge(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val METHOD_CHANNEL = "com.naviwealth/native_update"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }

    private val context: Context = activity.applicationContext
    private var methodChannel: MethodChannel? = null

    fun attach(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).also { it.setMethodCallHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "can_install_packages" -> result.success(canInstallPackages())
            "open_install_settings" -> openInstallSettings(result)
            "install_apk" -> installApk(call.argument<String>("path"), result)
            else -> result.notImplemented()
        }
    }

    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()

    private fun openInstallSettings(result: MethodChannel.Result) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:${context.packageName}")
            }
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        try {
            activity.startActivity(intent)
            result.success(null)
        } catch (error: ActivityNotFoundException) {
            result.error(
                "install_permission",
                "Android install settings are unavailable",
                error.message,
            )
        }
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("install", "APK path is missing", null)
            return
        }

        val apk = File(path)
        if (!apk.isFile || apk.length() == 0L) {
            result.error("install", "Downloaded APK is missing", null)
            return
        }

        val archive = context.packageManager.getPackageArchiveInfo(
            apk.absolutePath,
            packageInfoFlags(),
        )
        if (archive == null) {
            result.error("package_mismatch", "Downloaded file is not a valid APK", null)
            return
        }
        if (archive.packageName != context.packageName) {
            result.error(
                "package_mismatch",
                "Downloaded APK belongs to another application",
                archive.packageName,
            )
            return
        }

        val installed = try {
            context.packageManager.getPackageInfo(
                context.packageName,
                packageInfoFlags(),
            )
        } catch (error: PackageManager.NameNotFoundException) {
            result.error("package_mismatch", "Installed package could not be read", error.message)
            return
        }
        if (archiveVersionCode(archive) <= archiveVersionCode(installed)) {
            result.error(
                "downgrade",
                "Downloaded APK is not newer than the installed version",
                null,
            )
            return
        }
        val archiveSignatures = signatureDigests(archive)
        val installedSignatures = signatureDigests(installed)
        if (archiveSignatures.isEmpty() ||
            installedSignatures.isEmpty() ||
            archiveSignatures != installedSignatures
        ) {
            result.error(
                "signature_mismatch",
                "Downloaded APK is not signed by NaviWealth",
                null,
            )
            return
        }

        val uri = try {
            FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                apk,
            )
        } catch (error: IllegalArgumentException) {
            result.error("install", "Downloaded APK path is not shareable", error.message)
            return
        }

        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, APK_MIME_TYPE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            activity.startActivity(intent)
            result.success(null)
        } catch (error: SecurityException) {
            result.error("install_permission", "Android blocked APK installation", error.message)
        } catch (error: ActivityNotFoundException) {
            result.error("install", "No Android package installer is available", error.message)
        }
    }

    @Suppress("DEPRECATION")
    private fun packageInfoFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }

    @Suppress("DEPRECATION")
    private fun archiveVersionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }

    @Suppress("DEPRECATION")
    private fun signatureDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners ?: emptyArray()
        } else {
            info.signatures ?: emptyArray()
        }
        return signatures.map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString(separator = "") { byte ->
                    "%02x".format(Locale.ROOT, byte.toInt() and 0xff)
                }
        }.toSet()
    }

    fun dispose() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
    }
}
