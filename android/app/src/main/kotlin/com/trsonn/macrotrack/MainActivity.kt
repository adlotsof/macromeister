package com.trsonn.macrotrack

import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Streams a bundled Flutter asset out of the APK to a file in small chunks.
 * The Dart AssetBundle API only loads whole files into memory, which OOM-kills
 * the app for the 668 MB food database; AssetManager streams it instead.
 *
 * Extends FlutterFragmentActivity (not FlutterActivity) because the health
 * plugin casts the hosting Activity to androidx.activity.ComponentActivity —
 * with FlutterActivity its registration throws and aborts the whole plugin
 * registration chain.
 */
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.trsonn.macrotrack/asset_copy"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "copyAsset" -> {
                    val asset = call.argument<String>("asset")
                    val dest = call.argument<String>("dest")
                    if (asset == null || dest == null) {
                        result.error("args", "asset and dest required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val tmp = File(dest + ".tmp")
                        if (tmp.exists()) tmp.delete()
                        val input = assets.open(asset)
                        val out = FileOutputStream(tmp)
                        val buf = ByteArray(1 shl 20)
                        var copied = 0L
                        input.use { i ->
                            out.use { o ->
                                while (true) {
                                    val n = i.read(buf)
                                    if (n < 0) break
                                    o.write(buf, 0, n)
                                    copied += n
                                }
                                o.flush()
                                o.fd.sync()
                            }
                        }
                        val target = File(dest)
                        if (target.exists()) target.delete()
                        if (!tmp.renameTo(target)) {
                            result.error("rename", "rename failed", null)
                            return@setMethodCallHandler
                        }
                        result.success(copied)
                    } catch (e: Exception) {
                        File(dest + ".tmp").delete()
                        result.error("io", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
