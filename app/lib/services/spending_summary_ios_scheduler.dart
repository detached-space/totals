import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/widget_data_provider.dart';
import 'package:totals/utils/text_utils.dart';

/// Makes spending summaries reliable on iOS.
///
/// On Android a 15-minute workmanager loop checks "is it past the summary time
/// and not sent yet?" and fires. iOS runs background tasks opportunistically
/// (often only while charging/idle), so that loop alone misses the user's
/// chosen time. This scheduler, run on launch/resume/settings changes:
///
///  1. **Pre-arms** each enabled summary as an exact `zonedSchedule` local
///     notification at its next occurrence, carrying the latest totals — and
///     re-arms with fresher numbers every time it runs.
///  2. **Catches up** on foreground: if the time passed while nothing fired
///     (and nothing was armed), it shows the summary immediately.
///
/// Double-send safety: an "armed" marker records which period a pre-scheduled
/// notification covers. Both this scheduler and the background worker consult
/// the marker + the existing last-sent timestamps, so a period is delivered by
/// exactly one path. Markers are only written on iOS, so Android behavior is
/// unchanged.
class SpendingSummaryIosScheduler {
  SpendingSummaryIosScheduler._();
  static final SpendingSummaryIosScheduler instance =
      SpendingSummaryIosScheduler._();

  static const String _armedDailyKey = 'ios_summary_armed_daily';
  static const String _armedWeeklyKey = 'ios_summary_armed_weekly';
  static const String _armedMonthlyKey = 'ios_summary_armed_monthly';

  static bool get _isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  // Period helpers — mirror daily_spending_worker.dart (duplicated to avoid a
  // circular import; the worker imports this file for the armed markers).
  static bool _isWeeklySendDay(DateTime d) => d.weekday == DateTime.sunday;
  static DateTime _startOfWeek(DateTime d) {
    final startOfDay = DateTime(d.year, d.month, d.day);
    return startOfDay
        .subtract(Duration(days: startOfDay.weekday - DateTime.monday));
  }

