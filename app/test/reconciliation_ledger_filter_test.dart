import 'package:flutter_test/flutter_test.dart';
import 'package:totals/utils/account_reconciliation.dart';
import 'package:totals/utils/reconciliation_ledger_filter.dart';

void main() {
  final entries = <ReconciliationLedgerEntry>[
    _entry(
      reference: 'older-lower',
      time: DateTime(2026, 1, 1, 10),
      difference: -20,
      bankId: 1,
      accountKey: '1:alpha',
    ),
    _entry(
      reference: 'largest-higher',
      time: DateTime(2026, 2, 1, 10),
      difference: 100,
      bankId: 2,
      accountKey: '2:beta',
    ),
    _entry(
      reference: 'newest-lower',
      time: DateTime(2026, 3, 1, 10),
      difference: -10,
      bankId: 1,
      accountKey: '1:gamma',
    ),
  ];

  test('orders mismatch periods by newest, oldest, or largest difference', () {
    expect(
      _references(entries, const ReconciliationLedgerFilter()),
      <String>['largest-higher', 'older-lower', 'newest-lower'],
    );
    expect(
      _references(
        entries,
        const ReconciliationLedgerFilter(
          sort: ReconciliationLedgerSort.newest,
        ),
      ),
      <String>['newest-lower', 'largest-higher', 'older-lower'],
    );
    expect(
      _references(
        entries,
        const ReconciliationLedgerFilter(
          sort: ReconciliationLedgerSort.oldest,
        ),
      ),
      <String>['older-lower', 'largest-higher', 'newest-lower'],
    );
    expect(
      _references(
        entries,
        const ReconciliationLedgerFilter(
          sort: ReconciliationLedgerSort.largestDifference,
        ),
      ),
      <String>['largest-higher', 'older-lower', 'newest-lower'],
    );
  });

  test('filters inclusively by date, bank, account, and direction', () {
    expect(
      _references(
        entries,
        ReconciliationLedgerFilter(
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 3, 1),
          bankIds: const <int>{1},
          direction: ReconciliationDifferenceDirection.reportedLower,
        ),
      ),
      <String>['older-lower', 'newest-lower'],
    );
    expect(
      _references(
        entries,
        const ReconciliationLedgerFilter(accountKey: '2:beta'),
      ),
      <String>['largest-higher'],
    );
  });

  test('counts non-default ordering and filter groups', () {
    final filter = ReconciliationLedgerFilter(
      sort: ReconciliationLedgerSort.newest,
      startDate: DateTime(2026, 1, 1),
      bankIds: const <int>{1, 2},
      direction: ReconciliationDifferenceDirection.reportedHigher,
    );

    expect(filter.activeCount, 4);
    expect(filter.isActive, isTrue);
    expect(const ReconciliationLedgerFilter().activeCount, 0);
    expect(const ReconciliationLedgerFilter().isActive, isFalse);
  });
}

List<String> _references(
  List<ReconciliationLedgerEntry> entries,
  ReconciliationLedgerFilter filter,
) {
  return filterAndSortReconciliationLedgerEntries(
    entries: entries,
    filter: filter,
  ).map((entry) => entry.period.checkpointReference).toList(growable: false);
}

ReconciliationLedgerEntry _entry({
  required String reference,
  required DateTime time,
  required double difference,
  required int bankId,
  required String accountKey,
}) {
  return ReconciliationLedgerEntry(
    period: ReconciliationMismatchPeriod(
      previousCheckpointReference: 'before-$reference',
      previousCheckpointTime: time.subtract(const Duration(hours: 1)),
      previousReportedBalance: 100,
      transactionReferences: <String>[reference],
      checkpointReference: reference,
      checkpointTime: time,
      expectedBalance: 100,
      reportedBalance: 100 + difference,
      difference: difference,
    ),
    bankId: bankId,
    accountKey: accountKey,
  );
}
