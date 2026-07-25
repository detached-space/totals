import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/screens/transactions_for_period_page.dart';
import 'package:totals/services/financial_insights.dart';
import 'package:totals/widgets/insights/insights_explainer_bottomsheet.dart';
import 'package:totals/constants/cash_constants.dart';

import '../utils/map_keys.dart';

class InsightsPage extends StatelessWidget {
  final List<Transaction> transactions;
  final String? periodLabel;

  const InsightsPage({
    super.key,
    required this.transactions,
    this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final insightsService = InsightsService(
      () => transactions,
      getCategoryById: txProvider.getCategoryById,
      isExcludedFromIncome: txProvider.isReimbursementTransaction,
    );

    final insights = insightsService.summarize();
    final score =
        (insights[MapKeys.score] as Map<String, dynamic>)['value'] as int;
    final projections = insights[MapKeys.projections] as Map<String, dynamic>;
    final budget = insights[MapKeys.budget] as Map<String, dynamic>;
    final patterns = insights[MapKeys.patterns] as Map<String, dynamic>;
    final recurring = insights[MapKeys.recurring] as List<dynamic>;
    final anomalies = insights[MapKeys.anomalies] as List<Transaction>;
    final incomeAnomalies =
        insights[MapKeys.incomeAnomalies] as List<Transaction>;
    final totalIncome = _toDouble(insights[MapKeys.totalIncome]);
    final totalExpense = _toDouble(insights[MapKeys.totalExpense]);

    final formatter = NumberFormat.currency(symbol: 'ETB ', decimalDigits: 2);

    final double categorizedCoverage =
        _toDouble(patterns[MapKeys.categorizedCoverage]);
    final bool lowCoverage = categorizedCoverage < 0.7;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: Text(
          'Financial Insights',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                Icons.help_outline_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
              tooltip: 'Learn More',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const InsightsExplainerBottomSheet(),
                );
              },
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: Stack(
          children: [
            // Decorative background elements
            Positioned(
              top: -100,
              right: -50,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      Theme.of(context).colorScheme.primary.withOpacity(0.05),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      Theme.of(context).colorScheme.secondary.withOpacity(0.03),
                ),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (periodLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24, left: 2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            periodLabel!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),

                    // Categorization Banner
                    if (lowCoverage) ...[
                      _buildModernCategorizationBanner(
                        context,
                        categorizedCoverage,
                        transactions,
                        txProvider,
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Health Score Section
                    _buildModernScoreCard(context, score,
                        lowCoverage: lowCoverage),
                    const SizedBox(height: 24),

                    // Stability and Cashflow Section
                    _buildStabilityAndCashflowSection(
                      context,
                      _toDouble(patterns[MapKeys.spendVariance]),
                      totalIncome,
                      totalExpense,
                      formatter,
                    ),
                    const SizedBox(height: 24),

                    // Projections Section
                    _buildGlassSection(
                      context,
                      'Projections',
                      Icons.auto_graph_rounded,
                      [
                        _buildInfoRow(
                          context,
                          'Projected Income',
                          formatter.format(
                            _toDouble(projections['projectedIncome']),
                          ),
                        ),
                        _buildInfoRow(
                          context,
                          'Projected Expense',
                          formatter.format(
                            _toDouble(projections['projectedExpense']),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Divider(height: 1, thickness: 0.5),
                        ),
                        _buildInfoRow(
                          context,
                          'Estimated Savings',
                          formatter.format(
                            _toDouble(projections['projectedSavings']),
                          ),
                          isHighlight: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Budget Tips
                    _buildGlassSection(
                      context,
                      'Financial Intelligence',
                      Icons.tips_and_updates_rounded,
                      [
                        Text(
                          budget['tip'] as String,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Spending Patterns
                    if (patterns['spendVariance'] != null) ...[
                      _buildGlassSection(
                        context,
                        'Spending Anatomy',
                        Icons.pie_chart_rounded,
                        [
                          ...(patterns[MapKeys.byCategory]
                                  as Map<String, dynamic>)
                              .entries
                              .map(
                            (entry) {
                              final label = entry.key;
                              final value = _toDouble(entry.value);
                              String suffix = '';

                              if (totalExpense > 0 && label != 'CREDIT') {
                                final pct = (value / totalExpense) * 100;
                                suffix = ' (${pct.toStringAsFixed(1)}%)';
                              }

                              return _buildInfoRow(
                                context,
                                label,
                                '${formatter.format(value)}$suffix',
                              );
                            },
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(height: 1, thickness: 0.5),
                          ),
                          _buildInfoRow(
                            context,
                            'Stability Index',
                            _formatLargeNumber(
                                _toDouble(patterns[MapKeys.stabilityIndex])),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Unusual Transactions
                    _buildUnusualSection(
                      context,
                      anomalies,
                      incomeAnomalies,
                      formatter,
                    ),
                    const SizedBox(height: 24),

                    // Recurring Expenses
                    if (recurring.isNotEmpty) ...[
                      _ExpandableRecurringCard(
                        recurring: recurring,
                        formatter: formatter,
                        toDouble: _toDouble,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _bankLabel(int? bankId) {
    if (bankId == null) return 'Unknown bank';
    if (bankId == CashConstants.bankId) {
      return CashConstants.bankShortName;
    }
    for (final bank in AppConstants.banks) {
      if (bank.id == bankId) return bank.shortName;
    }
    return 'Bank($bankId)';
  }

  Widget _buildModernCategorizationBanner(
    BuildContext context,
    double categorizedCoverage,
    List<Transaction> transactions,
    TransactionProvider provider,
  ) {
    final coveragePercent = (categorizedCoverage * 100).toStringAsFixed(0);
    final uncategorizedCount = transactions.where((t) {
      return !_isIncome(t) && t.categoryId == null;
    }).length;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -20,
              child: Icon(
                Icons.account_balance_wallet_rounded,
                size: 120,
                color: Colors.white.withOpacity(0.12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome_rounded,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Coverage: $coveragePercent%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Precision requires data',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Categorize $uncategorizedCount more transactions to unlock deeper financial intelligence.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      final uncategorizedTransactions = transactions.where((t) {
                        return !_isIncome(t) && t.categoryId == null;
                      }).toList();

                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TransactionsForPeriodPage(
                            transactions: uncategorizedTransactions.isEmpty
                                ? transactions
                                : uncategorizedTransactions,
                            provider: provider,
                            title: uncategorizedTransactions.isEmpty
                                ? 'All Transactions'
                                : 'Needs Categorization',
                            subtitle: uncategorizedTransactions.isEmpty
                                ? null
                                : '$uncategorizedCount items pending',
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Categorize Now',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernScoreCard(BuildContext context, int score,
      {bool lowCoverage = false}) {
    Color scoreColor;
    String statusLabel;
    IconData statusIcon;

    if (score >= 80) {
      scoreColor = const Color(0xFF00C853);
      statusLabel = 'Excellent';
      statusIcon = Icons.verified_rounded;
    } else if (score >= 60) {
      scoreColor = const Color(0xFFFFB300);
      statusLabel = 'Good';
      statusIcon = Icons.info_rounded;
    } else {
      scoreColor = const Color(0xFFFF5252);
      statusLabel = 'Needs Attention';
      statusIcon = Icons.warning_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FINANCIAL HEALTH',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: scoreColor,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(statusIcon, color: scoreColor, size: 24),
                    ],
                  ),
                ],
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 10,
                      backgroundColor: scoreColor.withOpacity(0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (lowCoverage) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.insights_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Accuracy will improve as you categorize more transactions.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStabilityAndCashflowSection(
    BuildContext context,
    double variance,
    double income,
    double expense,
    NumberFormat formatter,
  ) {
    String stabilityLabel;
    Color stabilityColor;
    if (variance < 50000) {
      stabilityLabel = 'Highly Stable';
      stabilityColor = const Color(0xFF00C853);
    } else if (variance < 500000) {
      stabilityLabel = 'Moderate';
      stabilityColor = const Color(0xFFFFB300);
    } else {
      stabilityLabel = 'Volatile';
      stabilityColor = const Color(0xFFFF5252);
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildBalanceTile(
                context,
                'TOTAL INCOME',
                formatter.format(income),
                Icons.south_west_rounded,
                const Color(0xFF00C853),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildBalanceTile(
                context,
                'TOTAL EXPENSE',
                formatter.format(expense),
                Icons.north_east_rounded,
                const Color(0xFFFF5252),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: stabilityColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.analytics_rounded,
                    color: stabilityColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SPENDING STABILITY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stabilityLabel,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: stabilityColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceTile(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassSection(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    color: Theme.of(context).colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildUnusualSection(
    BuildContext context,
    List<Transaction> expenses,
    List<Transaction> income,
    NumberFormat formatter,
  ) {
    if (expenses.isEmpty && income.isEmpty) {
      return _buildGlassSection(
        context,
        'Unusual Activity',
        Icons.warning_amber_rounded,
        [
          Text(
            'High transaction stability. No unusual activity detected in this period.',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return _buildGlassSection(
      context,
      'Unusual Activity',
      Icons.warning_amber_rounded,
      [
        if (expenses.isNotEmpty) ...[
          Text(
            'EXPENSES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: const Color(0xFFFF5252).withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 12),
          ...expenses.take(3).map((t) =>
              _buildTransactionRow(context, t, formatter, isIncome: false)),
          if (income.isNotEmpty) const SizedBox(height: 20),
        ],
        if (income.isNotEmpty) ...[
          Text(
            'INCOME',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: const Color(0xFF00C853).withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 12),
          ...income.take(3).map((t) =>
              _buildTransactionRow(context, t, formatter, isIncome: true)),
        ],
      ],
    );
  }

  Widget _buildTransactionRow(
    BuildContext context,
    Transaction t,
    NumberFormat formatter, {
    required bool isIncome,
  }) {
    final color = isIncome ? const Color(0xFF00C853) : const Color(0xFFFF5252);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bankLabel(t.bankId),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _dateLabel(t.time),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatter.format(t.amount),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    bool isHighlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isHighlight
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.8),
                fontWeight: isHighlight ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isHighlight
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel(String? isoTime) {
    if (isoTime == null) return 'Unknown date';
    try {
      return DateFormat('MMM d, y').format(DateTime.parse(isoTime));
    } catch (_) {
      return 'Unknown date';
    }
  }

  String _formatLargeNumber(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)}K';
    }
    return value.toStringAsFixed(2);
  }

  bool _isIncome(Transaction t) {
    try {
      final type = t.type?.toUpperCase() ?? '';
      if (type.contains("CREDIT")) return true;
      if (type.contains("DEBIT")) return false;
      return t.amount >= 0;
    } catch (e) {
      return false;
    }
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}

class _ExpandableRecurringCard extends StatefulWidget {
  final List<dynamic> recurring;
  final NumberFormat formatter;
  final double Function(dynamic) toDouble;

  const _ExpandableRecurringCard({
    required this.recurring,
    required this.formatter,
    required this.toDouble,
  });

  @override
  State<_ExpandableRecurringCard> createState() =>
      _ExpandableRecurringCardState();
}

class _ExpandableRecurringCardState extends State<_ExpandableRecurringCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.repeat_rounded,
                        color: Theme.of(context).colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recurring Transactions',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          '${widget.recurring.length} regular payments detected',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: widget.recurring.map((item) {
                  final map = item as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            map['label'] as String,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              widget.formatter
                                  .format(widget.toDouble(map['avg'])),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${map['count']} payments',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
