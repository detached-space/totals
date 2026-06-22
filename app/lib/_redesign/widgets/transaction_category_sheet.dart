import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:totals/_redesign/screens/loans_page.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/loan_debt_repository.dart';
import 'package:totals/utils/category_sort.dart';
import 'package:totals/utils/loan_debt_utils.dart';
import 'package:totals/l10n/app_localizations.dart';

Future<void> showTransactionCategorySheet({
  required BuildContext context,
  required Transaction transaction,
  required TransactionProvider provider,
  bool allowAutoCategorizationRuleUpdates = true,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final hostContext = context;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TransactionCategorySheet(
      hostContext: hostContext,
      transaction: transaction,
      provider: provider,
      allowAutoCategorizationRuleUpdates: allowAutoCategorizationRuleUpdates,
    ),
  );
}

class _TransactionCategorySheet extends StatefulWidget {
  final BuildContext hostContext;
  final Transaction transaction;
  final TransactionProvider provider;
  final bool allowAutoCategorizationRuleUpdates;

  const _TransactionCategorySheet({
    required this.hostContext,
    required this.transaction,
    required this.provider,
    this.allowAutoCategorizationRuleUpdates = true,
  });

  @override
  State<_TransactionCategorySheet> createState() =>
      _TransactionCategorySheetState();
}

class _TransactionCategorySheetState extends State<_TransactionCategorySheet> {
  bool _showNewCategoryForm = false;
  bool _showColorChoices = false;
  bool _isApplyingCategory = false;
  bool _autoCategorizeFutureTransactions = false;
  String _draftColorKey = _kCategoryColorOptions.first.key;
  List<int> _autoCategorizationDraftCategoryIds = const [];
  late Transaction _transaction;
  final TextEditingController _newCategoryController = TextEditingController();
  final FocusNode _newCategoryFocus = FocusNode();
  final ScrollController _sheetScrollController = ScrollController();
  double _lastKeyboardInset = 0;

  Transaction get _tx => _transaction;
  TransactionProvider get _provider => widget.provider;

  bool get _isCredit => _tx.type == 'CREDIT';

  List<Category> get _currentCategories =>
      _provider.categoriesForTransaction(_tx);
  List<int> get _selectedCategoryIds => _tx.selectedCategoryIds;
  String? get _autoCategorizationCounterparty =>
      _provider.resolvePrimaryCounterparty(_tx);

  bool get _canShowAutoCategorizationOption =>
      widget.allowAutoCategorizationRuleUpdates &&
      _provider.canConfigureAutoCategorizationForTransaction(_tx) &&
      !_currentCategories.any(_isLoanDebtManagedCategory);
  bool get _canSelectRepaymentCategory => true;
  bool get _shouldShowRepaymentUnavailableHint => false;

  @override
  void initState() {
    super.initState();
    _transaction = widget.transaction;
    _syncAutoCategorizationCheckbox();
  }

  List<Category> get _availableCategories {
    final desiredFlow = _isCredit ? 'income' : 'expense';
    final filtered = _provider.categories
        .where((category) => category.flow.toLowerCase() == desiredFlow)
        .toList(growable: false);
    final base = filtered.isEmpty ? _provider.categories : filtered;
    return sortCategoriesAlphabetically(
      base.where((category) => category.name.trim().toLowerCase() != 'self'),
    );
  }

  void _syncAutoCategorizationCheckbox() {
    if (!widget.allowAutoCategorizationRuleUpdates) {
      _autoCategorizeFutureTransactions = false;
      _autoCategorizationDraftCategoryIds = const [];
      return;
    }

    _autoCategorizeFutureTransactions =
        _provider.autoCategorizationRulesForTransaction(_tx).isNotEmpty;
    _autoCategorizationDraftCategoryIds =
        _initialAutoCategorizationDraftCategoryIds(_tx);
  }

