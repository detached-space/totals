import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/transaction_category_split.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/category_filter_utils.dart';
import 'package:totals/utils/category_sort.dart';
import 'package:totals/utils/category_style.dart';
import 'package:totals/utils/loan_debt_utils.dart';
import 'package:totals/utils/reimbursement_utils.dart';

typedef TransactionSplitSave = Future<Transaction> Function(
  List<TransactionCategorySplit> splits,
);

final NumberFormat _splitAmountFormat = NumberFormat('#,##0.00');

String _formatSplitMinor(int amountMinor) {
  return _splitAmountFormat.format(amountMinor.abs() / 100);
}

List<Category> availableTransactionSplitCategories(
  Transaction transaction,
  TransactionProvider provider,
) {
  final flow = switch (transaction.type?.trim().toUpperCase()) {
    'CREDIT' => 'income',
    'DEBIT' => 'expense',
    _ => null,
  };
  if (flow == null || provider.isSelfTransfer(transaction)) {
    return const <Category>[];
  }

  return sortCategoriesAlphabetically(
    provider.categories.where(
      (category) =>
          category.id != null &&
          category.flow.trim().toLowerCase() == flow &&
          !category.uncategorized &&
          !isSelfCategoryFilter(category) &&
          !isLoanDebtCategory(category) &&
          !isRepaymentCategory(category) &&
          !isReimbursementCategory(category),
    ),
  );
}

List<Category> selectedTransactionSplitCategories(
  Transaction transaction,
  TransactionProvider provider,
) {
  final eligibleById = <int, Category>{
    for (final category
        in availableTransactionSplitCategories(transaction, provider))
      category.id!: category,
  };
  return <Category>[
    for (final categoryId in transaction.selectedCategoryIds)
      if (eligibleById[categoryId] != null) eligibleById[categoryId]!,
  ];
}

bool hasSplittableCategorySelection(
  Transaction transaction,
  TransactionProvider provider,
) {
  final selected = selectedTransactionSplitCategories(transaction, provider);
  return selected.length >= 2 &&
      selected.length == transaction.selectedCategoryIds.length;
}

String transactionSplitAmountSummary(Transaction transaction) {
  if (!transaction.hasCategorySplit) return '';
  return transaction.categorySplits!
      .map((split) => 'ETB ${_formatSplitMinor(split.amountMinor)}')
      .join(' + ');
}

Future<Transaction?> showTransactionSplitSheet({
  required BuildContext context,
  required Transaction transaction,
  required TransactionProvider provider,
}) async {
  final categories = selectedTransactionSplitCategories(
    transaction,
    provider,
  );
  if (categories.length < 2 ||
      categories.length != transaction.selectedCategoryIds.length) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          context.l10nTextRead(
            'Choose at least two regular categories before splitting the amount.',
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return null;
  }

  return showModalBottomSheet<Transaction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.black.withValues(alpha: 0.5),
    builder: (_) => TransactionSplitSheet(
      transaction: transaction,
      categories: categories,
      onSave: (splits) => provider.updateCategorySplitsForTransaction(
        transaction,
        splits,
      ),
    ),
  );
}

class TransactionSplitSheet extends StatefulWidget {
  final Transaction transaction;
  final List<Category> categories;
  final TransactionSplitSave onSave;

  const TransactionSplitSheet({
    super.key,
    required this.transaction,
    required this.categories,
    required this.onSave,
  });

  @override
  State<TransactionSplitSheet> createState() => _TransactionSplitSheetState();
}

class _TransactionSplitSheetState extends State<TransactionSplitSheet> {
  final List<_SplitDraft> _drafts = <_SplitDraft>[];
  bool _isSaving = false;

  int get _totalMinor => widget.transaction.amountMinor;

  int get _manuallyAllocatedMinor {
    if (_drafts.length < 2) return 0;
    return _drafts
        .take(_drafts.length - 1)
        .fold<int>(0, (sum, draft) => sum + _minorFrom(draft.controller.text));
  }

  int get _remainderMinor => _totalMinor - _manuallyAllocatedMinor;

  bool get _hasEmptyManualPart {
    if (_drafts.length < 2) return true;
    return _drafts
        .take(_drafts.length - 1)
        .any((draft) => _minorFrom(draft.controller.text) <= 0);
  }

  bool get _canSave =>
      !_isSaving &&
      _drafts.length >= 2 &&
      !_hasEmptyManualPart &&
      _remainderMinor > 0;

  @override
  void initState() {
    super.initState();
    _initializeDrafts();
  }

  void _initializeDrafts() {
    final existingByCategory = <int, int>{};
    if (widget.transaction.hasCategorySplit) {
      for (final split in widget.transaction.categorySplits!) {
        existingByCategory[split.categoryId] = split.amountMinor;
      }
    }

    final canUseExisting =
        existingByCategory.length == widget.categories.length &&
            widget.categories.every(
              (category) => existingByCategory.containsKey(category.id),
            );
    final evenAmount =
        widget.categories.isEmpty ? 0 : _totalMinor ~/ widget.categories.length;

    for (var index = 0; index < widget.categories.length; index++) {
      final category = widget.categories[index];
      final amountMinor = canUseExisting
          ? existingByCategory[category.id]!
          : index == widget.categories.length - 1
              ? _totalMinor - (evenAmount * index)
              : evenAmount;
      final controller = TextEditingController(
        text: _editableAmountText(amountMinor),
      )..addListener(_handleDraftChanged);
      _drafts.add(
        _SplitDraft(
          category: category,
          controller: controller,
        ),
      );
    }
  }

