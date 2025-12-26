import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/services/financial_insights.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:intl/intl.dart';

class InsightsDialog extends StatelessWidget {
  final List<Transaction> transactions;

  const InsightsDialog({
    super.key,
    required this.transactions,
  });

  // Helper function to safely convert numeric values to double
  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final insightsService = InsightsService(
      () => transactions,
      getCategoryById: txProvider.getCategoryById,
    );
    final insights = insightsService.summarize();

    final score = insights['score']['value'] as int;
    final projections = insights['projections'] as Map<String, dynamic>;
    final budget = insights['budget'] as Map<String, dynamic>;
    final patterns = insights['patterns'] as Map<String, dynamic>;
    final recurring = insights['recurring'] as List<dynamic>;
    final anomalies = insights['anomalies'] as List<Transaction>;
    final totalIncome = _toDouble(insights['totalIncome']);
    final totalExpense = _toDouble(insights['totalExpense']);

    final formatter = NumberFormat.currency(symbol: 'ETB ', decimalDigits: 2);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withOpacity(0.8),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Financial Insights',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Financial Health Score
                    _buildScoreCard(context, score),
                    const SizedBox(height: 16),

                    // Summary Cards
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

                    // Projections
                    _buildSectionCard(
                      context,
                      'Projections',
                      Icons.auto_graph,
                      [
                        _buildInfoRow(
                          context,
                          'Projected Income',
                          formatter.format(
                              _toDouble(projections['projectedIncome'])),
                        ),
                        _buildInfoRow(
                          context,
                          'Projected Expense',
                          formatter.format(
                              _toDouble(projections['projectedExpense'])),
                        ),
                        _buildInfoRow(
                          context,
                          'Projected Savings',
                          formatter.format(
                              _toDouble(projections['projectedSavings'])),
                          isHighlight: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Budget Suggestions
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
                    const SizedBox(height: 16),

                    // Recurring Expenses
                    if (recurring.isNotEmpty) ...[
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
                      const SizedBox(height: 16),
                    ],

                    // Anomalies
                    if (anomalies.isNotEmpty) ...[
                      _buildSectionCard(
                        context,
                        'Unusual Expenses',
                        Icons.warning_amber_rounded,
                        anomalies.take(5).map((t) {
                          return _buildInfoRow(
                            context,
                            t.reference.isNotEmpty ? t.reference : 'Unknown',
                            formatter.format(t.amount),
                            isHighlight: true,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Spending Patterns
                    if (patterns['spendVariance'] != null) ...[
                      _buildSectionCard(
                        context,
                        'Spending Patterns',
                        Icons.insights,
                        [
                          _buildInfoRow(
                            context,
                            'Spending Variance',
                            _toDouble(patterns['spendVariance'])
                                .toStringAsFixed(2),
                          ),
                          _buildInfoRow(
                            context,
                            'Essentials Ratio',
                            '${(_toDouble(patterns['essentialsRatio']) * 100).toStringAsFixed(1)}%',
                          ),
                        ],
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

  Widget _buildScoreCard(BuildContext context, int score) {
    Color scoreColor;
    String scoreLabel;
    if (score >= 80) {
      scoreColor = Colors.green;
      scoreLabel = 'Excellent';
    } else if (score >= 60) {
      scoreColor = Colors.orange;
      scoreLabel = 'Good';
    } else {
      scoreColor = Colors.red;
      scoreLabel = 'Needs Improvement';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scoreColor.withOpacity(0.2),
            scoreColor.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scoreColor.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scoreColor.withOpacity(0.2),
            ),
            child: Center(
              child: Text(
                '$score',
                style: TextStyle(
                  fontSize: 24,
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
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

  Widget _buildInfoRow(BuildContext context, String label, String value,
      {bool isHighlight = false}) {
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
