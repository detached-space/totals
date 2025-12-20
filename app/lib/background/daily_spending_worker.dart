import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:workmanager/workmanager.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_settings_service.dart';

const String dailySpendingSummaryTask = 'dailySpendingSummary';
const String dailySpendingSummaryUniqueName = 'dailySpendingSummaryUnique';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();

      if (task != dailySpendingSummaryTask) return true;

      final settings = NotificationSettingsService.instance;

      final enabled = await settings.isDailySummaryEnabled();
      if (!enabled) return true;

      final now = DateTime.now();

      final scheduledTime = await settings.getDailySummaryTime();
      if (!_isAfterOrEqualTimeOfDay(now, scheduledTime)) return true;

      final lastSent = await settings.getDailySummaryLastSentAt();
      if (lastSent != null && _isSameDay(lastSent, now)) return true;

      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

      final txRepo = TransactionRepository();
      final debits = await txRepo.getTransactionsByDateRange(
        start,
        end,
        type: 'DEBIT',
      );

      final totalSpent = debits.fold<double>(0.0, (sum, t) => sum + t.amount);
      final shown = await NotificationService.instance.showDailySpendingNotification(
        amount: totalSpent,
      );

      if (shown) {
        await settings.setDailySummaryLastSentAt(now);
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('debug: Daily spending worker failed: $e');
      }
      return true;
    }
  });
}

Duration initialDelayUntil(TimeOfDay time) {
  final now = DateTime.now();
  var scheduled =
      DateTime(now.year, now.month, now.day, time.hour, time.minute);
  if (!scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled.difference(now);
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isAfterOrEqualTimeOfDay(DateTime now, TimeOfDay time) {
  if (now.hour > time.hour) return true;
  if (now.hour < time.hour) return false;
  return now.minute >= time.minute;
}
