import 'dart:math';

import '../models/transaction.dart';
import '../utils/math_utils.dart';

class InsightsService {
  final List<Transaction> Function() _getTransactions;

  // small memoization cache, will be cleared
  // when transactions change
  Map<String, dynamic>? _cache;

  InsightsService(this._getTransactions);
  void invalidate() => _cache = null;

  Map<String, dynamic> summarize() {
    if (_cache != null) return _cache!;

    final transactions = _getTransactions();

    // use the existing type + sign approach
    // to split income/expense
    final income = transactions.where(_isIncome).toList();

    final expenses = transactions.where((t) => !_isIncome(t)).toList();

    final totalIncome = MathUtils.findTransactionSum(income);
    final totalExpense = MathUtils.findTransactionSum(expenses);

    final patterns = _spendingPatterns(transactions);
    final recurring = _recurring(expenses);
    final anomalies = _anomalies(expenses);
    final incomeAnomalies = _anomalies(income);
    final projections = _projections(income, expenses);

    final score = _healthScore(
      income: totalIncome,
      expense: totalExpense,
      savingsRate: _savingsRate(totalIncome, totalExpense),
      variance: patterns["spendVariance"].toDouble(),
      essentialsRatio: patterns["essentialsRatio"].toDouble(),
    );

    final budget = _budgetSuggestions(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      categoryTotals: patterns['byCategory'] as Map<String, double>,
    );

    _cache = {
      "totalIncome": totalIncome,
      "totalExpense": totalExpense,
      "patterns": patterns,
      "recurring": recurring,
      "anomalies": anomalies,
      "incomeAnomalies": incomeAnomalies,
      "projections": projections,
      "score": score,
      "budget": budget,
    };
    return _cache!;
  }

  List<Transaction> _anomalies(List<Transaction> expenses) {
    // we use simple z-score. i.e.
    // expense with 2 standard deviations to the right of the mean
    // i.e. expense > mean + 2 * sd
    // such an expense will be flagged as an anomaly.

    if (expenses.length < 5) return [];
    final amounts = expenses.map((t) => t.amount).toList();
    final mean = MathUtils.findMean(amounts);
    final variance = MathUtils.findVariance(amounts);

    final sd = sqrt(variance); // standard deviation
    final limitValue = mean + 2 * sd;
    return expenses.where((exp) => exp.amount > limitValue).toList();
  }

  double _avgMonthly(List<Transaction> txns) {
    // we group them by year-month key to get monthly totals.

    if (txns.isEmpty) return 0;
    final Map<String, double> byMonth = {};

    for (final t in txns) {
      // parse from ISO string.
      final txnDate = DateTime.tryParse(t.time ?? '') ??
          DateTime.now().subtract(Duration(days: 30));
      final key = '${txnDate.year}-${txnDate.month}';

      byMonth[key] = (byMonth[key] ?? 0) + t.amount;
    }

    return byMonth.values.isEmpty
        ? 0
        : MathUtils.findMean(byMonth.values.toList());
  }

  Map<String, dynamic> _budgetSuggestions({
    required double totalIncome,
    required double totalExpense,
    required Map<String, double> categoryTotals,
  }) {
    // baseline 50/30/20, overspend flags on per-category wantslike bucket.
    final needsCap = totalIncome * 0.5;
    final wantsCap = totalIncome * 0.3;
    final saveTarget = totalIncome * 0.2;

    final overspend = <String, double>{};
    categoryTotals.forEach((cat, amount) {
      if (cat == "CREDIT") return;

      if (amount > wantsCap) overspend[cat] = amount - wantsCap;
    });

    return {
      'targets': {'needs': needsCap, 'wants': wantsCap, 'savings': saveTarget},
      'overspend': overspend,
      'tip': totalExpense > totalIncome
          ? 'Spending exceeds income; reduce your spending'
          : 'Good job keeping spending under income!',
    };
  }

  String _categoryFor(Transaction txn) {
    if (_isIncome(txn)) return "CREDIT";
    if (_isExpense(txn)) return "DEBIT";
    return "DEBIT";
  }

  Map<String, dynamic> _healthScore({
    required double income,
    required double expense,
    required double savingsRate,
    required double variance,
    required double essentialsRatio,
  }) {
    // weighted blend: spend discipline, savings, stability, flexibility

    final expenseIncomeRatio =
        income == 0 ? 1.0 : (expense / income).clamp(0, 2);

    final stability = 1 / (1 + variance);
    final essentials = 1 - essentialsRatio;

    double score = 0.35 * (1 - expenseIncomeRatio.clamp(0, 1)) +
        0.25 * savingsRate.clamp(0, 1) +
        0.20 * stability.clamp(0, 1) +
        0.20 * essentials.clamp(0, 1);

    return {'value': (score * 100).clamp(0, 100).round()};
  }

