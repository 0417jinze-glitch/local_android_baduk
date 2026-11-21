package app.weiqi.weiqi

import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.FileOutputStream
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(
            messenger,
            "app.weiqi/files",
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "directory" -> result.success(filesDir.absolutePath)
                "copyModel" -> {
                    val asset = call.argument<String>("asset")!!
                    val path = call.argument<String>("path")!!
                    try {
                        val key = FlutterInjector.instance().flutterLoader()
                            .getLookupKeyForAsset("assets/engine/$asset")
                        assets.open(key).use { input ->
                            FileOutputStream(path).use { output ->
                                input.copyTo(output, bufferSize = 64 * 1024)
                                output.fd.sync()
                            }
                        }
                        result.success(null)
                    } catch (error: IOException) {
                        result.error("copyModel", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
