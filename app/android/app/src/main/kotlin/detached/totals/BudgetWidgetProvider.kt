package detached.totals

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.min
import kotlin.math.roundToInt

class BudgetWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val MAX_BUDGETS = 3
        private const val MATERIAL_ICONS_FONT_ASSET = "flutter_assets/fonts/MaterialIcons-Regular.otf"
        private const val ACTION_TOGGLE_BUDGET_PERIOD =
            "detached.totals.action.TOGGLE_BUDGET_PERIOD"
        private const val BUDGET_PERIOD_PREF_PREFIX = "budget_widget_period_"

        @Volatile
        private var materialIconsTypeface: Typeface? = null
    }

    private enum class BudgetPeriod(val storageValue: String) {
        MONTHLY("monthly"),
        WEEKLY("weekly");

        companion object {
            fun fromStorage(value: String?): BudgetPeriod {
                return values().firstOrNull { it.storageValue == value } ?: MONTHLY
            }
        }
    }

    private data class BudgetWidgetItem(
        val name: String,
        val compactValue: String,
        val expandedValue: String,
        val ringPercent: Double,
        val iconKey: String,
        val color: Int
    )

    private data class WidgetMode(
        val widthDp: Int,
        val heightDp: Int,
        val legendVisible: Boolean,
        val fractionVisible: Boolean,
        val periodToggleEnabled: Boolean
    )

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE_BUDGET_PERIOD) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val widgetId = intent.getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID
            )
            if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return

            val prefs = HomeWidgetPlugin.getData(context)
            val key = periodPreferenceKey(widgetId)
            val selectedPeriod = BudgetPeriod.fromStorage(prefs.getString(key, null))
            val nextPeriod = if (selectedPeriod == BudgetPeriod.MONTHLY) {
                BudgetPeriod.WEEKLY
            } else {
                BudgetPeriod.MONTHLY
            }

            prefs.edit().putString(key, nextPeriod.storageValue).apply()
            onUpdate(context, appWidgetManager, intArrayOf(widgetId), prefs)
            return
        }

        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val widgetIds = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
                ?: appWidgetManager.getAppWidgetIds(
                    android.content.ComponentName(context, BudgetWidgetProvider::class.java)
                )

            if (widgetIds.isNotEmpty()) {
                val prefs = HomeWidgetPlugin.getData(context)
                onUpdate(context, appWidgetManager, widgetIds, prefs)
            }
            return
        }

        super.onReceive(context, intent)
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
            val views = RemoteViews(context.packageName, R.layout.widget_budget_layout)
            val mode = resolveWidgetMode(appWidgetManager, widgetId)
            val selectedPeriod = if (mode.periodToggleEnabled) {
                loadSelectedPeriod(widgetData, widgetId)
            } else {
                BudgetPeriod.MONTHLY
            }
            val items = loadItems(widgetData, selectedPeriod)
            val emptyMessage = widgetData.getString(
                "budget_widget_empty_message",
                "Choose up to 3 budgets in Totals."
            ) ?: "Choose up to 3 budgets in Totals."

            bindClickAction(context, views, widgetId)
            applyResponsiveLayout(context, views, mode)
            bindPeriodToggle(context, views, widgetId, mode, selectedPeriod)

            if (items.isEmpty()) {
                views.setViewVisibility(R.id.budget_content_group, View.GONE)
                views.setViewVisibility(R.id.budget_empty_group, View.VISIBLE)
                views.setTextViewText(R.id.budget_empty_message, emptyMessage)
                appWidgetManager.updateAppWidget(widgetId, views)
                return@forEach
            }

            views.setViewVisibility(R.id.budget_content_group, View.VISIBLE)
            views.setViewVisibility(R.id.budget_empty_group, View.GONE)

            bindLegendRows(context, views, items, mode)

            createRingBitmap(context, mode, items, selectedPeriod)?.let { bitmap ->
                views.setImageViewBitmap(R.id.budget_ring_image, bitmap)
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
            ?: 140
        val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            .takeIf { it > 0 }
            ?: options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).takeIf { it > 0 }
            ?: 72

        val legendVisible = widthDp >= 176 && heightDp >= 58
        val fractionVisible = widthDp >= 300
        val periodToggleEnabled = true

        return WidgetMode(
            widthDp = widthDp,
            heightDp = heightDp,
            legendVisible = legendVisible,
            fractionVisible = fractionVisible,
            periodToggleEnabled = periodToggleEnabled
        )
    }

    private fun loadItems(
        widgetData: SharedPreferences,
        selectedPeriod: BudgetPeriod
    ): List<BudgetWidgetItem> {
        val items = mutableListOf<BudgetWidgetItem>()

        for (index in 0 until MAX_BUDGETS) {
            val prefix = "budget_item_$index"
            val budgetId = widgetData.getString("${prefix}_budget_id", "")?.trim().orEmpty()
            if (budgetId.isEmpty()) continue

            val name = widgetData.getString("${prefix}_name", "Budget") ?: "Budget"
            val compactValue = widgetData.getString(
                "${prefix}_${selectedPeriod.storageValue}_compact_value",
                null
            ) ?: widgetData.getString("${prefix}_compact_value", "0") ?: "0"
            val expandedValue = widgetData.getString(
                "${prefix}_${selectedPeriod.storageValue}_expanded_value",
                null
            ) ?: widgetData.getString("${prefix}_expanded_value", compactValue) ?: compactValue
            val ringPercent = (widgetData.getString(
                "${prefix}_${selectedPeriod.storageValue}_ring_percent",
                null
            ) ?: widgetData.getString("${prefix}_ring_percent", "0"))
                ?.toDoubleOrNull()
                ?.coerceIn(0.0, 100.0)
                ?: 0.0
            val iconKey = widgetData.getString("${prefix}_icon_key", "more_horiz")
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?: "more_horiz"
            val color = parseColorHex(widgetData.getString("${prefix}_color", null))

            items += BudgetWidgetItem(
                name = name,
                compactValue = compactValue,
                expandedValue = expandedValue,
                ringPercent = ringPercent,
                iconKey = iconKey,
                color = color
            )
        }

        return items
    }

    private fun loadSelectedPeriod(
        widgetData: SharedPreferences,
        widgetId: Int
    ): BudgetPeriod {
        return BudgetPeriod.fromStorage(
            widgetData.getString(
                periodPreferenceKey(widgetId),
                BudgetPeriod.MONTHLY.storageValue
            )
        )
    }

    private fun periodPreferenceKey(widgetId: Int): String {
        return "$BUDGET_PERIOD_PREF_PREFIX$widgetId"
    }

    private fun bindLegendRows(
        context: Context,
        views: RemoteViews,
        items: List<BudgetWidgetItem>,
        mode: WidgetMode
    ) {
        val rowIds = intArrayOf(
            R.id.budget_item_row_0,
            R.id.budget_item_row_1,
            R.id.budget_item_row_2
        )
        val iconIds = intArrayOf(
            R.id.budget_item_icon_0,
            R.id.budget_item_icon_1,
            R.id.budget_item_icon_2
        )
        val nameIds = intArrayOf(
            R.id.budget_item_name_0,
            R.id.budget_item_name_1,
            R.id.budget_item_name_2
        )
        val valueIds = intArrayOf(
            R.id.budget_item_value_0,
            R.id.budget_item_value_1,
            R.id.budget_item_value_2
        )

        views.setViewVisibility(
            R.id.budget_legend_group,
            if (mode.legendVisible) View.VISIBLE else View.GONE
        )
        val valueColor = ContextCompat.getColor(context, R.color.budget_widget_value)
        val subtleColor = ContextCompat.getColor(context, R.color.budget_widget_subtle)

        val valueTextSize = if (mode.fractionVisible) 14f else 13f

        for (index in 0 until MAX_BUDGETS) {
            val rowId = rowIds[index]
            val iconId = iconIds[index]
            val nameId = nameIds[index]
            val valueId = valueIds[index]

            if (!mode.legendVisible || index >= items.size) {
                views.setViewVisibility(rowId, View.GONE)
                continue
            }

            val item = items[index]
            views.setViewVisibility(rowId, View.VISIBLE)
            val iconBitmap = createLegendIconBitmap(
                context = context,
                iconKey = item.iconKey,
                color = item.color
            )
            if (iconBitmap != null) {
                views.setImageViewBitmap(iconId, iconBitmap)
            } else {
                views.setImageViewResource(iconId, resolveLegendIconRes(item.iconKey))
                views.setInt(iconId, "setColorFilter", item.color)
            }
            views.setTextViewText(
                valueId,
                if (mode.fractionVisible) {
                    createExpandedValueText(item.expandedValue, subtleColor)
                } else {
                    formatPercentText(item.ringPercent)
                }
            )
            views.setTextColor(nameId, valueColor)
            views.setTextColor(valueId, valueColor)
            views.setViewVisibility(nameId, View.GONE)
            views.setViewVisibility(valueId, View.VISIBLE)
            views.setTextViewTextSize(nameId, TypedValue.COMPLEX_UNIT_SP, valueTextSize)
            views.setTextViewTextSize(valueId, TypedValue.COMPLEX_UNIT_SP, valueTextSize)
        }
    }

    private fun bindPeriodToggle(
        context: Context,
        views: RemoteViews,
        widgetId: Int,
        mode: WidgetMode,
        selectedPeriod: BudgetPeriod
    ) {
        if (!mode.periodToggleEnabled) return

        val contentDescription =
            if (selectedPeriod == BudgetPeriod.MONTHLY) {
                "Monthly budget rings. Tap for weekly."
            } else {
                "Weekly budget rings. Tap for monthly."
            }
        views.setContentDescription(R.id.budget_ring_frame, contentDescription)
        views.setContentDescription(R.id.budget_ring_image, contentDescription)

        val periodTogglePendingIntent = createPeriodTogglePendingIntent(context, widgetId)
        views.setOnClickPendingIntent(
            R.id.budget_ring_frame,
            periodTogglePendingIntent
        )
        views.setOnClickPendingIntent(
            R.id.budget_ring_image,
            periodTogglePendingIntent
        )
    }

    private fun applyResponsiveLayout(
        context: Context,
        views: RemoteViews,
        mode: WidgetMode
    ) {
        val density = context.resources.displayMetrics.density
        val horizontalPadding = if (mode.legendVisible) 9 else 7
        val verticalPadding = if (mode.legendVisible) 7 else 6

        views.setViewPadding(
            R.id.widget_budget_root,
            (horizontalPadding * density).roundToInt(),
            (verticalPadding * density).roundToInt(),
            (horizontalPadding * density).roundToInt(),
            (verticalPadding * density).roundToInt()
        )
    }

    private fun bindClickAction(
        context: Context,
        views: RemoteViews,
        widgetId: Int
    ) {
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_LAUNCH_TARGET, MainActivity.TARGET_BUDGET)
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            context,
            widgetId + 9200,
            openAppIntent,
            pendingFlags
        )

        views.setOnClickPendingIntent(R.id.widget_budget_root, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.budget_empty_group, openAppPendingIntent)
    }

    private fun createPeriodTogglePendingIntent(
        context: Context,
        widgetId: Int
    ): PendingIntent {
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val intent = Intent(context, BudgetWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE_BUDGET_PERIOD
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }

        return PendingIntent.getBroadcast(
            context,
            widgetId + 9400,
            intent,
            pendingFlags
        )
    }

    private fun createRingBitmap(
        context: Context,
        mode: WidgetMode,
        items: List<BudgetWidgetItem>,
        selectedPeriod: BudgetPeriod
    ): Bitmap? {
        if (items.isEmpty()) return null

        val sizeDp = when {
            !mode.legendVisible -> (min(mode.widthDp, mode.heightDp) - 6).coerceIn(72, 98)
            mode.fractionVisible -> 82
            else -> 76
        }
        val density = context.resources.displayMetrics.density
        val sizePx = (sizeDp * density).roundToInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val center = sizePx / 2f
        val ringStrokeWidth = when (items.size) {
            1 -> sizePx * 0.16f
            2 -> sizePx * 0.12f
            else -> sizePx * 0.10f
        }
        val gap = ringStrokeWidth * 0.38f
        var radius = center - ringStrokeWidth / 2f - (sizePx * 0.03f)

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeWidth = ringStrokeWidth
        }
        val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeWidth = ringStrokeWidth
        }
        items.forEach { item ->
            if (radius <= ringStrokeWidth / 2f) return@forEach

            val rect = RectF(
                center - radius,
                center - radius,
                center + radius,
                center + radius
            )
            trackPaint.color = applyAlpha(item.color, 0.16f)
            ringPaint.color = item.color

            canvas.drawArc(rect, -90f, 360f, false, trackPaint)

            val sweep = ((item.ringPercent.coerceIn(0.0, 100.0) / 100.0) * 360.0).toFloat()
            if (sweep > 0.5f) {
                canvas.drawArc(rect, -90f, sweep, false, ringPaint)
            }

            radius -= ringStrokeWidth + gap
        }

        if (mode.periodToggleEnabled) {
            val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = ContextCompat.getColor(context, R.color.budget_widget_subtle)
                textAlign = Paint.Align.CENTER
                textSize = sizePx * 0.16f
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                style = Paint.Style.FILL
            }
            val label = if (selectedPeriod == BudgetPeriod.MONTHLY) "M" else "W"
            val baseline = center - ((labelPaint.descent() + labelPaint.ascent()) / 2f)
            canvas.drawText(label, center, baseline, labelPaint)
        }

        return bitmap
    }

    private fun parseColorHex(raw: String?): Int {
        if (raw.isNullOrBlank()) return Color.WHITE
        return try {
            Color.parseColor(raw)
        } catch (_: IllegalArgumentException) {
            Color.WHITE
        }
    }

    private fun createLegendIconBitmap(
        context: Context,
        iconKey: String,
        color: Int
    ): Bitmap? {
        val glyph = resolveLegendIconGlyph(iconKey) ?: return null
        val typeface = loadMaterialIconsTypeface(context) ?: return null
        val density = context.resources.displayMetrics.density
        val sizePx = (18f * density).roundToInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            textAlign = Paint.Align.CENTER
            textSize = sizePx * 0.95f
            this.typeface = typeface
            style = Paint.Style.FILL
        }
        val baseline = (sizePx / 2f) - ((paint.descent() + paint.ascent()) / 2f)
        canvas.drawText(glyph, sizePx / 2f, baseline, paint)
        return bitmap
    }

    private fun loadMaterialIconsTypeface(context: Context): Typeface? {
        materialIconsTypeface?.let { return it }
        return try {
            Typeface.createFromAsset(context.assets, MATERIAL_ICONS_FONT_ASSET).also {
                materialIconsTypeface = it
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun resolveLegendIconGlyph(iconKey: String?): String? {
        val codePoint = when (iconKey?.trim()) {
            "payments" -> 0xF0058
            "gift" -> 0xF61A
            "home" -> 0xF7F5
            "bolt" -> 0xF5CA
            "shopping_cart" -> 0xF0171
            "directions_car" -> 0xF6B3
            "restaurant" -> 0xF0108
            "checkroom" -> 0xF639
            "health" -> 0xF7DF
            "phone" -> 0xF0078
            "request_quote" -> 0xF0104
            "spa" -> 0xF01AD
            "more_horiz" -> 0xF8D9
            "savings" -> 0xF0128
            "flight" -> 0xF772
            "school" -> 0xF012E
            "sports_esports" -> 0xF01BC
            "pets" -> 0xF0077
            "movie" -> 0xF8E7
            "fitness_center" -> 0xF767
            "medical_services" -> 0xF8B0
            "local_gas_station" -> 0xF86D
            "celebration" -> 0xF625
            "subscriptions" -> 0xF01ED
            else -> return null
        }
        return String(Character.toChars(codePoint))
    }

    private fun resolveLegendIconRes(iconKey: String?): Int {
        return when (iconKey?.trim()) {
            "payments" -> android.R.drawable.ic_menu_save
            "gift" -> android.R.drawable.ic_menu_share
            "home" -> android.R.drawable.ic_menu_myplaces
            "bolt" -> android.R.drawable.ic_lock_idle_charging
            "shopping_cart" -> android.R.drawable.ic_menu_agenda
            "directions_car" -> android.R.drawable.ic_menu_directions
            "restaurant" -> android.R.drawable.ic_menu_slideshow
            "checkroom" -> android.R.drawable.ic_menu_crop
            "health" -> android.R.drawable.ic_menu_info_details
            "phone" -> android.R.drawable.ic_menu_call
            "request_quote" -> android.R.drawable.ic_menu_edit
            "spa" -> android.R.drawable.ic_menu_gallery
            "savings" -> android.R.drawable.ic_menu_save
            "flight" -> android.R.drawable.ic_menu_compass
            "school" -> android.R.drawable.ic_menu_info_details
            "sports_esports" -> android.R.drawable.ic_media_play
            "pets" -> android.R.drawable.ic_menu_myplaces
            "movie" -> android.R.drawable.ic_menu_slideshow
            "fitness_center" -> android.R.drawable.ic_menu_manage
            "medical_services" -> android.R.drawable.ic_menu_info_details
            "local_gas_station" -> android.R.drawable.ic_menu_directions
            "celebration" -> android.R.drawable.ic_menu_today
            "subscriptions" -> android.R.drawable.ic_menu_recent_history
            else -> android.R.drawable.ic_menu_more
        }
    }

    private fun applyAlpha(color: Int, factor: Float): Int {
        val alpha = (255 * factor).roundToInt().coerceIn(0, 255)
        return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
    }

    private fun formatPercentText(percent: Double): String {
        return "${percent.roundToInt()}%"
    }

    private fun createExpandedValueText(
        expandedValue: String,
        subtleColor: Int
    ): CharSequence {
        val normalizedValue = normalizeExpandedValueText(expandedValue)
        val slashIndex = normalizedValue.indexOf('/')
        if (slashIndex < 0 || slashIndex + 1 >= normalizedValue.length) {
            return normalizedValue
        }

        return SpannableString(normalizedValue).apply {
            setSpan(
                ForegroundColorSpan(subtleColor),
                slashIndex + 1,
                normalizedValue.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            setSpan(
                RelativeSizeSpan(0.9f),
                slashIndex + 1,
                normalizedValue.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    private fun normalizeExpandedValueText(expandedValue: String): String {
        val trimmedValue = expandedValue.trim()
        if (trimmedValue.isEmpty()) return expandedValue

        val slashIndex = trimmedValue.indexOf('/')
        val normalizedValue = if (slashIndex <= 0 || slashIndex + 1 >= trimmedValue.length) {
            trimmedValue
        } else {
            val left = trimmedValue.substring(0, slashIndex).trimEnd()
            val right = trimmedValue.substring(slashIndex + 1).trimStart()
            "$left /$right"
        }

        return normalizedValue.replace(Regex("\\betb\\b", RegexOption.IGNORE_CASE), "ETB")
    }
}
