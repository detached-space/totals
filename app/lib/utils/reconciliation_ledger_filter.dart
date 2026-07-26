import 'package:totals/utils/account_reconciliation.dart';

enum ReconciliationLedgerSort {
  newest,
  oldest,
  largestDifference,
}

enum ReconciliationDifferenceDirection {
  reportedLower,
  reportedHigher,
}

class ReconciliationLedgerFilter {
  final ReconciliationLedgerSort sort;
  final DateTime? startDate;
  final DateTime? endDate;
  final Set<int> bankIds;
  final String? accountKey;
  final ReconciliationDifferenceDirection? direction;

  const ReconciliationLedgerFilter({
    this.sort = ReconciliationLedgerSort.largestDifference,
    this.startDate,
    this.endDate,
    this.bankIds = const <int>{},
    this.accountKey,
    this.direction,
  });

  bool get isActive => activeCount > 0;

  int get activeCount {
    var count = 0;
    if (sort != ReconciliationLedgerSort.largestDifference) count++;
    if (startDate != null || endDate != null) count++;
    if (bankIds.isNotEmpty) count++;
    if (accountKey != null) count++;
    if (direction != null) count++;
    return count;
  }
}

class ReconciliationLedgerEntry {
  final ReconciliationMismatchPeriod period;
  final int? bankId;
  final String? accountKey;

  const ReconciliationLedgerEntry({
    required this.period,
    required this.bankId,
    required this.accountKey,
  });
}

List<ReconciliationLedgerEntry> filterAndSortReconciliationLedgerEntries({
  required Iterable<ReconciliationLedgerEntry> entries,
  required ReconciliationLedgerFilter filter,
}) {
  final start = filter.startDate == null
      ? null
      : DateTime(
          filter.startDate!.year,
          filter.startDate!.month,
          filter.startDate!.day,
        );
  final endExclusive = filter.endDate == null
      ? null
      : DateTime(
          filter.endDate!.year,
          filter.endDate!.month,
          filter.endDate!.day + 1,
        );

  final result = entries.where((entry) {
    final period = entry.period;
    if (start != null && period.checkpointTime.isBefore(start)) return false;
    if (endExclusive != null && !period.checkpointTime.isBefore(endExclusive)) {
      return false;
    }
    if (filter.bankIds.isNotEmpty &&
        (entry.bankId == null || !filter.bankIds.contains(entry.bankId))) {
      return false;
    }
    if (filter.accountKey != null && entry.accountKey != filter.accountKey) {
      return false;
    }
    switch (filter.direction) {
      case ReconciliationDifferenceDirection.reportedLower:
        if (period.difference >= 0) return false;
        break;
      case ReconciliationDifferenceDirection.reportedHigher:
        if (period.difference <= 0) return false;
        break;
      case null:
        break;
    }
    return true;
  }).toList(growable: true);

  result.sort((left, right) {
    final leftPeriod = left.period;
    final rightPeriod = right.period;
    switch (filter.sort) {
      case ReconciliationLedgerSort.newest:
        return rightPeriod.checkpointTime.compareTo(
          leftPeriod.checkpointTime,
        );
      case ReconciliationLedgerSort.oldest:
        return leftPeriod.checkpointTime.compareTo(
          rightPeriod.checkpointTime,
        );
      case ReconciliationLedgerSort.largestDifference:
        final differenceComparison =
            rightPeriod.difference.abs().compareTo(leftPeriod.difference.abs());
        if (differenceComparison != 0) return differenceComparison;
        return rightPeriod.checkpointTime.compareTo(
          leftPeriod.checkpointTime,
        );
    }
  });
  return result;
}
