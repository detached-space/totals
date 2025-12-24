import 'package:flutter/material.dart';
import 'package:totals/models/transaction.dart';
import 'package:intl/intl.dart';
import '../chart_data_point.dart';

class PnLCalendarChart extends StatelessWidget {
  final List<ChartDataPoint> data;
  final double maxValue;
  final DateTime baseDate;
  final String selectedPeriod;
  final String? selectedCard;
  final List<Transaction> transactions;
  final DateTime? Function(Transaction)? dateForTransaction;
  final ValueChanged<DateTime>? onDateSelected;

  const PnLCalendarChart({
    super.key,
    required this.data,
    required this.maxValue,
    required this.baseDate,
    required this.selectedPeriod,
    required this.selectedCard,
    required this.transactions,
    this.dateForTransaction,
    this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    final now = baseDate;
    Widget wrapCell(DateTime date, Widget child) {
      if (onDateSelected == null) return child;
      return GestureDetector(
        onTap: () => onDateSelected!(date),
        child: child,
      );
    }

    DateTime? resolveDate(Transaction transaction) {
      if (dateForTransaction != null) {
        return dateForTransaction!(transaction);
      }
      if (transaction.time == null) return null;
      try {
        return DateTime.parse(transaction.time!);
      } catch (_) {
        return null;
      }
    }

    // Determine date range based on selected period
    DateTime startDate;
    DateTime endDate;
    String periodLabel;
    List<DateTime> dates = [];

    if (selectedPeriod == 'Week') {
      int daysSinceMonday = (now.weekday - 1) % 7;
      startDate = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: daysSinceMonday));
      endDate = startDate.add(const Duration(days: 6));
      periodLabel = 'Week of ${DateFormat('MMM dd').format(startDate)}';
      for (int i = 0; i < 7; i++) {
        dates.add(startDate.add(Duration(days: i)));
      }
    } else if (selectedPeriod == 'Month') {
      startDate = DateTime(now.year, now.month, 1);
      endDate = DateTime(now.year, now.month + 1, 0);
      periodLabel = DateFormat('MMMM yyyy').format(startDate);
      final daysInMonth = endDate.day;
      for (int day = 1; day <= daysInMonth; day++) {
        dates.add(DateTime(now.year, now.month, day));
      }
    } else {
      startDate = DateTime(now.year, 1, 1);
      endDate = DateTime(now.year, 12, 31);
      periodLabel = '${now.year}';
      for (int month = 1; month <= 12; month++) {
        dates.add(DateTime(now.year, month, 1));
      }
    }

    final firstWeekday = (dates.first.weekday - 1) % 7;
    final dailyPnL = {for (final date in dates) date: 0.0};

    void addPnL(DateTime key, Transaction transaction) {
      if (!dailyPnL.containsKey(key)) return;
      if (selectedCard == 'Income' && transaction.type != 'CREDIT') return;
      if (selectedCard == 'Expense' && transaction.type != 'DEBIT') return;

      double delta = 0.0;
      if (selectedCard == 'Income') {
        delta = transaction.amount;
      } else if (selectedCard == 'Expense') {
        delta = -transaction.amount;
      } else {
        if (transaction.type == 'CREDIT') {
          delta = transaction.amount;
        } else if (transaction.type == 'DEBIT') {
          delta = -transaction.amount;
        } else {
          return;
        }
      }

      dailyPnL[key] = (dailyPnL[key] ?? 0.0) + delta;
    }

    for (final transaction in transactions) {
      final transactionDate = resolveDate(transaction);
      if (transactionDate == null) continue;

      if (selectedPeriod == 'Week') {
        final dayKey = DateTime(
          transactionDate.year,
          transactionDate.month,
          transactionDate.day,
        );
        if (dayKey.isBefore(startDate) || dayKey.isAfter(endDate)) {
          continue;
        }
        addPnL(dayKey, transaction);
      } else if (selectedPeriod == 'Month') {
        if (transactionDate.year != now.year ||
            transactionDate.month != now.month) {
          continue;
        }
        final dayKey = DateTime(
          transactionDate.year,
          transactionDate.month,
          transactionDate.day,
        );
        addPnL(dayKey, transaction);
      } else {
        if (transactionDate.year != now.year) continue;
        final monthKey =
            DateTime(transactionDate.year, transactionDate.month, 1);
        addPnL(monthKey, transaction);
      }
    }

