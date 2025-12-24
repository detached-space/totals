import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:totals/models/transaction.dart';
import '../chart_data_point.dart';
import '../chart_data_utils.dart';

class BarChartWidget extends StatelessWidget {
  final List<ChartDataPoint> data;
  final double maxValue;
  final DateTime baseDate;
  final String selectedPeriod;
  final int timeFrameOffset;
  final List<Transaction> transactions;
  final DateTime? Function(Transaction)? dateForTransaction;

  const BarChartWidget({
    super.key,
    required this.data,
    required this.maxValue,
    required this.baseDate,
    required this.selectedPeriod,
    required this.timeFrameOffset,
    required this.transactions,
    this.dateForTransaction,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        height: 280,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
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

    final incomeData = List<double>.filled(data.length, 0.0);
    final expenseData = List<double>.filled(data.length, 0.0);
    final periodStart = data.first.date ??
        DateTime(baseDate.year, baseDate.month, baseDate.day)
            .subtract(Duration(days: (baseDate.weekday - 1) % 7));

    for (final transaction in transactions) {
      final transactionDate = resolveDate(transaction);
      if (transactionDate == null) continue;
      final day = DateTime(
        transactionDate.year,
        transactionDate.month,
        transactionDate.day,
      );
      int? bucketIndex;

      if (selectedPeriod == 'Week') {
        final diffDays = day.difference(periodStart).inDays;
        if (diffDays >= 0 && diffDays < data.length) {
          bucketIndex = diffDays;
        }
      } else if (selectedPeriod == 'Month') {
        if (day.year != baseDate.year || day.month != baseDate.month) {
          continue;
        }
        final monthStart = DateTime(baseDate.year, baseDate.month, 1);
        final diffDays = day.difference(monthStart).inDays;
        final weekIndex = (diffDays / 7).floor();
        if (weekIndex >= 0 && weekIndex < data.length) {
          bucketIndex = weekIndex;
        }
      } else {
        if (day.year != baseDate.year) continue;
        final monthIndex = day.month - 1;
        if (monthIndex >= 0 && monthIndex < data.length) {
          bucketIndex = monthIndex;
        }
      }

      if (bucketIndex == null) continue;
      if (transaction.type == 'CREDIT') {
        incomeData[bucketIndex] += transaction.amount;
      } else if (transaction.type == 'DEBIT') {
        expenseData[bucketIndex] += transaction.amount;
      }
    }
    
    final maxBarValue = [
      ...incomeData,
      ...expenseData,
    ].fold(0.0, (maxValue, value) => value > maxValue ? value : maxValue);
    final chartMaxValue = (maxBarValue * 1.2).clamp(100.0, double.infinity);
    
    int currentDayIndex = ChartDataUtils.getCurrentDayIndex(data, baseDate, selectedPeriod);
    
    return Container(
      height: 280,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (chartMaxValue / 5).clamp(100.0, double.infinity),
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.08),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < data.length) {
                    // Only highlight if this is the current time frame (offset 0) and matches today
                    final isCurrentDay = timeFrameOffset == 0 && 
                                       baseDate.year == DateTime.now().year &&
                                       baseDate.month == DateTime.now().month &&
                                       baseDate.day == DateTime.now().day &&
                                       index == currentDayIndex;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isCurrentDay
                              ? Theme.of(context).colorScheme.primary.withOpacity(0.25)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          data[index].label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isCurrentDay ? FontWeight.bold : FontWeight.w500,
                            color: isCurrentDay
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
                reservedSize: 40,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: (chartMaxValue / 5).clamp(100.0, double.infinity),
                reservedSize: 45,
                getTitlesWidget: (value, meta) {
                  if (value == 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    '${(value / 1000).toStringAsFixed(0)}k',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: data.asMap().entries.map((entry) {
            final index = entry.key;
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  fromY: 0,
                  toY: incomeData[index],
                  color: Colors.green,
                  width: 8,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
                BarChartRodData(
                  fromY: 0,
                  toY: -expenseData[index],
                  color: Theme.of(context).colorScheme.error,
                  width: 8,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(2)),
                ),
              ],
            );
          }).toList(),
          minY: -chartMaxValue,
          maxY: chartMaxValue,
        ),
      ),
    );
  }
}

