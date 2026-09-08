package com.filla.wealthtrack

import android.app.Notification
import android.content.Context
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
        val ALLOW: Set<String> = setOf(
            "com.bca",
            "com.bca.mobile",
            "id.bca.mybca",
            "com.bca.mybca",
            "id.bmri.livin",
            "id.co.bri.brimo",
            "com.jago.digitalBanking",
            "id.co.superbank",
            "id.co.superbank.app",
            "com.superbank",
            "id.superbank.mobile",
            "id.co.krom",
            "id.co.krom.android",
            "com.krom.bank",
            "com.krom.id",
            "id.krom.mobile",
        )

        fun isEnabled(context: Context): Boolean {
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: return false
            val name = BankNotificationListener::class.java.name
            return flat.split(":").any { it.contains(name) }
        }

        fun drain(context: Context): List<Map<String, Any?>> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(QUEUE, "[]") ?: "[]"
            prefs.edit().putString(QUEUE, "[]").apply()
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
        if (pkg !in ALLOW) return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        if (title.isBlank() && text.isBlank()) return
        persist(
            JSONObject()
                .put("package", pkg)
                .put("title", title)
                .put("text", text)
                .put("posted_at", Instant.ofEpochMilli(sbn.postTime).toString()),
        )
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
}
