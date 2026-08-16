import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/repositories/reimbursement_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/owned_account_transfer_service.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/utils/reimbursement_utils.dart';
import 'package:totals/utils/transaction_amounts.dart';

class CategoryExpense {
  final int categoryId;
  final String name;
  final double amount;
  final String colorHex;

  CategoryExpense({
    required this.categoryId,
    required this.name,
    required this.amount,
    required this.colorHex,
  });

  Map<String, dynamic> toJson() => {
        'categoryId': categoryId,
        'name': name,
        'amount': amount,
        'colorHex': colorHex,
      };
}

class WidgetDataProvider {
  final TransactionRepository _transactionRepository;
  final AccountRepository _accountRepository;
  final CategoryRepository _categoryRepository;
  final BankConfigService _bankConfigService;
  final OwnedAccountTransferService _ownedAccountTransferService;
  final ReimbursementRepository _reimbursementRepository;

  static const List<String> _rankColors = [
    '#5AC8FA',
    '#FFB347',
    '#EF4444',
  ];

  WidgetDataProvider({
    TransactionRepository? transactionRepository,
    AccountRepository? accountRepository,
    CategoryRepository? categoryRepository,
    BankConfigService? bankConfigService,
    OwnedAccountTransferService? ownedAccountTransferService,
    ReimbursementRepository? reimbursementRepository,
  })  : _transactionRepository =
            transactionRepository ?? TransactionRepository(),
        _accountRepository = accountRepository ?? AccountRepository(),
        _categoryRepository = categoryRepository ?? CategoryRepository(),
        _bankConfigService = bankConfigService ?? BankConfigService(),
        _ownedAccountTransferService =
            ownedAccountTransferService ?? OwnedAccountTransferService(),
        _reimbursementRepository =
            reimbursementRepository ?? ReimbursementRepository();

  Future<List<Transaction>> _getTransactionsByTypeForRange(
    String type,
    DateTime start,
    DateTime end,
  ) async {
    final transactions =
        await _transactionRepository.getTransactionsByDateRange(
      start,
      end,
      type: type,
    );

    return _filterOutSelfTransfers(transactions);
  }

  Future<List<Transaction>> _getTodayTransactionsByType(String type) async {
    final now = DateTime.now();
    final startOfDay = _startOfDay(now);
    final endOfDay = _endOfDay(now);
    return _getTransactionsByTypeForRange(type, startOfDay, endOfDay);
  }

  Future<List<Transaction>> _getTodayDebitTransactions() async {
    return _getTodayTransactionsByType('DEBIT');
  }

  Future<List<Transaction>> _getTodayCreditTransactions() async {
    return _getTodayTransactionsByType('CREDIT');
  }

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  DateTime _startOfWeek(DateTime date) {
    final startOfDay = _startOfDay(date);
    return startOfDay.subtract(Duration(days: date.weekday - DateTime.monday));
  }

  DateTime _startOfMonth(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }

  Future<List<Transaction>> _filterOutSelfTransfers(
    List<Transaction> transactions,
  ) async {
    if (transactions.isEmpty) return transactions;
    final allTransactions = await _transactionRepository.getTransactions();
    final selfTransferReferences =
        await _buildSelfTransferReferences(allTransactions);
    final manualSelfCategoryIds = await _loadManualSelfCategoryIds();
    if (selfTransferReferences.isEmpty && manualSelfCategoryIds.isEmpty) {
      return transactions;
    }

    final filtered = <Transaction>[];
    for (final transaction in transactions) {
      final isSelfTransfer =
          selfTransferReferences.contains(transaction.reference) ||
              _isManualSelfTransfer(transaction, manualSelfCategoryIds);
      if (!isSelfTransfer || _shouldKeepForWidgetTotals(transaction)) {
        filtered.add(transaction);
        continue;
      }
      if (transaction.type == 'DEBIT' &&
          transactionFeeAmount(transaction) > 0) {
        filtered.add(transaction.copyWith(amount: 0));
      }
    }
    return filtered;
  }

  bool _shouldKeepForWidgetTotals(Transaction transaction) {
    // Manual cash expenses should always contribute to spending totals.
    // Self-transfer heuristics can occasionally flag overlapping references,
    // which would hide valid cash expenses from the widget.
    return transaction.bankId == CashConstants.bankId &&
        transaction.type == 'DEBIT';
  }

  Future<Set<String>> _buildSelfTransferReferences(
    List<Transaction> transactions,
  ) async {
    if (transactions.isEmpty) return <String>{};
    final banks = await _bankConfigService.getBanks();
    final accounts = await _accountRepository.getAccounts();
    final matches = _ownedAccountTransferService.findMatches(
      transactions: transactions,
      banks: banks,
      accounts: accounts,
    );
    final references = <String>{};

    for (final match in matches) {
      references
        ..add(match.debitTransaction.reference)
        ..add(match.creditTransaction.reference);
    }
    references.addAll(_buildCashTransferReferences(transactions));
    return references;
  }

  Set<String> _buildCashTransferReferences(
    List<Transaction> transactions,
  ) {
    final references = <String>{};
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
      references
        ..add(reference)
        ..add(linkedReference);
    }

