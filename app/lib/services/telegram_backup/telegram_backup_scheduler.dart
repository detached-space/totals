import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:totals/background/daily_spending_worker.dart';
import 'package:totals/services/advanced_settings_service.dart';
import 'package:totals/services/telegram_backup/telegram_backup_models.dart';
import 'package:totals/services/telegram_backup/telegram_backup_settings_service.dart';

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
}
