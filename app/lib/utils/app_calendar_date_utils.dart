import 'package:kenat/kenat.dart';
import 'package:totals/theme/app_calendar_option.dart';

class AppCalendarDateUtils {
  const AppCalendarDateUtils._();

  static DateTime ethiopianDateFromParts(int year, int month, int day) {
    final gc = Kenat.fromEthiopian(year, month, day).getGregorian();
    return DateTime(gc['year']!, gc['month']!, gc['day']!);
  }

  static DateTime monthStart(
    DateTime date, {
    required AppCalendarOption calendar,
  }) {
    if (calendar == AppCalendarOption.ethiopian) {
      final ec =
          Kenat.fromGregorian(date.year, date.month, date.day).getEthiopian();
      return ethiopianDateFromParts(ec['year']!, ec['month']!, 1);
    }
    return DateTime(date.year, date.month, 1);
  }

  static DateTime nextMonthStart(
    DateTime date, {
    required AppCalendarOption calendar,
  }) {
    if (calendar == AppCalendarOption.ethiopian) {
      return shiftMonth(
        monthStart(date, calendar: calendar),
        1,
        calendar: calendar,
      );
    }
    final start = monthStart(date, calendar: calendar);
    return DateTime(start.year, start.month + 1, 1);
  }

  static DateTime monthEndInclusive(
    DateTime date, {
    required AppCalendarOption calendar,
  }) {
    return nextMonthStart(date, calendar: calendar)
        .subtract(const Duration(milliseconds: 1));
  }

  static DateTime shiftMonth(
    DateTime date,
    int offset, {
    required AppCalendarOption calendar,
  }) {
    if (calendar == AppCalendarOption.ethiopian) {
      final ec =
          Kenat.fromGregorian(date.year, date.month, date.day).getEthiopian();
      var year = ec['year']!;
      var month = ec['month']! + offset;
      while (month > 13) {
        month -= 13;
        year++;
      }
      while (month < 1) {
        month += 13;
        year--;
      }
      return ethiopianDateFromParts(year, month, 1);
    }
    return DateTime(date.year, date.month + offset, 1);
  }

  static DateTime yearStart(
    DateTime date, {
    required AppCalendarOption calendar,
  }) {
    if (calendar == AppCalendarOption.ethiopian) {
      final ec =
          Kenat.fromGregorian(date.year, date.month, date.day).getEthiopian();
      return ethiopianDateFromParts(ec['year']!, 1, 1);
    }
    return DateTime(date.year, 1, 1);
  }

  static DateTime nextYearStart(
    DateTime date, {
    required AppCalendarOption calendar,
  }) {
    if (calendar == AppCalendarOption.ethiopian) {
      final ec =
          Kenat.fromGregorian(date.year, date.month, date.day).getEthiopian();
      return ethiopianDateFromParts(ec['year']! + 1, 1, 1);
    }
    final start = yearStart(date, calendar: calendar);
    return DateTime(start.year + 1, 1, 1);
  }

  static DateTime periodStart(
    DateTime date,
    String period, {
    required AppCalendarOption calendar,
  }) {
    switch (period) {
      case 'daily':
        return DateTime(date.year, date.month, date.day);
      case 'yearly':
        return yearStart(date, calendar: calendar);
      case 'monthly':
      default:
        return monthStart(date, calendar: calendar);
    }
  }

  static DateTime periodEndInclusive(
    DateTime start,
    String period, {
    required AppCalendarOption calendar,
  }) {
    switch (period) {
      case 'daily':
        return DateTime(start.year, start.month, start.day, 23, 59, 59);
      case 'yearly':
        return nextYearStart(start, calendar: calendar)
            .subtract(const Duration(seconds: 1));
      case 'monthly':
      default:
        return nextMonthStart(start, calendar: calendar)
            .subtract(const Duration(seconds: 1));
    }
  }
}
