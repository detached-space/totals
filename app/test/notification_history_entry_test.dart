import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/notification_service.dart';

void main() {
  test('transaction references survive notification history serialization', () {
    final entry = NotificationHistoryEntry(
      channel: 'transactions',
      title: 'CBE • Money Out',
      body: '-ETB 100.00',
      sentAt: DateTime.utc(2026, 8, 5),
      transactionReference: 'self-transfer-debit',
    );

    final restored = NotificationHistoryEntry.fromJson(entry.toJson());

    expect(restored.transactionReference, 'self-transfer-debit');
  });

  test('older notification history remains readable without a reference', () {
    final restored = NotificationHistoryEntry.fromJson(<String, dynamic>{
      'channel': 'transactions',
      'title': 'CBE • Money In',
      'body': '+ETB 100.00',
      'sentAt': '2026-08-05T00:00:00.000Z',
    });

    expect(restored.transactionReference, isNull);
  });
}
