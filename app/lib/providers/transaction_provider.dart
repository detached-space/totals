import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' hide Category;
import 'package:totals/models/account.dart';
import 'package:totals/models/auto_categorization.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/loan_debt_entry.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/repositories/loan_debt_repository.dart';
import 'package:totals/repositories/shared_expense_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/budget_alert_service.dart';
import 'package:totals/services/auto_categorization_service.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/telebirr_bank_transfer_service.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/utils/account_balance_resolver.dart';
import 'package:totals/utils/auto_categorization_rules_share_payload.dart';
import 'package:totals/utils/loan_debt_utils.dart';
import 'package:totals/utils/text_utils.dart';

class TransactionTotals {
  final double income;
  final double expense;

  const TransactionTotals({
    required this.income,
    required this.expense,
  });

  const TransactionTotals.zero()
      : income = 0.0,
        expense = 0.0;
}

class TransactionTrendSeries {
  final List<double> incomePoints;
  final List<double> expensePoints;
  final double maxValue;
  final double totalIncome;
  final double totalExpense;
  final int days;

  const TransactionTrendSeries({
    required this.incomePoints,
    required this.expensePoints,
    required this.maxValue,
    required this.totalIncome,
    required this.totalExpense,
    required this.days,
  });

  factory TransactionTrendSeries.empty(int days) {
    return TransactionTrendSeries(
      incomePoints: List<double>.filled(days, 0),
      expensePoints: List<double>.filled(days, 0),
      maxValue: 0,
      totalIncome: 0,
      totalExpense: 0,
      days: days,
    );
  }
}

class FinancialHealthSnapshot {
  final int score;
  final int cashFlowScore;
  final int runwayScore;
  final int stabilityScore;
  final int fixedCostScore;
  final double trailingIncome;
  final double trailingExpense;
  final double savingsRate;
  final double totalBalance;
  final double averageMonthlyExpense;
  final double runwayMonths;
  final double stabilityAverageDeviation;
  final int stabilitySampleCount;
  final double categorizedCoverage;
  final double essentialBurden;

  const FinancialHealthSnapshot({
    required this.score,
    required this.cashFlowScore,
    required this.runwayScore,
    required this.stabilityScore,
    required this.fixedCostScore,
    required this.trailingIncome,
    required this.trailingExpense,
    required this.savingsRate,
    required this.totalBalance,
    required this.averageMonthlyExpense,
    required this.runwayMonths,
    required this.stabilityAverageDeviation,
    required this.stabilitySampleCount,
    required this.categorizedCoverage,
    required this.essentialBurden,
  });

  const FinancialHealthSnapshot.neutral()
      : score = 50,
        cashFlowScore = 50,
        runwayScore = 50,
        stabilityScore = 50,
        fixedCostScore = 50,
        trailingIncome = 0.0,
        trailingExpense = 0.0,
        savingsRate = 0.0,
        totalBalance = 0.0,
        averageMonthlyExpense = 0.0,
        runwayMonths = 0.0,
        stabilityAverageDeviation = 0.0,
        stabilitySampleCount = 0,
        categorizedCoverage = 0.0,
        essentialBurden = 0.0;

  double get trailingNet => trailingIncome - trailingExpense;
  bool get hasStabilityHistory => stabilitySampleCount >= 2;
  bool get usesCategoryData => categorizedCoverage >= 0.4;
}

class _StabilityHealthMetrics {
  final double score;
  final double averageDeviation;
  final int sampleCount;

  const _StabilityHealthMetrics({
    required this.score,
    required this.averageDeviation,
    required this.sampleCount,
  });
}

class _AutoCategorizationRuleImportGroup {
  final String counterparty;
  final String flow;
  final List<int> categoryIds = [];
  int? primaryCategoryId;

  _AutoCategorizationRuleImportGroup({
    required this.counterparty,
    required this.flow,
  });

  void addCategory(int categoryId, {required bool isPrimary}) {
    if (!categoryIds.contains(categoryId)) {
      categoryIds.add(categoryId);
    }
    if (isPrimary || primaryCategoryId == null) {
      primaryCategoryId = categoryId;
    }
  }
}

class TransactionProvider with ChangeNotifier {
  final TransactionRepository _transactionRepo = TransactionRepository();
  final AccountRepository _accountRepo = AccountRepository();
  final CategoryRepository _categoryRepo = CategoryRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  final SharedExpenseRepository _sharedExpenseRepo = SharedExpenseRepository();
  final LoanDebtRepository _loanDebtRepo = LoanDebtRepository();
  final BudgetAlertService _budgetAlertService = BudgetAlertService();
  final AutoCategorizationService _autoCategorizationService =
      AutoCategorizationService.instance;
  final TelebirrBankTransferService _telebirrMatchService =
      TelebirrBankTransferService();

  List<Transaction> _transactions = [];
  List<Account> _accounts = [];
  List<Category> _categories = [];
  Map<int, Category> _categoryById = {};
  List<AutoCategorizationRule> _autoCategorizationRules = [];
  List<AutoCategoryPromptDismissal> _autoCategoryPromptDismissals = [];
  bool _autoCategorizationEnabled = true;
  Map<String, String> _selfTransferLabelByReference = {};
  Map<int, String> _bankNamesById = {
    CashConstants.bankId: CashConstants.bankName,
  };
  Map<int, String> _bankShortNamesById = {
    CashConstants.bankId: CashConstants.bankShortName,
  };

  // Summaries
  AllSummary? _summary;
  List<BankSummary> _bankSummaries = [];
  List<AccountSummary> _accountSummaries = [];

  bool _isLoading = false;
  String _searchKey = "";
  DateTime _selectedDate = DateTime.now();

  List<Transaction> _allTransactions = [];
  Set<String> _sharedExpenseLinkedRefs = {};
  final Set<String> _sharedExpenseSharingRefs = {};
  Map<String, String> _loanDebtPersonByReference = {};

  // Redesign home cached metrics
  List<Transaction> _todayTransactions = [];
  List<Transaction> _monthTransactions = [];
  TransactionTotals _todayTotals = const TransactionTotals.zero();
  TransactionTotals _weekTotals = const TransactionTotals.zero();
  TransactionTotals _monthTotals = const TransactionTotals.zero();
  TransactionTotals _thirtyDayTotals = const TransactionTotals.zero();
  int _selfTransferCount = 0;
  String _monthlyInsight =
      'No monthly activity yet. Keep using Totals to unlock insights.';
  TransactionTrendSeries _weekTrendSeries = TransactionTrendSeries.empty(7);
  TransactionTrendSeries _monthTrendSeries = TransactionTrendSeries.empty(30);
  FinancialHealthSnapshot _financialHealth =
      const FinancialHealthSnapshot.neutral();
  int _dataVersion = 0;
  Future<void>? _activeLoadDataFuture;
  bool _reloadQueuedWhileLoading = false;

  // Getters
  List<Transaction> get transactions => _transactions;
  List<Transaction> get allTransactions => _allTransactions;
  Set<String> get sharedExpenseLinkedRefs => _sharedExpenseLinkedRefs;
  Set<String> get sharedExpenseSharingRefs =>
      Set.unmodifiable(_sharedExpenseSharingRefs);
  List<Category> get categories => _categories;
  List<AutoCategorizationRule> get autoCategorizationRules =>
      _autoCategorizationRules;
  List<AutoCategoryPromptDismissal> get autoCategoryPromptDismissals =>
      _autoCategoryPromptDismissals;
  bool get isAutoCategorizationEnabled => _autoCategorizationEnabled;
  bool get isLoading => _isLoading;
  AllSummary? get summary => _summary;
  List<BankSummary> get bankSummaries => _bankSummaries;
  List<AccountSummary> get accountSummaries => _accountSummaries;
  DateTime get selectedDate => _selectedDate;

  bool isSharedExpenseTransaction(Transaction transaction) {
    return _sharedExpenseLinkedRefs.contains(transaction.reference.trim());
  }

  bool isSharingSharedExpenseTransaction(Transaction transaction) {
    return _sharedExpenseSharingRefs.contains(transaction.reference.trim());
  }

  void markSharedExpenseSharing(String? reference) {
    final normalized = reference?.trim();
    if (normalized == null || normalized.isEmpty) return;
    if (_sharedExpenseSharingRefs.add(normalized)) {
      notifyListeners();
    }
  }

  void unmarkSharedExpenseSharing(String? reference) {
    final normalized = reference?.trim();
    if (normalized == null || normalized.isEmpty) return;
    if (_sharedExpenseSharingRefs.remove(normalized)) {
      notifyListeners();
    }
  }

