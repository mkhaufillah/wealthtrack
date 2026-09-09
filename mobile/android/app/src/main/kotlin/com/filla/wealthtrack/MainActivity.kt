package com.filla.wealthtrack

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.filla.wealthtrack/bank_capture")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(BankNotificationListener.isEnabled(this))
                    "openSettings" -> {
                        startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
                        result.success(null)
                    }
                    "drain" -> result.success(BankNotificationListener.drain(this))
                    "listApps" -> result.success(BankNotificationListener.listLauncherApps(this))
                    "getListenPackages" -> result.success(BankNotificationListener.listenSet(this).toList())
                    "setListenPackages" -> {
                        val pkgs = (call.arguments as? List<*>)?.map { it.toString() } ?: emptyList()
                        BankNotificationListener.setListen(this, pkgs)
                        result.success(null)
                    }
                    "takePendingAction" -> result.success(BankNotificationListener.takePendingAction(this))
                    "requestNotify" -> {
                        BankNotificationListener.ensureChannel(this)
                        if (Build.VERSION.SDK_INT >= 33) {
                            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                                PackageManager.PERMISSION_GRANTED
                            ) {
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 91)
                            }
                        }
                        result.success(null)
                    }
                    "setSession" -> {
                        val args = call.arguments as? Map<*, *>
                        val base = args?.get("base")?.toString() ?: ""
                        val token = args?.get("token")?.toString() ?: ""
                        val lainnya = (args?.get("lainnya_id") as? Number)?.toInt() ?: 0
                        BankNotificationListener.setSession(this, base, token, lainnya)
                        result.success(null)
                    }
                    "clearSession" -> {
                        BankNotificationListener.clearSession(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        handleBankIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetIntent(intent)
        handleBankIntent(intent)
    }

    private fun handleBankIntent(intent: Intent?) {
        if (intent == null) return
        val action = when (intent.action) {
            BankNotificationListener.ACTION_CONFIRM -> "confirm"
            BankNotificationListener.ACTION_REJECT -> "reject"
            BankNotificationListener.ACTION_DELETE -> "delete"
            else -> null
        } ?: return
        BankNotificationListener.storePendingAction(this, action, intent.extras)
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
