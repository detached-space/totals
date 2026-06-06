import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

class RedesignNotificationsPage extends StatefulWidget {
  const RedesignNotificationsPage({super.key});

  @override
  State<RedesignNotificationsPage> createState() =>
      _RedesignNotificationsPageState();
}

class _RedesignNotificationsPageState extends State<RedesignNotificationsPage> {
  late Future<List<NotificationHistoryEntry>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = NotificationService.instance.getNotificationHistory();
  }

  Future<void> _reload() async {
    final future = NotificationService.instance.getNotificationHistory();
    setState(() {
      _historyFuture = future;
    });
    await future;
  }

  Future<void> _clearHistory() async {
    await NotificationService.instance.clearNotificationHistory();
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(context.l10nText('Notifications')),
        actions: [
          IconButton(
            tooltip: context.l10nText('Clear'),
            onPressed: _clearHistory,
            icon: const Icon(AppIcons.delete_outline_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<NotificationHistoryEntry>>(
          future: _historyFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final items = snapshot.data ?? const <NotificationHistoryEntry>[];
            if (items.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Text(context.l10nText('No notifications yet')),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _ChannelChip(channel: item.channel),
                          const Spacer(),
                          Text(
                            _formatTime(item.sentAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      if (item.body.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.body,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final yyyy = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$yyyy-$month-$day $hh:$mm';
  }
}

class _ChannelChip extends StatelessWidget {
  final String channel;

  const _ChannelChip({required this.channel});

  @override
  Widget build(BuildContext context) {
    final label = switch (channel) {
      'transactions' => 'Transaction',
      'daily_spending' => 'Daily',
      'account_sync' => 'Sync',
      'account_sync_complete' => 'Sync',
      'budgets' => 'Budget',
      _ => 'Other',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryLight,
        ),
      ),
    );
  }
}
