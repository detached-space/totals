package detached.totals

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Locale
import kotlin.math.roundToInt

class ExpenseWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val ACTION_TOGGLE_VISIBILITY =
            "detached.totals.widget.TOGGLE_VISIBILITY"
        private const val ACTION_TOGGLE_FLOW =
            "detached.totals.widget.TOGGLE_FLOW"
        private const val PREF_KEY_HIDDEN_PREFIX = "expense_widget_hidden_"
        private const val PREF_KEY_FLOW_PREFIX = "expense_widget_show_income_"
    }

    private data class WidgetMode(
        val widthDp: Int,
        val heightDp: Int,
        val compact: Boolean,
        val showHeader: Boolean,
        val showTitle: Boolean,
        val showLastUpdated: Boolean,
        val maxCategoryRows: Int
    )

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_TOGGLE_VISIBILITY -> {
                val widgetId = intent.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID
                )
                if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return

                val prefs = HomeWidgetPlugin.getData(context)
                val key = "$PREF_KEY_HIDDEN_PREFIX$widgetId"
                val newState = !prefs.getBoolean(key, false)
                prefs.edit().putBoolean(key, newState).apply()

                val appWidgetManager = AppWidgetManager.getInstance(context)
                onUpdate(context, appWidgetManager, intArrayOf(widgetId), prefs)
            }

            ACTION_TOGGLE_FLOW -> {
                val widgetId = intent.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID
                )
                if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return

                val prefs = HomeWidgetPlugin.getData(context)
                val key = "$PREF_KEY_FLOW_PREFIX$widgetId"
                val newState = !prefs.getBoolean(key, false)
                prefs.edit().putBoolean(key, newState).apply()

                val appWidgetManager = AppWidgetManager.getInstance(context)
                onUpdate(context, appWidgetManager, intArrayOf(widgetId), prefs)
            }
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val prefs = HomeWidgetPlugin.getData(context)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), prefs)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_expense_layout)
            val mode = resolveWidgetMode(appWidgetManager, widgetId)

            val hiddenKey = "$PREF_KEY_HIDDEN_PREFIX$widgetId"
            val isHidden = widgetData.getBoolean(hiddenKey, false)
            val flowKey = "$PREF_KEY_FLOW_PREFIX$widgetId"
            val showIncome = widgetData.getBoolean(flowKey, false)

            bindClickActions(context, views, widgetId)
            views.setImageViewResource(
                R.id.toggle_visibility,
                if (isHidden) R.drawable.ic_visibility_off else R.drawable.ic_visibility_on
            )
            applyResponsiveLayout(context, views, mode)

            val totalKey = if (showIncome) "income_total" else "expense_total"
            val totalRawKey = if (showIncome) "income_total_raw" else "expense_total_raw"
            val lastUpdatedKey = if (showIncome) "income_last_updated" else "expense_last_updated"
            val categoryPrefix = if (showIncome) "income_category" else "category"

            val totalAmount = widgetData.getString(totalKey, "0 ETB") ?: "0 ETB"
            val lastUpdated = widgetData.getString(lastUpdatedKey, null)
                ?: widgetData.getString("expense_last_updated", "--")
                ?: "--"

            val parts = totalAmount.trim().split(" ")
            val value = parts.getOrNull(0) ?: "0"
            val currency = parts.getOrNull(1) ?: "ETB"

            views.setTextViewText(
                R.id.widget_title,
                if (showIncome) "Today's Income" else "Today's Spending"
            )
            views.setTextViewText(R.id.last_updated, lastUpdated)
            views.setTextViewText(
                R.id.toggle_flow,
                if (showIncome) "Show expense" else "Show income"
            )

            val categoryRowIds = listOf(
                R.id.category_row_0,
                R.id.category_row_1,
                R.id.category_row_2
            )
            val categoryNameIds = listOf(
                R.id.category_name_0,
                R.id.category_name_1,
                R.id.category_name_2
            )
            val categoryAmountIds = listOf(
                R.id.category_amount_0,
                R.id.category_amount_1,
                R.id.category_amount_2
            )
            val rankColors = intArrayOf(
                ContextCompat.getColor(context, R.color.budget_widget_progress_safe),
                ContextCompat.getColor(context, R.color.budget_widget_progress_warn),
                ContextCompat.getColor(context, R.color.budget_widget_progress_danger)
            )

            val totalRaw = widgetData.getString(totalRawKey, null)
                ?.toDoubleOrNull()
                ?: parseCompactAmount(widgetData.getString(totalKey, null))
            val rawAmounts = DoubleArray(3) { index ->
                widgetData.getString("${categoryPrefix}_${index}_amount_raw", null)
                    ?.toDoubleOrNull()
                    ?.takeIf { it > 0.0 }
                    ?: parseCompactAmount(
                        widgetData.getString("${categoryPrefix}_${index}_amount", null)
                    )
            }
            val names = Array(3) { index ->
                widgetData.getString("${categoryPrefix}_${index}_name", "") ?: ""
            }
            val labels = Array(3) { index ->
                widgetData.getString("${categoryPrefix}_${index}_amount", "") ?: ""
            }
            val sumTop = rawAmounts.sum()
            var base = if (totalRaw > 0.0) totalRaw else sumTop
            if (base < sumTop) base = sumTop
            val percentLabels = Array(3) { index ->
                formatPercent(rawAmounts[index], base)
            }

            createCategoryBarBitmap(
                context = context,
                appWidgetManager = appWidgetManager,
                widgetId = widgetId,
                values = rawAmounts,
                base = base,
                colors = rankColors
            )?.let { bitmap ->
                views.setImageViewBitmap(R.id.category_bar, bitmap)
            }

            if (isHidden) {
                views.setTextViewText(R.id.expense_total_value, "***")
                views.setTextViewText(R.id.expense_total_currency, "")
            } else {
                views.setTextViewText(R.id.expense_total_value, value)
                views.setTextViewText(R.id.expense_total_currency, " $currency")
            }

            for (i in 0..2) {
                if (i >= mode.maxCategoryRows || names[i].isBlank()) {
                    views.setViewVisibility(categoryRowIds[i], View.GONE)
                    continue
                }

                views.setViewVisibility(categoryRowIds[i], View.VISIBLE)
                views.setTextViewText(categoryNameIds[i], names[i])

                views.setTextViewText(
                    categoryAmountIds[i],
                    if (isHidden) percentLabels[i] else labels[i]
                )
                views.setTextColor(categoryAmountIds[i], rankColors[i])
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun resolveWidgetMode(
        appWidgetManager: AppWidgetManager,
        widgetId: Int
    ): WidgetMode {
        val options = appWidgetManager.getAppWidgetOptions(widgetId)

        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            .takeIf { it > 0 }
            ?: options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH).takeIf { it > 0 }
            ?: 240
        val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            .takeIf { it > 0 }
            ?: options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).takeIf { it > 0 }
            ?: 110

        val compact = widthDp < 220 || heightDp < 120
        val showHeader = heightDp >= 84
        val showTitle = widthDp >= 178
        val showLastUpdated = heightDp >= 108
        val maxCategoryRows = when {
            widthDp < 182 -> 1
            widthDp < 226 -> 2
            else -> 3
        }

        return WidgetMode(
            widthDp = widthDp,
            heightDp = heightDp,
            compact = compact,
            showHeader = showHeader,
            showTitle = showTitle,
            showLastUpdated = showLastUpdated,
            maxCategoryRows = maxCategoryRows
        )
    }

    private fun applyResponsiveLayout(context: Context, views: RemoteViews, mode: WidgetMode) {
        val density = context.resources.displayMetrics.density
        val horizontalPadding = if (mode.compact) 10 else 12
        val verticalPadding = when {
            mode.heightDp < 84 -> 4
            mode.compact -> 8
            else -> 12
        }

        views.setViewPadding(
            R.id.widget_root,
            (horizontalPadding * density).roundToInt(),
            (verticalPadding * density).roundToInt(),
            (horizontalPadding * density).roundToInt(),
            (verticalPadding * density).roundToInt()
        )

        views.setViewVisibility(
            R.id.expense_header_row,
            if (mode.showHeader) View.VISIBLE else View.GONE
        )
        views.setViewVisibility(
            R.id.widget_title,
            if (mode.showTitle) View.VISIBLE else View.GONE
        )
        views.setViewVisibility(
            R.id.last_updated,
            if (mode.showLastUpdated) View.VISIBLE else View.GONE
        )

        views.setTextViewTextSize(
            R.id.widget_title,
            TypedValue.COMPLEX_UNIT_SP,
            if (mode.compact) 12f else 13f
        )
        views.setTextViewTextSize(
            R.id.toggle_flow,
            TypedValue.COMPLEX_UNIT_SP,
            if (mode.compact) 10f else 11f
        )
        views.setTextViewTextSize(
            R.id.expense_total_value,
            TypedValue.COMPLEX_UNIT_SP,
            when {
                mode.heightDp < 84 -> 22f
                mode.compact -> 24f
                else -> 30f
            }
        )
        views.setTextViewTextSize(
            R.id.expense_total_currency,
            TypedValue.COMPLEX_UNIT_SP,
            when {
                mode.heightDp < 84 -> 10f
                mode.compact -> 11f
                else -> 13f
            }
        )
        views.setTextViewTextSize(
            R.id.last_updated,
            TypedValue.COMPLEX_UNIT_SP,
            if (mode.compact) 7.5f else 8f
        )

        val rowNameIds = listOf(
            R.id.category_name_0,
            R.id.category_name_1,
            R.id.category_name_2
        )
        val rowAmountIds = listOf(
            R.id.category_amount_0,
            R.id.category_amount_1,
            R.id.category_amount_2
        )
        rowNameIds.forEach { id ->
            views.setTextViewTextSize(
                id,
                TypedValue.COMPLEX_UNIT_SP,
                if (mode.heightDp < 84) 8.5f else if (mode.compact) 9f else 10f
            )
        }
        rowAmountIds.forEach { id ->
            views.setTextViewTextSize(
                id,
                TypedValue.COMPLEX_UNIT_SP,
                if (mode.heightDp < 84) 8.5f else if (mode.compact) 9f else 10f
            )
        }
    }

    private fun bindClickActions(context: Context, views: RemoteViews, widgetId: Int) {
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val launchPendingIntent = PendingIntent.getActivity(
            context,
            widgetId + 1000,
            launchIntent,
            pendingFlags
        )
        views.setOnClickPendingIntent(R.id.widget_root, launchPendingIntent)

        val toggleIntent = Intent(context, ExpenseWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE_VISIBILITY
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        val togglePendingIntent = PendingIntent.getBroadcast(
            context,
            widgetId,
            toggleIntent,
            pendingFlags
        )
        views.setOnClickPendingIntent(R.id.toggle_visibility, togglePendingIntent)

        val toggleFlowIntent = Intent(context, ExpenseWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE_FLOW
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        val toggleFlowPendingIntent = PendingIntent.getBroadcast(
            context,
            widgetId + 2000,
            toggleFlowIntent,
            pendingFlags
        )
        views.setOnClickPendingIntent(R.id.toggle_flow, toggleFlowPendingIntent)
    }

    private fun createCategoryBarBitmap(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        values: DoubleArray,
        base: Double,
        colors: IntArray
    ): Bitmap? {
        val options = appWidgetManager.getAppWidgetOptions(widgetId)
        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            .takeIf { it > 0 }
            ?: options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH).takeIf { it > 0 }
            ?: 240

        val density = context.resources.displayMetrics.density
        val widthPx = ((widthDp - 24).coerceAtLeast(96) * density).toInt().coerceAtLeast(1)
        val heightPx = (8f * density).toInt().coerceAtLeast(1)

        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        if (base <= 0.0) return bitmap

        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val radius = heightPx / 2f

        val clipPath = Path().apply {
            addRoundRect(
                RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()),
                radius,
                radius,
                Path.Direction.CW
            )
        }
        canvas.clipPath(clipPath)

        var startX = 0f
        for (index in values.indices) {
            val fraction = (values[index] / base).coerceIn(0.0, 1.0)
            val segmentWidth = (fraction * widthPx).toFloat()
            if (segmentWidth <= 0f) continue

            paint.color = colors[index % colors.size]
            val endX = (startX + segmentWidth).coerceAtMost(widthPx.toFloat())
            canvas.drawRect(startX, 0f, endX, heightPx.toFloat(), paint)
            startX = endX
        }

        return bitmap
    }

    private fun parseCompactAmount(raw: String?): Double {
        if (raw.isNullOrBlank()) return 0.0
        val normalized = raw.trim().lowercase(Locale.US).replace("etb", "").trim()
        if (normalized.isEmpty()) return 0.0

        val multiplier = when {
            normalized.endsWith("k") -> 1000.0
            normalized.endsWith("m") -> 1000000.0
            else -> 1.0
        }
        val numeric = normalized.trimEnd('k', 'm').replace(",", "").trim()
        return numeric.toDoubleOrNull()?.times(multiplier) ?: 0.0
    }

    private fun formatPercent(value: Double, base: Double): String {
        if (value <= 0.0 || base <= 0.0) return "0%"
        val percent = (value / base * 100.0).roundToInt().coerceIn(1, 100)
        return "$percent%"
    }
}