  List<int> _initialAutoCategorizationDraftCategoryIds(
      Transaction transaction) {
    if (!_autoCategorizeFutureTransactions) return const [];
    final existingIds = _provider
        .autoCategorizationCategoryIdsForTransaction(transaction)
        .where(_canAutoCategorizeCategoryId)
        .toList(growable: false);
    if (existingIds.isNotEmpty) return existingIds;

    final selectedIds = transaction.selectedCategoryIds
        .where(_canAutoCategorizeCategoryId)
        .toList(growable: false);
    return selectedIds.isEmpty ? const [] : selectedIds;
  }

  List<int> _nextAutoCategorizationDraftCategoryIds({
    required Transaction previous,
    required Transaction updated,
  }) {
    if (!_autoCategorizeFutureTransactions) return const [];

    final previousSelectedIds = previous.selectedCategoryIds
        .where(_canAutoCategorizeCategoryId)
        .toSet();
    final nextSelectedIds = updated.selectedCategoryIds
        .where(_canAutoCategorizeCategoryId)
        .toList(growable: false);

    final rememberedIds = <int>[];

    void remember(int categoryId) {
      if (categoryId <= 0 || rememberedIds.contains(categoryId)) return;
      if (!_canAutoCategorizeCategoryId(categoryId)) return;
      rememberedIds.add(categoryId);
    }

    for (final categoryId in _autoCategorizationDraftCategoryIds) {
      remember(categoryId);
    }

    for (final categoryId in nextSelectedIds) {
      if (!previousSelectedIds.contains(categoryId)) {
        remember(categoryId);
      }
    }

    return rememberedIds;
  }

  int? _resolveAutoCategorizationPrimaryCategoryId(List<int> categoryIds) {
    if (categoryIds.isEmpty) return null;
    if (_tx.categoryId != null && categoryIds.contains(_tx.categoryId)) {
      return _tx.categoryId;
    }
    return categoryIds.first;
  }

  List<Category> get _autoCategorizationDraftCategories {
    final categories = <Category>[];
    for (final categoryId in _autoCategorizationDraftCategoryIds) {
      final category = _provider.getCategoryById(categoryId);
      if (category != null) {
        categories.add(category);
      }
    }
    return categories;
  }

  Future<void> _persistAutoCategorizationDraft({
    required bool hadExistingRules,
  }) async {
    if (!widget.allowAutoCategorizationRuleUpdates) return;

    if (_autoCategorizeFutureTransactions &&
        _autoCategorizationDraftCategoryIds.isNotEmpty) {
      await _provider.syncAutoCategorizationRulesForSelection(
        transaction: _tx,
        categoryIds: _autoCategorizationDraftCategoryIds,
        primaryCategoryId: _resolveAutoCategorizationPrimaryCategoryId(
          _autoCategorizationDraftCategoryIds,
        ),
        shouldAutoCategorize: true,
      );
    } else if (hadExistingRules) {
      await _provider.clearAutoCategorizationRuleForTransaction(_tx);
    }
  }

