import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:uuid/uuid.dart';

class RuntimeLockLease {
  final String name;
  final String owner;

  const RuntimeLockLease({
    required this.name,
    required this.owner,
  });
}

class RuntimeLockRepository {
  RuntimeLockRepository({
    Future<Database> Function()? databaseProvider,
    DateTime Function()? clock,
    String Function()? ownerIdFactory,
  })  : _databaseProvider =
            databaseProvider ?? (() => DatabaseHelper.instance.database),
        _clock = clock ?? DateTime.now,
        _ownerIdFactory = ownerIdFactory ?? (() => const Uuid().v4());

  final Future<Database> Function() _databaseProvider;
  final DateTime Function() _clock;
  final String Function() _ownerIdFactory;

  Future<RuntimeLockLease?> tryAcquire(
    String name, {
    Duration ttl = const Duration(minutes: 15),
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Runtime lock name is empty.');
    }
    if (ttl <= Duration.zero) {
      throw ArgumentError.value(
          ttl, 'ttl', 'Runtime lock TTL must be positive.');
    }

    final db = await _databaseProvider();
    final now = _clock().toUtc();
    final owner = _ownerIdFactory();
    final nowIso = now.toIso8601String();
    final expiresIso = now.add(ttl).toIso8601String();

    try {
      return await db.transaction<RuntimeLockLease?>((txn) async {
        await txn.delete(
          'sync_runtime_locks',
          where: 'name = ? AND expiresAt <= ?',
          whereArgs: [normalizedName, nowIso],
        );
        await txn.insert('sync_runtime_locks', {
          'name': normalizedName,
          'owner': owner,
          'acquiredAt': nowIso,
          'expiresAt': expiresIso,
        });
        return RuntimeLockLease(name: normalizedName, owner: owner);
      });
    } on DatabaseException catch (error) {
      if (_isLockContention(error)) return null;
      rethrow;
    }
  }

  Future<void> release(RuntimeLockLease lease) async {
    final db = await _databaseProvider();
    await db.delete(
      'sync_runtime_locks',
      where: 'name = ? AND owner = ?',
      whereArgs: [lease.name, lease.owner],
    );
  }

  bool _isLockContention(DatabaseException error) {
    if (error.isUniqueConstraintError()) return true;
    final resultCode = error.getResultCode();
    if (resultCode == null) return false;
    final primaryResultCode = resultCode & 0xff;
    return primaryResultCode == 5 || primaryResultCode == 6;
  }
}
