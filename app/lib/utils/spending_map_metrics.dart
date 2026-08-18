import 'package:intl/intl.dart';

enum SpendingMapPuckMetric { transactionCount, netAmount }

double spendingMapNetContribution({
  required String? transactionType,
  required double? amount,
}) {
  if (amount == null || !amount.isFinite) return 0;
  final magnitude = amount.abs();
  return switch (transactionType?.trim().toUpperCase()) {
    'CREDIT' => magnitude,
    'DEBIT' => -magnitude,
    _ => 0,
  };
}

String formatSpendingMapNetPuckLabel(double netAmount) {
  if (!netAmount.isFinite || netAmount.abs() < 0.005) return '0';
  final sign = netAmount > 0 ? '+' : '-';
  final compact = NumberFormat.compact(
    locale: 'en',
  ).format(netAmount.abs()).replaceAll(' ', '');
  return '$sign$compact';
}
