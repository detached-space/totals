import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/saved_location_repository.dart';
import 'package:totals/repositories/transaction_location_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String databasePath;
  late SavedLocationRepository savedLocationRepository;
  late TransactionLocationRepository transactionLocationRepository;
  late TransactionRepository transactionRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DataSyncSettingsService.cachedEnabled = false;
    await DatabaseHelper.instance.close();
    databasePath = '${await databaseFactoryFfi.getDatabasesPath()}/totals.db';
    await databaseFactoryFfi.deleteDatabase(databasePath);
    await DatabaseHelper.instance.database;
    savedLocationRepository = SavedLocationRepository(
      idFactory: () => 'saved-home',
      clock: () => DateTime.utc(2026, 8, 30, 12),
    );
    transactionLocationRepository = TransactionLocationRepository();
    transactionRepository = TransactionRepository();
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test('saved locations can be assigned, moved, renamed, and deleted',
      () async {
    final transaction = Transaction(
      amount: 25,
      reference: 'manual-location-transaction',
      bankId: 1,
      type: 'DEBIT',
    );
    await transactionRepository.saveTransaction(
      transaction,
      skipAutoCategorization: true,
    );

    final created = await savedLocationRepository.createLocation(
      name: ' Home ',
      latitude: 9.03,
      longitude: 38.74,
    );
    expect(created.id, 'saved-home');
    expect(created.name, 'Home');

    await transactionLocationRepository.assignSavedLocation(
      transaction: transaction,
      savedLocation: created,
    );
    var assigned =
        (await transactionLocationRepository.getTransactionLocations()).single;
    expect(assigned.savedLocationId, created.id);
    expect(assigned.placeName, 'Home');
    expect(assigned.accuracy, isNull);

    final updated = await savedLocationRepository.updateLocation(
      created,
      name: 'House',
      latitude: 9.031,
      longitude: 38.741,
    );
    expect(updated.name, 'House');
    assigned =
        (await transactionLocationRepository.getTransactionLocations()).single;
    expect(assigned.savedLocationId, created.id);
    expect(assigned.placeName, 'House');
    expect(assigned.latitude, 9.031);
    expect(assigned.longitude, 38.741);

    await savedLocationRepository.deleteLocation(created.id);
    expect(await savedLocationRepository.getSavedLocations(), isEmpty);
    assigned =
        (await transactionLocationRepository.getTransactionLocations()).single;
    expect(assigned.savedLocationId, isNull);
    expect(assigned.placeName, 'House');
    expect(assigned.latitude, 9.031);
  });
}
