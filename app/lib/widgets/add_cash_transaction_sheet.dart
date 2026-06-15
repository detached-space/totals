import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/app_date_format.dart';
import 'package:totals/utils/category_icons.dart';
import 'package:totals/utils/category_sort.dart';
import 'package:totals/l10n/app_localizations.dart';

Future<void> showAddCashTransactionSheet({
  required BuildContext context,
  required TransactionProvider provider,
  required String accountNumber,
  bool? initialIsDebit,
  bool showTypeSelector = true,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) {
      return _AddCashTransactionContent(
        provider: provider,
        accountNumber: accountNumber,
        initialIsDebit: initialIsDebit ?? true,
        showTypeSelector: showTypeSelector,
      );
    },
  );
}

class _AddCashTransactionContent extends StatefulWidget {
  final TransactionProvider provider;
  final String accountNumber;
  final bool initialIsDebit;
  final bool showTypeSelector;

  const _AddCashTransactionContent({
    required this.provider,
    required this.accountNumber,
    required this.initialIsDebit,
    required this.showTypeSelector,
  });

  @override
  State<_AddCashTransactionContent> createState() =>
      _AddCashTransactionContentState();
}

class _AddCashTransactionContentState
    extends State<_AddCashTransactionContent> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  final AccountRepository _accountRepo = AccountRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  late bool _isDebit;
  late AccountSummary _selectedAccount;
  late DateTime _selectedDateTime;
  List<Bank> _banks = const [];
  final List<int> _selectedCategoryIds = <int>[];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _noteController = TextEditingController();
    _isDebit = widget.initialIsDebit;
    _selectedAccount = _initialSelectedAccount();
    _selectedDateTime = DateTime.now();
    _loadBanks();
  }

  List<Category> get _filteredCategories {
    final flow = _isDebit ? 'expense' : 'income';
    return sortCategoriesAlphabetically(widget.provider.categories
        .where((c) => c.flow == flow && !c.uncategorized));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double? _parseAmount(String raw) {
    final cleaned = raw.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  List<AccountSummary> get _selectableAccounts {
    final summaries =
        List<AccountSummary>.from(widget.provider.accountSummaries)
          ..sort((a, b) {
            if (a.bankId == CashConstants.bankId) return -1;
            if (b.bankId == CashConstants.bankId) return 1;
            return a.bankId.compareTo(b.bankId);
          });
    final hasCash =
        summaries.any((summary) => summary.bankId == CashConstants.bankId);
    if (!hasCash) {
      summaries.insert(0, _cashAccountSummary());
    }
    return summaries;
  }

  AccountSummary _cashAccountSummary() {
    return AccountSummary(
      bankId: CashConstants.bankId,
      accountNumber: CashConstants.defaultAccountNumber,
      accountHolderName: CashConstants.defaultAccountHolderName,
      totalTransactions: 0,
      totalCredit: 0,
      totalDebit: 0,
      settledBalance: 0,
      balance: 0,
      pendingCredit: 0,
    );
  }

  AccountSummary _initialSelectedAccount() {
    final accounts = _selectableAccounts;
    final requestedAccountNumber = widget.accountNumber.trim();
    if (requestedAccountNumber.isNotEmpty) {
      for (final account in accounts) {
        if (account.accountNumber == requestedAccountNumber) {
          return account;
        }
      }
    }
    return accounts.first;
  }

  bool _sameAccount(AccountSummary a, AccountSummary b) {
    return a.bankId == b.bankId && a.accountNumber == b.accountNumber;
  }

  Bank _cashBank() {
    return Bank(
      id: CashConstants.bankId,
      name: CashConstants.bankName,
      shortName: CashConstants.bankShortName,
      codes: const [],
      image: 'assets/images/eth_birr.png',
      colors: CashConstants.bankColors,
    );
  }

  Map<int, Bank> get _banksById {
    return {
      CashConstants.bankId: _cashBank(),
      for (final bank in _banks) bank.id: bank,
    };
  }

  Bank _bankForAccount(AccountSummary account) {
    return _banksById[account.bankId] ??
        Bank(
          id: account.bankId,
          name: account.accountHolderName,
          shortName: account.bankId.toString(),
          codes: const [],
          image: '',
        );
  }

  Future<void> _loadBanks() async {
    final banks = await _bankConfigService.getBanks(allowRemoteFetch: false);
    if (!mounted) return;
    setState(() => _banks = banks);
  }

  Future<void> _ensureCashAccount() async {
    final accounts = await _accountRepo.getAccounts();
    final hasCash = accounts.any((a) => a.bank == CashConstants.bankId);
    if (hasCash) return;
    final cashAccount = Account(
      accountNumber: CashConstants.defaultAccountNumber,
      bank: CashConstants.bankId,
      balance: 0.0,
      accountHolderName: CashConstants.defaultAccountHolderName,
    );
    await _accountRepo.saveAccount(cashAccount);
  }

  Future<void> _updateStoredAccountBalance(
    AccountSummary selectedAccount,
    double remainingBalance,
  ) async {
    if (selectedAccount.bankId == CashConstants.bankId) return;

    final accounts = await _accountRepo.getAccounts();
    for (final account in accounts) {
      if (account.bank != selectedAccount.bankId ||
          account.accountNumber != selectedAccount.accountNumber) {
        continue;
      }

      await _accountRepo.saveAccount(
        Account(
          accountNumber: account.accountNumber,
          bank: account.bank,
          balance: remainingBalance,
          accountHolderName: account.accountHolderName,
          settledBalance: account.settledBalance,
          pendingCredit: account.pendingCredit,
          profileId: account.profileId,
        ),
      );
      return;
    }
  }

  double _remainingBalanceAfter(AccountSummary account, double amount) {
    return account.balance + (_isDebit ? -amount : amount);
  }

  String _manualReference(int bankId, int micros) {
    if (bankId == CashConstants.bankId) {
      return CashConstants.buildManualReference(micros);
    }
    return 'manual_${bankId}_$micros';
  }

  String _accountLabel(BuildContext context, AccountSummary account) {
    if (account.bankId == CashConstants.bankId) {
      return context.l10nText('Cash Wallet');
    }

    final bank = _bankForAccount(account);
    final shortName = bank.shortName.trim();
    if (shortName.isNotEmpty) return context.l10nText(shortName);
    final name = bank.name.trim();
    if (name.isNotEmpty) return context.l10nText(name);
    return context.l10nText('Bank');
  }

  Widget _buildAccountSelector(BuildContext context, Color accentColor) {
    final theme = Theme.of(context);
    final accounts = _selectableAccounts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10nText('Account'),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: accounts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final account = accounts[index];
              return _AccountSelectorChip(
                bank: _bankForAccount(account),
                label: _accountLabel(context, account),
                selected: _sameAccount(account, _selectedAccount),
                accentColor: accentColor,
                onTap: () => setState(() => _selectedAccount = account),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatTransactionDateTime(BuildContext context) {
    if (AppDateFormat.usesEthiopianCalendar(context)) {
      final date =
          AppDateFormat.monthDayYear(_selectedDateTime, context: context);
      final time = AppDateFormat.ethiopianTime(
        _selectedDateTime,
        context: context,
      );
      return '$date ${context.l10nText('at')} $time';
    }

    final month = AppDateFormat.monthFull(_selectedDateTime, context: context);
    final date = '${_selectedDateTime.day} $month ${_selectedDateTime.year}';
    final time = DateFormat('h:mm a').format(_selectedDateTime);
    return '$date ${context.l10nText('at')} $time';
  }

  Future<void> _pickTransactionDateTime() async {
    final current = _selectedDateTime;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (!mounted || pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted) return;

    final time = pickedTime ?? TimeOfDay.fromDateTime(current);
    setState(() {
      _selectedDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        time.hour,
        time.minute,
      );
    });
  }

  Widget _buildDateTimeField(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fieldRadius = BorderRadius.circular(12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10nText('Date & Time').toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: fieldRadius,
          child: InkWell(
            onTap: _pickTransactionDateTime,
            borderRadius: fieldRadius,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 54),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: fieldRadius,
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Text(
                _formatTransactionDateTime(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveTransaction() async {
    final amount = _parseAmount(_amountController.text);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10nTextRead('Enter a valid amount')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final selectedAccount = _selectedAccount;
      if (selectedAccount.bankId == CashConstants.bankId) {
        await _ensureCashAccount();
      }

      final now = DateTime.now();
      final note = _noteController.text.trim();
      final remainingBalance = _remainingBalanceAfter(selectedAccount, amount);
      final selectedCategoryIds =
          List<int>.from(_selectedCategoryIds, growable: false);
      await _updateStoredAccountBalance(selectedAccount, remainingBalance);
      final reference = _manualReference(
        selectedAccount.bankId,
        now.microsecondsSinceEpoch,
      );
      final transaction = Transaction(
        amount: amount,
        reference: reference,
        creditor: _isDebit || note.isEmpty ? null : note,
        receiver: _isDebit && note.isNotEmpty ? note : null,
        time: _selectedDateTime.toIso8601String(),
        bankId: selectedAccount.bankId,
        type: _isDebit ? 'DEBIT' : 'CREDIT',
        currentBalance: remainingBalance.toStringAsFixed(2),
        accountNumber: selectedAccount.accountNumber,
        categoryId:
            selectedCategoryIds.isEmpty ? null : selectedCategoryIds.first,
        categoryIds: selectedCategoryIds.isEmpty ? null : selectedCategoryIds,
      );

      await widget.provider.addTransaction(transaction);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10nTextRead('Error')}: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _cancel() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hintColor = colorScheme.onSurfaceVariant;
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final bottomSafeArea = mediaQuery.viewPadding.bottom;
    final keyboardLiftBuffer = keyboardInset > 0 ? 28.0 : 0.0;
    final actionBottomGap = keyboardInset > 0
        ? 4.0
        : (mediaQuery.size.height * 0.014).clamp(8.0, 14.0);
    final actionTopGap = keyboardInset > 0 ? 12.0 : 20.0;
    final formBottomPadding = keyboardInset > 0 ? 16.0 : 8.0;
    final accentColor = _isDebit ? Colors.red : Colors.green;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset + keyboardLiftBuffer),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : mediaQuery.size.height;

            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.only(
                          top: 8,
                          bottom: formBottomPadding,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _isDebit ? Icons.remove : Icons.add,
                                    color: accentColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _isDebit
                                        ? context.l10nText('Add Expense')
                                        : context.l10nText('Add Income'),
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            _buildAccountSelector(context, accentColor),
                            const SizedBox(height: 24),

                            if (widget.showTypeSelector) ...[
                              // Transaction Type Toggle
                              Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _TypeButton(
                                        label: 'Expense',
                                        icon: Icons.arrow_upward,
                                        isSelected: _isDebit,
                                        color: Colors.red,
                                        onTap: () => setState(() {
                                          _isDebit = true;
                                          _selectedCategoryIds.clear();
                                        }),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: _TypeButton(
                                        label: 'Income',
                                        icon: Icons.arrow_downward,
                                        isSelected: !_isDebit,
                                        color: Colors.green,
                                        onTap: () => setState(() {
                                          _isDebit = false;
                                          _selectedCategoryIds.clear();
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Amount Field
                            TextField(
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              autofocus: true,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                labelText: context.l10nText('Amount'),
                                hintText: '0.00',
                                hintStyle: TextStyle(color: hintColor),
                                labelStyle: TextStyle(color: hintColor),
                                floatingLabelStyle: TextStyle(
                                  color: hintColor,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixText: '${context.l10nText('ETB')} ',
                                prefixStyle:
                                    theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: hintColor,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: colorScheme.outline.withValues(
                                      alpha: 0.5,
                                    ),
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _isDebit ? Colors.red : Colors.green,
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // From/To Field
                            TextField(
                              controller: _noteController,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                labelText: _isDebit
                                    ? context.l10nText('To')
                                    : context.l10nText('From'),
                                hintText: _isDebit
                                    ? context.l10nText('Where did you spend?')
                                    : context.l10nText('Who paid you?'),
                                hintStyle: TextStyle(color: hintColor),
                                labelStyle: TextStyle(color: hintColor),
                                floatingLabelStyle: TextStyle(
                                  color: hintColor,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Icon(
                                  _isDebit
                                      ? Icons.call_made
                                      : Icons.call_received,
                                  size: 20,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: colorScheme.outline.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _isDebit ? Colors.red : Colors.green,
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Categories
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                context.l10nText('Categories'),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 36,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  _CashCategoryChip(
                                    label: 'None',
                                    icon: null,
                                    selected: _selectedCategoryIds.isEmpty,
                                    accentColor:
                                        _isDebit ? Colors.red : Colors.green,
                                    onTap: () =>
                                        setState(_selectedCategoryIds.clear),
                                  ),
                                  ..._filteredCategories.map((cat) {
                                    final categoryId = cat.id;
                                    if (categoryId == null) {
                                      return const SizedBox.shrink();
                                    }
                                    return _CashCategoryChip(
                                      label: cat.name,
                                      icon: iconForCategoryKey(cat.iconKey),
                                      selected: _selectedCategoryIds
                                          .contains(categoryId),
                                      accentColor:
                                          _isDebit ? Colors.red : Colors.green,
                                      onTap: () => setState(() {
                                        if (_selectedCategoryIds
                                            .contains(categoryId)) {
                                          _selectedCategoryIds
                                              .remove(categoryId);
                                        } else {
                                          _selectedCategoryIds.add(categoryId);
                                        }
                                      }),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            _buildDateTimeField(context),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: actionTopGap),
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: bottomSafeArea + actionBottomGap,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : _cancel,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: hintColor,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(context.l10nText('Cancel')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: _isLoading ? null : _saveTransaction,
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    _isDebit ? Colors.red : Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _isDebit
                                          ? context.l10nText('Save Expense')
                                          : context.l10nText('Save Income'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isSelected ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10nText(label),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color:
                      isSelected ? Colors.white : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountSelectorChip extends StatelessWidget {
  final Bank bank;
  final String label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _AccountSelectorChip({
    required this.bank,
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor =
        selected ? accentColor : colorScheme.outline.withValues(alpha: 0.28);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 52,
                    height: 52,
                    padding: EdgeInsets.all(selected ? 3 : 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: borderColor,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: ClipOval(
                      child: bank.image.isEmpty
                          ? _BankImageFallback(colorScheme: colorScheme)
                          : Image.asset(
                              bank.image,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _BankImageFallback(
                                colorScheme: colorScheme,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected ? accentColor : colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankImageFallback extends StatelessWidget {
  final ColorScheme colorScheme;

  const _BankImageFallback({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.account_balance,
        size: 22,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _CashCategoryChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _CashCategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = selected
        ? accentColor
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final fg = selected ? Colors.white : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                context.l10nText(label),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
