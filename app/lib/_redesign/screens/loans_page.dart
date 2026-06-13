import 'package:flutter/material.dart';
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

class _LoanDebtFilterSelection {
  final _LoanDebtTransactionFilter transactionFilter;
  final String? personName;

  const _LoanDebtFilterSelection({
    required this.transactionFilter,
    required this.personName,
  });
}

class _LoansPageState extends State<LoansPage> {
  final LoanDebtRepository _repository = LoanDebtRepository();
  late Future<List<LoanDebtEntry>> _entriesFuture;
  String? _selectedPerson;
  _LoanDebtTransactionFilter _transactionFilter =
      _LoanDebtTransactionFilter.all;

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
    return _filteredLoanDebtItems(items, _transactionFilter);
  }

  Future<void> _openTransactionFilterSheet({
    required List<_LoanDebtPersonSummary> people,
  }) async {
    final selected = await showModalBottomSheet<_LoanDebtFilterSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _TransactionFilterSheet(
        selectedTransactionFilter: _transactionFilter,
        selectedPerson: _selectedPerson,
        people: people,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _transactionFilter = selected.transactionFilter;
      _selectedPerson = selected.personName;
    });
  }

  void _openPersonPage({
    required _LoanDebtPersonSummary person,
    required List<_LoanDebtItem> items,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _LoanDebtPersonDetailPage(
          person: person,
          items: items,
        ),
      ),
    );
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
                      filterLabel: _loanDebtFilterSummaryLabel(
                        context,
                        transactionFilter: _transactionFilter,
                        personName: selectedPerson,
                      ),
                      onFilterTap: () =>
                          _openTransactionFilterSheet(people: people),
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
                        _LoanDebtTransactionTile(item: item),
                    if (dashboard.unassignedItems.isNotEmpty &&
                        selectedPerson == null) ...[
                      const SizedBox(height: 18),
                      _SectionHeader(
                        title: context.l10nText('Needs a person'),
                        subtitle: context.l10nText(
                          'Pick who this loan or debt belongs to',
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final item in dashboard.unassignedItems)
                        _UnassignedLoanDebtTile(
                          item: item,
                          onTap: () async {
                            final saved = await showLoanDebtPersonSheet(
                              context: context,
                              transaction: item.transaction,
                              repository: _repository,
                            );
                            if (!mounted) return;
                            if (saved) _refreshEntries();
                          },
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
              backgroundColor: AppColors.cardColor(context),
              foregroundColor: AppColors.textPrimary(context),
              side: BorderSide(color: AppColors.borderColor(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
              backgroundColor: AppColors.cardColor(context),
              foregroundColor: AppColors.textPrimary(context),
              side: BorderSide(color: AppColors.borderColor(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
    final isOwedToYou = person.net >= 0;
    final color = isOwedToYou ? AppColors.incomeSuccess : AppColors.red;
    final label = isOwedToYou
        ? context.l10nText('They owe you')
        : context.l10nText('You owe');
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
  final String filterLabel;
  final VoidCallback onFilterTap;

  const _TransactionsHeader({
    required this.title,
    required this.subtitle,
    required this.filterLabel,
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
        InkWell(
          onTap: onFilterTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.cardColor(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  AppIcons.filter_list,
                  color: AppColors.primaryLight,
                  size: 17,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 72),
                  child: Text(
                    filterLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoanDebtTransactionTile extends StatelessWidget {
  final _LoanDebtItem item;

  const _LoanDebtTransactionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return _LoanDebtBaseTile(
      item: item,
      personName: item.personName,
      onTap: null,
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
      personName: context.l10nText('Choose a person'),
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
    final color = borrowed ? AppColors.red : AppColors.incomeSuccess;
    final bankName = context.l10nText(
      provider.getBankShortName(item.transaction.bankId),
    );
    final details = [
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

  const _LoanDebtPersonDetailPage({
    required this.person,
    required this.items,
  });

  @override
  State<_LoanDebtPersonDetailPage> createState() =>
      _LoanDebtPersonDetailPageState();
}

class _LoanDebtPersonDetailPageState extends State<_LoanDebtPersonDetailPage> {
  _LoanDebtTransactionFilter _transactionFilter =
      _LoanDebtTransactionFilter.all;

  Future<void> _openTransactionFilterSheet() async {
    final selected = await showModalBottomSheet<_LoanDebtFilterSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _TransactionFilterSheet(
        selectedTransactionFilter: _transactionFilter,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _transactionFilter = selected.transactionFilter);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final person = widget.person;
    final items = widget.items;
    final filteredItems = _filteredLoanDebtItems(items, _transactionFilter);
    final lentTotal = items
        .where((item) => item.direction == LoanDebtDirection.lent)
        .fold<double>(0, (total, item) => total + item.amount);
    final borrowedTotal = items
        .where((item) => item.direction == LoanDebtDirection.borrowed)
        .fold<double>(0, (total, item) => total + item.amount);
    final isOwedToYou = person.net >= 0;
    final color = isOwedToYou ? AppColors.incomeSuccess : AppColors.red;
    final statusLabel = isOwedToYou
        ? context.l10nText('They owe you')
        : context.l10nText('You owe');

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
                      backgroundColor: AppColors.cardColor(context),
                      foregroundColor: AppColors.textPrimary(context),
                      side: BorderSide(color: AppColors.borderColor(context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
                            _formatEtb(person.net.abs(), context),
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
              filterLabel: _transactionFilterLabel(
                context,
                _transactionFilter,
              ),
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
                _LoanDebtTransactionTile(item: item),
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

class _TransactionFilterSheet extends StatelessWidget {
  final _LoanDebtTransactionFilter selectedTransactionFilter;
  final String? selectedPerson;
  final List<_LoanDebtPersonSummary> people;

  const _TransactionFilterSheet({
    required this.selectedTransactionFilter,
    this.selectedPerson,
    this.people = const <_LoanDebtPersonSummary>[],
  });

  @override
  Widget build(BuildContext context) {
    final options = <_LoanDebtTransactionFilter>[
      _LoanDebtTransactionFilter.all,
      _LoanDebtTransactionFilter.lent,
      _LoanDebtTransactionFilter.borrowed,
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Text(
                  context.l10nText('Filter transactions'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 14),
                _FilterSectionLabel(label: context.l10nText('Direction')),
                const SizedBox(height: 8),
                for (final option in options)
                  _TransactionFilterOption(
                    option: option,
                    selected: option == selectedTransactionFilter,
                    onTap: () => Navigator.pop(
                      context,
                      _LoanDebtFilterSelection(
                        transactionFilter: option,
                        personName: selectedPerson,
                      ),
                    ),
                  ),
                if (people.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _FilterSectionLabel(label: context.l10nText('People')),
                  const SizedBox(height: 8),
                  _PersonFilterOption(
                    label: context.l10nText('All people'),
                    selected: selectedPerson == null,
                    onTap: () => Navigator.pop(
                      context,
                      _LoanDebtFilterSelection(
                        transactionFilter: selectedTransactionFilter,
                        personName: null,
                      ),
                    ),
                  ),
                  for (final person in people)
                    _PersonFilterOption(
                      label: person.name,
                      selected: selectedPerson == person.name,
                      onTap: () => Navigator.pop(
                        context,
                        _LoanDebtFilterSelection(
                          transactionFilter: selectedTransactionFilter,
                          personName: person.name,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  final String label;

  const _FilterSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w900,
          ),
    );
  }
}

class _TransactionFilterOption extends StatelessWidget {
  final _LoanDebtTransactionFilter option;
  final bool selected;
  final VoidCallback onTap;

  const _TransactionFilterOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _transactionFilterColor(option);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.1)
            : AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? color : AppColors.borderColor(context),
              ),
            ),
            child: Row(
              children: [
                Icon(_transactionFilterIcon(option), color: color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _transactionFilterLabel(context, option),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (selected)
                  Icon(
                    AppIcons.check_rounded,
                    color: color,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonFilterOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PersonFilterOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const color = AppColors.primaryLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.1)
            : AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? color : AppColors.borderColor(context),
              ),
            ),
            child: Row(
              children: [
                const Icon(AppIcons.person_outline, color: color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (selected)
                  const Icon(
                    AppIcons.check_rounded,
                    color: color,
                    size: 20,
                  ),
              ],
            ),
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

      if (direction == LoanDebtDirection.borrowed) {
        totalBorrowed += transaction.amount.abs();
      } else {
        totalLent += transaction.amount.abs();
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
      if (item.direction == LoanDebtDirection.lent) {
        summary.net += item.amount;
      } else {
        summary.net -= item.amount;
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
      ..sort((a, b) => b.net.abs().compareTo(a.net.abs()));

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
  _LoanDebtTransactionFilter filter,
) {
  switch (filter) {
    case _LoanDebtTransactionFilter.all:
      return items;
    case _LoanDebtTransactionFilter.lent:
      return items
          .where((item) => item.direction == LoanDebtDirection.lent)
          .toList(growable: false);
    case _LoanDebtTransactionFilter.borrowed:
      return items
          .where((item) => item.direction == LoanDebtDirection.borrowed)
          .toList(growable: false);
  }
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

String _loanDebtFilterSummaryLabel(
  BuildContext context, {
  required _LoanDebtTransactionFilter transactionFilter,
  required String? personName,
}) {
  final direction = _transactionFilterLabel(context, transactionFilter);
  final person = personName?.trim();
  if (person == null || person.isEmpty) return direction;
  if (transactionFilter == _LoanDebtTransactionFilter.all) return person;
  return '$person · $direction';
}

IconData _transactionFilterIcon(_LoanDebtTransactionFilter filter) {
  switch (filter) {
    case _LoanDebtTransactionFilter.all:
      return AppIcons.filter_list;
    case _LoanDebtTransactionFilter.lent:
      return AppIcons.trending_up_rounded;
    case _LoanDebtTransactionFilter.borrowed:
      return AppIcons.trending_down_rounded;
  }
}

Color _transactionFilterColor(_LoanDebtTransactionFilter filter) {
  switch (filter) {
    case _LoanDebtTransactionFilter.all:
      return AppColors.primaryLight;
    case _LoanDebtTransactionFilter.lent:
      return AppColors.incomeSuccess;
    case _LoanDebtTransactionFilter.borrowed:
      return AppColors.red;
  }
}
