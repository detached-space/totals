import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/saved_location.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/transaction_location.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/data_sync/sync_enqueuer.dart';
import 'package:totals/services/data_sync/sync_models.dart';

class TransactionLocationRepository {
  TransactionLocationRepository({
    DatabaseHelper? databaseHelper,
    ProfileRepository? profileRepository,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _profileRepository = profileRepository ?? ProfileRepository();

  final DatabaseHelper _databaseHelper;
  final ProfileRepository _profileRepository;

  Future<bool> hasLocation(String transactionReference) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'transaction_locations',
      columns: const ['transactionReference'],
      where: 'transactionReference = ?',
      whereArgs: [transactionReference],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> saveLocation({
    required Transaction transaction,
    required double latitude,
    required double longitude,
    required DateTime capturedAt,
    double? accuracy,
  }) async {
    final db = await _databaseHelper.database;
    final profileId =
        transaction.profileId ?? await _profileRepository.getActiveProfileId();
    await db.insert(
      'transaction_locations',
      <String, Object?>{
        'transactionReference': transaction.reference,
        'profileId': profileId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<TransactionLocation>> getTransactionLocations() async {
    final db = await _databaseHelper.database;
    final activeProfileId = await _profileRepository.getActiveProfileId();
    final profileClause = activeProfileId == null
        ? ''
        : 'AND COALESCE(t.profileId, tl.profileId) = ?';
    final rows = await db.rawQuery(
      '''
      SELECT
        tl.transactionReference,
        tl.profileId,
        tl.latitude,
        tl.longitude,
        tl.accuracy,
        tl.capturedAt,
        tl.placeName,
        tl.savedLocationId,
        t.amount,
        t.type AS transactionType,
        t.time AS transactionTime
      FROM transaction_locations tl
      INNER JOIN transactions t
        ON t.reference = tl.transactionReference
      WHERE UPPER(TRIM(COALESCE(t.type, ''))) IN ('DEBIT', 'CREDIT')
        $profileClause
      ORDER BY COALESCE(t.time, tl.capturedAt) DESC
      ''',
      activeProfileId == null ? const [] : [activeProfileId],
    );
    return rows.map(TransactionLocation.fromMap).toList(growable: false);
  }

  Future<List<String>> getSavedPlaceNames() async {
    final locations = await getTransactionLocations();
    final namesByNormalizedValue = <String, String>{};
    for (final location in locations) {
      final placeName = location.placeName;
      if (placeName == null) continue;
      namesByNormalizedValue.putIfAbsent(
        placeName.toLowerCase(),
        () => placeName,
      );
    }
    final names = namesByNormalizedValue.values.toList(growable: false)
      ..sort((first, second) =>
          first.toLowerCase().compareTo(second.toLowerCase()));
    return names;
  }

  Future<List<TransactionLocation>> getForTransactionReferences(
    Set<String> transactionReferences,
  ) async {
    if (transactionReferences.isEmpty) return const <TransactionLocation>[];

    final db = await _databaseHelper.database;
    final rows = await db.query(
      'transaction_locations',
      columns: const <String>[
        'transactionReference',
        'profileId',
        'latitude',
        'longitude',
        'accuracy',
        'capturedAt',
        'placeName',
        'savedLocationId',
      ],
    );
    return rows
        .where(
          (row) => transactionReferences.contains(
            row['transactionReference']?.toString().trim(),
          ),
        )
        .map(TransactionLocation.fromMap)
        .toList(growable: false);
  }

  Future<void> restoreLocations(
    Iterable<TransactionLocation> locations,
  ) async {
    final locationsByReference = <String, TransactionLocation>{};
    for (final location in locations) {
      locationsByReference.putIfAbsent(
        location.transactionReference,
        () => location,
      );
    }
    if (locationsByReference.isEmpty) return;

    final db = await _databaseHelper.database;
    final transactionRows = await db.query(
      'transactions',
      columns: const <String>['reference', 'profileId'],
    );
    final profileByReference = <String, int?>{};
    for (final row in transactionRows) {
      final reference = row['reference']?.toString().trim() ?? '';
      if (reference.isEmpty || !locationsByReference.containsKey(reference)) {
        continue;
      }
      profileByReference[reference] = (row['profileId'] as num?)?.toInt();
    }
    if (profileByReference.isEmpty) return;

    final activeProfileId = await _profileRepository.getActiveProfileId();
    final batch = db.batch();
    for (final entry in locationsByReference.entries) {
      if (!profileByReference.containsKey(entry.key)) continue;
      final location = entry.value;
      batch.insert(
        'transaction_locations',
        <String, Object?>{
          'transactionReference': entry.key,
          'profileId': profileByReference[entry.key] ?? activeProfileId,
          'latitude': location.latitude,
          'longitude': location.longitude,
          'accuracy': location.accuracy,
          'capturedAt': location.capturedAt.toUtc().toIso8601String(),
          'placeName': location.placeName,
          'savedLocationId': location.savedLocationId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> setPlaceNameForTransactionReferences(
    Iterable<String> transactionReferences,
    String? placeName,
  ) async {
    final references = transactionReferences
        .map((reference) => reference.trim())
        .where((reference) => reference.isNotEmpty)
        .toSet();
    if (references.isEmpty) return;

    final normalizedName = normalizeTransactionPlaceName(placeName);
    final db = await _databaseHelper.database;
    final batch = db.batch();
    for (final reference in references) {
      batch.update(
        'transaction_locations',
        <String, Object?>{'placeName': normalizedName},
        where: 'transactionReference = ?',
        whereArgs: <Object?>[reference],
      );
    }
    await batch.commit(noResult: true);

    final transactionRows = await db.query('transactions');
    final syncRecords = <MapEntry<String, Map<String, dynamic>>>[];
    for (final row in transactionRows) {
      final reference = row['reference']?.toString().trim() ?? '';
      if (!references.contains(reference)) continue;
      final payload = Map<String, dynamic>.from(row)
        ..remove('sourceSubscriptionId')
        ..['locationName'] = normalizedName;
      syncRecords.add(MapEntry<String, Map<String, dynamic>>(
        reference,
        payload,
      ));
    }
    await SyncEnqueuer.instance.onManyWritten(
      entity: SyncEntity.transactions,
      records: syncRecords,
    );
  }

  Future<TransactionLocation> assignSavedLocation({
    required Transaction transaction,
    required SavedLocation savedLocation,
  }) async {
    return assignLocation(
      transaction: transaction,
      latitude: savedLocation.latitude,
      longitude: savedLocation.longitude,
      placeName: savedLocation.name,
      savedLocationId: savedLocation.id,
    );
  }

  Future<TransactionLocation> assignLocation({
    required Transaction transaction,
    required double latitude,
    required double longitude,
    required String placeName,
    String? savedLocationId,
  }) async {
    final reference = transaction.reference.trim();
    if (reference.isEmpty) {
      throw ArgumentError.value(
        transaction.reference,
        'transaction',
        'A transaction reference is required.',
      );
    }
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(latitude, 'latitude', 'Invalid latitude.');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(longitude, 'longitude', 'Invalid longitude.');
    }
    final normalizedName = normalizeTransactionPlaceName(placeName);
    if (normalizedName == null) {
      throw ArgumentError.value(
          placeName, 'placeName', 'A place name is required.');
    }

    final db = await _databaseHelper.database;
    final profileId =
        transaction.profileId ?? await _profileRepository.getActiveProfileId();
    final capturedAt = DateTime.now().toUtc();
    await db.insert(
      'transaction_locations',
      <String, Object?>{
        'transactionReference': reference,
        'profileId': profileId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': null,
        'capturedAt': capturedAt.toIso8601String(),
        'placeName': normalizedName,
        'savedLocationId': savedLocationId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final row = Map<String, dynamic>.from(transaction.toJson())
      ..remove('sourceSubscriptionId')
      ..['locationName'] = normalizedName;
    await SyncEnqueuer.instance.onEntityWritten(
      entity: SyncEntity.transactions,
      entityRef: reference,
      op: SyncOp.upsert,
      row: row,
    );

    return TransactionLocation(
      transactionReference: reference,
      profileId: profileId,
      latitude: latitude,
      longitude: longitude,
      capturedAt: capturedAt,
      amount: transaction.amount,
      transactionType: transaction.type,
      transactionTime: DateTime.tryParse(transaction.time?.trim() ?? ''),
      placeName: normalizedName,
      savedLocationId: savedLocationId,
    );
  }

  Future<void> clearForActiveProfile() async {
    final db = await _databaseHelper.database;
    final activeProfileId = await _profileRepository.getActiveProfileId();
    if (activeProfileId == null) {
      await db.delete('transaction_locations');
      return;
    }
    await db.delete(
      'transaction_locations',
      where: 'profileId = ?',
      whereArgs: [activeProfileId],
    );
  }
}
