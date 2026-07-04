import 'package:flutter/material.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/models/category.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/services/budget_service.dart';

class BudgetWidgetMetricSnapshot {
  final double spentRaw;
  final double amountRaw;
  final double percentUsed;
  final double ringPercent;
  final String compactValueLabel;
  final String expandedValueLabel;

  const BudgetWidgetMetricSnapshot({
    required this.spentRaw,
    required this.amountRaw,
    required this.percentUsed,
    required this.ringPercent,
    required this.compactValueLabel,
    required this.expandedValueLabel,
  });
}

class BudgetWidgetBudgetSnapshot {
  final int budgetId;
  final String name;
  final BudgetWidgetMetricSnapshot monthly;
  final BudgetWidgetMetricSnapshot weekly;
  final String defaultIconKey;
  final String defaultColorKey;
  final String colorHex;

  const BudgetWidgetBudgetSnapshot({
    required this.budgetId,
    required this.name,
    required this.monthly,
    required this.weekly,
    required this.defaultIconKey,
    required this.defaultColorKey,
    required this.colorHex,
  });

  double get amountRaw => monthly.amountRaw;
}

class BudgetWidgetPayload {
  final Map<int, BudgetWidgetBudgetSnapshot> budgetsById;
  final bool hasAnyBudgets;
  final String emptyMessage;
  final String lastUpdated;

  const BudgetWidgetPayload({
    required this.budgetsById,
    required this.hasAnyBudgets,
    required this.emptyMessage,
    required this.lastUpdated,
  });
}

class BudgetWidgetDataProvider {
  final BudgetService _budgetService;
  final CategoryRepository _categoryRepository;

  BudgetWidgetDataProvider({
    BudgetService? budgetService,
    CategoryRepository? categoryRepository,
  })  : _budgetService = budgetService ?? BudgetService(),
        _categoryRepository = categoryRepository ?? CategoryRepository();

  Future<BudgetWidgetPayload> getWidgetPayload({String? calendar}) async {
    final statuses = await _budgetService.getAllBudgetStatuses(
      calendar: calendar,
    );
    final visibleStatuses = statuses
        .where(
          (status) => status.budget.overlapsRange(
            status.periodStart,
            status.periodEnd,
          ),
        )
        .toList(growable: false);

    final categories = await _categoryRepository.getCategories();
    final categoryById = {
      for (final category in categories)
        if (category.id != null) category.id!: category,
    };

    final budgetsById = <int, BudgetWidgetBudgetSnapshot>{};
    for (final status in visibleStatuses) {
      final budgetId = status.budget.id;
      if (budgetId == null) continue;
      budgetsById[budgetId] = await _buildBudgetSnapshot(
        status: status,
        categoryById: categoryById,
      );
    }

    final hasAnyBudgets = budgetsById.isNotEmpty;

    return BudgetWidgetPayload(
      budgetsById: budgetsById,
      hasAnyBudgets: hasAnyBudgets,
      emptyMessage: hasAnyBudgets
          ? 'Choose up to 3 budgets in Totals.'
          : 'Create a budget to show it here.',
      lastUpdated: getLastUpdatedTimestamp(),
    );
  }

  Future<BudgetWidgetBudgetSnapshot> _buildBudgetSnapshot({
    required BudgetStatus status,
    required Map<int, Category> categoryById,
  }) async {
    final budget = status.budget;
    final defaultColorKey = _resolveBudgetColorKey(
      budget: budget,
      categoryById: categoryById,
    );
    final color = _colorFromKey(defaultColorKey);
    final defaultIconKey = _resolveBudgetIconKey(
      budget: budget,
      categoryById: categoryById,
    );
    final budgetName =
        budget.name.trim().isEmpty ? 'Budget' : budget.name.trim();
    final monthlyMetric = _buildMetricSnapshot(
      spent: status.spent,
      amount: budget.amount,
    );
    final weeklyMetric = await _buildWeeklyMetricSnapshot(status);

    return BudgetWidgetBudgetSnapshot(
      budgetId: budget.id!,
      name: budgetName,
      monthly: monthlyMetric,
      weekly: weeklyMetric,
      defaultIconKey: defaultIconKey,
      defaultColorKey: defaultColorKey,
      colorHex: _colorToHex(color),
    );
  }

  BudgetWidgetMetricSnapshot _buildMetricSnapshot({
    required double spent,
    required double amount,
  }) {
    final spentLabel = _formatMetricNumber(spent);
    final amountLabel = _formatMetricNumber(amount);
    final percentUsed = amount > 0 ? (spent / amount) * 100 : 0.0;

    return BudgetWidgetMetricSnapshot(
      spentRaw: spent,
      amountRaw: amount,
      percentUsed: percentUsed,
      ringPercent: percentUsed.clamp(0.0, 100.0).toDouble(),
      compactValueLabel: spentLabel,
      expandedValueLabel: '$spentLabel /$amountLabel ETB',
    );
  }

  Future<BudgetWidgetMetricSnapshot> _buildWeeklyMetricSnapshot(
    BudgetStatus status,
  ) async {
    final budget = status.budget;
    final weekRange = _currentWeekRangeWithinStatus(status);
    final spent = await _budgetService.calculateSpending(
      startDate: weekRange.start,
      endDate: weekRange.end,
      categoryId: budget.categoryId,
      categoryIds: budget.categoryIds,
    );
    final weeksInPeriod = _weeksInRange(status.periodStart, status.periodEnd);
    final amount = weeksInPeriod > 0 ? budget.amount / weeksInPeriod : 0.0;
    return _buildMetricSnapshot(spent: spent, amount: amount);
  }

