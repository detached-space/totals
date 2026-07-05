import 'dart:async';

import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/data_sync/data_sync_repository.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/services/data_sync/sync_service.dart';
import 'package:totals/utils/text_utils.dart';

/// Read-only view of the outbox: what was sent, what is pending, what failed.
class DataSyncLogPage extends StatefulWidget {
  const DataSyncLogPage({super.key});

  @override
  State<DataSyncLogPage> createState() => _DataSyncLogPageState();
}

class _DataSyncLogPageState extends State<DataSyncLogPage> {
  final _repo = DataSyncRepository();
  final _bankConfigService = BankConfigService();
  String? _statusFilter;
  List<SyncOutboxItem> _items = const [];
  Map<String, int> _counts = const {};
  Map<String, SyncTransactionLogDetails> _transactionDetails = const {};
  Map<int, String> _bankNamesById = const {};
  bool _loading = true;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final items = await _repo.getOutbox(
      statuses: _statusesForFilter(_statusFilter),
      limit: 300,
    );
    final counts = await _repo.outboxStatusCounts();
    final details = await _repo.getTransactionLogDetails(
      items
          .where((item) => item.entity == SyncEntity.transactions)
          .map((item) => item.entityRef),
    );
    final bankNamesById = await _loadBankNames(details.values);
    if (!mounted || token != _loadToken) return;
    setState(() {
      _items = items;
      _counts = counts;
      _transactionDetails = details;
      _bankNamesById = bankNamesById;
      _loading = false;
    });
  }

  Future<Map<int, String>> _loadBankNames(
    Iterable<SyncTransactionLogDetails> details,
  ) async {
    final bankIds = details
        .map((detail) => detail.bankId)
        .whereType<int>()
        .where((id) => id != CashConstants.bankId)
        .toSet();
    if (bankIds.isEmpty) return const <int, String>{};

    try {
      final banks = await _bankConfigService.getBanks(allowRemoteFetch: false);
      return {
        for (final bank in banks)
          if (bankIds.contains(bank.id))
            bank.id: bank.name.trim().isNotEmpty
                ? bank.name.trim()
                : bank.shortName.trim(),
      };
    } catch (_) {
      return const <int, String>{};
    }
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
    final all = _counts.values.fold<int>(0, (sum, count) => sum + count);
    final pending = _counts[SyncOutboxStatus.pending] ?? 0;
    final failed = _failedCount;
    final sent = _counts[SyncOutboxStatus.sent] ?? 0;
    final showRetryFailed =
        failed > 0 && (_statusFilter == null || _isFailedFilter);
    final showClearSent = sent > 0 &&
        (_statusFilter == null || _statusFilter == SyncOutboxStatus.sent);
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
                              _filterChip('All', null, all),
                              _filterChip(
                                'Pending',
                                SyncOutboxStatus.pending,
                                pending,
                              ),
                              _filterChip('Sent', SyncOutboxStatus.sent, sent),
                              _filterChip(
                                'Failed',
                                SyncOutboxStatus.dead,
                                failed,
                              ),
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
                      Expanded(
                        child: Text(
                          _visibleCountLabel,
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (showRetryFailed)
                        TextButton(
                          onPressed: _retryFailed,
                          child: Text('Retry failed ($failed)'),
                        ),
                      if (showClearSent)
                        TextButton(
                          onPressed: _clearSent,
                          child: Text('Clear sent ($sent)'),
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
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _filterChip(String label, String? status, int count) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label $count'),
        selected: _statusFilter == status,
        onSelected: (_) {
          setState(() => _statusFilter = status);
          _load();
        },
      ),
    );
  }

  Widget _row(SyncOutboxItem item) {
    final transactionDetails = item.entity == SyncEntity.transactions
        ? _transactionDetails[item.entityRef]
        : null;
    final transactionTime = transactionDetails == null
        ? null
        : _formatTime(transactionDetails.time);
    final transactionParty = transactionDetails == null
        ? null
        : _partyLabel(transactionDetails);
    final subtitleParts = <String>[
      if (transactionDetails == null) item.entity.label,
      if (transactionDetails != null) ...[
        if (transactionTime != null) transactionTime,
        if (transactionParty != null) transactionParty,
        if (transactionDetails.categoryNames.isNotEmpty)
          transactionDetails.categoryNames.join(', '),
      ],
      if (item.op == SyncOp.delete) 'delete',
      if (item.attempts > 0) 'attempt ${item.attempts}',
      if (item.lastStatusCode != null) 'HTTP ${item.lastStatusCode}',
    ];
    final subtitle =
        subtitleParts.isEmpty ? item.entity.label : subtitleParts.join(' · ');
    return DataSyncCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  transactionDetails == null
                      ? item.entityRef
                      : _bankLabel(transactionDetails),
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
              if (transactionDetails != null) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    _formatAmount(transactionDetails),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: _amountColor(transactionDetails),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              DataSyncStatusPill(item.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style:
                TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
          ),
          if (item.lastError != null && item.lastError!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.lastError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.red, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  bool get _isFailedFilter => _statusFilter == SyncOutboxStatus.dead;

  int get _failedCount =>
      (_counts[SyncOutboxStatus.dead] ?? 0) +
      (_counts[SyncOutboxStatus.failed] ?? 0);

  String get _visibleCountLabel {
    final count = _items.length;
    final noun = count == 1 ? 'item' : 'items';
    if (_statusFilter == null) return '$count $noun';
    if (_isFailedFilter) return '$count failed $noun';
    return '$count $_statusFilter $noun';
  }

  List<String>? _statusesForFilter(String? status) {
    if (status == null) return null;
    if (status == SyncOutboxStatus.dead) {
      return const [SyncOutboxStatus.dead, SyncOutboxStatus.failed];
    }
    return [status];
  }

  String _formatAmount(SyncTransactionLogDetails details) {
    final sign = details.isCredit
        ? '+ '
        : details.isDebit
            ? '- '
            : '';
    return '${sign}ETB ${formatNumberWithComma(details.amount)}';
  }

  String _bankLabel(SyncTransactionLogDetails details) {
    final bankId = details.bankId;
    if (bankId == CashConstants.bankId) return CashConstants.bankName;
    if (bankId != null) return _bankNamesById[bankId] ?? 'Bank $bankId';
    return 'Bank';
  }

  String? _partyLabel(SyncTransactionLogDetails details) {
    final party = details.party;
    if (party == null) return null;
    if (details.isCredit) return 'Sender: $party';
    if (details.isDebit) return 'Receiver: $party';
    return party;
  }

  Color _amountColor(SyncTransactionLogDetails details) {
    if (details.isCredit) return AppColors.incomeSuccess;
    if (details.isDebit) return AppColors.red;
    return AppColors.textPrimary(context);
  }

  String? _formatTime(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[local.month - 1];
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month ${local.day}, $hour:$minute';
  }
}
