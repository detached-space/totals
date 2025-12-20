import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsService {
  NotificationSettingsService._();

  static final NotificationSettingsService instance =
      NotificationSettingsService._();

  static const _kTransactionEnabled = 'notifications_transaction_enabled';
  static const _kDailyEnabled = 'notifications_daily_enabled';
  static const _kDailyHour = 'notifications_daily_hour';
  static const _kDailyMinute = 'notifications_daily_minute';
  static const _kDailyLastSentEpochMs = 'notifications_daily_last_sent_epoch_ms';

  Future<bool> isTransactionNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kTransactionEnabled) ?? true;
  }

  Future<void> setTransactionNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTransactionEnabled, enabled);
  }

  Future<bool> isDailySummaryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDailyEnabled) ?? true;
  }

  Future<void> setDailySummaryEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDailyEnabled, enabled);
  }

  Future<TimeOfDay> getDailySummaryTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_kDailyHour) ?? 20;
    final minute = prefs.getInt(_kDailyMinute) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> setDailySummaryTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDailyHour, time.hour);
    await prefs.setInt(_kDailyMinute, time.minute);
  }

  Future<DateTime?> getDailySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kDailyLastSentEpochMs);
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> setDailySummaryLastSentAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDailyLastSentEpochMs, time.millisecondsSinceEpoch);
  }

  Future<void> clearDailySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDailyLastSentEpochMs);
  }
}
