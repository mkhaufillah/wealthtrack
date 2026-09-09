package com.filla.wealthtrack

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class BankNotifActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = when (intent.action) {
            BankNotificationListener.ACTION_CONFIRM -> "confirm"
            BankNotificationListener.ACTION_REJECT -> "reject"
            BankNotificationListener.ACTION_DELETE -> "delete"
            else -> return
        }
        val notifId = intent.getIntExtra("notif_id", -1)
        if (notifId >= 0) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel("wt_bank", notifId)
        }
        val pkg = intent.getStringExtra("package") ?: ""
        val title = intent.getStringExtra("title") ?: ""
        val text = intent.getStringExtra("text") ?: ""
        val posted = intent.getStringExtra("posted_at") ?: ""
        val pending = goAsync()
        Thread {
            try {
                runAction(context, action, pkg, title, text, posted)
            } catch (_: Exception) {
            } finally {
                pending.finish()
            }
        }.start()
    }

    private fun runAction(
        context: Context,
        action: String,
        pkg: String,
        title: String,
        text: String,
        posted: String,
    ) {
        val prefs = context.getSharedPreferences(BankNotificationListener.PREFS, Context.MODE_PRIVATE)
        val base = prefs.getString("api_base", "") ?: ""
        val token = prefs.getString("api_token", "") ?: ""
        if (base.isBlank() || token.isBlank()) return
        val body = JSONObject()
            .put("package", pkg)
            .put("title", title)
            .put("text", text)
            .put("posted_at", posted)
        val ingest = http(base.trimEnd('/') + "/bank-inbox", "POST", token, body) ?: return
        val id = ingest.optInt("id", -1)
        if (id <= 0) return
        when (action) {
            "confirm" -> {
                var cat = prefs.getInt("lainnya_id", 0)
                if (cat <= 0) cat = lookupLainnya(base, token)
                val payload = JSONObject()
                if (cat > 0) payload.put("category_id", cat)
                http(base.trimEnd('/') + "/bank-inbox/$id/confirm", "POST", token, payload)
            }
            "reject" -> http(base.trimEnd('/') + "/bank-inbox/$id/reject", "POST", token, JSONObject())
            "delete" -> http(base.trimEnd('/') + "/bank-inbox/$id", "DELETE", token, null)
        }
        dropQueue(context, pkg, posted)
    }

    private fun lookupLainnya(base: String, token: String): Int {
        val arr = httpArray(base.trimEnd('/') + "/categories", token) ?: return 0
        var fallback = 0
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (!o.optString("name").equals("Lainnya", ignoreCase = true)) continue
            val id = o.optInt("id", 0)
            if (o.optString("type") == "expense") return id
            if (fallback == 0) fallback = id
        }
        return fallback
    }

    private fun dropQueue(context: Context, pkg: String, posted: String) {
        val prefs = context.getSharedPreferences(BankNotificationListener.PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(BankNotificationListener.QUEUE, "[]"))
        val next = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.optString("package") == pkg && o.optString("posted_at") == posted) continue
            next.put(o)
        }
        prefs.edit().putString(BankNotificationListener.QUEUE, next.toString()).apply()
    }

    private fun http(url: String, method: String, token: String, body: JSONObject?): JSONObject? {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 15000
        conn.readTimeout = 20000
        conn.requestMethod = method
        conn.setRequestProperty("Authorization", "Bearer $token")
        conn.setRequestProperty("Accept", "application/json")
        if (body != null && method != "GET") {
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            OutputStreamWriter(conn.outputStream).use { it.write(body.toString()) }
        }
        val code = conn.responseCode
        val stream = if (code in 200..299) conn.inputStream else conn.errorStream
        val text = stream?.bufferedReader()?.readText() ?: ""
        conn.disconnect()
        if (code !in 200..299) return null
        if (text.isBlank()) return JSONObject()
        return JSONObject(text)
    }

    private fun httpArray(url: String, token: String): JSONArray? {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 15000
        conn.readTimeout = 20000
        conn.requestMethod = "GET"
        conn.setRequestProperty("Authorization", "Bearer $token")
        conn.setRequestProperty("Accept", "application/json")
        val code = conn.responseCode
        val stream = if (code in 200..299) conn.inputStream else conn.errorStream
        val text = stream?.bufferedReader()?.readText() ?: ""
        conn.disconnect()
        if (code !in 200..299 || text.isBlank()) return null
        return JSONArray(text)
    }
}
