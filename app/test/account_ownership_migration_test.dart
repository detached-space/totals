import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/services/account_ownership_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('completed ownership migration is skipped on later launches', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'active_profile_id': 42,
      AccountOwnershipService.migrationVersionPreferenceKey(42): 1,
    });

    final didRun = await AccountOwnershipService.instance.runPendingMigration();

    expect(didRun, isFalse);
  });

  test('ownership migration version is isolated per profile', () {
    expect(
      AccountOwnershipService.migrationVersionPreferenceKey(1),
      isNot(AccountOwnershipService.migrationVersionPreferenceKey(2)),
    );
    expect(
      AccountOwnershipService.migrationVersionPreferenceKey(null),
      endsWith('default'),
    );
  });
}
