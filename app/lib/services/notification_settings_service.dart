import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/repositories/category_repository.dart';

class NotificationSettingsService {
  NotificationSettingsService._();

  static final NotificationSettingsService instance =
      NotificationSettingsService._();

  static const _kTransactionEnabled = 'notifications_transaction_enabled';
  static const _kFailedParseReviewEnabled =
      'notifications_failed_parse_review_enabled';
  static const _kBudgetEnabled = 'notifications_budget_enabled';
  static const _kSharedExpensesEnabled =
      'notifications_shared_expenses_enabled';
  static const _kLoanDebtReturnRemindersEnabled =
      'notifications_loan_debt_return_reminders_enabled';
  static const _kDailyEnabled = 'notifications_daily_enabled';
  static const _kDailyHour = 'notifications_daily_hour';
  static const _kDailyMinute = 'notifications_daily_minute';
  static const _kDailyLastSentEpochMs =
      'notifications_daily_last_sent_epoch_ms';
  static const _kWeeklyEnabled = 'notifications_weekly_enabled';
  static const _kWeeklyLastSentEpochMs =
      'notifications_weekly_last_sent_epoch_ms';
  static const _kMonthlyEnabled = 'notifications_monthly_enabled';
  static const _kMonthlyLastSentEpochMs =
      'notifications_monthly_last_sent_epoch_ms';
  static const _kAutoCategorizeReceiverEnabled =
      'auto_categorize_receiver_enabled';
  static const _kQuickCategorizeIncomeIds = 'quick_categorize_income_ids';
  static const _kQuickCategorizeExpenseIds = 'quick_categorize_expense_ids';
  static const List<String> _kDefaultQuickIncomeBuiltInKeys = [
    'income_salary',
    'income_business',
    'income_side_hustle',
  ];
  static const List<String> _kDefaultQuickExpenseBuiltInKeys = [
    'expense_groceries',
    'expense_transport',
    'expense_airtime',
  ];

  Future<bool> isTransactionNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kTransactionEnabled) ?? true;
  }

  Future<void> setTransactionNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTransactionEnabled, enabled);
  }

  Future<bool> isFailedParseReviewNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kFailedParseReviewEnabled) ?? true;
  }

  Future<void> setFailedParseReviewNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFailedParseReviewEnabled, enabled);
  }

  Future<bool> isBudgetAlertsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBudgetEnabled) ?? true;
  }

  Future<void> setBudgetAlertsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBudgetEnabled, enabled);
  }

  Future<bool> isSharedExpenseNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSharedExpensesEnabled) ?? true;
  }

  Future<void> setSharedExpenseNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSharedExpensesEnabled, enabled);
  }

  Future<bool> isLoanDebtReturnRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kLoanDebtReturnRemindersEnabled) ?? true;
  }

  Future<void> setLoanDebtReturnRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoanDebtReturnRemindersEnabled, enabled);
  }

  Future<bool> isDailySummaryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDailyEnabled) ?? true;
  }

  Future<void> setDailySummaryEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDailyEnabled, enabled);
  }

  Future<TimeOfDay> getDailySummaryTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_kDailyHour) ?? 20;
    final minute = prefs.getInt(_kDailyMinute) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> setDailySummaryTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDailyHour, time.hour);
    await prefs.setInt(_kDailyMinute, time.minute);
  }

  Future<DateTime?> getDailySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kDailyLastSentEpochMs);
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> setDailySummaryLastSentAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDailyLastSentEpochMs, time.millisecondsSinceEpoch);
  }

  Future<void> clearDailySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDailyLastSentEpochMs);
  }

  Future<bool> isWeeklySummaryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kWeeklyEnabled) ?? false;
  }

  Future<void> setWeeklySummaryEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWeeklyEnabled, enabled);
  }

  Future<DateTime?> getWeeklySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kWeeklyLastSentEpochMs);
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> setWeeklySummaryLastSentAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWeeklyLastSentEpochMs, time.millisecondsSinceEpoch);
  }

  Future<void> clearWeeklySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kWeeklyLastSentEpochMs);
  }

  Future<bool> isMonthlySummaryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kMonthlyEnabled) ?? false;
  }

  Future<void> setMonthlySummaryEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMonthlyEnabled, enabled);
  }

  Future<DateTime?> getMonthlySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kMonthlyLastSentEpochMs);
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> setMonthlySummaryLastSentAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMonthlyLastSentEpochMs, time.millisecondsSinceEpoch);
  }

  Future<void> clearMonthlySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMonthlyLastSentEpochMs);
  }

  Future<bool> isAnySpendingSummaryEnabled() async {
    return await isDailySummaryEnabled() ||
        await isWeeklySummaryEnabled() ||
        await isMonthlySummaryEnabled();
  }

  Future<bool> isAutoCategorizationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoCategorizeReceiverEnabled) ?? true;
  }

  Future<void> setAutoCategorizationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoCategorizeReceiverEnabled, enabled);
  }

  Future<bool> isAutoCategorizeByReceiverEnabled() async {
    return isAutoCategorizationEnabled();
  }

  Future<void> setAutoCategorizeByReceiverEnabled(bool enabled) async {
    await setAutoCategorizationEnabled(enabled);
  }

  Future<List<int>> getQuickCategorizeIncomeIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kQuickCategorizeIncomeIds);
    if (raw == null) {
      final defaults = await _resolveDefaultQuickCategorizeIds(flow: 'income');
      await prefs.setStringList(
        _kQuickCategorizeIncomeIds,
        defaults.map((id) => id.toString()).toList(),
      );
      return defaults;
    }
    return raw.map((s) => int.tryParse(s)).whereType<int>().toList();
  }

  Future<void> setQuickCategorizeIncomeIds(List<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final limited = ids.take(3).toList();
    await prefs.setStringList(
      _kQuickCategorizeIncomeIds,
      limited.map((id) => id.toString()).toList(),
    );
  }

  Future<List<int>> getQuickCategorizeExpenseIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kQuickCategorizeExpenseIds);
    if (raw == null) {
      final defaults = await _resolveDefaultQuickCategorizeIds(flow: 'expense');
      await prefs.setStringList(
        _kQuickCategorizeExpenseIds,
        defaults.map((id) => id.toString()).toList(),
      );
      return defaults;
    }
    return raw.map((s) => int.tryParse(s)).whereType<int>().toList();
  }

  Future<void> setQuickCategorizeExpenseIds(List<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final limited = ids.take(3).toList();
    await prefs.setStringList(
      _kQuickCategorizeExpenseIds,
      limited.map((id) => id.toString()).toList(),
    );
  }

  Future<List<int>> _resolveDefaultQuickCategorizeIds({
    required String flow,
  }) async {
    final preferredKeys = flow == 'income'
        ? _kDefaultQuickIncomeBuiltInKeys
        : _kDefaultQuickExpenseBuiltInKeys;
    final categories = await CategoryRepository().getCategories();
    final eligible = categories
        .where(
          (category) =>
              category.id != null &&
              category.flow.toLowerCase() == flow &&
              !category.uncategorized,
        )
        .toList(growable: false);

    final defaults = <int>[];
    for (final builtInKey in preferredKeys) {
      final match = eligible
          .where((category) => category.builtInKey == builtInKey)
          .firstOrNull;
      final id = match?.id;
      if (id != null && !defaults.contains(id)) {
        defaults.add(id);
      }
    }

    if (defaults.length < 3) {
      for (final category in eligible) {
        final id = category.id;
        if (id == null || defaults.contains(id)) continue;
        defaults.add(id);
        if (defaults.length >= 3) break;
      }
    }

    return defaults.take(3).toList(growable: false);
  }
}
