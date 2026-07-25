import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/category_style.dart';
import '../chart_data_point.dart';

class BarChartWidget extends StatelessWidget {
  final List<ChartDataPoint> data;
  final DateTime baseDate;
  final String selectedPeriod;
  final String selectedFlow;
  final List<Transaction> transactions;
  final Set<int?> selectedIncomeCategoryIds;
  final Set<int?> selectedExpenseCategoryIds;
  final ValueChanged<String>? onFlowChanged;
  final ValueChanged<String>? onPeriodChanged;
  final DateTime? Function(Transaction)? dateForTransaction;

  const BarChartWidget({
    super.key,
    required this.data,
    required this.baseDate,
    required this.selectedPeriod,
    required this.selectedFlow,
    required this.transactions,
    required this.selectedIncomeCategoryIds,
    required this.selectedExpenseCategoryIds,
    this.onFlowChanged,
    this.onPeriodChanged,
    this.dateForTransaction,
  });

  static final NumberFormat _currencyFormat = NumberFormat('#,##0');

  static const List<_BarToggleOption> _periodOptions = [
    _BarToggleOption(label: 'Weekly', value: 'Week'),
    _BarToggleOption(label: 'Monthly', value: 'Month'),
    _BarToggleOption(label: 'Yearly', value: 'Year'),
  ];

  static const List<_BarToggleOption> _flowOptions = [
    _BarToggleOption(label: 'Expense', value: 'Expense'),
    _BarToggleOption(label: 'Income', value: 'Income'),
  ];

  String _periodLabel() {
    switch (selectedPeriod) {
      case 'Week':
        return 'Weekly';
      case 'Month':
        return 'Monthly';
      default:
        return 'Yearly';
    }
  }

  double _barWidth() {
    switch (selectedPeriod) {
      case 'Week':
        return 36;
      case 'Month':
        return 46;
      default:
        return 18;
    }
  }

  bool _matchesCategorySelection(int? categoryId, Set<int?> selection) {
    if (selection.isEmpty) return true;
    if (categoryId == null) return selection.contains(null);
    return selection.contains(categoryId);
  }

