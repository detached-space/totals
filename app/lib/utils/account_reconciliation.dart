import 'package:totals/models/transaction.dart';
import 'package:totals/utils/transaction_amounts.dart';

class AccountReconciliation {
  final double openingBalance;
  final double closingBalance;
  final double expectedClosingBalance;
  final double adjustment;
  final int comparedBalanceCount;
  final int mismatchCount;
  final Set<String> mismatchedTransactionReferences;
  final List<ReconciliationMismatchPeriod> mismatchPeriods;
  final DateTime startDate;
  final DateTime endDate;

  const AccountReconciliation({
    required this.openingBalance,
    required this.closingBalance,
    required this.expectedClosingBalance,
    required this.adjustment,
    required this.comparedBalanceCount,
    required this.mismatchCount,
    required this.mismatchedTransactionReferences,
    required this.mismatchPeriods,
    required this.startDate,
    required this.endDate,
  });

  bool get isReconciled => adjustment.abs() <= 0.02;
}

class ReconciliationMismatchPeriod {
  final String previousCheckpointReference;
  final DateTime previousCheckpointTime;
  final double previousReportedBalance;
  final List<String> transactionReferences;
  final String checkpointReference;
  final DateTime checkpointTime;
  final double expectedBalance;
  final double reportedBalance;
  final double difference;

  const ReconciliationMismatchPeriod({
    required this.previousCheckpointReference,
    required this.previousCheckpointTime,
    required this.previousReportedBalance,
    required this.transactionReferences,
    required this.checkpointReference,
    required this.checkpointTime,
    required this.expectedBalance,
    required this.reportedBalance,
    required this.difference,
  });
}

AccountReconciliation? reconcileAccountTransactions(
  Iterable<Transaction> transactions,
) {
  final ordered = transactions
      .map((transaction) {
        final time = _parseTime(transaction.time);
        if (time == null) return null;
        return _TimedTransaction(transaction, time);
      })
      .whereType<_TimedTransaction>()
      .toList(growable: true)
    ..sort((left, right) {
      final timeComparison = left.time.compareTo(right.time);
      if (timeComparison != 0) return timeComparison;
      return left.transaction.reference.compareTo(right.transaction.reference);
    });
  if (ordered.isEmpty) return null;

  _TimedTransaction? firstAnchor;
  _TimedTransaction? lastAnchor;
  _TimedTransaction? previousReportedEntry;
  double? previousReportedBalance;
  var deltaSincePreviousBalance = 0.0;
  var mismatchCount = 0;
  var comparedBalanceCount = 0;
  final intervalReferences = <String>[];
  final mismatchedTransactionReferences = <String>{};
  final mismatchPeriods = <ReconciliationMismatchPeriod>[];

  for (final entry in ordered) {
    final transaction = entry.transaction;
    intervalReferences.add(transaction.reference);
    deltaSincePreviousBalance += transactionBalanceDelta(transaction);
    final reportedBalance = _parseBalance(transaction.currentBalance);
    if (reportedBalance == null) continue;

    firstAnchor ??= entry;
    lastAnchor = entry;
    if (previousReportedBalance != null) {
      comparedBalanceCount++;
      final expectedBalance =
          previousReportedBalance + deltaSincePreviousBalance;
      if ((reportedBalance - expectedBalance).abs() > 0.02) {
        mismatchCount++;
        mismatchedTransactionReferences.addAll(intervalReferences);
        mismatchPeriods.add(
          ReconciliationMismatchPeriod(
            previousCheckpointReference:
                previousReportedEntry!.transaction.reference,
            previousCheckpointTime: previousReportedEntry.time,
            previousReportedBalance: previousReportedBalance,
            transactionReferences:
                List<String>.unmodifiable(intervalReferences),
            checkpointReference: transaction.reference,
            checkpointTime: entry.time,
            expectedBalance: expectedBalance,
            reportedBalance: reportedBalance,
            difference: reportedBalance - expectedBalance,
          ),
        );
      }
    }
    previousReportedBalance = reportedBalance;
    previousReportedEntry = entry;
    deltaSincePreviousBalance = 0.0;
    intervalReferences.clear();
  }

  if (firstAnchor == null || lastAnchor == null) return null;
  final firstBalance = _parseBalance(
    firstAnchor.transaction.currentBalance,
  )!;
  final closingBalance = _parseBalance(
    lastAnchor.transaction.currentBalance,
  )!;
  final openingBalance =
      firstBalance - transactionBalanceDelta(firstAnchor.transaction);

  var scopedDelta = 0.0;
  for (final entry in ordered) {
    if (entry.time.isBefore(firstAnchor.time) ||
        entry.time.isAfter(lastAnchor.time)) {
      continue;
    }
    scopedDelta += transactionBalanceDelta(entry.transaction);
  }
  final expectedClosingBalance = openingBalance + scopedDelta;

  return AccountReconciliation(
    openingBalance: openingBalance,
    closingBalance: closingBalance,
    expectedClosingBalance: expectedClosingBalance,
    adjustment: closingBalance - expectedClosingBalance,
    comparedBalanceCount: comparedBalanceCount,
    mismatchCount: mismatchCount,
    mismatchedTransactionReferences:
        Set<String>.unmodifiable(mismatchedTransactionReferences),
    mismatchPeriods: List<ReconciliationMismatchPeriod>.unmodifiable(
      mismatchPeriods,
    ),
    startDate: firstAnchor.time,
    endDate: lastAnchor.time,
  );
}

class _TimedTransaction {
  final Transaction transaction;
  final DateTime time;

  const _TimedTransaction(this.transaction, this.time);
}

DateTime? _parseTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

double? _parseBalance(String? raw) {
  if (raw == null) return null;
  final normalized = raw.trim().replaceAll(',', '');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}
