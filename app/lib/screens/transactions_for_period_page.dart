import 'package:flutter/material.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/widgets/analytics/transactions_list.dart';
import 'package:totals/widgets/categorize_transaction_sheet.dart';
import 'package:totals/widgets/category_filter_button.dart';
import 'package:totals/widgets/category_filter_sheet.dart';

class TransactionsForPeriodPage extends StatefulWidget {
  final List<Transaction> transactions;
  final TransactionProvider provider;
  final String title;
  final String? subtitle;

  const TransactionsForPeriodPage({
    super.key,
    required this.transactions,
    required this.provider,
    required this.title,
    this.subtitle,
  });

  @override
  State<TransactionsForPeriodPage> createState() =>
      _TransactionsForPeriodPageState();
}

class _TransactionsForPeriodPageState extends State<TransactionsForPeriodPage> {
  String _sortBy = 'Date';
  Set<int?> _selectedIncomeCategoryIds = {};
  Set<int?> _selectedExpenseCategoryIds = {};

  Transaction? _findUpdatedTransaction(
    Transaction original,
    List<Transaction> updatedTransactions,
  ) {
    for (final transaction in updatedTransactions) {
      if (transaction.reference != original.reference) continue;
      if (transaction.time != original.time) continue;
      if (transaction.amount != original.amount) continue;
      if (transaction.bankId != original.bankId) continue;
      if (transaction.accountNumber != original.accountNumber) continue;
      return transaction;
    }
    return null;
  }

  List<Transaction> _refreshTransactions(TransactionProvider provider) {
    final updated = provider.allTransactions;
    return widget.transactions
        .map((transaction) =>
            _findUpdatedTransaction(transaction, updated) ?? transaction)
        .toList();
  }

  bool _matchesCategorySelection(int? categoryId, Set<int?> selection) {
    if (selection.isEmpty) return true;
    if (categoryId == null) return selection.contains(null);
    return selection.contains(categoryId);
  }

  bool _matchesCategoryFilter(Transaction transaction) {
    if (_selectedIncomeCategoryIds.isEmpty &&
        _selectedExpenseCategoryIds.isEmpty) {
      return true;
    }
    if (transaction.type == 'CREDIT') {
      return _matchesCategorySelection(
          transaction.categoryId, _selectedIncomeCategoryIds);
    }
    if (transaction.type == 'DEBIT') {
      return _matchesCategorySelection(
          transaction.categoryId, _selectedExpenseCategoryIds);
    }
    return true;
  }

  List<Transaction> _filterByCategory(List<Transaction> transactions) {
    return transactions.where(_matchesCategoryFilter).toList(growable: false);
  }

  Future<void> _openCategoryFilterSheet({required String flow}) async {
    final result = await showCategoryFilterSheet(
      context: context,
      provider: widget.provider,
      selectedCategoryIds: flow == 'income'
          ? _selectedIncomeCategoryIds
          : _selectedExpenseCategoryIds,
      flow: flow,
    );
    if (result == null) return;
    setState(() {
      if (flow == 'income') {
        _selectedIncomeCategoryIds = result.toSet();
      } else {
        _selectedExpenseCategoryIds = result.toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.provider,
          builder: (context, _) {
            final refreshedTransactions = _refreshTransactions(widget.provider);
            final filteredTransactions =
                _filterByCategory(refreshedTransactions);
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CategoryFilterIconButton(
                            icon: Icons.category_rounded,
                            iconColor: Colors.green,
                            selectedCount:
                                _selectedIncomeCategoryIds.length,
                            tooltip: 'Income categories',
                            onTap: () =>
                                _openCategoryFilterSheet(flow: 'income'),
                          ),
                          const SizedBox(width: 8),
                          CategoryFilterIconButton(
                            icon: Icons.category_rounded,
                            iconColor: Theme.of(context).colorScheme.error,
                            selectedCount:
                                _selectedExpenseCategoryIds.length,
                            tooltip: 'Expense categories',
                            onTap: () =>
                                _openCategoryFilterSheet(flow: 'expense'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TransactionsList(
                      transactions: filteredTransactions,
                      sortBy: _sortBy,
                      provider: widget.provider,
                      includeBottomPadding: false,
                      onTransactionTap: (transaction) async {
                        await showCategorizeTransactionSheet(
                          context: context,
                          provider: widget.provider,
                          transaction: transaction,
                        );
                      },
                      onSortChanged: (sort) {
                        setState(() {
                          _sortBy = sort;
                        });
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
