import 'dart:async';

import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/services/data_sync/data_sync_repository.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/services/data_sync/sync_service.dart';

/// Read-only view of the outbox: what was sent, what is pending, what failed.
class DataSyncLogPage extends StatefulWidget {
  const DataSyncLogPage({super.key});

  @override
  State<DataSyncLogPage> createState() => _DataSyncLogPageState();
}

class _DataSyncLogPageState extends State<DataSyncLogPage> {
  final _repo = DataSyncRepository();
  String? _statusFilter;
  List<SyncOutboxItem> _items = const [];
  Map<String, int> _counts = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _repo.getOutbox(status: _statusFilter, limit: 300);
    final counts = await _repo.outboxStatusCounts();
    if (!mounted) return;
    setState(() {
      _items = items;
      _counts = counts;
      _loading = false;
    });
  }

  Future<void> _retryFailed() async {
    await _repo.retryFailed();
    unawaited(SyncService.instance.requestDrain(reason: 'retry'));
    await _load();
  }

  Future<void> _clearSent() async {
    await _repo.clearSent();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final failed = (_counts[SyncOutboxStatus.dead] ?? 0) +
        (_counts[SyncOutboxStatus.failed] ?? 0);
    final sent = _counts[SyncOutboxStatus.sent] ?? 0;
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: const Text('Sync log'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _filterChip('All', null),
                              _filterChip('Pending', SyncOutboxStatus.pending),
                              _filterChip('Sent', SyncOutboxStatus.sent),
                              _filterChip('Failed', SyncOutboxStatus.dead),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      if (failed > 0)
                        TextButton(
                          onPressed: _retryFailed,
                          child: Text('Retry $failed failed'),
                        ),
                      const Spacer(),
                      if (sent > 0)
                        TextButton(
                          onPressed: _clearSent,
                          child: Text('Clear $sent sent'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Text(
                            'Nothing here yet.',
                            style: TextStyle(
                                color: AppColors.textSecondary(context)),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _items.length,
                          itemBuilder: (ctx, i) => _row(_items[i]),
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _filterChip(String label, String? status) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _statusFilter == status,
        onSelected: (_) {
          setState(() => _statusFilter = status);
          _load();
        },
      ),
    );
  }

  Widget _row(SyncOutboxItem item) {
    final subtitleParts = <String>[
      item.entity.label,
      if (item.op == SyncOp.delete) 'delete',
      if (item.attempts > 0) 'attempt ${item.attempts}',
      if (item.lastStatusCode != null) 'HTTP ${item.lastStatusCode}',
    ];
    return DataSyncCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.entityRef,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DataSyncStatusPill(item.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitleParts.join(' · '),
            style:
                TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
          ),
          if (item.lastError != null && item.lastError!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.lastError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.red, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
