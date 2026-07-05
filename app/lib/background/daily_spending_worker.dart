import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:workmanager/workmanager.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/shared_expense_background_notification_service.dart';
import 'package:totals/services/data_sync/sync_service.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/services/widget_data_provider.dart';
import 'package:totals/services/widget_refresh_settings_service.dart';
import 'package:totals/services/widget_refresh_state_service.dart';

const String dailySpendingSummaryTask = 'dailySpendingSummary';
const String dailySpendingSummaryUniqueName = 'dailySpendingSummaryUnique';
const String widgetMidnightRefreshTask = 'widgetMidnightRefresh';
const String widgetMidnightRefreshUniqueName = 'widgetMidnightRefreshUnique';
const String sharedExpenseNotificationCatchupTask =
    'sharedExpenseNotificationCatchup';
const String sharedExpenseNotificationCatchupUniqueName =
    'sharedExpenseNotificationCatchupUnique';
const String dataSyncDrainTask = 'dataSyncDrain';
const String dataSyncDrainUniqueName = 'dataSyncDrainUnique';
const String dataSyncImmediateDrainTask = 'dataSyncImmediateDrain';
const String dataSyncImmediateDrainUniqueName = 'dataSyncImmediateDrainUnique';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();

      if (task == widgetMidnightRefreshTask) {
        await WidgetService.initialize();
        final now = DateTime.now();
        final scheduledTime =
            await WidgetRefreshSettingsService.instance.getWidgetRefreshTime();
        final lastRefresh =
            await WidgetRefreshStateService.instance.getLastRefreshAt();
        if (!_isAfterOrEqualTimeOfDay(now, scheduledTime)) {
          return true;
        }
        if (lastRefresh != null && _isSameDay(lastRefresh, now)) {
          return true;
        }
        await WidgetService.refreshWidget();
        return true;
      }

      if (task == sharedExpenseNotificationCatchupTask) {
        await SharedExpenseBackgroundNotificationService.instance
            .sendMissedActivityDigestIfNeeded();
        return true;
      }

      if (task == dataSyncDrainTask || task == dataSyncImmediateDrainTask) {
        // requestDrain self-gates on the master flag (read from prefs here).
        final reason = inputData?['reason'] as String? ?? 'periodic';
        await SyncService.instance.requestDrain(reason: reason);
        return true;
      }

      if (task != dailySpendingSummaryTask) return true;

      final settings = NotificationSettingsService.instance;
      final smsService = SmsService();
      final spendingProvider = WidgetDataProvider();
      final scheduledTime = await settings.getDailySummaryTime();

      final now = DateTime.now();
      try {
        final catchupResult =
            await smsService.syncMissedBankSmsSinceLastCatchup();
        if (kDebugMode && catchupResult.added > 0) {
          debugPrint(
            'debug: Background SMS catch-up added '
            '${catchupResult.added} transaction(s)',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('debug: Background SMS catch-up failed: $e');
        }
      }

      if (!_isAfterOrEqualTimeOfDay(now, scheduledTime)) return true;

      final dailyEnabled = await settings.isDailySummaryEnabled();
      if (dailyEnabled) {
        final lastDailySent = await settings.getDailySummaryLastSentAt();
        if (lastDailySent == null || !_isSameDay(lastDailySent, now)) {
          final totalSpent = await spendingProvider.getTodaySpending();
          final shown =
              await NotificationService.instance.showDailySpendingNotification(
            amount: totalSpent,
          );
          if (shown) {
            await settings.setDailySummaryLastSentAt(now);
          }
        }
      }

      final weeklyEnabled = await settings.isWeeklySummaryEnabled();
      if (weeklyEnabled && isWeeklySummarySendDay(now)) {
        final currentWeekStart = _startOfWeek(now);
        final lastWeeklySent = await settings.getWeeklySummaryLastSentAt();
        final alreadySentThisWeek = lastWeeklySent != null &&
            !lastWeeklySent.isBefore(currentWeekStart);
        if (!alreadySentThisWeek) {
          final totalSpent = await spendingProvider.getCurrentWeekSpending(
            now: now,
          );
          final shown =
              await NotificationService.instance.showWeeklySpendingNotification(
            amount: totalSpent,
          );
          if (shown) {
            await settings.setWeeklySummaryLastSentAt(now);
          }
        }
      }

      final monthlyEnabled = await settings.isMonthlySummaryEnabled();
      if (monthlyEnabled && isMonthlySummarySendDay(now)) {
        final currentMonthStart = DateTime(now.year, now.month, 1);
        final lastMonthlySent = await settings.getMonthlySummaryLastSentAt();
        final alreadySentThisMonth = lastMonthlySent != null &&
            !lastMonthlySent.isBefore(currentMonthStart);
        if (!alreadySentThisMonth) {
          final totalSpent = await spendingProvider.getCurrentMonthSpending(
            now: now,
          );
          final shown = await NotificationService.instance
              .showMonthlySpendingNotification(
            amount: totalSpent,
          );
          if (shown) {
            await settings.setMonthlySummaryLastSentAt(now);
          }
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('debug: Daily spending worker failed: $e');
      }
      return true;
    }
  });
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isAfterOrEqualTimeOfDay(DateTime now, TimeOfDay time) {
  if (now.hour > time.hour) return true;
  if (now.hour < time.hour) return false;
  return now.minute >= time.minute;
}

@visibleForTesting
bool isWeeklySummarySendDay(DateTime date) {
  return date.weekday == DateTime.sunday;
}

@visibleForTesting
bool isMonthlySummarySendDay(DateTime date) {
  return date.day == _lastDayOfMonth(date).day;
}

DateTime _startOfWeek(DateTime date) {
  final startOfDay = DateTime(date.year, date.month, date.day);
  return startOfDay.subtract(Duration(days: date.weekday - DateTime.monday));
}

DateTime _lastDayOfMonth(DateTime date) {
  return DateTime(date.year, date.month + 1, 0);
}
