import 'package:totals/models/budget.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/budget_repository.dart';
import 'package:totals/repositories/reimbursement_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/utils/transaction_amounts.dart';

class BudgetService {
  final BudgetRepository _budgetRepository = BudgetRepository();
  final TransactionRepository _transactionRepository = TransactionRepository();
  final ReimbursementRepository _reimbursementRepository =
      ReimbursementRepository();

  // Calculate spending for a given period and category
  Future<double> calculateSpending({
    required DateTime startDate,
    required DateTime endDate,
    int? categoryId,
    List<int>? categoryIds,
  }) async {
    final transactions =
        await _transactionRepository.getTransactionsByDateRange(
      startDate,
      endDate,
      type: 'DEBIT', // Only count expenses
    );

    final ids = <int>{};
    if (categoryIds != null) {
      ids.addAll(categoryIds.where((id) => id > 0));
    }
    if (categoryId != null && categoryId > 0) {
      ids.add(categoryId);
    }

    final filtered = ids.isEmpty
        ? transactions
        : transactions
            .where((transaction) =>
                transaction.selectedCategoryIds.any(ids.contains))
            .toList(growable: false);
    final reimbursedByReference =
        await _reimbursementRepository.getAppliedTotalsForExpenses(
      filtered.map((transaction) => transaction.reference),
    );
    return _sumNetSpending(
      filtered,
      reimbursedByReference,
    );
  }

  // Calculate budget usage/spent amounts for a budget
  Future<BudgetStatus> getBudgetStatus(Budget budget) async {
    return (await _getStatusesForBudgets(<Budget>[budget])).single;
  }

  // Get all active budgets with their status
  Future<List<BudgetStatus>> getAllBudgetStatuses({String? calendar}) async {
    final budgets = await _budgetRepository.getActiveBudgets(
      calendar: calendar,
    );
    return _getStatusesForBudgets(budgets);
  }

  // Get budgets by type with status
  Future<List<BudgetStatus>> getBudgetStatusesByType(
    String type, {
    String? calendar,
  }) async {
    final budgets = await _budgetRepository.getBudgetsByType(
      type,
      calendar: calendar,
    );
    return _getStatusesForBudgets(budgets);
  }

  // Get category budgets with status
  Future<List<BudgetStatus>> getCategoryBudgetStatuses({
    String? calendar,
  }) async {
    final budgets = await _budgetRepository.getCategoryBudgets(
      calendar: calendar,
    );
    return _getStatusesForBudgets(budgets);
  }

  Future<List<BudgetStatus>> _getStatusesForBudgets(
    List<Budget> budgets,
  ) async {
    if (budgets.isEmpty) return const <BudgetStatus>[];

    final requestsByPeriod = <String, List<_BudgetStatusRequest>>{};
    for (var index = 0; index < budgets.length; index++) {
      final budget = budgets[index];
      final periodStart = budget.getCurrentPeriodStart();
      final periodEnd = budget.getCurrentPeriodEnd();
      final periodKey = '${periodStart.microsecondsSinceEpoch}:'
          '${periodEnd.microsecondsSinceEpoch}';
      requestsByPeriod
          .putIfAbsent(periodKey, () => <_BudgetStatusRequest>[])
          .add(
            _BudgetStatusRequest(
              index: index,
              budget: budget,
              periodStart: periodStart,
              periodEnd: periodEnd,
            ),
          );
    }

    final statuses = List<BudgetStatus?>.filled(budgets.length, null);
    for (final requests in requestsByPeriod.values) {
      final periodStart = requests.first.periodStart;
      final periodEnd = requests.first.periodEnd;
      final transactions =
          await _transactionRepository.getTransactionsByDateRange(
        periodStart,
        periodEnd,
        type: 'DEBIT',
      );
      final reimbursedByReference =
          await _reimbursementRepository.getAppliedTotalsForExpenses(
        transactions.map((transaction) => transaction.reference),
      );

      for (final request in requests) {
        final categoryIds = request.budget.selectedCategoryIds.toSet();
        final applicableTransactions = categoryIds.isEmpty
            ? transactions
            : transactions.where(
                (transaction) =>
                    transaction.selectedCategoryIds.any(categoryIds.contains),
              );
        final spent = _sumNetSpending(
          applicableTransactions,
          reimbursedByReference,
        );
        statuses[request.index] = _buildStatus(
          request: request,
          spent: spent,
        );
      }
    }

    return List<BudgetStatus>.generate(
      statuses.length,
      (index) => statuses[index]!,
      growable: false,
    );
  }