  Future<void> refreshSharedExpenseLinks() async {
    try {
      _sharedExpenseLinkedRefs = await _sharedExpenseRepo.getAllLinkedTxRefs();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('debug: Could not refresh shared expense links: $error');
      }
    } finally {
      notifyListeners();
    }
  }

  Transaction? transactionByReference(String? reference) {
    final normalized = reference?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final transaction in _allTransactions) {
      if (transaction.reference == normalized) return transaction;
    }
    return null;
  }

  List<Transaction> get todayTransactions => _todayTransactions;
  List<Transaction> get monthTransactions => _monthTransactions;
  TransactionTotals get todayTotals => _todayTotals;
  TransactionTotals get weekTotals => _weekTotals;
  TransactionTotals get monthTotals => _monthTotals;
  TransactionTotals get thirtyDayTotals => _thirtyDayTotals;
  int get selfTransferCount => _selfTransferCount;
  String get monthlyInsight => _monthlyInsight;
  TransactionTrendSeries get weekTrendSeries => _weekTrendSeries;
  TransactionTrendSeries get monthTrendSeries => _monthTrendSeries;
  FinancialHealthSnapshot get financialHealth => _financialHealth;
  int get dataVersion => _dataVersion;
  Map<int, String> get bankNamesById => _bankNamesById;
  Map<int, String> get bankShortNamesById => _bankShortNamesById;

  String getBankName(int? bankId) {
    if (bankId == null) return 'Bank';
    if (bankId == CashConstants.bankId) return CashConstants.bankName;
    return _bankNamesById[bankId] ?? 'Bank $bankId';
  }

  String getBankShortName(int? bankId) {
    if (bankId == null) return 'Bank';
    if (bankId == CashConstants.bankId) return CashConstants.bankShortName;
    return _bankShortNamesById[bankId] ?? 'Bank $bankId';
  }

  String _normalizedSortText(String value) => value.trim().toLowerCase();

  int _compareCashFirst(int aBankId, int bBankId) {
    final aIsCash = aBankId == CashConstants.bankId;
    final bIsCash = bBankId == CashConstants.bankId;
    if (aIsCash == bIsCash) return 0;
    return aIsCash ? -1 : 1;
  }

  int _compareBankSummaries(BankSummary a, BankSummary b) {
    final cashComparison = _compareCashFirst(a.bankId, b.bankId);
    if (cashComparison != 0) return cashComparison;

    final nameComparison = _normalizedSortText(
      getBankName(a.bankId),
    ).compareTo(_normalizedSortText(getBankName(b.bankId)));
    if (nameComparison != 0) return nameComparison;

    return a.bankId.compareTo(b.bankId);
  }

  int _compareAccountSummaries(AccountSummary a, AccountSummary b) {
    final cashComparison = _compareCashFirst(a.bankId, b.bankId);
    if (cashComparison != 0) return cashComparison;

    final holderComparison = _normalizedSortText(
      a.accountHolderName,
    ).compareTo(_normalizedSortText(b.accountHolderName));
    if (holderComparison != 0) return holderComparison;

    final bankComparison = _normalizedSortText(
      getBankName(a.bankId),
    ).compareTo(_normalizedSortText(getBankName(b.bankId)));
    if (bankComparison != 0) return bankComparison;

    return _normalizedSortText(
      a.accountNumber,
    ).compareTo(_normalizedSortText(b.accountNumber));
  }

  Category? getCategoryById(int? id) {
    if (id == null) return null;
    return _categoryById[id];
  }

  List<Category> categoriesForTransaction(Transaction transaction) {
    final categories = <Category>[];
    for (final categoryId in transaction.selectedCategoryIds) {
      final category = getCategoryById(categoryId);
      if (category != null) {
        categories.add(category);
      }
    }
    return categories;
  }

  String categoryLabelForTransaction(
    Transaction transaction, {
    String uncategorizedLabel = 'Uncategorized',
  }) {
    final categories = categoriesForTransaction(transaction);
    if (categories.isEmpty) return uncategorizedLabel;
    final primaryLabel = categories.first.name.trim();
    if (primaryLabel.isEmpty) return uncategorizedLabel;
    final extraCount = categories.length - 1;
    if (extraCount <= 0) return primaryLabel;
    return '$primaryLabel +$extraCount';
  }

  String? loanDebtPersonNameForTransaction(Transaction transaction) {
    final normalizedReference = transaction.reference.trim();
    if (normalizedReference.isEmpty) return null;

    final appliesToLoanDebt = categoriesForTransaction(transaction).any(
      (category) =>
          isLoanDebtCategory(category) || isRepaymentCategory(category),
    );
    if (!appliesToLoanDebt) return null;

    final personName = _loanDebtPersonByReference[normalizedReference]?.trim();
    return personName == null || personName.isEmpty ? null : personName;
  }

  List<AutoCategorizationRule> autoCategorizationRulesForFlow(String flow) {
    final normalizedFlow = _autoCategorizationService.normalizeFlow(flow);
    final rules = _autoCategorizationRules
        .where((rule) => rule.flow == normalizedFlow)
        .where((rule) => _categoryById.containsKey(rule.categoryId))
        .toList(growable: false);
    rules.sort(
      (a, b) => a.counterparty.toLowerCase().compareTo(
            b.counterparty.toLowerCase(),
          ),
    );
    rules.sort((a, b) {
      if (a.counterparty.toLowerCase() != b.counterparty.toLowerCase()) {
        return a.counterparty.toLowerCase().compareTo(
              b.counterparty.toLowerCase(),
            );
      }
      if (a.isPrimary != b.isPrimary) {
        return a.isPrimary ? -1 : 1;
      }
      return a.categoryId.compareTo(b.categoryId);
    });
    return rules;
  }

  List<AutoCategoryPromptDismissal> autoCategoryPromptDismissalsForFlow(
    String flow,
  ) {
    final normalizedFlow = _autoCategorizationService.normalizeFlow(flow);
    final dismissals = _autoCategoryPromptDismissals
        .where((dismissal) => dismissal.flow == normalizedFlow)
        .toList(growable: false);
    dismissals.sort(
      (a, b) => a.counterparty.toLowerCase().compareTo(
            b.counterparty.toLowerCase(),
          ),
    );
    return dismissals;
  }

  String autoCategorizationFlowForTransaction(Transaction transaction) {
    return _autoCategorizationService.flowForTransactionType(transaction.type);
  }

  List<AutoCategorizationRule> autoCategorizationRulesForTransaction(
    Transaction transaction,
  ) {
    final counterparty = resolvePrimaryCounterparty(transaction);
    if (counterparty == null) return const [];

    final normalizedCounterparty =
        _autoCategorizationService.normalizeCounterparty(counterparty);
    final flow = autoCategorizationFlowForTransaction(transaction);
    final rules = _autoCategorizationRules
        .where((rule) => rule.flow == flow)
        .where((rule) => rule.normalizedCounterparty == normalizedCounterparty)
        .where((rule) => _categoryById.containsKey(rule.categoryId))
        .toList(growable: false);
    rules.sort((a, b) {
      if (a.isPrimary != b.isPrimary) {
        return a.isPrimary ? -1 : 1;
      }
      return a.categoryId.compareTo(b.categoryId);
    });
    return rules;
  }

  List<int> autoCategorizationCategoryIdsForTransaction(
    Transaction transaction,
  ) {
    final ids = <int>[];
    for (final rule in autoCategorizationRulesForTransaction(transaction)) {
      if (rule.categoryId <= 0 || ids.contains(rule.categoryId)) continue;
      ids.add(rule.categoryId);
    }
    return ids;
  }

  AutoCategorizationRule? findAutoCategorizationRuleForTransaction(
    Transaction transaction,
  ) {
    final rules = autoCategorizationRulesForTransaction(transaction);
    if (rules.isEmpty) return null;
    for (final rule in rules) {
      if (rule.isPrimary) return rule;
    }
    return rules.first;
  }

  bool canConfigureAutoCategorizationForTransaction(Transaction transaction) {
    if (!_autoCategorizationEnabled) return false;
    if (_isSelfTransfer(transaction)) return false;
    return resolvePrimaryCounterparty(transaction) != null;
  }

  String? getSelfTransferLabel(Transaction transaction) {
    final existing = _selfTransferLabelByReference[transaction.reference];
    if (existing != null) return existing;
    if (_isManualSelfCategory(transaction)) {
      return transaction.type == 'CREDIT' ? 'to self' : 'from self';
    }
    return null;
  }

  bool isSelfTransfer(Transaction transaction) {
    return _isSelfTransfer(transaction);
  }

  bool isDetectedSelfTransfer(Transaction transaction) {
    return _selfTransferLabelByReference.containsKey(transaction.reference);
  }

  bool _isSelfTransfer(Transaction transaction) {
    return isDetectedSelfTransfer(transaction) ||
        _isManualSelfCategory(transaction);
  }

  bool _isManualSelfCategory(Transaction transaction) {
    final category = _categoryById[transaction.categoryId];
    if (category == null) return false;
    return category.name.trim().toLowerCase() == 'self';
  }

  Future<void> loadData() {
    final existing = _activeLoadDataFuture;
    if (existing != null) {
      _reloadQueuedWhileLoading = true;
      return existing;
    }

    final future = _loadDataUntilSettled();
    _activeLoadDataFuture = future;
    future.whenComplete(() {
      if (identical(_activeLoadDataFuture, future)) {
        _activeLoadDataFuture = null;
      }
    });
    return future;
  }

  Future<void> _loadDataUntilSettled() async {
    do {
      _reloadQueuedWhileLoading = false;
      await _loadDataInternal();
    } while (_reloadQueuedWhileLoading);
  }

  Future<void> _loadDataInternal() async {
    _isLoading = true;
    notifyListeners();

    try {
      _accounts = await _accountRepo.getAccounts();
      // print all the accounts
      debugPrint(
        "debug: Accounts: ${_accounts.map((a) => a.balance).join(', ')}",
      );

      await _categoryRepo.ensureSeeded();
      _categories = await _categoryRepo.getCategories();
      _categoryById = {
        for (final c in _categories)
          if (c.id != null) c.id!: c,
      };
      await _reloadAutoCategorizationState();

      _allTransactions = await _transactionRepo.getTransactions();
      try {
        _sharedExpenseLinkedRefs =
            await _sharedExpenseRepo.getAllLinkedTxRefs();
      } catch (error) {
        if (kDebugMode) {
          debugPrint('debug: Could not load shared expense links: $error');
        }
        _sharedExpenseLinkedRefs = {};
      }
      await _refreshLoanDebtPeople();
      debugPrint("debug: Transactions: ${_allTransactions.length}");

      final banks = await _bankConfigService.getBanks();
      _bankNamesById = {
        CashConstants.bankId: CashConstants.bankName,
        for (final bank in banks) bank.id: bank.name,
      };
      _bankShortNamesById = {
        CashConstants.bankId: CashConstants.bankShortName,
        for (final bank in banks) bank.id: bank.shortName,
      };
      final labels = _buildSelfTransferLabels(
        _telebirrMatchService.findMatches(_allTransactions, banks),
      );
      labels.addAll(_buildCashTransferLabels(_allTransactions));
      _selfTransferLabelByReference = labels;

      await _calculateSummaries(_allTransactions);
      _filterTransactions(_allTransactions);
      _recomputeRedesignHomeMetrics(_allTransactions);
      _dataVersion += 1;
    } catch (e) {
      debugPrint("debug: Error loading data: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshLoanDebtPeople() async {
    try {
      final entries = await _loanDebtRepo.getEntries();
      final repayments = await _loanDebtRepo.getRepayments();
      _loanDebtPersonByReference = _buildLoanDebtPersonLabels(
        entries: entries,
        repayments: repayments,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('debug: Could not load loan/debt person labels: $error');
      }
      _loanDebtPersonByReference = {};
    }
  }

  Map<String, String> _buildLoanDebtPersonLabels({
    required List<LoanDebtEntry> entries,
    required List<LoanDebtRepayment> repayments,
  }) {
    final personByReference = <String, String>{};
    final personByLoanReference = <String, String>{};

    for (final entry in entries) {
      final reference = entry.transactionReference.trim();
      final personName = entry.personName.trim();
      if (reference.isEmpty || personName.isEmpty) continue;
      personByReference[reference] = personName;
      personByLoanReference[reference] = personName;
    }

    for (final repayment in repayments) {
      final repaymentReference = repayment.repaymentTransactionReference.trim();
      final loanDebtReference = repayment.loanDebtTransactionReference.trim();
      if (repaymentReference.isEmpty || loanDebtReference.isEmpty) continue;

      final personName = personByLoanReference[loanDebtReference]?.trim();
      if (personName == null || personName.isEmpty) continue;
      personByReference[repaymentReference] = personName;
    }

    return personByReference;
  }

  void updateSearchKey(String key) {
    _searchKey = key;
    loadData(); // Reload to re-filter
  }

  void updateDate(DateTime date) {
    _selectedDate = date;
    loadData();
  }

  Future<void> _calculateSummaries(List<Transaction> allTransactions) async {
    final banks = await _bankConfigService.getBanks();
    final banksById = {for (final bank in banks) bank.id: bank};

    // Filter out transactions that don't have a matching account (orphaned transactions)
    final validTransactions = allTransactions.where((t) {
      if (t.bankId == null) return false;

      // Check if there's an account for this transaction's bank
      final bankAccounts = _accounts.where((a) => a.bank == t.bankId).toList();
      if (bankAccounts.isEmpty) return false;

      if (t.bankId == CashConstants.bankId) {
        return true;
      }

      final bank = banksById[t.bankId];
      if (bank == null) return false;

      // If transaction has accountNumber, verify it matches an account
      if (t.accountNumber != null && t.accountNumber!.isNotEmpty) {
        for (var account in bankAccounts) {
          bool matches = false;

          if (bank.uniformMasking == true) {
            // CBE: match last 4 digits
            matches = t.accountNumber!
                    .substring(t.accountNumber!.length - bank.maskPattern!) ==
                account.accountNumber.substring(
                    account.accountNumber.length - bank.maskPattern!);
          } else if (bank.uniformMasking == false) {
            // Awash/Telebirr: match by bankId only
            matches = true;
          } else {
            // Other banks: exact match
            matches = t.accountNumber == account.accountNumber;
          }

          if (matches) return true;
        }
        return false; // No matching account found
      } else {
        // NULL accountNumber - include only if single account for bank (legacy data)
        return bankAccounts.length == 1;
      }
    }).toList();

    // Group accounts by bank
    Map<int, List<Account>> groupedAccounts = {};
    for (var account in _accounts) {
      if (!groupedAccounts.containsKey(account.bank)) {
        groupedAccounts[account.bank] = [];
      }
      groupedAccounts[account.bank]!.add(account);
    }

    final resolvedAccountBalances = <String, double>{};

    // Calculate Account Summaries
    _accountSummaries = _accounts.map((account) {
      // Logic for specific account transactions
      // Note: original logic had a specific condition for bankId == 1 handling substrings
      // Use validTransactions to ensure we only include transactions with matching accounts
      var accountTransactions = validTransactions.where((t) {
        bool bankMatch = t.bankId == account.bank;
        if (!bankMatch) return false;

        if (account.bank == CashConstants.bankId) {
          return true;
        }

        final bank = banksById[t.bankId];
        if (bank == null) return false;

        if (bank.uniformMasking == true) {
          // CBE check: last 4 digits

          return t.accountNumber
                  ?.substring(t.accountNumber!.length - bank.maskPattern!) ==
              account.accountNumber
                  .substring(account.accountNumber.length - bank.maskPattern!);
        } else {
          return t.bankId == account.bank;
        }
      }).toList();

      debugPrint(
        "debug: Account Transactions: ${accountTransactions.length}",
      );

      // Fallback: If this is the ONLY account for this bank, also include transactions with NULL account number
      // This handles legacy data or parsing failures where account wasn't captured.
      // NOTE: Skip this for banks that match by bankId only (uniformMasking == false)
      // because they already get all transactions via the else clause above
      if (account.bank != CashConstants.bankId) {
        try {
          final accountBank = banksById[account.bank];
          if (accountBank != null && accountBank.uniformMasking != false) {
            var bankAccounts =
                _accounts.where((a) => a.bank == account.bank).toList();
            if (bankAccounts.length == 1 && bankAccounts.first == account) {
              var orphanedTransactions = validTransactions
                  .where((t) =>
                      t.bankId == account.bank &&
                      (t.accountNumber == null || t.accountNumber!.isEmpty))
                  .toList();
              accountTransactions.addAll(orphanedTransactions);
            }
          }
        } catch (e) {
          // Bank not found in database, skip orphaned transactions fallback
        }
      }

      double totalDebit = 0.0;
      double totalCredit = 0.0;
      double cashBalance = 0.0;
      for (var t in accountTransactions) {
        double amount = t.amount;
        final skip = _categoryById[t.categoryId]?.uncategorized == true;
        if (t.type == "DEBIT") {
          cashBalance -= amount;
          if (!skip) {
            totalDebit += amount;
          }
        }
        if (t.type == "CREDIT") {
          cashBalance += amount;
          if (!skip) {
            totalCredit += amount;
          }
        }
      }

      final isCashAccount = account.bank == CashConstants.bankId;
      final bankAccountCount = groupedAccounts[account.bank]?.length ?? 0;
      final accountBalance = resolveDisplayedAccountBalance(
        account: account,
        accountTransactions: accountTransactions,
        bankAccountCount: bankAccountCount,
        cashBalanceDelta: cashBalance,
        isCashAccount: isCashAccount,
      );
      resolvedAccountBalances[accountBalanceResolverKey(account)] =
          accountBalance;

      return AccountSummary(
        bankId: account.bank,
        accountNumber: account.accountNumber,
        accountHolderName: account.accountHolderName,
        totalTransactions: accountTransactions.length.toDouble(),
        totalCredit: totalCredit,
        totalDebit: totalDebit,
        settledBalance: account.settledBalance ?? 0.0,
        balance: accountBalance,
        pendingCredit: account.pendingCredit ?? 0.0,
      );
    }).toList();
    _accountSummaries.sort(_compareAccountSummaries);

    // Calculate Bank Summaries
    _bankSummaries = groupedAccounts.entries.map((entry) {
      final bankId = entry.key;
      final accounts = entry.value;

      // Filter transactions for this bank (using valid transactions only)
      final bankTransactions =
          validTransactions.where((t) => t.bankId == bankId).toList();

      double totalDebit = 0.0;
      double totalCredit = 0.0;
      double cashBalance = 0.0;

      for (var t in bankTransactions) {
        double amount = t.amount;
        final skip = _categoryById[t.categoryId]?.uncategorized == true;
        if (t.type == "DEBIT") {
          cashBalance -= amount;
          if (!skip) {
            totalDebit += amount;
          }
        } else if (t.type == "CREDIT") {
          cashBalance += amount;
          if (!skip) {
            totalCredit += amount;
          }
        }
      }

      double settledBalance =
          accounts.fold(0.0, (sum, a) => sum + (a.settledBalance ?? 0.0));
      double pendingCredit =
          accounts.fold(0.0, (sum, a) => sum + (a.pendingCredit ?? 0.0));
      final isCashBank = bankId == CashConstants.bankId;
      final hasSingleNonCashAccount = !isCashBank && accounts.length == 1;
      final totalBalance = isCashBank
          ? accounts.fold(0.0, (sum, a) => sum + a.balance) + cashBalance
          : hasSingleNonCashAccount
              ? resolvedAccountBalances[
                      accountBalanceResolverKey(accounts.first)] ??
                  accounts.first.balance
              : accounts.fold(0.0, (sum, a) => sum + a.balance);

      return BankSummary(
        bankId: bankId,
        totalCredit: totalCredit,
        totalDebit: totalDebit,
        settledBalance: settledBalance,
        pendingCredit: pendingCredit,
        totalBalance: totalBalance,
        accountCount: accounts.length,
      );
    }).toList();
    _bankSummaries.sort(_compareBankSummaries);

    // Calculate AllSummary
    double grandTotalCredit =
        _bankSummaries.fold(0.0, (sum, b) => sum + b.totalCredit);
    double grandTotalDebit =
        _bankSummaries.fold(0.0, (sum, b) => sum + b.totalDebit);
    double grandTotalBalance =
        _bankSummaries.fold(0.0, (sum, b) => sum + b.totalBalance);

    _summary = AllSummary(
      totalCredit: grandTotalCredit,
      totalDebit: grandTotalDebit,
      banks: _accounts
          .length, // Original logic passed account length to banks? weird, but sticking to logic
      accounts: _accounts.length,
      totalBalance: grandTotalBalance,
    );
  }

  void _filterTransactions(List<Transaction> allTransactions) {
    // Filter by date and search key
    // Normalize selected date to start of day for comparison
    DateTime selectedDateStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    _transactions = allTransactions.where((t) {
      if (t.time == null) return false;

      // Parse ISO8601 date string
      try {
        DateTime? transactionDate;
        if (t.time!.contains('T')) {
          // ISO8601 format: "2024-01-15T10:30:00.000Z"
          transactionDate = DateTime.parse(t.time!);
        } else {
          // Try other formats if needed
          transactionDate = DateTime.tryParse(t.time!);
        }

        if (transactionDate == null) return false;

        // Normalize transaction date to start of day for comparison
        DateTime transactionDateStart = DateTime(
          transactionDate.year,
          transactionDate.month,
          transactionDate.day,
        );

        // Compare dates (ignoring time)
        bool dateMatch =
            transactionDateStart.isAtSameMomentAs(selectedDateStart);
        if (!dateMatch) return false;
      } catch (e) {
        debugPrint(
          "debug: Error parsing transaction date: ${t.time}, error: $e",
        );
        return false;
      }

      if (_searchKey.isEmpty) return true;

      return (t.creditor?.toLowerCase().contains(_searchKey.toLowerCase()) ??
              false) ||
          (t.receiver?.toLowerCase().contains(_searchKey.toLowerCase()) ??
              false) ||
          (t.note?.toLowerCase().contains(_searchKey.toLowerCase()) ?? false) ||
          (t.reference.toLowerCase().contains(_searchKey.toLowerCase()));
    }).toList();
  }

  Transaction? _replaceTransactionLocally(Transaction updated) {
    Transaction? previous;

    List<Transaction> replaceInList(List<Transaction> source) {
      return source.map((transaction) {
        if (transaction.reference != updated.reference) return transaction;
        previous ??= transaction;
        return updated;
      }).toList();
    }

    _allTransactions = replaceInList(_allTransactions);
    _transactions = replaceInList(_transactions);
    _todayTransactions = replaceInList(_todayTransactions);
    _monthTransactions = replaceInList(_monthTransactions);
    return previous;
  }

  void _notifyOptimisticChange() {
    _dataVersion += 1;
    notifyListeners();
  }

  Future<void> _reloadAutoCategorizationState() async {
    _autoCategorizationEnabled = await NotificationSettingsService.instance
        .isAutoCategorizationEnabled();
    _autoCategorizationRules = await _autoCategorizationService.getRules();
    _autoCategoryPromptDismissals =
        await _autoCategorizationService.getDismissals();
  }

  Future<void> _recomputeAfterTransactionMutation() async {
    await _calculateSummaries(_allTransactions);
    _filterTransactions(_allTransactions);
    _recomputeRedesignHomeMetrics(_allTransactions);
    _dataVersion += 1;
    notifyListeners();
  }

  Map<String, String> _buildSelfTransferLabels(
    List<TelebirrBankTransferMatch> matches,
  ) {
    final labels = <String, String>{};
    for (final match in matches) {
      labels[match.telebirrTransaction.reference] = 'from self';
      labels[match.bankTransaction.reference] = 'to self';
    }
    return labels;
  }

  Map<String, String> _buildCashTransferLabels(
    List<Transaction> transactions,
  ) {
    final labels = <String, String>{};
    final byReference = {
      for (final transaction in transactions)
        transaction.reference: transaction,
    };

    for (final transaction in transactions) {
      if (transaction.bankId != CashConstants.bankId) continue;
      final reference = transaction.reference;
      if (!reference.startsWith(CashConstants.atmReferencePrefix)) continue;

      final linkedReference =
          reference.substring(CashConstants.atmReferencePrefix.length);
      if (!byReference.containsKey(linkedReference)) continue;

      labels[reference] = 'from self';
      labels[linkedReference] = 'to self';
    }

    return labels;
  }

  void _recomputeRedesignHomeMetrics(List<Transaction> transactions) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    // Rolling 7-day window (today + previous 6 days).
    final weekStart = todayStart.subtract(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    final last30Start = todayStart.subtract(const Duration(days: 29));
    final last90Start = todayStart.subtract(const Duration(days: 89));

    final todayEntries = <MapEntry<Transaction, DateTime>>[];
    final monthTransactions = <Transaction>[];

    var todayIncome = 0.0;
    var todayExpense = 0.0;
    var weekIncome = 0.0;
    var weekExpense = 0.0;
    var monthIncome = 0.0;
    var monthExpense = 0.0;
    var thirtyDayIncome = 0.0;
    var thirtyDayExpense = 0.0;
    var selfTransferCount = 0;

    final weekIncomeBuckets = List<double>.filled(7, 0);
    final weekExpenseBuckets = List<double>.filled(7, 0);
    final monthIncomeBuckets = List<double>.filled(30, 0);
    final monthExpenseBuckets = List<double>.filled(30, 0);

    final monthNetByOffset = List<double>.filled(4, 0);
    final monthHasTransactions = List<bool>.filled(4, false);
    final healthMonthIncomeByOffset = List<double>.filled(4, 0);
    final healthMonthExpenseByOffset = List<double>.filled(4, 0);

    var ninetyDayIncome = 0.0;
    var ninetyDayExpense = 0.0;
    var ninetyDayCategorizedExpense = 0.0;
    var ninetyDayEssentialExpense = 0.0;

    for (final transaction in transactions) {
      final dt = _parseTransactionTimeLocal(transaction.time);
      if (dt == null) continue;

      final dateOnly = DateTime(dt.year, dt.month, dt.day);
      final isToday =
          !dateOnly.isBefore(todayStart) && dateOnly.isBefore(tomorrowStart);
      final isWeek =
          !dateOnly.isBefore(weekStart) && !dateOnly.isAfter(todayStart);
      final isMonth =
          !dateOnly.isBefore(monthStart) && dateOnly.isBefore(nextMonthStart);
      final isLast30 =
          !dateOnly.isBefore(last30Start) && !dateOnly.isAfter(todayStart);
      final isLast90 =
          !dateOnly.isBefore(last90Start) && !dateOnly.isAfter(todayStart);
      final isSelfTransfer = _isSelfTransfer(transaction);

      if (isToday) {
        todayEntries.add(MapEntry(transaction, dt));
      }
      if (isMonth) {
        monthTransactions.add(transaction);
      }
      if (isSelfTransfer) {
        selfTransferCount += 1;
      }

      final monthOffset =
          (now.year - dateOnly.year) * 12 + (now.month - dateOnly.month);
      if (monthOffset >= 0 && monthOffset <= 3) {
        monthHasTransactions[monthOffset] = true;
      }

      final isMisc =
          _categoryById[transaction.categoryId]?.uncategorized == true;

      if (isSelfTransfer || isMisc) continue;

      final isCredit = transaction.type == 'CREDIT';
      final isDebit = transaction.type == 'DEBIT';
      if (!isCredit && !isDebit) continue;

      final amount = transaction.amount;
      final category = _categoryById[transaction.categoryId];

      if (isToday) {
        if (isCredit) {
          todayIncome += amount;
        } else {
          todayExpense += amount;
        }
      }

      if (isWeek) {
        if (isCredit) {
          weekIncome += amount;
        } else {
          weekExpense += amount;
        }

        final weekIndex = dateOnly.difference(weekStart).inDays;
        if (weekIndex >= 0 && weekIndex < 7) {
          if (isCredit) {
            weekIncomeBuckets[weekIndex] += amount;
          } else {
            weekExpenseBuckets[weekIndex] += amount;
          }
        }
      }

      if (isMonth) {
        if (isCredit) {
          monthIncome += amount;
        } else {
          monthExpense += amount;
        }
      }

      if (isLast30) {
        if (isCredit) {
          thirtyDayIncome += amount;
        } else {
          thirtyDayExpense += amount;
        }

        final monthIndex = dateOnly.difference(last30Start).inDays;
        if (monthIndex >= 0 && monthIndex < 30) {
          if (isCredit) {
            monthIncomeBuckets[monthIndex] += amount;
          } else {
            monthExpenseBuckets[monthIndex] += amount;
          }
        }
      }

      if (monthOffset >= 0 && monthOffset <= 3) {
        monthNetByOffset[monthOffset] += isCredit ? amount : -amount;
        if (isCredit) {
          healthMonthIncomeByOffset[monthOffset] += amount;
        } else {
          healthMonthExpenseByOffset[monthOffset] += amount;
        }
      }

      if (isLast90) {
        if (isCredit) {
          ninetyDayIncome += amount;
        } else {
          ninetyDayExpense += amount;
          if (category != null && !category.uncategorized) {
            ninetyDayCategorizedExpense += amount;
            if (category.essential) {
              ninetyDayEssentialExpense += amount;
            }
          }
        }
      }
    }

    todayEntries.sort((a, b) => b.value.compareTo(a.value));

    _todayTransactions =
        todayEntries.map((entry) => entry.key).toList(growable: false);
    _monthTransactions = monthTransactions.toList(growable: false);
    _todayTotals =
        TransactionTotals(income: todayIncome, expense: todayExpense);
    _weekTotals = TransactionTotals(income: weekIncome, expense: weekExpense);
    _monthTotals =
        TransactionTotals(income: monthIncome, expense: monthExpense);
    _thirtyDayTotals = TransactionTotals(
      income: thirtyDayIncome,
      expense: thirtyDayExpense,
    );
    _selfTransferCount = selfTransferCount;
    _weekTrendSeries =
        _buildTrendSeriesFromBuckets(weekIncomeBuckets, weekExpenseBuckets);
    _monthTrendSeries =
        _buildTrendSeriesFromBuckets(monthIncomeBuckets, monthExpenseBuckets);
    _monthlyInsight =
        _buildMonthlyInsightFromNets(monthNetByOffset, monthHasTransactions);
    _financialHealth = _buildFinancialHealthSnapshot(
      trailingIncome: ninetyDayIncome,
      trailingExpense: ninetyDayExpense,
      categorizedExpense: ninetyDayCategorizedExpense,
      essentialExpense: ninetyDayEssentialExpense,
      monthlyIncomeByOffset: healthMonthIncomeByOffset,
      monthlyExpenseByOffset: healthMonthExpenseByOffset,
      totalBalance: _summary?.totalBalance ??
          _accountSummaries.fold<double>(
            0.0,
            (sum, summary) => sum + summary.balance,
          ),
    );
  }

  DateTime? _parseTransactionTimeLocal(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  TransactionTrendSeries _buildTrendSeriesFromBuckets(
    List<double> income,
    List<double> expense,
  ) {
    final days = income.length;
    final totalIncome = income.fold<double>(0.0, (sum, value) => sum + value);
    final totalExpense = expense.fold<double>(0.0, (sum, value) => sum + value);
    final maxIncome = income.fold<double>(0.0, math.max);
    final maxExpense = expense.fold<double>(0.0, math.max);
    final maxValue = math.max(maxIncome, maxExpense);

    if (maxValue <= 0) {
      return TransactionTrendSeries.empty(days);
    }

    List<double> normalize(List<double> values) {
      return values
          .map((value) => (value / maxValue).clamp(0.0, 1.0).toDouble())
          .toList(growable: false);
    }

    return TransactionTrendSeries(
      incomePoints: normalize(income),
      expensePoints: normalize(expense),
      maxValue: maxValue,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      days: days,
    );
  }

  // Composite redesign score: recent cash flow, liquidity runway,
  // stability across prior full months, and essential-cost pressure.
  FinancialHealthSnapshot _buildFinancialHealthSnapshot({
    required double trailingIncome,
    required double trailingExpense,
    required double categorizedExpense,
    required double essentialExpense,
    required List<double> monthlyIncomeByOffset,
    required List<double> monthlyExpenseByOffset,
    required double totalBalance,
  }) {
    final savingsRate = trailingIncome <= 0
        ? 0.0
        : ((trailingIncome - trailingExpense) / trailingIncome)
            .clamp(-1.0, 1.0);
    final averageMonthlyExpense = trailingExpense / 3.0;
    final runwayMonths = averageMonthlyExpense <= 0
        ? (totalBalance > 0 ? double.infinity : 0.0)
        : (totalBalance <= 0 ? 0.0 : totalBalance / averageMonthlyExpense);
    final categorizedCoverage = trailingExpense <= 0
        ? 0.0
        : (categorizedExpense / trailingExpense).clamp(0.0, 1.0);
    final essentialBurden = trailingIncome <= 0
        ? 0.0
        : (essentialExpense / trailingIncome).clamp(0.0, 2.0);
    final stabilityMetrics = _buildStabilityMetrics(
      monthlyIncomeByOffset: monthlyIncomeByOffset,
      monthlyExpenseByOffset: monthlyExpenseByOffset,
    );
    final cashFlowScore = _computeCashFlowScore(
      savingsRate: savingsRate,
    );
    final runwayScore = _computeRunwayScore(
      runwayMonths: runwayMonths,
      totalBalance: totalBalance,
      averageMonthlyExpense: averageMonthlyExpense,
    );
    final stabilityScore = stabilityMetrics.score;
    final fixedCostScore = _computeFixedCostScore(
      trailingIncome: trailingIncome,
      trailingExpense: trailingExpense,
      categorizedCoverage: categorizedCoverage,
      essentialBurden: essentialBurden,
    );

    final weightedScore = 0.40 * cashFlowScore +
        0.30 * runwayScore +
        0.20 * stabilityScore +
        0.10 * fixedCostScore;

    return FinancialHealthSnapshot(
      score: weightedScore.round().clamp(0, 100),
      cashFlowScore: cashFlowScore.round().clamp(0, 100),
      runwayScore: runwayScore.round().clamp(0, 100),
      stabilityScore: stabilityScore.round().clamp(0, 100),
      fixedCostScore: fixedCostScore.round().clamp(0, 100),
      trailingIncome: trailingIncome,
      trailingExpense: trailingExpense,
      savingsRate: savingsRate,
      totalBalance: totalBalance,
      averageMonthlyExpense: averageMonthlyExpense,
      runwayMonths: runwayMonths,
      stabilityAverageDeviation: stabilityMetrics.averageDeviation,
      stabilitySampleCount: stabilityMetrics.sampleCount,
      categorizedCoverage: categorizedCoverage,
      essentialBurden: essentialBurden,
    );
  }

  double _computeCashFlowScore({
    required double savingsRate,
  }) {
    return _scoreLinear(savingsRate, min: -0.20, max: 0.20);
  }

  double _computeRunwayScore({
    required double runwayMonths,
    required double totalBalance,
    required double averageMonthlyExpense,
  }) {
    if (averageMonthlyExpense <= 0) {
      if (totalBalance > 0) return 75;
      return 50;
    }

    return _scoreLinear(runwayMonths, min: 0.0, max: 6.0);
  }

  _StabilityHealthMetrics _buildStabilityMetrics({
    required List<double> monthlyIncomeByOffset,
    required List<double> monthlyExpenseByOffset,
  }) {
    final monthlySavingsRates = <double>[];

    for (var offset = 1; offset < monthlyIncomeByOffset.length; offset++) {
      final income = monthlyIncomeByOffset[offset];
      final expense = monthlyExpenseByOffset[offset];
      if (income <= 0 && expense <= 0) continue;

      if (income <= 0) {
        monthlySavingsRates.add(-1.0);
        continue;
      }

      monthlySavingsRates.add(
        ((income - expense) / income).clamp(-1.0, 1.0),
      );
    }

    if (monthlySavingsRates.length < 2) {
      return const _StabilityHealthMetrics(
        score: 50,
        averageDeviation: 0.0,
        sampleCount: 0,
      );
    }

    final mean = monthlySavingsRates.fold<double>(
          0.0,
          (sum, value) => sum + value,
        ) /
        monthlySavingsRates.length;
    final averageDeviation = monthlySavingsRates.fold<double>(
          0.0,
          (sum, value) => sum + (value - mean).abs(),
        ) /
        monthlySavingsRates.length;

    return _StabilityHealthMetrics(
      score: _inverseScoreLinear(averageDeviation, min: 0.05, max: 0.35),
      averageDeviation: averageDeviation,
      sampleCount: monthlySavingsRates.length,
    );
  }

  double _computeFixedCostScore({
    required double trailingIncome,
    required double trailingExpense,
    required double categorizedCoverage,
    required double essentialBurden,
  }) {
    if (trailingExpense <= 0 || trailingIncome <= 0) return 50;

    if (categorizedCoverage < 0.4) return 50;

    return _inverseScoreLinear(essentialBurden, min: 0.50, max: 0.85);
  }

  double _scoreLinear(
    double value, {
    required double min,
    required double max,
  }) {
    if (max <= min) return 50;
    return (((value - min) / (max - min)).clamp(0.0, 1.0)) * 100.0;
  }

  double _inverseScoreLinear(
    double value, {
    required double min,
    required double max,
  }) {
    return 100.0 - _scoreLinear(value, min: min, max: max);
  }

  String _buildMonthlyInsightFromNets(
    List<double> monthNetByOffset,
    List<bool> monthHasTransactions,
  ) {
    final currentNet = monthNetByOffset[0];
    final priorNets = <double>[];

    for (int offset = 1; offset <= 3; offset++) {
      if (!monthHasTransactions[offset]) continue;
      priorNets.add(monthNetByOffset[offset]);
    }

    if (!monthHasTransactions[0] && priorNets.isEmpty) {
      return 'No monthly activity yet. Keep using Totals to unlock insights.';
    }

    final currentLabel = _formatEtbValue(currentNet.abs());
    final currentSign = currentNet >= 0 ? 'saved' : 'spent more than earned';

    if (priorNets.isEmpty) {
      return currentNet >= 0
          ? "You've saved ETB $currentLabel so far this month."
          : "You've spent ETB $currentLabel more than you earned this month.";
    }

    final avgNet =
        priorNets.reduce((sum, value) => sum + value) / priorNets.length;
    if (avgNet.abs() < 0.01) {
      return currentNet >= 0
          ? "You've saved ETB $currentLabel so far this month."
          : "You've spent ETB $currentLabel more than you earned this month.";
    }

    final deltaPercent = ((currentNet - avgNet).abs() / avgNet.abs()) * 100;
    final roundedPercent = deltaPercent.isFinite ? deltaPercent.round() : 0;
    final direction = currentNet >= avgNet ? 'better' : 'lower';

    return "You've $currentSign ETB $currentLabel this month, $roundedPercent% $direction than your 3-month average.";
  }

  String _formatEtbValue(double value) {
    final rounded = value.roundToDouble();
    return formatNumberWithComma(rounded).replaceFirst(RegExp(r'\\.00$'), '');
  }

  Future<double> setCashWalletBalance({
    required double targetBalance,
    required String accountNumber,
  }) async {
    if (targetBalance < 0) {
      throw ArgumentError('Target balance cannot be negative');
    }

    final cashAccounts =
        _accounts.where((a) => a.bank == CashConstants.bankId).toList();

    if (cashAccounts.isEmpty) {
      final accountToCreate = accountNumber.isNotEmpty
          ? accountNumber
          : CashConstants.defaultAccountNumber;
      await _accountRepo.saveAccount(
        Account(
          accountNumber: accountToCreate,
          bank: CashConstants.bankId,
          balance: targetBalance,
          accountHolderName: CashConstants.defaultAccountHolderName,
        ),
      );
      await loadData();
      await WidgetService.refreshWidget();
      return targetBalance;
    }

    final cashAccount = cashAccounts.firstWhere(
      (a) => a.accountNumber == accountNumber,
      orElse: () => cashAccounts.first,
    );

    final walletSummaries = _accountSummaries
        .where((summary) => summary.bankId == CashConstants.bankId)
        .toList();
    final currentBalance = walletSummaries.isNotEmpty
        ? walletSummaries.fold<double>(
            0.0, (sum, summary) => sum + summary.balance)
        : cashAccounts.fold<double>(
            0.0, (sum, account) => sum + account.balance);

    final delta = targetBalance - currentBalance;
    if (delta.abs() < 0.0001) return 0.0;

    final updatedCashAccount = Account(
      accountNumber: cashAccount.accountNumber,
      bank: cashAccount.bank,
      balance: cashAccount.balance + delta,
      accountHolderName: cashAccount.accountHolderName,
      settledBalance: cashAccount.settledBalance,
      pendingCredit: cashAccount.pendingCredit,
      profileId: cashAccount.profileId,
    );
    await _accountRepo.saveAccount(updatedCashAccount);
    await loadData();
    await WidgetService.refreshWidget();
    return delta;
  }

  // Method to handle new incoming SMS transaction
  Future<void> addTransaction(Transaction t) async {
    await _transactionRepo.saveTransaction(t);
    // Update account balance if match found
    // This logic was in onBackgroundMessage, we should probably centralize it here or in a Service
    // For now, simpler to just reload everything
    await loadData();
    await WidgetService.refreshWidget();
    // Check budget alerts after adding transaction (only for DEBIT transactions)
    if (t.type == 'DEBIT') {
      try {
        await _budgetAlertService.checkAndNotifyBudgetAlerts();
      } catch (e) {
        debugPrint(
          "debug: Error checking budget alerts after transaction: $e",
        );
      }
    }
  }

  Future<void> setCategoryForTransaction(
    Transaction transaction,
    Category category,
  ) async {
    if (category.id == null) return;
    await updateCategoriesForTransaction(
      transaction,
      categoryIds: <int>[category.id!],
      primaryCategoryId: category.id,
    );
  }

  Future<Transaction> updateCategoriesForTransaction(
    Transaction transaction, {
    required List<int> categoryIds,
    int? primaryCategoryId,
  }) async {
    final normalizedCategoryIds = <int>[];
    for (final categoryId in categoryIds) {
      if (categoryId <= 0 || normalizedCategoryIds.contains(categoryId)) {
        continue;
      }
      normalizedCategoryIds.add(categoryId);
    }

    final resolvedPrimaryCategoryId = normalizedCategoryIds.isEmpty
        ? null
        : (primaryCategoryId != null &&
                normalizedCategoryIds.contains(primaryCategoryId)
            ? primaryCategoryId
            : normalizedCategoryIds.first);

    final updated = normalizedCategoryIds.isEmpty
        ? transaction.copyWith(
            clearCategoryId: true,
            clearCategoryIds: true,
          )
        : transaction.copyWith(
            categoryId: resolvedPrimaryCategoryId,
            categoryIds: normalizedCategoryIds,
          );

    final hasSelectionChanged = updated.categoryId != transaction.categoryId ||
        !listEquals(
          updated.selectedCategoryIds,
          transaction.selectedCategoryIds,
        );
    if (!hasSelectionChanged) {
      return transaction;
    }

    final previous = _replaceTransactionLocally(updated);
    if (previous != null) {
      _notifyOptimisticChange();
    }

    try {
      await _transactionRepo.saveTransaction(
        updated,
        skipAutoCategorization: true,
      );
    } catch (e) {
      if (previous != null) {
        _replaceTransactionLocally(previous);
        _notifyOptimisticChange();
      }
      rethrow;
    }

    unawaited(
      _finalizeCategoryMutationAfterSave(
        transactionType: transaction.type,
        categoryIds: updated.selectedCategoryIds,
      ),
    );

    return updated;
  }

  Future<void> updateNoteForTransaction(
    Transaction transaction,
    String? note,
  ) async {
    final normalizedNote = note?.trim();
    final updated = normalizedNote == null || normalizedNote.isEmpty
        ? transaction.copyWith(clearNote: true)
        : transaction.copyWith(note: normalizedNote);
    final previous = _replaceTransactionLocally(updated);
    if (previous != null) {
      _filterTransactions(_allTransactions);
      _notifyOptimisticChange();
    }

    try {
      await _transactionRepo.saveTransaction(
        updated,
        skipAutoCategorization: true,
      );
    } catch (e) {
      if (previous != null) {
        _replaceTransactionLocally(previous);
        _filterTransactions(_allTransactions);
        _notifyOptimisticChange();
      }
      rethrow;
    }

    _filterTransactions(_allTransactions);
    _dataVersion += 1;
    notifyListeners();
  }

  Future<void> updateCounterpartyForTransaction(
    Transaction transaction,
    String? counterparty,
  ) async {
    final normalizedCounterparty = counterparty?.trim();
    final updatedValue =
        normalizedCounterparty == null || normalizedCounterparty.isEmpty
            ? null
            : normalizedCounterparty;
    final updated = Transaction(
      amount: transaction.amount,
      reference: transaction.reference,
      creditor:
          transaction.type == 'CREDIT' ? updatedValue : transaction.creditor,
      receiver:
          transaction.type == 'CREDIT' ? transaction.receiver : updatedValue,
      note: transaction.note,
      time: transaction.time,
      status: transaction.status,
      currentBalance: transaction.currentBalance,
      bankId: transaction.bankId,
      type: transaction.type,
      transactionLink: transaction.transactionLink,
      accountNumber: transaction.accountNumber,
      categoryId: transaction.categoryId,
      categoryIds: transaction.categoryIds,
      profileId: transaction.profileId,
      serviceCharge: transaction.serviceCharge,
      vat: transaction.vat,
      sourceType: transaction.sourceType,
      sourceMessageId: transaction.sourceMessageId,
      sourceFingerprint: transaction.sourceFingerprint,
    );

    final previous = _replaceTransactionLocally(updated);
    if (previous != null) {
      _filterTransactions(_allTransactions);
      _notifyOptimisticChange();
    }

    try {
      await _transactionRepo.saveTransaction(
        updated,
        skipAutoCategorization: true,
      );
    } catch (e) {
      if (previous != null) {
        _replaceTransactionLocally(previous);
        _filterTransactions(_allTransactions);
        _notifyOptimisticChange();
      }
      rethrow;
    }

    _filterTransactions(_allTransactions);
    _dataVersion += 1;
    notifyListeners();
  }

  Future<void> clearCategoryForTransaction(Transaction transaction) async {
    await updateCategoriesForTransaction(
      transaction,
      categoryIds: const <int>[],
    );
  }

  Future<void> _finalizeCategoryMutationAfterSave({
    required String? transactionType,
    Iterable<int> categoryIds = const <int>[],
  }) async {
    try {
      await _recomputeAfterTransactionMutation();
      await WidgetService.refreshWidget();
    } catch (e) {
      debugPrint("debug: Error recomputing state after categorizing: $e");
    }

    if (transactionType == 'DEBIT') {
      for (final categoryId in categoryIds.toSet()) {
        try {
          await _budgetAlertService
              .checkAndNotifyBudgetAlertsForCategory(categoryId);
        } catch (e) {
          debugPrint(
            "debug: Error checking budget alerts after categorizing: $e",
          );
        }
      }
    }
  }

  Future<void> deleteTransactionsByReferences(
      Iterable<String> references) async {
    await _transactionRepo.deleteTransactionsByReferences(references);
    await loadData();
    await WidgetService.refreshWidget();
  }

  Future<void> createCategory({
    required String name,
    required bool essential,
    bool uncategorized = false,
    String? iconKey,
    String? colorKey,
    String? description,
    String flow = 'expense',
    bool recurring = false,
  }) async {
    await _categoryRepo.createCategory(
      name: name,
      essential: essential,
      uncategorized: uncategorized,
      iconKey: iconKey,
      colorKey: colorKey,
      description: description,
      flow: flow,
      recurring: recurring,
    );
    await loadData();
  }

  Future<void> updateCategory(Category category) async {
    await _categoryRepo.updateCategory(category);
    await loadData();
  }

  Future<void> deleteCategory(Category category) async {
    await _categoryRepo.deleteCategory(category);
    await loadData();
  }

  Future<AutoCategorizationRulesImportResult>
      importAutoCategorizationRulesPayload(
    AutoCategorizationRulesSharePayload payload,
  ) async {
    final localCategories = await _categoryRepo.getCategories();
    final categoryIdBySourceId = <int, int>{};
    var createdCategories = 0;
    var matchedCategories = 0;

    for (final sharedCategory in payload.categories) {
      if (categoryIdBySourceId.containsKey(sharedCategory.sourceId)) {
        continue;
      }

      var localCategory = _findMatchingSharedCategory(
        sharedCategory,
        localCategories,
      );

      if (localCategory == null) {
        localCategory = await _createSharedCategory(
          sharedCategory,
          localCategories,
        );
        createdCategories++;
      } else {
        matchedCategories++;
      }

      final localCategoryId = localCategory.id;
      if (localCategoryId != null && localCategoryId > 0) {
        categoryIdBySourceId[sharedCategory.sourceId] = localCategoryId;
      }
    }

    final groups = <String, _AutoCategorizationRuleImportGroup>{};
    for (final sharedRule in payload.rules) {
      final localCategoryId = categoryIdBySourceId[sharedRule.sourceCategoryId];
      if (localCategoryId == null || localCategoryId <= 0) continue;

      final flow = _autoCategorizationService.normalizeFlow(sharedRule.flow);
      final normalizedCounterparty =
          sharedRule.normalizedCounterparty.trim().isNotEmpty
              ? sharedRule.normalizedCounterparty
              : _autoCategorizationService.normalizeCounterparty(
                  sharedRule.counterparty,
                );
      if (normalizedCounterparty.isEmpty) continue;

      final key = '$normalizedCounterparty::$flow';
      final group = groups.putIfAbsent(
        key,
        () => _AutoCategorizationRuleImportGroup(
          counterparty: sharedRule.counterparty,
          flow: flow,
        ),
      );
      group.addCategory(localCategoryId, isPrimary: sharedRule.isPrimary);
    }

    var importedRuleGroups = 0;
    var importedRules = 0;
    for (final group in groups.values) {
      if (group.categoryIds.isEmpty) continue;

      await _autoCategorizationService.replaceRules(
        counterparty: group.counterparty,
        flow: group.flow,
        categoryIds: group.categoryIds,
        primaryCategoryId: group.primaryCategoryId,
      );
      await _autoCategorizationService.clearPromptDismissal(
        counterparty: group.counterparty,
        flow: group.flow,
      );
      importedRuleGroups++;
      importedRules += group.categoryIds.length;
    }

    await loadData();
    return AutoCategorizationRulesImportResult(
      createdCategories: createdCategories,
      matchedCategories: matchedCategories,
      importedRuleGroups: importedRuleGroups,
      importedRules: importedRules,
    );
  }

  Future<Category> _createSharedCategory(
    AutoCategorizationRulesShareCategory sharedCategory,
    List<Category> localCategories,
  ) async {
    try {
      final category = await _categoryRepo.createCategory(
        name: sharedCategory.name,
        essential: sharedCategory.essential,
        uncategorized: sharedCategory.uncategorized,
        iconKey: sharedCategory.iconKey,
        colorKey: sharedCategory.colorKey,
        description: sharedCategory.description,
        flow: _normalizeSharedCategoryFlow(sharedCategory.flow),
        recurring: sharedCategory.recurring,
      );
      localCategories.add(category);
      return category;
    } catch (_) {
      final refreshedCategories = await _categoryRepo.getCategories();
      localCategories
        ..clear()
        ..addAll(refreshedCategories);
      final existing = _findMatchingSharedCategory(
        sharedCategory,
        localCategories,
      );
      if (existing != null) return existing;
      rethrow;
    }
  }

  Category? _findMatchingSharedCategory(
    AutoCategorizationRulesShareCategory sharedCategory,
    List<Category> localCategories,
  ) {
    final builtInKey = sharedCategory.builtInKey?.trim();
    if (builtInKey != null && builtInKey.isNotEmpty) {
      for (final category in localCategories) {
        if (category.builtInKey == builtInKey) return category;
      }
    }

    final targetFlow = _normalizeSharedCategoryFlow(sharedCategory.flow);
    final targetName = _normalizeSharedCategoryName(sharedCategory.name);
    for (final category in localCategories) {
      if (_normalizeSharedCategoryFlow(category.flow) != targetFlow) continue;
      if (_normalizeSharedCategoryName(category.name) == targetName) {
        return category;
      }
    }
    return null;
  }

  String _normalizeSharedCategoryFlow(String? flow) {
    return flow?.trim().toLowerCase() == 'income' ? 'income' : 'expense';
  }

  String _normalizeSharedCategoryName(String name) {
    return name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String? resolvePrimaryCounterparty(Transaction transaction) {
    return _autoCategorizationService.resolvePrimaryCounterparty(
      type: transaction.type,
      receiver: transaction.receiver,
      creditor: transaction.creditor,
    );
  }

  Future<AutoCategorizationPromptDecision?>
      buildAutoCategorizationPromptDecision(
    Transaction transaction,
    Category category,
  ) async {
    if (!_autoCategorizationEnabled) return null;
    final categoryId = category.id;
    if (categoryId == null) return null;
    if (_isLoanDebtManagedCategory(category)) return null;
    if (transaction.categoryId == categoryId) return null;
    if (_isSelfTransfer(transaction)) return null;

    final counterparty = resolvePrimaryCounterparty(transaction);
    if (counterparty == null) return null;

    final flow = _autoCategorizationService.normalizeFlow(category.flow);
    final isDismissed = await _autoCategorizationService.isPromptDismissed(
      counterparty: counterparty,
      flow: flow,
    );
    if (isDismissed) return null;

    final existingRule =
        await _autoCategorizationService.getRuleForCounterparty(
      counterparty,
      flow,
    );
    if (existingRule != null && existingRule.categoryId == categoryId) {
      return null;
    }

    return AutoCategorizationPromptDecision(
      counterparty: counterparty,
      flow: flow,
      categoryId: categoryId,
      existingRule: existingRule,
    );
  }

  Future<void> saveAutoCategorizationRule(
    AutoCategorizationPromptDecision decision,
  ) async {
    await _autoCategorizationService.upsertRule(
      counterparty: decision.counterparty,
      flow: decision.flow,
      categoryId: decision.categoryId,
    );
    await _autoCategorizationService.clearPromptDismissal(
      counterparty: decision.counterparty,
      flow: decision.flow,
    );
    await _reloadAutoCategorizationState();
    _dataVersion += 1;
    notifyListeners();
  }

  Future<void> syncAutoCategorizationRuleForSelection({
    required Transaction transaction,
    required Category category,
    required bool shouldAutoCategorize,
  }) async {
    final categoryId = category.id;
    if (categoryId == null) return;
    await syncAutoCategorizationRulesForSelection(
      transaction: transaction,
      categoryIds: <int>[categoryId],
      primaryCategoryId: categoryId,
      shouldAutoCategorize: shouldAutoCategorize,
    );
  }

  Future<void> syncAutoCategorizationRulesForSelection({
    required Transaction transaction,
    required List<int> categoryIds,
    int? primaryCategoryId,
    required bool shouldAutoCategorize,
  }) async {
    if (!_autoCategorizationEnabled) return;

    final counterparty = resolvePrimaryCounterparty(transaction);
    if (counterparty == null) return;

    final normalizedCategoryIds = <int>[];
    for (final categoryId in categoryIds) {
      if (categoryId <= 0 || normalizedCategoryIds.contains(categoryId)) {
        continue;
      }
      final category = _categoryById[categoryId];
      if (category == null || _isLoanDebtManagedCategory(category)) continue;
      normalizedCategoryIds.add(categoryId);
    }

    final resolvedPrimaryCategoryId = normalizedCategoryIds.isEmpty
        ? null
        : (primaryCategoryId != null &&
                normalizedCategoryIds.contains(primaryCategoryId)
            ? primaryCategoryId
            : normalizedCategoryIds.first);

    final flow = autoCategorizationFlowForTransaction(transaction);

    if (shouldAutoCategorize && resolvedPrimaryCategoryId != null) {
      await _autoCategorizationService.replaceRules(
        counterparty: counterparty,
        flow: flow,
        categoryIds: normalizedCategoryIds,
        primaryCategoryId: resolvedPrimaryCategoryId,
      );
      await _autoCategorizationService.clearPromptDismissal(
        counterparty: counterparty,
        flow: flow,
      );
    } else {
      await _autoCategorizationService.deleteRulesForCounterparty(
        counterparty,
        flow,
      );
    }

    await _reloadAutoCategorizationState();
    _dataVersion += 1;
    notifyListeners();
  }

  bool _isLoanDebtManagedCategory(Category category) {
    return isLoanDebtCategory(category) || isRepaymentCategory(category);
  }

  Future<void> clearAutoCategorizationRuleForTransaction(
    Transaction transaction,
  ) async {
    if (!_autoCategorizationEnabled) return;

    final counterparty = resolvePrimaryCounterparty(transaction);
    if (counterparty == null) return;

    await _autoCategorizationService.deleteRulesForCounterparty(
      counterparty,
      autoCategorizationFlowForTransaction(transaction),
    );
    await _reloadAutoCategorizationState();
    _dataVersion += 1;
    notifyListeners();
  }

  Future<void> dismissAutoCategorizationPrompt(
    AutoCategorizationPromptDecision decision,
  ) async {
    await _autoCategorizationService.dismissPrompt(
      counterparty: decision.counterparty,
      flow: decision.flow,
    );
    await _reloadAutoCategorizationState();
    _dataVersion += 1;
    notifyListeners();
  }

  Future<void> deleteAutoCategorizationRule(
    AutoCategorizationRule rule,
  ) async {
    final id = rule.id;
    if (id == null) return;
    await _autoCategorizationService.deleteRule(id);
    await _reloadAutoCategorizationState();
    _dataVersion += 1;
    notifyListeners();
  }

  Future<void> clearAutoCategoryPromptDismissal(
    AutoCategoryPromptDismissal dismissal,
  ) async {
    final id = dismissal.id;
    if (id != null) {
      await _autoCategorizationService.clearPromptDismissalById(id);
    } else {
      await _autoCategorizationService.clearPromptDismissal(
        counterparty: dismissal.counterparty,
        flow: dismissal.flow,
      );
    }
    await _reloadAutoCategorizationState();
    _dataVersion += 1;
    notifyListeners();
  }

  Future<void> setAutoCategorizationEnabled(bool enabled) async {
    if (_autoCategorizationEnabled == enabled) return;
    await NotificationSettingsService.instance
        .setAutoCategorizationEnabled(enabled);
    _autoCategorizationEnabled = enabled;
    _dataVersion += 1;
    notifyListeners();
  }

  /// Apply auto-categorization to existing uncategorized transactions
  Future<int> applyAutoCategorizationToExisting() async {
    if (!_autoCategorizationEnabled) return 0;

    // Get all uncategorized transactions
    final uncategorizedTransactions = _allTransactions
        .where((t) => t.categoryId == null)
        .where((t) =>
            (t.receiver != null && t.receiver!.isNotEmpty) ||
            (t.creditor != null && t.creditor!.isNotEmpty))
        .toList();

    int updatedCount = 0;
    final batch = <Transaction>[];

    for (final transaction in uncategorizedTransactions) {
      final selection =
          await _autoCategorizationService.getCategorySelectionForTransaction(
        type: transaction.type,
        receiver: transaction.receiver,
        creditor: transaction.creditor,
      );

      if (selection != null && !selection.isEmpty) {
        batch.add(
          transaction.copyWith(
            categoryId: selection.primaryCategoryId,
            categoryIds: selection.categoryIds,
          ),
        );
        updatedCount++;
      }
    }

    // Save all updated transactions
    if (batch.isNotEmpty) {
      for (final transaction in batch) {
        await _transactionRepo.saveTransaction(transaction);
      }
      await loadData();
    }

    return updatedCount;
  }
}
