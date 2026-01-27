package com.zivpn.netreset

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.zivpn.netreset/service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startForeground") {
                val serviceIntent = Intent(this, KeepAliveService::class.java)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                result.success("Started")
            } else if (call.method == "stopForeground") {
                val serviceIntent = Intent(this, KeepAliveService::class.java)
                stopService(serviceIntent)
                result.success("Stopped")
            } else if (call.method == "minimizeApp") {
                moveTaskToBack(true)
                result.success("Minimized")
            } else {
                result.notImplemented()
            }
        }
    }
}
