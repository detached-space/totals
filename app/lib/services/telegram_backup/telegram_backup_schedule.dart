import 'package:flutter/material.dart';
import 'package:totals/services/telegram_backup/telegram_backup_models.dart';

DateTime? telegramBackupBoundaryAtOrBefore({
  required TelegramBackupSchedule schedule,
  required DateTime now,
  required TimeOfDay summaryTime,
}) {
  if (schedule == TelegramBackupSchedule.manual) return null;

  final localNow = now.toLocal();
  if (schedule == TelegramBackupSchedule.daily) {
    var boundary = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      summaryTime.hour,
      summaryTime.minute,
    );
    if (boundary.isAfter(localNow)) {
      boundary = DateTime(
        localNow.year,
        localNow.month,
        localNow.day - 1,
        summaryTime.hour,
        summaryTime.minute,
      );
    }
    return boundary;
  }

  final daysSinceSunday = localNow.weekday % 7;
  var boundary = DateTime(
    localNow.year,
    localNow.month,
    localNow.day - daysSinceSunday,
    summaryTime.hour,
    summaryTime.minute,
  );
  if (boundary.isAfter(localNow)) {
    boundary = DateTime(
      boundary.year,
      boundary.month,
      boundary.day - 7,
      summaryTime.hour,
      summaryTime.minute,
    );
  }
  return boundary;
}

bool isTelegramBackupDue({
  required TelegramBackupConfig config,
  required DateTime now,
  required TimeOfDay summaryTime,
}) {
  final anchor = config.scheduleAnchorAt?.toLocal();
  if (anchor == null) return false;

  final boundary = telegramBackupBoundaryAtOrBefore(
    schedule: config.schedule,
    now: now,
    summaryTime: summaryTime,
  );
  if (boundary == null || !boundary.isAfter(anchor)) return false;

  final lastBackup = config.lastBackupAt?.toLocal();
  return lastBackup == null || lastBackup.isBefore(boundary);
}
