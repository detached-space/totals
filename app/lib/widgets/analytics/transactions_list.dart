import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/category_icons.dart';
import 'package:totals/utils/category_style.dart';

class TransactionsList extends StatefulWidget {
  final List<Transaction> transactions;
  final String sortBy;
  final ValueChanged<String>? onSortChanged;
  final bool showHeader;
  final bool includeBottomPadding;
  final ValueChanged<Transaction>? onTransactionTap;
  final ValueChanged<Transaction>? onTransactionLongPress;
  final TransactionProvider? provider;
  final bool selectionMode;
  final Set<String> selectedReferences;

  const TransactionsList({
    super.key,
    required this.transactions,
    required this.sortBy,
    this.onSortChanged,
    this.showHeader = true,
    this.includeBottomPadding = true,
    this.onTransactionTap,
    this.onTransactionLongPress,
    this.provider,
    this.selectionMode = false,
    this.selectedReferences = const <String>{},
  });

  @override
  State<TransactionsList> createState() => _TransactionsListState();
}

class _TransactionsListState extends State<TransactionsList> {
  static const int _itemsPerPage = 10;
  final BankConfigService _bankConfigService = BankConfigService();
  int _currentPage = 0;
  Map<int, String> _bankLabelsById = {};

  String _formatCurrency(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    try {
      final banks = await _bankConfigService.getBanks();
      if (!mounted) return;
      setState(() {
        _bankLabelsById = {
          for (final bank in banks)
            bank.id: _bankLabelFor(bank),
        };
      });
    } catch (e) {
      // Keep fallback labels if bank config isn't available.
    }
  }

  String _bankLabelFor(Bank bank) {
    if (bank.shortName.trim().isNotEmpty) {
      return bank.shortName;
    }
    return bank.name;
  }

  String _getBankLabel(Transaction transaction) {
    final bankId = transaction.bankId;
    if (bankId == null) return 'Unknown bank';
    return _bankLabelsById[bankId] ?? 'Bank $bankId';
  }

  @override
  void didUpdateWidget(TransactionsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset to first page when transactions change
    if (oldWidget.transactions.length != widget.transactions.length) {
      setState(() {
        _currentPage = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectionMode =
        widget.selectionMode || widget.selectedReferences.isNotEmpty;
    final sortedTransactions = List<Transaction>.from(widget.transactions);
    sortedTransactions.sort((a, b) {
      switch (widget.sortBy) {
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

    final totalPages = (sortedTransactions.length / _itemsPerPage).ceil();
    final startIndex = _currentPage * _itemsPerPage;
    final endIndex =
        (startIndex + _itemsPerPage).clamp(0, sortedTransactions.length);
    final paginatedTransactions =
        sortedTransactions.sublist(startIndex, endIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Transactions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${sortedTransactions.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              PopupMenuButton<String>(
                enabled: widget.onSortChanged != null,
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
                onSelected: widget.onSortChanged,
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
        ],

        // Transactions list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: paginatedTransactions.length,
          itemBuilder: (context, index) {
            final transaction = paginatedTransactions[index];
            return TransactionListItem(
              transaction: transaction,
              bankLabel: _getBankLabel(transaction),
              provider: widget.provider,
              formatCurrency: _formatCurrency,
              selectionMode: selectionMode,
              isSelected:
                  widget.selectedReferences.contains(transaction.reference),
              onTap: widget.onTransactionTap != null
                  ? () => widget.onTransactionTap!(transaction)
                  : null,
              onLongPress: widget.onTransactionLongPress != null
                  ? () => widget.onTransactionLongPress!(transaction)
                  : null,
            );
          },
        ),

        // Pagination controls
        if (totalPages > 1) ...[
          // const SizedBox(height: 8),
          _buildPaginationControls(totalPages),
        ],

        if (widget.includeBottomPadding)
          const SizedBox(height: 80), // Space for bottom nav
      ],
    );
  }

  Widget _buildPaginationControls(int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous button
          _PaginationButton(
            icon: Icons.chevron_left,
            onTap:
                _currentPage > 0 ? () => setState(() => _currentPage--) : null,
            isEnabled: _currentPage > 0,
          ),

          const SizedBox(width: 8),

          // Page numbers
          ..._buildPageNumbers(totalPages),

          const SizedBox(width: 8),

          // Next button
          _PaginationButton(
            icon: Icons.chevron_right,
            onTap: _currentPage < totalPages - 1
                ? () => setState(() => _currentPage++)
                : null,
            isEnabled: _currentPage < totalPages - 1,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageNumbers(int totalPages) {
    List<Widget> pageWidgets = [];

    // Determine which page numbers to show
    List<int> pagesToShow = [];

    if (totalPages <= 5) {
      // Show all pages if 5 or fewer
      pagesToShow = List.generate(totalPages, (i) => i);
    } else {
      // Always show first page
      pagesToShow.add(0);

      // Show pages around current page
      if (_currentPage > 2) {
        pagesToShow.add(-1); // Ellipsis indicator
      }

      for (int i = _currentPage - 1; i <= _currentPage + 1; i++) {
        if (i > 0 && i < totalPages - 1) {
          pagesToShow.add(i);
        }
      }

      if (_currentPage < totalPages - 3) {
        pagesToShow.add(-1); // Ellipsis indicator
      }

      // Always show last page
      pagesToShow.add(totalPages - 1);
    }

    for (int i = 0; i < pagesToShow.length; i++) {
      final pageNum = pagesToShow[i];

      if (pageNum == -1) {
        // Ellipsis
        pageWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      } else {
        pageWidgets.add(
          GestureDetector(
            onTap: () => setState(() => _currentPage = pageNum),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _currentPage == pageNum
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '${pageNum + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _currentPage == pageNum
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    return pageWidgets;
  }
}

class _PaginationButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isEnabled;

  const _PaginationButton({
    required this.icon,
    required this.onTap,
    required this.isEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isEnabled
              ? Theme.of(context).colorScheme.surface
              : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isEnabled
                ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                : Theme.of(context).colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isEnabled
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
        ),
      ),
    );
  }
}

class TransactionListItem extends StatelessWidget {
  final Transaction transaction;
  final String bankLabel;
  final TransactionProvider? provider;
  final String Function(double) formatCurrency;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TransactionListItem({
    required this.transaction,
    required this.bankLabel,
    required this.provider,
    required this.formatCurrency,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
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
    final timeStr =
        dateTime != null ? DateFormat('hh:mm a').format(dateTime) : '';

    final receiver = transaction.receiver?.trim();
    final hasReceiver = receiver != null && receiver.isNotEmpty;

    final category = provider?.getCategoryById(transaction.categoryId);
    final categoryColor = category == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : categoryTypeColor(category, context);
    final selectionColor = Theme.of(context).colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? selectionColor.withOpacity(0.08)
                : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? selectionColor.withOpacity(0.4)
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
                        if (hasReceiver)
                          const SizedBox(height: 4),
                        if (hasReceiver)
                          Text(
                            'to $receiver',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (provider != null) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _CategoryChip(
                                label: category?.name ?? 'Uncategorized',
                                icon: iconForCategoryKey(category?.iconKey),
                                color: categoryColor,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (selectionMode) ...[
                        Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: isSelected
                              ? selectionColor
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 6),
                      ],
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
