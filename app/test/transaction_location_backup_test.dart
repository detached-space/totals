import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/transaction_location_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String databasePath;
  late TransactionRepository transactionRepository;
  late TransactionLocationRepository locationRepository;

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
    transactionRepository = TransactionRepository();
    locationRepository = TransactionLocationRepository();
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test('location data survives a full export and restore', () async {
    const reference = 'location-backup-round-trip';
    final transaction = Transaction(
      amount: 250,
      reference: reference,
      bankId: 1,
      type: 'CREDIT',
      time: '2026-08-17T12:00:00.000Z',
    );
    await transactionRepository.saveTransaction(
      transaction,
      skipAutoCategorization: true,
    );
    await locationRepository.saveLocation(
      transaction: transaction,
      latitude: 8.980603,
      longitude: 38.757761,
      accuracy: 7.25,
      capturedAt: DateTime.parse('2026-08-17T12:00:05.000Z'),
    );
    await locationRepository.setPlaceNameForTransactionReferences(
      const <String>[reference],
      '  Favorite café  ',
    );

    final service = DataExportImportService();
    final exported = await service.exportAllData();
    final payload = jsonDecode(exported) as Map<String, dynamic>;

    expect(payload['schemaVersion'], 13);
    final exportedLocation =
        (payload['transactionLocations'] as List<dynamic>).single as Map;
    expect(exportedLocation['transactionReference'], reference);
    expect(exportedLocation['latitude'], 8.980603);
    expect(exportedLocation['longitude'], 38.757761);
    expect(exportedLocation['accuracy'], 7.25);
    expect(exportedLocation['capturedAt'], '2026-08-17T12:00:05.000Z');
    expect(exportedLocation['placeName'], 'Favorite café');
    expect(exportedLocation.containsKey('profileId'), isFalse);

    await transactionRepository.clearAll();
    expect(await locationRepository.hasLocation(reference), isFalse);

    await service.importAllData(exported);

    expect(
      await transactionRepository.getTransactionByReference(reference),
      isNotNull,
    );
    final restored =
        (await locationRepository.getTransactionLocations()).single;
    expect(restored.transactionReference, reference);
    expect(restored.latitude, 8.980603);
    expect(restored.longitude, 38.757761);
    expect(restored.accuracy, 7.25);
    expect(restored.placeName, 'Favorite café');
    expect(
      restored.capturedAt.toUtc(),
      DateTime.parse('2026-08-17T12:00:05.000Z'),
    );

    final changedPayload = Map<String, dynamic>.from(payload);
    changedPayload['transactionLocations'] = <Map<String, dynamic>>[
      <String, dynamic>{
        ...Map<String, dynamic>.from(exportedLocation),
        'latitude': 9.0,
      },
    ];
    await service.importAllData(jsonEncode(changedPayload));

    final preserved =
        (await locationRepository.getTransactionLocations()).single;
    expect(preserved.latitude, 8.980603);
    expect(preserved.placeName, 'Favorite café');
  });

  test('custom place names can be changed and removed for a puck', () async {
    final transactions = <Transaction>[
      Transaction(
        amount: 10,
        reference: 'named-place-one',
        bankId: 1,
        type: 'DEBIT',
      ),
      Transaction(
        amount: 20,
        reference: 'named-place-two',
        bankId: 1,
        type: 'CREDIT',
      ),
    ];
    for (final transaction in transactions) {
      await transactionRepository.saveTransaction(
        transaction,
        skipAutoCategorization: true,
      );
      await locationRepository.saveLocation(
        transaction: transaction,
        latitude: 9.033,
        longitude: 38.842,
        capturedAt: DateTime.utc(2026, 8, 17),
      );
    }

    final references = transactions.map((transaction) => transaction.reference);
    await locationRepository.setPlaceNameForTransactionReferences(
      references,
      'Home',
    );
    var locations = await locationRepository.getTransactionLocations();
    expect(
        locations.map((location) => location.placeName), everyElement('Home'));

    await locationRepository.setPlaceNameForTransactionReferences(
      references,
      null,
    );
    locations = await locationRepository.getTransactionLocations();
    expect(
        locations.map((location) => location.placeName), everyElement(isNull));
  });

  test('filtered exports include locations only for selected transactions',
      () async {
    final included = Transaction(
      amount: 10,
      reference: 'included-location',
      bankId: 1,
      type: 'DEBIT',
    );
    final excluded = Transaction(
      amount: 20,
      reference: 'excluded-location',
      bankId: 4,
      type: 'DEBIT',
    );
    for (final transaction in <Transaction>[included, excluded]) {
      await transactionRepository.saveTransaction(
        transaction,
        skipAutoCategorization: true,
      );
      await locationRepository.saveLocation(
        transaction: transaction,
        latitude: transaction.bankId == 1 ? 8.9806 : 8.5644,
        longitude: transaction.bankId == 1 ? 38.7578 : 39.2872,
        capturedAt: DateTime.utc(2026, 8, 17),
      );
    }

    final exported = await DataExportImportService().exportAllData(
      options: const DataExportOptions(bankIds: <int>{1}),
    );
    final payload = jsonDecode(exported) as Map<String, dynamic>;
    final locations = payload['transactionLocations'] as List<dynamic>;

    expect(locations, hasLength(1));
    expect(
      (locations.single as Map)['transactionReference'],
      included.reference,
    );
  });

  test('restore skips malformed and orphaned location rows', () async {
    const reference = 'valid-location-owner';
    await transactionRepository.saveTransaction(
      Transaction(
        amount: 30,
        reference: reference,
        bankId: 1,
        type: 'DEBIT',
      ),
      skipAutoCategorization: true,
    );

    await DataExportImportService().importAllData(
      jsonEncode(<String, dynamic>{
        'schemaVersion': 13,
        'transactions': const <dynamic>[],
        'transactionLocations': <Map<String, dynamic>>[
          <String, dynamic>{
            'transactionReference': reference,
            'latitude': 8.9806,
            'longitude': 38.7578,
            'capturedAt': '2026-08-17T10:00:00.000Z',
          },
          <String, dynamic>{
            'transactionReference': 'bad-coordinates',
            'latitude': 200,
            'longitude': 38.7578,
            'capturedAt': '2026-08-17T10:00:00.000Z',
          },
          <String, dynamic>{
            'transactionReference': 'missing-transaction',
            'latitude': 8.5644,
            'longitude': 39.2872,
            'capturedAt': '2026-08-17T10:00:00.000Z',
          },
        ],
      }),
    );

    final restored = await locationRepository.getTransactionLocations();
    expect(restored, hasLength(1));
    expect(restored.single.transactionReference, reference);
  });
}