  Future<void> _toggleAutoCategorization() async {
    if (_isApplyingCategory || !widget.allowAutoCategorizationRuleUpdates) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errorMessage = context.l10nTextRead(
      'Could not update auto-categorization. Changes were reverted.',
    );
    final hadExistingRules =
        _provider.autoCategorizationRulesForTransaction(_tx).isNotEmpty;
    final previousEnabled = _autoCategorizeFutureTransactions;
    final previousDraftIds =
        List<int>.from(_autoCategorizationDraftCategoryIds);
    final nextEnabled = !previousEnabled;
    final nextDraftIds = nextEnabled
        ? _tx.selectedCategoryIds
            .where(_canAutoCategorizeCategoryId)
            .toList(growable: false)
        : const <int>[];
    final shouldEnable = nextEnabled && nextDraftIds.isNotEmpty;

    setState(() {
      _isApplyingCategory = true;
      _autoCategorizeFutureTransactions = shouldEnable;
      _autoCategorizationDraftCategoryIds = nextDraftIds;
    });

    try {
      await _persistAutoCategorizationDraft(
        hadExistingRules: hadExistingRules,
      );
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(errorMessage),
        ),
      );
      if (!mounted) return;
      setState(() {
        _autoCategorizeFutureTransactions = previousEnabled;
        _autoCategorizationDraftCategoryIds = previousDraftIds;
      });
    } finally {
      if (mounted) {
        setState(() => _isApplyingCategory = false);
      }
    }
  }

  Future<void> _dismissAutoCategorizationCategory(Category category) async {
    final categoryId = category.id;
    if (categoryId == null || _isApplyingCategory) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errorMessage = context.l10nTextRead(
      'Could not update auto-categorization. Changes were reverted.',
    );
    final hadExistingRules =
        _provider.autoCategorizationRulesForTransaction(_tx).isNotEmpty;
    final previousEnabled = _autoCategorizeFutureTransactions;
    final previousDraftIds =
        List<int>.from(_autoCategorizationDraftCategoryIds);
    final nextDraftIds = _autoCategorizationDraftCategoryIds
        .where((id) => id != categoryId)
        .toList(growable: false);

    setState(() {
      _isApplyingCategory = true;
      _autoCategorizationDraftCategoryIds = nextDraftIds;
      _autoCategorizeFutureTransactions = nextDraftIds.isNotEmpty;
    });

    try {
      await _persistAutoCategorizationDraft(
        hadExistingRules: hadExistingRules,
      );
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(errorMessage),
        ),
      );
      if (!mounted) return;
      setState(() {
        _autoCategorizeFutureTransactions = previousEnabled;
        _autoCategorizationDraftCategoryIds = previousDraftIds;
      });
    } finally {
      if (mounted) {
        setState(() => _isApplyingCategory = false);
      }
    }
  }

  void _dismissComposerState({bool clearDraft = false}) {
    FocusManager.instance.primaryFocus?.unfocus();
    _newCategoryFocus.unfocus();
    if (!_showNewCategoryForm && !_showColorChoices && !clearDraft) return;
    if (!mounted) return;
    setState(() {
      _showNewCategoryForm = false;
      _showColorChoices = false;
      if (clearDraft) {
        _newCategoryController.clear();
      }
    });
  }

  bool _isSelfCategory(Category category) {
    return category.name.trim().toLowerCase() == 'self';
  }

  bool _isLoanDebtManagedCategory(Category category) {
    return isLoanDebtCategory(category) || isRepaymentCategory(category);
  }

  bool _isSelfCategoryId(int id) {
    final category = _provider.getCategoryById(id);
    if (category == null) return false;
    return _isSelfCategory(category);
  }

  bool _isLoanDebtManagedCategoryId(int id) {
    final category = _provider.getCategoryById(id);
    if (category == null) return false;
    return _isLoanDebtManagedCategory(category);
  }

  bool _canAutoCategorizeCategoryId(int id) {
    return !_isSelfCategoryId(id) && !_isLoanDebtManagedCategoryId(id);
  }

  bool _transactionHasRepaymentCategory(Transaction transaction) {
    return transaction.selectedCategoryIds.any((id) {
      final category = _provider.getCategoryById(id);
      return category != null && isRepaymentCategory(category);
    });
  }

  bool _isRepaymentCategoryId(int id) {
    final category = _provider.getCategoryById(id);
    return category != null && isRepaymentCategory(category);
  }

  List<int> _categoryIdsWithoutRepayment(Transaction transaction) {
    return transaction.selectedCategoryIds
        .where((id) => !_isRepaymentCategoryId(id))
        .toList(growable: false);
  }

  int? _primaryCategoryForIds(Transaction transaction, List<int> categoryIds) {
    if (categoryIds.isEmpty) return null;
    final currentPrimary = transaction.categoryId;
    if (currentPrimary != null && categoryIds.contains(currentPrimary)) {
      return currentPrimary;
    }
    return categoryIds.first;
  }

  Future<bool> _ensureRepaymentCandidateAvailable(String _) async {
    return true;
  }

  Future<bool> _removeUnlinkedRepaymentCategory(
    Transaction transaction,
  ) async {
    final nextCategoryIds = _categoryIdsWithoutRepayment(transaction);
    try {
      await LoanDebtRepository().deleteRepaymentForTransaction(
        transaction.reference,
      );
      final updated = await _provider.updateCategoriesForTransaction(
        transaction,
        categoryIds: nextCategoryIds,
        primaryCategoryId: _primaryCategoryForIds(transaction, nextCategoryIds),
      );
      if (mounted) {
        setState(() => _transaction = updated);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Transaction?> _applyCategorySelection({
    required List<int> categoryIds,
    int? primaryCategoryId,
  }) async {
    if (_isApplyingCategory) return null;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final shouldAutoCategorize = _autoCategorizeFutureTransactions;
    final previousTransaction = _tx;
    final hadRepaymentCategory =
        _transactionHasRepaymentCategory(previousTransaction);
    final hasLoanDebtManagedCategory =
        categoryIds.any(_isLoanDebtManagedCategoryId);
    final updateErrorMessage = context.l10nTextRead(
      'Could not update category. Changes were reverted.',
    );
    final repaymentCleanupErrorMessage = context.l10nTextRead(
      'Category was saved, but repayment link could not be removed.',
    );
    final hadExistingRules = _provider
        .autoCategorizationRulesForTransaction(previousTransaction)
        .isNotEmpty;
    _dismissComposerState(clearDraft: true);
    setState(() => _isApplyingCategory = true);

    try {
      final updated = await _provider.updateCategoriesForTransaction(
        previousTransaction,
        categoryIds: categoryIds,
        primaryCategoryId: primaryCategoryId,
      );
      final nextAutoCategoryIds = _nextAutoCategorizationDraftCategoryIds(
        previous: previousTransaction,
        updated: updated,
      );
      final shouldPersistAutoCategorization = shouldAutoCategorize &&
          nextAutoCategoryIds.isNotEmpty &&
          !hasLoanDebtManagedCategory;
      final removedRepaymentCategory =
          hadRepaymentCategory && !_transactionHasRepaymentCategory(updated);
      if (removedRepaymentCategory) {
        try {
          await LoanDebtRepository().deleteRepaymentForTransaction(
            updated.reference,
          );
        } catch (_) {
          if (mounted) {
            messenger?.showSnackBar(
              SnackBar(
                content: Text(repaymentCleanupErrorMessage),
              ),
            );
          }
        }
      }

      if (!mounted) return updated;
      setState(() {
        _transaction = updated;
        _autoCategorizeFutureTransactions = shouldPersistAutoCategorization;
        _autoCategorizationDraftCategoryIds = nextAutoCategoryIds;
      });

      try {
        await _persistAutoCategorizationDraft(
          hadExistingRules: hadExistingRules,
        );
      } catch (_) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Category was saved, but auto-categorization could not be updated.',
            ),
          ),
        );
      }
      return updated;
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(updateErrorMessage),
        ),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() => _isApplyingCategory = false);
      }
    }
  }

  Future<void> _toggleCategory(Category category) async {
    final categoryId = category.id;
    if (_isApplyingCategory || categoryId == null) return;

    final isSelected = _selectedCategoryIds.contains(categoryId);
    if (_isSelfCategory(category)) {
      await _applyCategorySelection(
        categoryIds: isSelected ? const <int>[] : <int>[categoryId],
        primaryCategoryId: isSelected ? null : categoryId,
      );
      return;
    }

    final nextIds = _selectedCategoryIds
        .where((id) => id != categoryId && !_isSelfCategoryId(id))
        .toList(growable: true);

    if (isSelected) {
      final nextPrimary = _tx.categoryId == categoryId
          ? (nextIds.isEmpty ? null : nextIds.first)
          : _tx.categoryId;
      await _applyCategorySelection(
        categoryIds: nextIds,
        primaryCategoryId: nextPrimary,
      );
      return;
    }

    if (isRepaymentCategory(category)) {
      final unavailableMessage = context.l10nTextRead(
        'Add an active loan or debt first, then link a repayment.',
      );
      final canSelectRepayment = await _ensureRepaymentCandidateAvailable(
        unavailableMessage,
      );
      if (!canSelectRepayment || !mounted) return;
      nextIds.removeWhere((id) {
        final existing = _provider.getCategoryById(id);
        return existing != null && isLoanDebtCategory(existing);
      });
    } else if (isLoanDebtCategory(category)) {
      nextIds.removeWhere((id) {
        final existing = _provider.getCategoryById(id);
        return existing != null && isRepaymentCategory(existing);
      });
    }

    nextIds.insert(0, categoryId);
    final updated = await _applyCategorySelection(
      categoryIds: nextIds,
      primaryCategoryId: categoryId,
    );
    if (updated == null || !mounted) return;
    if (isRepaymentCategory(category)) {
      await _openRepaymentLinkPrompt(updated);
    } else if (isLoanDebtCategory(category)) {
      await _openLoanDebtPersonPrompt(updated);
    }
  }

  Future<void> _clearCategory() async {
    await _applyCategorySelection(categoryIds: const <int>[]);
  }

  Future<void> _openLoanDebtPersonPrompt(Transaction transaction) async {
    final hostContext = widget.hostContext;
    _dismissComposerState(clearDraft: true);
    if (mounted) {
      Navigator.of(context).pop();
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!hostContext.mounted) return;
    final saved = await showLoanDebtPersonSheet(
      context: hostContext,
      transaction: transaction,
    );
    if (saved) {
      unawaited(_provider.loadData());
    }
  }

  Future<void> _openRepaymentLinkPrompt(Transaction transaction) async {
    final hostContext = widget.hostContext;
    final rollbackMessage = context.l10nTextRead(
      'Repayment was not linked, so the category was removed.',
    );
    final rollbackErrorMessage = context.l10nTextRead(
      'Could not remove the unlinked repayment category.',
    );
    _dismissComposerState(clearDraft: true);
    if (mounted) {
      Navigator.of(context).pop();
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!hostContext.mounted) return;
    final saved = await showRepaymentLinkSheet(
      context: hostContext,
      transaction: transaction,
    );
    if (saved) {
      unawaited(_provider.loadData());
      return;
    }
    final removed = await _removeUnlinkedRepaymentCategory(transaction);
    if (!hostContext.mounted) return;
    ScaffoldMessenger.maybeOf(hostContext)?.showSnackBar(
      SnackBar(
        content: Text(removed ? rollbackMessage : rollbackErrorMessage),
      ),
    );
    if (removed) {
      unawaited(_provider.loadData());
    }
  }

  void _toggleNewCategoryForm() {
    final shouldShow = !_showNewCategoryForm;
    setState(() {
      _showNewCategoryForm = shouldShow;
      _showColorChoices = false;
      if (!shouldShow) {
        _newCategoryController.clear();
      }
    });
    if (!shouldShow) {
      _newCategoryFocus.unfocus();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _newCategoryFocus.requestFocus();
      _scrollComposerIntoView();
    });
  }

  void _toggleColorChoices() {
    final willOpen = !_showColorChoices;
    setState(() => _showColorChoices = willOpen);
    if (!willOpen) return;
    _scrollComposerIntoView();
  }

  void _scrollComposerIntoView() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheetScrollController.hasClients) return;
      final target = _sheetScrollController.position.maxScrollExtent;
      _sheetScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Category? _findCategoryByNameAndFlow({
    required String name,
    required String flow,
    Set<int>? excludeIds,
  }) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedFlow = flow.toLowerCase();
    return _provider.categories
        .where((category) =>
            category.flow.toLowerCase() == normalizedFlow &&
            category.name.trim().toLowerCase() == normalizedName &&
            (category.id == null ||
                !(excludeIds?.contains(category.id) ?? false)))
        .fold<Category?>(
          null,
          (best, category) =>
              best == null || (category.id ?? 0) > (best.id ?? 0)
                  ? category
                  : best,
        );
  }

  bool _categoryExistsForFlow({
    required String name,
    required String flow,
  }) {
    return _findCategoryByNameAndFlow(name: name, flow: flow) != null;
  }

  String? _extractColorKey(String? iconKey) {
    if (iconKey == null || iconKey.isEmpty) return null;
    const prefix = 'color:';
    if (!iconKey.startsWith(prefix)) return null;
    final value = iconKey.substring(prefix.length).trim();
    if (value.isEmpty) return null;
    return value;
  }

  Color _colorFromKey(String colorKey) {
    for (final option in _kCategoryColorOptions) {
      if (option.key == colorKey) return option.color;
    }
    return _kCategoryColorOptions.first.color;
  }

  int _fallbackColorIndex(Category category) {
    final seed = '${category.flow}:${category.name.toLowerCase()}';
    int hash = 0;
    for (final code in seed.codeUnits) {
      hash = (hash + code) & 0x7fffffff;
    }
    return hash % _kCategoryColorOptions.length;
  }

  Future<void> _setSelfCategory() async {
    const selfName = 'Self';
    final flow = _isCredit ? 'income' : 'expense';
    final existing = _findCategoryByNameAndFlow(name: selfName, flow: flow);
    if (existing != null) {
      await _applyCategorySelection(
        categoryIds: existing.id == null ? const <int>[] : <int>[existing.id!],
        primaryCategoryId: existing.id,
      );
      return;
    }

    final knownCategoryIds = _provider.categories
        .map((category) => category.id)
        .whereType<int>()
        .toSet();

    try {
      await _provider.createCategory(
        name: selfName,
        essential: false,
        flow: flow,
        colorKey: 'gray',
      );
    } catch (_) {
      if (!mounted) return;
    }

    final created = _findCategoryByNameAndFlow(
      name: selfName,
      flow: flow,
      excludeIds: knownCategoryIds,
    );
    final target =
        created ?? _findCategoryByNameAndFlow(name: selfName, flow: flow);
    if (target != null) {
      await _applyCategorySelection(
        categoryIds: target.id == null ? const <int>[] : <int>[target.id!],
        primaryCategoryId: target.id,
      );
    }
  }

  Future<void> _createNewCategoryInline() async {
    final createdName = _newCategoryController.text.trim();
    if (createdName.isEmpty) return;
    final flow = _isCredit ? 'income' : 'expense';
    if (_categoryExistsForFlow(name: createdName, flow: flow)) {
      _newCategoryFocus.requestFocus();
      return;
    }
    final knownCategoryIds = _provider.categories
        .map((category) => category.id)
        .whereType<int>()
        .toSet();
    try {
      await _provider.createCategory(
        name: createdName,
        essential: false,
        flow: flow,
        colorKey: _draftColorKey,
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().toLowerCase();
      if (message.contains('unique') ||
          message.contains('constraint') ||
          message.contains('already exists')) {
        _newCategoryFocus.requestFocus();
        setState(() {});
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.l10nTextRead('Could not create category'))),
      );
      return;
    }
    if (!mounted) return;
    final createdCategory = _findCategoryByNameAndFlow(
      name: createdName,
      flow: flow,
      excludeIds: knownCategoryIds,
    );
    if (createdCategory != null) {
      await _toggleCategory(createdCategory);
      return;
    }
    setState(() {
      _showNewCategoryForm = false;
      _showColorChoices = false;
      _newCategoryController.clear();
    });
    _newCategoryFocus.unfocus();
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    _newCategoryFocus.dispose();
    _sheetScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentCategoryLabel = context.l10nText(
      _provider.categoryLabelForTransaction(
        _tx,
        uncategorizedLabel: 'Categorize',
      ),
    );
    final categoriesTitle = context.l10nText('Categories');
    final isLockedSelfTransfer = _provider.isDetectedSelfTransfer(_tx);
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final keyboardScrollBuffer = keyboardInset > 0 ? 88.0 : 24.0;
    final maxSheetHeight = mediaQuery.size.height *
        (_showNewCategoryForm || _showColorChoices ? 0.76 : 0.62);
    if (keyboardInset > _lastKeyboardInset && _showNewCategoryForm) {
      _scrollComposerIntoView();
    }
    _lastKeyboardInset = keyboardInset;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedCategoryIds.isEmpty
                            ? categoriesTitle
                            : '$categoriesTitle · $currentCategoryLabel',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(AppIcons.close, size: 20),
                      color: AppColors.textSecondary(context),
                      onPressed: _isApplyingCategory
                          ? null
                          : () {
                              _dismissComposerState();
                              Navigator.pop(context);
                            },
                    ),
                  ],
                ),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  controller: _sheetScrollController,
                  padding: EdgeInsets.fromLTRB(20, 0, 20, keyboardScrollBuffer),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCategoryPicker(
                        isLockedSelfTransfer: isLockedSelfTransfer,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryPicker({
    required bool isLockedSelfTransfer,
  }) {
    final categories = _availableCategories;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_canShowAutoCategorizationOption) ...[
            _buildAutoCategorizationCheckbox(),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isLockedSelfTransfer)
                ...categories.map((category) {
                  final isSelected = category.id != null &&
                      _selectedCategoryIds.contains(category.id);
                  final isRepaymentDisabled = isRepaymentCategory(category) &&
                      !isSelected &&
                      !_canSelectRepaymentCategory;
                  return _CategoryPickerChip(
                    label: category.name,
                    color: _categoryColor(category),
                    isSelected: isSelected,
                    onTap: _isApplyingCategory || isRepaymentDisabled
                        ? null
                        : () => _toggleCategory(category),
                  );
                }),
              _CategoryPickerChip(
                label: 'Self',
                color: _colorFromKey('gray'),
                isSelected: isLockedSelfTransfer ||
                    _currentCategories.any(_isSelfCategory),
                showColorDot: false,
                onTap: isLockedSelfTransfer || _isApplyingCategory
                    ? null
                    : _setSelfCategory,
              ),
              if (!isLockedSelfTransfer)
                _CategoryPickerChip(
                  label: _showNewCategoryForm ? 'Cancel' : '+ New',
                  color: _showNewCategoryForm
                      ? AppColors.red
                      : AppColors.textSecondary(context),
                  isSelected: false,
                  isRemove: _showNewCategoryForm,
                  showColorDot: false,
                  onTap: _isApplyingCategory ? null : _toggleNewCategoryForm,
                ),
              if (!isLockedSelfTransfer && _selectedCategoryIds.isNotEmpty)
                _CategoryPickerChip(
                  label: 'Clear',
                  color: AppColors.red,
                  isSelected: false,
                  isRemove: true,
                  showColorDot: false,
                  onTap: _isApplyingCategory ? null : _clearCategory,
                ),
            ],
          ),
          if (!isLockedSelfTransfer && _shouldShowRepaymentUnavailableHint) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  AppIcons.info_outline_rounded,
                  size: 14,
                  color: AppColors.textTertiary(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.l10nText(
                      'Repayment needs an active linked loan or debt first.',
                    ),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ],
          if (!isLockedSelfTransfer && _showNewCategoryForm)
            _buildNewCategoryComposer(),
        ],
      ),
    );
  }

  Widget _buildAutoCategorizationCheckbox() {
    final counterparty = _autoCategorizationCounterparty;
    if (counterparty == null) return const SizedBox.shrink();

    final isChecked = _autoCategorizeFutureTransactions;
    const activeColor = AppColors.primaryLight;
    final borderColor =
        isChecked ? activeColor : AppColors.borderColor(context);

    return InkWell(
      onTap: _isApplyingCategory ? null : () => _toggleAutoCategorization(),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isChecked ? activeColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isChecked
                          ? activeColor
                          : AppColors.borderColor(context),
                      width: 1.4,
                    ),
                  ),
                  child: isChecked
                      ? const Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10nText(
                          'Auto-categorize future transactions',
                        ),
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        counterparty,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isChecked && _autoCategorizationDraftCategories.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                context.l10nText(
                  'Dismiss categories you do not want to remember',
                ),
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _autoCategorizationDraftCategories
                    .map(
                      (category) => _CategoryPickerChip(
                        label: category.name,
                        color: _categoryColor(category),
                        isSelected: true,
                        onTap: () =>
                            _dismissAutoCategorizationCategory(category),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNewCategoryComposer() {
    final selectedColor = _colorFromKey(_draftColorKey);
    final flow = _isCredit ? 'income' : 'expense';
    final draftName = _newCategoryController.text.trim();
    final isDuplicateName = draftName.isNotEmpty &&
        _categoryExistsForFlow(name: draftName, flow: flow);
    final canSubmit = draftName.isNotEmpty && !isDuplicateName;
    final textFieldBorderColor =
        isDuplicateName ? AppColors.red : AppColors.borderColor(context);
    final focusedBorderColor =
        isDuplicateName ? AppColors.red : AppColors.primaryLight;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newCategoryController,
                  focusNode: _newCategoryFocus,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _createNewCategoryInline(),
                  onTapOutside: (_) => _newCategoryFocus.unfocus(),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: context.l10nText('Category name'),
                    hintStyle:
                        TextStyle(color: AppColors.textTertiary(context)),
                    filled: true,
                    fillColor: AppColors.surfaceColor(context),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: textFieldBorderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: textFieldBorderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: focusedBorderColor,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleColorChoices,
                child: Container(
                  height: 40,
                  width: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: selectedColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Icon(
                        _showColorChoices
                            ? AppIcons.keyboard_arrow_up
                            : AppIcons.keyboard_arrow_down,
                        size: 16,
                        color: AppColors.textSecondary(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: canSubmit ? _createNewCategoryInline : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    context.l10nText('Add'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if (_showColorChoices) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _kCategoryColorOptions.map((option) {
                    final selected = option.key == _draftColorKey;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _draftColorKey = option.key;
                            _showColorChoices = false;
                          });
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: option.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? AppColors.textPrimary(context)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _categoryColor(Category category) {
    final explicitKey = _normalizeColorKey(category.colorKey) ??
        _extractColorKey(category.iconKey);
    if (explicitKey != null) {
      return _colorFromKey(explicitKey);
    }
    return _kCategoryColorOptions[_fallbackColorIndex(category)].color;
  }

  String? _normalizeColorKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

class _CategoryColorOption {
  final String key;
  final Color color;

  const _CategoryColorOption({
    required this.key,
    required this.color,
  });
}

const List<_CategoryColorOption> _kCategoryColorOptions = [
  _CategoryColorOption(key: 'blue', color: AppColors.blue),
  _CategoryColorOption(key: 'emerald', color: AppColors.incomeSuccess),
  _CategoryColorOption(key: 'amber', color: AppColors.amber),
  _CategoryColorOption(key: 'red', color: AppColors.red),
  _CategoryColorOption(key: 'rose', color: Color(0xFFFB7185)),
  _CategoryColorOption(key: 'magenta', color: Color(0xFFD946EF)),
  _CategoryColorOption(key: 'violet', color: Color(0xFF8B5CF6)),
  _CategoryColorOption(key: 'indigo', color: Color(0xFF6366F1)),
  _CategoryColorOption(key: 'teal', color: Color(0xFF14B8A6)),
  _CategoryColorOption(key: 'mint', color: Color(0xFF34D399)),
  _CategoryColorOption(key: 'orange', color: Color(0xFFF97316)),
  _CategoryColorOption(key: 'tangerine', color: Color(0xFFFF8C42)),
  _CategoryColorOption(key: 'yellow', color: Color(0xFFEAB308)),
  _CategoryColorOption(key: 'cyan', color: Color(0xFF06B6D4)),
  _CategoryColorOption(key: 'sky', color: Color(0xFF0EA5E9)),
  _CategoryColorOption(key: 'lime', color: Color(0xFF84CC16)),
  _CategoryColorOption(key: 'pink', color: Color(0xFFEC4899)),
  _CategoryColorOption(key: 'brown', color: Color(0xFFA16207)),
  _CategoryColorOption(key: 'gray', color: Color(0xFF6B7280)),
];

class _CategoryPickerChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final bool isRemove;
  final bool showColorDot;
  final VoidCallback? onTap;

  const _CategoryPickerChip({
    required this.label,
    required this.color,
    required this.isSelected,
    this.isRemove = false,
    this.showColorDot = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        isSelected ? color.withValues(alpha: 0.15) : Colors.transparent;
    final borderColor = isSelected ? color : AppColors.borderColor(context);
    final isEnabled = onTap != null;
    final textColor = !isEnabled
        ? AppColors.textTertiary(context)
        : (isRemove ? AppColors.red : AppColors.textPrimary(context));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showColorDot) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isEnabled ? color : color.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                context.l10nText(label),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
