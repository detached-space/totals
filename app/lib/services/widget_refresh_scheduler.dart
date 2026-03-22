import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:totals/background/daily_spending_worker.dart';

class WidgetRefreshScheduler {
  WidgetRefreshScheduler._();

  static const Duration _refreshCheckFrequency = Duration(minutes: 30);

  static Future<void> syncWidgetRefreshSchedule() async {
    if (kIsWeb) return;

    try {
      await Workmanager().registerPeriodicTask(
        widgetMidnightRefreshUniqueName,
        widgetMidnightRefreshTask,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        frequency: _refreshCheckFrequency,
        initialDelay: Duration.zero,
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to sync widget refresh schedule: $e');
      }
    }
  }
}
