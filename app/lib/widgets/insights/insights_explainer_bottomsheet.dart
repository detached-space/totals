import 'package:flutter/material.dart';

class InsightsExplainerBottomSheet extends StatelessWidget {
  const InsightsExplainerBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Understanding Your Insights',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Content
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _buildExplanationItem(
                        context,
                        'Financial Health Score',
                        'A 0-100 score showing how well you\'re managing your money. It looks at how much you spend vs earn, your savings rate, and how consistent your spending is. As you categorize more of your transactions (needs vs wants), the score and tips become more accurate.',
                        Icons.favorite,
                        Colors.red,
                      ),
                      const SizedBox(height: 16),
                      _buildExplanationItem(
                        context,
                        'Total Income & Expense',
                        'Your total money coming in (income) and going out (expenses) for the selected period. The difference shows if you\'re saving or spending more than you earn.',
                        Icons.account_balance_wallet,
                        Colors.blue,
                      ),
                      const SizedBox(height: 16),
                      _buildExplanationItem(
                        context,
                        'Projections',
                        'Predictions for next month based on your past spending patterns. Shows expected income, expenses, and savings to help you plan ahead.',
                        Icons.trending_up,
                        Colors.green,
                      ),
                      const SizedBox(height: 16),
                      _buildExplanationItem(
                        context,
                        'Budget Tips',
                        'Recommendations based on the 50/30/20 rule: 50% for needs, 30% for wants, 20% for savings. Helps identify areas where you might be overspending.',
                        Icons.savings,
                        Colors.purple,
                      ),
                      const SizedBox(height: 16),
                      _buildExplanationItem(
                        context,
                        'Recurring Expenses',
                        'Regular payments that happen repeatedly (like subscriptions or bills). Shows how often they occur and their average amount to help you track regular costs.',
                        Icons.repeat,
                        Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      _buildExplanationItem(
                        context,
                        'Unusual Expenses',
                        'Spending that\'s significantly higher than your average. These are flagged to help you spot unexpected large purchases or potential issues.',
                        Icons.warning_amber_rounded,
                        Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      _buildExplanationItem(
                        context,
                        'Unusual Income',
                        'Income that\'s much higher than your usual amount. Helps identify bonuses, one-time payments, or irregular income sources.',
                        Icons.trending_up,
                        Colors.green,
                      ),
                      const SizedBox(height: 16),
                      _buildExplanationItem(
                        context,
                        'Spending Patterns',
                        'Shows how your money is distributed across different categories and how consistent your spending is. Lower variance means more predictable spending habits.',
                        Icons.pie_chart,
                        Colors.blue,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExplanationItem(
    BuildContext context,
    String title,
    String explanation,
    IconData icon,
    Color iconColor,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  explanation,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
