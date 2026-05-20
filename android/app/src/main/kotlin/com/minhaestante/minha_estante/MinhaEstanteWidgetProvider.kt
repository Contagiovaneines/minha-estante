package com.minhaestante.minha_estante

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import kotlin.math.roundToInt

class MinhaEstanteWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        private const val prefsName = "minha_estante_home_widget"
        private const val keyTitle = "title"
        private const val keySubtitle = "subtitle"
        private const val keyProgress = "progress"

        fun saveAndUpdate(context: Context, title: String, subtitle: String, progress: Float) {
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit()
                .putString(keyTitle, title.ifBlank { "Minha Estante" })
                .putString(keySubtitle, subtitle.ifBlank { "Continuar lendo" })
                .putFloat(keyProgress, progress.coerceIn(0f, 1f))
                .apply()
            updateAll(context)
        }

        fun clear(context: Context) {
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit()
                .clear()
                .apply()
            updateAll(context)
        }

        private fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, MinhaEstanteWidgetProvider::class.java)
            )
            updateWidgets(context, manager, ids)
        }

        private fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray
        ) {
            val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            val title = prefs.getString(keyTitle, null)
            val subtitle = prefs.getString(keySubtitle, null)
            val progress = prefs.getFloat(keyProgress, 0f).coerceIn(0f, 1f)

            for (widgetId in appWidgetIds) {
                val views = RemoteViews(context.packageName, R.layout.minha_estante_widget)
                views.setTextViewText(R.id.widgetTitle, title ?: "Minha Estante")
                views.setTextViewText(
                    R.id.widgetSubtitle,
                    subtitle ?: "Abra um livro para fixar aqui"
                )

                val progressPercent = (progress * 100).roundToInt().coerceIn(0, 100)
                views.setViewVisibility(
                    R.id.widgetProgress,
                    if (progressPercent > 0) View.VISIBLE else View.GONE
                )
                views.setProgressBar(R.id.widgetProgress, 100, progressPercent, false)
                views.setOnClickPendingIntent(R.id.widgetRoot, launchPendingIntent(context))
                appWidgetManager.updateAppWidget(widgetId, views)
            }
        }

        private fun launchPendingIntent(context: Context): PendingIntent {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(
                context.packageName
            ) ?: Intent(context, MainActivity::class.java)
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

            return PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}
