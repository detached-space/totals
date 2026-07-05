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
  static const Duration _immediateBackoff = Duration(minutes: 1);

  static Future<void> sync() async {
    if (kIsWeb) return;
    try {
      await DataSyncSettingsService.instance.ensureLoaded();
      final enabled = DataSyncSettingsService.instance.masterEnabled.value;
      final scheduledRules =
          enabled ? await DataSyncRepository().countRulesNeedingSchedule() : 0;

      if (enabled && scheduledRules > 0) {
        await Workmanager().registerPeriodicTask(
          dataSyncDrainUniqueName,
          dataSyncDrainTask,
          existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
          frequency: _frequency,
          // Zero, not _frequency: sync() runs on every app launch and rule
          // edit, and `replace` re-registers the task each time. A non-zero
          // initial delay would push the first run 15 min out on every launch,
          // so frequent app opens would defer the scheduled drain forever.
          // Mirrors NotificationScheduler / WidgetRefreshScheduler.
          initialDelay: Duration.zero,
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

  static Future<void> requestImmediateDrain({
    String reason = 'manual',
    Duration initialDelay = Duration.zero,
  }) async {
    if (kIsWeb) return;
    try {
      await DataSyncSettingsService.instance.ensureLoaded();
      if (!DataSyncSettingsService.instance.masterEnabled.value) return;
      await Workmanager().registerOneOffTask(
        dataSyncImmediateDrainUniqueName,
        dataSyncImmediateDrainTask,
        inputData: {'reason': reason},
        existingWorkPolicy: ExistingWorkPolicy.keep,
        initialDelay: initialDelay,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: _immediateBackoff,
        outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to request immediate Data Sync drain: $e');
      }
    }
  }
}
