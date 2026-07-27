import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/reimbursement_allocation.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/budget_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/reimbursement_repository.dart';
import 'package:totals/utils/reimbursement_utils.dart';
import 'package:totals/utils/transaction_amounts.dart';

enum ReimbursementLinkOutcome {
  linked,
  cancelled,
}

Future<ReimbursementLinkOutcome> showReimbursementLinkSheet({
  required BuildContext context,
  required Transaction transaction,
  required TransactionProvider provider,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final result = await showModalBottomSheet<ReimbursementLinkOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => _ReimbursementLinkSheet(
      transaction: transaction,
      provider: provider,
    ),
  );
  return result ?? ReimbursementLinkOutcome.cancelled;
}

class _ReimbursementCandidate {
  final Transaction transaction;
  final double paidAmount;
  final double availableAmount;
  final DateTime? timestamp;
  final String searchText;

  const _ReimbursementCandidate({
    required this.transaction,
    required this.paidAmount,
    required this.availableAmount,
    required this.timestamp,
    required this.searchText,
  });
}

class _ReimbursementLinkSheet extends StatefulWidget {
  final Transaction transaction;
  final TransactionProvider provider;

  const _ReimbursementLinkSheet({
    required this.transaction,
    required this.provider,
  });

  @override
  State<_ReimbursementLinkSheet> createState() =>
      _ReimbursementLinkSheetState();
}

class _ReimbursementLinkSheetState extends State<_ReimbursementLinkSheet> {
  static const _epsilon = 0.005;

  final ReimbursementRepository _repository = ReimbursementRepository();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, TextEditingController> _amountControllers = {};
  final Map<String, double> _draftAmounts = {};

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  String _query = '';
  List<_ReimbursementCandidate> _candidates = const [];

  double get _receivedAmount => widget.transaction.amount.abs();

  double get _draftTotal => _draftAmounts.values.fold<double>(
        0.0,
        (sum, amount) => sum + amount,
      );

  double get _remainingAmount => math.max(0.0, _receivedAmount - _draftTotal);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final controller in _amountControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    // Let the loading state paint before scanning a large transaction history.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    try {
      final allocations = widget.provider.reimbursementAllocations;
      final reimbursementReference = widget.transaction.reference.trim();
      final existingForCredit = <String, double>{};
      final appliedByExpenseExcludingCurrent = <String, double>{};

      for (final allocation in allocations) {
        final expenseReference = allocation.expenseTransactionReference.trim();
        if (expenseReference.isEmpty) continue;
        if (allocation.reimbursementTransactionReference.trim() ==
            reimbursementReference) {
          existingForCredit.update(
            expenseReference,
            (current) => current + allocation.appliedAmount,
            ifAbsent: () => allocation.appliedAmount,
          );
        } else {
          appliedByExpenseExcludingCurrent.update(
            expenseReference,
            (current) => current + allocation.appliedAmount,
            ifAbsent: () => allocation.appliedAmount,
          );
        }
      }

      final candidates = <_ReimbursementCandidate>[];
      for (final transaction in widget.provider.allTransactions) {
        if (transaction.type?.trim().toUpperCase() != 'DEBIT') continue;
        final reference = transaction.reference.trim();
        if (reference.isEmpty || widget.provider.isSelfTransfer(transaction)) {
          continue;
        }
        final paidAmount = transactionDebitOutflow(transaction);
        final appliedElsewhere =
            appliedByExpenseExcludingCurrent[reference] ?? 0.0;
        final availableAmount = math.max(0.0, paidAmount - appliedElsewhere);
        final isExisting = existingForCredit.containsKey(reference);
        if (availableAmount <= _epsilon && !isExisting) continue;
        final searchText = <String>[
          widget.provider.categoryLabelForTransaction(transaction),
          widget.provider.getBankShortName(transaction.bankId),
          _transactionCounterparty(transaction),
        ].join(' ').toLowerCase();
        candidates.add(
          _ReimbursementCandidate(
            transaction: transaction,
            paidAmount: paidAmount,
            availableAmount: availableAmount,
            timestamp: DateTime.tryParse(transaction.time?.trim() ?? ''),
            searchText: searchText,
          ),
        );
      }

