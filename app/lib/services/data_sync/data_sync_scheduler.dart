import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:totals/background/daily_spending_worker.dart';
import 'package:totals/services/data_sync/data_sync_repository.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';

/// Registers (or cancels) the periodic WorkManager task that drains the Data
/// Sync outbox. Only scheduled when the feature is enabled AND at least one
/// rule opts into the periodic trigger, so disabled installs incur no
/// background work. Mirrors [WidgetRefreshScheduler].
class DataSyncScheduler {
  DataSyncScheduler._();

  // 15 min is the Android WorkManager floor for periodic tasks.
  static const Duration _frequency = Duration(minutes: 15);

  static Future<void> sync() async {
    if (kIsWeb) return;
    try {
      await DataSyncSettingsService.instance.ensureLoaded();
      final enabled = DataSyncSettingsService.instance.masterEnabled.value;
      final periodicRules =
          enabled ? await DataSyncRepository().countRulesWithPeriodicTrigger() : 0;

      if (enabled && periodicRules > 0) {
        await Workmanager().registerPeriodicTask(
          dataSyncDrainUniqueName,
          dataSyncDrainTask,
          existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
          frequency: _frequency,
          initialDelay: _frequency,
        );
      } else {
        await Workmanager().cancelByUniqueName(dataSyncDrainUniqueName);
      }
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to sync Data Sync schedule: $e');
      }
    }
  }
}
