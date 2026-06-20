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
      expect(out.containsKey('amount'), isFalse, reason: 'renamed, not duplicated');
    });

    test('skips source keys that are absent (no null emitted)', () {
      final out = SyncFieldMapper.apply(src, {'missing': 'x', 'amount': 'value'});
      expect(out, {'value': -9.99});
      expect(out.containsKey('x'), isFalse);
    });

    test('blank target field names are ignored', () {
      final out = SyncFieldMapper.apply(src, {'amount': '   ', 'reference': 'id'});
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
}