  double _sumNetSpending(
    Iterable<Transaction> transactions,
    Map<String, double> reimbursedByReference,
  ) {
    return transactions.fold<double>(
      0.0,
      (sum, transaction) {
        final gross = transactionDebitOutflow(transaction);
        final reimbursed = reimbursedByReference[transaction.reference] ?? 0.0;
        final net = gross - reimbursed;
        return sum + (net <= 0 ? 0.0 : net);
      },
    );
  }

  BudgetStatus _buildStatus({
    required _BudgetStatusRequest request,
    required double spent,
  }) {
    final budget = request.budget;
    final remaining = budget.amount - spent;
    final percentageUsed =
        budget.amount > 0 ? (spent / budget.amount) * 100 : 0.0;
    return BudgetStatus(
      budget: budget,
      spent: spent,
      remaining: remaining,
      percentageUsed: percentageUsed,
      isExceeded: spent > budget.amount,
      isApproachingLimit: percentageUsed >= budget.alertThreshold,
      periodStart: request.periodStart,
      periodEnd: request.periodEnd,
    );
  }

  // Get budgets by category ID
  Future<List<Budget>> getBudgetsByCategory(
    int categoryId, {
    String? calendar,
  }) async {
    return await _budgetRepository.getBudgetsByCategory(
      categoryId,
      calendar: calendar,
    );
  }

  // Check if budget is exceeded or approaching limit
  Future<bool> isBudgetExceeded(Budget budget) async {
    final status = await getBudgetStatus(budget);
    return status.isExceeded;
  }

  Future<bool> isBudgetApproachingLimit(Budget budget) async {
    final status = await getBudgetStatus(budget);
    return status.isApproachingLimit;
  }

  // Handle budget rollover logic
  Future<void> handleBudgetRollover(Budget budget) async {
    if (!budget.rollover) return;

    final now = DateTime.now();
    final periodEnd = budget.getCurrentPeriodEnd();

    // If current period has ended, check for rollover
    if (now.isAfter(periodEnd)) {
      final status = await getBudgetStatus(budget);
      final remaining = status.remaining;

      if (remaining > 0) {
        // Create a new budget entry with rolled over amount
        final newStartDate = budget.getCurrentPeriodStart();
        final rolledOverBudget = budget.copyWith(
          id: null,
          amount: budget.amount + remaining,
          startDate: newStartDate,
          createdAt: DateTime.now(),
        );

        await _budgetRepository.insertBudget(rolledOverBudget);
      }
    }
  }
}

class _BudgetStatusRequest {
  final int index;
  final Budget budget;
  final DateTime periodStart;
  final DateTime periodEnd;

  const _BudgetStatusRequest({
    required this.index,
    required this.budget,
    required this.periodStart,
    required this.periodEnd,
  });
}

class BudgetStatus {
  final Budget budget;
  final double spent;
  final double remaining;
  final double percentageUsed;
  final bool isExceeded;
  final bool isApproachingLimit;
  final DateTime periodStart;
  final DateTime periodEnd;

  BudgetStatus({
    required this.budget,
    required this.spent,
    required this.remaining,
    required this.percentageUsed,
    required this.isExceeded,
    required this.isApproachingLimit,
    required this.periodStart,
    required this.periodEnd,
  });
}