    return references;
  }

  Future<Set<int>> _loadManualSelfCategoryIds() async {
    final categories = await _categoryRepository.getCategories();
    return categories
        .where((category) => category.name.trim().toLowerCase() == 'self')
        .map((category) => category.id)
        .whereType<int>()
        .toSet();
  }

  bool _isManualSelfTransfer(
    Transaction transaction,
    Set<int> manualSelfCategoryIds,
  ) {
    final categoryId = transaction.categoryId;
    if (categoryId == null) return false;
    return manualSelfCategoryIds.contains(categoryId);
  }

  Future<List<CategoryExpense>> _buildCategoryBreakdown(
    List<Transaction> transactions,
  ) async {
    final categories = await _categoryRepository.getCategories();
    final categoryMap = {for (final c in categories) c.id: c};
    final reimbursedByReference =
        await _reimbursementRepository.getAppliedTotalsForExpenses(
      transactions
          .where((transaction) => transaction.type == 'DEBIT')
          .map((transaction) => transaction.reference),
    );

    final Map<int, double> categoryTotals = {};
    for (final tx in transactions) {
      final catId = tx.categoryId ?? 0;
      final amount = tx.type == 'DEBIT'
          ? transactionNetExpenseAmount(
              tx,
              isSelfTransfer: false,
              reimbursedAmount:
                  reimbursedByReference[tx.reference.trim()] ?? 0.0,
            )
          : tx.amount;
      if (amount <= 0) continue;
      categoryTotals[catId] = (categoryTotals[catId] ?? 0) + amount;
    }

    final sortedEntries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topEntries = sortedEntries.take(3).toList();
    return topEntries.asMap().entries.map((entry) {
      final rank = entry.key;
      final categoryEntry = entry.value;
      final category = categoryMap[categoryEntry.key];
      final colorHex = _rankColors[rank % _rankColors.length];
      return CategoryExpense(
        categoryId: categoryEntry.key,
        name: category?.name ?? 'Uncategorized',
        amount: categoryEntry.value,
        colorHex: colorHex,
      );
    }).toList();
  }

  Future<List<CategoryExpense>> getTodayCategoryBreakdown() async {
    final transactions = await _getTodayDebitTransactions();
    return _buildCategoryBreakdown(transactions);
  }

  Future<List<CategoryExpense>> getTodayIncomeCategoryBreakdown() async {
    final transactions = await _getTodayCreditTransactions();
    return _buildCategoryBreakdown(transactions);
  }

  /// Get today's total spending (DEBIT transactions only)
  Future<double> getTodaySpending() async {
    final now = DateTime.now();
    return getSpendingForRange(
      _startOfDay(now),
      _endOfDay(now),
    );
  }

  Future<double> getSpendingForRange(DateTime start, DateTime end) async {
    final transactions = await _getTransactionsByTypeForRange(
      'DEBIT',
      start,
      end,
    );
    final reimbursedByReference =
        await _reimbursementRepository.getAppliedTotalsForExpenses(
      transactions.map((transaction) => transaction.reference),
    );
    return transactions.fold<double>(
      0.0,
      (sum, tx) =>
          sum +
          transactionNetExpenseAmount(
            tx,
            isSelfTransfer: false,
            reimbursedAmount: reimbursedByReference[tx.reference.trim()] ?? 0.0,
          ),
    );
  }

  Future<double> getLastCompletedWeekSpending({DateTime? now}) async {
    final anchor = now ?? DateTime.now();
    final currentWeekStart = _startOfWeek(anchor);
    final lastWeekStart = currentWeekStart.subtract(const Duration(days: 7));
    final lastWeekEnd =
        _endOfDay(currentWeekStart.subtract(const Duration(days: 1)));
    return getSpendingForRange(lastWeekStart, lastWeekEnd);
  }

  Future<double> getCurrentWeekSpending({DateTime? now}) async {
    final anchor = now ?? DateTime.now();
    return getSpendingForRange(
      _startOfWeek(anchor),
      _endOfDay(anchor),
    );
  }

  Future<double> getLastCompletedMonthSpending({DateTime? now}) async {
    final anchor = now ?? DateTime.now();
    final currentMonthStart = _startOfMonth(anchor);
    final lastMonthDate = currentMonthStart.subtract(const Duration(days: 1));
    final lastMonthStart = _startOfMonth(lastMonthDate);
    final lastMonthEnd = _endOfDay(lastMonthDate);
    return getSpendingForRange(lastMonthStart, lastMonthEnd);
  }

  Future<double> getCurrentMonthSpending({DateTime? now}) async {
    final anchor = now ?? DateTime.now();
    return getSpendingForRange(
      _startOfMonth(anchor),
      _endOfDay(anchor),
    );
  }

  /// Get today's total income (CREDIT transactions only)
  Future<double> getTodayIncome() async {
    final transactions = await _getTodayCreditTransactions();
    final reimbursementCategoryIds = (await _categoryRepository.getCategories())
        .where(isReimbursementCategory)
        .map((category) => category.id)
        .whereType<int>()
        .toSet();
    final linkedReferences =
        await _reimbursementRepository.getLinkedReimbursementReferences(
      transactions.map((transaction) => transaction.reference),
    );

    return transactions.fold<double>(
      0.0,
      (sum, transaction) {
        final isReimbursement =
            linkedReferences.contains(transaction.reference.trim()) ||
                transaction.selectedCategoryIds
                    .any(reimbursementCategoryIds.contains);
        return sum + (isReimbursement ? 0.0 : transaction.amount);
      },
    );
  }

  /// Format amount for widget display
  String formatAmountForWidget(double amount) {
    if (amount.abs() >= 1000) {
      final abbreviated = formatNumberAbbreviated(amount).replaceAll(' ', '');
      return '$abbreviated ETB';
    }

    final rounded = amount.roundToDouble();
    final formatted =
        formatNumberWithComma(rounded).replaceFirst(RegExp(r'\.00$'), '');
    return '$formatted ETB';
  }

  /// Get formatted timestamp
  String getLastUpdatedTimestamp() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$month/$day, $hour:$minute';
  }
}
