import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/data_sync/sync_models.dart';

void main() {
  group('SyncFilter.matches', () {
    test('empty filter matches everything', () {
      const filter = SyncFilter();
      expect(filter.isEmpty, isTrue);
      expect(filter.matches({'amount': 5, 'type': 'DEBIT'}), isTrue);
      expect(filter.matches(const {}), isTrue);
    });

    test('type matches case-insensitively', () {
      const filter = SyncFilter(type: 'DEBIT');
      expect(filter.matches({'type': 'DEBIT'}), isTrue);
      expect(filter.matches({'type': 'debit'}), isTrue);
      expect(filter.matches({'type': 'CREDIT'}), isFalse);
      expect(filter.matches(const {}), isFalse);
    });

    test('min/max amount compare on absolute value', () {
      const filter = SyncFilter(minAmount: 500);
      expect(filter.matches({'amount': 500}), isTrue);
      expect(filter.matches({'amount': -500}), isTrue, reason: 'debits are negative');
      expect(filter.matches({'amount': -499.99}), isFalse);
      expect(filter.matches({'amount': '600'}), isTrue, reason: 'string coercion');

      const range = SyncFilter(minAmount: 100, maxAmount: 1000);
      expect(range.matches({'amount': -50}), isFalse);
      expect(range.matches({'amount': 500}), isTrue);
      expect(range.matches({'amount': 1001}), isFalse);
      expect(range.matches({'amount': null}), isFalse);
    });

    test('bankIds match transactions (bankId) and accounts (bank)', () {
      const filter = SyncFilter(bankIds: [1, 3]);
      expect(filter.matches({'bankId': 1}), isTrue);
      expect(filter.matches({'bank': 3}), isTrue);
      expect(filter.matches({'bankId': 2}), isFalse);
      expect(filter.matches(const {}), isFalse);
    });

    test('accountKeys match exact (accounts) and by last-4 suffix (txns)', () {
      const filter = SyncFilter(accountKeys: ['1000001234|1']);
      expect(filter.matches({'accountNumber': '1000001234', 'bank': 1}), isTrue);
      expect(filter.matches({'accountNumber': '1234', 'bankId': 1}), isTrue);
      expect(filter.matches({'accountNumber': '1234', 'bankId': 2}), isFalse);
      expect(filter.matches({'accountNumber': '9999', 'bankId': 1}), isFalse);
    });

    test('bank vs account selection is ORed', () {
      const filter = SyncFilter(bankIds: [1], accountKeys: ['5555|2']);
      expect(filter.matches({'bankId': 1, 'accountNumber': '0001'}), isTrue);
      expect(filter.matches({'bankId': 2, 'accountNumber': '5555'}), isTrue);
      expect(filter.matches({'bankId': 3, 'accountNumber': '0002'}), isFalse);
    });

    test('date range matches against time/createdAt/startDate', () {
      final filter = SyncFilter(
        startDate: DateTime.parse('2024-01-01T00:00:00Z'),
        endDate: DateTime.parse('2024-12-31T23:59:59Z'),
      );
      expect(filter.matches({'time': '2024-06-15T10:00:00Z'}), isTrue);
      expect(filter.matches({'time': '2023-06-15T10:00:00Z'}), isFalse);
      expect(filter.matches({'createdAt': '2024-02-01T10:00:00Z'}), isTrue);
      expect(filter.matches({'time': null}), isFalse);
    });

    test('isActive coerces int/bool', () {
      const filter = SyncFilter(isActive: true);
      expect(filter.matches({'isActive': true}), isTrue);
      expect(filter.matches({'isActive': 1}), isTrue);
      expect(filter.matches({'isActive': 0}), isFalse);
      expect(filter.matches({'isActive': false}), isFalse);
    });

    test('profileId scopes records', () {
      const filter = SyncFilter(profileId: 3);
      expect(filter.matches({'profileId': 3}), isTrue);
      expect(filter.matches({'profileId': 4}), isFalse);
      expect(filter.matches(const {}), isFalse);
    });

    test('multiple fields are ANDed', () {
      const filter = SyncFilter(type: 'DEBIT', minAmount: 100, bankIds: [1]);
      expect(
        filter.matches({'type': 'DEBIT', 'amount': -200, 'bankId': 1}),
        isTrue,
      );
      expect(
        filter.matches({'type': 'DEBIT', 'amount': -50, 'bankId': 1}),
        isFalse,
      );
      expect(
        filter.matches({'type': 'CREDIT', 'amount': -200, 'bankId': 1}),
        isFalse,
      );
    });

    test('encode/decode round-trip; empty encodes to null', () {
      const empty = SyncFilter();
      expect(empty.encode(), isNull);
      expect(SyncFilter.decode(null), isNull);
      expect(SyncFilter.decode('  '), isNull);

      final filter = SyncFilter(
        type: 'CREDIT',
        minAmount: 10,
        bankIds: [2, 4],
        accountKeys: ['1234|2'],
        startDate: DateTime.parse('2024-01-01T00:00:00.000Z'),
        isActive: false,
        profileId: 7,
      );
      final decoded = SyncFilter.decode(filter.encode());
      expect(decoded, isNotNull);
      expect(decoded!.type, 'CREDIT');
      expect(decoded.minAmount, 10);
      expect(decoded.bankIds, [2, 4]);
      expect(decoded.accountKeys, ['1234|2']);
      expect(decoded.isActive, isFalse);
      expect(decoded.profileId, 7);
      expect(decoded.startDate, DateTime.parse('2024-01-01T00:00:00.000Z'));
    });

    test('decodes legacy single bankId into bankIds', () {
      final decoded = SyncFilter.decode('{"bankId":5}');
      expect(decoded, isNotNull);
      expect(decoded!.bankIds, [5]);
    });
  });

  group('syncEntityRef', () {
    test('transactions use reference', () {
      expect(syncEntityRef(SyncEntity.transactions, {'reference': 'ABC123'}), 'ABC123');
      expect(syncEntityRef(SyncEntity.transactions, {'reference': '  '}), isNull);
      expect(syncEntityRef(SyncEntity.transactions, const {}), isNull);
    });

    test('accounts use accountNumber|bank', () {
      expect(
        syncEntityRef(SyncEntity.accounts, {'accountNumber': '1234', 'bank': 1}),
        '1234|1',
      );
      expect(syncEntityRef(SyncEntity.accounts, {'accountNumber': '1234'}), isNull);
    });

    test('budgets use budget:id', () {
      expect(syncEntityRef(SyncEntity.budgets, {'id': 9}), 'budget:9');
      expect(syncEntityRef(SyncEntity.budgets, const {}), isNull);
    });
  });
}
