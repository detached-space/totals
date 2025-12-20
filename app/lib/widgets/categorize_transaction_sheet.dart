import 'package:flutter/material.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/category_icons.dart';

Future<void> showCategorizeTransactionSheet({
  required BuildContext context,
  required TransactionProvider provider,
  required Transaction transaction,
}) async {
  final desiredFlow = transaction.type == 'CREDIT' ? 'income' : 'expense';
  final filtered = provider.categories
      .where((c) => c.flow.toLowerCase() == desiredFlow)
      .toList(growable: false);
  final categories = filtered.isEmpty ? provider.categories : filtered;
  final current = provider.getCategoryById(transaction.categoryId);

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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Categorize',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (current != null)
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
                    final selected = current?.id != null && c.id == current!.id;

                    return ListTile(
                      leading: Icon(iconForCategoryKey(c.iconKey)),
                      title: Text(c.name),
                      subtitle: Text(c.essential ? 'Essential' : 'Non-essential'),
                      trailing: selected ? const Icon(Icons.check_rounded) : null,
                      onTap: () async {
                        if (c.id == null) return;
                        Navigator.pop(context);
                        await provider.setCategoryForTransaction(transaction, c);
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

