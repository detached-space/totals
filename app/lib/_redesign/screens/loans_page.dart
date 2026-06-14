import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/loan_debt_entry.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/loan_debt_repository.dart';
import 'package:totals/utils/app_date_format.dart';
import 'package:totals/utils/loan_debt_utils.dart';
import 'package:totals/utils/text_utils.dart';

Future<bool> showLoanDebtPersonSheet({
  required BuildContext context,
  required Transaction transaction,
  LoanDebtRepository? repository,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.black.withValues(alpha: 0.5),
    builder: (_) => _LoanDebtPersonSheet(
      transaction: transaction,
      repository: repository ?? LoanDebtRepository(),
    ),
  );
  return result ?? false;
}

class LoansPage extends StatefulWidget {
  const LoansPage({super.key});

  @override
  State<LoansPage> createState() => _LoansPageState();
}

enum _LoanDebtTransactionFilter { all, lent, borrowed }

enum _LoanDebtStatusFilter { all, active, settled, forgiven }

class _LoanDebtFilterSelection {
  final _LoanDebtTransactionFilter transactionFilter;
  final _LoanDebtStatusFilter statusFilter;
  final String? personName;
  final int? bankId;
  final double? minAmount;
  final double? maxAmount;
  final DateTime? startDate;
  final DateTime? endDate;

  const _LoanDebtFilterSelection({
    required this.transactionFilter,
    this.statusFilter = _LoanDebtStatusFilter.all,
    required this.personName,
    this.bankId,
    this.minAmount,
    this.maxAmount,
    this.startDate,
    this.endDate,
  });

  int get activeCount {
    var count = 0;
    if (transactionFilter != _LoanDebtTransactionFilter.all) count++;
    if (statusFilter != _LoanDebtStatusFilter.all) count++;
    if (personName?.trim().isNotEmpty == true) count++;
    if (bankId != null) count++;
    if (minAmount != null || maxAmount != null) count++;
    if (startDate != null || endDate != null) count++;
    return count;
  }
}

