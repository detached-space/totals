import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/saved_location.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/transaction_location.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/data_sync/sync_enqueuer.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/utils/spending_map_clustering.dart';
import 'package:uuid/uuid.dart';

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
    final fallbackProfileId =
        transaction.profileId ?? await _profileRepository.getActiveProfileId();
    String? matchedName;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'transaction_locations',
        columns: const ['transactionReference'],
        where: 'transactionReference = ?',
        whereArgs: [transaction.reference],
        limit: 1,
      );
      if (existing.isNotEmpty) return;

      final owner = await txn.query(
        'transactions',
        columns: const ['profileId'],
        where: 'reference = ?',
        whereArgs: [transaction.reference],
        limit: 1,
      );
      final profileId = owner.isEmpty
          ? fallbackProfileId
          : (owner.single['profileId'] as int?) ?? fallbackProfileId;
      final match = accuracy == null ||
              !accuracy.isFinite ||
              accuracy < 0 ||
              accuracy > spendingMapSameLocationRadiusMeters
          ? null
          : await _matchCapturedPlace(
              txn,
              profileId: profileId,
              latitude: latitude,
              longitude: longitude,
            );
      matchedName = match?['placeName'] as String?;
      await txn.insert(
        'transaction_locations',
        <String, Object?>{
          'transactionReference': transaction.reference,
          'profileId': profileId,
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
          'capturedAt': capturedAt.toUtc().toIso8601String(),
          'placeName': matchedName,
          'savedLocationId': match?['savedLocationId'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
    if (matchedName != null) {
      final row = Map<String, dynamic>.from(transaction.toJson())
        ..remove('sourceSubscriptionId')
        ..['locationName'] = matchedName;
      await SyncEnqueuer.instance.onEntityWritten(
        entity: SyncEntity.transactions,
        entityRef: transaction.reference,
        op: SyncOp.upsert,
        row: row,
      );
    }
  }

  Future<Map<String, Object?>?> _matchCapturedPlace(
    DatabaseExecutor db, {
    required int? profileId,
    required double latitude,
    required double longitude,
  }) async {
    // A null profile matches only unowned places, never every profile.
    final savedRows = await db.rawQuery(
      'SELECT id AS savedLocationId, name AS placeName, latitude, longitude '
      'FROM saved_locations WHERE profileId IS ? ORDER BY id',
      [profileId],
    );
    final nearbySaved = _nearbyNamedPlaces(savedRows, latitude, longitude);
    if (nearbySaved.isNotEmpty) return _unambiguousPlace(nearbySaved);

    final namedRows = await db.rawQuery(
      '''
      SELECT tl.transactionReference, tl.placeName, tl.latitude, tl.longitude,
             tl.accuracy
      FROM transaction_locations tl
      INNER JOIN transactions t ON t.reference = tl.transactionReference
      WHERE COALESCE(t.profileId, tl.profileId) IS ?
        AND tl.savedLocationId IS NULL
        AND TRIM(COALESCE(tl.placeName, '')) <> ''
      ORDER BY tl.capturedAt, tl.transactionReference
      ''',
      [profileId],
    );
    final match = _unambiguousPlace(
      _nearbyNamedPlaces(namedRows, latitude, longitude),
    );
    if (match == null) return null;

    // Turn an existing custom name into a fixed, reusable anchor. Inherited
    // captures link to it, so they cannot extend its matching radius over time.
    final savedLocationId = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('saved_locations', <String, Object?>{
      'id': savedLocationId,
      'profileId': profileId,
      'name': match['placeName'],
      'latitude': match['latitude'],
      'longitude': match['longitude'],
      'createdAt': now,
      'updatedAt': now,
    });
    await db.update(
      'transaction_locations',
      <String, Object?>{'savedLocationId': savedLocationId},
      where: 'transactionReference = ?',
      whereArgs: [match['transactionReference']],
    );
    return <String, Object?>{...match, 'savedLocationId': savedLocationId};
  }

  List<Map<String, Object?>> _nearbyNamedPlaces(
    List<Map<String, Object?>> rows,
    double latitude,
    double longitude,
  ) {
    final nearby = <({Map<String, Object?> row, double distance})>[];
    for (final row in rows) {
      final accuracy = (row['accuracy'] as num?)?.toDouble();
      if (accuracy != null &&
          (!accuracy.isFinite ||
              accuracy < 0 ||
              accuracy > spendingMapSameLocationRadiusMeters)) {
        continue;
      }
      final distance = spendingMapDistanceMeters(
        firstLatitude: latitude,
        firstLongitude: longitude,
        secondLatitude: (row['latitude'] as num).toDouble(),
        secondLongitude: (row['longitude'] as num).toDouble(),
      );
      if (distance <= spendingMapSameLocationRadiusMeters) {
        nearby.add((row: row, distance: distance));
      }
    }
    nearby.sort((first, second) => first.distance.compareTo(second.distance));
    return nearby.map((candidate) => candidate.row).toList(growable: false);
  }

  Map<String, Object?>? _unambiguousPlace(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return null;
    final names = rows
        .map((row) => (row['placeName'] as String).trim().toLowerCase())
        .toSet();
    return names.length == 1 ? rows.first : null;
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
    final changedReferences = <String>{...references};
    await db.transaction((txn) async {
      final savedIds = <String>{};
      for (final reference in references) {
        final rows = await txn.query(
          'transaction_locations',
          columns: const ['savedLocationId'],
          where: 'transactionReference = ?',
          whereArgs: [reference],
        );
        for (final row in rows) {
          final savedId = row['savedLocationId'] as String?;
          if (savedId != null) savedIds.add(savedId);
        }
        await txn.update(
          'transaction_locations',
          <String, Object?>{
            'placeName': normalizedName,
            if (normalizedName == null) 'savedLocationId': null,
          },
          where: 'transactionReference = ?',
          whereArgs: [reference],
        );
      }
      if (normalizedName == null) return;
      for (final savedId in savedIds) {
        await txn.update(
          'saved_locations',
          <String, Object?>{
            'name': normalizedName,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [savedId],
        );
        final linked = await txn.query(
          'transaction_locations',
          columns: const ['transactionReference'],
          where: 'savedLocationId = ?',
          whereArgs: [savedId],
        );
        changedReferences.addAll(
          linked.map((row) => row['transactionReference'] as String),
        );
        await txn.update(
          'transaction_locations',
          <String, Object?>{'placeName': normalizedName},
          where: 'savedLocationId = ?',
          whereArgs: [savedId],
        );
      }
    });

    final transactionRows = await db.query('transactions');
    final syncRecords = <MapEntry<String, Map<String, dynamic>>>[];
    for (final row in transactionRows) {
      final reference = row['reference']?.toString().trim() ?? '';
      if (!changedReferences.contains(reference)) continue;
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
