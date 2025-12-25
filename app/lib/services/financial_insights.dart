import 'dart:math';

import 'package:totals/models/category.dart';

import '../models/transaction.dart';
import '../utils/math_utils.dart';

class InsightsService {
  const int _scoreVersion = 2; // v1 = no categories, v2 = category aware.
  final List<Transaction> Function() _getTransactions;

  // function that maps categoryId to Category?
  final Category? Function(int? categoryId)? _getCategoryById;

  // small memoization cache, will be cleared
  // when transactions change
  Map<String, dynamic>? _cache;

  InsightsService(this._getTransactions,
      {Category? Function(int? categoryId)? getCategoryById})
      : _getCategoryById = getCategoryById;

  void invalidate() => _cache = null;

  Map<String, dynamic> summarize() {
    if (_cache != null) return _cache!;

    final transactions = _getTransactions();

    // use the existing type + sign approach
    // to split income/expense
    final income = transactions.where(_isIncome).toList();
    final totalIncome = MathUtils.findTransactionSum(income);

    final expenses = transactions.where((t) => !_isIncome(t)).toList();
    final expensesAbs = transactions
        .where((t) => !_isIncome(t))
        .map((t) => t.amount.abs())
        .toList();

    final categoryBreakdown = _computeCategorySpend(transactions);
    final totalExpense = MathUtils.findSum(expensesAbs);

    final double categorizedTotal =
        categoryBreakdown.essential + categoryBreakdown.nonEssential;
    final categorizedCoverage = totalExpense == 0
        ? 0.0
        : (categorizedTotal / totalExpense).clamp(0.0, 1.0);

    final double essentialsRatio = categorizedTotal == 0
        ? 0.0
        : (categoryBreakdown.essential / categorizedTotal).clamp(0.0, 1.0);

    final patterns = _spendingPatterns(transactions);
    // we add these to the summary map so that the UI
    // can use them later.
    patterns["essentialsRatio"] = essentialsRatio;
    patterns["categorizedCoverage"] = categorizedCoverage;
    patterns["essentialSpend"] = categoryBreakdown.essential;
    patterns["nonEssentialSpend"] = categoryBreakdown.nonEssential;
    patterns["uncategorizedSpend"] = categoryBreakdown.uncategorized;

    final recurring = _recurring(expenses);
    final anomalies = _anomalies(expenses);
    final incomeAnomalies = _anomalies(income);
    final projections = _projections(income, expenses);

    final score = _healthScore(
      income: totalIncome,
      expense: totalExpense,
      savingsRate: _savingsRate(totalIncome, totalExpense),
      variance: patterns["spendVariance"].toDouble(),
      stabilityIndex: patterns["stablityIndex"].toDouble(),
      essentialsRatio: patterns["essentialsRatio"].toDouble(),
      categorizedCoverage: patterns["categorizedCoverate"].toDouble(),
      // essentialsRatio removed from health score calculation
      // Will be improved in the future when better categorization is available
    );

    final budget = _budgetSuggestions(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      categoryTotals: patterns['byCategory'] as Map<String, double>,
      essentialsSpend: patterns['essentialSpend'] as double,
      nonEssentialsSpend: patterns['nonEssentialSpend'] as double,
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
          DateTime.now().subtract(const Duration(days: 30));
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
    required double essentialsSpend,
    required double nonEssentialsSpend,
  }) {
    // baseline 50/30/20, overspend flags on per-category wantslike bucket.
    final needsCap = totalIncome * 0.5;
    final wantsCap = totalIncome * 0.3;
    final saveTarget = totalIncome * 0.2;

    final actualNeeds = essentialsSpend;
    final actualWants = nonEssentialsSpend;
    final estimatedSavings =
        (totalIncome - totalExpense).clamp(-double.infinity, double.infinity);

    final Map<String, double> overspend = {};
    if (actualWants > wantsCap) {
      overspend['wants'] = actualWants - wantsCap;
      overspend['needs'] = actualNeeds - needsCap;
    }

    String tip = '';
    if (totalExpense > totalIncome) {
      tip =
          'You\'re spending more than you earn. Try reducing wants first, then look at long-term ways to lower fixed(essential) costs.';
    } else if (overspend.containsKey('wants')) {
      tip =
          'Your lifestyle spending (wants) is above the usual 30% guielne. Cutting a few non-essentials can free up more savings';
    } else if (estimatedSavings < saveTarget) {
      tip =
          'You are saving, but below the common 20% goal. Consider slowly increasing your monthly savings';
    } else {
      tip =
          'Great job. Your spending and savings are close to common 50/30/20 guidelines';
    }

    return {
      'targets': {
        'needs': needsCap,
        'wants': wantsCap,
        'savings': saveTarget,
      },
      'overspend': overspend,
      'tip': tip,
    };
  }