  DateTime? _resolveDate(Transaction transaction) {
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

  int? _bucketIndexFor(DateTime transactionDate) {
    final day = DateTime(
      transactionDate.year,
      transactionDate.month,
      transactionDate.day,
    );

    if (selectedPeriod == 'Week') {
      final baseDay = DateTime(baseDate.year, baseDate.month, baseDate.day);
      final weekStart =
          baseDay.subtract(Duration(days: (baseDay.weekday - 1) % 7));
      final diffDays = day.difference(weekStart).inDays;
      if (diffDays < 0 || diffDays >= data.length) return null;
      return diffDays;
    }

    if (selectedPeriod == 'Month') {
      if (day.year != baseDate.year || day.month != baseDate.month) {
        return null;
      }
      return ((day.day - 1) / 7).floor().clamp(0, data.length - 1).toInt();
    }

    if (day.year != baseDate.year) return null;
    return day.month - 1;
  }

  String _categoryLabel(Category? category) {
    final name = category?.name.trim();
    if (name == null || name.isEmpty) {
      return 'Other';
    }
    return name;
  }

  List<_BarCategoryStat> _buildCategoryStats(
    TransactionProvider provider,
    ThemeData theme,
  ) {
    final isIncome = selectedFlow == 'Income';
    final selectedCategoryIds =
        isIncome ? selectedIncomeCategoryIds : selectedExpenseCategoryIds;
    final statsByKey = <String, _BarCategoryStat>{};
    final categoryFallback = isIncome
        ? const Color(0xFF67D88B)
        : theme.colorScheme.primary.withValues(alpha: 0.92);
    final otherColor =
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72);

    for (final transaction in transactions) {
      if (provider.isSelfTransfer(transaction)) {
        continue;
      }
      if (isIncome && transaction.type != 'CREDIT') {
        continue;
      }
      if (!isIncome && transaction.type != 'DEBIT') {
        continue;
      }
      if (!_matchesCategorySelection(
          transaction.categoryId, selectedCategoryIds)) {
        continue;
      }

      final transactionDate = _resolveDate(transaction);
      if (transactionDate == null) continue;
      final bucketIndex = _bucketIndexFor(transactionDate);
      if (bucketIndex == null) continue;

      final category = provider.getCategoryById(transaction.categoryId);
      final key =
          category?.id != null ? 'category:${category!.id}' : 'uncategorized';
      final stat = statsByKey.putIfAbsent(
        key,
        () => _BarCategoryStat(
          label: _categoryLabel(category),
          color: category == null
              ? otherColor
              : categoryPaletteColor(category, fallback: categoryFallback),
          bucketValues: List<double>.filled(data.length, 0.0),
          orderSeed: statsByKey.length,
        ),
      );

      final amount = isIncome
          ? provider.incomeAmountForTransaction(transaction)
          : transaction.amount.abs();
      if (amount <= 0) continue;
      stat.bucketValues[bucketIndex] += amount;
      stat.total += amount;
    }

    final categories = statsByKey.values.toList()
      ..sort((a, b) {
        final totalCompare = b.total.compareTo(a.total);
        if (totalCompare != 0) return totalCompare;
        return a.orderSeed.compareTo(b.orderSeed);
      });

    return categories;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final categories = _buildCategoryStats(provider, theme);
    final bucketTotals = List<double>.generate(
      data.length,
      (index) => categories.fold<double>(
        0.0,
        (sum, category) => sum + category.bucketValues[index],
      ),
    );
    final maxBucketTotal = bucketTotals.fold<double>(
      0.0,
      (maxSoFar, value) => value > maxSoFar ? value : maxSoFar,
    );
    final chartMaxValue = maxBucketTotal <= 0
        ? 100.0
        : (maxBucketTotal * 1.16).clamp(100.0, double.infinity);
    final title = '${_periodLabel()} $selectedFlow';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BarSegmentedControl(
            options: _periodOptions,
            selectedValue: selectedPeriod,
            onChanged: onPeriodChanged,
            expand: true,
          ),
          const SizedBox(height: 10),
          _BarSegmentedControl(
            options: _flowOptions,
            selectedValue: selectedFlow,
            onChanged: onFlowChanged,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: categories.isEmpty
                ? Center(
                    child: Text(
                      'No ${selectedFlow.toLowerCase()} data available',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 220,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            minY: 0,
                            maxY: chartMaxValue,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: (chartMaxValue / 4)
                                  .clamp(50.0, double.infinity),
                              getDrawingHorizontalLine: (value) {
                                return FlLine(
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.12),
                                  strokeWidth: 1,
                                  dashArray: const [4, 4],
                                );
                              },
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  getTitlesWidget: (value, meta) {
                                    final index = value.toInt();
                                    if (index < 0 || index >= data.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        data[index].label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: theme
                                              .colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.9),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            barTouchData: BarTouchData(
                              enabled: true,
                              handleBuiltInTouches: true,
                              touchTooltipData: BarTouchTooltipData(
                                tooltipRoundedRadius: 12,
                                tooltipPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                                getTooltipColor: (group) =>
                                    theme.colorScheme.surface,
                                getTooltipItem:
                                    (group, groupIndex, rod, rodIndex) {
                                  final index = group.x.toInt();
                                  final total = bucketTotals[index];
                                  return BarTooltipItem(
                                    '${data[index].label}\nETB ${_currencyFormat.format(total)}',
                                    TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  );
                                },
                              ),
                            ),
                            barGroups: List<BarChartGroupData>.generate(
                              data.length,
                              (index) {
                                final stackingOrder =
                                    categories.reversed.toList();
                                double runningTotal = 0.0;
                                final stacks = <BarChartRodStackItem>[];

                                for (final category in stackingOrder) {
                                  final value = category.bucketValues[index];
                                  if (value <= 0) continue;
                                  stacks.add(
                                    BarChartRodStackItem(
                                      runningTotal,
                                      runningTotal + value,
                                      category.color,
                                    ),
                                  );
                                  runningTotal += value;
                                }

                                return BarChartGroupData(
                                  x: index,
                                  barsSpace: 0,
                                  barRods: [
                                    BarChartRodData(
                                      toY: runningTotal,
                                      width: _barWidth(),
                                      color: categories.first.color,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(7),
                                      ),
                                      rodStackItems: stacks,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 112,
                        child: _BarCategoryScroller(categories: categories),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _BarSegmentedControl extends StatelessWidget {
  final List<_BarToggleOption> options;
  final String selectedValue;
  final ValueChanged<String>? onChanged;
  final bool expand;

  const _BarSegmentedControl({
    required this.options,
    required this.selectedValue,
    this.onChanged,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final optionWidgets = <Widget>[];

    for (int index = 0; index < options.length; index++) {
      final option = options[index];
      final optionWidget = _BarSegmentedControlOption(
        label: option.label,
        selected: selectedValue == option.value,
        onTap: () => onChanged?.call(option.value),
      );

      if (expand) {
        optionWidgets.add(Expanded(child: optionWidget));
      } else {
        optionWidgets.add(optionWidget);
      }

      if (index < options.length - 1) {
        optionWidgets.add(const SizedBox(width: 4));
      }
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: optionWidgets,
      ),
    );
  }
}

class _BarSegmentedControlOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BarSegmentedControlOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.26),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.86),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _BarCategoryScroller extends StatelessWidget {
  final List<_BarCategoryStat> categories;

  const _BarCategoryScroller({
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final columns = <Widget>[];

    for (int index = 0; index < categories.length; index += 2) {
      final top = categories[index];
      final bottom =
          index + 1 < categories.length ? categories[index + 1] : null;
      columns.add(
        Padding(
          padding:
              EdgeInsets.only(right: index + 2 < categories.length ? 14 : 0),
          child: SizedBox(
            width: 188,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BarCategoryItem(stat: top),
                const SizedBox(height: 10),
                if (bottom != null)
                  _BarCategoryItem(stat: bottom)
                else
                  const SizedBox(height: 38),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columns,
      ),
    );
  }
}

class _BarCategoryItem extends StatelessWidget {
  final _BarCategoryStat stat;

  const _BarCategoryItem({
    required this.stat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: stat.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            stat.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'ETB ${BarChartWidget._currencyFormat.format(stat.total)}',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _BarToggleOption {
  final String label;
  final String value;

  const _BarToggleOption({
    required this.label,
    required this.value,
  });
}

class _BarCategoryStat {
  final String label;
  final Color color;
  final List<double> bucketValues;
  final int orderSeed;
  double total = 0.0;

  _BarCategoryStat({
    required this.label,
    required this.color,
    required this.bucketValues,
    required this.orderSeed,
  });
}