  _BudgetWidgetDateRange _currentWeekRangeWithinStatus(BudgetStatus status) {
    final now = DateTime.now();
    final periodStart = _startOfDay(status.periodStart);
    final periodEnd = status.periodEnd;
    var start = _startOfWeek(now);
    if (start.isBefore(periodStart)) start = periodStart;

    var end = _endOfDay(start.add(const Duration(days: 6)));
    if (end.isAfter(periodEnd)) end = periodEnd;
    if (end.isBefore(start)) end = _endOfDay(start);

    return _BudgetWidgetDateRange(start: start, end: end);
  }

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  DateTime _startOfWeek(DateTime date) {
    final day = _startOfDay(date);
    return day.subtract(Duration(days: date.weekday - DateTime.monday));
  }

  int _weeksInRange(DateTime start, DateTime end) {
    final startDay = _startOfDay(start);
    final endDay = _startOfDay(end);
    final days = endDay.difference(startDay).inDays + 1;
    if (days <= 0) return 1;
    return (days + 6) ~/ 7;
  }

  String _resolveBudgetIconKey({
    required Budget budget,
    required Map<int, Category> categoryById,
  }) {
    final categories = budget.selectedCategoryIds
        .map((id) => categoryById[id])
        .whereType<Category>()
        .toList(growable: false);

    for (final category in categories) {
      final iconKey = _normalizeIconKey(category.iconKey);
      if (iconKey != null) return iconKey;
    }

    return _kDefaultBudgetWidgetIconKey;
  }

  String _resolveBudgetColorKey({
    required Budget budget,
    required Map<int, Category> categoryById,
  }) {
    final categories = budget.selectedCategoryIds
        .map((id) => categoryById[id])
        .whereType<Category>()
        .toList(growable: false);

    for (final category in categories) {
      final explicitColorKey = _normalizeWidgetColorKey(category.colorKey) ??
          _normalizeWidgetColorKey(_extractLegacyColorKey(category.iconKey));
      if (explicitColorKey != null) {
        return explicitColorKey;
      }
    }

    final seed = categories.isNotEmpty
        ? categories.map((category) => category.name).join('|')
        : budget.name;
    return _kBudgetWidgetFallbackColorKeys[
        _hashSeed(seed) % _kBudgetWidgetFallbackColorKeys.length];
  }

  String? _normalizeColorKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String? _extractLegacyColorKey(String? iconKey) {
    if (iconKey == null || iconKey.isEmpty) return null;
    const prefix = 'color:';
    if (!iconKey.startsWith(prefix)) return null;
    final value = iconKey.substring(prefix.length).trim();
    if (value.isEmpty) return null;
    return value;
  }

  String? _normalizeIconKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.startsWith('color:')) return null;
    if (!_kSupportedBudgetWidgetIconKeys.contains(trimmed)) return null;
    return trimmed;
  }

  String? _normalizeWidgetColorKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (!_kBudgetWidgetColors.containsKey(trimmed)) return null;
    return trimmed;
  }

  Color _colorFromKey(String colorKey) {
    return _kBudgetWidgetColors[colorKey] ?? _kBudgetWidgetPalette.first;
  }

  int _hashSeed(String value) {
    var hash = 0;
    for (final codeUnit in value.trim().toLowerCase().codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return hash;
  }

  String _formatMetricNumber(double amount) {
    final absolute = amount.abs();
    final sign = amount < 0 ? '-' : '';

    if (absolute >= 1000000) {
      final value = absolute / 1000000;
      return '$sign${_formatCompactDecimal(value)}M';
    }
    if (absolute >= 1000) {
      final value = absolute / 1000;
      return '$sign${_formatCompactDecimal(value)}K';
    }
    if (absolute >= 100) {
      return '$sign${absolute.round()}';
    }
    if (absolute == absolute.roundToDouble()) {
      return '$sign${absolute.toInt()}';
    }
    return '$sign${absolute.toStringAsFixed(1)}';
  }

  String _formatCompactDecimal(double value) {
    final formatted = value.toStringAsFixed(value >= 10 ? 0 : 1);
    return formatted.replaceFirst(RegExp(r'\.0$'), '');
  }

  String _colorToHex(Color color) {
    final red = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final green = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final blue = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#${(red + green + blue).toUpperCase()}';
  }

  String getLastUpdatedTimestamp() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$month/$day, $hour:$minute';
  }
}

class _BudgetWidgetDateRange {
  final DateTime start;
  final DateTime end;

  const _BudgetWidgetDateRange({
    required this.start,
    required this.end,
  });
}

const Map<String, Color> _kBudgetWidgetColors = {
  'mint': Color(0xFF34D399),
  'blue': Color(0xFF60A5FA),
  'pink': Color(0xFFEC4899),
  'violet': Color(0xFF8B7CF6),
  'amber': Color(0xFFF1B556),
  'teal': Color(0xFF2FB5A8),
  'orange': Color(0xFFF28C5B),
  'cyan': Color(0xFF46B8D9),
};

const String _kDefaultBudgetWidgetIconKey = 'more_horiz';

const Set<String> _kSupportedBudgetWidgetIconKeys = {
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

const List<String> _kBudgetWidgetFallbackColorKeys = [
  'mint',
  'blue',
  'pink',
  'violet',
  'amber',
  'teal',
  'orange',
  'cyan',
];

const List<Color> _kBudgetWidgetPalette = [
  Color(0xFF34D399),
  Color(0xFF60A5FA),
  Color(0xFFEC4899),
  Color(0xFF8B7CF6),
  Color(0xFFF1B556),
  Color(0xFF2FB5A8),
  Color(0xFFF28C5B),
  Color(0xFF46B8D9),
];
