import 'package:totals/models/budget.dart';
import 'package:totals/repositories/budget_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';

class BudgetService {
  final BudgetRepository _budgetRepository = BudgetRepository();
  final TransactionRepository _transactionRepository = TransactionRepository();

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

    if (ids.isNotEmpty) {
      final filtered = transactions
          .where((t) => t.selectedCategoryIds.any(ids.contains))
          .toList();
      return filtered.fold<double>(0.0, (sum, t) => sum + t.amount.abs());
    }

    return transactions.fold<double>(0.0, (sum, t) => sum + t.amount.abs());
  }

  // Calculate budget usage/spent amounts for a budget
  Future<BudgetStatus> getBudgetStatus(Budget budget) async {
    final periodStart = budget.getCurrentPeriodStart();
    final periodEnd = budget.getCurrentPeriodEnd();

    final spent = await calculateSpending(
      startDate: periodStart,
      endDate: periodEnd,
      categoryId: budget.categoryId,
      categoryIds: budget.categoryIds,
    );

    final remaining = budget.amount - spent;
    final percentageUsed =
        budget.amount > 0 ? (spent / budget.amount) * 100 : 0.0;
    final isExceeded = spent > budget.amount;
    final isApproachingLimit = percentageUsed >= budget.alertThreshold;

    return BudgetStatus(
      budget: budget,
      spent: spent,
      remaining: remaining,
      percentageUsed: percentageUsed,
      isExceeded: isExceeded,
      isApproachingLimit: isApproachingLimit,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }

  // Get all active budgets with their status
  Future<List<BudgetStatus>> getAllBudgetStatuses({String? calendar}) async {
    final budgets = await _budgetRepository.getActiveBudgets(
      calendar: calendar,
    );
    final statuses = <BudgetStatus>[];

    for (final budget in budgets) {
      final status = await getBudgetStatus(budget);
      statuses.add(status);
    }

    return statuses;
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
    final statuses = <BudgetStatus>[];

    for (final budget in budgets) {
      final status = await getBudgetStatus(budget);
      statuses.add(status);
    }

    return statuses;
  }

  // Get category budgets with status
  Future<List<BudgetStatus>> getCategoryBudgetStatuses({
    String? calendar,
  }) async {
    final budgets = await _budgetRepository.getCategoryBudgets(
      calendar: calendar,
    );
    final statuses = <BudgetStatus>[];

    for (final budget in budgets) {
      final status = await getBudgetStatus(budget);
      statuses.add(status);
    }

    return statuses;
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
