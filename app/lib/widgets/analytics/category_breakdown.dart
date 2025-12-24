import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/category_style.dart';

class CategoryBreakdown extends StatelessWidget {
  final List<Transaction> transactions;
  final TransactionProvider provider;
  final String? selectedCard;

  const CategoryBreakdown({
    super.key,
    required this.transactions,
    required this.provider,
    required this.selectedCard,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return _EmptyState(title: _titleFor(selectedCard));
    }

    final totals = <int?, double>{};
    final counts = <int?, int>{};
    final categoriesById = <int?, Category?>{};

    for (final transaction in transactions) {
      final category = provider.getCategoryById(transaction.categoryId);
      final key = category?.id;
      categoriesById[key] = category;
      totals[key] = (totals[key] ?? 0) + transaction.amount.abs();
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final totalAmount =
        totals.values.fold(0.0, (sum, value) => sum + value);
    final stats = totals.entries
        .map((entry) => _CategoryStat(
              category: categoriesById[entry.key],
              amount: entry.value,
              count: counts[entry.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    return _CategoryBreakdownCard(
      title: _titleFor(selectedCard),
      totalAmount: totalAmount,
      stats: stats,
    );
  }

  String _titleFor(String? selectedCard) {
    if (selectedCard == 'Income') return 'Income categories';
    if (selectedCard == 'Expense') return 'Expense categories';
    return 'Categories';
  }
}

class _CategoryBreakdownCard extends StatelessWidget {
  final String title;
  final double totalAmount;
  final List<_CategoryStat> stats;

  const _CategoryBreakdownCard({
    required this.title,
    required this.totalAmount,
    required this.stats,
  });

  String _formatAmount(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                'ETB ${_formatAmount(totalAmount)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final stat in stats) ...[
            _CategoryBreakdownRow(
              stat: stat,
              totalAmount: totalAmount,
            ),
            if (stat != stats.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _CategoryBreakdownRow extends StatelessWidget {
  final _CategoryStat stat;
  final double totalAmount;

  const _CategoryBreakdownRow({
    required this.stat,
    required this.totalAmount,
  });

  String _formatAmount(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final category = stat.category;
    final color = category == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : categoryTypeColor(category, context);
    final percent = totalAmount > 0 ? stat.amount / totalAmount : 0.0;
    final typeLabel = category?.typeLabel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category?.name ?? 'Uncategorized',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (typeLabel != null)
                    Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'ETB ${_formatAmount(stat.amount)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  '${stat.count} txns',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 6,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;

  const _EmptyState({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.7),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            'No category data',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryStat {
  final Category? category;
  final double amount;
  final int count;

  const _CategoryStat({
    required this.category,
    required this.amount,
    required this.count,
  });
}
