import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/transaction.dart';

void main() {
  group('Transaction.fromJson', () {
    test('parses all fields from a complete map', () {
      final json = {
        'amount': 500.0,
        'reference': 'FT12345',
        'creditor': 'John Doe',
        'receiver': 'Jane Doe',
        'time': '2025-01-01T10:00:00.000',
        'status': 'CLEARED',
        'currentBalance': '10000.00',
        'bankId': 1,
        'type': 'DEBIT',
        'transactionLink': 'https://example.com',
        'accountNumber': '6068',
        'categoryId': 3,
        'profileId': 1,
        'serviceCharge': 5.0,
        'vat': 0.75,
      };

      final tx = Transaction.fromJson(json);

      expect(tx.amount, equals(500.0));
      expect(tx.reference, equals('FT12345'));
      expect(tx.creditor, equals('John Doe'));
      expect(tx.receiver, equals('Jane Doe'));
      expect(tx.time, equals('2025-01-01T10:00:00.000'));
      expect(tx.status, equals('CLEARED'));
      expect(tx.currentBalance, equals('10000.00'));
      expect(tx.bankId, equals(1));
      expect(tx.type, equals('DEBIT'));
      expect(tx.accountNumber, equals('6068'));
      expect(tx.categoryId, equals(3));
      expect(tx.profileId, equals(1));
      expect(tx.serviceCharge, equals(5.0));
      expect(tx.vat, equals(0.75));
    });

    test('uses empty string for missing reference', () {
      final tx = Transaction.fromJson({'amount': 100.0});
      expect(tx.reference, equals(''));
      expect(tx.amount, equals(100.0));
    });

    test('parses amount from string', () {
      final tx = Transaction.fromJson({'amount': '250.75', 'reference': 'REF'});
      expect(tx.amount, equals(250.75));
    });

    test('parses amount from int', () {
      final tx = Transaction.fromJson({'amount': 100, 'reference': 'REF'});
      expect(tx.amount, equals(100.0));
    });

    test('defaults to 0.0 for unparseable amount', () {
      final tx = Transaction.fromJson({'amount': 'bad', 'reference': 'REF'});
      expect(tx.amount, equals(0.0));
    });

    test('null optional fields remain null', () {
      final tx = Transaction.fromJson({'amount': 10.0, 'reference': 'REF'});
      expect(tx.creditor, isNull);
      expect(tx.bankId, isNull);
      expect(tx.categoryId, isNull);
    });
  });

  group('Transaction.toJson', () {
    test('serializes all non-null fields', () {
      final tx = Transaction(
        amount: 100.0,
        reference: 'FT99',
        type: 'CREDIT',
        bankId: 2,
        accountNumber: '1234',
        serviceCharge: 2.5,
        vat: 0.375,
        profileId: 1,
      );

      final json = tx.toJson();

      expect(json['amount'], equals(100.0));
      expect(json['reference'], equals('FT99'));
      expect(json['type'], equals('CREDIT'));
      expect(json['bankId'], equals(2));
      expect(json['accountNumber'], equals('1234'));
      expect(json['serviceCharge'], equals(2.5));
      expect(json['vat'], equals(0.375));
      expect(json['profileId'], equals(1));
    });

    test('omits profileId when null', () {
      final tx = Transaction(amount: 50.0, reference: 'REF');
      final json = tx.toJson();
      expect(json.containsKey('profileId'), isFalse);
    });

    test('omits serviceCharge when null', () {
      final tx = Transaction(amount: 50.0, reference: 'REF');
      final json = tx.toJson();
      expect(json.containsKey('serviceCharge'), isFalse);
    });

    test('omits vat when null', () {
      final tx = Transaction(amount: 50.0, reference: 'REF');
      final json = tx.toJson();
      expect(json.containsKey('vat'), isFalse);
    });
  });

  group('Transaction.copyWith', () {
    final original = Transaction(
      amount: 200.0,
      reference: 'ORIG',
      type: 'DEBIT',
      bankId: 1,
      categoryId: 5,
    );

    test('returns copy with updated amount', () {
      final copy = original.copyWith(amount: 999.0);
      expect(copy.amount, equals(999.0));
      expect(copy.reference, equals('ORIG'));
    });

    test('preserves unchanged fields', () {
      final copy = original.copyWith(type: 'CREDIT');
      expect(copy.type, equals('CREDIT'));
      expect(copy.bankId, equals(1));
      expect(copy.categoryId, equals(5));
    });

    test('clears categoryId when clearCategoryId is true', () {
      final copy = original.copyWith(clearCategoryId: true);
      expect(copy.categoryId, isNull);
    });

    test('keeps categoryId when clearCategoryId is false (default)', () {
      final copy = original.copyWith(amount: 1.0);
      expect(copy.categoryId, equals(5));
    });
  });
}
