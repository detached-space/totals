import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/data_sync/sync_models.dart';

void main() {
  group('SyncPathTemplate.resolve', () {
    test('substitutes placeholders and joins base + path', () {
      final uri = SyncPathTemplate.resolve(
        'https://api.example.com',
        '/txns/{reference}',
        {'reference': 'ABC123'},
      );
      expect(uri.toString(), 'https://api.example.com/txns/ABC123');
    });

    test('handles trailing slash on base and missing leading slash on path', () {
      final uri = SyncPathTemplate.resolve(
        'https://api.example.com/',
        'txns',
        const {},
      );
      expect(uri.toString(), 'https://api.example.com/txns');
    });

    test('percent-encodes placeholder values', () {
      final uri = SyncPathTemplate.resolve(
        'https://api.example.com',
        '/p/{reference}',
        {'reference': 'a b/c?d'},
      );
      expect(uri.toString(), 'https://api.example.com/p/a%20b%2Fc%3Fd');
    });

    test('empty path returns the base', () {
      final uri = SyncPathTemplate.resolve('https://api.example.com', '', const {});
      expect(uri.toString(), 'https://api.example.com');
    });

    test('throws when a placeholder has no value', () {
      expect(
        () => SyncPathTemplate.resolve('https://x.io', '/t/{reference}', const {}),
        throwsA(isA<SyncTemplateException>()),
      );
      expect(
        () => SyncPathTemplate.resolve('https://x.io', '/t/{reference}', {'reference': null}),
        throwsA(isA<SyncTemplateException>()),
      );
    });

    test('numeric placeholder values stringify', () {
      final uri = SyncPathTemplate.resolve(
        'https://x.io',
        '/b/{id}',
        {'id': 42},
      );
      expect(uri.toString(), 'https://x.io/b/42');
    });
  });
}
