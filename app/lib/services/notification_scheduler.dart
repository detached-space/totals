import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:totals/background/daily_spending_worker.dart';
import 'package:totals/services/notification_settings_service.dart';

class NotificationScheduler {
  NotificationScheduler._();

  static const Duration _summaryCheckFrequency = Duration(minutes: 15);
  static const Duration _sharedExpenseCheckFrequency = Duration(minutes: 15);

  static Future<void> syncSpendingSummarySchedule() async {
    if (kIsWeb) return;

    try {
      final enabled = await NotificationSettingsService.instance
          .isAnySpendingSummaryEnabled();

      if (!enabled) {
        await Workmanager().cancelByUniqueName(dailySpendingSummaryUniqueName);
        return;
      }

      await Workmanager().registerPeriodicTask(
        dailySpendingSummaryUniqueName,
        dailySpendingSummaryTask,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        frequency: _summaryCheckFrequency,
        initialDelay: Duration.zero,
      );
    } catch (e) {
      // Ignore if not supported on the current platform.
      if (kDebugMode) {
        print('debug: Failed to sync spending summary schedule: $e');
      }
    }
  }

  static Future<void> syncSharedExpenseNotificationSchedule() async {
    if (kIsWeb) return;

    try {
      final enabled = await NotificationSettingsService.instance
          .isSharedExpenseNotificationsEnabled();

      if (!enabled) {
        await Workmanager()
            .cancelByUniqueName(sharedExpenseNotificationCatchupUniqueName);
        return;
      }

      await Workmanager().registerPeriodicTask(
        sharedExpenseNotificationCatchupUniqueName,
        sharedExpenseNotificationCatchupTask,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        frequency: _sharedExpenseCheckFrequency,
        initialDelay: Duration.zero,
      );
    } catch (e) {
      // Ignore if not supported on the current platform.
      if (kDebugMode) {
        print('debug: Failed to sync shared expense notification schedule: $e');
      }
    }
  }
}
