package com.filla.wealthtrack

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.filla.wealthtrack/widget"
        private const val ACTION_ADD_TRANSACTION = "com.filla.wealthtrack.ADD_TRANSACTION"
        private const val ACTION_SCAN_RECEIPT = "com.filla.wealthtrack.SCAN_RECEIPT"
    }

    private var methodChannel: MethodChannel? = null
    private var pendingWidgetAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingAction" -> {
                    result.success(pendingWidgetAction)
                    pendingWidgetAction = null
                }
                else -> result.notImplemented()
            }
        }

        handleWidgetIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetIntent(intent)
    }

    private fun handleWidgetIntent(intent: Intent?) {
        if (intent == null) return

        val action = intent.action
        val actionExtra = intent.getStringExtra(WealthTrackWidget.EXTRA_WIDGET_ACTION)

        val resolvedAction = action ?: actionExtra

        when (resolvedAction) {
            ACTION_ADD_TRANSACTION -> {
                pendingWidgetAction = "add_transaction"
                methodChannel?.invokeMethod("navigate", "add_transaction")
            }
            ACTION_SCAN_RECEIPT -> {
                pendingWidgetAction = "scan_receipt"
                methodChannel?.invokeMethod("navigate", "scan_receipt")
            }
        }
    }
}