  String _categoryFor(Transaction txn) {
    if (_isIncome(txn)) return "CREDIT";
    if (_isExpense(txn)) return "DEBIT";
    return "DEBIT";
  }

  _CategorySpendBreakdown _computeCategorySpend(List<Transaction> txns) {
    double essential = 0;
    double nonEssential = 0;
    double uncategorized = 0;

    for (final t in txns) {
      if (_isIncome(t)) continue; // we only care about expenses here

      final amount = t.amount.abs(); // we take the absolute value
      final category = _getCategoryById?.call(t.categoryId);

      if (category == null) {
        uncategorized += amount;
        continue;
      }

      // if an "income" category is attached to an expense
      if (category.flow.toLowerCase() == "income") {
        nonEssential += amount;
        continue;
      }

      if (category.essential) {
        essential += amount;
      } else {
        nonEssential += amount;
      }
    }

    return _CategorySpendBreakdown(
      essential: essential,
      nonEssential: nonEssential,
      uncategorized: uncategorized,
    );
  }

  Map<String, dynamic> _healthScore({
    required double income,
    required double expense,
    required double savingsRate,
    required double variance,
    required double stabilityIndex,
    required double essentialsRatio,
    required double categorizedCoverage,
  }) {
    // weighted blend: spend discipline, savings, stability
    // new calculation for the health score, includes the essentials spend
    // deriving it from the app's categories.

    final expenseIncomeRatio =
        income == 0 ? 1.0 : (expense / income).clamp(0, 2);

    // coverage factor for essentials influence
    // i.e. how much of the sms messages have been
    // categorized. In most cases, at this early stage of the app,
    // users will have categorized only a small percentage of the sms messages,
    // so the rest will be "uncategorized". This will affect the calculatioin
    // of the financial health score. So we will make sure that it will not make
    // the results biased, by using the coverage factor to derive 
    // the essentials component of the equation.
    double coverageFactor = 0.1;
    if (categorizedCoverage < 0.3) {
      coverageFactor = 0.0;
    } else if (categorizedCoverage > 0.7) {
      coverageFactor = 0.5;
    } else {
      coverageFactor = 1.0;
    }

    final essentialsComponent =
        (1 - essentialsRatio).clamp(0.0, 0.1) * coverageFactor;

    double score = 0.40 * (1 - expenseIncomeRatio.clamp(0, 1)) +
        0.30 * savingsRate.clamp(0, 1) +
        0.20 * stabilityIndex.clamp(0, 1) +
        0.10 * essentialsComponent;

    return {'value': (score * 100).clamp(0, 100).round()};
  }

  bool _isExpense(Transaction t) {
    final type = t.type?.toUpperCase() ?? '';

    // Prefer explicit type when available
    if (type.contains("DEBIT")) return true;
    if (type.contains("CREDIT")) return false;

    // Fallback to sign only when type is unknown
    return t.amount < 0;
  }

  bool _isIncome(Transaction t) {
    final type = t.type?.toUpperCase() ?? '';

    // Prefer explicit type when available
    if (type.contains("CREDIT")) return true;
    if (type.contains("DEBIT")) return false;

    // Fallback to sign only when type is unknown
    return t.amount >= 0;
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

    // variance shows how volatile our spending is.
    // we scale the amounts down so that we work in thousands
    // this is because the variance can get very high,
    // even in the millions.
    final amounts = txns.map((txn) => txn.amount / 1000.0).toList();
    final variance = MathUtils.findVariance(amounts);

    // then we convert the varaince into a stability index between
    // 0 and 1. we will tweak "k" after seing real data (e.g. k = 5 or 10)
    const double k = 5.0;
    final double stabilityIndex = 1 / (1 + (variance / k));

    return {
      'spendVariance': variance.toDouble(),
      'stabilityIndex': stabilityIndex.clamp(0.0, 1.0),
    };
  }

  double _trend(List<Transaction> txns) {
    // last month minus previous month.
    // returns 0 when data is insufficient.
    final Map<String, double> byMonth = {};

    for (final t in txns) {
      // parse from ISO string.
      final txnDate = DateTime.tryParse(t.time ?? '') ??
          DateTime.now().subtract(const Duration(days: 30));

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

class _CategorySpendBreakdown {
  final double essential;
  final double nonEssential;
  final double uncategorized;

  _CategorySpendBreakdown({
    required this.essential,
    required this.nonEssential,
    required this.uncategorized,
  });
}
