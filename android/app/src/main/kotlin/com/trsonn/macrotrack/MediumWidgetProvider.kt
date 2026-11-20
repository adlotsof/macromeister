package com.trsonn.macrotrack

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews

import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen glance widget: today's remaining kcal, macro line and water
 * total. Data is written from Dart via HomeWidget.saveWidgetData (see
 * lib/services/widget_sync.dart) on every log/water change; this provider
 * just renders the saved strings.
 */
class MediumWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.medium_widget).apply {
            setTextViewText(
                R.id.widget_remaining,
                widgetData.getString("remaining", null) ?: "— kcal left"
            )
            setTextViewText(
                R.id.widget_macros,
                widgetData.getString("macros", null) ?: "P— · C— · F—"
            )
            setTextViewText(
                R.id.widget_water,
                widgetData.getString("water", null) ?: "Water: — ml"
            )
        }
        appWidgetManager.updateAppWidget(appWidgetIds, views)
    }
}
