import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/screens/transactions_for_period_page.dart';
import 'package:totals/services/financial_insights.dart';
import 'package:totals/widgets/insights/insights_explainer_bottomsheet.dart';

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
        actions: [
          IconButton(
            icon: Icon(
              Icons.help_outline,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        ],
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
                // Show categorization encouragement banner when coverage is low
                if (lowCoverage) ...[
                  _buildCategorizationBanner(
                    context,
                    categorizedCoverage,
                    transactions,
                    txProvider,
                  ),
                  const SizedBox(height: 12),
                ],
                _buildScoreCard(context, score, lowCoverage: lowCoverage),
                const SizedBox(height: 12),
                _buildStabilityCard(
                  context,
                  _toDouble(patterns[MapKeys.spendVariance]),
                ),
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
                    // Removed needs/wants targets - will be improved in the future
                  ],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  context,
                  'Unusual Expenses',
                  Icons.warning_amber_rounded,
                  anomalies.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No unusual expenses detected. Your spending is consistent.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ]
                      : anomalies.take(5).map((t) {
                          return _buildInfoRow(
                            context,
                            '${_bankLabel(t.bankId)} • ${_dateLabel(t.time)}',
                            formatter.format(t.amount),
                            isHighlight: true,
                          );
                        }).toList(),
                ),
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
                      ...(patterns[MapKeys.byCategory] as Map<String, dynamic>)
                          .entries
                          .map(
                        (entry) {
                          final label = entry.key;
                          final value = _toDouble(entry.value);
                          String suffix = '';

                          // Show percentage of total expenses for debit-like categories.
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
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        context,
                        'Spending Variance',
                        _formatLargeNumber(
                            _toDouble(patterns[MapKeys.stabilityIndex])),
                      ),
                      // Removed Essentials Share - will be improved in the future
                      // when better categorization is available
                    ],
                  ),
                ],
                // Recurring expenses at the end (expandable)
                if (recurring.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildExpandableRecurringSection(
                    context,
                    recurring,
                    formatter,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _bankLabel(int? bankId) {
    if (bankId == null) return 'Unknown bank';
    for (final bank in AppConstants.banks) {
      if (bank.id == bankId) return bank.shortName;
    }
    return 'Bank($bankId)';
  }

  Widget _buildCategorizationBanner(
    BuildContext context,
    double categorizedCoverage,
    List<Transaction> transactions,
    TransactionProvider provider,
  ) {
    try {
      final coveragePercent = (categorizedCoverage * 100).toStringAsFixed(0);
      final uncategorizedCount = transactions.where((t) {
        try {
          return !_isIncome(t) && t.categoryId == null;
        } catch (e) {
          print('[INSIGHTS_PAGE_ERROR] Error in _isIncome check: $e');
          return false;
        }
      }).length;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.15),
              Theme.of(context).colorScheme.primary.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            width: 1.5,
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
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.label_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Improve Your Insights',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$coveragePercent% of your spending is categorized. '
                        'Categorize more transactions for better insights!',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      try {
                        // Navigate to transactions page filtered to uncategorized
                        final uncategorizedTransactions =
                            transactions.where((t) {
                          try {
                            return !_isIncome(t) && t.categoryId == null;
                          } catch (e) {
                            print(
                                '[INSIGHTS_PAGE_ERROR] Error filtering transactions: $e');
                            return false;
                          }
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
                                  : 'Uncategorized Transactions',
                              subtitle: uncategorizedTransactions.isEmpty
                                  ? null
                                  : '$uncategorizedCount transactions need categorization',
                            ),
                          ),
                        );
                      } catch (e, stackTrace) {
                        print(
                            '[INSIGHTS_PAGE_ERROR] Error navigating to transactions: $e');
                        print('[INSIGHTS_PAGE_ERROR] Stack trace: $stackTrace');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    },
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    label: Text(
                      uncategorizedCount > 0
                          ? 'Categorize $uncategorizedCount Transactions'
                          : 'View Transactions',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } catch (e, stackTrace) {
      print('[INSIGHTS_PAGE_ERROR] Error in _buildCategorizationBanner: $e');
      print('[INSIGHTS_PAGE_ERROR] Stack trace: $stackTrace');
      // Return empty container on error to prevent grey screen
      return const SizedBox.shrink();
    }
  }

  Widget _buildExpandableRecurringSection(
    BuildContext context,
    List<dynamic> recurring,
    NumberFormat formatter,
  ) {
    return _ExpandableRecurringCard(
      recurring: recurring,
      formatter: formatter,
      toDouble: _toDouble,
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

  Widget _buildScoreCard(BuildContext context, int score,
      {bool lowCoverage = false}) {
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
                const SizedBox(height: 4),
                if (lowCoverage)
                  Text(
                    'Your score becomes more accurate as you categorize more of your spending.',
                    style: TextStyle(
                      fontSize: 11,
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

  Widget _buildStabilityCard(BuildContext context, double variance) {
    // Simple thresholds to convert raw variance into human-readable labels.
    String label;
    String description;
    Color color;

    if (variance < 50000) {
      label = 'Stable';
      description = 'Your spending is fairly predictable from month to month.';
      color = Colors.green;
    } else if (variance < 500000) {
      label = 'Moderate';
      description = 'Your spending changes, but not extremely.';
      color = Colors.orange;
    } else {
      label = 'Very Irregular';
      description =
          'Your spending jumps a lot between months. Try smoothing big spikes.';
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.18),
            color.withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(0.35),
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.08),
            ),
            child: Icon(
              Icons.show_chart,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spending Stability',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
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

  String _dateLabel(String? isoTime) {
    if (isoTime == null) return 'Unknown date';
    try {
      return DateFormat('MMM d').format(DateTime.parse(isoTime));
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
      print(
          '[INSIGHTS_PAGE_ERROR] Error in _isIncome: $e, transaction: ${t.reference}');
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
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.repeat,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Recurring Expenses',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.recurring.length} items',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 12),
            ...widget.recurring.map((item) {
              final map = item as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        map['label'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      '${map['count']}x - ${widget.formatter.format(widget.toDouble(map['avg']))}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
