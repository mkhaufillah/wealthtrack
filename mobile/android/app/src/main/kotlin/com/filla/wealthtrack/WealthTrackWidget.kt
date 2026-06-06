package com.filla.wealthtrack

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * AppWidgetProvider for WealthTrack quick action widget.
 * Two buttons: Add Transaction & Scan Receipt.
 * Each tap launches MainActivity with a specific action string.
 */
class WealthTrackWidget : AppWidgetProvider() {

    companion object {
        const val ACTION_ADD_TRANSACTION = "com.filla.wealthtrack.ADD_TRANSACTION"
        const val ACTION_SCAN_RECEIPT = "com.filla.wealthtrack.SCAN_RECEIPT"
        const val EXTRA_WIDGET_ACTION = "widget_action"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val views = RemoteViews(context.packageName, R.layout.wealthtrack_widget)

        // PendingIntent for "Add Transaction" button
        val addIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_ADD_TRANSACTION
            putExtra(EXTRA_WIDGET_ACTION, ACTION_ADD_TRANSACTION)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val addPendingIntent = PendingIntent.getActivity(
            context,
            0,
            addIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_add_transaction, addPendingIntent)

        // PendingIntent for "Scan Receipt" button
        val scanIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_SCAN_RECEIPT
            putExtra(EXTRA_WIDGET_ACTION, ACTION_SCAN_RECEIPT)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val scanPendingIntent = PendingIntent.getActivity(
            context,
            1,
            scanIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_scan_receipt, scanPendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
