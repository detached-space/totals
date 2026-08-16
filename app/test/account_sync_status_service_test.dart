import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/account_sync_status_service.dart';
import 'package:totals/services/account_transaction_reparse_service.dart';

void main() {
  final service = AccountSyncStatusService.instance;

  setUp(service.clearAll);
  tearDown(service.clearAll);

  test('bank stays busy while any selected account has reparse status', () {
    service.setSyncStatus(
      '251900000001',
      6,
      'Waiting for reparse...',
      progress: 0,
    );
    service.setSyncStatus(
      '251900000002',
      6,
      'Waiting for reparse...',
      progress: 0,
    );

    expect(service.hasAnyAccountSyncing(6), isTrue);
    expect(service.hasAnyAccountSyncing(1), isFalse);

    service.clearSyncStatus('251900000001', 6);
    expect(service.hasAnyAccountSyncing(6), isTrue);

    service.clearSyncStatus('251900000002', 6);
    expect(service.hasAnyAccountSyncing(6), isFalse);
  });

  test('tracks Other transactions progress separately from account progress',
      () {
    service.setSyncStatus(
      AccountTransactionReparseTarget.unmatchedAccountKey,
      1,
      'Reparsing 25/100 messages...',
      progress: 0.25,
    );

    expect(
      service.getSyncStatus(
        AccountTransactionReparseTarget.unmatchedAccountKey,
        1,
      ),
      'Reparsing 25/100 messages...',
    );
    expect(
      service.getSyncProgress(
        AccountTransactionReparseTarget.unmatchedAccountKey,
        1,
      ),
      0.25,
    );
    expect(service.getSyncStatus('10001234', 1), isNull);
  });
}
