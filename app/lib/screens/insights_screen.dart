import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/insights_provider.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final insights = context.watch<InsightsProvider>().insights;

    final score = insights['score']['value'] as int;
    final projections = insights['projections'] as Map<String, dynamic>;
    final budget = insights['budget'] as Map<String, dynamic>;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      child: ListView(children: [
        _card('Financial Health Score', '$score / 100'),
        _card('Projected Savings',
            'ETB ${projections['projectedSavings'].toStringAsFixed(2)}'),
        _card('Budget Tip', budget['tip'] as String),
        _card('Spending Patterns', budget['patterns']),
        _card('Recurring Expenses', budget['recurring']),
      ]),
    );
  }

  Widget _card(String title, String value) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }
}
