import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../chart_data_point.dart';

class PieChartWidget extends StatelessWidget {
  final List<ChartDataPoint> data;

  const PieChartWidget({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final total = data.fold(0.0, (sum, point) => sum + point.value);
    if (total == 0) {
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

    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 50,
          sections: data.asMap().entries.map((entry) {
            final index = entry.key;
            final point = entry.value;
            final percentage = (point.value / total) * 100;
            return PieChartSectionData(
              value: point.value,
              title: '${point.label}\n${percentage.toStringAsFixed(1)}%',
              color: Theme.of(context).colorScheme.primary.withOpacity(
                0.3 + (index % 3) * 0.2,
              ),
              radius: 90,
              titleStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

