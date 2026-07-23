// Residual gap B1 — optional fee fields must stay null when absent in JSON,
// not silently become 0.0.

import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/transaction.dart';

void main() {
  group('B1: Transaction.fromJson optional fees', () {
    test('missing serviceCharge/vat/totalFee stay null', () {
      final tx = Transaction.fromJson({
        'amount': 100,
        'reference': 'REF-B1',
      });

      expect(tx.amount, 100);
      expect(tx.serviceCharge, isNull);
      expect(tx.vat, isNull);
      expect(tx.totalFee, isNull);
    });

    test('explicit null fee keys stay null', () {
      final tx = Transaction.fromJson({
        'amount': 100,
        'reference': 'REF-B1b',
        'serviceCharge': null,
        'vat': null,
        'totalFee': null,
      });

      expect(tx.serviceCharge, isNull);
      expect(tx.vat, isNull);
      expect(tx.totalFee, isNull);
    });

    test('present fee values parse correctly including zero', () {
      final tx = Transaction.fromJson({
        'amount': 100,
        'reference': 'REF-B1c',
        'serviceCharge': 1.5,
        'vat': 0.0,
        'totalFee': '2.75',
      });

      expect(tx.serviceCharge, closeTo(1.5, 0.001));
      expect(tx.vat, 0.0);
      expect(tx.totalFee, closeTo(2.75, 0.001));
    });

    test('toJson omits null fees and includes present ones', () {
      final withFees = Transaction.fromJson({
        'amount': 10,
        'reference': 'R',
        'totalFee': 1.0,
      });
      final withoutFees = Transaction.fromJson({
        'amount': 10,
        'reference': 'R',
      });

      expect(withFees.toJson().containsKey('totalFee'), isTrue);
      expect(withoutFees.toJson().containsKey('totalFee'), isFalse);
      expect(withoutFees.toJson().containsKey('serviceCharge'), isFalse);
      expect(withoutFees.toJson().containsKey('vat'), isFalse);
    });
  });
}