  void _handleDraftChanged() {
    if (mounted) setState(() {});
  }

  String _editableAmountText(int amountMinor) {
    if (amountMinor <= 0) return '';
    return (amountMinor / 100).toStringAsFixed(2);
  }

  int _minorFrom(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    final amount = double.tryParse(normalized);
    return TransactionCategorySplit.toMinorUnits(amount ?? 0);
  }

  void _splitEvenly() {
    if (_isSaving || _drafts.length < 2) return;
    final base = _totalMinor ~/ _drafts.length;
    for (var index = 0; index < _drafts.length - 1; index++) {
      _drafts[index].controller.text = _editableAmountText(base);
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (!_canSave) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final splits = <TransactionCategorySplit>[];
    for (var index = 0; index < _drafts.length; index++) {
      splits.add(
        TransactionCategorySplit(
          categoryId: _drafts[index].category.id!,
          amountMinor: index == _drafts.length - 1
              ? _remainderMinor
              : _minorFrom(_drafts[index].controller.text),
        ),
      );
    }

    setState(() => _isSaving = true);
    try {
      final updated = await widget.onSave(splits);
      if (mounted) Navigator.of(context).pop(updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10nTextRead('Could not save the transaction split.'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.controller
        ..removeListener(_handleDraftChanged)
        ..dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;

    return AnimatedPadding(
      key: const ValueKey<String>('transaction-split-sheet'),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.82),
          color: AppColors.background(context),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 18),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderColor(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10nText('Split amount'),
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: AppColors.textPrimary(context),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              context.l10nText(
                                'Set how much belongs to each category',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        key: const ValueKey<String>(
                          'close-transaction-split',
                        ),
                        onTap: _isSaving ? null : () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.cardColor(context),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            AppIcons.close,
                            size: 16,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SplitTotalCard(
                          totalMinor: _totalMinor,
                          categoryCount: _drafts.length,
                          onSplitEvenly: _isSaving ? null : _splitEvenly,
                        ),
                        const SizedBox(height: 12),
                        for (var index = 0;
                            index < _drafts.length;
                            index++) ...[
                          _buildCategoryAmountRow(index),
                          if (index != _drafts.length - 1)
                            const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: _canSave
                                ? const LinearGradient(
                                    colors: <Color>[
                                      AppColors.primaryLight,
                                      AppColors.primaryDark,
                                    ],
                                  )
                                : null,
                            color: _canSave
                                ? null
                                : AppColors.textTertiary(context)
                                    .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: FilledButton(
                            key: const ValueKey<String>(
                              'save-transaction-split',
                            ),
                            onPressed: _canSave ? _save : null,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: Colors.transparent,
                              disabledBackgroundColor: Colors.transparent,
                              foregroundColor: AppColors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 19,
                                    height: 19,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.white,
                                    ),
                                  )
                                : Text(
                                    context.l10nText('Save split'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          context.l10nText(
                            widget.transaction.hasCategorySplit
                                ? "Closing this sheet won't save your edits. Your current split will stay as it is."
                                : "Closing this sheet won't save a split. Your selected categories will stay as they are.",
                          ),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary(context),
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryAmountRow(int index) {
    final theme = Theme.of(context);
    final draft = _drafts[index];
    final isRemainder = index == _drafts.length - 1;
    final color = categoryPaletteColor(
      draft.category,
      fallback: AppColors.primaryLight,
    );

    return Container(
      key: ValueKey<String>('split-part-$index'),
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            key: ValueKey<String>('split-part-$index-color-dot'),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10nText(draft.category.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (isRemainder)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_remainderMinor < 0 ? '-' : ''}'
                  'ETB ${_formatSplitMinor(_remainderMinor)}',
                  key: const ValueKey<String>('split-remainder-amount'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _remainderMinor <= 0
                        ? AppColors.red
                        : AppColors.textPrimary(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10nText('Auto remainder'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: 132,
              child: TextField(
                key: ValueKey<String>('split-part-$index-amount'),
                controller: draft.controller,
                enabled: !_isSaving,
                textAlign: TextAlign.end,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (RegExp(r'^\d{0,9}([.,]\d{0,2})?$')
                        .hasMatch(newValue.text)) {
                      return newValue;
                    }
                    return oldValue;
                  }),
                ],
                textInputAction: TextInputAction.next,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w800,
                ),
                decoration: InputDecoration(
                  prefixText: 'ETB ',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surfaceColor(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(
                      color: AppColors.primaryLight,
                      width: 1.4,
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

class _SplitDraft {
  final Category category;
  final TextEditingController controller;

  const _SplitDraft({
    required this.category,
    required this.controller,
  });
}

class _SplitTotalCard extends StatelessWidget {
  final int totalMinor;
  final int categoryCount;
  final VoidCallback? onSplitEvenly;

  const _SplitTotalCard({
    required this.totalMinor,
    required this.categoryCount,
    required this.onSplitEvenly,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryLight.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10nText('Transaction total'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ETB ${_formatSplitMinor(totalMinor)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$categoryCount ${context.l10nText('categories')}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            key: const ValueKey<String>('split-evenly'),
            onPressed: onSplitEvenly,
            icon: const Icon(Icons.balance_rounded, size: 16),
            label: Text(
              context.l10nText('Split evenly'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryLight,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}
