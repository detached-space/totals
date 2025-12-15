import 'package:totals/models/transaction.dart';
import 'chart_data_point.dart';

class ChartDataUtils {
  static List<ChartDataPoint> getChartData(
    List<Transaction> transactions,
    String period,
    DateTime baseDate,
  ) {
    if (period == 'Week') {
      return getWeeklyData(transactions, baseDate);
    } else if (period == 'Month') {
      return getMonthlyData(transactions, baseDate);
    } else {
      return getYearlyData(transactions, baseDate);
    }
  }

  static List<ChartDataPoint> getWeeklyData(List<Transaction> transactions, DateTime baseDate) {
    final now = baseDate;
    // Get the start of the week (Monday)
    int daysSinceMonday = (now.weekday - 1) % 7;
    final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysSinceMonday));
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    
    return List.generate(7, (index) {
      final date = weekStart.add(Duration(days: index));
      final dayTransactions = transactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate.year == date.year &&
              transactionDate.month == date.month &&
              transactionDate.day == date.day;
        } catch (e) {
          return false;
        }
      }).toList();
      
      final total = dayTransactions.fold(0.0, (sum, t) => sum + t.amount);
      return ChartDataPoint(
        label: days[index],
        value: total,
        date: date,
      );
    });
  }

  static List<ChartDataPoint> getMonthlyData(List<Transaction> transactions, DateTime baseDate) {
    final now = baseDate;
    final monthStart = DateTime(now.year, now.month, 1);
    final weeksInMonth = ((now.difference(monthStart).inDays) / 7).ceil();
    
    return List.generate(weeksInMonth.clamp(1, 4), (index) {
      final weekStart = monthStart.add(Duration(days: index * 7));
      final weekEnd = weekStart.add(const Duration(days: 6));
      
      final weekTransactions = transactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
              transactionDate.isBefore(weekEnd.add(const Duration(days: 1)));
        } catch (e) {
          return false;
        }
      }).toList();
      
      final total = weekTransactions.fold(0.0, (sum, t) => sum + t.amount);
      return ChartDataPoint(
        label: 'W${index + 1}',
        value: total,
        date: weekStart,
      );
    });
  }

  static List<ChartDataPoint> getYearlyData(List<Transaction> transactions, DateTime baseDate) {
    final now = baseDate;
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    return List.generate(12, (index) {
      final monthTransactions = transactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate.year == now.year && transactionDate.month == index + 1;
        } catch (e) {
          return false;
        }
      }).toList();
      
      final total = monthTransactions.fold(0.0, (sum, t) => sum + t.amount);
      return ChartDataPoint(
        label: months[index],
        value: total,
        date: DateTime(now.year, index + 1, 1),
      );
    });
  }

  static int getCurrentDayIndex(List<ChartDataPoint> data, DateTime baseDate, String period) {
    final now = baseDate;
    
    if (period == 'Week') {
      // Find the index that matches today's date
      for (int i = 0; i < data.length; i++) {
        if (data[i].date != null) {
          final dataDate = data[i].date!;
          if (dataDate.year == now.year &&
              dataDate.month == now.month &&
              dataDate.day == now.day) {
            return i;
          }
        }
      }
      // Fallback: return today's weekday index (0-6, where 0 is Saturday)
      int daysSinceSaturday = (now.weekday + 1) % 7;
      return daysSinceSaturday.clamp(0, data.length - 1);
    } else if (period == 'Month') {
      // Find current week index
      final monthStart = DateTime(now.year, now.month, 1);
      final weekNumber = ((now.difference(monthStart).inDays) / 7).floor();
      return weekNumber.clamp(0, data.length - 1);
    } else {
      // For year view, return current month index
      return (now.month - 1).clamp(0, data.length - 1);
    }
  }
}

