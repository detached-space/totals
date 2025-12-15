import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/models/transaction.dart';
import 'package:intl/intl.dart';

class IncomeExpenseCards extends StatelessWidget {
  final String? selectedCard;
  final String selectedPeriod;
  final int? selectedBankFilter;
  final String? selectedAccountFilter;
  final DateTime Function() getBaseDate;
  final ValueChanged<String?> onCardSelected;

  const IncomeExpenseCards({
    super.key,
    required this.selectedCard,
    required this.selectedPeriod,
    required this.selectedBankFilter,
    required this.selectedAccountFilter,
    required this.getBaseDate,
    required this.onCardSelected,
  });

  @override
  Widget build(BuildContext context) {
    final allTransactions =
        Provider.of<TransactionProvider>(context, listen: false)
            .allTransactions;
    final accounts = Provider.of<TransactionProvider>(context, listen: false)
        .accountSummaries;

    // Filter by period
    final now = getBaseDate();
    List<Transaction> periodFiltered = [];

    if (selectedPeriod == 'Week') {
      int daysSinceMonday = (now.weekday - 1) % 7;
      final weekStart = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: daysSinceMonday));
      periodFiltered = allTransactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate
                  .isAfter(weekStart.subtract(const Duration(days: 1))) &&
              transactionDate.isBefore(now.add(const Duration(days: 1)));
        } catch (e) {
          return false;
        }
      }).toList();
    } else if (selectedPeriod == 'Month') {
      final monthStart = DateTime(now.year, now.month, 1);
      periodFiltered = allTransactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate.year == now.year &&
              transactionDate.month == now.month;
        } catch (e) {
          return false;
        }
      }).toList();
    } else {
      // Year
      periodFiltered = allTransactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate.year == now.year;
        } catch (e) {
          return false;
        }
      }).toList();
    }

    // Filter by bank if selected
    if (selectedBankFilter != null) {
      periodFiltered =
          periodFiltered.where((t) => t.bankId == selectedBankFilter).toList();
    }

    // Filter by account if selected
    if (selectedAccountFilter != null && selectedBankFilter != null) {
      final account = accounts.firstWhere(
        (a) =>
            a.accountNumber == selectedAccountFilter &&
            a.bankId == selectedBankFilter,
        orElse: () => accounts.firstWhere((a) => a.bankId == selectedBankFilter,
            orElse: () => accounts.first),
      );

      periodFiltered = periodFiltered.where((t) {
        if (account.bankId == 1 &&
            t.accountNumber != null &&
            account.accountNumber.length >= 4) {
          return t.accountNumber!.substring(t.accountNumber!.length - 4) ==
              account.accountNumber.substring(account.accountNumber.length - 4);
        } else if (account.bankId == 4 &&
            t.accountNumber != null &&
            account.accountNumber.length >= 3) {
          return t.accountNumber!.substring(t.accountNumber!.length - 3) ==
              account.accountNumber.substring(account.accountNumber.length - 3);
        } else if (account.bankId == 3 &&
            t.accountNumber != null &&
            account.accountNumber.length >= 2) {
          return t.accountNumber!.substring(t.accountNumber!.length - 2) ==
              account.accountNumber.substring(account.accountNumber.length - 2);
        } else {
          return t.bankId == account.bankId;
        }
      }).toList();
    }

    // Calculate income and expenses for the period
    final periodIncome = periodFiltered
        .where((t) => t.type == 'CREDIT')
        .fold(0.0, (sum, t) => sum + t.amount);
    final periodExpenses = periodFiltered
        .where((t) => t.type == 'DEBIT')
        .fold(0.0, (sum, t) => sum + t.amount);

    return Row(
      children: [
        Expanded(
          child: _IncomeExpenseCard(
            label: 'Income',
            amount: periodIncome,
            color: Colors.green,
            cardType: 'Income',
            isSelected: selectedCard == 'Income',
            onTap: () =>
                onCardSelected(selectedCard == 'Income' ? null : 'Income'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _IncomeExpenseCard(
            label: 'Expense',
            amount: periodExpenses,
            color: Theme.of(context).colorScheme.error,
            cardType: 'Expense',
            isSelected: selectedCard == 'Expense',
            onTap: () =>
                onCardSelected(selectedCard == 'Expense' ? null : 'Expense'),
          ),
        ),
      ],
    );
  }
}

class _IncomeExpenseCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final String cardType;
  final bool isSelected;
  final VoidCallback onTap;

  const _IncomeExpenseCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.cardType,
    required this.isSelected,
    required this.onTap,
  });

  String _formatCurrency(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = cardType == 'Income';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isIncome
                      ? [
                          Colors.green.shade600,
                          Colors.green.shade700,
                        ]
                      : [
                          Theme.of(context).colorScheme.error,
                          Theme.of(context).colorScheme.error.withOpacity(0.8),
                        ],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.4),
                    Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.2),
                  ],
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.transparent : color.withOpacity(0.3),
            width: isSelected ? 0 : 1,
          ),
          boxShadow: [
            // Main shadow for depth
            BoxShadow(
              color: isSelected
                  ? (isIncome
                      ? Colors.green.withOpacity(0.4)
                      : Theme.of(context).colorScheme.error.withOpacity(0.4))
                  : Colors.black.withOpacity(0.1),
              blurRadius: isSelected ? 12 : 8,
              offset: Offset(0, isSelected ? 6 : 4),
              spreadRadius: isSelected ? 2 : 0,
            ),
            // Secondary shadow for more depth
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
            // Inner shadow effect (simulated with a subtle top highlight)
            if (isSelected)
              BoxShadow(
                color: Colors.white.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'ETB ${_formatCurrency(amount)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

