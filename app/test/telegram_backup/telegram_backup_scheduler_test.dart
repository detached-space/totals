import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/telegram_backup/telegram_backup_scheduler.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  test('scheduled Telegram backups accept any connected network', () {
    expect(
      TelegramBackupScheduler.requiredNetworkType,
      NetworkType.connected,
    );
    expect(
      TelegramBackupScheduler.requiredNetworkType,
      isNot(NetworkType.unmetered),
    );
  });

  test('scheduled Telegram backups preserve their cadence across app launches',
      () {
    expect(
      TelegramBackupScheduler.checkFrequency,
      const Duration(minutes: 15),
    );
    expect(TelegramBackupScheduler.initialDelay, Duration.zero);
    expect(
      TelegramBackupScheduler.existingWorkPolicy,
      ExistingPeriodicWorkPolicy.update,
    );
  });

  test('summary-triggered backups wait for a network and deduplicate requests',
      () {
    expect(
      TelegramBackupScheduler.requiredNetworkType,
      NetworkType.connected,
    );
    expect(
      TelegramBackupScheduler.summaryTriggerExistingWorkPolicy,
      ExistingWorkPolicy.keep,
    );
    expect(
      TelegramBackupScheduler.summaryTriggerInputData,
      <String, dynamic>{
        'trigger': 'summary',
        'skipSmsCatchup': true,
      },
    );
    expect(
      TelegramBackupScheduler.summaryTriggerBackoff,
      const Duration(minutes: 1),
    );
  });
}
