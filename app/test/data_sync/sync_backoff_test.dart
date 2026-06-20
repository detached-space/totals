import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/data_sync/sync_models.dart';

void main() {
  group('computeSyncBackoff', () {
    test('exponential from a 30s base', () {
      expect(computeSyncBackoff(1), const Duration(seconds: 30));
      expect(computeSyncBackoff(2), const Duration(minutes: 1));
      expect(computeSyncBackoff(3), const Duration(minutes: 2));
      expect(computeSyncBackoff(4), const Duration(minutes: 4));
    });

    test('is monotonically non-decreasing', () {
      Duration prev = Duration.zero;
      for (var attempt = 1; attempt <= 20; attempt++) {
        final d = computeSyncBackoff(attempt);
        expect(d >= prev, isTrue, reason: 'attempt $attempt regressed');
        prev = d;
      }
    });

    test('caps at 6h and never overflows', () {
      expect(computeSyncBackoff(100), const Duration(hours: 6));
      expect(computeSyncBackoff(1000), const Duration(hours: 6));
    });

    test('attempts below 1 are treated as 1', () {
      expect(computeSyncBackoff(0), const Duration(seconds: 30));
      expect(computeSyncBackoff(-5), const Duration(seconds: 30));
    });
  });

  group('applySyncJitter', () {
    test('0.5 leaves the delay unchanged', () {
      expect(
        applySyncJitter(const Duration(seconds: 100), 0.5),
        const Duration(seconds: 100),
      );
    });

    test('bounds are ±20%', () {
      expect(applySyncJitter(const Duration(seconds: 100), 0.0).inMilliseconds, 80000);
      expect(
        applySyncJitter(const Duration(seconds: 100), 0.999).inMilliseconds,
        closeTo(120000, 100),
      );
    });
  });
}
