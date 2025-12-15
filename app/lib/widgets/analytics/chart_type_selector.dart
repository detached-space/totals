import 'package:flutter/material.dart';

class ChartTypeSelector extends StatelessWidget {
  final String chartType;
  final ValueChanged<String> onChartTypeChanged;

  const ChartTypeSelector({
    super.key,
    required this.chartType,
    required this.onChartTypeChanged,
  });

  IconData _getChartTypeIcon(String chartType) {
    switch (chartType) {
      case 'Line Chart':
        return Icons.show_chart;
      case 'Bar Chart':
        return Icons.bar_chart;
      case 'Pie Chart':
        return Icons.pie_chart;
      case 'P&L Calendar':
        return Icons.calendar_today;
      default:
        return Icons.show_chart;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.2),
        ),
      ),
      child: PopupMenuButton<String>(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getChartTypeIcon(chartType),
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              chartType,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        onSelected: onChartTypeChanged,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'Line Chart',
            child: Row(
              children: [
                Icon(Icons.show_chart, size: 18),
                const SizedBox(width: 12),
                const Text('Line Chart'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'Bar Chart',
            child: Row(
              children: [
                Icon(Icons.bar_chart, size: 18),
                const SizedBox(width: 12),
                const Text('Bar Chart'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'Pie Chart',
            child: Row(
              children: [
                Icon(Icons.pie_chart, size: 18),
                const SizedBox(width: 12),
                const Text('Pie Chart'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'P&L Calendar',
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 18),
                const SizedBox(width: 12),
                const Text('P&L Calendar'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

