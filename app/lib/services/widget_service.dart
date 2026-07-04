import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/services/budget_widget_data_provider.dart';
import 'package:totals/services/widget_data_provider.dart';
import 'package:totals/services/widget_refresh_state_service.dart';
import 'package:totals/theme/app_calendar_option.dart';

class WidgetService {
  static const String appGroupId = 'group.detached.totals.widget';

  static const String expenseAndroidWidgetName = 'ExpenseWidgetProvider';
  static const String expenseAndroidWidgetQualifiedName =
      'detached.totals.$expenseAndroidWidgetName';

  static const String budgetAndroidWidgetName = 'BudgetWidgetProvider';
  static const String budgetAndroidWidgetQualifiedName =
      'detached.totals.$budgetAndroidWidgetName';
  static const int maxBudgetWidgetBudgets = 3;

  static const String _appCalendarKey = 'app_calendar';
  static const String _budgetWidgetSelectedIdsKey =
      'budget_widget_selected_ids';
  static const String _budgetWidgetSelectedCountKey =
      'budget_widget_selected_count';
  static const String _budgetWidgetEmptyMessageKey =
      'budget_widget_empty_message';
  static const String _budgetWidgetLastUpdatedKey =
      'budget_widget_last_updated';
  static const String _budgetWidgetStylesKey = 'budget_widget_styles';

  static WidgetDataProvider? _dataProvider;
  static BudgetWidgetDataProvider? _budgetDataProvider;

  static WidgetDataProvider get dataProvider {
    _dataProvider ??= WidgetDataProvider();
    return _dataProvider!;
  }

  static BudgetWidgetDataProvider get budgetDataProvider {
    _budgetDataProvider ??= BudgetWidgetDataProvider();
    return _budgetDataProvider!;
  }

  /// Initialize the widget plugin.
  static Future<void> initialize() async {
    await HomeWidget.setAppGroupId(appGroupId);
  }

  /// Refresh all home screen widgets.
  static Future<void> refreshWidget() async {
    await refreshAllWidgets();
  }

  /// Refresh all widgets and update global refresh timestamp.
  static Future<void> refreshAllWidgets() async {
    try {
      await _refreshExpenseWidget();
    } catch (e) {
      print('Error refreshing expense widget: $e');
    }

    await refreshBudgetWidget(updateRefreshState: false);
    await WidgetRefreshStateService.instance.setLastRefreshAt(DateTime.now());
  }

  static Future<void> _refreshExpenseWidget() async {
    final todaySpending = await dataProvider.getTodaySpending();
    final formattedAmount = dataProvider.formatAmountForWidget(todaySpending);
    final todayIncome = await dataProvider.getTodayIncome();
    final formattedIncome = dataProvider.formatAmountForWidget(todayIncome);
    final lastUpdated = dataProvider.getLastUpdatedTimestamp();
    final categories = await dataProvider.getTodayCategoryBreakdown();
    final incomeCategories =
        await dataProvider.getTodayIncomeCategoryBreakdown();

    await HomeWidget.saveWidgetData<String>('expense_total', formattedAmount);
    await HomeWidget.saveWidgetData<String>(
      'expense_total_raw',
      todaySpending.toString(),
    );
    await HomeWidget.saveWidgetData<String>(
        'expense_last_updated', lastUpdated);

    final categoryJson = jsonEncode(categories.map((c) => c.toJson()).toList());
    await HomeWidget.saveWidgetData<String>('expense_categories', categoryJson);

    await HomeWidget.saveWidgetData<String>('income_total', formattedIncome);
    await HomeWidget.saveWidgetData<String>(
      'income_total_raw',
      todayIncome.toString(),
    );
    await HomeWidget.saveWidgetData<String>('income_last_updated', lastUpdated);

    final incomeCategoryJson =
        jsonEncode(incomeCategories.map((c) => c.toJson()).toList());
    await HomeWidget.saveWidgetData<String>(
      'income_categories',
      incomeCategoryJson,
    );

    await _saveCategoryData(prefix: 'category', categories: categories);
    await _saveCategoryData(
        prefix: 'income_category', categories: incomeCategories);

    await HomeWidget.updateWidget(androidName: expenseAndroidWidgetName);

    print(
      'Expense widget updated: $formattedAmount / $formattedIncome at $lastUpdated',
    );
  }

