import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/models/transaction.dart';
import '../chart_data_point.dart';
import '../chart_data_utils.dart';

class BarChartWidget extends StatelessWidget {
  final List<ChartDataPoint> data;
  final double maxValue;
  final DateTime baseDate;
  final String selectedPeriod;
  final int? selectedBankFilter;
  final int timeFrameOffset;

  const BarChartWidget({
    super.key,
    required this.data,
    required this.maxValue,
    required this.baseDate,
    required this.selectedPeriod,
    required this.selectedBankFilter,
    required this.timeFrameOffset,
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
    
    // Get income and expense data separately by recalculating for each period point
    final allTransactions = Provider.of<TransactionProvider>(context, listen: false).allTransactions;
    
    // Filter by bank if selected
    var bankFiltered = allTransactions;
    if (selectedBankFilter != null) {
      bankFiltered = allTransactions.where((t) => t.bankId == selectedBankFilter).toList();
    }
    
    // Calculate income and expense for each period point using the same logic as chart data
    final incomeData = <double>[];
    final expenseData = <double>[];
    
    for (var point in data) {
      final pointDate = point.date;
      if (pointDate == null) {
        incomeData.add(0.0);
        expenseData.add(0.0);
        continue;
      }
      
      // Filter transactions for this specific period point
      final pointTransactions = bankFiltered.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          if (selectedPeriod == 'Week') {
            return transactionDate.year == pointDate.year &&
                   transactionDate.month == pointDate.month &&
                   transactionDate.day == pointDate.day;
          } else if (selectedPeriod == 'Month') {
            // For month view, match week ranges
            final weekStart = pointDate;
            final weekEnd = weekStart.add(const Duration(days: 6));
            return transactionDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
                   transactionDate.isBefore(weekEnd.add(const Duration(days: 1)));
          } else {
            // For year view, match month
            return transactionDate.year == pointDate.year &&
                   transactionDate.month == pointDate.month;
          }
        } catch (e) {
          return false;
        }
      }).toList();
      
      final income = pointTransactions
          .where((t) => t.type == 'CREDIT')
          .fold(0.0, (sum, t) => sum + t.amount);
      final expense = pointTransactions
          .where((t) => t.type == 'DEBIT')
          .fold(0.0, (sum, t) => sum + t.amount);
      
      incomeData.add(income);
      expenseData.add(expense);
    }
    
    final maxBarValue = [
      ...incomeData,
      ...expenseData,
    ].reduce((a, b) => a > b ? a : b);
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

