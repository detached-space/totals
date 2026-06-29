import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/loan_debt_repository.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/utils/app_date_format.dart';
import 'package:totals/utils/loan_debt_utils.dart';
import 'package:totals/utils/category_sort.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/utils/transaction_link_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/_redesign/screens/loans_page.dart';
import 'package:totals/_redesign/screens/shared_expenses_page.dart';
import 'package:totals/theme/app_calendar_option.dart';
import 'package:totals/l10n/app_localizations.dart';

/// Shows the transaction details bottom sheet matching the redesign style.
Future<void> showTransactionDetailsSheet({
  required BuildContext context,
  required Transaction transaction,
  required TransactionProvider provider,
  bool initiallyExpandCategory = false,
  bool showQuickAccessCategories = false,
  bool allowAutoCategorizationRuleUpdates = true,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final hostContext = context;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TransactionDetailsSheet(
      hostContext: hostContext,
      transaction: transaction,
      provider: provider,
      initiallyExpandCategory: initiallyExpandCategory,
      showQuickAccessCategories: showQuickAccessCategories,
      allowAutoCategorizationRuleUpdates: allowAutoCategorizationRuleUpdates,
    ),
  );
}

class _TransactionDetailsSheet extends StatefulWidget {
  final BuildContext hostContext;
  final Transaction transaction;
  final TransactionProvider provider;
  final bool initiallyExpandCategory;
  final bool showQuickAccessCategories;
  final bool allowAutoCategorizationRuleUpdates;

  const _TransactionDetailsSheet({
    required this.hostContext,
    required this.transaction,
    required this.provider,
    this.initiallyExpandCategory = false,
    this.showQuickAccessCategories = false,
    this.allowAutoCategorizationRuleUpdates = true,
  });

  @override
  State<_TransactionDetailsSheet> createState() =>
      _TransactionDetailsSheetState();
}

class _TransactionDetailsSheetState extends State<_TransactionDetailsSheet> {
  bool _categoryExpanded = false;
  bool _isSavingCounterparty = false;
  bool _isSavingNote = false;
  bool _isApplyingCategory = false;
  bool _showNewCategoryForm = false;
  bool _showColorChoices = false;
  bool _autoCategorizeFutureTransactions = false;
  String _draftColorKey = _kCategoryColorOptions.first.key;
  List<int> _quickCategoryIds = const [];
  List<int> _autoCategorizationDraftCategoryIds = const [];
  late Transaction _transaction;
  final TextEditingController _counterpartyController = TextEditingController();
  final FocusNode _counterpartyFocus = FocusNode();
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteFocus = FocusNode();
  final TextEditingController _newCategoryController = TextEditingController();
  final FocusNode _newCategoryFocus = FocusNode();
  final ScrollController _sheetScrollController = ScrollController();
  double _lastKeyboardInset = 0;

  Transaction get _tx => _transaction;
  TransactionProvider get _provider => widget.provider;

