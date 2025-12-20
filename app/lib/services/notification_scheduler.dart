import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:totals/background/daily_spending_worker.dart';
import 'package:totals/services/notification_settings_service.dart';

class NotificationScheduler {
  NotificationScheduler._();

  static const Duration _dailySummaryCheckFrequency = Duration(minutes: 15);

  static Future<void> syncDailySummarySchedule() async {
    if (kIsWeb) return;

    try {
      final enabled =
          await NotificationSettingsService.instance.isDailySummaryEnabled();

      if (!enabled) {
        await Workmanager().cancelByUniqueName(dailySpendingSummaryUniqueName);
        return;
      }

      await Workmanager().registerPeriodicTask(
        dailySpendingSummaryUniqueName,
        dailySpendingSummaryTask,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        frequency: _dailySummaryCheckFrequency,
        initialDelay: Duration.zero,
      );
    } catch (e) {
      // Ignore if not supported on the current platform.
      if (kDebugMode) {
        print('debug: Failed to sync daily summary schedule: $e');
      }
    }
  }
}
