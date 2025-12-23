import 'package:flutter/material.dart';
import 'package:totals/models/transaction.dart';
import 'chart_data_point.dart';
import 'charts/line_chart_widget.dart';
import 'charts/bar_chart_widget.dart';
import 'charts/pie_chart_widget.dart';
import 'charts/pnl_calendar_chart.dart';

class ChartContainer extends StatefulWidget {
  final List<ChartDataPoint> data;
  final double maxValue;
  final String chartType;
  final String selectedPeriod;
  final int timeFrameOffset;
  final PageController timeFramePageController;
  final ValueChanged<int> onTimeFramePageChanged;
  final DateTime Function(int?) getBaseDate;
  final List<ChartDataPoint> Function(int) getChartDataForOffset;
  final String? selectedCard;
  final List<Transaction> barChartTransactions;
  final List<Transaction> pnlTransactions;
  final DateTime? Function(Transaction) dateForTransaction;
  final ValueChanged<DateTime>? onCalendarCellSelected;
  final VoidCallback onResetTimeFrame;
  final ValueChanged<bool> onNavigateTimeFrame;

  const ChartContainer({
    super.key,
    required this.data,
    required this.maxValue,
    required this.chartType,
    required this.selectedPeriod,
    required this.timeFrameOffset,
    required this.timeFramePageController,
    required this.onTimeFramePageChanged,
    required this.getBaseDate,
    required this.getChartDataForOffset,
    required this.selectedCard,
    required this.barChartTransactions,
    required this.pnlTransactions,
    required this.dateForTransaction,
    this.onCalendarCellSelected,
    required this.onResetTimeFrame,
    required this.onNavigateTimeFrame,
  });

  @override
  State<ChartContainer> createState() => _ChartContainerState();
}

class _ChartContainerState extends State<ChartContainer> {
  bool _leftButtonPressed = false;
  bool _rightButtonPressed = false;

  double _getChartHeight() {
    switch (widget.chartType) {
      case 'Heatmap':
        return 350;
      default:
        return 280;
    }
  }

  Widget _buildChart(
      List<ChartDataPoint> data, double maxValue, DateTime baseDate) {
    if (data.isEmpty) {
      return Container(
        height: _getChartHeight(),
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

    Widget chartWidget;
    switch (widget.chartType) {
      case 'Bar Chart':
        chartWidget = BarChartWidget(
          data: data,
          maxValue: maxValue,
          baseDate: baseDate,
          selectedPeriod: widget.selectedPeriod,
          timeFrameOffset: widget.timeFrameOffset,
          transactions: widget.barChartTransactions,
          dateForTransaction: widget.dateForTransaction,
        );
        break;
      case 'Pie Chart':
        chartWidget = PieChartWidget(data: data);
        break;
      case 'Heatmap':
        chartWidget = PnLCalendarChart(
          data: data,
          maxValue: maxValue,
          baseDate: baseDate,
          selectedPeriod: widget.selectedPeriod,
          selectedCard: widget.selectedCard,
          transactions: widget.pnlTransactions,
          dateForTransaction: widget.dateForTransaction,
          onDateSelected: widget.onCalendarCellSelected,
        );
        break;
      case 'Line Chart':
      default:
        chartWidget = LineChartWidget(
          data: data,
          maxValue: maxValue,
          baseDate: baseDate,
          selectedPeriod: widget.selectedPeriod,
          timeFrameOffset: widget.timeFrameOffset,
        );
        break;
    }

    return chartWidget;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTapDown: (_) {
                    setState(() => _leftButtonPressed = true);
                  },
                  onTapUp: (_) {
                    setState(() => _leftButtonPressed = false);
                    widget.onNavigateTimeFrame(false);
                  },
                  onTapCancel: () {
                    setState(() => _leftButtonPressed = false);
                  },
                  child: AnimatedScale(
                    scale: _leftButtonPressed ? 0.9 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeInOut,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeInOut,
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.chevron_left,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTapDown: (_) {
                    setState(() => _rightButtonPressed = true);
                  },
                  onTapUp: (_) {
                    setState(() => _rightButtonPressed = false);
                    widget.onNavigateTimeFrame(true);
                  },
                  onTapCancel: () {
                    setState(() => _rightButtonPressed = false);
                  },
                  child: AnimatedScale(
                    scale: _rightButtonPressed ? 0.9 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeInOut,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeInOut,
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.timeFrameOffset != 0)
              GestureDetector(
                onTap: widget.onResetTimeFrame,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.today,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Today',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        RepaintBoundary(
          child: SizedBox(
            height: _getChartHeight(),
            child: PageView.builder(
              controller: widget.timeFramePageController,
              onPageChanged: widget.onTimeFramePageChanged,
              itemCount: 3,
              itemBuilder: (context, pageIndex) {
                final pageOffset = pageIndex - 1;
                final effectiveOffset = widget.timeFrameOffset + pageOffset;

                final pageData = widget.getChartDataForOffset(effectiveOffset);
                final pageMaxValue = pageData.isEmpty
                    ? 5000.0
                    : (pageData
                                .map((e) => e.value)
                                .reduce((a, b) => a > b ? a : b) *
                            1.2)
                        .clamp(100.0, double.infinity);

                final pageBaseDate = widget.getBaseDate(effectiveOffset);

                return RepaintBoundary(
                  child: _buildChart(pageData, pageMaxValue, pageBaseDate),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
