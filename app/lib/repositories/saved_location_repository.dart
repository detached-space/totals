import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/saved_location.dart';
import 'package:totals/models/transaction_location.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:uuid/uuid.dart';

class SavedLocationRepository {
  SavedLocationRepository({
    DatabaseHelper? databaseHelper,
    ProfileRepository? profileRepository,
    String Function()? idFactory,
    DateTime Function()? clock,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _profileRepository = profileRepository ?? ProfileRepository(),
        _idFactory = idFactory ?? const Uuid().v4,
        _clock = clock ?? DateTime.now;

  final DatabaseHelper _databaseHelper;
  final ProfileRepository _profileRepository;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  Future<List<SavedLocation>> getSavedLocations() async {
    final db = await _databaseHelper.database;
    final activeProfileId = await _profileRepository.getActiveProfileId();
    final rows = await db.query(
      'saved_locations',
      where: activeProfileId == null ? null : 'profileId = ?',
      whereArgs: activeProfileId == null ? null : <Object?>[activeProfileId],
      orderBy: 'name COLLATE NOCASE ASC, createdAt ASC',
    );
    return rows.map(SavedLocation.fromMap).toList(growable: false);
  }

  Future<SavedLocation> createLocation({
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final profileId = await _profileRepository.getActiveProfileId();
    final now = _clock().toUtc();
    final location = SavedLocation.fromMap(<String, Object?>{
      'id': _idFactory(),
      'profileId': profileId,
      'name': normalizeTransactionPlaceName(name),
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
    final db = await _databaseHelper.database;
    await db.insert('saved_locations', location.toDatabaseMap());
    return location;
  }

  Future<SavedLocation> updateLocation(
    SavedLocation location, {
    String? name,
    double? latitude,
    double? longitude,
  }) async {
    final updated = SavedLocation.fromMap(<String, Object?>{
      ...location.toDatabaseMap(),
      'name': normalizeTransactionPlaceName(name) ?? location.name,
      'latitude': latitude ?? location.latitude,
      'longitude': longitude ?? location.longitude,
      'updatedAt': _clock().toUtc().toIso8601String(),
    });
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final changed = await txn.update(
        'saved_locations',
        updated.toDatabaseMap(),
        where: 'id = ?',
        whereArgs: <Object?>[location.id],
      );
      if (changed == 0) {
        throw StateError('Saved location no longer exists.');
      }
      await txn.update(
        'transaction_locations',
        <String, Object?>{
          'placeName': updated.name,
          if (updated.latitude != location.latitude ||
              updated.longitude != location.longitude) ...{
            'latitude': updated.latitude,
            'longitude': updated.longitude,
            'accuracy': null,
          },
        },
        where: 'savedLocationId = ?',
        whereArgs: <Object?>[updated.id],
      );
    });
    return updated;
  }

  Future<void> deleteLocation(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return;
    final db = await _databaseHelper.database;
    await db.delete(
      'saved_locations',
      where: 'id = ?',
      whereArgs: <Object?>[normalizedId],
    );
  }

  Future<void> restoreLocations(Iterable<SavedLocation> locations) async {
    final locationsById = <String, SavedLocation>{};
    for (final location in locations) {
      locationsById.putIfAbsent(location.id, () => location);
    }
    if (locationsById.isEmpty) return;

    final db = await _databaseHelper.database;
    final activeProfileId = await _profileRepository.getActiveProfileId();
    final batch = db.batch();
    for (final location in locationsById.values) {
      batch.insert(
        'saved_locations',
        location.toDatabaseMap(overrideProfileId: activeProfileId),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearForActiveProfile() async {
    final db = await _databaseHelper.database;
    final activeProfileId = await _profileRepository.getActiveProfileId();
    if (activeProfileId == null) {
      await db.delete('saved_locations');
      return;
    }
    await db.delete(
      'saved_locations',
      where: 'profileId = ?',
      whereArgs: <Object?>[activeProfileId],
    );
  }
}
