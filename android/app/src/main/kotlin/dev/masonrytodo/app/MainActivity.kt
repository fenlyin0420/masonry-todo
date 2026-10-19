package dev.masonrytodo.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // 自动更新通道：提供下载目录、ABI、安装权限检查与系统安装器唤起。
    // 下载好的 APK 放在内部 filesDir/updates 下，经 FileProvider 交给安装器。
    private val channelName = "masonry_todo.updates"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getUpdatesDir" -> {
                        val dir = File(filesDir, "updates").apply { mkdirs() }
                        result.success(dir.absolutePath)
                    }

                    "getAbi" -> {
                        result.success(Build.SUPPORTED_ABIS.firstOrNull())
                    }

                    "canInstall" -> {
                        // canRequestPackageInstalls 与 ACTION_MANAGE_UNKNOWN_APP_SOURCES
                        // 都是 API 26 才有；minSdk 24 的机型视为可用，
                        // 安装走普通 ACTION_VIEW 流程。
                        result.success(
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                                true
                            } else {
                                packageManager.canRequestPackageInstalls()
                            },
                        )
                    }

                    "openInstallSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        Uri.parse("package:$packageName"),
                                    ),
                                )
                            }
                        } catch (e: android.content.ActivityNotFoundException) {
                            // 老系统没有这个设置页，忽略。
                        }
                        result.success(null)
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("NO_PATH", "missing apk path", null)
                            return@setMethodCallHandler
                        }
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("NOT_FOUND", "apk file missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri =
                                FileProvider.getUriForFile(
                                    this,
                                    "$packageName.updates",
                                    file,
                                )
                            startActivity(
                                Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(
                                        uri,
                                        "application/vnd.android.package-archive",
                                    ).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            // 权限未给、安装器缺失或 FileProvider 配置不对：
                            // 把原因交给 Dart 侧提示，别让用户只看到没反应。
                            result.error("INSTALL_FAILED", e.message ?: e.toString(), null)
                        }
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }
}
