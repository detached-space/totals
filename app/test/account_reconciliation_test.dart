import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/account_reconciliation.dart';

void main() {
  test('reconciles balance history including fees and VAT', () {
    final result = reconcileAccountTransactions(<Transaction>[
      _transaction(
        reference: 'credit',
        type: 'CREDIT',
        amount: 200,
        time: '2026-01-01T10:00:00',
        balance: '300',
      ),
      _transaction(
        reference: 'debit',
        type: 'DEBIT',
        amount: 50,
        time: '2026-01-02T10:00:00',
        balance: '244.25',
        serviceCharge: 5,
        vat: .75,
      ),
    ]);

    expect(result, isNotNull);
    expect(result!.openingBalance, 100);
    expect(result.expectedClosingBalance, 244.25);
    expect(result.closingBalance, 244.25);
    expect(result.adjustment, closeTo(0, .001));
    expect(result.mismatchCount, 0);
    expect(result.mismatchedTransactionReferences, isEmpty);
    expect(result.mismatchPeriods, isEmpty);
  });

  test('reports missing imported activity as an adjustment', () {
    final result = reconcileAccountTransactions(<Transaction>[
      _transaction(
        reference: 'credit',
        type: 'CREDIT',
        amount: 200,
        time: '2026-01-01T10:00:00',
        balance: '200',
      ),
      _transaction(
        reference: 'later-credit',
        type: 'CREDIT',
        amount: 50,
        time: '2026-01-02T10:00:00',
        balance: '100',
      ),
    ]);

    expect(result, isNotNull);
    expect(result!.expectedClosingBalance, 250);
    expect(result.closingBalance, 100);
    expect(result.adjustment, -150);
    expect(result.mismatchCount, 1);
    expect(result.mismatchedTransactionReferences, <String>{'later-credit'});
    expect(result.mismatchPeriods, hasLength(1));
    final period = result.mismatchPeriods.single;
    expect(period.previousCheckpointReference, 'credit');
    expect(period.previousReportedBalance, 200);
    expect(period.transactionReferences, <String>['later-credit']);
    expect(period.checkpointReference, 'later-credit');
    expect(period.expectedBalance, 250);
    expect(period.reportedBalance, 100);
    expect(period.difference, -150);
  });

  test('includes every transaction in a mismatched balance interval', () {
    final result = reconcileAccountTransactions(<Transaction>[
      _transaction(
        reference: 'opening-anchor',
        type: 'CREDIT',
        amount: 100,
        time: '2026-01-01T10:00:00',
        balance: '100',
      ),
      Transaction(
        amount: 20,
        reference: 'without-balance',
        type: 'DEBIT',
        time: '2026-01-01T11:00:00',
      ),
      _transaction(
        reference: 'mismatched-anchor',
        type: 'DEBIT',
        amount: 10,
        time: '2026-01-01T12:00:00',
        balance: '50',
      ),
    ]);

    expect(result, isNotNull);
    expect(result!.mismatchCount, 1);
    expect(
      result.mismatchedTransactionReferences,
      <String>{'without-balance', 'mismatched-anchor'},
    );
    expect(
      result.mismatchPeriods.single.transactionReferences,
      <String>['without-balance', 'mismatched-anchor'],
    );
  });

  test('keeps consecutive mismatches as separate ledger periods', () {
    final result = reconcileAccountTransactions(<Transaction>[
      _transaction(
        reference: 'opening',
        type: 'CREDIT',
        amount: 100,
        time: '2026-01-01T10:00:00',
        balance: '100',
      ),
      _transaction(
        reference: 'first-mismatch',
        type: 'CREDIT',
        amount: 20,
        time: '2026-01-01T11:00:00',
        balance: '50',
      ),
      _transaction(
        reference: 'second-mismatch',
        type: 'DEBIT',
        amount: 10,
        time: '2026-01-01T12:00:00',
        balance: '50',
      ),
    ]);

    expect(result, isNotNull);
    expect(result!.mismatchPeriods, hasLength(2));
    expect(
      result.mismatchPeriods[0].transactionReferences,
      <String>['first-mismatch'],
    );
    expect(result.mismatchPeriods[0].difference, -70);
    expect(result.mismatchPeriods[1].previousReportedBalance, 50);
    expect(
      result.mismatchPeriods[1].transactionReferences,
      <String>['second-mismatch'],
    );
    expect(result.mismatchPeriods[1].difference, 10);
  });
}

Transaction _transaction({
  required String reference,
  required String type,
  required double amount,
  required String time,
  required String balance,
  double? serviceCharge,
  double? vat,
}) {
  return Transaction(
    amount: amount,
    reference: reference,
    type: type,
    time: time,
    currentBalance: balance,
    serviceCharge: serviceCharge,
    vat: vat,
  );
}
