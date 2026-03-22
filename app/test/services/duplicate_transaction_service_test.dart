import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/duplicate_transaction_service.dart';

Transaction makeTransaction({
  required String reference,
  required double amount,
  required String time,
  String type = 'DEBIT',
  int? bankId,
  String? accountNumber,
}) {
  return Transaction(
    amount: amount,
    reference: reference,
    type: type,
    time: time,
    bankId: bankId,
    accountNumber: accountNumber,
  );
}

void main() {
  final service = DuplicateTransactionService();

  const String t0 = '2025-01-01T10:00:00.000';
  const String t30s = '2025-01-01T10:00:30.000'; // 30 seconds later
  const String t59s = '2025-01-01T10:00:59.000'; // 59 seconds later
  const String t60s = '2025-01-01T10:01:00.000'; // exactly 60 seconds later
  const String t61s = '2025-01-01T10:01:01.000'; // 61 seconds later

  group('DuplicateTransactionService.findDuplicates', () {
    test('returns empty list when no transactions', () {
      expect(service.findDuplicates([]), isEmpty);
    });

    test('returns empty list for a single transaction', () {
      final tx = makeTransaction(reference: 'A', amount: 100, time: t0);
      expect(service.findDuplicates([tx]), isEmpty);
    });

    test('detects duplicate with same amount, type, within time window', () {
      final a = makeTransaction(reference: 'A', amount: 500.0, time: t0);
      final b = makeTransaction(reference: 'B', amount: 500.0, time: t30s);
      final result = service.findDuplicates([a, b]);
      expect(result.length, equals(1));
      expect(result.first.timeDelta.inSeconds, equals(30));
    });

    test('does not flag when amounts differ beyond tolerance', () {
      final a = makeTransaction(reference: 'A', amount: 500.0, time: t0);
      final b = makeTransaction(reference: 'B', amount: 501.0, time: t30s);
      expect(service.findDuplicates([a, b]), isEmpty);
    });

    test('does not flag when types differ', () {
      final a = makeTransaction(reference: 'A', amount: 500.0, time: t0, type: 'CREDIT');
      final b = makeTransaction(reference: 'B', amount: 500.0, time: t30s, type: 'DEBIT');
      expect(service.findDuplicates([a, b]), isEmpty);
    });

    test('flags duplicate when time delta is exactly 60s (boundary inclusive)', () {
      final a = makeTransaction(reference: 'A', amount: 500.0, time: t0);
      final b = makeTransaction(reference: 'B', amount: 500.0, time: t60s);
      // service uses: if (delta > timeWindow) break
      // delta == timeWindow is NOT > timeWindow, so the pair is still checked
      expect(service.findDuplicates([a, b]).length, equals(1));
    });

    test('detects duplicate within 59 seconds', () {
      final a = makeTransaction(reference: 'A', amount: 500.0, time: t0);
      final b = makeTransaction(reference: 'B', amount: 500.0, time: t59s);
      expect(service.findDuplicates([a, b]).length, equals(1));
    });

    test('does not flag when time delta exceeds window', () {
      final a = makeTransaction(reference: 'A', amount: 500.0, time: t0);
      final b = makeTransaction(reference: 'B', amount: 500.0, time: t61s);
      expect(service.findDuplicates([a, b]), isEmpty);
    });

    test('flags transactions with same reference as suspected duplicate', () {
      final a = makeTransaction(reference: 'SAME', amount: 500.0, time: t0);
      final b = makeTransaction(reference: 'SAME', amount: 500.0, time: t30s);
      // findDuplicates has no same-reference exclusion; only checkIncoming does
      expect(service.findDuplicates([a, b]).length, equals(1));
    });

    test('does not flag when different bank IDs are set', () {
      final a = makeTransaction(reference: 'A', amount: 500.0, time: t0, bankId: 1);
      final b = makeTransaction(reference: 'B', amount: 500.0, time: t30s, bankId: 2);
      expect(service.findDuplicates([a, b]), isEmpty);
    });

    test('does not flag when different account numbers are set', () {
      final a = makeTransaction(reference: 'A', amount: 500.0, time: t0, accountNumber: '1234');
      final b = makeTransaction(reference: 'B', amount: 500.0, time: t30s, accountNumber: '5678');
      expect(service.findDuplicates([a, b]), isEmpty);
    });

    test('skips transactions with null time', () {
      final a = Transaction(amount: 500.0, reference: 'A', type: 'DEBIT');
      final b = makeTransaction(reference: 'B', amount: 500.0, time: t0);
      expect(service.findDuplicates([a, b]), isEmpty);
    });

    test('each transaction is used in at most one pair', () {
      final a = makeTransaction(reference: 'A', amount: 100.0, time: t0);
      final b = makeTransaction(reference: 'B', amount: 100.0, time: t30s);
      final c = makeTransaction(reference: 'C', amount: 100.0, time: t59s);
      // A-B is a pair; C should not be paired with anything
      final result = service.findDuplicates([a, b, c]);
      expect(result.length, equals(1));
    });

    test('amount tolerance allows tiny floating point difference', () {
      final a = makeTransaction(reference: 'A', amount: 100.0, time: t0);
      final b = makeTransaction(reference: 'B', amount: 100.005, time: t30s);
      expect(service.findDuplicates([a, b]).length, equals(1));
    });
  });

  group('DuplicateTransactionService.checkIncoming', () {
    test('returns null when no existing transactions', () {
      final incoming = makeTransaction(reference: 'NEW', amount: 200.0, time: t30s);
      expect(service.checkIncoming(incoming, []), isNull);
    });

    test('detects incoming as duplicate of existing', () {
      final existing = makeTransaction(reference: 'OLD', amount: 200.0, time: t0);
      final incoming = makeTransaction(reference: 'NEW', amount: 200.0, time: t30s);
      final result = service.checkIncoming(incoming, [existing]);
      expect(result, isNotNull);
      expect(result!.timeDelta.inSeconds, equals(30));
    });

    test('returns null when amounts differ beyond tolerance', () {
      final existing = makeTransaction(reference: 'OLD', amount: 200.0, time: t0);
      final incoming = makeTransaction(reference: 'NEW', amount: 300.0, time: t30s);
      expect(service.checkIncoming(incoming, [existing]), isNull);
    });

    test('returns null when time delta exceeds window', () {
      final existing = makeTransaction(reference: 'OLD', amount: 200.0, time: t0);
      final incoming = makeTransaction(reference: 'NEW', amount: 200.0, time: t61s);
      expect(service.checkIncoming(incoming, [existing]), isNull);
    });

    test('skips existing transaction with same reference as incoming', () {
      final existing = makeTransaction(reference: 'SAME', amount: 200.0, time: t0);
      final incoming = makeTransaction(reference: 'SAME', amount: 200.0, time: t30s);
      expect(service.checkIncoming(incoming, [existing]), isNull);
    });

    test('returns null when incoming has no time', () {
      final existing = makeTransaction(reference: 'OLD', amount: 200.0, time: t0);
      final incoming = Transaction(amount: 200.0, reference: 'NEW', type: 'DEBIT');
      expect(service.checkIncoming(incoming, [existing]), isNull);
    });
  });
}
