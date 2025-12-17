import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/financial_insights.dart';

class InsightsPage extends StatelessWidget {
  final List<Transaction> transactions;
  final String? periodLabel;

  const InsightsPage({
    super.key,
    required this.transactions,
    this.periodLabel,
  });

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String _bankLabel(int? bankId) {
    if (bankId == null) return 'Unknown bank';
    for (final bank in AppConstants.banks) {
      if (bank.id == bankId) return bank.shortName;
    }
    return 'Bank($bankId)';
  }

  String _dateLabel(String? isoTime) {
    if (isoTime == null) return 'Unknown date';
    try {
      return DateFormat('MMM d').format(DateTime.parse(isoTime));
    } catch (_) {
      return 'Unknown date';
    }
  }

  @override
  Widget build(BuildContext context) {
    final insightsService = InsightsService(() => transactions);
    final insights = insightsService.summarize();

    final score = insights['score']['value'] as int;
    final projections = insights['projections'] as Map<String, dynamic>;
    final budget = insights['budget'] as Map<String, dynamic>;
    final patterns = insights['patterns'] as Map<String, dynamic>;
    final recurring = insights['recurring'] as List<dynamic>;
    final anomalies = insights['anomalies'] as List<Transaction>;
    final incomeAnomalies = insights['incomeAnomalies'] as List<Transaction>;
    final totalIncome = _toDouble(insights['totalIncome']);
    final totalExpense = _toDouble(insights['totalExpense']);

    final formatter = NumberFormat.currency(symbol: 'ETB ', decimalDigits: 2);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              ),
              child: Icon(
                Icons.lightbulb,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Financial Insights',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (periodLabel != null)
                  Text(
                    periodLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.08),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withOpacity(0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This is still experimental, financial score might not be accurate.',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildScoreCard(context, score),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        context,
                        'Total Income',
                        formatter.format(totalIncome),
                        Icons.trending_up,
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        context,
                        'Total Expense',
                        formatter.format(totalExpense),
                        Icons.trending_down,
                        Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  context,
                  'Projections',
                  Icons.auto_graph,
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
                    _buildInfoRow(
                      context,
                      'Projected Savings',
                      formatter.format(
                        _toDouble(projections['projectedSavings']),
                      ),
                      isHighlight: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  context,
                  'Budget Tips',
                  Icons.savings,
                  [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        budget['tip'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (budget['targets'] != null) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      ...(budget['targets'] as Map<String, dynamic>)
                          .entries
                          .map(
                            (entry) => _buildInfoRow(
                              context,
                              entry.key.toUpperCase(),
                              formatter.format(_toDouble(entry.value)),
                            ),
                          ),
                    ],
                  ],
                ),
                if (recurring.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    context,
                    'Recurring Expenses',
                    Icons.repeat,
                    recurring.map((item) {
                      final map = item as Map<String, dynamic>;
                      return _buildInfoRow(
                        context,
                        map['label'] as String,
                        '${map['count']}x - ${formatter.format(_toDouble(map['avg']))}',
                      );
                    }).toList(),
                  ),
                ],
                if (anomalies.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    context,
                    'Unusual Expenses',
                    Icons.warning_amber_rounded,
                    anomalies.take(5).map((t) {
                      return _buildInfoRow(
                        context,
                        '${_bankLabel(t.bankId)} • ${_dateLabel(t.time)}',
                        formatter.format(t.amount),
                        isHighlight: true,
                      );
                    }).toList(),
                  ),
                ],
                if (incomeAnomalies.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    context,
                    'Unusual Income',
                    Icons.trending_up,
                    incomeAnomalies.take(5).map((t) {
                      return _buildInfoRow(
                        context,
                        '${_bankLabel(t.bankId)} • ${_dateLabel(t.time)}',
                        formatter.format(t.amount),
                        isHighlight: true,
                      );
                    }).toList(),
                  ),
                ],
                if (patterns['spendVariance'] != null) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    context,
                    'Spending Patterns',
                    Icons.insights,
                    [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Coming soon.',
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreCard(BuildContext context, int score) {
    Color scoreColor;
    String scoreLabel;
    String scoreSubtitle;

    if (score >= 80) {
      scoreColor = Colors.green;
      scoreLabel = 'Excellent';
      scoreSubtitle = 'You\'re doing a great job managing your money.';
    } else if (score >= 60) {
      scoreColor = Colors.orange;
      scoreLabel = 'Good';
      scoreSubtitle = 'Solid progress — small tweaks can boost savings.';
    } else {
      scoreColor = Colors.red;
      scoreLabel = 'Needs Improvement';
      scoreSubtitle = 'Focus on reducing expenses to improve your health.';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scoreColor.withOpacity(0.25),
            scoreColor.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scoreColor.withOpacity(0.4),
          width: 1.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.12),
            ),
            child: Center(
              child: Text(
                '$score',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: scoreColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Financial Health Score',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  scoreLabel,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  scoreSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
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
      padding: const EdgeInsets.symmetric(vertical: 6),
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
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isHighlight
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
