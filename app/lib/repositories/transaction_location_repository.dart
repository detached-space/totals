import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/transaction_location.dart';
import 'package:totals/repositories/profile_repository.dart';

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