class _LoansPageState extends State<LoansPage> {
  final LoanDebtRepository _repository = LoanDebtRepository();
  late Future<List<LoanDebtEntry>> _entriesFuture;
  String? _selectedPerson;
  _LoanDebtTransactionFilter _transactionFilter =
      _LoanDebtTransactionFilter.all;
  _LoanDebtStatusFilter _statusFilter = _LoanDebtStatusFilter.all;
  int? _selectedBankId;
  double? _minAmount;
  double? _maxAmount;
  DateTime? _startDate;
  DateTime? _endDate;
  _LoanDebtTransactionFilter _unassignedTransactionFilter =
      _LoanDebtTransactionFilter.all;
  int? _unassignedBankId;
  double? _unassignedMinAmount;
  double? _unassignedMaxAmount;
  DateTime? _unassignedStartDate;
  DateTime? _unassignedEndDate;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _repository.getEntries();
  }

  void _refreshEntries() {
    setState(() {
      _entriesFuture = _repository.getEntries();
    });
  }

  List<_LoanDebtItem> _filterItems(List<_LoanDebtItem> items) {
    return _filteredLoanDebtItems(
      items,
      _transactionFilter,
      statusFilter: _statusFilter,
      bankId: _selectedBankId,
      minAmount: _minAmount,
      maxAmount: _maxAmount,
      startDate: _startDate,
      endDate: _endDate,
    );
  }

  _LoanDebtFilterSelection get _assignedFilterSelection =>
      _LoanDebtFilterSelection(
        transactionFilter: _transactionFilter,
        statusFilter: _statusFilter,
        personName: _selectedPerson,
        bankId: _selectedBankId,
        minAmount: _minAmount,
        maxAmount: _maxAmount,
        startDate: _startDate,
        endDate: _endDate,
      );

  _LoanDebtFilterSelection get _unassignedFilterSelection =>
      _LoanDebtFilterSelection(
        transactionFilter: _unassignedTransactionFilter,
        personName: null,
        bankId: _unassignedBankId,
        minAmount: _unassignedMinAmount,
        maxAmount: _unassignedMaxAmount,
        startDate: _unassignedStartDate,
        endDate: _unassignedEndDate,
      );

  List<int> _bankIdsForItems(List<_LoanDebtItem> items) {
    final bankIds = <int>{};
    for (final item in items) {
      final bankId = item.transaction.bankId;
      if (bankId != null) bankIds.add(bankId);
    }
    return bankIds.toList()..sort();
  }

  Future<void> _openTransactionFilterSheet({
    required List<_LoanDebtPersonSummary> people,
    required List<int> bankIds,
  }) async {
    final selected = await showModalBottomSheet<_LoanDebtFilterSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _TransactionFilterSheet(
        selectedTransactionFilter: _transactionFilter,
        selectedStatusFilter: _statusFilter,
        selectedPerson: _selectedPerson,
        people: people,
        bankIds: bankIds,
        selectedBankId: _selectedBankId,
        minAmount: _minAmount,
        maxAmount: _maxAmount,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _transactionFilter = selected.transactionFilter;
      _statusFilter = selected.statusFilter;
      _selectedPerson = selected.personName;
      _selectedBankId = selected.bankId;
      _minAmount = selected.minAmount;
      _maxAmount = selected.maxAmount;
      _startDate = selected.startDate;
      _endDate = selected.endDate;
    });
  }

  Future<void> _openUnassignedTransactionFilterSheet({
    required List<int> bankIds,
  }) async {
    final selected = await showModalBottomSheet<_LoanDebtFilterSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _TransactionFilterSheet(
        selectedTransactionFilter: _unassignedTransactionFilter,
        selectedStatusFilter: _LoanDebtStatusFilter.all,
        showStatusFilter: false,
        bankIds: bankIds,
        selectedBankId: _unassignedBankId,
        minAmount: _unassignedMinAmount,
        maxAmount: _unassignedMaxAmount,
        startDate: _unassignedStartDate,
        endDate: _unassignedEndDate,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _unassignedTransactionFilter = selected.transactionFilter;
      _unassignedBankId = selected.bankId;
      _unassignedMinAmount = selected.minAmount;
      _unassignedMaxAmount = selected.maxAmount;
      _unassignedStartDate = selected.startDate;
      _unassignedEndDate = selected.endDate;
    });
  }

  Future<void> _openPersonPage({
    required _LoanDebtPersonSummary person,
    required List<_LoanDebtItem> items,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _LoanDebtPersonDetailPage(
          person: person,
          items: items,
          repository: _repository,
        ),
      ),
    );
    if (!mounted) return;
    _refreshEntries();
  }

  Future<void> _openLoanDebtDetailsSheet(_LoanDebtItem item) async {
    final result = await showModalBottomSheet<_LoanDebtDetailsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _LoanDebtDetailsSheet(
        item: item,
        repository: _repository,
      ),
    );
    if (!mounted) return;
    if (result != null) _refreshEntries();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: FutureBuilder<List<LoanDebtEntry>>(
          future: _entriesFuture,
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const <LoanDebtEntry>[];
            final dashboard = _LoanDebtDashboard.from(
              transactions: provider.allTransactions,
              categories: provider.categories,
              entries: entries,
            );
            final people = dashboard.people;
            final selectedPerson = _selectedPerson;
            final visibleItems = selectedPerson == null
                ? dashboard.assignedItems
                : dashboard.assignedItems
                    .where((item) => item.personName == selectedPerson)
                    .toList(growable: false);
            final filteredVisibleItems = _filterItems(visibleItems);
            final filteredUnassignedItems = _filteredLoanDebtItems(
              dashboard.unassignedItems,
              _unassignedTransactionFilter,
              bankId: _unassignedBankId,
              minAmount: _unassignedMinAmount,
              maxAmount: _unassignedMaxAmount,
              startDate: _unassignedStartDate,
              endDate: _unassignedEndDate,
            );
            final assignedBankIds = _bankIdsForItems(dashboard.assignedItems);
            final unassignedBankIds =
                _bankIdsForItems(dashboard.unassignedItems);

            return RefreshIndicator(
              onRefresh: () async {
                await provider.loadData();
                _refreshEntries();
                await _entriesFuture;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _LoansHeader(
                    isRefreshing:
                        snapshot.connectionState == ConnectionState.waiting,
                    onRefresh: _refreshEntries,
                  ),
                  const SizedBox(height: 18),
                  _LoansSummaryRow(dashboard: dashboard),
                  const SizedBox(height: 18),
                  if (dashboard.hasAnyLoanDebtTransaction) ...[
                    if (people.isNotEmpty) ...[
                      _SectionHeader(
                        title: context.l10nText('People'),
                        subtitle: context.l10nText('Current balances'),
                      ),
                      const SizedBox(height: 10),
                      for (final person in people)
                        _PersonBalanceTile(
                          person: person,
                          onTap: () => _openPersonPage(
                            person: person,
                            items: dashboard.itemsForPerson(person.name),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                    _TransactionsHeader(
                      title: context.l10nText('Transactions'),
                      subtitle: selectedPerson ??
                          context.l10nText('Linked loans and debts'),
                      activeFilterCount: _assignedFilterSelection.activeCount,
                      onFilterTap: () => _openTransactionFilterSheet(
                        people: people,
                        bankIds: assignedBankIds,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (filteredVisibleItems.isEmpty)
                      _EmptyPanel(
                        icon: AppIcons.filter_list,
                        title: context.l10nText('No matching transactions'),
                        subtitle: context.l10nText(
                          'Change the filter or choose another person.',
                        ),
                      )
                    else
                      for (final item in filteredVisibleItems)
                        _LoanDebtTransactionTile(
                          item: item,
                          onTap: () => _openLoanDebtDetailsSheet(item),
                        ),
                    if (dashboard.unassignedItems.isNotEmpty &&
                        selectedPerson == null) ...[
                      const SizedBox(height: 18),
                      _TransactionsHeader(
                        title: context.l10nText('Unlinked debts and loans'),
                        subtitle: context.l10nText('Needs a person'),
                        activeFilterCount:
                            _unassignedFilterSelection.activeCount,
                        onFilterTap: () =>
                            _openUnassignedTransactionFilterSheet(
                          bankIds: unassignedBankIds,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (filteredUnassignedItems.isEmpty)
                        _EmptyPanel(
                          icon: AppIcons.filter_list,
                          title: context.l10nText('No matching transactions'),
                          subtitle: context.l10nText(
                            'Change the filter to see other unlinked debts and loans.',
                          ),
                        )
                      else
                        for (final item in filteredUnassignedItems)
                          _UnassignedLoanDebtTile(
                            item: item,
                            onTap: () => _openLoanDebtDetailsSheet(item),
                          ),
                    ],
                  ] else
                    _EmptyPanel(
                      icon: AppIcons.debts,
                      title: context.l10nText('No loans or debts yet'),
                      subtitle: context.l10nText(
                        'Categorize a transaction as Loan or Debt to track who it belongs to.',
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoanDebtPersonSheet extends StatefulWidget {
  final Transaction transaction;
  final LoanDebtRepository repository;

  const _LoanDebtPersonSheet({
    required this.transaction,
    required this.repository,
  });

  @override
  State<_LoanDebtPersonSheet> createState() => _LoanDebtPersonSheetState();
}

class _LoanDebtPersonSheetState extends State<_LoanDebtPersonSheet> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  List<String> _knownPeople = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _selectedName;

  LoanDebtDirection get _direction =>
      loanDebtDirectionForTransaction(widget.transaction);

  bool get _isBorrowed => _direction == LoanDebtDirection.borrowed;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final List<Object?> results;
    try {
      results = await Future.wait<Object?>([
        widget.repository.getKnownPeople(),
        widget.repository.getEntryForTransaction(widget.transaction.reference),
      ]);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }
    if (!mounted) return;

    final people = (results[0] as List<String>)
        .where((name) => name.trim().isNotEmpty)
        .toList(growable: true);
    final entry = results[1] as LoanDebtEntry?;
    final existingName = entry?.personName.trim();
    if (existingName != null &&
        existingName.isNotEmpty &&
        !people
            .any((name) => name.toLowerCase() == existingName.toLowerCase())) {
      people.insert(0, existingName);
    }
    final selectedName =
        existingName != null && existingName.isNotEmpty ? existingName : null;

    setState(() {
      _knownPeople = people;
      _selectedName = selectedName;
      _nameController.text = _selectedName ?? '';
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    final personName = normalizeLoanDebtPersonName(_nameController.text);
    if (personName.isEmpty || _isSaving) {
      _nameFocus.requestFocus();
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.repository.upsertTransactionPerson(
        transactionReference: widget.transaction.reference,
        personName: personName,
        direction: _direction,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10nTextRead('Could not save person')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final title = _isBorrowed
        ? context.l10nText('Who lent you this?')
        : context.l10nText('Who did you lend to?');
    final subtitle = _isBorrowed
        ? context.l10nText('Choose who you took this money from.')
        : context.l10nText('Choose who you gave this money to.');
    final amount = _formatEtb(widget.transaction.amount.abs(), context);
    final canSubmit =
        normalizeLoanDebtPersonName(_nameController.text).isNotEmpty &&
            !_isSaving;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderColor(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: (_isBorrowed
                                ? AppColors.red
                                : AppColors.incomeSuccess)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        AppIcons.debts,
                        color: _isBorrowed
                            ? AppColors.red
                            : AppColors.incomeSuccess,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$subtitle $amount',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary(context),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_isLoading)
                  const LinearProgressIndicator(minHeight: 2)
                else if (_knownPeople.isNotEmpty) ...[
                  Text(
                    context.l10nText('Choose a person'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _knownPeople.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final name = _knownPeople[index];
                        final selected =
                            _selectedName?.toLowerCase() == name.toLowerCase();
                        return ChoiceChip(
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          selected: selected,
                          onSelected: (_) {
                            setState(() {
                              _selectedName = name;
                              _nameController.text = name;
                            });
                          },
                          selectedColor:
                              AppColors.primaryLight.withValues(alpha: 0.16),
                          backgroundColor: AppColors.surfaceColor(context),
                          side: BorderSide(
                            color: selected
                                ? AppColors.primaryLight
                                : AppColors.borderColor(context),
                          ),
                          labelStyle: theme.textTheme.labelLarge?.copyWith(
                            color: selected
                                ? AppColors.primaryLight
                                : AppColors.textPrimary(context),
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                TextField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: (value) {
                    final normalized = normalizeLoanDebtPersonName(value);
                    setState(() {
                      _selectedName = normalized.isEmpty ? null : normalized;
                    });
                  },
                  onSubmitted: (_) => _save(),
                  style: TextStyle(color: AppColors.textPrimary(context)),
                  decoration: InputDecoration(
                    labelText: context.l10nText('Name'),
                    hintText: context.l10nText('Enter a new name'),
                    prefixIcon: const Icon(AppIcons.person_outline),
                    filled: true,
                    fillColor: AppColors.surfaceColor(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: AppColors.borderColor(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: AppColors.borderColor(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.primaryLight),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: canSubmit ? _save : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryLight,
                      foregroundColor: AppColors.white,
                      disabledBackgroundColor:
                          AppColors.primaryLight.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : Text(context.l10nText('Save')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoansHeader extends StatelessWidget {
  final bool isRefreshing;
  final VoidCallback onRefresh;

  const _LoansHeader({
    required this.isRefreshing,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.textPrimary(context),
            ),
            icon: const Icon(AppIcons.arrow_back_rounded, size: 20),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10nText('Loans & debts'),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                context.l10nText('Track who owes whom from transactions.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: isRefreshing ? null : onRefresh,
            style: IconButton.styleFrom(
              foregroundColor: AppColors.textPrimary(context),
            ),
            icon: isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.refresh, size: 20),
          ),
        ),
      ],
    );
  }
}

class _LoansSummaryRow extends StatelessWidget {
  final _LoanDebtDashboard dashboard;

  const _LoansSummaryRow({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryMetric(
              title: context.l10nText('Owed'),
              value: _formatEtbCompact(dashboard.totalLent, context),
              icon: AppIcons.trending_up_rounded,
              color: AppColors.incomeSuccess,
            ),
          ),
          const _MetricDivider(),
          Expanded(
            child: _SummaryMetric(
              title: context.l10nText('Owe'),
              value: _formatEtbCompact(dashboard.totalBorrowed, context),
              icon: AppIcons.trending_down_rounded,
              color: AppColors.red,
            ),
          ),
          const _MetricDivider(),
          Expanded(
            child: _SummaryMetric(
              title: context.l10nText('People'),
              value: dashboard.people.length.toString(),
              icon: AppIcons.group_outlined,
              color: AppColors.blue,
            ),
          ),
          const _MetricDivider(),
          Expanded(
            child: _SummaryMetric(
              title: context.l10nText('Open'),
              value: dashboard.unassignedItems.length.toString(),
              icon: AppIcons.person_outline,
              color: AppColors.amber,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: AppColors.borderColor(context),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryMetric({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 5),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w800,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonBalanceTile extends StatelessWidget {
  final _LoanDebtPersonSummary person;
  final VoidCallback onTap;

  const _PersonBalanceTile({
    required this.person,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasOpenBalance = person.net.abs() > 0.005;
    final isOwedToYou = person.net >= 0;
    final color = !hasOpenBalance
        ? AppColors.blue
        : (isOwedToYou ? AppColors.incomeSuccess : AppColors.red);
    final label = !hasOpenBalance
        ? context.l10nText('Settled')
        : (isOwedToYou
            ? context.l10nText('They owe you')
            : context.l10nText('You owe'));
    final transactionCountLabel = _formatTransactionCount(
      context,
      person.transactionCount,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: Row(
              children: [
                _PersonAvatar(name: person.name, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              person.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textPrimary(context),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TinyStatusPill(label: label, color: color),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            AppIcons.receipt_long_rounded,
                            size: 14,
                            color: AppColors.textTertiary(context),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            transactionCountLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.textSecondary(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 118),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          _formatEtb(person.net.abs(), context),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Icon(
                      AppIcons.chevron_right_rounded,
                      color: AppColors.textTertiary(context),
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TinyStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _TinyStatusPill({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _TransactionsHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int activeFilterCount;
  final VoidCallback onFilterTap;

  const _TransactionsHeader({
    required this.title,
    required this.subtitle,
    required this.activeFilterCount,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _LoanDebtFilterActionButton(
          onTap: onFilterTap,
          activeFilterCount: activeFilterCount,
        ),
      ],
    );
  }
}

class _LoanDebtFilterActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final int activeFilterCount;

  const _LoanDebtFilterActionButton({
    required this.onTap,
    this.activeFilterCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final hasFilters = activeFilterCount > 0;
    const badgeSize = size <= 40 ? 16.0 : 18.0;
    const badgeOffset = size <= 40 ? -3.0 : -4.0;
    const iconSize = size <= 40 ? 18.0 : 22.0;
    const borderRadius = size <= 40 ? 9.0 : 10.0;
    const badgeFontSize = size <= 40 ? 9.0 : 10.0;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: hasFilters
                  ? AppColors.primaryDark.withValues(alpha: 0.1)
                  : AppColors.cardColor(context),
              borderRadius: BorderRadius.circular(borderRadius),
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
              size: iconSize,
            ),
          ),
          if (hasFilters)
            Positioned(
              top: badgeOffset,
              right: badgeOffset,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$activeFilterCount',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: badgeFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoanDebtTransactionTile extends StatelessWidget {
  final _LoanDebtItem item;
  final VoidCallback onTap;

  const _LoanDebtTransactionTile({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _LoanDebtBaseTile(
      item: item,
      personName: item.personName,
      onTap: onTap,
    );
  }
}

class _UnassignedLoanDebtTile extends StatelessWidget {
  final _LoanDebtItem item;
  final VoidCallback onTap;

  const _UnassignedLoanDebtTile({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _LoanDebtBaseTile(
      item: item,
      personName: context.l10nText('Needs a person'),
      onTap: onTap,
    );
  }
}

class _LoanDebtBaseTile extends StatelessWidget {
  final _LoanDebtItem item;
  final String personName;
  final VoidCallback? onTap;

  const _LoanDebtBaseTile({
    required this.item,
    required this.personName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.read<TransactionProvider>();
    final borrowed = item.direction == LoanDebtDirection.borrowed;
    final directionColor = borrowed ? AppColors.red : AppColors.incomeSuccess;
    final color = _loanDebtStatusColor(item.status, directionColor);
    final bankName = context.l10nText(
      provider.getBankShortName(item.transaction.bankId),
    );
    final details = [
      if (!item.isActive) _loanDebtStatusLabel(context, item.status),
      bankName,
      item.dateLabel(context),
      item.timeLabel(context),
    ].where((value) => value.trim().isNotEmpty).join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 74,
                  color: color,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        personName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 122),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _formatEtb(item.amount, context),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoanDebtDetailsSheet extends StatefulWidget {
  final _LoanDebtItem item;
  final LoanDebtRepository repository;

  const _LoanDebtDetailsSheet({
    required this.item,
    required this.repository,
  });

  @override
  State<_LoanDebtDetailsSheet> createState() => _LoanDebtDetailsSheetState();
}

class _LoanDebtDetailsResult {
  final String transactionReference;
  final LoanDebtStatus? status;
  final bool unlinked;

  const _LoanDebtDetailsResult._({
    required this.transactionReference,
    this.status,
    this.unlinked = false,
  });

  const _LoanDebtDetailsResult.savedPerson(String transactionReference)
      : this._(transactionReference: transactionReference);

  const _LoanDebtDetailsResult.unlinked(String transactionReference)
      : this._(transactionReference: transactionReference, unlinked: true);

  const _LoanDebtDetailsResult.status(
    String transactionReference,
    LoanDebtStatus status,
  ) : this._(transactionReference: transactionReference, status: status);
}

class _LoanDebtDetailsSheetState extends State<_LoanDebtDetailsSheet> {
  static const Duration _confirmWindow = Duration(milliseconds: 3500);

  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  List<String> _knownPeople = const [];
  bool _isLoadingPeople = true;
  bool _isSavingPerson = false;
  Timer? _actionDisarmTimer;
  String? _armedAction;
  String? _pendingAction;
  String? _selectedName;

  _LoanDebtItem get _item => widget.item;
  Transaction get _transaction => _item.transaction;
  bool get _needsPerson => !_item.hasPerson;
  bool get _isBorrowed => _item.direction == LoanDebtDirection.borrowed;
  bool get _isActionBusy => _pendingAction != null;
  Color get _directionColor =>
      _isBorrowed ? AppColors.red : AppColors.incomeSuccess;

  @override
  void initState() {
    super.initState();
    if (_needsPerson) {
      _loadKnownPeople();
    } else {
      _isLoadingPeople = false;
    }
  }

  Future<void> _loadKnownPeople() async {
    try {
      final people = await widget.repository.getKnownPeople();
      if (!mounted) return;
      setState(() {
        _knownPeople = people
            .where((name) => name.trim().isNotEmpty)
            .toList(growable: false);
        _isLoadingPeople = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingPeople = false);
    }
  }

  Future<void> _savePerson() async {
    final personName = normalizeLoanDebtPersonName(_nameController.text);
    if (personName.isEmpty || _isSavingPerson || _isActionBusy) {
      _nameFocus.requestFocus();
      return;
    }

    setState(() => _isSavingPerson = true);
    try {
      await widget.repository.upsertTransactionPerson(
        transactionReference: _transaction.reference,
        personName: personName,
        direction: _item.direction,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        _LoanDebtDetailsResult.savedPerson(_transaction.reference),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10nTextRead('Could not save person')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isSavingPerson = false);
    }
  }

  bool _armOrConfirm(String action) {
    if (_armedAction != action) {
      setState(() => _armedAction = action);
      _actionDisarmTimer?.cancel();
      _actionDisarmTimer = Timer(_confirmWindow, () {
        if (!mounted) return;
        setState(() => _armedAction = null);
      });
      return false;
    }

    _actionDisarmTimer?.cancel();
    setState(() => _armedAction = null);
    return true;
  }

  Future<void> _unlinkPerson() async {
    if (_isActionBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_armOrConfirm('unlink')) return;

    setState(() => _pendingAction = 'unlink');
    try {
      await widget.repository.deleteEntryForTransaction(_transaction.reference);
      if (!mounted) return;
      Navigator.pop(
        context,
        _LoanDebtDetailsResult.unlinked(_transaction.reference),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10nTextRead('Could not unlink person')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _pendingAction = null);
    }
  }

  Future<void> _resolveLoanDebt(LoanDebtStatus status) async {
    if (_isActionBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_armOrConfirm(status.storageValue)) return;

    setState(() => _pendingAction = status.storageValue);
    try {
      await widget.repository.updateEntryStatus(
        transactionReference: _transaction.reference,
        status: status,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        _LoanDebtDetailsResult.status(_transaction.reference, status),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10nTextRead('Could not update loan or debt')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _pendingAction = null);
    }
  }

  @override
  void dispose() {
    _actionDisarmTimer?.cancel();
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String _dateTimeLabel(BuildContext context) {
    final date = _item.dateLabel(context);
    final time = _item.timeLabel(context);
    if (time.trim().isEmpty) return date;
    return '$date · $time';
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isBorrowed
        ? context.l10nText('Debt details')
        : context.l10nText('Loan details');
    final status =
        _isBorrowed ? context.l10nText('Borrowed') : context.l10nText('Lent');
    final statusColor = _loanDebtStatusColor(_item.status, _directionColor);
    final subtitle =
        _needsPerson ? context.l10nText('Needs a person') : _item.personName;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _directionColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            AppIcons.debts,
            color: _directionColor,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _TinyStatusPill(label: status, color: _directionColor),
                      if (!_item.isActive) ...[
                        const SizedBox(height: 5),
                        _TinyStatusPill(
                          label: _loanDebtStatusLabel(context, _item.status),
                          color: statusColor,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _formatEtb(_item.amount, context),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLinkedPersonPanel(BuildContext context) {
    final theme = Theme.of(context);
    final status = _item.isActive
        ? (_isBorrowed
            ? context.l10nText('You owe')
            : context.l10nText('They owe you'))
        : _loanDebtStatusLabel(context, _item.status);
    final statusColor = _loanDebtStatusColor(_item.status, _directionColor);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        children: [
          _PersonAvatar(name: _item.personName, color: _directionColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10nText('Linked to'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _item.personName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _TinyStatusPill(label: status, color: statusColor),
        ],
      ),
    );
  }

  Widget _buildPersonAssignmentSection(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isBorrowed
        ? context.l10nText('Who lent you this?')
        : context.l10nText('Who did you loan this to?');
    final subtitle = _isBorrowed
        ? context.l10nText('Choose who you took this money from.')
        : context.l10nText('Choose who you gave this money to.');
    final canSubmit =
        normalizeLoanDebtPersonName(_nameController.text).isNotEmpty &&
            !_isSavingPerson;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  AppIcons.person_outline,
                  color: AppColors.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingPeople)
            const LinearProgressIndicator(minHeight: 2)
          else if (_knownPeople.isNotEmpty) ...[
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _knownPeople.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final name = _knownPeople[index];
                  final selected =
                      _selectedName?.toLowerCase() == name.toLowerCase();
                  return ChoiceChip(
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        _selectedName = name;
                        _nameController.text = name;
                      });
                    },
                    selectedColor:
                        AppColors.primaryLight.withValues(alpha: 0.16),
                    backgroundColor: AppColors.cardColor(context),
                    side: BorderSide(
                      color: selected
                          ? AppColors.primaryLight
                          : AppColors.borderColor(context),
                    ),
                    labelStyle: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? AppColors.primaryLight
                          : AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: (value) {
              final normalized = normalizeLoanDebtPersonName(value);
              setState(() {
                _selectedName = normalized.isEmpty ? null : normalized;
              });
            },
            onSubmitted: (_) => _savePerson(),
            style: TextStyle(color: AppColors.textPrimary(context)),
            decoration: InputDecoration(
              labelText: context.l10nText('Name'),
              hintText: context.l10nText('Enter a new name'),
              prefixIcon: const Icon(AppIcons.person_outline),
              filled: true,
              fillColor: AppColors.cardColor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.borderColor(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.borderColor(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primaryLight),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: canSubmit ? _savePerson : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryLight,
                foregroundColor: AppColors.white,
                disabledBackgroundColor:
                    AppColors.primaryLight.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isSavingPerson
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : Text(context.l10nText('Save person')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRows(
    BuildContext context,
    TransactionProvider provider,
  ) {
    final rows = <_LoanDebtDetailRow>[];

    void addRow({
      required IconData icon,
      required String label,
      required String? value,
    }) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) return;
      rows.add(
        _LoanDebtDetailRow(
          icon: icon,
          label: label,
          value: trimmed,
        ),
      );
    }

    addRow(
      icon: AppIcons.account_balance,
      label: context.l10nText('Bank'),
      value: context.l10nText(provider.getBankName(_transaction.bankId)),
    );
    addRow(
      icon: AppIcons.calendar_today_outlined,
      label: context.l10nText('Date & Time'),
      value: _dateTimeLabel(context),
    );
    addRow(
      icon: AppIcons.category,
      label: context.l10nText('Category'),
      value: context.l10nText(
        provider.categoryLabelForTransaction(
          _transaction,
          uncategorizedLabel: context.l10nText('Uncategorized'),
        ),
      ),
    );
    addRow(
      icon: AppIcons.account_balance_wallet_outlined,
      label: context.l10nText('Account'),
      value: _transaction.accountNumber,
    );
    addRow(
      icon: AppIcons.person_outline,
      label: context.l10nText('Receiver'),
      value: _transaction.receiver,
    );
    addRow(
      icon: AppIcons.person_outline,
      label: context.l10nText('Creditor'),
      value: _transaction.creditor,
    );
    addRow(
      icon: AppIcons.sms_outlined,
      label: context.l10nText('Note'),
      value: _transaction.note,
    );
    addRow(
      icon: AppIcons.receipt_long_rounded,
      label: context.l10nText('Reference'),
      value: _transaction.reference,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1)
              Divider(
                height: 20,
                color: AppColors.borderColor(context),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionsSection(BuildContext context) {
    if (_needsPerson) return const SizedBox.shrink();
    final settleArmed = _armedAction == LoanDebtStatus.settled.storageValue;
    final forgiveArmed = _armedAction == LoanDebtStatus.forgiven.storageValue;
    final undoArmed = _armedAction == LoanDebtStatus.active.storageValue;
    final unlinkArmed = _armedAction == 'unlink';
    final buttons = <Widget>[
      if (_item.isActive) ...[
        _LoanDebtActionButton(
          icon: AppIcons.check_circle_rounded,
          label: settleArmed
              ? context.l10nText('Tap again')
              : context.l10nText('Settled'),
          color: AppColors.incomeSuccess,
          isLoading: _pendingAction == LoanDebtStatus.settled.storageValue,
          enabled: !_isActionBusy,
          armed: settleArmed,
          onTap: () => _resolveLoanDebt(LoanDebtStatus.settled),
        ),
        _LoanDebtActionButton(
          icon: AppIcons.favorite_rounded,
          label: forgiveArmed
              ? context.l10nText('Tap again')
              : (_isBorrowed
                  ? context.l10nText('Forgiven')
                  : context.l10nText('Forgive')),
          color: AppColors.red,
          isLoading: _pendingAction == LoanDebtStatus.forgiven.storageValue,
          enabled: !_isActionBusy,
          armed: forgiveArmed,
          onTap: () => _resolveLoanDebt(LoanDebtStatus.forgiven),
        ),
      ] else ...[
        _LoanDebtActionButton(
          icon: AppIcons.refresh,
          label: undoArmed
              ? context.l10nText('Tap again')
              : context.l10nText(
                  _item.status == LoanDebtStatus.forgiven
                      ? 'Unforgive'
                      : 'Unsettle',
                ),
          color: AppColors.blue,
          isLoading: _pendingAction == LoanDebtStatus.active.storageValue,
          enabled: !_isActionBusy,
          armed: undoArmed,
          onTap: () => _resolveLoanDebt(LoanDebtStatus.active),
        ),
      ],
      _LoanDebtActionButton(
        icon: AppIcons.close_rounded,
        label: unlinkArmed
            ? context.l10nText('Tap again')
            : context.l10nText('Unlink'),
        color: AppColors.primaryLight,
        isLoading: _pendingAction == 'unlink',
        enabled: !_isActionBusy,
        armed: unlinkArmed,
        onTap: _unlinkPerson,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10nText('Actions'),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var index = 0; index < buttons.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(child: buttons[index]),
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TransactionProvider>();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderColor(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _buildHeader(context),
                const SizedBox(height: 18),
                if (_needsPerson)
                  _buildPersonAssignmentSection(context)
                else
                  _buildLinkedPersonPanel(context),
                const SizedBox(height: 14),
                _buildDetailRows(context, provider),
                if (!_needsPerson) ...[
                  const SizedBox(height: 14),
                  _buildActionsSection(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoanDebtDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _LoanDebtDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.cardColor(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 17,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoanDebtActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;
  final bool enabled;
  final bool armed;
  final VoidCallback onTap;

  const _LoanDebtActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isLoading,
    required this.enabled,
    this.armed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor =
        enabled || isLoading ? color : AppColors.textTertiary(context);
    final tileColor =
        armed ? color.withValues(alpha: 0.10) : AppColors.surfaceColor(context);
    final borderColor =
        armed ? color.withValues(alpha: 0.65) : AppColors.borderColor(context);
    final iconBackground =
        armed ? color : effectiveColor.withValues(alpha: 0.12);
    final iconColor = armed ? AppColors.white : effectiveColor;
    final titleColor = armed ? color : AppColors.textPrimary(context);

    return Material(
      color: tileColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled && !isLoading ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: iconColor,
                          ),
                        )
                      : Icon(icon, color: iconColor, size: 18),
                ),
              ),
              const SizedBox(height: 7),
              SizedBox(
                width: double.infinity,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: titleColor,
                    fontWeight: FontWeight.w900,
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

class _PersonAvatar extends StatelessWidget {
  final String name;
  final Color color;

  const _PersonAvatar({
    required this.name,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: AppColors.textTertiary(context)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoanDebtPersonDetailPage extends StatefulWidget {
  final _LoanDebtPersonSummary person;
  final List<_LoanDebtItem> items;
  final LoanDebtRepository repository;

  const _LoanDebtPersonDetailPage({
    required this.person,
    required this.items,
    required this.repository,
  });

  @override
  State<_LoanDebtPersonDetailPage> createState() =>
      _LoanDebtPersonDetailPageState();
}

class _LoanDebtPersonDetailPageState extends State<_LoanDebtPersonDetailPage> {
  late List<_LoanDebtItem> _items;
  _LoanDebtTransactionFilter _transactionFilter =
      _LoanDebtTransactionFilter.all;
  _LoanDebtStatusFilter _statusFilter = _LoanDebtStatusFilter.all;
  int? _selectedBankId;
  double? _minAmount;
  double? _maxAmount;
  DateTime? _startDate;
  DateTime? _endDate;

  _LoanDebtFilterSelection get _filterSelection => _LoanDebtFilterSelection(
        transactionFilter: _transactionFilter,
        statusFilter: _statusFilter,
        personName: null,
        bankId: _selectedBankId,
        minAmount: _minAmount,
        maxAmount: _maxAmount,
        startDate: _startDate,
        endDate: _endDate,
      );

  @override
  void initState() {
    super.initState();
    _items = List<_LoanDebtItem>.from(widget.items);
  }

  List<int> _bankIdsForItems(List<_LoanDebtItem> items) {
    final bankIds = <int>{};
    for (final item in items) {
      final bankId = item.transaction.bankId;
      if (bankId != null) bankIds.add(bankId);
    }
    return bankIds.toList()..sort();
  }

  Future<void> _openTransactionFilterSheet() async {
    final selected = await showModalBottomSheet<_LoanDebtFilterSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _TransactionFilterSheet(
        selectedTransactionFilter: _transactionFilter,
        selectedStatusFilter: _statusFilter,
        bankIds: _bankIdsForItems(_items),
        selectedBankId: _selectedBankId,
        minAmount: _minAmount,
        maxAmount: _maxAmount,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _transactionFilter = selected.transactionFilter;
      _statusFilter = selected.statusFilter;
      _selectedBankId = selected.bankId;
      _minAmount = selected.minAmount;
      _maxAmount = selected.maxAmount;
      _startDate = selected.startDate;
      _endDate = selected.endDate;
    });
  }

  Future<void> _openLoanDebtDetailsSheet(_LoanDebtItem item) async {
    final result = await showModalBottomSheet<_LoanDebtDetailsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _LoanDebtDetailsSheet(
        item: item,
        repository: widget.repository,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (result.unlinked) {
        _items = _items
            .where(
              (candidate) =>
                  candidate.transaction.reference !=
                  result.transactionReference,
            )
            .toList(growable: false);
        return;
      }

      final status = result.status;
      if (status == null) return;
      _items = _items
          .map(
            (candidate) =>
                candidate.transaction.reference == result.transactionReference
                    ? _loanDebtItemWithStatus(candidate, status)
                    : candidate,
          )
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final person = widget.person;
    final items = _items;
    final filteredItems = _filteredLoanDebtItems(
      items,
      _transactionFilter,
      statusFilter: _statusFilter,
      bankId: _selectedBankId,
      minAmount: _minAmount,
      maxAmount: _maxAmount,
      startDate: _startDate,
      endDate: _endDate,
    );
    final activeItems = items.where((item) => item.isActive);
    final lentTotal = activeItems
        .where((item) => item.direction == LoanDebtDirection.lent)
        .fold<double>(0, (total, item) => total + item.amount);
    final borrowedTotal = activeItems
        .where((item) => item.direction == LoanDebtDirection.borrowed)
        .fold<double>(0, (total, item) => total + item.amount);
    final net = lentTotal - borrowedTotal;
    final hasOpenBalance = net.abs() > 0.005;
    final isOwedToYou = net >= 0;
    final color = !hasOpenBalance
        ? AppColors.blue
        : (isOwedToYou ? AppColors.incomeSuccess : AppColors.red);
    final statusLabel = !hasOpenBalance
        ? context.l10nText('Settled')
        : (isOwedToYou
            ? context.l10nText('They owe you')
            : context.l10nText('You owe'));

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textPrimary(context),
                    ),
                    icon: const Icon(AppIcons.arrow_back_rounded, size: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardColor(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              child: Row(
                children: [
                  _PersonAvatar(name: person.name, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TinyStatusPill(label: statusLabel, color: color),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _formatEtb(net.abs(), context),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PersonDetailMetric(
                    title: context.l10nText('You lent'),
                    value: _formatEtb(lentTotal, context),
                    color: AppColors.incomeSuccess,
                    icon: AppIcons.trending_up_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PersonDetailMetric(
                    title: context.l10nText('You borrowed'),
                    value: _formatEtb(borrowedTotal, context),
                    color: AppColors.red,
                    icon: AppIcons.trending_down_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _TransactionsHeader(
              title: context.l10nText('Transactions'),
              subtitle: _formatFilteredTransactionCount(
                context,
                filteredItems.length,
                items.length,
              ),
              activeFilterCount: _filterSelection.activeCount,
              onFilterTap: _openTransactionFilterSheet,
            ),
            const SizedBox(height: 10),
            if (filteredItems.isEmpty)
              _EmptyPanel(
                icon: AppIcons.filter_list,
                title: context.l10nText('No matching transactions'),
                subtitle: context.l10nText(
                  'Change the filter to see this person\'s other transactions.',
                ),
              )
            else
              for (final item in filteredItems)
                _LoanDebtTransactionTile(
                  item: item,
                  onTap: () => _openLoanDebtDetailsSheet(item),
                ),
          ],
        ),
      ),
    );
  }
}

class _PersonDetailMetric extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _PersonDetailMetric({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionFilterSheet extends StatefulWidget {
  final _LoanDebtTransactionFilter selectedTransactionFilter;
  final _LoanDebtStatusFilter selectedStatusFilter;
  final bool showStatusFilter;
  final String? selectedPerson;
  final List<_LoanDebtPersonSummary> people;
  final List<int> bankIds;
  final int? selectedBankId;
  final double? minAmount;
  final double? maxAmount;
  final DateTime? startDate;
  final DateTime? endDate;

  const _TransactionFilterSheet({
    required this.selectedTransactionFilter,
    this.selectedStatusFilter = _LoanDebtStatusFilter.all,
    this.showStatusFilter = true,
    this.selectedPerson,
    this.people = const <_LoanDebtPersonSummary>[],
    this.bankIds = const <int>[],
    this.selectedBankId,
    this.minAmount,
    this.maxAmount,
    this.startDate,
    this.endDate,
  });

  @override
  State<_TransactionFilterSheet> createState() =>
      _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<_TransactionFilterSheet> {
  late _LoanDebtTransactionFilter _selectedTransactionFilter;
  late _LoanDebtStatusFilter _selectedStatusFilter;
  late String? _selectedPerson;
  late int? _selectedBankId;
  late final TextEditingController _minAmountController;
  late final TextEditingController _maxAmountController;
  String? _amountErrorText;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _selectedTransactionFilter = widget.selectedTransactionFilter;
    _selectedStatusFilter = widget.selectedStatusFilter;
    _selectedPerson = widget.selectedPerson;
    _selectedBankId = widget.selectedBankId;
    _minAmountController = TextEditingController(
      text: _formatAmountInput(widget.minAmount),
    );
    _maxAmountController = TextEditingController(
      text: _formatAmountInput(widget.maxAmount),
    );
    _startDate = widget.startDate;
    _endDate = widget.endDate;
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  void _clearAll() {
    setState(() {
      _selectedTransactionFilter = _LoanDebtTransactionFilter.all;
      _selectedStatusFilter = _LoanDebtStatusFilter.all;
      _selectedPerson = null;
      _selectedBankId = null;
      _minAmountController.clear();
      _maxAmountController.clear();
      _amountErrorText = null;
      _startDate = null;
      _endDate = null;
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
      _LoanDebtFilterSelection(
        transactionFilter: _selectedTransactionFilter,
        statusFilter: _selectedStatusFilter,
        personName: _selectedPerson,
        bankId: _selectedBankId,
        minAmount: minAmount,
        maxAmount: maxAmount,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
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
    return amount
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _handleAmountChanged(String _) {
    if (_amountErrorText == null) return;
    final minRaw = _minAmountController.text;
    final maxRaw = _maxAmountController.text;
    final minAmount = _parseAmountInput(minRaw);
    final maxAmount = _parseAmountInput(maxRaw);
    setState(() {
      _amountErrorText = _buildAmountValidationMessage(
        minRaw: minRaw,
        maxRaw: maxRaw,
        minAmount: minAmount,
        maxAmount: maxAmount,
      );
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
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
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TransactionProvider>();
    final options = <_LoanDebtTransactionFilter>[
      _LoanDebtTransactionFilter.all,
      _LoanDebtTransactionFilter.lent,
      _LoanDebtTransactionFilter.borrowed,
    ];
    final statusOptions = <_LoanDebtStatusFilter>[
      _LoanDebtStatusFilter.all,
      _LoanDebtStatusFilter.active,
      _LoanDebtStatusFilter.settled,
      _LoanDebtStatusFilter.forgiven,
    ];
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final navBarPadding = MediaQuery.of(context).padding.bottom;

    return Container(
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
                  child: Text(
                    context.l10nText('Filter Transactions'),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
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
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                16 + bottomPadding + navBarPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('DIRECTION'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in options)
                        _LoanDebtFilterChip(
                          label: _transactionFilterLabel(context, option),
                          selected: option == _selectedTransactionFilter,
                          onTap: () => setState(
                            () => _selectedTransactionFilter = option,
                          ),
                        ),
                    ],
                  ),
                  if (widget.showStatusFilter) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('STATUS'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in statusOptions)
                          _LoanDebtFilterChip(
                            label: _statusFilterLabel(context, option),
                            selected: option == _selectedStatusFilter,
                            onTap: () => setState(
                              () => _selectedStatusFilter = option,
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (widget.people.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('PEOPLE'),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: MediaQuery.of(context).size.width,
                      child: Transform.translate(
                        offset: const Offset(-20, 0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              _LoanDebtFilterChip(
                                label: context.l10nText('All people'),
                                selected: _selectedPerson == null,
                                onTap: () =>
                                    setState(() => _selectedPerson = null),
                              ),
                              for (final person in widget.people)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: _LoanDebtFilterChip(
                                    label: person.name,
                                    selected: _selectedPerson == person.name,
                                    onTap: () => setState(
                                      () => _selectedPerson = person.name,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (widget.bankIds.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('BANK'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _LoanDebtFilterChip(
                          label: context.l10nText('All Banks'),
                          selected: _selectedBankId == null,
                          onTap: () => setState(() => _selectedBankId = null),
                        ),
                        for (final bankId in widget.bankIds)
                          _LoanDebtFilterChip(
                            label: context.l10nText(
                              provider.getBankShortName(bankId),
                            ),
                            selected: _selectedBankId == bankId,
                            onTap: () =>
                                setState(() => _selectedBankId = bankId),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel('AMOUNT RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _LoanDebtAmountFilterField(
                          controller: _minAmountController,
                          hint: 'Min',
                          hasError: _amountErrorText != null,
                          onChanged: _handleAmountChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _LoanDebtAmountFilterField(
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
                      context.l10nText(_amountErrorText!),
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel('DATE RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _LoanDebtDatePickerField(
                          hint: 'Start date',
                          value: _startDate == null
                              ? null
                              : AppDateFormat.monthDayMaybeYear(_startDate!),
                          onTap: () => _pickDate(isStart: true),
                          onClear: _startDate == null
                              ? null
                              : () => setState(() => _startDate = null),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _LoanDebtDatePickerField(
                          hint: 'End date',
                          value: _endDate == null
                              ? null
                              : AppDateFormat.monthDayMaybeYear(_endDate!),
                          onTap: () => _pickDate(isStart: false),
                          onClear: _endDate == null
                              ? null
                              : () => setState(() => _endDate = null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clearAll,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary(context),
                            side: BorderSide(
                              color: AppColors.borderColor(context),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Clear All'),
                            style: const TextStyle(
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
                          child: Text(
                            context.l10nText('Apply Filters'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      context.l10nText(text),
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _LoanDebtFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LoanDebtFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                selected ? AppColors.white : AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LoanDebtDatePickerField extends StatelessWidget {
  final String hint;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _LoanDebtDatePickerField({
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
                value ?? context.l10nText(hint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

class _LoanDebtAmountFilterField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  const _LoanDebtAmountFilterField({
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      style: TextStyle(
        color: AppColors.textPrimary(context),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: context.l10nText(hint),
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        prefixText: '${context.l10nText('ETB')} ',
        prefixStyle: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: AppColors.surfaceColor(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
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
            width: 1.3,
          ),
        ),
      ),
    );
  }
}

class _LoanDebtDashboard {
  final List<_LoanDebtItem> assignedItems;
  final List<_LoanDebtItem> unassignedItems;
  final List<_LoanDebtPersonSummary> people;
  final double totalLent;
  final double totalBorrowed;

  const _LoanDebtDashboard({
    required this.assignedItems,
    required this.unassignedItems,
    required this.people,
    required this.totalLent,
    required this.totalBorrowed,
  });

  bool get hasAnyLoanDebtTransaction =>
      assignedItems.isNotEmpty || unassignedItems.isNotEmpty;

  List<_LoanDebtItem> itemsForPerson(String personName) {
    final normalized = personName.trim().toLowerCase();
    if (normalized.isEmpty) return const <_LoanDebtItem>[];
    return assignedItems
        .where((item) => item.personName.toLowerCase() == normalized)
        .toList(growable: false);
  }

  factory _LoanDebtDashboard.from({
    required List<Transaction> transactions,
    required List<Category> categories,
    required List<LoanDebtEntry> entries,
  }) {
    final entriesByReference = <String, LoanDebtEntry>{
      for (final entry in entries) entry.transactionReference.trim(): entry,
    };
    final assignedItems = <_LoanDebtItem>[];
    final unassignedItems = <_LoanDebtItem>[];
    double totalLent = 0;
    double totalBorrowed = 0;

    for (final transaction in transactions) {
      if (!transactionHasLoanDebtCategory(
        transaction: transaction,
        categories: categories,
      )) {
        continue;
      }

      final reference = transaction.reference.trim();
      final entry = entriesByReference[reference];
      final direction =
          entry?.direction ?? loanDebtDirectionForTransaction(transaction);
      final item = _LoanDebtItem(
        transaction: transaction,
        entry: entry,
        direction: direction,
      );

      if (item.isActive) {
        if (direction == LoanDebtDirection.borrowed) {
          totalBorrowed += transaction.amount.abs();
        } else {
          totalLent += transaction.amount.abs();
        }
      }

      if (item.hasPerson) {
        assignedItems.add(item);
      } else {
        unassignedItems.add(item);
      }
    }

    int compareItems(_LoanDebtItem a, _LoanDebtItem b) {
      return b.sortTime.compareTo(a.sortTime);
    }

    assignedItems.sort(compareItems);
    unassignedItems.sort(compareItems);

    final peopleByName = <String, _MutablePersonSummary>{};
    for (final item in assignedItems) {
      final key = item.personName.toLowerCase();
      final summary = peopleByName.putIfAbsent(
        key,
        () => _MutablePersonSummary(item.personName),
      );
      summary.transactionCount += 1;
      if (item.isActive) {
        if (item.direction == LoanDebtDirection.lent) {
          summary.net += item.amount;
        } else {
          summary.net -= item.amount;
        }
      }
    }

    final people = peopleByName.values
        .map(
          (summary) => _LoanDebtPersonSummary(
            name: summary.name,
            net: summary.net,
            transactionCount: summary.transactionCount,
          ),
        )
        .toList(growable: false)
      ..sort((a, b) {
        final netComparison = b.net.abs().compareTo(a.net.abs());
        if (netComparison != 0) return netComparison;
        return b.transactionCount.compareTo(a.transactionCount);
      });

    return _LoanDebtDashboard(
      assignedItems: assignedItems,
      unassignedItems: unassignedItems,
      people: people,
      totalLent: totalLent,
      totalBorrowed: totalBorrowed,
    );
  }
}

class _LoanDebtItem {
  final Transaction transaction;
  final LoanDebtEntry? entry;
  final LoanDebtDirection direction;

  const _LoanDebtItem({
    required this.transaction,
    required this.entry,
    required this.direction,
  });

  double get amount => transaction.amount.abs();
  bool get hasPerson => personName.trim().isNotEmpty;
  String get personName => entry?.personName.trim() ?? '';
  LoanDebtStatus get status => entry?.status ?? LoanDebtStatus.active;
  bool get isActive => status == LoanDebtStatus.active;

  _LoanDebtItem copyWith({
    LoanDebtEntry? entry,
    LoanDebtDirection? direction,
  }) {
    return _LoanDebtItem(
      transaction: transaction,
      entry: entry ?? this.entry,
      direction: direction ?? this.direction,
    );
  }

  int get sortTime {
    final parsed = DateTime.tryParse(transaction.time ?? '');
    return parsed?.millisecondsSinceEpoch ?? 0;
  }

  DateTime? get parsedLocalTime {
    final parsed = DateTime.tryParse(transaction.time ?? '');
    return parsed?.toLocal();
  }

  String dateLabel(BuildContext context) {
    final parsed = parsedLocalTime;
    if (parsed == null) return context.l10nText('Unknown date');
    return AppDateFormat.monthDayMaybeYear(parsed);
  }

  String timeLabel(BuildContext context) {
    final parsed = parsedLocalTime;
    if (parsed == null) return '';
    final hour = parsed.hour;
    final minute = parsed.minute.toString().padLeft(2, '0');
    final period = context.l10nText(hour >= 12 ? 'PM' : 'AM');
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$hour12:$minute $period';
  }
}

class _LoanDebtPersonSummary {
  final String name;
  final double net;
  final int transactionCount;

  const _LoanDebtPersonSummary({
    required this.name,
    required this.net,
    required this.transactionCount,
  });
}

class _MutablePersonSummary {
  final String name;
  double net = 0;
  int transactionCount = 0;

  _MutablePersonSummary(this.name);
}

String _formatEtb(double amount, BuildContext context) {
  final formatted = formatNumberWithComma(amount).replaceFirst('.00', '');
  final currency = context.l10nText('ETB');
  return '$currency $formatted';
}

List<_LoanDebtItem> _filteredLoanDebtItems(
  List<_LoanDebtItem> items,
  _LoanDebtTransactionFilter filter, {
  _LoanDebtStatusFilter statusFilter = _LoanDebtStatusFilter.all,
  int? bankId,
  double? minAmount,
  double? maxAmount,
  DateTime? startDate,
  DateTime? endDate,
}) {
  final start = startDate == null
      ? null
      : DateTime(startDate.year, startDate.month, startDate.day);
  final end = endDate == null
      ? null
      : DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

  return items.where((item) {
    if (filter == _LoanDebtTransactionFilter.lent &&
        item.direction != LoanDebtDirection.lent) {
      return false;
    }
    if (filter == _LoanDebtTransactionFilter.borrowed &&
        item.direction != LoanDebtDirection.borrowed) {
      return false;
    }
    if (statusFilter == _LoanDebtStatusFilter.active && !item.isActive) {
      return false;
    }
    if (statusFilter == _LoanDebtStatusFilter.settled &&
        item.status != LoanDebtStatus.settled) {
      return false;
    }
    if (statusFilter == _LoanDebtStatusFilter.forgiven &&
        item.status != LoanDebtStatus.forgiven) {
      return false;
    }
    if (bankId != null && item.transaction.bankId != bankId) return false;
    if (minAmount != null && item.amount < minAmount) return false;
    if (maxAmount != null && item.amount > maxAmount) return false;
    final parsed = item.parsedLocalTime;
    if (start != null) {
      if (parsed == null || parsed.isBefore(start)) return false;
    }
    if (end != null) {
      if (parsed == null || parsed.isAfter(end)) return false;
    }
    return true;
  }).toList(growable: false);
}

_LoanDebtItem _loanDebtItemWithStatus(
  _LoanDebtItem item,
  LoanDebtStatus status,
) {
  final entry = item.entry;
  if (entry == null) return item;
  final now = DateTime.now();
  return item.copyWith(
    entry: LoanDebtEntry(
      id: entry.id,
      transactionReference: entry.transactionReference,
      personName: entry.personName,
      direction: entry.direction,
      status: status,
      resolvedAt: status == LoanDebtStatus.active ? null : now,
      createdAt: entry.createdAt,
      updatedAt: now,
    ),
  );
}

String _formatEtbCompact(double amount, BuildContext context) {
  final currency = context.l10nText('ETB');
  final normalized = amount.abs();
  final formatted = normalized >= 10000
      ? formatNumberAbbreviated(amount)
          .replaceAll(' k', 'K')
          .replaceAll(' M', 'M')
      : formatNumberWithComma(amount).replaceFirst('.00', '');
  return '$currency $formatted';
}

String _formatTransactionCount(BuildContext context, int count) {
  final label = context.l10nText(
    count == 1 ? 'transaction' : 'transactions',
  );
  return '$count $label';
}

String _formatFilteredTransactionCount(
  BuildContext context,
  int filteredCount,
  int totalCount,
) {
  final label = context.l10nText('transactions');
  return '$filteredCount/$totalCount $label';
}

String _transactionFilterLabel(
  BuildContext context,
  _LoanDebtTransactionFilter filter,
) {
  switch (filter) {
    case _LoanDebtTransactionFilter.all:
      return context.l10nText('All');
    case _LoanDebtTransactionFilter.lent:
      return context.l10nText('Lent');
    case _LoanDebtTransactionFilter.borrowed:
      return context.l10nText('Borrowed');
  }
}

String _statusFilterLabel(
  BuildContext context,
  _LoanDebtStatusFilter filter,
) {
  switch (filter) {
    case _LoanDebtStatusFilter.all:
      return context.l10nText('All statuses');
    case _LoanDebtStatusFilter.active:
      return context.l10nText('Active');
    case _LoanDebtStatusFilter.settled:
      return context.l10nText('Settled');
    case _LoanDebtStatusFilter.forgiven:
      return context.l10nText('Forgiven');
  }
}

String _loanDebtStatusLabel(BuildContext context, LoanDebtStatus status) {
  switch (status) {
    case LoanDebtStatus.active:
      return context.l10nText('Active');
    case LoanDebtStatus.settled:
      return context.l10nText('Settled');
    case LoanDebtStatus.forgiven:
      return context.l10nText('Forgiven');
  }
}

Color _loanDebtStatusColor(LoanDebtStatus status, Color activeColor) {
  switch (status) {
    case LoanDebtStatus.active:
      return activeColor;
    case LoanDebtStatus.settled:
      return AppColors.blue;
    case LoanDebtStatus.forgiven:
      return AppColors.amber;
  }
}
