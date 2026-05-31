import 'dart:convert';

import 'package:totals/theme/app_calendar_option.dart';
import 'package:totals/utils/app_calendar_date_utils.dart';

class Budget {
  final int? id;
  final String name;
  final String type; // 'daily', 'monthly', 'yearly', 'category'
  final double amount;
  final int? categoryId;
  final List<int>? categoryIds;
  final DateTime startDate;
  final DateTime? endDate;
  final bool rollover;
  final double alertThreshold; // 0-100 percentage
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String?
      timeFrame; // 'daily', 'monthly', 'yearly', 'never' - for category budgets
  final String calendar;

  Budget({
    this.id,
    required this.name,
    required this.type,
    required this.amount,
    this.categoryId,
    this.categoryIds,
    required this.startDate,
    this.endDate,
    this.rollover = false,
    this.alertThreshold = 80.0,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
    this.timeFrame,
    this.calendar = 'gregorian',
  });

  static List<int>? _decodeCategoryIds(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      final parsed = raw
          .map((e) {
            if (e is int) return e;
            if (e is num) return e.toInt();
            if (e is String) return int.tryParse(e.trim());
            return null;
          })
          .whereType<int>()
          .toSet()
          .toList();
      return parsed.isEmpty ? null : parsed;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      try {
        final decoded = jsonDecode(trimmed);
        return _decodeCategoryIds(decoded);
      } catch (_) {
        final parsed = trimmed
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .whereType<int>()
            .toSet()
            .toList();
        return parsed.isEmpty ? null : parsed;
      }
    }
    return null;
  }

  factory Budget.fromDb(Map<String, dynamic> row) {
    return Budget(
      id: row['id'] as int?,
      name: (row['name'] as String?) ?? '',
      type: (row['type'] as String?) ?? 'monthly',
      amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
      categoryId: row['categoryId'] as int?,
      categoryIds: _decodeCategoryIds(row['categoryIds']),
      startDate: row['startDate'] != null
          ? DateTime.parse(row['startDate'] as String)
          : DateTime.now(),
      endDate: row['endDate'] != null
          ? DateTime.parse(row['endDate'] as String)
          : null,
      rollover: (row['rollover'] as int? ?? 0) == 1,
      alertThreshold: (row['alertThreshold'] as num?)?.toDouble() ?? 80.0,
      isActive: (row['isActive'] as int? ?? 1) == 1,
      createdAt: row['createdAt'] != null
          ? DateTime.parse(row['createdAt'] as String)
          : DateTime.now(),
      updatedAt: row['updatedAt'] != null
          ? DateTime.parse(row['updatedAt'] as String)
          : null,
      timeFrame: row['timeFrame'] as String?,
      calendar: (row['calendar'] as String?) ?? 'gregorian',
    );
  }

  factory Budget.fromJson(Map<String, dynamic> json) {
    bool toBool(dynamic value, {bool defaultValue = false}) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') return true;
        if (normalized == 'false' || normalized == '0') return false;
      }
      return defaultValue;
    }

    double toDouble(dynamic value, {double defaultValue = 0.0}) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value.trim()) ?? defaultValue;
      return defaultValue;
    }

    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    DateTime? parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String && value.trim().isNotEmpty) {
        try {
          return DateTime.parse(value);
        } catch (_) {
          return null;
        }
      }
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return null;
    }

    return Budget(
      id: toInt(json['id']),
      name: (json['name'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'monthly',
      amount: toDouble(json['amount']),
      categoryId: toInt(json['categoryId']),
      categoryIds: _decodeCategoryIds(json['categoryIds']),
      startDate: parseDate(json['startDate']) ?? DateTime.now(),
      endDate: parseDate(json['endDate']),
      rollover: toBool(json['rollover']),
      alertThreshold: toDouble(
        json['alertThreshold'],
        defaultValue: 80.0,
      ),
      isActive: toBool(json['isActive'], defaultValue: true),
      createdAt: parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: parseDate(json['updatedAt']),
      timeFrame: json['timeFrame'] as String?,
      calendar: (json['calendar'] as String?) ?? 'gregorian',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'type': type,
      'amount': amount,
      'categoryId': categoryId,
      'categoryIds': categoryIds,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'rollover': rollover,
      'alertThreshold': alertThreshold,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'timeFrame': timeFrame,
      'calendar': calendar,
    };
  }

  Map<String, dynamic> toDb() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'amount': amount,
      'categoryId': categoryId,
      'categoryIds': categoryIds == null || categoryIds!.isEmpty
          ? null
          : jsonEncode(categoryIds),
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'rollover': rollover ? 1 : 0,
      'alertThreshold': alertThreshold,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'timeFrame': timeFrame,
      'calendar': calendar,
    };
  }

  Budget copyWith({
    int? id,
    String? name,
    String? type,
    double? amount,
    int? categoryId,
    List<int>? categoryIds,
    DateTime? startDate,
    DateTime? endDate,
    bool? rollover,
    double? alertThreshold,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? timeFrame,
    String? calendar,
  }) {
    return Budget(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      categoryIds: categoryIds ?? this.categoryIds,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      rollover: rollover ?? this.rollover,
      alertThreshold: alertThreshold ?? this.alertThreshold,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      timeFrame: timeFrame ?? this.timeFrame,
      calendar: calendar ?? this.calendar,
    );
  }

  List<int> get selectedCategoryIds {
    final ids = <int>{};
    if (categoryIds != null) {
      ids.addAll(categoryIds!.where((id) => id > 0));
    }
    if (categoryId != null && categoryId! > 0) {
      ids.add(categoryId!);
    }
    return ids.toList(growable: false);
  }

  int? get primaryCategoryId {
    final ids = selectedCategoryIds;
    if (ids.isEmpty) return null;
    return ids.first;
  }

  bool get appliesToAllExpenses => selectedCategoryIds.isEmpty;

  bool includesCategory(int? id) {
    if (appliesToAllExpenses) return true;
    if (id == null) return false;
    return selectedCategoryIds.contains(id);
  }

  bool overlapsRange(DateTime rangeStart, DateTime rangeEnd) {
    final normalizedStart =
        DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final normalizedEnd = DateTime(
      rangeEnd.year,
      rangeEnd.month,
      rangeEnd.day,
      23,
      59,
      59,
      999,
    );

    final budgetStart = startDate;
    final budgetEnd = endDate;

    final startsAfterRange = budgetStart.isAfter(normalizedEnd);
    final endsBeforeRange =
        budgetEnd != null && budgetEnd.isBefore(normalizedStart);

    return !startsAfterRange && !endsBeforeRange;
  }

  AppCalendarOption get calendarOption =>
      AppCalendarOption.fromStorage(calendar);

  String get _currentPeriodFrame {
    if (type != 'category') return type;
    final frame = timeFrame ?? 'monthly';
    return frame == 'unlimited' ? 'never' : frame;
  }

  // Helper methods for period calculations
  DateTime getCurrentPeriodStart() {
    final frame = _currentPeriodFrame;
    if (frame == 'never') {
      return startDate;
    }
    return AppCalendarDateUtils.periodStart(
      DateTime.now(),
      frame,
      calendar: calendarOption,
    );
  }

  DateTime getCurrentPeriodEnd() {
    final start = getCurrentPeriodStart();
    final frame = _currentPeriodFrame;
    if (frame == 'never') {
      return endDate ?? DateTime(2100, 12, 31, 23, 59, 59);
    }
    return AppCalendarDateUtils.periodEndInclusive(
      start,
      frame,
      calendar: calendarOption,
    );
  }

  bool isDateInCurrentPeriod(DateTime date) {
    final start = getCurrentPeriodStart();
    final end = getCurrentPeriodEnd();
    return !date.isBefore(start) && !date.isAfter(end);
  }
}
