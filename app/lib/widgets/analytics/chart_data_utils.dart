import 'package:totals/models/transaction.dart';
import 'chart_data_point.dart';

class ChartDataUtils {
  static List<ChartDataPoint> getChartData(
    List<Transaction> transactions,
    String period,
    DateTime baseDate, {
    DateTime? Function(Transaction)? dateForTransaction,
  }) {
    if (period == 'Week') {
      return getWeeklyData(
        transactions,
        baseDate,
        dateForTransaction: dateForTransaction,
      );
    } else if (period == 'Month') {
      return getMonthlyData(
        transactions,
        baseDate,
        dateForTransaction: dateForTransaction,
      );
    } else {
      return getYearlyData(
        transactions,
        baseDate,
        dateForTransaction: dateForTransaction,
      );
    }
  }

  static DateTime? _getTransactionDate(
    Transaction transaction,
    DateTime? Function(Transaction)? dateForTransaction,
  ) {
    if (dateForTransaction != null) {
      return dateForTransaction(transaction);
    }
    if (transaction.time == null) return null;
    try {
      return DateTime.parse(transaction.time!);
    } catch (_) {
      return null;
    }
  }

  static DateTime _dateOnly(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  static List<ChartDataPoint> getWeeklyData(
    List<Transaction> transactions,
    DateTime baseDate, {
    DateTime? Function(Transaction)? dateForTransaction,
  }) {
    final now = baseDate;
    int daysSinceMonday = (now.weekday - 1) % 7;
    final weekStart =
        DateTime(now.year, now.month, now.day).subtract(Duration(days: daysSinceMonday));
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final totals = List<double>.filled(7, 0.0);

    for (final transaction in transactions) {
      final transactionDate =
          _getTransactionDate(transaction, dateForTransaction);
      if (transactionDate == null) continue;
      final day = _dateOnly(transactionDate);
      final index = day.difference(weekStart).inDays;
      if (index >= 0 && index < totals.length) {
        totals[index] += transaction.amount;
      }
    }

    return List.generate(7, (index) {
      final date = weekStart.add(Duration(days: index));
      return ChartDataPoint(
        label: days[index],
        value: totals[index],
        date: date,
      );
    });
  }

  static List<ChartDataPoint> getMonthlyData(
    List<Transaction> transactions,
    DateTime baseDate, {
    DateTime? Function(Transaction)? dateForTransaction,
  }) {
    final now = baseDate;
    final monthStart = DateTime(now.year, now.month, 1);
    final weeksInMonth = ((now.difference(monthStart).inDays) / 7).ceil();
    final bucketCount = weeksInMonth.clamp(1, 4).toInt();
    final totals = List<double>.filled(bucketCount, 0.0);

    for (final transaction in transactions) {
      final transactionDate =
          _getTransactionDate(transaction, dateForTransaction);
      if (transactionDate == null) continue;
      if (transactionDate.year != now.year ||
          transactionDate.month != now.month) {
        continue;
      }
      final day = _dateOnly(transactionDate);
      final diffDays = day.difference(monthStart).inDays;
      if (diffDays < 0) continue;
      final weekIndex = (diffDays / 7).floor();
      if (weekIndex >= 0 && weekIndex < totals.length) {
        totals[weekIndex] += transaction.amount;
      }
    }

    return List.generate(bucketCount, (index) {
      final weekStart = monthStart.add(Duration(days: index * 7));
      return ChartDataPoint(
        label: 'W${index + 1}',
        value: totals[index],
        date: weekStart,
      );
    });
  }

  static List<ChartDataPoint> getYearlyData(
    List<Transaction> transactions,
    DateTime baseDate, {
    DateTime? Function(Transaction)? dateForTransaction,
  }) {
    final now = baseDate;
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final totals = List<double>.filled(12, 0.0);

    for (final transaction in transactions) {
      final transactionDate =
          _getTransactionDate(transaction, dateForTransaction);
      if (transactionDate == null) continue;
      if (transactionDate.year != now.year) continue;
      final index = transactionDate.month - 1;
      if (index >= 0 && index < totals.length) {
        totals[index] += transaction.amount;
      }
    }

    return List.generate(12, (index) {
      return ChartDataPoint(
        label: months[index],
        value: totals[index],
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

