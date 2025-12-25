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
  Set<String> _selectedReferences = {};

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
    final refreshed = <Transaction>[];
    for (final transaction in widget.transactions) {
      final updatedTransaction = _findUpdatedTransaction(transaction, updated);
      if (updatedTransaction != null) {
        refreshed.add(updatedTransaction);
      }
    }
    return refreshed;
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

  bool get _isSelectionMode => _selectedReferences.isNotEmpty;

  void _toggleSelection(Transaction transaction) {
    setState(() {
      if (_selectedReferences.contains(transaction.reference)) {
        _selectedReferences.remove(transaction.reference);
      } else {
        _selectedReferences.add(transaction.reference);
      }
    });
  }

  void _clearSelection() {
    if (_selectedReferences.isEmpty) return;
    setState(() {
      _selectedReferences.clear();
    });
  }

  void _selectAll(List<Transaction> transactions) {
    final references =
        transactions.map((transaction) => transaction.reference).toSet();
    setState(() {
      if (references.isEmpty) {
        _selectedReferences.clear();
        return;
      }
      final isAllSelected = _selectedReferences.length == references.length &&
          _selectedReferences.containsAll(references);
      if (isAllSelected) {
        _selectedReferences.clear();
      } else {
        _selectedReferences = references;
      }
    });
  }

  void _invertSelection(List<Transaction> transactions) {
    final references =
        transactions.map((transaction) => transaction.reference).toSet();
    setState(() {
      _selectedReferences = references.difference(_selectedReferences);
    });
  }

  void _pruneSelection(Set<String> validReferences) {
    if (_selectedReferences.isEmpty) return;
    if (_selectedReferences.every(validReferences.contains)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedReferences.removeWhere(
          (reference) => !validReferences.contains(reference),
        );
      });
    });
  }

  Future<void> _confirmDeleteSelected(
    TransactionProvider provider,
  ) async {
    if (_selectedReferences.isEmpty) return;
    final count = _selectedReferences.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Delete $count transaction${count == 1 ? '' : 's'}?'),
          content: const Text(
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await provider.deleteTransactionsByReferences(_selectedReferences);
    if (!mounted) return;
    setState(() {
      _selectedReferences.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.provider,
      builder: (context, _) {
        final refreshedTransactions = _refreshTransactions(widget.provider);
        final filteredTransactions =
            _filterByCategory(refreshedTransactions);
        final filteredReferences =
            filteredTransactions.map((transaction) => transaction.reference);
        _pruneSelection(filteredReferences.toSet());
        final selectionCount = _selectedReferences.length;

        return Scaffold(
          appBar: AppBar(
            leading: _isSelectionMode
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _clearSelection,
                  )
                : null,
            title: _isSelectionMode
                ? Text('$selectionCount selected')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
            actions: _isSelectionMode
                ? [
                    IconButton(
                      tooltip: 'Select all',
                      icon: const Icon(Icons.select_all),
                      onPressed: () => _selectAll(filteredTransactions),
                    ),
                    IconButton(
                      tooltip: 'Invert selection',
                      icon: const Icon(Icons.swap_horiz),
                      onPressed: () => _invertSelection(filteredTransactions),
                    ),
                    IconButton(
                      tooltip: 'Delete selected',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          _confirmDeleteSelected(widget.provider),
                    ),
                  ]
                : null,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
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
                            icon: Icons.toc_rounded,
                            iconColor: Colors.green,
                            flipIconHorizontally: true,
                            selectedCount:
                                _selectedIncomeCategoryIds.length,
                            tooltip: 'Income categories',
                            onTap: () =>
                                _openCategoryFilterSheet(flow: 'income'),
                          ),
                          const SizedBox(width: 8),
                          CategoryFilterIconButton(
                            icon: Icons.toc_rounded,
                            iconColor: Theme.of(context).colorScheme.error,
                            flipIconHorizontally: true,
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
                      selectionMode: _isSelectionMode,
                      selectedReferences: _selectedReferences,
                      onTransactionTap: (transaction) async {
                        if (_isSelectionMode) {
                          _toggleSelection(transaction);
                          return;
                        }
                        await showCategorizeTransactionSheet(
                          context: context,
                          provider: widget.provider,
                          transaction: transaction,
                        );
                      },
                      onTransactionLongPress: (transaction) {
                        _toggleSelection(transaction);
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
            ),
          ),
        );
      },
    );
  }
}
