import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
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

enum _LogAttemptFilter { untried, retried }

enum _LogHttpFilter { anyCode, success, error, noCode }

const _uncategorizedTransactionCategory = 'Uncategorized';

class _LogFilter {
  final Set<SyncEntity> entities;
  final Set<SyncOp> ops;
  final Set<int> bankIds;
  final Set<_LogAttemptFilter> attempts;
  final Set<_LogHttpFilter> http;
  final Set<String> transactionTypes;
  final Set<String> transactionCategoryNames;
  final Set<String> budgetCategoryNames;
  final Set<bool> budgetActiveStates;
  final double? minAmount;
  final double? maxAmount;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? transactionStartDate;
  final DateTime? transactionEndDate;

  const _LogFilter({
    this.entities = const <SyncEntity>{},
    this.ops = const <SyncOp>{},
    this.bankIds = const <int>{},
    this.attempts = const <_LogAttemptFilter>{},
    this.http = const <_LogHttpFilter>{},
    this.transactionTypes = const <String>{},
    this.transactionCategoryNames = const <String>{},
    this.budgetCategoryNames = const <String>{},
    this.budgetActiveStates = const <bool>{},
    this.minAmount,
    this.maxAmount,
    this.startDate,
    this.endDate,
    this.transactionStartDate,
    this.transactionEndDate,
  });

  bool get isActive =>
      entities.isNotEmpty ||
      ops.isNotEmpty ||
      bankIds.isNotEmpty ||
      attempts.isNotEmpty ||
      http.isNotEmpty ||
      transactionTypes.isNotEmpty ||
      transactionCategoryNames.isNotEmpty ||
      budgetCategoryNames.isNotEmpty ||
      budgetActiveStates.isNotEmpty ||
      minAmount != null ||
      maxAmount != null ||
      startDate != null ||
      endDate != null ||
      transactionStartDate != null ||
      transactionEndDate != null;

  int get activeCount {
    var count = 0;
    if (entities.isNotEmpty) count++;
    if (ops.isNotEmpty) count++;
    if (bankIds.isNotEmpty) count++;
    if (attempts.isNotEmpty) count++;
    if (http.isNotEmpty) count++;
    if (transactionTypes.isNotEmpty) count++;
    if (transactionCategoryNames.isNotEmpty) count++;
    if (budgetCategoryNames.isNotEmpty) count++;
    if (budgetActiveStates.isNotEmpty) count++;
    if (minAmount != null || maxAmount != null) count++;
    if (startDate != null || endDate != null) count++;
    if (transactionStartDate != null || transactionEndDate != null) count++;
    return count;
  }
}

class _DataSyncLogPageState extends State<DataSyncLogPage> {
  final _repo = DataSyncRepository();
  final _bankConfigService = BankConfigService();
  final _searchController = TextEditingController();

