package app.weiqi.weiqi

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.weiqi/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "directory" -> result.success(filesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }
    }
}