  static DateTime _lastDayOfMonth(DateTime d) =>
      DateTime(d.year, d.month + 1, 0);
  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
  static String _monthKey(DateTime d) => '${d.year}-${d.month}';
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// True when a pre-armed notification covers today's daily summary — the
  /// worker then just marks it sent instead of showing a duplicate.
  static Future<bool> wasArmedForToday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_armedDailyKey) == _dayKey(DateTime.now());
  }

  static Future<bool> wasArmedForThisWeek() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_armedWeeklyKey) ==
        _dayKey(_startOfWeek(DateTime.now()));
  }

  static Future<bool> wasArmedForThisMonth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_armedMonthlyKey) == _monthKey(DateTime.now());
  }

  bool _running = false;

  Future<void> sync() async {
    if (!_isIos || _running) return;
    _running = true;
    try {
      final settings = NotificationSettingsService.instance;
      final notifications = NotificationService.instance;
      final provider = WidgetDataProvider();
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final time = await settings.getDailySummaryTime();
      DateTime at(DateTime day) =>
          DateTime(day.year, day.month, day.day, time.hour, time.minute);

      // ---- Daily -----------------------------------------------------------
      if (!await settings.isDailySummaryEnabled()) {
        await notifications.cancelScheduledSpendingSummary(
            NotificationService.dailySpendingNotificationId);
        await prefs.remove(_armedDailyKey);
      } else {
        final todayAt = at(now);
        final last = await settings.getDailySummaryLastSentAt();
        final sentToday = last != null && _sameDay(last, now);
        if (!sentToday && !now.isBefore(todayAt)) {
          if (prefs.getString(_armedDailyKey) == _dayKey(now)) {
            // The pre-armed notification fired for us while closed.
            await settings.setDailySummaryLastSentAt(now);
          } else {
            final amount = await provider.getTodaySpending();
            final shown = await notifications.showDailySpendingNotification(
                amount: amount);
            if (shown) await settings.setDailySummaryLastSentAt(now);
          }
        }

        final nextIsToday =
            now.isBefore(todayAt) && !(last != null && _sameDay(last, now));
        final next =
            nextIsToday ? todayAt : at(now.add(const Duration(days: 1)));
        final amount = nextIsToday ? await provider.getTodaySpending() : 0.0;
        await notifications.scheduleSpendingSummaryAt(
          id: NotificationService.dailySpendingNotificationId,
          title: "Today's spending",
          body: "You've spent ${formatNumberWithComma(amount)} ETB today.",
          when: next,
        );
        await prefs.setString(_armedDailyKey, _dayKey(next));
      }

      // ---- Weekly (Sundays, same clock time) -------------------------------
      if (!await settings.isWeeklySummaryEnabled()) {
        await notifications.cancelScheduledSpendingSummary(
            NotificationService.weeklySpendingNotificationId);
        await prefs.remove(_armedWeeklyKey);
      } else {
        final weekStartNow = _startOfWeek(now);
        final last = await settings.getWeeklySummaryLastSentAt();
        final sentThisWeek = last != null && !last.isBefore(weekStartNow);
        if (_isWeeklySendDay(now) &&
            !sentThisWeek &&
            !now.isBefore(at(now))) {
          if (prefs.getString(_armedWeeklyKey) == _dayKey(weekStartNow)) {
            await settings.setWeeklySummaryLastSentAt(now);
          } else {
            final amount = await provider.getCurrentWeekSpending(now: now);
            final shown = await notifications.showWeeklySpendingNotification(
                amount: amount);
            if (shown) await settings.setWeeklySummaryLastSentAt(now);
          }
        }

        var nextSunday = DateTime(now.year, now.month, now.day);
        if (!(_isWeeklySendDay(now) && !sentThisWeek && now.isBefore(at(now)))) {
          nextSunday = nextSunday.add(const Duration(days: 1));
          while (!_isWeeklySendDay(nextSunday)) {
            nextSunday = nextSunday.add(const Duration(days: 1));
          }
        }
        final sameWeek =
            _startOfWeek(nextSunday).isAtSameMomentAs(weekStartNow);
        final amount =
            sameWeek ? await provider.getCurrentWeekSpending(now: now) : 0.0;
        await notifications.scheduleSpendingSummaryAt(
          id: NotificationService.weeklySpendingNotificationId,
          title: "This week's spending",
          body: "You've spent ${formatNumberWithComma(amount)} ETB this week.",
          when: at(nextSunday),
        );
        await prefs.setString(
            _armedWeeklyKey, _dayKey(_startOfWeek(nextSunday)));
      }

      // ---- Monthly (last day of month, same clock time) --------------------
      if (!await settings.isMonthlySummaryEnabled()) {
        await notifications.cancelScheduledSpendingSummary(
            NotificationService.monthlySpendingNotificationId);
        await prefs.remove(_armedMonthlyKey);
      } else {
        final monthStart = DateTime(now.year, now.month, 1);
        final lastDay = _lastDayOfMonth(now);
        final last = await settings.getMonthlySummaryLastSentAt();
        final sentThisMonth = last != null && !last.isBefore(monthStart);
        final isSendDay = _sameDay(now, lastDay);
        if (isSendDay && !sentThisMonth && !now.isBefore(at(now))) {
          if (prefs.getString(_armedMonthlyKey) == _monthKey(now)) {
            await settings.setMonthlySummaryLastSentAt(now);
          } else {
            final amount = await provider.getCurrentMonthSpending(now: now);
            final shown = await notifications.showMonthlySpendingNotification(
                amount: amount);
            if (shown) await settings.setMonthlySummaryLastSentAt(now);
          }
        }

        final thisMonthDue = at(lastDay);
        final DateTime next;
        final bool sameMonth;
        if (!sentThisMonth && now.isBefore(thisMonthDue)) {
          next = thisMonthDue;
          sameMonth = true;
        } else {
          next = at(_lastDayOfMonth(DateTime(now.year, now.month + 1, 1)));
          sameMonth = false;
        }
        final amount =
            sameMonth ? await provider.getCurrentMonthSpending(now: now) : 0.0;
        await notifications.scheduleSpendingSummaryAt(
          id: NotificationService.monthlySpendingNotificationId,
          title: "This month's spending",
          body:
              "You've spent ${formatNumberWithComma(amount)} ETB this month.",
          when: next,
        );
        await prefs.setString(
            _armedMonthlyKey,
            sameMonth ? _monthKey(now) : _monthKey(next));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('debug: SpendingSummaryIosScheduler.sync failed: $e');
      }
    } finally {
      _running = false;
    }
  }
}
