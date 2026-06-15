import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/screens/loans_page.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/theme/app_calendar_option.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/widgets/transaction_category_sheet.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/app_date_format.dart';
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
        final transactions = provider.todayTransactions;

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
              if (_isSelecting)
                IconButton(
                  onPressed: () => _deleteSelected(provider),
                  icon: Icon(AppIcons.delete_outline_rounded,
                      color: AppColors.red),
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
                        context.l10nText('No transactions today'),
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

// ── Helpers ─────────────────────────────────────────────────────────────────

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