    final maxPnL = dailyPnL.values.isEmpty
        ? 100.0
        : dailyPnL.values.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);

    int weeks;
    int itemsPerRow;
    if (selectedPeriod == 'Week') {
      weeks = 1;
      itemsPerRow = 7;
    } else if (selectedPeriod == 'Month') {
      final daysInMonth = dates.length;
      final totalCells = firstWeekday + daysInMonth;
      weeks = (totalCells / 7).ceil();
      itemsPerRow = 7;
    } else {
      weeks = 3;
      itemsPerRow = 4;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                periodLabel,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Row(
                children: [
                  _buildLegendItem(context, 'Income', Colors.green),
                  const SizedBox(width: 12),
                  _buildLegendItem(
                      context, 'Expense', Theme.of(context).colorScheme.error),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              if (selectedPeriod == 'Year')
                Row(
                  children: ['Q1', 'Q2', 'Q3', 'Q4'].map((quarter) {
                    return Expanded(
                      child: Center(
                        child: Text(
                          quarter,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                )
              else
                Row(
                  children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                      .map((day) {
                    return Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 8),
              ...List.generate(weeks, (weekIndex) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: List.generate(itemsPerRow, (dayIndex) {
                      final cellIndex = selectedPeriod == 'Year'
                          ? dayIndex * weeks + weekIndex
                          : weekIndex * itemsPerRow + dayIndex;

                      if (selectedPeriod == 'Year') {
                        if (cellIndex >= dates.length) {
                          return Expanded(child: Container());
                        }
                        final date = dates[cellIndex];
                        final monthName = DateFormat('MMM').format(date);
                        final pnl = dailyPnL[date] ?? 0.0;
                        final isCurrentMonth =
                            baseDate.year == DateTime.now().year &&
                                baseDate.month == DateTime.now().month &&
                                date.year == DateTime.now().year &&
                                date.month == DateTime.now().month;
                        final intensity = maxPnL > 0
                            ? (pnl.abs() / maxPnL).clamp(0.0, 1.0)
                            : 0.0;
                        final isPositive = pnl >= 0;
                        final hasTransactions = pnl != 0.0;
                        final bgOpacity =
                            hasTransactions ? (0.2 + intensity * 0.6) : 0.1;
                        final useWhiteText = bgOpacity > 0.5;

                        return Expanded(
                          child: wrapCell(
                            date,
                            Padding(
                              padding: const EdgeInsets.all(2),
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  color: !hasTransactions
                                      ? Colors.grey.withOpacity(0.2)
                                      : (isPositive
                                          ? Colors.green.withOpacity(bgOpacity)
                                          : Theme.of(context)
                                              .colorScheme
                                              .error
                                              .withOpacity(bgOpacity)),
                                  borderRadius: BorderRadius.circular(8),
                                  border: isCurrentMonth
                                      ? Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      monthName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isCurrentMonth
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: useWhiteText
                                            ? Colors.white
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                      ),
                                    ),
                                    if (pnl != 0)
                                      Text(
                                        '${pnl > 0 ? '+' : ''}${(pnl / 1000).toStringAsFixed(1)}k',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: useWhiteText
                                              ? Colors.white
                                              : (isPositive
                                                  ? Colors.green.shade700
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .error),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      } else {
                        final cellIndexWithOffset =
                            weekIndex * itemsPerRow + dayIndex;
                        final dayNumber =
                            cellIndexWithOffset - firstWeekday + 1;

                        if (selectedPeriod == 'Week') {
                          if (cellIndexWithOffset >= dates.length) {
                            return Expanded(child: Container());
                          }
                          final date = dates[cellIndexWithOffset];
                          final dayNumber = date.day;
                          final pnl = dailyPnL[date] ?? 0.0;
                          final isToday =
                              baseDate.year == DateTime.now().year &&
                                  baseDate.month == DateTime.now().month &&
                                  baseDate.day == DateTime.now().day &&
                                  date.year == DateTime.now().year &&
                                  date.month == DateTime.now().month &&
                                  date.day == DateTime.now().day;
                          final intensity = maxPnL > 0
                              ? (pnl.abs() / maxPnL).clamp(0.0, 1.0)
                              : 0.0;
                          final isPositive = pnl >= 0;
                          final hasTransactions = pnl != 0.0;
                          final bgOpacity =
                              hasTransactions ? (0.2 + intensity * 0.6) : 0.1;
                          final useWhiteText = bgOpacity > 0.5;

                          return Expanded(
                            child: wrapCell(
                              date,
                              Padding(
                                padding: const EdgeInsets.all(2),
                                child: Container(
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: !hasTransactions
                                        ? Colors.grey.withOpacity(0.2)
                                        : (isPositive
                                            ? Colors.green
                                                .withOpacity(bgOpacity)
                                            : Theme.of(context)
                                                .colorScheme
                                                .error
                                                .withOpacity(bgOpacity)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: isToday
                                        ? Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '$dayNumber',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isToday
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: useWhiteText
                                              ? Colors.white
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                        ),
                                      ),
                                      if (pnl != 0)
                                        Text(
                                          '${pnl > 0 ? '+' : ''}${(pnl / 1000).toStringAsFixed(1)}k',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: useWhiteText
                                                ? Colors.white
                                                : (isPositive
                                                    ? Colors.green.shade700
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .error),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        } else {
                          if (dayNumber < 1 || dayNumber > dates.length) {
                            return Expanded(child: Container());
                          }

                          final date = dates[dayNumber - 1];
                          final pnl = dailyPnL[date] ?? 0.0;
                          final isToday =
                              baseDate.year == DateTime.now().year &&
                                  baseDate.month == DateTime.now().month &&
                                  baseDate.day == DateTime.now().day &&
                                  date.year == DateTime.now().year &&
                                  date.month == DateTime.now().month &&
                                  date.day == DateTime.now().day;
                          final intensity = maxPnL > 0
                              ? (pnl.abs() / maxPnL).clamp(0.0, 1.0)
                              : 0.0;
                          final isPositive = pnl >= 0;
                          final hasTransactions = pnl != 0.0;
                          final bgOpacity =
                              hasTransactions ? (0.2 + intensity * 0.6) : 0.1;
                          final useWhiteText = bgOpacity > 0.5;

                          return Expanded(
                            child: wrapCell(
                              date,
                              Padding(
                                padding: const EdgeInsets.all(2),
                                child: Container(
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: !hasTransactions
                                        ? Colors.grey.withOpacity(0.2)
                                        : (isPositive
                                            ? Colors.green
                                                .withOpacity(bgOpacity)
                                            : Theme.of(context)
                                                .colorScheme
                                                .error
                                                .withOpacity(bgOpacity)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: isToday
                                        ? Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '$dayNumber',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isToday
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: useWhiteText
                                              ? Colors.white
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                        ),
                                      ),
                                      if (pnl != 0)
                                        Text(
                                          '${pnl > 0 ? '+' : ''}${(pnl / 1000).toStringAsFixed(1)}k',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: useWhiteText
                                                ? Colors.white
                                                : (isPositive
                                                    ? Colors.green.shade700
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .error),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                      }
                    }),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withOpacity(0.6),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
