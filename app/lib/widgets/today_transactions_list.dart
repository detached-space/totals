import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/category_icons.dart';
import 'package:totals/widgets/categorize_transaction_sheet.dart';

class TodayTransactionsList extends StatelessWidget {
  final List<Transaction> transactions;
  final TransactionProvider provider;
  final String? highlightedReference;
  final ValueChanged<Transaction>? onTransactionTap;

  const TodayTransactionsList({
    super.key,
    required this.transactions,
    required this.provider,
    this.highlightedReference,
    this.onTransactionTap,
  });

  String _formatCurrency(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List<Transaction>.from(transactions);
    sorted.sort((a, b) {
      if (a.time == null && b.time == null) return 0;
      if (a.time == null) return 1;
      if (b.time == null) return -1;
      try {
        final dateA = DateTime.parse(a.time!);
        final dateB = DateTime.parse(b.time!);
        return dateB.compareTo(dateA);
      } catch (_) {
        return 0;
      }
    });

    if (sorted.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No transactions found',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final transaction = sorted[index];
        return _TodayTransactionItem(
          transaction: transaction,
          formatCurrency: _formatCurrency,
          provider: provider,
          isHighlighted: highlightedReference != null &&
              transaction.reference == highlightedReference,
          onTap: () {
            if (onTransactionTap != null) {
              onTransactionTap!(transaction);
            } else {
              showCategorizeTransactionSheet(
                context: context,
                provider: provider,
                transaction: transaction,
              );
            }
          },
        );
      },
    );
  }
}

class _TodayTransactionItem extends StatelessWidget {
  final Transaction transaction;
  final String Function(double) formatCurrency;
  final TransactionProvider provider;
  final VoidCallback onTap;
  final bool isHighlighted;

  const _TodayTransactionItem({
    required this.transaction,
    required this.formatCurrency,
    required this.provider,
    required this.onTap,
    required this.isHighlighted,
  });

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.type == 'CREDIT';
    final bankLabel = (() {
      final bankId = transaction.bankId;
      if (bankId == null) return 'Unknown bank';
      for (final b in AppConstants.banks) {
        if (b.id == bankId) return b.shortName;
      }
      return 'Unknown bank';
    })();
    final dateTime = transaction.time != null
        ? (() {
            try {
              return DateTime.parse(transaction.time!);
            } catch (_) {
              return null;
            }
          })()
        : null;
    final dateStr = dateTime != null
        ? DateFormat('MMM dd, yyyy').format(dateTime)
        : 'Unknown date';
    final timeStr =
        dateTime != null ? DateFormat('hh:mm a').format(dateTime) : '';

    final category = provider.getCategoryById(transaction.categoryId);
    final isIncomeCategory = category?.flow.toLowerCase() == 'income';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isHighlighted
              ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
              : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted
                ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                : Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withOpacity(0.1),
            width: 1,
          ),
        ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bankLabel,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (transaction.creditor != null ||
                            transaction.receiver != null)
                          const SizedBox(height: 4),
                        if (transaction.creditor != null)
                          Text(
                            transaction.creditor!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        // if (transaction.receiver != null)
                        //   Text(
                        //     transaction.receiver!,
                        //     style: TextStyle(
                        //       fontSize: 13,
                        //       color: Theme.of(context)
                        //           .colorScheme
                        //           .onSurfaceVariant,
                        //     ),
                        //     maxLines: 1,
                        //     overflow: TextOverflow.ellipsis,
                        //   ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _CategoryChip(
                              label: category?.name ?? 'Uncategorized',
                              icon: iconForCategoryKey(category?.iconKey),
                              color: category == null
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                  : (isIncomeCategory
                                      ? (category.essential
                                          ? Colors.green
                                          : Colors.teal)
                                      : (category.essential
                                          ? Colors.blue
                                          : Colors.orange)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isCredit ? '+' : '-'}ETB ${formatCurrency(transaction.amount)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isCredit
                              ? Colors.green
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                      if (dateTime != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (timeStr.isNotEmpty)
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withOpacity(0.7),
                            ),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
