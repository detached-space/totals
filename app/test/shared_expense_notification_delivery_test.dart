import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/totals_engine_client.dart';

void main() {
  test('engine client fails closed without loaded environment configuration',
      () {
    expect(TotalsEngineClient.new, throwsStateError);
  });

  test('an explicitly configured engine endpoint is normalized', () {
    final client = TotalsEngineClient(baseUrl: 'configured-engine/');
    expect(client.baseUrl, 'configured-engine');
  });

  test('shared expense event IDs map to a deterministic notification ID', () {
    expect(
      NotificationService.sharedExpenseNotificationIdForTesting(
        'shared-expense-event-123',
      ),
      44135874,
    );
  });
}
