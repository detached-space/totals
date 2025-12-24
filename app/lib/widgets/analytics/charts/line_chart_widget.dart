import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../chart_data_point.dart';
import '../chart_data_utils.dart';

class LineChartWidget extends StatelessWidget {
  final List<ChartDataPoint> data;
  final double maxValue;
  final DateTime baseDate;
  final String selectedPeriod;
  final int timeFrameOffset;

  const LineChartWidget({
    super.key,
    required this.data,
    required this.maxValue,
    required this.baseDate,
    required this.selectedPeriod,
    required this.timeFrameOffset,
  });

  @override
  Widget build(BuildContext context) {
    // Find current day index based on base date
    int currentDayIndex = ChartDataUtils.getCurrentDayIndex(data, baseDate, selectedPeriod);

    return Stack(
      children: [
        Container(
          height: 280,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (maxValue / 5).clamp(100.0, double.infinity),
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.08),
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      if ((value % 1).abs() > 0.001) {
                        return const SizedBox.shrink();
                      }
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
                    interval: (maxValue / 5).clamp(100.0, double.infinity),
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
              minX: 0,
              maxX: (data.length - 1).toDouble(),
              minY: 0,
              maxY: maxValue,
              lineBarsData: [
                LineChartBarData(
                  spots: data.asMap().entries.map((entry) {
                    return FlSpot(entry.key.toDouble(), entry.value.value);
                  }).toList(),
                  isCurved: true,
                  curveSmoothness: 0.5,
                  color: Theme.of(context).colorScheme.primary,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: false,
                  ),
                  belowBarData: BarAreaData(
                    show: false,
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) =>
                      Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.9),
                  tooltipRoundedRadius: 8,
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