  bool get _isCredit => _tx.type == 'CREDIT';
  bool get _canShowSplitWithGroup =>
      widget.hostContext.mounted &&
      _tx.reference.trim().isNotEmpty &&
      _tx.type?.toUpperCase() == 'DEBIT';
  bool get _isAlreadySharedExpense => _provider.isSharedExpenseTransaction(_tx);
  bool get _isSharingSharedExpense =>
      _provider.isSharingSharedExpenseTransaction(_tx);
  bool get _canSplitWithGroup =>
      _canShowSplitWithGroup &&
      !_isAlreadySharedExpense &&
      !_isSharingSharedExpense;
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
    _categoryExpanded = widget.initiallyExpandCategory;
    _transaction = widget.transaction;
    _syncAutoCategorizationCheckbox();
    _counterpartyController.text = _storedCounterpartyValue ?? '';
    _counterpartyFocus.addListener(_handleCounterpartyFocusChange);
    _noteController.text = _tx.note?.trim() ?? '';
    _noteFocus.addListener(_handleNoteFocusChange);
    if (widget.showQuickAccessCategories) {
      _loadQuickCategoryIds();
    }
  }

  String get _counterparty {
    final receiver = _tx.receiver?.trim();
    final creditor = _tx.creditor?.trim();
    if (receiver != null && receiver.isNotEmpty) return receiver;
    if (creditor != null && creditor.isNotEmpty) return creditor;
    if (_provider.isSelfTransfer(_tx)) return 'You';
    return _bankFullName;
  }

  String? get _storedCounterpartyValue {
    final receiver = _tx.receiver?.trim();
    final creditor = _tx.creditor?.trim();
    if (_isCredit) {
      if (creditor != null && creditor.isNotEmpty) return creditor;
      if (receiver != null && receiver.isNotEmpty) return receiver;
      return null;
    }
    if (receiver != null && receiver.isNotEmpty) return receiver;
    if (creditor != null && creditor.isNotEmpty) return creditor;
    return null;
  }

  String get _counterpartyRole => _isCredit ? 'sender' : 'recipient';

  String get _bankFullName {
    return context.l10nText(_provider.getBankName(_tx.bankId));
  }

  String get _bankShortName {
    return context.l10nText(_provider.getBankShortName(_tx.bankId));
  }

  String get _formattedAmount {
    final formatted = formatNumberWithComma(_tx.amount);
    final prefix = _isCredit ? '+ ' : '- ';
    return '${prefix}ETB $formatted';
  }

  String? get _formattedDate {
    final dt = _parseTime(_tx.time);
    if (dt == null) return null;

    final isEC = context.read<ThemeProvider>().appCalendar ==
        AppCalendarOption.ethiopian;

    if (isEC) {
      final timeStr = AppDateFormat.ethiopianTime(dt, context: context);

      return '${AppDateFormat.monthDayMaybeYear(dt, context: context)} · $timeStr';
    } else {
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final amPm = hour >= 12 ? 'PM' : 'AM';
      final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      final timeStr = '$h12:$minute $amPm';
      return '${AppDateFormat.monthDayMaybeYear(dt, context: context)} · $timeStr';
    }
  }

  String? get _formattedBalance {
    final raw = _tx.currentBalance;
    if (raw == null || raw.isEmpty) return null;
    final parsed = double.tryParse(raw);
    if (parsed == null) return raw;
    return 'ETB ${formatNumberAbbreviated(parsed).replaceAll('k', 'K')}';
  }

  String? get _formattedServiceCharge {
    final sc = _tx.serviceCharge;
    if (sc == null || sc == 0) return null;
    return 'ETB ${formatNumberWithComma(sc)}';
  }

  String? get _formattedVat {
    final v = _tx.vat;
    if (v == null || v == 0) return null;
    return 'ETB ${formatNumberWithComma(v)}';
  }

  DateTime? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  Category? get _currentCategory => _provider.getCategoryById(_tx.categoryId);
  List<Category> get _currentCategories =>
      _provider.categoriesForTransaction(_tx);
  List<int> get _selectedCategoryIds => _tx.selectedCategoryIds;

  String? get _noteText {
    final note = _tx.note?.trim();
    if (note == null || note.isEmpty) return null;
    return note;
  }

  List<Category> get _availableCategories {
    final desiredFlow = _isCredit ? 'income' : 'expense';
    final filtered = _provider.categories
        .where((c) => c.flow.toLowerCase() == desiredFlow)
        .toList(growable: false);
    final base = filtered.isEmpty ? _provider.categories : filtered;
    return sortCategoriesAlphabetically(
      base.where((c) => c.name.trim().toLowerCase() != 'self'),
    );
  }

  List<Category> get _quickAccessCategories {
    if (!widget.showQuickAccessCategories || _quickCategoryIds.isEmpty) {
      return const [];
    }

    final categoriesById = <int, Category>{};
    for (final category in _availableCategories) {
      final id = category.id;
      if (id != null) {
        categoriesById[id] = category;
      }
    }

    final result = <Category>[];
    for (final id in _quickCategoryIds) {
      final category = categoriesById[id];
      if (category != null) {
        result.add(category);
      }
    }
    return result;
  }

  List<Category> get _remainingCategories {
    final quickIds = _quickAccessCategories
        .map((category) => category.id)
        .whereType<int>()
        .toSet();
    if (quickIds.isEmpty) return _availableCategories;
    return _availableCategories
        .where((category) =>
            category.id == null || !quickIds.contains(category.id))
        .toList(growable: false);
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
    final hadExistingRules =
        _provider.autoCategorizationRulesForTransaction(_tx).isNotEmpty;
    final previousEnabled = _autoCategorizeFutureTransactions;
    final previousDraftIds =
        List<int>.from(_autoCategorizationDraftCategoryIds);
    final revertedMessage = context.l10nTextRead(
      'Could not update auto-categorization. Changes were reverted.',
    );
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
          content: Text(revertedMessage),
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
    final hadExistingRules =
        _provider.autoCategorizationRulesForTransaction(_tx).isNotEmpty;
    final previousEnabled = _autoCategorizeFutureTransactions;
    final previousDraftIds =
        List<int>.from(_autoCategorizationDraftCategoryIds);
    final revertedMessage = context.l10nTextRead(
      'Could not update auto-categorization. Changes were reverted.',
    );
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
          content: Text(revertedMessage),
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

  Future<void> _loadQuickCategoryIds() async {
    final settings = NotificationSettingsService.instance;
    final ids = _isCredit
        ? await settings.getQuickCategorizeIncomeIds()
        : await settings.getQuickCategorizeExpenseIds();
    if (!mounted) return;
    setState(() {
      _quickCategoryIds = ids;
    });
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
    final hadExistingRules = _provider
        .autoCategorizationRulesForTransaction(previousTransaction)
        .isNotEmpty;
    final revertedMessage = context.l10nTextRead(
      'Could not update category. Changes were reverted.',
    );
    final repaymentCleanupErrorMessage = context.l10nTextRead(
      'Category was saved, but repayment link could not be removed.',
    );
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
          content: Text(revertedMessage),
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

  void _copyReference({String message = 'Reference copied'}) {
    Clipboard.setData(ClipboardData(text: _tx.reference));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleReferenceTap() async {
    final link = TransactionLinkUtils.resolveReferenceLink(_tx);
    if (link == null) {
      _copyReference();
      return;
    }

    final uri = Uri.tryParse(link);
    if (uri == null) {
      _copyReference();
      return;
    }

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {}

    try {
      final opened = await launchUrl(uri);
      if (opened) return;
    } catch (_) {}

    if (!mounted) return;
    _copyReference(
      message: 'Could not open receipt link. Reference copied instead',
    );
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
    _noteFocus.unfocus();
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

  void _handleNoteFocusChange() {
    if (_noteFocus.hasFocus) {
      _scrollComposerIntoView();
      return;
    }
    _saveNote();
  }

  void _handleCounterpartyFocusChange() {
    if (_counterpartyFocus.hasFocus) return;
    _saveCounterparty();
  }

  Transaction _copyTransactionWithCounterparty(String? counterparty) {
    final normalizedCounterparty = counterparty?.trim();
    final updatedValue =
        normalizedCounterparty == null || normalizedCounterparty.isEmpty
            ? null
            : normalizedCounterparty;
    return Transaction(
      amount: _tx.amount,
      reference: _tx.reference,
      creditor: _isCredit ? updatedValue : _tx.creditor,
      receiver: _isCredit ? _tx.receiver : updatedValue,
      note: _tx.note,
      time: _tx.time,
      status: _tx.status,
      currentBalance: _tx.currentBalance,
      bankId: _tx.bankId,
      type: _tx.type,
      transactionLink: _tx.transactionLink,
      accountNumber: _tx.accountNumber,
      categoryId: _tx.categoryId,
      categoryIds: _tx.categoryIds,
      profileId: _tx.profileId,
      serviceCharge: _tx.serviceCharge,
      vat: _tx.vat,
      sourceType: _tx.sourceType,
      sourceMessageId: _tx.sourceMessageId,
      sourceFingerprint: _tx.sourceFingerprint,
    );
  }

  Future<void> _saveCounterparty() async {
    if (_isSavingCounterparty) return;

    final trimmed = _counterpartyController.text.trim();
    final normalized = trimmed.isEmpty ? null : trimmed;
    final current = _storedCounterpartyValue;

    if (normalized == current) return;

    final updated = _copyTransactionWithCounterparty(normalized);

    setState(() => _isSavingCounterparty = true);

    try {
      await _provider.updateCounterpartyForTransaction(_tx, normalized);
      if (!mounted) return;
      setState(() {
        _transaction = updated;
        _counterpartyController.text = _storedCounterpartyValue ?? '';
        _syncAutoCategorizationCheckbox();
        _isSavingCounterparty = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSavingCounterparty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10nTextRead('Could not save')} $_counterpartyRole',
          ),
        ),
      );
    }
  }

  Future<void> _saveNote() async {
    if (_isSavingNote) return;

    final trimmed = _noteController.text.trim();
    final normalized = trimmed.isEmpty ? null : trimmed;
    final current = _noteText;

    if (normalized == current) return;

    final updated = normalized == null
        ? _tx.copyWith(clearNote: true)
        : _tx.copyWith(note: normalized);

    setState(() => _isSavingNote = true);

    try {
      await _provider.updateNoteForTransaction(_tx, normalized);
      if (!mounted) return;
      setState(() {
        _transaction = updated;
        _noteController.text = updated.note ?? '';
        _isSavingNote = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSavingNote = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10nTextRead('Could not save note'))),
      );
    }
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
        .where((c) =>
            c.flow.toLowerCase() == normalizedFlow &&
            c.name.trim().toLowerCase() == normalizedName &&
            (c.id == null || !(excludeIds?.contains(c.id) ?? false)))
        .fold<Category?>(
          null,
          (best, c) => best == null || (c.id ?? 0) > (best.id ?? 0) ? c : best,
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

    final knownCategoryIds =
        _provider.categories.map((c) => c.id).whereType<int>().toSet();

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
    final knownCategoryIds =
        _provider.categories.map((c) => c.id).whereType<int>().toSet();
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

  Future<void> _deleteTransaction() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10nText('Delete transaction?')),
        content: Text(
          ctx.l10nText(
            'This will permanently remove this transaction. This cannot be undone.',
          ),
        ),
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
    if (confirmed == true && mounted) {
      Navigator.pop(context);
      await _provider.deleteTransactionsByReferences([_tx.reference]);
    }
  }

  Future<void> _splitWithGroup() async {
    final hostContext = widget.hostContext;
    final transaction = _tx;
    _dismissComposerState();
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!hostContext.mounted) return;
    final didSplit = await showSplitTransactionWithGroupFlow(
      context: hostContext,
      transaction: transaction,
    );
    if (didSplit) {
      unawaited(_provider.loadData());
    }
  }

  Future<void> _openLoanDebtPersonPrompt(Transaction transaction) async {
    final hostContext = widget.hostContext;
    _dismissComposerState(clearDraft: true);
    Navigator.of(context).pop();
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
    Navigator.of(context).pop();
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

  @override
  void dispose() {
    _counterpartyFocus.removeListener(_handleCounterpartyFocusChange);
    _counterpartyController.dispose();
    _counterpartyFocus.dispose();
    _noteFocus.removeListener(_handleNoteFocusChange);
    _noteController.dispose();
    _noteFocus.dispose();
    _newCategoryController.dispose();
    _newCategoryFocus.dispose();
    _sheetScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = _currentCategory;
    final isLockedSelfTransfer = _provider.isDetectedSelfTransfer(_tx);
    final selfTransferLabel = _provider.getSelfTransferLabel(_tx);
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardScrollBuffer = keyboardInset > 0 ? 88.0 : 24.0;
    if (keyboardInset > _lastKeyboardInset &&
        (_showNewCategoryForm ||
            _noteFocus.hasFocus ||
            _counterpartyFocus.hasFocus)) {
      _scrollComposerIntoView();
    }
    _lastKeyboardInset = keyboardInset;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
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

              // Header row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10nText('Transaction Details'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(AppIcons.close, size: 20),
                      color: AppColors.textSecondary(context),
                      onPressed: () {
                        _dismissComposerState();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),

              // Amount
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  _formattedAmount,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _isCredit ? AppColors.incomeSuccess : AppColors.red,
                  ),
                ),
              ),

              // Counterparty name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: !_provider.isSelfTransfer(_tx)
                      ? TextField(
                          controller: _counterpartyController,
                          focusNode: _counterpartyFocus,
                          enabled: !_isSavingCounterparty,
                          textAlign: TextAlign.center,
                          textInputAction: TextInputAction.done,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary(context),
                          ),
                          onSubmitted: (_) {
                            FocusManager.instance.primaryFocus?.unfocus();
                          },
                          onTapOutside: (_) {
                            FocusManager.instance.primaryFocus?.unfocus();
                          },
                          decoration: InputDecoration(
                            hintText:
                                '${context.l10nText('Tap to add')} $_counterpartyRole',
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary(context),
                            ),
                            isCollapsed: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                          ),
                        )
                      : _MarqueeText(
                          text: _counterparty,
                          centerWhenStatic: true,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // Scrollable detail rows + category + delete
              Flexible(
                child: SingleChildScrollView(
                  controller: _sheetScrollController,
                  padding: EdgeInsets.fromLTRB(20, 0, 20, keyboardScrollBuffer),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DetailRow(
                        label: 'Reference',
                        value: _tx.reference,
                        marquee: true,
                        onTap: () {
                          unawaited(_handleReferenceTap());
                        },
                      ),
                      _DetailRow(label: 'Bank', value: _bankShortName),
                      // if (_tx.accountNumber != null &&
                      //     _tx.accountNumber!.isNotEmpty)
                      //   _DetailRow(label: 'Account', value: _tx.accountNumber!),
                      if (_formattedDate != null)
                        _DetailRow(
                            label: 'Date & Time', value: _formattedDate!),
                      if (_formattedBalance != null)
                        _DetailRow(
                            label: 'Balance After', value: _formattedBalance!),
                      if (_formattedServiceCharge != null)
                        _DetailRow(
                            label: 'Service Charge',
                            value: _formattedServiceCharge!),
                      if (_formattedVat != null)
                        _DetailRow(label: 'VAT', value: _formattedVat!),

                      // Category row
                      if (isLockedSelfTransfer)
                        _DetailRow(
                          label: 'Category',
                          value: context
                              .l10nText(selfTransferLabel ?? 'Self transfer'),
                        )
                      else
                        _buildCategoryRow(category),

                      // Category picker chips
                      if (_categoryExpanded && !isLockedSelfTransfer)
                        _buildCategoryPicker(),

                      _buildNoteSection(),

                      const SizedBox(height: 20),

                      if (_canShowSplitWithGroup) ...[
                        _buildSplitWithGroupButton(),
                        const SizedBox(height: 10),
                      ],

                      // Delete button
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _deleteTransaction,
                          label: Text(context.l10nText('Delete transaction')),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.red,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: AppColors.red.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 0),
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

  Widget _buildSplitWithGroupButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _canSplitWithGroup ? _splitWithGroup : null,
        icon: const Icon(AppIcons.group_outlined, size: 18),
        label: Text(
          context.l10nText(
            _isSharingSharedExpense ? 'Sharing' : 'Split with group',
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: AppColors.white,
          disabledBackgroundColor:
              AppColors.textTertiary(context).withValues(alpha: 0.16),
          disabledForegroundColor: AppColors.textSecondary(context),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildNoteSection() {
    final theme = Theme.of(context);
    final valueColumnWidth =
        (MediaQuery.of(context).size.width * 0.3).clamp(96.0, 120.0);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderColor(context), width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _kLabelWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                context.l10nText('Reason'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: valueColumnWidth,
            child: TextField(
              controller: _noteController,
              focusNode: _noteFocus,
              enabled: !_isSavingNote,
              maxLines: 1,
              textAlign: TextAlign.start,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w500,
              ),
              onTap: _scrollComposerIntoView,
              onSubmitted: (_) {
                FocusManager.instance.primaryFocus?.unfocus();
              },
              onTapOutside: (_) {
                FocusManager.instance.primaryFocus?.unfocus();
              },
              decoration: InputDecoration(
                hintText: context.l10nText('Add a note..'),
                hintStyle: TextStyle(color: AppColors.textTertiary(context)),
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(Category? category) {
    final theme = Theme.of(context);
    final valueColumnWidth =
        (MediaQuery.of(context).size.width * 0.3).clamp(96.0, 120.0);
    final categoryLabel = context.l10nText(
      _provider.categoryLabelForTransaction(
        _tx,
        uncategorizedLabel: 'Categorize',
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: AppColors.borderColor(context), width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _kLabelWidth,
            child: Text(
              context.l10nText('Categories'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: valueColumnWidth,
            child: GestureDetector(
              onTap: _isApplyingCategory
                  ? null
                  : () {
                      _noteFocus.unfocus();
                      setState(() {
                        _categoryExpanded = !_categoryExpanded;
                      });
                    },
              child: Row(
                children: [
                  if (category != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _categoryColor(category),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        categoryLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _categoryColor(category),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Text(
                        context.l10nText('Categorize'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textTertiary(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    _categoryExpanded
                        ? AppIcons.keyboard_arrow_up
                        : AppIcons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.textTertiary(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPicker() {
    final quickCategories = _quickAccessCategories;
    final categories = _remainingCategories;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_canShowAutoCategorizationOption) ...[
            _buildAutoCategorizationCheckbox(),
            const SizedBox(height: 12),
          ],
          if (quickCategories.isNotEmpty) ...[
            _buildCategorySectionLabel('Quick Access'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...quickCategories.map((category) {
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
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (categories.isNotEmpty && quickCategories.isNotEmpty) ...[
            _buildCategorySectionLabel('All Categories'),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...categories.map((c) {
                final isSelected =
                    c.id != null && _selectedCategoryIds.contains(c.id);
                final isRepaymentDisabled = isRepaymentCategory(c) &&
                    !isSelected &&
                    !_canSelectRepaymentCategory;
                return _CategoryPickerChip(
                  label: c.name,
                  color: _categoryColor(c),
                  isSelected: isSelected,
                  onTap: _isApplyingCategory || isRepaymentDisabled
                      ? null
                      : () => _toggleCategory(c),
                );
              }),
            ],
          ),
          if (_shouldShowRepaymentUnavailableHint) ...[
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CategoryPickerChip(
                label: 'Self',
                color: _colorFromKey('gray'),
                isSelected: _currentCategories.any(_isSelfCategory),
                showColorDot: false,
                onTap: _isApplyingCategory ? null : _setSelfCategory,
              ),
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
              if (_selectedCategoryIds.isNotEmpty)
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
          if (_showNewCategoryForm) _buildNewCategoryComposer(),
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

  Widget _buildCategorySectionLabel(String label) {
    return Text(
      context.l10nText(label),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
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

// ── Constants ───────────────────────────────────────────────────────────────

const double _kLabelWidth = 110;

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

// ── Detail row ──────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool marquee;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.label,
    required this.value,
    this.marquee = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textPrimary(context),
      fontWeight: FontWeight.w600,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: AppColors.borderColor(context), width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _kLabelWidth,
            child: Text(
              context.l10nText(label),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          const Spacer(),
          if (marquee)
            Flexible(
              child: GestureDetector(
                onTap: onTap,
                child: _MarqueeText(text: value, style: valueStyle),
              ),
            )
          else
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: valueStyle,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Marquee text (auto-scrolls if overflowing) ──────────────────────────────

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final bool centerWhenStatic;

  const _MarqueeText({
    required this.text,
    this.style,
    this.centerWhenStatic = false,
  });

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  final _px = ValueNotifier<double>(0.0);
  double _scrollDistance = 0;
  static const _gap = 20.0;
  static const _pxPerSec = 30.0;

  @override
  void dispose() {
    _ticker?.dispose();
    _px.dispose();
    super.dispose();
  }

  void _ensureScroll(double distance) {
    _scrollDistance = distance;
    if (_ticker != null) return;
    _ticker = createTicker((elapsed) {
      _px.value =
          (elapsed.inMicroseconds * _pxPerSec / 1000000.0) % _scrollDistance;
    })
      ..start();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final tp = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();

      if (tp.width <= constraints.maxWidth) {
        final staticText = Text(widget.text, style: widget.style, maxLines: 1);
        if (!widget.centerWhenStatic) return staticText;
        return Align(
          alignment: Alignment.center,
          child: staticText,
        );
      }

      _ensureScroll(tp.width + _gap);

      return SizedBox(
        width: constraints.maxWidth,
        height: tp.height,
        child: ClipRect(
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.06, 0.94, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: _px,
                builder: (context, px, child) => Transform.translate(
                  offset: Offset(-px, 0),
                  child: child,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.text, style: widget.style),
                    const SizedBox(width: _gap),
                    Text(widget.text, style: widget.style),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ── Category picker chip ────────────────────────────────────────────────────

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
    final bg = isSelected ? color.withValues(alpha: 0.15) : Colors.transparent;
    final border = isSelected ? color : AppColors.borderColor(context);
    final isEnabled = onTap != null;
    final textColor = !isEnabled
        ? AppColors.textTertiary(context)
        : (isRemove ? AppColors.red : AppColors.textPrimary(context));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
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