  String? _statusFilter;
  String _searchQuery = '';
  _LogFilter _filter = const _LogFilter();
  List<SyncOutboxItem> _allItems = const [];
  Map<String, SyncTransactionLogDetails> _transactionDetails = const {};
  Map<String, SyncAccountLogDetails> _accountDetails = const {};
  Map<String, SyncBudgetLogDetails> _budgetDetails = const {};
  Map<int, String> _bankNamesById = const {};
  bool _loading = true;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final items = await _repo.getOutbox(limit: 300);
    final transactionDetails = await _repo.getTransactionLogDetails(
      items
          .where((item) => item.entity == SyncEntity.transactions)
          .map((item) => item.entityRef),
    );
    final accountDetails = await _repo.getAccountLogDetails(
      items
          .where((item) => item.entity == SyncEntity.accounts)
          .map((item) => item.entityRef),
    );
    final budgetDetails = await _repo.getBudgetLogDetails(
      items
          .where((item) => item.entity == SyncEntity.budgets)
          .map((item) => item.entityRef),
    );
    final bankIds = <int>{
      for (final detail in transactionDetails.values)
        if (detail.bankId != null) detail.bankId!,
      for (final detail in accountDetails.values) detail.bankId,
    };
    final bankNamesById = await _loadBankNames(bankIds);
    if (!mounted || token != _loadToken) return;
    setState(() {
      _allItems = items;
      _transactionDetails = transactionDetails;
      _accountDetails = accountDetails;
      _budgetDetails = budgetDetails;
      _bankNamesById = bankNamesById;
      _loading = false;
    });
  }

  Future<Map<int, String>> _loadBankNames(Set<int> bankIds) async {
    final ids = bankIds.where((id) => id != CashConstants.bankId).toSet();
    if (ids.isEmpty) return const <int, String>{};

    try {
      final banks = await _bankConfigService.getBanks(allowRemoteFetch: false);
      return {
        for (final bank in banks)
          if (ids.contains(bank.id))
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

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_LogFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogFilterSheet(
        currentFilter: _filter,
        transactionBankIds: _transactionBankIdsForFilter(),
        accountBankIds: _accountBankIdsForFilter(),
        transactionCategoryNames: _transactionCategoryNamesForFilter(),
        budgetCategoryNames: _budgetCategoryNamesForFilter(),
        bankLabelForId: _bankLabelForId,
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final baseItems = _baseFilteredItems;
    final visibleItems = _visibleItems;
    final all = baseItems.length;
    final pending = _countStatus(baseItems, SyncOutboxStatus.pending);
    final failed = _countFailed(baseItems);
    final sent = _countStatus(baseItems, SyncOutboxStatus.sent);
    final totalFailed = _countFailed(_allItems);
    final totalSent = _countStatus(_allItems, SyncOutboxStatus.sent);
    final showRetryFailed =
        totalFailed > 0 && (_statusFilter == null || _isFailedFilter);
    final showClearSent = totalSent > 0 &&
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _LogSearchFilterRow(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    onFilterTap: _openFilterSheet,
                    activeFilterCount: _filter.activeCount,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
                        _filterChip('Failed', SyncOutboxStatus.dead, failed),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _visibleCountLabel(visibleItems.length),
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
                          child: Text('Retry failed ($totalFailed)'),
                        ),
                      if (showClearSent)
                        TextButton(
                          onPressed: _clearSent,
                          child: Text('Clear sent ($totalSent)'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: visibleItems.isEmpty
                      ? Center(
                          child: Text(
                            _allItems.isEmpty
                                ? 'Nothing here yet.'
                                : 'No logs match these filters.',
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: visibleItems.length,
                          itemBuilder: (ctx, i) => _row(visibleItems[i]),
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
      child: _LogStatusChip(
        label: label,
        count: count,
        selected: _statusFilter == status,
        onTap: () => setState(() => _statusFilter = status),
      ),
    );
  }

  Widget _row(SyncOutboxItem item) {
    final transactionDetails = item.entity == SyncEntity.transactions
        ? _transactionDetails[item.entityRef]
        : null;
    final accountDetails = item.entity == SyncEntity.accounts
        ? _accountDetails[item.entityRef]
        : null;
    final budgetDetails = item.entity == SyncEntity.budgets
        ? _budgetDetails[item.entityRef]
        : null;
    final trailing = _trailingText(
      item,
      transactionDetails,
      accountDetails,
      budgetDetails,
    );
    return DataSyncCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _titleForItem(
                    item,
                    transactionDetails,
                    accountDetails,
                    budgetDetails,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    trailing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: _trailingColor(item, transactionDetails),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              DataSyncStatusPill(item.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _subtitleForItem(
              item,
              transactionDetails,
              accountDetails,
              budgetDetails,
            ),
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
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

  List<SyncOutboxItem> get _baseFilteredItems => _allItems
      .where((item) => _matchesSearch(item) && _matchesLogFilter(item))
      .toList(growable: false);

  List<SyncOutboxItem> get _visibleItems =>
      _baseFilteredItems.where(_matchesStatusFilter).toList(growable: false);

  String _visibleCountLabel(int count) {
    final noun = count == 1 ? 'item' : 'items';
    if (_statusFilter == null) return '$count $noun';
    if (_isFailedFilter) return '$count failed $noun';
    return '$count $_statusFilter $noun';
  }

  bool _matchesStatusFilter(SyncOutboxItem item) {
    final status = _statusFilter;
    if (status == null) return true;
    if (status == SyncOutboxStatus.dead) return _isFailedStatus(item.status);
    return item.status == status;
  }

  bool _matchesLogFilter(SyncOutboxItem item) {
    if (_filter.entities.isNotEmpty &&
        !_filter.entities.contains(item.entity)) {
      return false;
    }
    if (_filter.ops.isNotEmpty && !_filter.ops.contains(item.op)) return false;
    if (_filter.bankIds.isNotEmpty &&
        !_filter.bankIds.contains(_bankIdForItem(item))) {
      return false;
    }
    if (_filter.attempts.isNotEmpty && !_matchesAttemptFilter(item)) {
      return false;
    }
    if (_filter.http.isNotEmpty && !_matchesHttpFilter(item)) return false;
    if (_filter.transactionTypes.isNotEmpty &&
        !_matchesTransactionTypeFilter(item)) {
      return false;
    }
    if (_filter.transactionCategoryNames.isNotEmpty &&
        !_matchesTransactionCategoryFilter(item)) {
      return false;
    }
    if (_filter.budgetCategoryNames.isNotEmpty &&
        !_matchesBudgetCategoryFilter(item)) {
      return false;
    }
    if (_filter.budgetActiveStates.isNotEmpty &&
        !_matchesBudgetStateFilter(item)) {
      return false;
    }
    if ((_filter.minAmount != null || _filter.maxAmount != null) &&
        !_matchesAmountRange(item)) {
      return false;
    }
    if ((_filter.transactionStartDate != null ||
            _filter.transactionEndDate != null) &&
        !_matchesTransactionDateRange(item)) {
      return false;
    }
    final startDate = _filter.startDate;
    final endDate = _filter.endDate;
    if (startDate != null && item.updatedAt.isBefore(_dateOnly(startDate))) {
      return false;
    }
    if (endDate != null && item.updatedAt.isAfter(_endOfDay(endDate))) {
      return false;
    }
    return true;
  }

  bool _matchesAttemptFilter(SyncOutboxItem item) {
    for (final attempt in _filter.attempts) {
      switch (attempt) {
        case _LogAttemptFilter.untried:
          if (item.attempts == 0) return true;
        case _LogAttemptFilter.retried:
          if (item.attempts > 0) return true;
      }
    }
    return false;
  }

  bool _matchesHttpFilter(SyncOutboxItem item) {
    final statusCode = item.lastStatusCode;
    for (final filter in _filter.http) {
      switch (filter) {
        case _LogHttpFilter.anyCode:
          if (statusCode != null) return true;
        case _LogHttpFilter.success:
          if (statusCode != null && statusCode >= 200 && statusCode < 300) {
            return true;
          }
        case _LogHttpFilter.error:
          if (statusCode != null && statusCode >= 400) return true;
        case _LogHttpFilter.noCode:
          if (statusCode == null) return true;
      }
    }
    return false;
  }

  bool _matchesTransactionTypeFilter(SyncOutboxItem item) {
    if (item.entity != SyncEntity.transactions) return false;
    final type =
        _transactionDetails[item.entityRef]?.type?.trim().toUpperCase();
    return type != null && _filter.transactionTypes.contains(type);
  }

  bool _matchesTransactionCategoryFilter(SyncOutboxItem item) {
    if (item.entity != SyncEntity.transactions) return false;
    final names = _transactionCategoryNamesForItem(item);
    if (names.isEmpty) {
      return _filter.transactionCategoryNames
          .contains(_uncategorizedTransactionCategory);
    }
    return names.any(_filter.transactionCategoryNames.contains);
  }

  bool _matchesBudgetCategoryFilter(SyncOutboxItem item) {
    if (item.entity != SyncEntity.budgets) return false;
    final detail = _budgetDetails[item.entityRef];
    if (detail == null) {
      final names = _stringList(_payloadSnapshot(item)['categoryNames']);
      if (names.isEmpty) {
        return _filter.budgetCategoryNames.contains('All expenses');
      }
      return names.any(_filter.budgetCategoryNames.contains);
    }
    if (detail.categoryNames.isEmpty) {
      return _filter.budgetCategoryNames.contains('All expenses');
    }
    return detail.categoryNames.any(_filter.budgetCategoryNames.contains);
  }

  bool _matchesBudgetStateFilter(SyncOutboxItem item) {
    if (item.entity != SyncEntity.budgets) return false;
    final detail = _budgetDetails[item.entityRef];
    if (detail != null) {
      return _filter.budgetActiveStates.contains(detail.isActive);
    }
    final active = _asBool(_payloadSnapshot(item)['isActive']);
    return active != null && _filter.budgetActiveStates.contains(active);
  }

  bool _matchesAmountRange(SyncOutboxItem item) {
    final amount = _amountForItem(item);
    if (amount == null) return false;
    if (_filter.minAmount != null && amount < _filter.minAmount!) return false;
    if (_filter.maxAmount != null && amount > _filter.maxAmount!) return false;
    return true;
  }

  bool _matchesTransactionDateRange(SyncOutboxItem item) {
    if (item.entity != SyncEntity.transactions) return false;
    final raw = _transactionDetails[item.entityRef]?.time;
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    if (parsed == null) return false;
    final local = parsed.toLocal();
    final start = _filter.transactionStartDate;
    final end = _filter.transactionEndDate;
    if (start != null && local.isBefore(_dateOnly(start))) return false;
    if (end != null && local.isAfter(_endOfDay(end))) return false;
    return true;
  }

  bool _matchesSearch(SyncOutboxItem item) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    return _searchTextForItem(item).toLowerCase().contains(query);
  }

  String _searchTextForItem(SyncOutboxItem item) {
    final transactionDetails = item.entity == SyncEntity.transactions
        ? _transactionDetails[item.entityRef]
        : null;
    final accountDetails = item.entity == SyncEntity.accounts
        ? _accountDetails[item.entityRef]
        : null;
    final budgetDetails = item.entity == SyncEntity.budgets
        ? _budgetDetails[item.entityRef]
        : null;
    return [
      item.entity.label,
      item.entityRef,
      item.status,
      item.op.storage,
      if (item.lastStatusCode != null) 'HTTP ${item.lastStatusCode}',
      if (item.lastError != null) item.lastError!,
      _titleForItem(item, transactionDetails, accountDetails, budgetDetails),
      _subtitleForItem(item, transactionDetails, accountDetails, budgetDetails),
      if (transactionDetails != null)
        formatNumberWithComma(transactionDetails.amount),
      if (accountDetails != null) formatNumberWithComma(accountDetails.balance),
      if (budgetDetails != null) formatNumberWithComma(budgetDetails.amount),
    ].join(' ');
  }

  int _countStatus(List<SyncOutboxItem> items, String status) =>
      items.where((item) => item.status == status).length;

  int _countFailed(List<SyncOutboxItem> items) =>
      items.where((item) => _isFailedStatus(item.status)).length;

  bool _isFailedStatus(String status) =>
      status == SyncOutboxStatus.dead || status == SyncOutboxStatus.failed;

  List<int> _transactionBankIdsForFilter() {
    final ids = <int>{};
    for (final item in _allItems) {
      if (item.entity != SyncEntity.transactions) continue;
      final bankId = _bankIdForItem(item);
      if (bankId != null) ids.add(bankId);
    }
    return _sortedBankIds(ids);
  }

  List<int> _accountBankIdsForFilter() {
    final ids = <int>{};
    for (final item in _allItems) {
      if (item.entity != SyncEntity.accounts) continue;
      final bankId = _bankIdForItem(item);
      if (bankId != null) ids.add(bankId);
    }
    return _sortedBankIds(ids);
  }

  List<int> _sortedBankIds(Set<int> ids) {
    final sorted = ids.toList(growable: false)
      ..sort((a, b) => _bankLabelForId(a).compareTo(_bankLabelForId(b)));
    return sorted;
  }

  List<String> _transactionCategoryNamesForFilter() {
    final names = <String>{};
    var hasUncategorized = false;
    for (final item in _allItems) {
      if (item.entity != SyncEntity.transactions) continue;
      final itemNames = _transactionCategoryNamesForItem(item);
      if (itemNames.isEmpty) {
        hasUncategorized = true;
      } else {
        names.addAll(itemNames);
      }
    }
    final sorted = names.toList(growable: false)..sort();
    if (hasUncategorized) sorted.insert(0, _uncategorizedTransactionCategory);
    return sorted;
  }

  List<String> _transactionCategoryNamesForItem(SyncOutboxItem item) {
    final detailNames = _transactionDetails[item.entityRef]?.categoryNames;
    if (detailNames != null && detailNames.isNotEmpty) {
      return [
        for (final name in detailNames)
          if (name.trim().isNotEmpty) name.trim(),
      ];
    }
    final snapshot = _payloadSnapshot(item);
    final names = _stringList(snapshot['categoryNames']).toSet();
    final single = _trimmed(snapshot['categoryName']);
    if (single != null) names.add(single);
    return names.toList(growable: false)..sort();
  }

  List<String> _budgetCategoryNamesForFilter() {
    final names = <String>{};
    var hasAllExpensesBudget = false;
    for (final detail in _budgetDetails.values) {
      if (detail.categoryNames.isEmpty) {
        hasAllExpensesBudget = true;
      } else {
        names.addAll(
            detail.categoryNames.where((name) => name.trim().isNotEmpty));
      }
    }
    final sorted = names.toList(growable: false)..sort();
    if (hasAllExpensesBudget) sorted.insert(0, 'All expenses');
    return sorted;
  }

  int? _bankIdForItem(SyncOutboxItem item) {
    if (item.entity == SyncEntity.transactions) {
      return _transactionDetails[item.entityRef]?.bankId ??
          _asInt(_payloadSnapshot(item)['bankId']) ??
          _asInt(_payloadSnapshot(item)['bank']);
    }
    if (item.entity == SyncEntity.accounts) {
      return _accountDetails[item.entityRef]?.bankId ??
          _bankIdFromAccountRef(item.entityRef) ??
          _asInt(_payloadSnapshot(item)['bank']);
    }
    return null;
  }

  String _titleForItem(
    SyncOutboxItem item,
    SyncTransactionLogDetails? transactionDetails,
    SyncAccountLogDetails? accountDetails,
    SyncBudgetLogDetails? budgetDetails,
  ) {
    if (transactionDetails != null) return _bankLabel(transactionDetails);
    if (accountDetails != null) return _bankLabelForId(accountDetails.bankId);
    if (item.entity == SyncEntity.accounts) {
      final bankId = _bankIdFromAccountRef(item.entityRef) ??
          _asInt(_payloadSnapshot(item)['bank']);
      if (bankId != null) return _bankLabelForId(bankId);
      return 'Account';
    }
    if (budgetDetails != null && budgetDetails.name.trim().isNotEmpty) {
      return budgetDetails.name.trim();
    }
    if (item.entity == SyncEntity.budgets) {
      final snapshotName = _trimmed(_payloadSnapshot(item)['name']);
      if (snapshotName != null) return snapshotName;
      final id = _budgetIdFromRef(item.entityRef);
      return id == null ? 'Budget' : 'Budget $id';
    }
    return item.entityRef;
  }

  String _subtitleForItem(
    SyncOutboxItem item,
    SyncTransactionLogDetails? transactionDetails,
    SyncAccountLogDetails? accountDetails,
    SyncBudgetLogDetails? budgetDetails,
  ) {
    final parts = <String>[];
    if (transactionDetails != null) {
      final transactionTime = _formatTime(transactionDetails.time);
      final transactionParty = _partyLabel(transactionDetails);
      if (transactionTime != null) parts.add(transactionTime);
      if (transactionParty != null) parts.add(transactionParty);
      if (transactionDetails.categoryNames.isNotEmpty) {
        parts.add(transactionDetails.categoryNames.join(', '));
      }
    } else if (accountDetails != null) {
      parts.add(accountDetails.accountNumber);
      final holder = accountDetails.accountHolderName.trim();
      if (holder.isNotEmpty) parts.add(holder);
    } else if (item.entity == SyncEntity.accounts) {
      final snapshot = _payloadSnapshot(item);
      final accountNumber = _accountNumberFromRef(item.entityRef) ??
          _trimmed(snapshot['accountNumber']);
      final holder = _trimmed(snapshot['accountHolderName']);
      if (accountNumber != null) parts.add(accountNumber);
      if (holder != null) parts.add(holder);
      if (parts.isEmpty) parts.add(item.entity.label);
    } else if (budgetDetails != null) {
      if (budgetDetails.categoryNames.isEmpty) {
        parts.add('All expenses');
      } else {
        parts.add(budgetDetails.categoryNames.join(', '));
      }
      parts.add(budgetDetails.type);
      if (!budgetDetails.isActive) parts.add('inactive');
    } else if (item.entity == SyncEntity.budgets) {
      final snapshot = _payloadSnapshot(item);
      final categoryNames = _stringList(snapshot['categoryNames']);
      if (categoryNames.isNotEmpty) {
        parts.add(categoryNames.join(', '));
      } else {
        final type = _trimmed(snapshot['type']);
        parts.add(type ?? item.entity.label);
      }
    } else {
      parts.add(item.entity.label);
    }

    if (item.op == SyncOp.delete) parts.add('delete');
    if (item.attempts > 0) parts.add('attempt ${item.attempts}');
    if (item.lastStatusCode != null) parts.add('HTTP ${item.lastStatusCode}');
    return parts.isEmpty ? item.entity.label : parts.join(' · ');
  }

  String? _trailingText(
    SyncOutboxItem item,
    SyncTransactionLogDetails? transactionDetails,
    SyncAccountLogDetails? accountDetails,
    SyncBudgetLogDetails? budgetDetails,
  ) {
    if (transactionDetails != null) return _formatAmount(transactionDetails);
    if (accountDetails != null) {
      return 'ETB ${formatNumberWithComma(accountDetails.balance)}';
    }
    if (budgetDetails != null) {
      return 'ETB ${formatNumberWithComma(budgetDetails.amount)}';
    }
    final snapshot = _payloadSnapshot(item);
    final amount = _asDouble(snapshot['amount'] ?? snapshot['balance']);
    if (amount == null) return null;
    return 'ETB ${formatNumberWithComma(amount)}';
  }

  Color _trailingColor(
    SyncOutboxItem item,
    SyncTransactionLogDetails? transactionDetails,
  ) {
    if (transactionDetails != null) return _amountColor(transactionDetails);
    return AppColors.textPrimary(context);
  }

  Map<String, dynamic> _payloadSnapshot(SyncOutboxItem item) {
    final raw = item.payloadJson;
    if (raw == null || raw.trim().isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const <String, dynamic>{};
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
    if (bankId == null) return 'Bank';
    return _bankLabelForId(bankId);
  }

  String _bankLabelForId(int bankId) {
    if (bankId == CashConstants.bankId) return CashConstants.bankName;
    return _bankNamesById[bankId] ?? 'Bank $bankId';
  }

  String? _partyLabel(SyncTransactionLogDetails details) => details.party;

  Color _amountColor(SyncTransactionLogDetails details) {
    if (details.isCredit) return AppColors.incomeSuccess;
    if (details.isDebit) return AppColors.red;
    return AppColors.textPrimary(context);
  }

  String? _formatTime(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return _formatDateTime(parsed.toLocal());
  }

  String _formatDateTime(DateTime value) {
    final month = _months[value.month - 1];
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month ${value.day}, $hour:$minute';
  }

  int? _budgetIdFromRef(String ref) =>
      int.tryParse(ref.trim().replaceFirst('budget:', ''));

  String? _accountNumberFromRef(String ref) {
    final sep = ref.lastIndexOf('|');
    if (sep <= 0) return null;
    final value = ref.substring(0, sep).trim();
    return value.isEmpty ? null : value;
  }

  int? _bankIdFromAccountRef(String ref) {
    final sep = ref.lastIndexOf('|');
    if (sep <= 0 || sep == ref.length - 1) return null;
    return int.tryParse(ref.substring(sep + 1).trim());
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

  String? _trimmed(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }

  double? _amountForItem(SyncOutboxItem item) {
    switch (item.entity) {
      case SyncEntity.transactions:
        final amount = _transactionDetails[item.entityRef]?.amount ??
            _asDouble(_payloadSnapshot(item)['amount']);
        return amount?.abs();
      case SyncEntity.accounts:
        return _accountDetails[item.entityRef]?.balance ??
            _asDouble(_payloadSnapshot(item)['balance']);
      case SyncEntity.budgets:
        return _budgetDetails[item.entityRef]?.amount ??
            _asDouble(_payloadSnapshot(item)['amount']);
    }
  }

  List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((value) => value?.toString().trim())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }
}

const _months = [
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

class _LogSearchFilterRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;
  final int activeFilterCount;

  const _LogSearchFilterRow({
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
    required this.activeFilterCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Search sync logs',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.textTertiary(context),
                ),
                filled: true,
                fillColor: AppColors.surfaceColor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderColor(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderColor(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.primaryLight,
                    width: 1.3,
                  ),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _LogFilterButton(
          onTap: onFilterTap,
          activeFilterCount: activeFilterCount,
        ),
      ],
    );
  }
}

class _LogFilterButton extends StatelessWidget {
  final VoidCallback onTap;
  final int activeFilterCount;

  const _LogFilterButton({
    required this.onTap,
    required this.activeFilterCount,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilters = activeFilterCount > 0;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: hasFilters
                  ? AppColors.primaryDark.withValues(alpha: 0.1)
                  : AppColors.cardColor(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasFilters
                    ? AppColors.primaryDark
                    : AppColors.borderColor(context),
              ),
            ),
            child: Icon(
              AppIcons.filter_list,
              color: hasFilters
                  ? AppColors.primaryDark
                  : AppColors.textSecondary(context),
              size: 22,
            ),
          ),
          if (hasFilters)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  activeFilterCount.toString(),
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LogStatusChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _LogStatusChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryDark
              : AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primaryDark
                : AppColors.borderColor(context),
          ),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            color:
                selected ? AppColors.white : AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LogFilterSheet extends StatefulWidget {
  final _LogFilter currentFilter;
  final List<int> transactionBankIds;
  final List<int> accountBankIds;
  final List<String> transactionCategoryNames;
  final List<String> budgetCategoryNames;
  final String Function(int bankId) bankLabelForId;

  const _LogFilterSheet({
    required this.currentFilter,
    required this.transactionBankIds,
    required this.accountBankIds,
    required this.transactionCategoryNames,
    required this.budgetCategoryNames,
    required this.bankLabelForId,
  });

  @override
  State<_LogFilterSheet> createState() => _LogFilterSheetState();
}

class _LogFilterSheetState extends State<_LogFilterSheet> {
  late Set<SyncEntity> _entities;
  late Set<SyncOp> _ops;
  late Set<int> _bankIds;
  late Set<_LogAttemptFilter> _attempts;
  late Set<_LogHttpFilter> _http;
  late Set<String> _transactionTypes;
  late Set<String> _transactionCategoryNames;
  late Set<String> _budgetCategoryNames;
  late Set<bool> _budgetActiveStates;
  late final TextEditingController _minAmountController;
  late final TextEditingController _maxAmountController;
  String? _amountErrorText;
  late DateTime? _startDate;
  late DateTime? _endDate;
  late DateTime? _transactionStartDate;
  late DateTime? _transactionEndDate;

  @override
  void initState() {
    super.initState();
    _entities = Set<SyncEntity>.from(widget.currentFilter.entities);
    _ops = Set<SyncOp>.from(widget.currentFilter.ops);
    _bankIds = Set<int>.from(widget.currentFilter.bankIds);
    _attempts = Set<_LogAttemptFilter>.from(widget.currentFilter.attempts);
    _http = Set<_LogHttpFilter>.from(widget.currentFilter.http);
    _transactionTypes = Set<String>.from(widget.currentFilter.transactionTypes);
    _transactionCategoryNames =
        Set<String>.from(widget.currentFilter.transactionCategoryNames);
    _budgetCategoryNames =
        Set<String>.from(widget.currentFilter.budgetCategoryNames);
    _budgetActiveStates =
        Set<bool>.from(widget.currentFilter.budgetActiveStates);
    _minAmountController = TextEditingController(
      text: _formatAmountInput(widget.currentFilter.minAmount),
    );
    _maxAmountController = TextEditingController(
      text: _formatAmountInput(widget.currentFilter.maxAmount),
    );
    _startDate = widget.currentFilter.startDate;
    _endDate = widget.currentFilter.endDate;
    _transactionStartDate = widget.currentFilter.transactionStartDate;
    _transactionEndDate = widget.currentFilter.transactionEndDate;
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  void _clearAll() {
    setState(() {
      _entities.clear();
      _ops.clear();
      _bankIds.clear();
      _attempts.clear();
      _http.clear();
      _transactionTypes.clear();
      _transactionCategoryNames.clear();
      _budgetCategoryNames.clear();
      _budgetActiveStates.clear();
      _minAmountController.clear();
      _maxAmountController.clear();
      _amountErrorText = null;
      _startDate = null;
      _endDate = null;
      _transactionStartDate = null;
      _transactionEndDate = null;
    });
  }

  void _apply() {
    final minRaw = _minAmountController.text;
    final maxRaw = _maxAmountController.text;
    final minAmount = _parseAmountInput(minRaw);
    final maxAmount = _parseAmountInput(maxRaw);
    final amountError = _buildAmountValidationMessage(
      minRaw: minRaw,
      maxRaw: maxRaw,
      minAmount: minAmount,
      maxAmount: maxAmount,
    );

    if (amountError != null) {
      setState(() => _amountErrorText = amountError);
      return;
    }

    Navigator.of(context).pop(
      _LogFilter(
        entities: Set<SyncEntity>.unmodifiable(_entities),
        ops: Set<SyncOp>.unmodifiable(_ops),
        bankIds: Set<int>.unmodifiable(_bankIds),
        attempts: Set<_LogAttemptFilter>.unmodifiable(_attempts),
        http: Set<_LogHttpFilter>.unmodifiable(_http),
        transactionTypes: Set<String>.unmodifiable(_transactionTypes),
        transactionCategoryNames:
            Set<String>.unmodifiable(_transactionCategoryNames),
        budgetCategoryNames: Set<String>.unmodifiable(_budgetCategoryNames),
        budgetActiveStates: Set<bool>.unmodifiable(_budgetActiveStates),
        minAmount: minAmount,
        maxAmount: maxAmount,
        startDate: _startDate,
        endDate: _endDate,
        transactionStartDate: _transactionStartDate,
        transactionEndDate: _transactionEndDate,
      ),
    );
  }

  bool get _showsTransactions => _entities.contains(SyncEntity.transactions);
  bool get _showsAccounts => _entities.contains(SyncEntity.accounts);
  bool get _showsBudgets => _entities.contains(SyncEntity.budgets);
  bool get _showsBankFilter => _showsTransactions || _showsAccounts;
  bool get _showsAmountFilter =>
      _showsTransactions || _showsAccounts || _showsBudgets;
  bool get _hasEntityScopedFilters =>
      _showsTransactions ||
      _showsBudgets ||
      _showsBankFilter ||
      _showsAmountFilter;
  bool get _hasDraftFilters => _draftActiveCount > 0;

  int get _draftActiveCount {
    var count = 0;
    if (_entities.isNotEmpty) count++;
    if (_ops.isNotEmpty) count++;
    if (_bankIds.isNotEmpty) count++;
    if (_attempts.isNotEmpty) count++;
    if (_http.isNotEmpty) count++;
    if (_transactionTypes.isNotEmpty) count++;
    if (_transactionCategoryNames.isNotEmpty) count++;
    if (_budgetCategoryNames.isNotEmpty) count++;
    if (_budgetActiveStates.isNotEmpty) count++;
    if (_minAmountController.text.trim().isNotEmpty ||
        _maxAmountController.text.trim().isNotEmpty) {
      count++;
    }
    if (_startDate != null || _endDate != null) count++;
    if (_transactionStartDate != null || _transactionEndDate != null) count++;
    return count;
  }

  Set<int> get _visibleBankIdSet {
    final ids = <int>{};
    if (_showsTransactions) ids.addAll(widget.transactionBankIds);
    if (_showsAccounts) ids.addAll(widget.accountBankIds);
    return ids;
  }

  List<int> get _visibleBankIds {
    final ids = _visibleBankIdSet.toList(growable: false)
      ..sort((a, b) => widget.bankLabelForId(a).compareTo(
            widget.bankLabelForId(b),
          ));
    return ids;
  }

  String get _bankSectionLabel {
    if (_showsTransactions && !_showsAccounts) return 'TRANSACTION BANK';
    if (_showsAccounts && !_showsTransactions) return 'ACCOUNT BANK';
    return 'BANK';
  }

  void _toggleEntity(SyncEntity entity) {
    setState(() {
      _toggleInSet(_entities, entity);
      _pruneEntityScopedFilters();
    });
  }

  void _pruneEntityScopedFilters() {
    if (!_showsTransactions) {
      _transactionTypes.clear();
      _transactionCategoryNames.clear();
      _transactionStartDate = null;
      _transactionEndDate = null;
    }
    if (!_showsBudgets) {
      _budgetCategoryNames.clear();
      _budgetActiveStates.clear();
    }
    if (!_showsBankFilter) {
      _bankIds.clear();
    } else {
      final visibleBankIds = _visibleBankIdSet;
      _bankIds.removeWhere((bankId) => !visibleBankIds.contains(bankId));
    }
    if (!_showsAmountFilter) {
      _minAmountController.clear();
      _maxAmountController.clear();
      _amountErrorText = null;
    }
  }

  void _toggleInSet<T>(Set<T> set, T value) {
    if (set.contains(value)) {
      set.remove(value);
    } else {
      set.add(value);
    }
  }

  double? _parseAmountInput(String raw) {
    final normalized = raw.replaceAll(',', '').trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  bool _hasInvalidAmountInput(String raw) {
    final normalized = raw.replaceAll(',', '').trim();
    return normalized.isNotEmpty && double.tryParse(normalized) == null;
  }

  String? _buildAmountValidationMessage({
    required String minRaw,
    required String maxRaw,
    required double? minAmount,
    required double? maxAmount,
  }) {
    if (_hasInvalidAmountInput(minRaw) || _hasInvalidAmountInput(maxRaw)) {
      return 'Enter a valid amount';
    }
    if (minAmount != null && maxAmount != null && maxAmount < minAmount) {
      return 'Maximum must be at least minimum.';
    }
    return null;
  }

  String _formatAmountInput(double? amount) {
    if (amount == null) return '';
    if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
    var formatted = amount.toStringAsFixed(2);
    while (formatted.contains('.') && formatted.endsWith('0')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    if (formatted.endsWith('.')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    return formatted;
  }

  void _handleAmountChanged(String _) {
    final minRaw = _minAmountController.text;
    final maxRaw = _maxAmountController.text;
    final minAmount = _parseAmountInput(minRaw);
    final maxAmount = _parseAmountInput(maxRaw);
    setState(() {
      _amountErrorText = _amountErrorText == null
          ? null
          : _buildAmountValidationMessage(
              minRaw: minRaw,
              maxRaw: maxRaw,
              minAmount: minAmount,
              maxAmount: maxAmount,
            );
    });
  }

  Future<void> _pickDate({
    required bool isStart,
    bool transactionDate = false,
  }) async {
    final initial = transactionDate
        ? (isStart ? _transactionStartDate : _transactionEndDate) ??
            DateTime.now()
        : (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) {
        final dark = AppColors.isDark(ctx);
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: dark
                ? const ColorScheme.dark(
                    primary: AppColors.primaryLight,
                    onPrimary: AppColors.white,
                    surface: AppColors.darkCard,
                    onSurface: AppColors.white,
                  )
                : const ColorScheme.light(
                    primary: AppColors.primaryDark,
                    onPrimary: AppColors.white,
                    surface: AppColors.white,
                    onSurface: AppColors.slate900,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      if (transactionDate) {
        if (isStart) {
          _transactionStartDate = picked;
        } else {
          _transactionEndDate = picked;
        }
      } else if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardPadding = MediaQuery.of(context).viewInsets.bottom;
    final navBarPadding = MediaQuery.of(context).padding.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardPadding),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.slate400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Filter sync logs',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_hasDraftFilters) ...[
                          const SizedBox(width: 10),
                          _activeCountBadge(),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      AppIcons.close,
                      color: AppColors.textSecondary(context),
                    ),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('ENTITY'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _LogFilterChoice(
                          label: 'All',
                          selected: _entities.isEmpty,
                          onTap: () => setState(() {
                            _entities.clear();
                            _pruneEntityScopedFilters();
                          }),
                        ),
                        for (final entity in SyncEntity.values)
                          _LogFilterChoice(
                            label: entity.label,
                            selected: _entities.contains(entity),
                            onTap: () => _toggleEntity(entity),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('OPERATION'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _LogFilterChoice(
                          label: 'All',
                          selected: _ops.isEmpty,
                          onTap: () => setState(() => _ops.clear()),
                        ),
                        _LogFilterChoice(
                          label: 'Upsert',
                          selected: _ops.contains(SyncOp.upsert),
                          onTap: () => setState(
                            () => _toggleInSet(_ops, SyncOp.upsert),
                          ),
                        ),
                        _LogFilterChoice(
                          label: 'Delete',
                          selected: _ops.contains(SyncOp.delete),
                          onTap: () => setState(
                            () => _toggleInSet(_ops, SyncOp.delete),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _filterDivider(),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_showsTransactions) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('TRANSACTION TYPE'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _LogFilterChoice(
                                  label: 'All',
                                  selected: _transactionTypes.isEmpty,
                                  onTap: () =>
                                      setState(() => _transactionTypes.clear()),
                                ),
                                _LogFilterChoice(
                                  label: 'Expense',
                                  selected: _transactionTypes.contains('DEBIT'),
                                  onTap: () => setState(
                                    () => _toggleInSet(
                                        _transactionTypes, 'DEBIT'),
                                  ),
                                ),
                                _LogFilterChoice(
                                  label: 'Income',
                                  selected:
                                      _transactionTypes.contains('CREDIT'),
                                  onTap: () => setState(
                                    () => _toggleInSet(
                                        _transactionTypes, 'CREDIT'),
                                  ),
                                ),
                              ],
                            ),
                            if (widget.transactionCategoryNames.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _sectionLabel('TRANSACTION CATEGORIES'),
                              const SizedBox(height: 8),
                              _horizontalChoices(
                                [
                                  _LogFilterChoice(
                                    label: 'All',
                                    selected: _transactionCategoryNames.isEmpty,
                                    onTap: () => setState(
                                      () => _transactionCategoryNames.clear(),
                                    ),
                                  ),
                                  for (final name
                                      in widget.transactionCategoryNames)
                                    _LogFilterChoice(
                                      label: name,
                                      selected:
                                          _transactionCategoryNames.contains(
                                        name,
                                      ),
                                      onTap: () => setState(
                                        () => _toggleInSet(
                                          _transactionCategoryNames,
                                          name,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if (_visibleBankIds.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _bankFilterSection(
                                _bankSectionLabel,
                                _visibleBankIds,
                              ),
                            ],
                            const SizedBox(height: 20),
                            _sectionLabel('TRANSACTION DATE'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _LogDateField(
                                    hint: 'Start date',
                                    value: _transactionStartDate == null
                                        ? null
                                        : _formatDate(_transactionStartDate!),
                                    onTap: () => _pickDate(
                                      isStart: true,
                                      transactionDate: true,
                                    ),
                                    onClear: _transactionStartDate == null
                                        ? null
                                        : () => setState(
                                              () =>
                                                  _transactionStartDate = null,
                                            ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _LogDateField(
                                    hint: 'End date',
                                    value: _transactionEndDate == null
                                        ? null
                                        : _formatDate(_transactionEndDate!),
                                    onTap: () => _pickDate(
                                      isStart: false,
                                      transactionDate: true,
                                    ),
                                    onClear: _transactionEndDate == null
                                        ? null
                                        : () => setState(
                                              () => _transactionEndDate = null,
                                            ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_showsBudgets) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('BUDGET STATUS'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _LogFilterChoice(
                                  label: 'All',
                                  selected: _budgetActiveStates.isEmpty,
                                  onTap: () => setState(
                                      () => _budgetActiveStates.clear()),
                                ),
                                _LogFilterChoice(
                                  label: 'Active',
                                  selected: _budgetActiveStates.contains(true),
                                  onTap: () => setState(
                                    () =>
                                        _toggleInSet(_budgetActiveStates, true),
                                  ),
                                ),
                                _LogFilterChoice(
                                  label: 'Inactive',
                                  selected: _budgetActiveStates.contains(false),
                                  onTap: () => setState(
                                    () => _toggleInSet(
                                        _budgetActiveStates, false),
                                  ),
                                ),
                              ],
                            ),
                            if (widget.budgetCategoryNames.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _sectionLabel('BUDGET CATEGORY'),
                              const SizedBox(height: 8),
                              _horizontalChoices(
                                [
                                  _LogFilterChoice(
                                    label: 'All',
                                    selected: _budgetCategoryNames.isEmpty,
                                    onTap: () => setState(
                                      () => _budgetCategoryNames.clear(),
                                    ),
                                  ),
                                  for (final name in widget.budgetCategoryNames)
                                    _LogFilterChoice(
                                      label: name,
                                      selected:
                                          _budgetCategoryNames.contains(name),
                                      onTap: () => setState(
                                        () => _toggleInSet(
                                          _budgetCategoryNames,
                                          name,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                          if (!_showsTransactions &&
                              _showsAccounts &&
                              _visibleBankIds.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _bankFilterSection(
                              _bankSectionLabel,
                              _visibleBankIds,
                            ),
                          ],
                          if (_showsAmountFilter) ...[
                            const SizedBox(height: 20),
                            _sectionLabel(_amountSectionLabel()),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _LogAmountField(
                                    controller: _minAmountController,
                                    hint: 'Min',
                                    hasError: _amountErrorText != null,
                                    onChanged: _handleAmountChanged,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _LogAmountField(
                                    controller: _maxAmountController,
                                    hint: 'Max',
                                    hasError: _amountErrorText != null,
                                    onChanged: _handleAmountChanged,
                                  ),
                                ),
                              ],
                            ),
                            if (_amountErrorText != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _amountErrorText!,
                                style: const TextStyle(
                                  color: AppColors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    if (_hasEntityScopedFilters) ...[
                      const SizedBox(height: 20),
                      _filterDivider(),
                    ],
                    const SizedBox(height: 20),
                    _sectionLabel('ATTEMPTS'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _LogFilterChoice(
                          label: 'All',
                          selected: _attempts.isEmpty,
                          onTap: () => setState(() => _attempts.clear()),
                        ),
                        _LogFilterChoice(
                          label: 'Not retried',
                          selected:
                              _attempts.contains(_LogAttemptFilter.untried),
                          onTap: () => setState(
                            () => _toggleInSet(
                              _attempts,
                              _LogAttemptFilter.untried,
                            ),
                          ),
                        ),
                        _LogFilterChoice(
                          label: 'Retried',
                          selected:
                              _attempts.contains(_LogAttemptFilter.retried),
                          onTap: () => setState(
                            () => _toggleInSet(
                              _attempts,
                              _LogAttemptFilter.retried,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('HTTP RESULT'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _LogFilterChoice(
                          label: 'All',
                          selected: _http.isEmpty,
                          onTap: () => setState(() => _http.clear()),
                        ),
                        _LogFilterChoice(
                          label: 'Any HTTP',
                          selected: _http.contains(_LogHttpFilter.anyCode),
                          onTap: () => setState(
                            () => _toggleInSet(_http, _LogHttpFilter.anyCode),
                          ),
                        ),
                        _LogFilterChoice(
                          label: 'Success',
                          selected: _http.contains(_LogHttpFilter.success),
                          onTap: () => setState(
                            () => _toggleInSet(_http, _LogHttpFilter.success),
                          ),
                        ),
                        _LogFilterChoice(
                          label: 'Error',
                          selected: _http.contains(_LogHttpFilter.error),
                          onTap: () => setState(
                            () => _toggleInSet(_http, _LogHttpFilter.error),
                          ),
                        ),
                        _LogFilterChoice(
                          label: 'No HTTP',
                          selected: _http.contains(_LogHttpFilter.noCode),
                          onTap: () => setState(
                            () => _toggleInSet(_http, _LogHttpFilter.noCode),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _filterDivider(),
                    const SizedBox(height: 20),
                    _sectionLabel('UPDATED DATE'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _LogDateField(
                            hint: 'Start date',
                            value: _startDate == null
                                ? null
                                : _formatDate(_startDate!),
                            onTap: () => _pickDate(isStart: true),
                            onClear: _startDate == null
                                ? null
                                : () => setState(() => _startDate = null),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _LogDateField(
                            hint: 'End date',
                            value: _endDate == null
                                ? null
                                : _formatDate(_endDate!),
                            onTap: () => _pickDate(isStart: false),
                            onClear: _endDate == null
                                ? null
                                : () => setState(() => _endDate = null),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _actionBar(navBarPadding),
          ],
        ),
      ),
    );
  }

  Widget _activeCountBadge() {
    final foreground = AppColors.isDark(context)
        ? AppColors.primaryLight
        : AppColors.primaryDark;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 140),
      child: Container(
        key: ValueKey(_draftActiveCount),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: foreground.withValues(alpha: 0.18)),
        ),
        child: Text(
          '$_draftActiveCount active',
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _actionBar(double navBarPadding) {
    final activeCount = _draftActiveCount;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        border: Border(
          top: BorderSide(
            color: AppColors.borderColor(context),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + navBarPadding),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _hasDraftFilters ? _clearAll : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary(context),
                disabledForegroundColor:
                    AppColors.textTertiary(context).withValues(alpha: 0.7),
                side: BorderSide(color: AppColors.borderColor(context)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Clear',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: Text(
                  activeCount == 0 ? 'Apply' : 'Apply ($activeCount)',
                  key: ValueKey(activeCount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterDivider() {
    return Container(
      height: 1,
      color: AppColors.borderColor(context).withValues(
        alpha: AppColors.isDark(context) ? 0.55 : 0.8,
      ),
    );
  }

  Widget _bankFilterSection(String label, List<int> bankIds) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        const SizedBox(height: 8),
        _horizontalChoices(
          [
            _LogFilterChoice(
              label: 'All Banks',
              selected: _bankIds.isEmpty,
              onTap: () => setState(() => _bankIds.clear()),
            ),
            for (final bankId in bankIds)
              _LogFilterChoice(
                label: widget.bankLabelForId(bankId),
                selected: _bankIds.contains(bankId),
                onTap: () => setState(
                  () => _toggleInSet(_bankIds, bankId),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _horizontalChoices(List<Widget> children) {
    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Transform.translate(
        offset: const Offset(-20, 0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _amountSectionLabel() {
    final labels = <String>[];
    if (_showsTransactions) labels.add('transaction amount');
    if (_showsAccounts) labels.add('account balance');
    if (_showsBudgets) labels.add('budget amount');
    if (labels.length == 1) return labels.first.toUpperCase();
    return 'MONEY RANGE';
  }

  String _formatDate(DateTime value) =>
      '${_months[value.month - 1]} ${value.day}';
}

class _LogFilterChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LogFilterChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    final maxLabelWidth = MediaQuery.of(context).size.width - 108;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: BoxConstraints(maxWidth: maxLabelWidth + 42),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryDark
                : AppColors.surfaceColor(context),
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? AppColors.primaryDark
                  : AppColors.borderColor(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(
                  AppIcons.check_rounded,
                  size: 13,
                  color: AppColors.white,
                ),
                const SizedBox(width: 5),
              ],
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? AppColors.white
                        : AppColors.textSecondary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountInputFormatter extends TextInputFormatter {
  const _AmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    for (final codeUnit in newValue.text.codeUnits) {
      final isDigit = codeUnit >= 48 && codeUnit <= 57;
      final isSeparator = codeUnit == 44 || codeUnit == 46;
      if (!isDigit && !isSeparator) return oldValue;
    }
    return newValue;
  }
}

class _LogAmountField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  const _LogAmountField({
    required this.controller,
    required this.hint,
    required this.hasError,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [_AmountInputFormatter()],
      style: TextStyle(
        color: AppColors.textPrimary(context),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        prefixText: 'ETB ',
        prefixStyle: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: AppColors.surfaceColor(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.borderColor(context),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.borderColor(context),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.primaryLight,
          ),
        ),
      ),
    );
  }
}

class _LogDateField extends StatelessWidget {
  final String hint;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _LogDateField({
    required this.hint,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                style: TextStyle(
                  color: value != null
                      ? AppColors.textPrimary(context)
                      : AppColors.textTertiary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  AppIcons.close,
                  size: 16,
                  color: AppColors.textTertiary(context),
                ),
              )
            else
              Icon(
                AppIcons.calendar_today_outlined,
                size: 16,
                color: AppColors.textTertiary(context),
              ),
          ],
        ),
      ),
    );
  }
}
