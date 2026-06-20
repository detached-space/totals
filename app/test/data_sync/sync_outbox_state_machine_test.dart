import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/data_sync/sync_models.dart';

void main() {
  group('classifySyncResponse', () {
    test('2xx is success', () {
      expect(classifySyncResponse(statusCode: 200), SyncSendOutcome.success);
      expect(classifySyncResponse(statusCode: 201), SyncSendOutcome.success);
      expect(classifySyncResponse(statusCode: 299), SyncSendOutcome.success);
    });

    test('408/429/5xx/network/no-status retry', () {
      expect(classifySyncResponse(statusCode: 408), SyncSendOutcome.retry);
      expect(classifySyncResponse(statusCode: 429), SyncSendOutcome.retry);
      expect(classifySyncResponse(statusCode: 500), SyncSendOutcome.retry);
      expect(classifySyncResponse(statusCode: 503), SyncSendOutcome.retry);
      expect(classifySyncResponse(networkError: true), SyncSendOutcome.retry);
      expect(classifySyncResponse(), SyncSendOutcome.retry);
    });

    test('other 4xx are dead (no retry)', () {
      expect(classifySyncResponse(statusCode: 400), SyncSendOutcome.dead);
      expect(classifySyncResponse(statusCode: 401), SyncSendOutcome.dead);
      expect(classifySyncResponse(statusCode: 404), SyncSendOutcome.dead);
      expect(classifySyncResponse(statusCode: 422), SyncSendOutcome.dead);
    });
  });

  group('nextOutboxTransition', () {
    test('success → sent, attempts unchanged', () {
      final t = nextOutboxTransition(
        currentAttempts: 2,
        outcome: SyncSendOutcome.success,
        maxAttempts: 8,
      );
      expect(t, const SyncOutboxTransition(SyncOutboxStatus.sent, 2));
    });

    test('dead → dead, attempts unchanged', () {
      final t = nextOutboxTransition(
        currentAttempts: 0,
        outcome: SyncSendOutcome.dead,
        maxAttempts: 8,
      );
      expect(t, const SyncOutboxTransition(SyncOutboxStatus.dead, 0));
    });

    test('retry increments attempts and stays pending below cap', () {
      final t = nextOutboxTransition(
        currentAttempts: 1,
        outcome: SyncSendOutcome.retry,
        maxAttempts: 8,
      );
      expect(t, const SyncOutboxTransition(SyncOutboxStatus.pending, 2));
    });

    test('retry at the cap goes dead', () {
      final t = nextOutboxTransition(
        currentAttempts: 7,
        outcome: SyncSendOutcome.retry,
        maxAttempts: 8,
      );
      expect(t, const SyncOutboxTransition(SyncOutboxStatus.dead, 8));
    });
  });
}
