import 'package:intl/intl.dart';

String formatNumberWithComma(double? number) {
  if (number == null) return '0.00';
  return number.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (Match match) => '${match[1]},',
      );
}

String formatNumberAbbreviated(double? number) {
  if (number == null) return '0';

  final value = number.abs();

  if (value >= 1000000) {
    // Round to nearest 100k for millions
    final rounded = (value / 100000).round() / 10.0;
    final formatted = rounded % 1 == 0
        ? rounded.toInt().toString()
        : rounded.toString();
    return '${number < 0 ? '-' : ''}$formatted M';
  } else if (value >= 1000) {
    // Round to nearest 100 for thousands
    final rounded = (value / 100).round() / 10.0;
    final formatted = rounded % 1 == 0
        ? rounded.toInt().toString()
        : rounded.toString();
    return '${number < 0 ? '-' : ''}$formatted k';
  } else {
    // For values less than 1000, show as is (rounded to nearest integer)
    return '${number < 0 ? '-' : ''}${value.round()}';
  }
}

/// Compact representation for large amounts: 1234567 → "1.2M", 125000 →
/// "125K". Designed for the shared-expense balance card where a long
/// "1,234,567.00" would overflow. Use [formatNumberWithComma] when the
/// exact figure matters (expense detail rows, settlement amounts).
///
/// Format rules:
///  - <1K → whole-number rounding ("847")
///  - 1K..999K → one decimal max, no trailing .0 ("12K", "12.5K", "999K")
///  - 1M..999M → same ("1.2M")
///  - >=1B → same ("3.4B")
String formatAmountCompact(double? number) {
  if (number == null) return '0';
  final value = number.abs();
  final sign = number < 0 ? '-' : '';

  String trim1(double v) {
    final r = (v * 10).round() / 10.0;
    if (r == r.truncateToDouble()) return r.toInt().toString();
    return r.toStringAsFixed(1);
  }

  if (value >= 1e9) return '$sign${trim1(value / 1e9)}B';
  if (value >= 1e6) return '$sign${trim1(value / 1e6)}M';
  if (value >= 1e3) return '$sign${trim1(value / 1e3)}K';
  return '$sign${value.round()}';
}

String formatTime(String input) {
  try {
    DateTime dateTime;

    // Check if the input contains a full timestamp
    if (input.contains('-')) {
      // Parse a full timestamp like "2025-03-10 22:19:45.573278"
      dateTime = DateTime.parse(input);
    } else {
      // If only time is provided, assume today's date
      DateTime now = DateTime.now();
      List<String> timeParts = input.split('.')[0].split(':');

      if (timeParts.length < 3) {
        throw FormatException("Invalid time format");
      }

      dateTime = DateTime(now.year, now.month, now.day, int.parse(timeParts[0]),
          int.parse(timeParts[1]), int.parse(timeParts[2]));
    }

    // Format the date and time
    return DateFormat("dd MMM yyyy | HH:mm").format(dateTime);
  } catch (e) {
    return "Invalid time input";
  }
}

String formatTelebirrSenderName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final hasDigits = RegExp(r'\d').hasMatch(trimmed);
  if (!hasDigits && !trimmed.contains('(')) return trimmed;
  final base = trimmed.split('(').first.trim();
  if (base.isEmpty) return trimmed;
  final parts = base.split(RegExp(r'\s+'));
  if (parts.isEmpty) return trimmed;
  if (parts.length == 1) return parts.first;
  return '${parts.first} ${parts[1]}';
}
