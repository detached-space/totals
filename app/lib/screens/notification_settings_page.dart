import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_scheduler.dart';
import 'package:totals/services/notification_settings_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _loading = true;
  bool _transactionEnabled = true;
  bool _dailyEnabled = true;
  TimeOfDay _dailyTime = const TimeOfDay(hour: 20, minute: 0);
  DateTime? _lastDailySummarySentAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = NotificationSettingsService.instance;
    final tx = await settings.isTransactionNotificationsEnabled();
    final daily = await settings.isDailySummaryEnabled();
    final time = await settings.getDailySummaryTime();
    final lastSent = await settings.getDailySummaryLastSentAt();
    if (!mounted) return;
    setState(() {
      _transactionEnabled = tx;
      _dailyEnabled = daily;
      _dailyTime = time;
      _lastDailySummarySentAt = lastSent;
      _loading = false;
    });
  }

  Future<void> _setTransactionEnabled(bool value) async {
    setState(() => _transactionEnabled = value);
    await NotificationSettingsService.instance
        .setTransactionNotificationsEnabled(value);
  }

  Future<void> _setDailyEnabled(bool value) async {
    setState(() => _dailyEnabled = value);
    await NotificationSettingsService.instance.setDailySummaryEnabled(value);
    await NotificationScheduler.syncDailySummarySchedule();
    await _load();
  }

  Future<void> _pickDailyTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dailyTime,
    );
    if (picked == null) return;
    setState(() => _dailyTime = picked);
    await NotificationSettingsService.instance.setDailySummaryTime(picked);
    await NotificationScheduler.syncDailySummarySchedule();
    await _load();
  }

  Future<void> _sendTestDailySummary() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

      final txRepo = TransactionRepository();
      final debits = await txRepo.getTransactionsByDateRange(
        start,
        end,
        type: 'DEBIT',
      );
      final totalSpent = debits.fold<double>(0.0, (sum, t) => sum + t.amount);
      final shown =
          await NotificationService.instance.showDailySpendingTestNotification(
        amount: totalSpent,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shown
                ? 'Test summary notification sent'
                : 'Unable to send notification',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send test notification')),
      );
    }
  }

  String _nextDailySummaryLabel(BuildContext context) {
    final now = DateTime.now();
    final last = _lastDailySummarySentAt;
    final sentToday = last != null && _isSameDay(last, now);

    final scheduledToday = DateTime(
        now.year, now.month, now.day, _dailyTime.hour, _dailyTime.minute);

    if (sentToday) {
      final tomorrow = scheduledToday.add(const Duration(days: 1));
      final timeLabel = TimeOfDay.fromDateTime(tomorrow).format(context);
      return 'Tomorrow at $timeLabel';
    }

    if (scheduledToday.isAfter(now)) {
      return 'Today at ${_dailyTime.format(context)}';
    }

    return 'Sending soon';
  }

  String _lastDailySummaryLabel(BuildContext context) {
    final last = _lastDailySummarySentAt;
    if (last == null) return 'Not sent yet';

    final now = DateTime.now();
    final dayLabel = _isSameDay(last, now)
        ? 'Today'
        : DateFormat('MMM dd, yyyy').format(last);
    final timeLabel = DateFormat('hh:mm a').format(last);
    return '$dayLabel at $timeLabel';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;

    if (!mounted) return;

    if (status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Notifications permission already granted')),
      );
      return;
    }

    if (status.isPermanentlyDenied) {
      final opened = await openAppSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Open Settings to enable notifications'
                : 'Enable notifications in system settings',
          ),
        ),
      );
      return;
    }

    final requested = await Permission.notification.request();
    if (!mounted) return;

    if (requested.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications enabled')),
      );
    } else if (requested.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notifications are blocked; enable them in Settings'),
        ),
      );
      await openAppSettings();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications permission denied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: SwitchListTile(
                    value: _transactionEnabled,
                    onChanged: _setTransactionEnabled,
                    title: const Text('Transaction alerts'),
                    subtitle:
                        const Text('Notify when a new transaction is detected'),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    value: _dailyEnabled,
                    onChanged: _setDailyEnabled,
                    title: const Text("Day's summary"),
                    subtitle:
                        const Text("Daily 'Today's spending' notification"),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    enabled: _dailyEnabled,
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Summary time'),
                    subtitle: Text(_dailyTime.format(context)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _dailyEnabled ? _pickDailyTime : null,
                  ),
                ),
                // const SizedBox(height: 8),
                // Card(
                //   child: ListTile(
                //     enabled: _dailyEnabled,
                //     leading: const Icon(Icons.event_available_rounded),
                //     title: const Text('Next summary'),
                //     subtitle: Text(
                //       _dailyEnabled ? _nextDailySummaryLabel(context) : 'Off',
                //     ),
                //   ),
                // ),
                // const SizedBox(height: 8),
                // Card(
                //   child: ListTile(
                //     enabled: _dailyEnabled,
                //     leading: const Icon(Icons.history_rounded),
                //     title: const Text('Last sent'),
                //     subtitle: Text(
                //       _dailyEnabled ? _lastDailySummaryLabel(context) : 'Off',
                //     ),
                //   ),
                // ),
                // const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    enabled: _dailyEnabled,
                    leading: const Icon(Icons.notification_add_rounded),
                    title: const Text('Send test summary'),
                    subtitle:
                        const Text('Send a sample summary notification now'),
                    onTap: _dailyEnabled ? _sendTestDailySummary : null,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.notifications_active_rounded),
                    title: const Text('Request permission'),
                    subtitle:
                        const Text('If notifications are blocked, enable them'),
                    onTap: () {
                      _requestNotificationPermission();
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Note: delivery time depends on your phone's battery optimization.",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}
