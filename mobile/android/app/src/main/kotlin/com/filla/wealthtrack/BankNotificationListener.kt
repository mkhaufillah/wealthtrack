package com.filla.wealthtrack

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

class BankNotificationListener : NotificationListenerService() {
    companion object {
        const val PREFS = "bank_capture"
        const val QUEUE = "queue"
        const val LISTEN = "listen_packages"
        const val PENDING_ACTION = "pending_action"
        const val CHANNEL_ID = "wt_bank"
        const val ACTION_CONFIRM = "com.filla.wealthtrack.BANK_CONFIRM"
        const val ACTION_REJECT = "com.filla.wealthtrack.BANK_REJECT"
        const val ACTION_DELETE = "com.filla.wealthtrack.BANK_DELETE"
        val DEFAULT_LISTEN: Set<String> = setOf(
            "com.bca",
            "id.bmri.livin",
            "id.co.bri.brimo",
            "com.jago.digitalBanking",
            "id.co.bankfama.android",
            "com.krom.android",
            "id.co.btn.mobilebanking.android",
            "id.co.bankbkemobile.digitalbank",
            "com.bibit.bibitid",
            "com.stockbit.android",
            "com.telkom.mwallet",
            "id.flip",
            "ovo.id",
            "com.gojek.gopay",
            "id.dana",
            "com.shopeepay.id",
        )

        fun isEnabled(context: Context): Boolean {
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: return false
            val name = BankNotificationListener::class.java.name
            return flat.split(":").any { it.contains(name) }
        }

        fun listenSet(context: Context): Set<String> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(LISTEN, null)
            if (raw != null) {
                val arr = JSONArray(raw)
                val out = HashSet<String>()
                for (i in 0 until arr.length()) {
                    val v = arr.optString(i)
                    if (v.isNotBlank()) out.add(v)
                }
                return out
            }
            val installed = listLauncherApps(context).mapNotNull { it["package"] as? String }.toSet()
            return DEFAULT_LISTEN.intersect(installed)
        }

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(CHANNEL_ID, "Draf bank", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "Draf transaksi dari notifikasi app lain"
            ch.enableVibration(true)
            ch.setShowBadge(true)
            nm.createNotificationChannel(ch)
        }

        fun setListen(context: Context, packages: List<String>) {
            val arr = JSONArray()
            packages.forEach { arr.put(it) }
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(LISTEN, arr.toString()).apply()
        }

        fun listLauncherApps(context: Context): List<Map<String, Any?>> {
            val pm = context.packageManager
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            val resolved = pm.queryIntentActivities(intent, PackageManager.MATCH_ALL)
            val out = ArrayList<Map<String, Any?>>()
            val seen = HashSet<String>()
            for (ri in resolved) {
                val pkg = ri.activityInfo.packageName ?: continue
                if (!seen.add(pkg)) continue
                val label = ri.loadLabel(pm)?.toString() ?: pkg
                out.add(mapOf("package" to pkg, "label" to label))
            }
            out.sortBy { (it["label"] as String).lowercase() }
            return out
        }

        fun drain(context: Context): List<Map<String, Any?>> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(QUEUE, "[]") ?: "[]"
            prefs.edit().putString(QUEUE, "[]").apply()
            return parseQueue(raw)
        }

        fun takePendingAction(context: Context): Map<String, Any?>? {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(PENDING_ACTION, null) ?: return null
            prefs.edit().remove(PENDING_ACTION).apply()
            val o = JSONObject(raw)
            return mapOf(
                "action" to o.optString("action"),
                "package" to o.optString("package"),
                "title" to o.optString("title"),
                "text" to o.optString("text"),
                "posted_at" to o.optString("posted_at"),
            )
        }

        fun storePendingAction(context: Context, action: String, extras: android.os.Bundle?) {
            val o = JSONObject()
                .put("action", action)
                .put("package", extras?.getString("package") ?: "")
                .put("title", extras?.getString("title") ?: "")
                .put("text", extras?.getString("text") ?: "")
                .put("posted_at", extras?.getString("posted_at") ?: "")
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(PENDING_ACTION, o.toString()).apply()
        }

        private fun parseQueue(raw: String): List<Map<String, Any?>> {
            val arr = JSONArray(raw)
            val out = ArrayList<Map<String, Any?>>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                out.add(
                    mapOf(
                        "package" to o.optString("package"),
                        "title" to o.optString("title"),
                        "text" to o.optString("text"),
                        "posted_at" to o.optString("posted_at"),
                    ),
                )
            }
            return out
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return
        if (pkg !in listenSet(this)) return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        if (title.isBlank() && text.isBlank()) return
        val obj = JSONObject()
            .put("package", pkg)
            .put("title", title)
            .put("text", text)
            .put("posted_at", Instant.ofEpochMilli(sbn.postTime).toString())
        persist(obj)
        notifyDraft(obj)
    }

    private fun persist(obj: JSONObject) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(QUEUE, "[]"))
        arr.put(obj)
        while (arr.length() > 200) {
            arr.remove(0)
        }
        prefs.edit().putString(QUEUE, arr.toString()).apply()
    }

    private fun notifyDraft(obj: JSONObject) {
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
                ) {
                    return
                }
            }
            ensureChannel(this)
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !nm.areNotificationsEnabled()) return
            val title = obj.optString("title")
            val text = obj.optString("text")
            val preview = listOf(title, text).filter { it.isNotBlank() }.joinToString(" · ").take(80)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            fun actionPi(action: String, code: Int): PendingIntent {
                val i = Intent(this, MainActivity::class.java).apply {
                    this.action = action
                    putExtra("package", obj.optString("package"))
                    putExtra("title", title)
                    putExtra("text", text)
                    putExtra("posted_at", obj.optString("posted_at"))
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                return PendingIntent.getActivity(this, code, i, flags)
            }
            val id = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
            val icon = if (applicationInfo.icon != 0) applicationInfo.icon else android.R.drawable.stat_notify_chat
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            builder.setSmallIcon(icon)
                .setContentTitle("Transaksi baru")
                .setContentText(preview.ifBlank { "Ada draf dari notifikasi" })
                .setStyle(Notification.BigTextStyle().bigText(preview.ifBlank { "Ada draf dari notifikasi" }))
                .setAutoCancel(true)
                .setContentIntent(actionPi(ACTION_CONFIRM, id + 1))
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_HIGH)
            builder.addAction(icon, "Catat", actionPi(ACTION_CONFIRM, id + 2))
            builder.addAction(icon, "Abaikan", actionPi(ACTION_REJECT, id + 3))
            builder.addAction(icon, "Hapus", actionPi(ACTION_DELETE, id + 4))
            nm.notify("wt_bank", id, builder.build())
        } catch (_: Exception) {
        }
    }
}
