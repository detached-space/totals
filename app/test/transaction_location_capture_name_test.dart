import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/saved_location.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/transaction_location.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/repositories/saved_location_repository.dart';
import 'package:totals/repositories/transaction_location_repository.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const latitude = 9.03;
  const longitude = 38.74;
  final capturedAt = DateTime.utc(2026, 9, 25, 12);
  late DatabaseHelper helper;
  late Database db;
  late _ActiveProfile profiles;
  late SavedLocationRepository places;
  late TransactionLocationRepository locations;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DataSyncSettingsService.cachedEnabled = false;
    helper = DatabaseHelper.forTesting(
      path: inMemoryDatabasePath,
      databaseFactory: databaseFactoryFfi,
    );
    db = await helper.database;
    profiles = _ActiveProfile(1);
    places = SavedLocationRepository(
      databaseHelper: helper,
      profileRepository: profiles,
    );
    locations = TransactionLocationRepository(
      databaseHelper: helper,
      profileRepository: profiles,
    );
  });
  tearDown(() => helper.close());

  double latitudeAt(double metres) => latitude + metres / 111195;

  Future<Transaction> transaction(String reference,
      {int? profileId = 1}) async {
    final result = Transaction(
      reference: reference,
      amount: 25,
      bankId: 1,
      type: 'DEBIT',
      profileId: profileId,
    );
    await db.insert('transactions', <String, Object?>{
      'reference': reference,
      'amount': 25,
      'bankId': 1,
      'type': 'DEBIT',
      'profileId': profileId,
    });
    return result;
  }

  Future<TransactionLocation> read(String reference) async =>
      (await locations.getForTransactionReferences({reference})).single;

  Future<TransactionLocation> capture(
    String reference, {
    double metres = 0,
    double? accuracy = 5,
    int? profileId = 1,
  }) async {
    final tx = await transaction(reference, profileId: profileId);
    await locations.saveLocation(
      transaction: tx,
      latitude: latitudeAt(metres),
      longitude: longitude,
      accuracy: accuracy,
      capturedAt: capturedAt,
    );
    return read(reference);
  }

  Future<SavedLocation> savedPlace(String name, {double metres = 0}) =>
      places.createLocation(
        name: name,
        latitude: latitudeAt(metres),
        longitude: longitude,
      );

  Future<Transaction> namedTransaction(
    String reference,
    String name, {
    double metres = 0,
  }) async {
    final tx = await transaction(reference);
    await locations.assignLocation(
      transaction: tx,
      latitude: latitudeAt(metres),
      longitude: longitude,
      placeName: name,
    );
    return tx;
  }

  test('capture inherits a saved name and link while preserving GPS data',
      () async {
    final home = await savedPlace('Home');
    final captured = await capture('new-sms', metres: 40, accuracy: 7);

    expect(captured.placeName, 'Home');
    expect(captured.savedLocationId, home.id);
    expect(captured.latitude, latitudeAt(40));
    expect(captured.longitude, longitude);
    expect(captured.accuracy, 7);
    expect(captured.capturedAt, capturedAt);
  });

  test('an existing custom name becomes a fixed anchor without drifting',
      () async {
    await namedTransaction('original', 'Favorite café');
    final first = await capture('first', metres: 40);
    final second = await capture('second', metres: 20);
    final beyondOriginalPlace = await capture('outside', metres: 80);

    expect(first.placeName, 'Favorite café');
    expect(first.savedLocationId, isNotNull);
    expect(second.savedLocationId, first.savedLocationId);
    expect((await read('original')).savedLocationId, first.savedLocationId);
    expect(beyondOriginalPlace.placeName, isNull);
    expect(beyondOriginalPlace.savedLocationId, isNull);
    final anchors = await places.getSavedLocations();
    expect(anchors, hasLength(1));
    expect(anchors.single.latitude, latitude);
  });

  test('capture uses the 50 metre limit regardless of map zoom', () async {
    await savedPlace('Home');
    expect((await capture('inside', metres: 49)).placeName, 'Home');
    expect((await capture('outside', metres: 51)).placeName, isNull);
  });

  for (final accuracy in <double?>[null, -1, 51, 250]) {
    test(
        'capture with accuracy $accuracy keeps coordinates without a guessed name',
        () async {
      await savedPlace('Home');
      final captured = await capture('uncertain', accuracy: accuracy);
      expect(captured.latitude, latitude);
      expect(captured.placeName, isNull);
      expect(captured.savedLocationId, isNull);
    });
  }

  test('ambiguous saved places do not fall back to a historic custom name',
      () async {
    await savedPlace('Home');
    await savedPlace('Office', metres: 60);
    await namedTransaction('historic-home', 'Home', metres: 30);

    final captured = await capture('between', metres: 30);
    expect(captured.placeName, isNull);
    expect(captured.savedLocationId, isNull);
  });

  test('different nearby historic names remain unassigned', () async {
    await namedTransaction('home', 'Home');
    await namedTransaction('office', 'Office', metres: 60);
    expect((await capture('between', metres: 30)).placeName, isNull);
    expect(await places.getSavedLocations(), isEmpty);
  });

  test('explicit saved places take precedence over old transaction labels',
      () async {
    await namedTransaction('old', 'Old name');
    final home = await savedPlace('Home', metres: 10);
    final captured = await capture('new');
    expect(captured.placeName, 'Home');
    expect(captured.savedLocationId, home.id);
  });

  test('poor accuracy in a historic named capture does not become an anchor',
      () async {
    await namedTransaction('uncertain-home', 'Home');
    await db.update(
      'transaction_locations',
      {'accuracy': 200},
      where: 'transactionReference = ?',
      whereArgs: ['uncertain-home'],
    );
    expect((await capture('new')).placeName, isNull);
    expect(await places.getSavedLocations(), isEmpty);
  });

  test('the stored transaction profile wins when the active profile changes',
      () async {
    final home = await savedPlace('Personal home');
    final tx = await transaction('personal-sms');
    profiles.id = 2;
    await savedPlace('Work');
    await locations.saveLocation(
      transaction: Transaction(
        reference: tx.reference,
        amount: tx.amount,
        bankId: tx.bankId,
        type: tx.type,
      ),
      latitude: latitude,
      longitude: longitude,
      accuracy: 5,
      capturedAt: capturedAt,
    );
    final captured = await read(tx.reference);
    expect(captured.profileId, 1);
    expect(captured.placeName, 'Personal home');
    expect(captured.savedLocationId, home.id);
  });

  test('other profiles do not supply saved or historic custom names', () async {
    await savedPlace('Personal home');
    await namedTransaction('private', 'Private café', metres: 200);
    profiles.id = 2;
    expect((await capture('work-home', profileId: 2)).placeName, isNull);
    expect((await capture('work-cafe', profileId: 2, metres: 200)).placeName,
        isNull);
  });

  test('a null profile matches only unowned places', () async {
    await savedPlace('Personal home');
    profiles.id = null;
    expect(
        (await capture('unowned-before', profileId: null)).placeName, isNull);
    final unowned = await savedPlace('Unowned');
    expect((await capture('unowned-after', profileId: null)).savedLocationId,
        unowned.id);
  });

  test('repeat capture preserves existing manual names and coordinates',
      () async {
    final tx = await namedTransaction('manual', 'Chosen location', metres: 200);
    await savedPlace('Home');
    await locations.saveLocation(
      transaction: tx,
      latitude: latitude,
      longitude: longitude,
      accuracy: 5,
      capturedAt: capturedAt,
    );
    final preserved = await read(tx.reference);
    expect(preserved.placeName, 'Chosen location');
    expect(preserved.latitude, latitudeAt(200));
    expect(preserved.savedLocationId, isNull);
  });

  test('renaming an inherited place updates the anchor and later captures',
      () async {
    await namedTransaction('original', 'Home');
    await capture('linked', metres: 30);
    await locations.setPlaceNameForTransactionReferences(['original'], 'House');

    expect((await read('linked')).placeName, 'House');
    expect((await read('linked')).latitude, latitudeAt(30));
    expect((await places.getSavedLocations()).single.name, 'House');
    expect((await capture('later', metres: 20)).placeName, 'House');
  });

  test('renaming a saved place preserves captured coordinates and accuracy',
      () async {
    final home = await savedPlace('Home');
    await capture('linked', metres: 30, accuracy: 7);
    await places.updateLocation(home, name: 'House');
    final renamed = await read('linked');
    expect(renamed.placeName, 'House');
    expect(renamed.latitude, latitudeAt(30));
    expect(renamed.accuracy, 7);
  });

  test('removing a transaction name detaches it from later place renames',
      () async {
    final home = await savedPlace('Home');
    await capture('cleared');
    await locations.setPlaceNameForTransactionReferences(['cleared'], null);
    await places.updateLocation(home, name: 'House');
    final cleared = await read('cleared');
    expect(cleared.placeName, isNull);
    expect(cleared.savedLocationId, isNull);
  });
}

class _ActiveProfile extends ProfileRepository {
  _ActiveProfile(this.id);
  int? id;

  @override
  Future<int?> getActiveProfileId() async => id;
}
