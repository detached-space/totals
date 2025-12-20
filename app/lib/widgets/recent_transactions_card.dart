import 'package:flutter/material.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/utils/category_icons.dart';

class RecentTransactionsCard extends StatelessWidget {
  final List<Transaction> transactions;
  final TransactionProvider provider;
  final int? totalCount;
  final String title;

  const RecentTransactionsCard({
    super.key,
    required this.transactions,
    required this.provider,
    this.totalCount,
    this.title = 'Recent transactions',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        elevation: 0,
        color: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                  if (transactions.isNotEmpty)
                    Text(
                      '${totalCount ?? transactions.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No transactions yet',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: transactions.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 16,
                    color:
                        Theme.of(context).dividerColor.withOpacity(0.7),
                  ),
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final isCredit = tx.type == 'CREDIT';
                    final category = provider.getCategoryById(tx.categoryId);

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showCategorizeSheet(
                        context: context,
                        transaction: tx,
                        currentCategory: category,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 4,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: (isCredit
                                        ? Colors.green
                                        : Colors.red)
                                    .withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isCredit
                                    ? Icons.arrow_downward_rounded
                                    : Icons.arrow_upward_rounded,
                                size: 18,
                                color:
                                    isCredit ? Colors.green : Colors.red,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _titleFor(tx),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      Text(
                                        _timeLabel(tx),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                      _categoryChip(context, category),
                                      if (category != null)
                                        _essentialChip(context, category),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${isCredit ? '+' : '-'}ETB ${formatNumberWithComma(tx.amount)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isCredit ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 8),
              Text(
                'Tap a transaction to categorize',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _titleFor(Transaction tx) {
    final parts = [
      tx.creditor?.trim(),
      tx.receiver?.trim(),
      tx.reference.trim(),
    ].whereType<String>().where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? 'Transaction' : parts.first;
  }

  static String _timeLabel(Transaction tx) {
    final t = tx.time;
    if (t == null || t.isEmpty) return '—';
    return formatTime(t);
  }

  Widget _categoryChip(BuildContext context, Category? category) {
    final label = category?.name ?? 'Uncategorized';
    final color = category == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _essentialChip(BuildContext context, Category category) {
    final label = category.essential ? 'Essential' : 'Non-essential';
    final color = category.essential ? Colors.blue : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Future<void> _showCategorizeSheet({
    required BuildContext context,
    required Transaction transaction,
    required Category? currentCategory,
  }) async {
    final categories = provider.categories;

    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No categories available')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Categorize',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (currentCategory != null)
                  ListTile(
                    leading: const Icon(Icons.close_rounded),
                    title: const Text('Clear category'),
                    onTap: () async {
                      Navigator.pop(context);
                      await provider.clearCategoryForTransaction(transaction);
                    },
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final c = categories[index];
                      final selected = currentCategory?.id != null &&
                          c.id == currentCategory!.id;
                      return ListTile(
                        leading: Icon(iconForCategoryKey(c.iconKey)),
                        title: Text(c.name),
                        subtitle: Text(
                          c.essential ? 'Essential' : 'Non-essential',
                        ),
                        trailing:
                            selected ? const Icon(Icons.check_rounded) : null,
                        onTap: () async {
                          Navigator.pop(context);
                          await provider.setCategoryForTransaction(
                            transaction,
                            c,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
