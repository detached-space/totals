import 'package:flutter/material.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/utils/category_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

Future<void> showAddCashTransactionSheet({
  required BuildContext context,
  required TransactionProvider provider,
  required String accountNumber,
  bool? initialIsDebit,
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
      );
    },
  );
}

class _AddCashTransactionContent extends StatefulWidget {
  final TransactionProvider provider;
  final String accountNumber;
  final bool initialIsDebit;

  const _AddCashTransactionContent({
    required this.provider,
    required this.accountNumber,
    required this.initialIsDebit,
  });

  @override
  State<_AddCashTransactionContent> createState() =>
      _AddCashTransactionContentState();
}

class _AddCashTransactionContentState
    extends State<_AddCashTransactionContent> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late bool _isDebit;
  int? _selectedCategoryId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _noteController = TextEditingController();
    _isDebit = widget.initialIsDebit;
  }

  List<Category> get _filteredCategories {
    final flow = _isDebit ? 'expense' : 'income';
    return widget.provider.categories
        .where((c) => c.flow == flow && !c.uncategorized)
        .toList();
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

  double _currentCashWalletBalance() {
    final walletSummaries = widget.provider.accountSummaries
        .where((summary) => summary.bankId == CashConstants.bankId)
        .toList();
    if (walletSummaries.isEmpty) return 0.0;
    return walletSummaries.fold<double>(
      0.0,
      (sum, summary) => sum + summary.balance,
    );
  }

  Future<void> _ensureCashAccount() async {
    final accountRepo = AccountRepository();
    final accounts = await accountRepo.getAccounts();
    final hasCash = accounts.any((a) => a.bank == CashConstants.bankId);
    if (hasCash) return;
    final cashAccount = Account(
      accountNumber: CashConstants.defaultAccountNumber,
      bank: CashConstants.bankId,
      balance: 0.0,
      accountHolderName: CashConstants.defaultAccountHolderName,
    );
    await accountRepo.saveAccount(cashAccount);
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
      await _ensureCashAccount();

      final now = DateTime.now();
      final note = _noteController.text.trim();
      final nextCashBalance =
          _currentCashWalletBalance() + (_isDebit ? -amount : amount);
      final reference = CashConstants.buildManualReference(
        now.microsecondsSinceEpoch,
      );
      final transaction = Transaction(
        amount: amount,
        reference: reference,
        creditor: _isDebit || note.isEmpty ? null : note,
        receiver: _isDebit && note.isNotEmpty ? note : null,
        time: now.toIso8601String(),
        bankId: CashConstants.bankId,
        type: _isDebit ? 'DEBIT' : 'CREDIT',
        currentBalance: nextCashBalance.toStringAsFixed(2),
        accountNumber: widget.accountNumber.isNotEmpty
            ? widget.accountNumber
            : CashConstants.defaultAccountNumber,
        categoryId: _selectedCategoryId,
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
                                    color:
                                        (_isDebit ? Colors.red : Colors.green)
                                            .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _isDebit ? Icons.remove : Icons.add,
                                    color: _isDebit ? Colors.red : Colors.green,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _isDebit
                                        ? context.l10nText('Add Cash Expense')
                                        : context.l10nText('Add Cash Income'),
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

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
                                        _selectedCategoryId = null;
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
                                        _selectedCategoryId = null;
                                      }),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

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

                            // Category
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                context.l10nText('Category'),
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
                                    selected: _selectedCategoryId == null,
                                    accentColor:
                                        _isDebit ? Colors.red : Colors.green,
                                    onTap: () => setState(
                                        () => _selectedCategoryId = null),
                                  ),
                                  ..._filteredCategories.map((cat) {
                                    return _CashCategoryChip(
                                      label: cat.name,
                                      icon: iconForCategoryKey(cat.iconKey),
                                      selected: _selectedCategoryId == cat.id,
                                      accentColor:
                                          _isDebit ? Colors.red : Colors.green,
                                      onTap: () => setState(
                                        () => _selectedCategoryId = cat.id,
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
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
                              onPressed: _isLoading
                                  ? null
                                  : () => Navigator.pop(context),
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
