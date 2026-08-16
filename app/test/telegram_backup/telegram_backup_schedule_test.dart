import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/telegram_backup/telegram_backup_models.dart';
import 'package:totals/services/telegram_backup/telegram_backup_schedule.dart';

void main() {
  const summaryTime = TimeOfDay(hour: 20, minute: 0);

  TelegramBackupConfig config({
    required TelegramBackupSchedule schedule,
    required DateTime anchor,
    DateTime? lastBackup,
  }) {
    return TelegramBackupConfig(
      botId: '123',
      botUsername: 'totals_backup_bot',
      botDisplayName: 'Totals Backup',
      chatId: '456',
      chatDisplayName: 'Owner',
      catalogMessageId: 7,
      schedule: schedule,
      scheduleAnchorAt: anchor,
      lastBackupAt: lastBackup,
    );
  }

  test('daily backup waits for the first summary time after setup', () {
    final value = config(
      schedule: TelegramBackupSchedule.daily,
      anchor: DateTime(2026, 7, 24, 10),
    );

    expect(
      isTelegramBackupDue(
        config: value,
        now: DateTime(2026, 7, 24, 19, 59),
        summaryTime: summaryTime,
      ),
      isFalse,
    );
    expect(
      isTelegramBackupDue(
        config: value,
        now: DateTime(2026, 7, 24, 20),
        summaryTime: summaryTime,
      ),
      isTrue,
    );
  });

  test('daily backup catches up after a missed summary-time window', () {
    final value = config(
      schedule: TelegramBackupSchedule.daily,
      anchor: DateTime(2026, 7, 24, 19),
    );

    expect(
      isTelegramBackupDue(
        config: value,
        now: DateTime(2026, 7, 25, 9),
        summaryTime: summaryTime,
      ),
      isTrue,
    );
  });

  test('daily success suppresses repeats until the next summary time', () {
    final value = config(
      schedule: TelegramBackupSchedule.daily,
      anchor: DateTime(2026, 7, 24, 10),
      lastBackup: DateTime(2026, 7, 24, 20, 5),
    );

    expect(
      isTelegramBackupDue(
        config: value,
        now: DateTime(2026, 7, 25, 19, 59),
        summaryTime: summaryTime,
      ),
      isFalse,
    );
    expect(
      isTelegramBackupDue(
        config: value,
        now: DateTime(2026, 7, 25, 20),
        summaryTime: summaryTime,
      ),
      isTrue,
    );
  });

  test('weekly backup uses Sunday summary time and catches up on Monday', () {
    final value = config(
      schedule: TelegramBackupSchedule.weekly,
      anchor: DateTime(2026, 7, 24, 10),
    );

    expect(DateTime(2026, 7, 26).weekday, DateTime.sunday);
    expect(
      isTelegramBackupDue(
        config: value,
        now: DateTime(2026, 7, 26, 19, 59),
        summaryTime: summaryTime,
      ),
      isFalse,
    );
    expect(
      isTelegramBackupDue(
        config: value,
        now: DateTime(2026, 7, 27, 9),
        summaryTime: summaryTime,
      ),
      isTrue,
    );
  });

  test('weekly catch-up still allows the following Sunday backup', () {
    final value = config(
      schedule: TelegramBackupSchedule.weekly,
      anchor: DateTime(2026, 7, 24, 10),
      lastBackup: DateTime(2026, 7, 27, 9),
    );

    expect(
      isTelegramBackupDue(
        config: value,
        now: DateTime(2026, 8, 2, 20),
        summaryTime: summaryTime,
      ),
      isTrue,
    );
  });

  test('manual backups never become automatically due', () {
    final value = config(
      schedule: TelegramBackupSchedule.manual,
      anchor: DateTime(2026, 7, 24, 10),
    );

    expect(
      isTelegramBackupDue(
        config: value,
        now: DateTime(2026, 8, 2, 20),
        summaryTime: summaryTime,
      ),
      isFalse,
    );
  });
}
