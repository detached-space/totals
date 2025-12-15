import 'package:flutter/material.dart';
import 'package:totals/models/transaction.dart';
import 'package:intl/intl.dart';

class TransactionsList extends StatelessWidget {
  final List<Transaction> transactions;
  final String sortBy;
  final ValueChanged<String> onSortChanged;

  const TransactionsList({
    super.key,
    required this.transactions,
    required this.sortBy,
    required this.onSortChanged,
  });

  String _formatCurrency(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final sortedTransactions = List<Transaction>.from(transactions);
    sortedTransactions.sort((a, b) {
      switch (sortBy) {
        case 'Amount':
          return b.amount.compareTo(a.amount);
        case 'Reference':
          return a.reference.compareTo(b.reference);
        case 'Date':
        default:
          if (a.time == null && b.time == null) return 0;
          if (a.time == null) return 1;
          if (b.time == null) return -1;
          try {
            final dateA = DateTime.parse(a.time!);
            final dateB = DateTime.parse(b.time!);
            return dateB.compareTo(dateA);
          } catch (e) {
            return 0;
          }
      }
    });

    if (sortedTransactions.isEmpty) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Transactions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            PopupMenuButton<String>(
              icon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sort,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Sort by',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              onSelected: onSortChanged,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'Date',
                  child: Text('Date'),
                ),
                const PopupMenuItem(
                  value: 'Amount',
                  child: Text('Amount'),
                ),
                const PopupMenuItem(
                  value: 'Reference',
                  child: Text('Reference'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sortedTransactions.length,
          itemBuilder: (context, index) {
            final transaction = sortedTransactions[index];
            return _TransactionItem(transaction: transaction, formatCurrency: _formatCurrency);
          },
        ),
      ],
    );
  }
}

class _TransactionItem extends StatelessWidget {
  final Transaction transaction;
  final String Function(double) formatCurrency;

  const _TransactionItem({
    required this.transaction,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.type == 'CREDIT';
    final dateTime = transaction.time != null
        ? (() {
            try {
              return DateTime.parse(transaction.time!);
            } catch (e) {
              return null;
            }
          })()
        : null;
    final dateStr = dateTime != null
        ? DateFormat('MMM dd, yyyy').format(dateTime)
        : 'Unknown date';
    final timeStr = dateTime != null
        ? DateFormat('hh:mm a').format(dateTime)
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.1),
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
                      transaction.reference,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (transaction.creditor != null || transaction.receiver != null)
                      const SizedBox(height: 4),
                    if (transaction.creditor != null)
                      Text(
                        transaction.creditor!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (transaction.receiver != null)
                      Text(
                        transaction.receiver!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (timeStr.isNotEmpty)
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                        ),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

