// Residual gaps A1/A2/A4 — reparse merge must persist totalFee when that is
// the only field filled from a reparsed candidate.

import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/account_transaction_reparse_service.dart';

void main() {
  late AccountTransactionReparseService service;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    service = AccountTransactionReparseService();
  });

  group('A1: mergeParsedFields totalFee-only fill', () {
    test('returns updated tx when reparse only supplies totalFee', () {
      final existing = Transaction(
        amount: 100,
        reference: 'REF-A1',
        creditor: 'Shop',
        type: 'DEBIT',
        time: '2026-01-15T10:00:00.000',
      );
      final reparsed = Transaction(
        amount: 100,
        reference: 'REF-A1',
        creditor: 'Shop',
        type: 'DEBIT',
        time: '2026-01-15T10:00:00.000',
        totalFee: 5.5,
      );

      final merged = service.mergeParsedFieldsForTest(existing, reparsed);

      expect(merged, isNotNull,
          reason: 'totalFee-only improvement must not be treated as no-op');
      expect(merged!.totalFee, closeTo(5.5, 0.001));
      expect(merged.reference, 'REF-A1');
      expect(merged.creditor, 'Shop');
    });

    test('returns null when totalFee already present and equal', () {
      final existing = Transaction(
        amount: 100,
        reference: 'REF-A1b',
        totalFee: 5.5,
      );
      final reparsed = Transaction(
        amount: 100,
        reference: 'REF-A1b',
        totalFee: 9.9, // existing wins via _pickAmount
      );

      final merged = service.mergeParsedFieldsForTest(existing, reparsed);

      expect(merged, isNull,
          reason: 'meaningful existing totalFee is kept; no other fields change');
    });

    test('preserves existing totalFee when reparsed omits it', () {
      final existing = Transaction(
        amount: 100,
        reference: 'REF-A1c',
        totalFee: 3.25,
        receiver: null,
      );
      final reparsed = Transaction(
        amount: 100,
        reference: 'REF-A1c',
        receiver: 'New Merchant',
      );

      final merged = service.mergeParsedFieldsForTest(existing, reparsed);

      expect(merged, isNotNull);
      expect(merged!.totalFee, closeTo(3.25, 0.001));
      expect(merged.receiver, 'New Merchant');
    });
  });

  group('A2: mergeExistingTransactionFields totalFee pick', () {
    test('takes candidate totalFee when current has none', () {
      final current = Transaction(
        amount: 50,
        reference: 'REF-A2',
        creditor: 'A',
      );
      final candidate = Transaction(
        amount: 50,
        reference: 'REF-A2',
        creditor: 'A',
        totalFee: 2.0,
      );

      final merged =
          service.mergeExistingTransactionFieldsForTest(current, candidate);

      expect(merged.totalFee, closeTo(2.0, 0.001));
    });

    test('keeps current totalFee when already meaningful', () {
      final current = Transaction(
        amount: 50,
        reference: 'REF-A2b',
        totalFee: 4.0,
      );
      final candidate = Transaction(
        amount: 50,
        reference: 'REF-A2b',
        totalFee: 9.0,
      );

      final merged =
          service.mergeExistingTransactionFieldsForTest(current, candidate);

      expect(merged.totalFee, closeTo(4.0, 0.001));
    });
  });
}