      for (final entry in existingForCredit.entries) {
        _setDraftAmount(entry.key, entry.value, notify: false);
      }
      setState(() {
        _candidates = candidates;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _setDraftAmount(
    String reference,
    double amount, {
    bool notify = true,
  }) {
    final normalized = amount <= _epsilon ? 0.0 : amount;
    if (normalized <= 0) {
      _draftAmounts.remove(reference);
      _amountControllers.remove(reference)?.dispose();
    } else {
      _draftAmounts[reference] = normalized;
      final formatted = _editableAmount(normalized);
      final controller = _amountControllers.putIfAbsent(
        reference,
        () => TextEditingController(text: formatted),
      );
      if (controller.text != formatted) {
        controller.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
    if (notify && mounted) setState(() {});
  }

  void _applyCandidate(_ReimbursementCandidate candidate) {
    final reference = candidate.transaction.reference;
    final amount = math.min(
      candidate.availableAmount,
      _remainingAmount,
    );
    if (amount <= _epsilon) return;
    _setDraftAmount(reference, amount);
  }

  void _onAmountChanged(
    _ReimbursementCandidate candidate,
    String raw,
  ) {
    final parsed = double.tryParse(raw.replaceAll(',', '').trim()) ?? 0.0;
    if (parsed <= _epsilon) {
      _draftAmounts.remove(candidate.transaction.reference);
    } else {
      _draftAmounts[candidate.transaction.reference] = parsed;
    }
    setState(() {});
  }

  bool get _hasValidationError {
    if (_draftTotal - _receivedAmount > _epsilon) return true;
    for (final candidate in _candidates) {
      final amount = _draftAmounts[candidate.transaction.reference] ?? 0.0;
      if (amount - candidate.availableAmount > _epsilon) return true;
    }
    return false;
  }

  String? _candidateError(_ReimbursementCandidate candidate) {
    final amount = _draftAmounts[candidate.transaction.reference] ?? 0.0;
    if (amount - candidate.availableAmount > _epsilon) {
      return context.l10nText(
        'This is more than the amount available on this expense.',
      );
    }
    if (_draftTotal - _receivedAmount > _epsilon) {
      return context.l10nText(
        'The total applied is more than the reimbursement received.',
      );
    }
    return null;
  }

  Future<void> _save() async {
    if (_isSaving || _draftAmounts.isEmpty || _hasValidationError) return;
    setState(() => _isSaving = true);
    try {
      await _repository.replaceForReimbursement(
        reimbursementTransactionReference: widget.transaction.reference,
        allocations: _draftAmounts.entries.map(
          (entry) => ReimbursementAllocationDraft(
            expenseTransactionReference: entry.key,
            appliedAmount: entry.value,
          ),
        ),
      );
      await _refreshAffectedState();
      if (!mounted) return;
      Navigator.pop(context, ReimbursementLinkOutcome.linked);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _refreshAffectedState() async {
    BudgetProvider? budgetProvider;
    try {
      budgetProvider = context.read<BudgetProvider>();
    } catch (_) {}
    await Future.wait<void>([
      widget.provider.refreshReimbursements(),
      if (budgetProvider != null)
        budgetProvider.refreshBudgetStatuses(waitForWidget: false),
    ]);
  }

  List<_ReimbursementCandidate> get _visibleCandidates {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _candidates;
    return _candidates
        .where((candidate) => candidate.searchText.contains(query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final bottomSafeArea = mediaQuery.viewPadding.bottom;
    final keyboardLiftBuffer = keyboardInset > 0 ? 28.0 : 0.0;
    final actionBottomGap = keyboardInset > 0
        ? 4.0
        : (mediaQuery.size.height * 0.014).clamp(8.0, 14.0);
    final theme = Theme.of(context);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: keyboardInset + keyboardLiftBuffer,
      ),
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: Material(
          color: AppColors.cardColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderColor(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 10, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10nText(
                              'Which expense were you reimbursed for?',
                            ),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_formatEtb(_receivedAmount)} '
                            '${context.l10nText('received')}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(
                                context,
                                ReimbursementLinkOutcome.cancelled,
                              ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: context.l10nText('Search expenses'),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surfaceColor(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppColors.borderColor(context),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppColors.borderColor(context),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: _buildBody()),
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  bottomSafeArea + actionBottomGap,
                ),
                decoration: BoxDecoration(
                  color: AppColors.cardColor(context),
                  border: Border(
                    top: BorderSide(color: AppColors.borderColor(context)),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10nText('Applied'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: AppColors.textSecondary(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${_formatEtb(_draftTotal)} / '
                          '${_formatEtb(_receivedAmount)}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: _hasValidationError
                                ? AppColors.red
                                : AppColors.textPrimary(context),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('save-reimbursement-links'),
                        onPressed: _isSaving ||
                                _draftAmounts.isEmpty ||
                                _hasValidationError
                            ? null
                            : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                context.l10nText('Save reimbursement'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
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
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _load,
                child: Text(context.l10nText('Try again')),
              ),
            ],
          ),
        ),
      );
    }

    final candidates = _visibleCandidates;
    if (candidates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _query.isEmpty
                ? context.l10nText(
                    'No expenses are available to reimburse.',
                  )
                : context.l10nText('No matching expenses found.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
      );
    }

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: candidates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildCandidateCard(candidates[index]),
    );
  }

  Widget _buildCandidateCard(_ReimbursementCandidate candidate) {
    final theme = Theme.of(context);
    final transaction = candidate.transaction;
    final reference = transaction.reference;
    // Keep the editor mounted while the user temporarily clears the field.
    // The controller is removed only through the explicit remove action.
    final isSelected = _amountControllers.containsKey(reference);
    final error = _candidateError(candidate);
    final category = widget.provider.categoryLabelForTransaction(transaction);
    final bankImage = widget.provider.getBankImage(transaction.bankId);
    final date = candidate.timestamp == null
        ? context.l10nText('Unknown date')
        : DateFormat('MMM d, y').format(candidate.timestamp!);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: error != null
              ? AppColors.red
              : isSelected
                  ? AppColors.primaryLight
                  : AppColors.borderColor(context),
          width: isSelected ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ExpenseBankLogo(
                imagePath: bankImage,
                size: 38,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10nText(category),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        date,
                        _transactionCounterparty(transaction),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${_formatEtb(candidate.paidAmount)} '
            '${context.l10nText('paid')} · '
            '${_formatEtb(candidate.availableAmount)} '
            '${context.l10nText('available')}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (!isSelected)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: ValueKey('apply-reimbursement-$reference'),
                onPressed: _remainingAmount <= _epsilon || _isSaving
                    ? null
                    : () => _applyCandidate(candidate),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                  side: const BorderSide(color: AppColors.primaryLight),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  '${context.l10nText('Apply')} '
                  '${_formatEtb(math.min(candidate.availableAmount, _remainingAmount))}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('reimbursement-amount-$reference'),
                    controller: _amountControllers[reference],
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    onChanged: (value) => _onAmountChanged(candidate, value),
                    decoration: InputDecoration(
                      labelText: context.l10nText('Amount applied'),
                      prefixText: 'ETB ',
                      errorText: error,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: context.l10nText('Remove'),
                  onPressed:
                      _isSaving ? null : () => _setDraftAmount(reference, 0),
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.red,
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _editableAmount(double amount) {
    if ((amount - amount.roundToDouble()).abs() < 0.001) {
      return amount.toStringAsFixed(0);
    }
    return amount.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  String _formatEtb(double amount) {
    return 'ETB ${NumberFormat('#,##0.##').format(amount)}';
  }

  String _transactionCounterparty(Transaction transaction) {
    final receiver = transaction.receiver?.trim();
    if (receiver != null && receiver.isNotEmpty) return receiver;
    final creditor = transaction.creditor?.trim();
    if (creditor != null && creditor.isNotEmpty) return creditor;
    final note = transaction.note?.trim();
    if (note != null && note.isNotEmpty) return note;
    return context.l10nTextRead('Expense');
  }
}

class _ExpenseBankLogo extends StatelessWidget {
  final String imagePath;
  final double size;

  const _ExpenseBankLogo({
    required this.imagePath,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 512)
        .toInt();
    final fallback = Container(
      width: size,
      height: size,
      color: AppColors.mutedFill(context),
      alignment: Alignment.center,
      child: Icon(
        Icons.account_balance_rounded,
        size: size * 0.5,
        color: AppColors.textSecondary(context),
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: imagePath.trim().isEmpty
            ? fallback
            : Image.asset(
                imagePath,
                fit: BoxFit.cover,
                cacheWidth: decodeSize,
                cacheHeight: decodeSize,
                errorBuilder: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

class ReimbursementRelationshipsSection extends StatelessWidget {
  final Transaction transaction;
  final TransactionProvider provider;
  final ValueChanged<Transaction>? onTransactionUpdated;

  const ReimbursementRelationshipsSection({
    super.key,
    required this.transaction,
    required this.provider,
    this.onTransactionUpdated,
  });

  Future<void> _countAsIncome(BuildContext context) async {
    final currentTransaction =
        provider.transactionByReference(transaction.reference) ?? transaction;
    final categoryIds =
        currentTransaction.selectedCategoryIds.where((categoryId) {
      final category = provider.getCategoryById(categoryId);
      return category == null || !isReimbursementCategory(category);
    }).toList(growable: false);
    final currentPrimary = currentTransaction.categoryId;
    final primaryCategoryId =
        currentPrimary != null && categoryIds.contains(currentPrimary)
            ? currentPrimary
            : (categoryIds.isEmpty ? null : categoryIds.first);

    try {
      final updated = await provider.updateCategoriesForTransaction(
        currentTransaction,
        categoryIds: categoryIds,
        primaryCategoryId: primaryCategoryId,
      );
      onTransactionUpdated?.call(updated);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: provider,
      builder: (context, _) {
        final currentTransaction =
            provider.transactionByReference(transaction.reference) ??
                transaction;
        final isCredit =
            currentTransaction.type?.trim().toUpperCase() == 'CREDIT';
        final allocations = isCredit
            ? provider.reimbursementsForCredit(currentTransaction.reference)
            : provider.reimbursementsForExpense(currentTransaction.reference);
        final isUnlinkedReimbursement =
            isCredit && provider.isReimbursementTransaction(currentTransaction);
        if (allocations.isEmpty && !isUnlinkedReimbursement) {
          return const SizedBox.shrink();
        }

        final total = allocations.fold<double>(
          0.0,
          (sum, allocation) => sum + allocation.appliedAmount,
        );
        final theme = Theme.of(context);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16),
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
                children: [
                  const Icon(
                    Icons.currency_exchange_rounded,
                    color: AppColors.primaryLight,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10nText(
                        isCredit ? 'Applied to expenses' : 'Reimbursements',
                      ),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (total > 0)
                    Text(
                      'ETB ${NumberFormat('#,##0.##').format(total)}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
              if (allocations.isEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  context.l10nText(
                    'Not linked to an expense. It does not reduce a budget.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary(context),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => showReimbursementLinkSheet(
                      context: context,
                      transaction: currentTransaction,
                      provider: provider,
                    ),
                    child: Text(context.l10nText('Link an expense')),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => _countAsIncome(context),
                    child: Text(
                      context.l10nText('Count as income instead'),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                ...allocations.map(
                  (allocation) => _ReimbursementRelationshipRow(
                    allocation: allocation,
                    showExpense: isCredit,
                    provider: provider,
                    onTransactionUpdated:
                        isCredit ? onTransactionUpdated : null,
                  ),
                ),
                if (isCredit) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => showReimbursementLinkSheet(
                        context: context,
                        transaction: currentTransaction,
                        provider: provider,
                      ),
                      child: Text(
                        context.l10nText('Edit reimbursement links'),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReimbursementRelationshipRow extends StatefulWidget {
  final ReimbursementAllocation allocation;
  final bool showExpense;
  final TransactionProvider provider;
  final ValueChanged<Transaction>? onTransactionUpdated;

  const _ReimbursementRelationshipRow({
    required this.allocation,
    required this.showExpense,
    required this.provider,
    this.onTransactionUpdated,
  });

  @override
  State<_ReimbursementRelationshipRow> createState() =>
      _ReimbursementRelationshipRowState();
}

class _ReimbursementRelationshipRowState
    extends State<_ReimbursementRelationshipRow> {
  bool _isRemoving = false;

  Future<void> _unlink() async {
    final id = widget.allocation.id;
    if (id == null || _isRemoving) return;
    setState(() => _isRemoving = true);
    try {
      final updated = await widget.provider.unlinkReimbursementAllocation(id);
      if (updated != null) {
        widget.onTransactionUpdated?.call(updated);
      }
      if (!mounted) return;
      try {
        await context
            .read<BudgetProvider>()
            .refreshBudgetStatuses(waitForWidget: false);
      } catch (_) {}
    } catch (error) {
      if (!mounted) return;
      setState(() => _isRemoving = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reference = widget.showExpense
        ? widget.allocation.expenseTransactionReference
        : widget.allocation.reimbursementTransactionReference;
    final linked = widget.provider.transactionByReference(reference);
    final category = linked == null
        ? context.l10nText('Deleted transaction')
        : widget.provider.categoryLabelForTransaction(linked);
    final timestamp = DateTime.tryParse(linked?.time?.trim() ?? '');
    final date =
        timestamp == null ? null : DateFormat('MMM d, y').format(timestamp);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10nText(category),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (date != null)
                  Text(
                    date,
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            'ETB ${NumberFormat('#,##0.##').format(widget.allocation.appliedAmount)}',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10nText('Unlink'),
            visualDensity: VisualDensity.compact,
            onPressed: _isRemoving ? null : _unlink,
            icon: _isRemoving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link_off_rounded, size: 18),
            color: AppColors.textSecondary(context),
          ),
        ],
      ),
    );
  }
}