  bool _isIncome(Transaction t) {
    final type = t.type?.toUpperCase() ?? '';

    // Prefer explicit type when available
    if (type.contains("CREDIT")) return true;
    if (type.contains("DEBIT")) return false;

    // Fallback to sign only when type is unknown
    return t.amount >= 0;
  }

  bool _isExpense(Transaction t) {
    final type = t.type?.toUpperCase() ?? '';

    // Prefer explicit type when available
    if (type.contains("DEBIT")) return true;
    if (type.contains("CREDIT")) return false;

    // Fallback to sign only when type is unknown
    return t.amount < 0;
  }

  Map<String, dynamic> _projections(
    List<Transaction> income,
    List<Transaction> expenses,
  ) {
    // predictions/extrapolation for the future spending/income trends
    // of the user based on their transaction history.
    // method: blend average monthly and simple last-delta trend
    // for next-month estimate.

    double avgIncome = _avgMonthly(income);
    double avgExpense = _avgMonthly(expenses);

    final incomeTrend = _trend(income);
    final expenseTrend = _trend(expenses);

    final projectedIncome = avgIncome + incomeTrend;
    final projectedExpense = avgExpense + expenseTrend;
    final projectedSavings = projectedIncome - projectedExpense;

    return {
      'projectedIncome': projectedIncome,
      'projectedExpense': projectedExpense,
      'projectedSavings': projectedSavings,
    };
  }

  // recurring expenses.
  List<Map<String, dynamic>> _recurring(List<Transaction> expenses) {
    // detect repetition via reference prefix frequency;
    // we need 3+ hits.

    final Map<String, List<Transaction>> byRef = {};

    for (final tx in expenses) {
      final key = (tx.reference ?? '').split('-').first;
      if (key.isEmpty) continue;

      // lookup the value by that key, if it's not there add a new entry.
      byRef.putIfAbsent(key, () => []).add(tx);
    }

    return byRef.entries
        .where((exp) => exp.value.length >= 3)
        .map(
          (exp) => {
            'label': exp.key,
            'count': exp.value.length,
            'avg': MathUtils.findTransactionSum(exp.value) / exp.value.length,
          },
        )
        .toList();
  }

  double _savingsRate(double income, double expense) {
    // negative savings allowed but clampd to [-1, 1] for scoring.
    if (income <= 0) return 0;
    final savings = income - expense;
    return (savings / income).clamp(-1, 1);
  }

  Map<String, dynamic> _spendingPatterns(List<Transaction> txns) {
    final Map<String, double> byCategory = {};

    for (final txn in txns) {
      final cat = _categoryFor(txn);
      byCategory[cat] = (byCategory[cat] ?? 0) + (txn.amount);
    }

    final amounts = txns.map((txn) => txn.amount).toList();

    // variance shows how volatile our spending is.
    final variance = MathUtils.findVariance(amounts);

    // essentials ratio is how much we spend on essentials
    // for now it's placeholder value, in case we get better tags we
    // could more accurately calculate it.
    final essenSpends =
        txns.where((t) => !_isIncome(t)).map((t) => t.amount).toList();
    final essentialsSpend = MathUtils.findSum(essenSpends);

    final totalSpends =
        txns.where((t) => !_isIncome(t)).map((t) => t.amount).toList();
    final totalSpend = MathUtils.findSum(totalSpends);

    final essentialsRatio =
        totalSpend == 0 ? 0 : (essentialsSpend / totalSpend).clamp(0, 1);

    return {
      'byCategory': byCategory,
      'spendVariance': variance.toDouble(),
      'essentialsRatio': essentialsRatio,
    };
  }

  double _trend(List<Transaction> txns) {
    // last month minux previous month.
    // returns 0 when data is insufficient.
    final Map<String, double> byMonth = {};

    for (final t in txns) {
      // parse from ISO string.
      final txnDate = DateTime.tryParse(t.time ?? '') ??
          DateTime.now().subtract(Duration(days: 30));

      final key = '${txnDate.year}-${txnDate.month}';

      byMonth[key] = (byMonth[key] ?? 0) + t.amount;
    }

    final sorted = byMonth.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (sorted.length < 2) return 0;

    final last = sorted.last.value;
    final beforeLast = sorted[sorted.length - 2].value;

    return last - beforeLast;
  }
}
