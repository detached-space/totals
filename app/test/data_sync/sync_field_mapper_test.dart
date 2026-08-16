import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/data_sync/sync_models.dart';

void main() {
  group('SyncFieldMapper.apply', () {
    final src = {
      'amount': -9.99,
      'reference': 'TX1',
      'time': '2024-01-01T00:00:00Z',
      'note': 'coffee',
    };

    test('null/empty map = identity (copy)', () {
      final out = SyncFieldMapper.apply(src, null);
      expect(out, equals(src));
      expect(identical(out, src), isFalse, reason: 'should be a copy');
      expect(SyncFieldMapper.apply(src, const {}), equals(src));
    });

    test('renames mapped fields and drops the rest by default', () {
      final out = SyncFieldMapper.apply(src, {
        'amount': 'value',
        'reference': 'external_id',
      });
      expect(out, {'value': -9.99, 'external_id': 'TX1'});
      expect(out.containsKey('time'), isFalse);
      expect(out.containsKey('note'), isFalse);
    });

    test('includeUnmapped keeps unmapped fields under original names', () {
      final out = SyncFieldMapper.apply(
        src,
        {'amount': 'value'},
        includeUnmapped: true,
      );
      expect(out['value'], -9.99);
      expect(out['reference'], 'TX1');
      expect(out['note'], 'coffee');
      expect(out.containsKey('amount'), isFalse,
          reason: 'renamed, not duplicated');
    });

    test('skips source keys that are absent (no null emitted)', () {
      final out =
          SyncFieldMapper.apply(src, {'missing': 'x', 'amount': 'value'});
      expect(out, {'value': -9.99});
      expect(out.containsKey('x'), isFalse);
    });

    test('blank target field names are ignored', () {
      final out =
          SyncFieldMapper.apply(src, {'amount': '   ', 'reference': 'id'});
      expect(out, {'id': 'TX1'});
    });

    test('decode/encode round-trip', () {
      const raw = '{"amount":"value","reference":"id"}';
      final decoded = SyncFieldMapper.decode(raw);
      expect(decoded, {'amount': 'value', 'reference': 'id'});
      expect(SyncFieldMapper.decode(null), isEmpty);
      expect(SyncFieldMapper.decode('not json'), isEmpty);
      expect(SyncFieldMapper.encode(const {}), isNull);
      expect(SyncFieldMapper.encode({'a': 'b'}), '{"a":"b"}');
    });
  });

  group('SyncTransactionCategoryPayload', () {
    test('exposes category enrichment fields for transaction mappings', () {
      expect(
        SyncEntity.transactions.fieldKeys,
        containsAllInOrder([
          'categoryId',
          'categoryIds',
          'categoryNames',
        ]),
      );
    });

    test('exposes enriched account fields for mappings', () {
      expect(
        SyncEntity.accounts.fieldKeys,
        containsAllInOrder([
          'bank',
          'bankName',
          'bankShortName',
          'balance',
        ]),
      );
    });

    test('exposes enriched budget fields for mappings', () {
      expect(
        SyncEntity.budgets.fieldKeys,
        containsAll([
          'categoryNames',
          'appliesToAllExpenses',
          'usedAmount',
          'availableAmount',
          'percentageUsed',
          'isExceeded',
          'isApproachingLimit',
          'periodStart',
          'periodEnd',
          'isRecurring',
          'recurrence',
        ]),
      );
    });

    test('orders category names to match the transaction category selection',
        () {
      final payload = SyncTransactionCategoryPayload.enrich(
        {
          'reference': 'TX1',
          'amount': -120,
          'categoryId': 2,
          'categoryIds': [2, 5],
        },
        [
          {
            'id': 5,
            'name': 'Transport',
            'flow': 'expense',
            'essential': true,
          },
          {
            'id': 2,
            'name': 'Food',
            'flow': 'expense',
            'essential': false,
          },
        ],
      );

      expect(payload['categoryNames'], ['Food', 'Transport']);
      expect(payload['categoryId'], 2);
      expect(payload['categoryIds'], [2, 5]);
      expect(payload.containsKey('categoryName'), isFalse);
      expect(payload.containsKey('category'), isFalse);
      expect(payload.containsKey('categories'), isFalse);
    });

    test('keeps explicit empty category fields for uncategorized transactions',
        () {
      final payload = SyncTransactionCategoryPayload.enrich(
        {
          'reference': 'TX2',
          'amount': -30,
          'categoryId': null,
          'categoryIds': null,
        },
        const [],
      );

      expect(payload['categoryNames'], isEmpty);
      expect(payload.containsKey('categoryName'), isFalse);
      expect(payload.containsKey('category'), isFalse);
      expect(payload.containsKey('categories'), isFalse);
    });

    test('decodes category ids from legacy stored shapes', () {
      expect(
        SyncTransactionCategoryPayload.categoryIdsFor({
          'categoryId': 3,
          'categoryIds': '[4, 3, "5"]',
        }),
        [3, 4, 5],
      );
      expect(
        SyncTransactionCategoryPayload.categoryIdsFor({
          'categoryIds': '7,8,7',
        }),
        [7, 8],
      );
    });
  });
}
