import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/screens/loans_page.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/theme/app_calendar_option.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/widgets/category_filter_chip.dart';
import 'package:totals/_redesign/widgets/transaction_category_sheet.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/account_sort.dart';
import 'package:totals/utils/app_date_format.dart';
import 'package:totals/utils/category_filter_utils.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/_redesign/widgets/transaction_tile.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

class TodaysTransactionsPage extends StatefulWidget {
  const TodaysTransactionsPage({super.key});

  @override
  State<TodaysTransactionsPage> createState() => _TodaysTransactionsPageState();
}

class _TodaysTransactionsPageState extends State<TodaysTransactionsPage> {
  final Set<String> _selectedRefs = {};
  _TodayTransactionsFilter _filter = const _TodayTransactionsFilter();

  bool get _isSelecting => _selectedRefs.isNotEmpty;

  void _toggle(Transaction tx) {
    setState(() {
      if (_selectedRefs.contains(tx.reference)) {
        _selectedRefs.remove(tx.reference);
      } else {
        _selectedRefs.add(tx.reference);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedRefs.clear());

  List<Transaction> _filteredTransactions(
    TransactionProvider provider,
    List<Transaction> transactions,
  ) {
    return transactions.where((transaction) {
      if (_filter.type != null && transaction.type != _filter.type) {
        return false;
      }
      if (_filter.bankId != null && transaction.bankId != _filter.bankId) {
        return false;
      }
      if (_filter.accountKey != null) {
        final summary = provider.accountSummaryForTransaction(transaction);
        final otherBankId = _todayOtherAccountBankId(_filter.accountKey!);
        if (otherBankId != null) {
          if (summary != null || transaction.bankId != otherBankId) {
            return false;
          }
        } else if (summary == null ||
            _todayAccountKey(summary) != _filter.accountKey) {
          return false;
        }
      }
      if (!provider.matchesCategoryFilterSelection(
        transaction,
        _filter.categoryIds,
      )) {
        return false;
      }
      if (_filter.minAmount != null &&
          transaction.amount < _filter.minAmount!) {
        return false;
      }
      if (_filter.maxAmount != null &&
          transaction.amount > _filter.maxAmount!) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  Future<void> _openFilterSheet(
    TransactionProvider provider,
    List<Transaction> transactions,
  ) async {
    final bankIds = <int>{};
    final accountsByKey = <String, AccountSummary>{};
    final unmatchedBankIds = <int>{};
    final categoryIds = <int>{};

    for (final transaction in transactions) {
      final bankId = transaction.bankId;
      if (bankId != null) bankIds.add(bankId);
      final account = provider.accountSummaryForTransaction(transaction);
      if (account != null) {
        accountsByKey[_todayAccountKey(account)] = account;
      } else if (bankId != null) {
        unmatchedBankIds.add(bankId);
      }
      categoryIds.addAll(provider.categoryIdsForFiltering(transaction));
    }

    final sortedBankIds = bankIds.toList(growable: true)
      ..sort(
        (left, right) => compareDisplayText(
          context.l10nText(provider.getBankShortName(left)),
          context.l10nText(provider.getBankShortName(right)),
        ),
      );
    final accounts = accountsByKey.values.toList(growable: true)
      ..sort(
        (left, right) => compareAccountDisplayFields(
          leftBankId: left.bankId,
          rightBankId: right.bankId,
          leftHolderName: left.accountHolderName,
          rightHolderName: right.accountHolderName,
          leftAccountNumber: left.accountNumber,
          rightAccountNumber: right.accountNumber,
          bankNameForId: (bankId) =>
              context.l10nText(provider.getBankShortName(bankId)),
        ),
      );
    final categories = orderedCategoriesForFilter(
      categoryIds.map(provider.getCategoryById).whereType<Category>(),
    );

    final selected = await showModalBottomSheet<_TodayTransactionsFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TodayTransactionsFilterSheet(
        currentFilter: _filter,
        bankIds: sortedBankIds,
        accounts: accounts,
        unmatchedBankIds: unmatchedBankIds,
        categories: categories,
        bankLabel: (bankId) =>
            context.l10nText(provider.getBankShortName(bankId)),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _filter = selected;
      _selectedRefs.clear();
    });
  }

  Future<void> _openDetails(
      TransactionProvider provider, Transaction tx) async {
    await showTransactionDetailsSheet(
      context: context,
      transaction: tx,
      provider: provider,
    );
  }

  Future<void> _openCategorySheet(
      TransactionProvider provider, Transaction tx) async {
    await showTransactionCategorySheet(
      context: context,
      transaction: tx,
      provider: provider,
    );
  }

  Future<void> _categorizeSelected(TransactionProvider provider) async {
    if (_selectedRefs.isEmpty) return;
    final references = Set<String>.from(_selectedRefs);
    final transactions = provider.allTransactions
        .where((transaction) => references.contains(transaction.reference))
        .toList(growable: false);
    try {
      final changed = await showBatchTransactionCategorySheet(
        context: context,
        transactions: transactions,
        provider: provider,
      );
      if (!mounted || changed == null) return;
      _clearSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changed == 0
                ? context.l10nTextRead('Categories were already assigned.')
                : '${context.l10nTextRead('Categorized')} $changed '
                    '${context.l10nTextRead(changed == 1 ? 'transaction' : 'transactions')}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10nTextRead('Could not update category')}: $error',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteSelected(TransactionProvider provider) async {
    if (_selectedRefs.isEmpty) return;
    final count = _selectedRefs.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${ctx.l10nText('Delete')} $count ${ctx.l10nText(count > 1 ? 'transactions' : 'transaction')}?',
        ),
        content: Text(ctx.l10nText('This cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10nText('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              ctx.l10nText('Delete'),
              style: const TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.deleteTransactionsByReferences(_selectedRefs.toList());
      _clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEC = context.watch<ThemeProvider>().appCalendar ==
        AppCalendarOption.ethiopian;

    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final allTransactions = provider.todayTransactions;
        final transactions = _filteredTransactions(provider, allTransactions);

        String pageTitle;
        if (_isSelecting) {
          pageTitle = '${_selectedRefs.length} selected';
        } else if (isEC) {
          pageTitle =
              AppDateFormat.monthDayYear(DateTime.now(), context: context);
        } else {
          pageTitle = context.l10nText("Today's Transactions");
        }

        return Scaffold(
          backgroundColor: AppColors.background(context),
          appBar: AppBar(
            backgroundColor: AppColors.background(context),
            surfaceTintColor: Colors.transparent,
            leading: _isSelecting
                ? IconButton(
                    onPressed: _clearSelection,
                    icon: const Icon(AppIcons.close),
                  )
                : IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(AppIcons.arrow_back_rounded),
                  ),
            title: Text(
              pageTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: _isSelecting
                    ? AppColors.primaryDark
                    : AppColors.textPrimary(context),
              ),
            ),
            actions: [
              if (!_isSelecting)
                _TodayFilterActionButton(
                  activeCount: _filter.activeCount,
                  onTap: () => _openFilterSheet(provider, allTransactions),
                ),
              if (_isSelecting)
                IconButton(
                  onPressed: () => _categorizeSelected(provider),
                  tooltip: context.l10nText('Categorize selected'),
                  icon: const Icon(
                    AppIcons.category,
                    color: AppColors.primaryLight,
                  ),
                ),
              if (_isSelecting)
                IconButton(
                  onPressed: () => _deleteSelected(provider),
                  icon: const Icon(
                    AppIcons.delete_outline_rounded,
                    color: AppColors.red,
                  ),
                ),
            ],
          ),
          body: transactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppIcons.receipt_long_rounded,
                        size: 48,
                        color: AppColors.textTertiary(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10nText(
                          allTransactions.isEmpty
                              ? 'No transactions today'
                              : 'No transactions match these filters',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final bankLabel = context.l10nText(
                      provider.getBankShortName(tx.bankId),
                    );
                    final category = provider.getCategoryById(tx.categoryId);
                    final isSelfTransfer = provider.isSelfTransfer(tx);
                    final isMisc = category?.uncategorized == true;
                    final categoryLabel = isSelfTransfer
                        ? 'Self'
                        : provider.categoryLabelForTransaction(
                            tx,
                            uncategorizedLabel: 'Categorize',
                          );
                    final isCategorized =
                        isSelfTransfer || tx.selectedCategoryIds.isNotEmpty;
                    final isCredit = tx.type == 'CREDIT';
                    final selected = _selectedRefs.contains(tx.reference);

                    return TransactionTile(
                      bank: bankLabel,
                      category: categoryLabel,
                      categoryModel: category,
                      personLabel:
                          provider.loanDebtPersonNameForTransaction(tx),
                      onPersonTap: (personName) => openLoansPersonPage(
                        context: context,
                        personName: personName,
                      ),
                      isCategorized: isCategorized,
                      isDebit: !isCredit,
                      isSelfTransfer: isSelfTransfer,
                      isMisc: isMisc,
                      isReimbursed: provider.isReimbursedExpense(tx),
                      isSharing: provider.isSharingSharedExpenseTransaction(tx),
                      isShared: provider.isSharedExpenseTransaction(tx),
                      amount: _amountLabel(
                        tx.amount,
                        isCredit: isCredit,
                        currencyLabel: context.l10nText('ETB'),
                      ),
                      amountColor:
                          isCredit ? AppColors.incomeSuccess : AppColors.red,
                      name: _counterparty(tx, isSelfTransfer: isSelfTransfer),
                      timestamp: _timeLabel(tx, context),
                      selected: selected,
                      onTap: _isSelecting
                          ? () => _toggle(tx)
                          : () => _openDetails(provider, tx),
                      onCategoryTap: _isSelecting
                          ? () => _toggle(tx)
                          : () => _openCategorySheet(provider, tx),
                      onLongPress: () => _toggle(tx),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _TodayTransactionsFilter {
  final String? type;
  final int? bankId;
  final String? accountKey;
  // Empty = all categories; uncategorizedCategoryFilterId = none assigned.
  final Set<int> categoryIds;
  final double? minAmount;
  final double? maxAmount;

  const _TodayTransactionsFilter({
    this.type,
    this.bankId,
    this.accountKey,
    this.categoryIds = const <int>{},
    this.minAmount,
    this.maxAmount,
  });

  int get activeCount {
    var count = 0;
    if (type != null) count++;
    if (bankId != null) count++;
    if (accountKey != null) count++;
    if (categoryIds.isNotEmpty) count++;
    if (minAmount != null || maxAmount != null) count++;
    return count;
  }
}

class _TodayTransactionsFilterSheet extends StatefulWidget {
  final _TodayTransactionsFilter currentFilter;
  final List<int> bankIds;
  final List<AccountSummary> accounts;
  final Set<int> unmatchedBankIds;
  final List<Category> categories;
  final String Function(int bankId) bankLabel;

  const _TodayTransactionsFilterSheet({
    required this.currentFilter,
    required this.bankIds,
    required this.accounts,
    required this.unmatchedBankIds,
    required this.categories,
    required this.bankLabel,
  });

  @override
  State<_TodayTransactionsFilterSheet> createState() =>
      _TodayTransactionsFilterSheetState();
}

class _TodayTransactionsFilterSheetState
    extends State<_TodayTransactionsFilterSheet> {
  late String? _selectedType;
  late int? _selectedBankId;
  late String? _selectedAccountKey;
  late Set<int> _selectedCategoryIds;
  late final TextEditingController _minAmountController;
  late final TextEditingController _maxAmountController;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.currentFilter.type;
    _selectedBankId = widget.currentFilter.bankId;
    _selectedAccountKey = widget.currentFilter.accountKey;
    _selectedCategoryIds = <int>{...widget.currentFilter.categoryIds};
    _minAmountController = TextEditingController(
      text: _formatAmount(widget.currentFilter.minAmount),
    );
    _maxAmountController = TextEditingController(
      text: _formatAmount(widget.currentFilter.maxAmount),
    );
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  List<AccountSummary> get _visibleAccounts => _selectedBankId == null
      ? widget.accounts
      : widget.accounts
          .where((account) => account.bankId == _selectedBankId)
          .toList(growable: false);

  List<int> get _visibleUnmatchedBankIds => widget.unmatchedBankIds
      .where(
        (bankId) => _selectedBankId == null || bankId == _selectedBankId,
      )
      .toList(growable: false)
    ..sort(
      (left, right) => compareDisplayText(
        widget.bankLabel(left),
        widget.bankLabel(right),
      ),
    );

  void _selectBank(int? bankId) {
    setState(() {
      _selectedBankId = bankId;
      if (_selectedAccountKey == null) return;
      final accountVisible = _visibleAccounts.any(
        (account) => _todayAccountKey(account) == _selectedAccountKey,
      );
      final otherVisible = _visibleUnmatchedBankIds.any(
        (candidate) => _todayOtherAccountKey(candidate) == _selectedAccountKey,
      );
      if (!accountVisible && !otherVisible) _selectedAccountKey = null;
    });
  }

  void _toggleCategory(int categoryId) {
    setState(() {
      if (!_selectedCategoryIds.add(categoryId)) {
        _selectedCategoryIds.remove(categoryId);
      }
    });
  }

  void _clearAll() {
    setState(() {
      _selectedType = null;
      _selectedBankId = null;
      _selectedAccountKey = null;
      _selectedCategoryIds.clear();
      _minAmountController.clear();
      _maxAmountController.clear();
      _amountError = null;
    });
  }

  void _apply() {
    final min = _parseAmount(_minAmountController.text);
    final max = _parseAmount(_maxAmountController.text);
    final minInvalid =
        _minAmountController.text.trim().isNotEmpty && min == null;
    final maxInvalid =
        _maxAmountController.text.trim().isNotEmpty && max == null;
    if (minInvalid || maxInvalid) {
      setState(() => _amountError = 'Enter a valid amount');
      return;
    }
    if (min != null && max != null && max < min) {
      setState(() => _amountError = 'Maximum must be at least minimum.');
      return;
    }

    Navigator.of(context).pop(
      _TodayTransactionsFilter(
        type: _selectedType,
        bankId: _selectedBankId,
        accountKey: _selectedAccountKey,
        categoryIds: Set<int>.unmodifiable(_selectedCategoryIds),
        minAmount: min,
        maxAmount: max,
      ),
    );
  }

  double? _parseAmount(String raw) {
    final normalized = raw.trim().replaceAll(',', '');
    return normalized.isEmpty ? null : double.tryParse(normalized);
  }

  String _formatAmount(double? amount) {
    if (amount == null) return '';
    if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
    return amount
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _accountLabel(AccountSummary account) {
    final holder = account.accountHolderName.trim();
    final identity = holder.isEmpty
        ? account.accountNumber
        : '$holder • ${account.accountNumber}';
    return _selectedBankId == null
        ? '${widget.bankLabel(account.bankId)} • $identity'
        : identity;
  }

  String _otherLabel(int bankId) {
    final other = context.l10nText('Other transactions');
    return _selectedBankId == null
        ? '${widget.bankLabel(bankId)} • $other'
        : other;
  }

  Widget _sectionLabel(String label) {
    return Text(
      context.l10nText(label),
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(context.l10nText(label)),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primaryLight.withValues(alpha: 0.14),
      backgroundColor: AppColors.surfaceColor(context),
      side: BorderSide(
        color:
            selected ? AppColors.primaryLight : AppColors.borderColor(context),
      ),
      labelStyle: TextStyle(
        color:
            selected ? AppColors.primaryLight : AppColors.textPrimary(context),
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );
  }

  Widget _amountField(
    TextEditingController controller,
    String hint, {
    TextInputAction? textInputAction,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      onChanged: (_) {
        if (_amountError != null) setState(() => _amountError = null);
      },
      decoration: InputDecoration(
        hintText: context.l10nText(hint),
        isDense: true,
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
          borderSide: const BorderSide(color: AppColors.primaryLight),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
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
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
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
                TextButton(
                  onPressed: _clearAll,
                  child: Text(context.l10nText('Clear all')),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(AppIcons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('TYPE'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(
                        label: 'All',
                        selected: _selectedType == null,
                        onTap: () => setState(() => _selectedType = null),
                      ),
                      _chip(
                        label: 'Expense',
                        selected: _selectedType == 'DEBIT',
                        onTap: () => setState(() => _selectedType = 'DEBIT'),
                      ),
                      _chip(
                        label: 'Income',
                        selected: _selectedType == 'CREDIT',
                        onTap: () => setState(() => _selectedType = 'CREDIT'),
                      ),
                    ],
                  ),
                  if (widget.bankIds.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('BANK'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          label: 'All Banks',
                          selected: _selectedBankId == null,
                          onTap: () => _selectBank(null),
                        ),
                        for (final bankId in widget.bankIds)
                          _chip(
                            label: widget.bankLabel(bankId),
                            selected: _selectedBankId == bankId,
                            onTap: () => _selectBank(bankId),
                          ),
                      ],
                    ),
                  ],
                  if (widget.accounts.isNotEmpty ||
                      widget.unmatchedBankIds.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('ACCOUNT'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          label: 'All account activity',
                          selected: _selectedAccountKey == null,
                          onTap: () =>
                              setState(() => _selectedAccountKey = null),
                        ),
                        for (final account in _visibleAccounts)
                          _chip(
                            label: _accountLabel(account),
                            selected: _selectedAccountKey ==
                                _todayAccountKey(account),
                            onTap: () => setState(
                              () => _selectedAccountKey =
                                  _todayAccountKey(account),
                            ),
                          ),
                        for (final bankId in _visibleUnmatchedBankIds)
                          _chip(
                            label: _otherLabel(bankId),
                            selected: _selectedAccountKey ==
                                _todayOtherAccountKey(bankId),
                            onTap: () => setState(
                              () => _selectedAccountKey =
                                  _todayOtherAccountKey(bankId),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel('CATEGORY'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      CategoryFilterChip(
                        label: 'All',
                        selected: _selectedCategoryIds.isEmpty,
                        onTap: () =>
                            setState(() => _selectedCategoryIds.clear()),
                      ),
                      CategoryFilterChip(
                        label: 'Uncategorized',
                        selected: _selectedCategoryIds.contains(
                          uncategorizedCategoryFilterId,
                        ),
                        onTap: () => _toggleCategory(
                          uncategorizedCategoryFilterId,
                        ),
                      ),
                      for (final category in widget.categories)
                        if (category.id != null)
                          CategoryFilterChip(
                            label: category.name,
                            flow: category.flow,
                            subtleFlowTint: isSelfCategoryFilter(category),
                            selected: _selectedCategoryIds.contains(
                              category.id,
                            ),
                            onTap: () => _toggleCategory(category.id!),
                          ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('AMOUNT RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _amountField(
                          _minAmountController,
                          'Min',
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _amountField(
                          _maxAmountController,
                          'Max',
                          textInputAction: TextInputAction.done,
                        ),
                      ),
                    ],
                  ),
                  if (_amountError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.l10nText(_amountError!),
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              16 + bottomPadding + viewInsets,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(context.l10nText('Apply Filters')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayFilterActionButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const _TodayFilterActionButton({
    required this.activeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: context.l10nText('Filter Transactions'),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            AppIcons.filter_list,
            color: activeCount > 0
                ? AppColors.primaryLight
                : AppColors.textSecondary(context),
          ),
          if (activeCount > 0)
            Positioned(
              right: -7,
              top: -7,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$activeCount',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 9,
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

// ── Helpers ─────────────────────────────────────────────────────────────────

String _todayAccountKey(AccountSummary account) {
  return '${account.bankId}:${account.accountNumber}';
}

String _todayOtherAccountKey(int bankId) => 'other:$bankId';

int? _todayOtherAccountBankId(String key) {
  if (!key.startsWith('other:')) return null;
  return int.tryParse(key.substring('other:'.length));
}

String _amountLabel(
  double amount, {
  required bool isCredit,
  required String currencyLabel,
}) {
  final formatted = formatNumberWithComma(amount);
  return '${isCredit ? '+' : '-'} $currencyLabel $formatted';
}

String _counterparty(Transaction tx, {bool isSelfTransfer = false}) {
  final receiver = tx.receiver?.trim();
  final creditor = tx.creditor?.trim();
  if (receiver != null && receiver.isNotEmpty) return receiver.toUpperCase();
  if (creditor != null && creditor.isNotEmpty) return creditor.toUpperCase();
  return isSelfTransfer ? 'YOU' : 'UNKNOWN';
}

String _timeLabel(Transaction tx, BuildContext context) {
  if (tx.time == null || tx.time!.isEmpty) return '';
  try {
    final dt = DateTime.parse(tx.time!).toLocal();
    final isEC = AppDateFormat.usesEthiopianCalendar(context);
    if (isEC) {
      return AppDateFormat.ethiopianTime(dt, context: context);
    }
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  } catch (_) {
    return '';
  }
}
