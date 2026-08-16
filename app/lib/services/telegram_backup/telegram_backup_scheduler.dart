import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:totals/services/advanced_settings_service.dart';
import 'package:totals/services/telegram_backup/telegram_backup_models.dart';
import 'package:totals/services/telegram_backup/telegram_backup_settings_service.dart';

const String telegramBackupCheckTask = 'telegramBackupCheck';
const String telegramBackupCheckUniqueName = 'telegramBackupCheckUnique';
const String telegramBackupAfterSummaryUniqueName =
    'telegramBackupAfterSummaryUnique';

class TelegramBackupScheduler {
  TelegramBackupScheduler._();

  // WorkManager timing is intentionally treated as an opportunistic check.
  // The service applies the summary-time daily/weekly rule before exporting.
  @visibleForTesting
  static const Duration checkFrequency = Duration(minutes: 15);

  @visibleForTesting
  static const Duration initialDelay = Duration.zero;

  @visibleForTesting
  static const NetworkType requiredNetworkType = NetworkType.connected;

  @visibleForTesting
  static const ExistingPeriodicWorkPolicy existingWorkPolicy =
      ExistingPeriodicWorkPolicy.update;

  @visibleForTesting
  static const ExistingWorkPolicy summaryTriggerExistingWorkPolicy =
      ExistingWorkPolicy.keep;

  @visibleForTesting
  static const Duration summaryTriggerBackoff = Duration(minutes: 1);

  @visibleForTesting
  static const Map<String, dynamic> summaryTriggerInputData = <String, dynamic>{
    'trigger': 'summary',
    'skipSmsCatchup': true,
  };

  static Future<void> sync() async {
    if (kIsWeb) return;
    try {
      await AdvancedSettingsService.instance.ensureLoaded();
      await TelegramBackupSettingsService.instance.ensureLoaded();
      final featureEnabled =
          AdvancedSettingsService.instance.telegramBackupEnabled.value;
      final config = TelegramBackupSettingsService.instance.config.value;
      final shouldSchedule = featureEnabled &&
          config != null &&
          config.schedule != TelegramBackupSchedule.manual;

      if (!shouldSchedule) {
        await Workmanager().cancelByUniqueName(
          telegramBackupCheckUniqueName,
        );
        await Workmanager().cancelByUniqueName(
          telegramBackupAfterSummaryUniqueName,
        );
        return;
      }

      await TelegramBackupSettingsService.instance.ensureScheduleAnchor();
      await Workmanager().registerPeriodicTask(
        telegramBackupCheckUniqueName,
        telegramBackupCheckTask,
        existingWorkPolicy: existingWorkPolicy,
        frequency: checkFrequency,
        initialDelay: initialDelay,
        constraints: Constraints(
          networkType: requiredNetworkType,
        ),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'debug: Failed to sync Telegram backup schedule: $error',
        );
      }
    }
  }

  /// Requests a due backup immediately after a spending summary is delivered.
  ///
  /// This one-off task shares the periodic worker's durable due check and
  /// device lock, so overlapping periodic and summary-triggered runs cannot
  /// upload duplicate backups. A connected-network constraint lets the
  /// summary notification remain independent of internet availability.
  static Future<void> enqueueAfterSummary() async {
    if (kIsWeb) return;
    try {
      await Workmanager().registerOneOffTask(
        telegramBackupAfterSummaryUniqueName,
        telegramBackupCheckTask,
        inputData: summaryTriggerInputData,
        existingWorkPolicy: summaryTriggerExistingWorkPolicy,
        constraints: Constraints(networkType: requiredNetworkType),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: summaryTriggerBackoff,
        outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'debug: Failed to request Telegram backup after summary: $error',
        );
      }
    }
  }
}