  static Future<void> refreshBudgetWidget({
    String? calendar,
    bool updateRefreshState = true,
  }) async {
    try {
      final resolvedCalendar = await _resolveBudgetWidgetCalendar(calendar);
      final payload = await budgetDataProvider.getWidgetPayload(
        calendar: resolvedCalendar,
      );
      final selectedIds = await getBudgetWidgetSelectedIds(
        calendar: resolvedCalendar,
      );
      final stylesById = await getBudgetWidgetStylePreferences();
      final sanitizedIds = selectedIds
          .where(payload.budgetsById.containsKey)
          .take(maxBudgetWidgetBudgets)
          .toList(growable: false);
      final displayIds = _orderBudgetWidgetDisplayIds(
        selectedIds: sanitizedIds,
        payload: payload,
      );

      if (!_sameIds(selectedIds, sanitizedIds)) {
        await _saveBudgetWidgetSelectedIds(
          sanitizedIds,
          calendar: resolvedCalendar,
        );
      }

      await HomeWidget.saveWidgetData<String>(
        _budgetWidgetSelectedCountKey,
        sanitizedIds.length.toString(),
      );
      await HomeWidget.saveWidgetData<String>(
        _budgetWidgetEmptyMessageKey,
        sanitizedIds.isEmpty
            ? payload.emptyMessage
            : 'Choose up to $maxBudgetWidgetBudgets budgets in Totals.',
      );
      await HomeWidget.saveWidgetData<String>(
        _budgetWidgetLastUpdatedKey,
        payload.lastUpdated,
      );

      for (var index = 0; index < maxBudgetWidgetBudgets; index++) {
        final prefix = 'budget_item_$index';
        if (index < displayIds.length) {
          final snapshot = payload.budgetsById[displayIds[index]];
          if (snapshot != null) {
            final stylePreference = stylesById[snapshot.budgetId];
            final resolvedIconKey =
                _normalizeBudgetWidgetIconKey(stylePreference?.iconKey) ??
                    snapshot.defaultIconKey;
            final resolvedColorKey =
                _normalizeBudgetWidgetColorKey(stylePreference?.colorKey) ??
                    snapshot.defaultColorKey;
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_budget_id',
              snapshot.budgetId.toString(),
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_name',
              snapshot.name,
            );
            await _saveBudgetWidgetMetricData(
              prefix: prefix,
              period: 'monthly',
              metric: snapshot.monthly,
            );
            await _saveBudgetWidgetMetricData(
              prefix: prefix,
              period: 'weekly',
              metric: snapshot.weekly,
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_compact_value',
              snapshot.monthly.compactValueLabel,
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_expanded_value',
              snapshot.monthly.expandedValueLabel,
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_spent_raw',
              snapshot.monthly.spentRaw.toString(),
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_amount_raw',
              snapshot.monthly.amountRaw.toString(),
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_percent',
              snapshot.monthly.percentUsed.toString(),
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_ring_percent',
              snapshot.monthly.ringPercent.toString(),
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_icon_key',
              resolvedIconKey,
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_color',
              _budgetWidgetColorHexForKey(resolvedColorKey) ??
                  snapshot.colorHex,
            );
            continue;
          }
        }

        await HomeWidget.saveWidgetData<String>('${prefix}_budget_id', '');
        await HomeWidget.saveWidgetData<String>('${prefix}_name', '');
        await _clearBudgetWidgetMetricData(prefix: prefix, period: 'monthly');
        await _clearBudgetWidgetMetricData(prefix: prefix, period: 'weekly');
        await HomeWidget.saveWidgetData<String>('${prefix}_compact_value', '');
        await HomeWidget.saveWidgetData<String>('${prefix}_expanded_value', '');
        await HomeWidget.saveWidgetData<String>('${prefix}_spent_raw', '0');
        await HomeWidget.saveWidgetData<String>('${prefix}_amount_raw', '0');
        await HomeWidget.saveWidgetData<String>('${prefix}_percent', '0');
        await HomeWidget.saveWidgetData<String>('${prefix}_ring_percent', '0');
        await HomeWidget.saveWidgetData<String>('${prefix}_icon_key', '');
        await HomeWidget.saveWidgetData<String>('${prefix}_color', '');
      }

      await HomeWidget.updateWidget(
        qualifiedAndroidName: budgetAndroidWidgetQualifiedName,
      );

      if (updateRefreshState) {
        await WidgetRefreshStateService.instance
            .setLastRefreshAt(DateTime.now());
      }

      print('Budget widget updated');
    } catch (e) {
      print('Error updating budget widget: $e');
    }
  }

  static Future<void> _saveBudgetWidgetMetricData({
    required String prefix,
    required String period,
    required BudgetWidgetMetricSnapshot metric,
  }) async {
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_compact_value',
      metric.compactValueLabel,
    );
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_expanded_value',
      metric.expandedValueLabel,
    );
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_spent_raw',
      metric.spentRaw.toString(),
    );
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_amount_raw',
      metric.amountRaw.toString(),
    );
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_percent',
      metric.percentUsed.toString(),
    );
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_ring_percent',
      metric.ringPercent.toString(),
    );
  }

  static Future<void> _clearBudgetWidgetMetricData({
    required String prefix,
    required String period,
  }) async {
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_compact_value',
      '',
    );
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_expanded_value',
      '',
    );
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_spent_raw',
      '0',
    );
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_amount_raw',
      '0',
    );
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_percent',
      '0',
    );
    await HomeWidget.saveWidgetData<String>(
      '${prefix}_${period}_ring_percent',
      '0',
    );
  }

  static Future<void> _saveCategoryData({
    required String prefix,
    required List<CategoryExpense> categories,
  }) async {
    for (int i = 0; i < 3; i++) {
      if (i < categories.length) {
        final category = categories[i];
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_${i}_name',
          category.name,
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_${i}_amount',
          dataProvider.formatAmountForWidget(category.amount),
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_${i}_amount_raw',
          category.amount.toString(),
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_${i}_color',
          category.colorHex,
        );
      } else {
        await HomeWidget.saveWidgetData<String>('${prefix}_${i}_name', '');
        await HomeWidget.saveWidgetData<String>('${prefix}_${i}_amount', '');
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_${i}_amount_raw',
          '0',
        );
        await HomeWidget.saveWidgetData<String>('${prefix}_${i}_color', '');
      }
    }
  }

  /// Send basic expense data to the existing expense widget.
  static Future<void> updateWidgetData({
    required String totalAmount,
    required String lastUpdated,
  }) async {
    await HomeWidget.saveWidgetData<String>('expense_total', totalAmount);
    await HomeWidget.saveWidgetData<String>(
        'expense_last_updated', lastUpdated);
    await HomeWidget.updateWidget(
      qualifiedAndroidName: expenseAndroidWidgetQualifiedName,
    );
    await WidgetRefreshStateService.instance.setLastRefreshAt(DateTime.now());
  }

  static Future<List<int>> getBudgetWidgetSelectedIds({
    String? calendar,
  }) async {
    final resolvedCalendar = await _resolveBudgetWidgetCalendar(calendar);
    final scopedKey = _budgetWidgetSelectedIdsKeyForCalendar(resolvedCalendar);
    final raw = await HomeWidget.getWidgetData<String>(
      scopedKey,
    );
    if (raw != null) return _decodeIntList(raw);

    if (resolvedCalendar == AppCalendarOption.gregorian.storageValue) {
      final legacyRaw = await HomeWidget.getWidgetData<String>(
        _budgetWidgetSelectedIdsKey,
      );
      final legacyIds = _decodeIntList(legacyRaw);
      if (legacyRaw != null) {
        await _saveBudgetWidgetSelectedIds(
          legacyIds,
          calendar: resolvedCalendar,
        );
      }
      return legacyIds;
    }

    return _decodeIntList(raw);
  }

  static Future<BudgetWidgetStylePreference?> getBudgetWidgetStylePreference(
    int budgetId,
  ) async {
    final styles = await getBudgetWidgetStylePreferences();
    return styles[budgetId];
  }

  static Future<Map<int, BudgetWidgetStylePreference>>
      getBudgetWidgetStylePreferences() async {
    final raw = await HomeWidget.getWidgetData<String>(
      _budgetWidgetStylesKey,
      defaultValue: '{}',
    );
    return _decodeBudgetWidgetStyleMap(raw);
  }

  static Future<BudgetWidgetSelectionResult> addBudgetToWidget(
    int budgetId, {
    String? calendar,
    BudgetWidgetStylePreference? stylePreference,
  }) async {
    final resolvedCalendar = await _resolveBudgetWidgetCalendar(calendar);
    final selectedIds = await getBudgetWidgetSelectedIds(
      calendar: resolvedCalendar,
    );
    if (selectedIds.contains(budgetId)) {
      if (stylePreference != null) {
        await _saveBudgetWidgetStylePreference(budgetId, stylePreference);
      }
      await refreshBudgetWidget(calendar: resolvedCalendar);
      return BudgetWidgetSelectionResult.alreadySelected;
    }
    if (selectedIds.length >= maxBudgetWidgetBudgets) {
      return BudgetWidgetSelectionResult.limitReached;
    }

    if (stylePreference != null) {
      await _saveBudgetWidgetStylePreference(budgetId, stylePreference);
    }
    final nextIds = [...selectedIds, budgetId];
    await _saveBudgetWidgetSelectedIds(nextIds, calendar: resolvedCalendar);
    await refreshBudgetWidget(calendar: resolvedCalendar);
    return BudgetWidgetSelectionResult.added;
  }

  static Future<bool> removeBudgetFromWidget(
    int budgetId, {
    String? calendar,
  }) async {
    final resolvedCalendar = await _resolveBudgetWidgetCalendar(calendar);
    final selectedIds = await getBudgetWidgetSelectedIds(
      calendar: resolvedCalendar,
    );
    if (!selectedIds.contains(budgetId)) return false;

    final nextIds = selectedIds.where((id) => id != budgetId).toList();
    await _saveBudgetWidgetSelectedIds(nextIds, calendar: resolvedCalendar);
    await refreshBudgetWidget(calendar: resolvedCalendar);
    return true;
  }

  static bool _isInstalledBudgetWidget(HomeWidgetInfo widget) {
    final className = widget.androidClassName?.trim();
    return className == budgetAndroidWidgetQualifiedName ||
        className == budgetAndroidWidgetName ||
        className?.endsWith('.$budgetAndroidWidgetName') == true;
  }

  static List<int> _orderBudgetWidgetDisplayIds({
    required List<int> selectedIds,
    required BudgetWidgetPayload payload,
  }) {
    if (selectedIds.length <= 1) {
      return selectedIds;
    }

    final indexedIds = selectedIds.asMap().entries.toList(growable: false);
    indexedIds.sort((left, right) {
      final leftAmount = payload.budgetsById[left.value]?.amountRaw ?? 0;
      final rightAmount = payload.budgetsById[right.value]?.amountRaw ?? 0;
      final amountCompare = rightAmount.compareTo(leftAmount);
      if (amountCompare != 0) {
        return amountCompare;
      }
      return left.key.compareTo(right.key);
    });

    return indexedIds.map((entry) => entry.value).toList(growable: false);
  }

  static Future<void> _saveBudgetWidgetSelectedIds(
    List<int> ids, {
    String? calendar,
  }) async {
    final resolvedCalendar = await _resolveBudgetWidgetCalendar(calendar);
    final sanitized = ids
        .where((id) => id > 0)
        .toSet()
        .take(maxBudgetWidgetBudgets)
        .toList(growable: false);
    await HomeWidget.saveWidgetData<String>(
      _budgetWidgetSelectedIdsKeyForCalendar(resolvedCalendar),
      jsonEncode(sanitized),
    );
    if (resolvedCalendar == AppCalendarOption.gregorian.storageValue) {
      await HomeWidget.saveWidgetData<String>(
        _budgetWidgetSelectedIdsKey,
        jsonEncode(sanitized),
      );
    }
  }

  static Future<String> _resolveBudgetWidgetCalendar(String? calendar) async {
    if (calendar != null) {
      return AppCalendarOption.fromStorage(calendar).storageValue;
    }
    final prefs = await SharedPreferences.getInstance();
    return AppCalendarOption.fromStorage(prefs.getString(_appCalendarKey))
        .storageValue;
  }

  static String _budgetWidgetSelectedIdsKeyForCalendar(String calendar) {
    return '${_budgetWidgetSelectedIdsKey}_${AppCalendarOption.fromStorage(calendar).storageValue}';
  }

  static Future<void> _saveBudgetWidgetStylePreference(
    int budgetId,
    BudgetWidgetStylePreference stylePreference,
  ) async {
    if (budgetId <= 0) return;

    final normalizedIconKey =
        _normalizeBudgetWidgetIconKey(stylePreference.iconKey) ??
            _kDefaultBudgetWidgetIconKey;
    final normalizedColorKey =
        _normalizeBudgetWidgetColorKey(stylePreference.colorKey) ??
            _kDefaultBudgetWidgetColorKey;
    final current = await getBudgetWidgetStylePreferences();
    current[budgetId] = BudgetWidgetStylePreference(
      iconKey: normalizedIconKey,
      colorKey: normalizedColorKey,
    );

    await HomeWidget.saveWidgetData<String>(
      _budgetWidgetStylesKey,
      jsonEncode({
        for (final entry in current.entries)
          entry.key.toString(): entry.value.toJson(),
      }),
    );
  }

  static List<int> _decodeIntList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((value) {
            if (value is int) return value;
            if (value is num) return value.toInt();
            if (value is String) return int.tryParse(value.trim());
            return null;
          })
          .whereType<int>()
          .where((id) => id > 0)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Map<int, BudgetWidgetStylePreference> _decodeBudgetWidgetStyleMap(
    String? raw,
  ) {
    if (raw == null || raw.trim().isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};

      final styles = <int, BudgetWidgetStylePreference>{};
      decoded.forEach((key, value) {
        final budgetId = int.tryParse(key.toString());
        if (budgetId == null || budgetId <= 0 || value is! Map) return;

        final iconKey =
            _normalizeBudgetWidgetIconKey(value['iconKey']?.toString()) ??
                _kDefaultBudgetWidgetIconKey;
        final colorKey =
            _normalizeBudgetWidgetColorKey(value['colorKey']?.toString()) ??
                _kDefaultBudgetWidgetColorKey;

        styles[budgetId] = BudgetWidgetStylePreference(
          iconKey: iconKey,
          colorKey: colorKey,
        );
      });
      return styles;
    } catch (_) {
      return const {};
    }
  }

  static String? _normalizeBudgetWidgetIconKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (!_kBudgetWidgetSupportedIconKeys.contains(trimmed)) return null;
    return trimmed;
  }

  static String? _normalizeBudgetWidgetColorKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (!_kBudgetWidgetColorHexByKey.containsKey(trimmed)) return null;
    return trimmed;
  }

  static String? _budgetWidgetColorHexForKey(String? colorKey) {
    if (colorKey == null) return null;
    return _kBudgetWidgetColorHexByKey[colorKey];
  }

  static bool _sameIds(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

enum BudgetWidgetSelectionResult {
  added,
  alreadySelected,
  limitReached,
}

class BudgetWidgetStylePreference {
  final String iconKey;
  final String colorKey;

  const BudgetWidgetStylePreference({
    required this.iconKey,
    required this.colorKey,
  });

  Map<String, String> toJson() => {
        'iconKey': iconKey,
        'colorKey': colorKey,
      };
}

const String _kDefaultBudgetWidgetIconKey = 'more_horiz';
const String _kDefaultBudgetWidgetColorKey = 'mint';

const Set<String> _kBudgetWidgetSupportedIconKeys = {
  'payments',
  'gift',
  'home',
  'bolt',
  'shopping_cart',
  'directions_car',
  'restaurant',
  'checkroom',
  'health',
  'phone',
  'request_quote',
  'spa',
  'more_horiz',
  'savings',
  'flight',
  'school',
  'sports_esports',
  'pets',
  'movie',
  'fitness_center',
  'medical_services',
  'local_gas_station',
  'celebration',
  'subscriptions',
};

const Map<String, String> _kBudgetWidgetColorHexByKey = {
  'mint': '#34D399',
  'blue': '#60A5FA',
  'pink': '#EC4899',
  'violet': '#8B7CF6',
  'amber': '#F1B556',
  'teal': '#2FB5A8',
  'orange': '#F28C5B',
  'cyan': '#46B8D9',
};
