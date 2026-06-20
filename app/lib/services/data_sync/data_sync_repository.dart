import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/services/data_sync/sync_models.dart';

/// Persistence for the Data Sync feature: destinations, rules, and the durable
/// outbox. Keeps all SQL out of the engine/UI. Secret values for destinations
/// live in [FlutterSecureStorage] (never in sqflite); FK cascades are not
/// enforced by sqflite, so child deletes are performed explicitly here.
class DataSyncRepository {
  DataSyncRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  Future<Database> get _db async => DatabaseHelper.instance.database;

  static String _now() => DateTime.now().toIso8601String();

  // -------------------------------------------------------------------------
  // Destinations
  // -------------------------------------------------------------------------

  Future<List<SyncDestination>> getDestinations() async {
    final db = await _db;
    final rows = await db.query('sync_destinations', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(SyncDestination.fromDb).toList(growable: false);
  }

  Future<SyncDestination?> getDestination(int id) async {
    final db = await _db;
    final rows = await db.query(
      'sync_destinations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncDestination.fromDb(rows.first);
  }

  /// Insert a destination and optionally persist its secret. Returns the new id.
  Future<int> insertDestination(SyncDestination dest, {String? secret}) async {
    final db = await _db;
    final data = dest.toDb()
      ..remove('id')
      ..['secretRef'] = null;
    final id = await db.insert('sync_destinations', data);

    if (secret != null && secret.isNotEmpty && dest.authType.needsSecret) {
      final ref = SyncDestination.secretRefFor(id);
      await _secureStorage.write(key: ref, value: secret);
      await db.update(
        'sync_destinations',
        {'secretRef': ref, 'updatedAt': _now()},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    return id;
  }

  /// Update a destination. Pass [secret] to (re)write the stored secret, or
  /// [clearSecret] to remove it.
  Future<void> updateDestination(
    SyncDestination dest, {
    String? secret,
    bool clearSecret = false,
  }) async {
    final id = dest.id;
    if (id == null) return;
    final db = await _db;
    final ref = SyncDestination.secretRefFor(id);

    String? secretRef = dest.secretRef;
    if (clearSecret) {
      await _secureStorage.delete(key: ref);
      secretRef = null;
    } else if (secret != null && secret.isNotEmpty) {
      await _secureStorage.write(key: ref, value: secret);
      secretRef = ref;
    }

    final data = dest.copyWith(updatedAt: DateTime.now()).toDb()
      ..['secretRef'] = secretRef;
    await db.update(
      'sync_destinations',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a destination plus its rules, their outbox rows, and its secret.
  Future<void> deleteDestination(int id) async {
    final db = await _db;
    final ruleIds = (await db.query(
      'sync_rules',
      columns: ['id'],
      where: 'destinationId = ?',
      whereArgs: [id],
    ))
        .map((r) => r['id'] as int)
        .toList();

    await db.transaction((txn) async {
      for (final ruleId in ruleIds) {
        await txn.delete('sync_outbox', where: 'ruleId = ?', whereArgs: [ruleId]);
      }
      await txn.delete('sync_rules', where: 'destinationId = ?', whereArgs: [id]);
      await txn.delete('sync_destinations', where: 'id = ?', whereArgs: [id]);
    });

    await _secureStorage.delete(key: SyncDestination.secretRefFor(id));
  }

  Future<String?> getDestinationSecret(SyncDestination dest) async {
    final ref = dest.secretRef;
    if (ref == null || ref.isEmpty) return null;
    return _secureStorage.read(key: ref);
  }

  // -------------------------------------------------------------------------
  // Rules
  // -------------------------------------------------------------------------

  Future<List<SyncRule>> getRules() async {
    final db = await _db;
    final rows = await db.query('sync_rules', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(SyncRule.fromDb).toList(growable: false);
  }

  Future<SyncRule?> getRule(int id) async {
    final db = await _db;
    final rows = await db.query(
      'sync_rules',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncRule.fromDb(rows.first);
  }

  /// Enabled rules for an entity — the hot path used at enqueue time.
  Future<List<SyncRule>> getEnabledRulesForEntity(SyncEntity entity) async {
    final db = await _db;
    final rows = await db.query(
      'sync_rules',
      where: 'entity = ? AND enabled = 1',
      whereArgs: [entity.storage],
    );
    return rows.map(SyncRule.fromDb).toList(growable: false);
  }

  Future<int> countEnabledRules() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_rules WHERE enabled = 1',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<int> countRulesWithPeriodicTrigger() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_rules WHERE enabled = 1 AND triggerPeriodic = 1',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<int> insertRule(SyncRule rule) async {
    final db = await _db;
    final data = rule.toDb()..remove('id');
    return db.insert('sync_rules', data);
  }

  Future<void> updateRule(SyncRule rule) async {
    final id = rule.id;
    if (id == null) return;
    final db = await _db;
    final data = rule.copyWith(updatedAt: DateTime.now()).toDb();
    await db.update('sync_rules', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteRule(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('sync_outbox', where: 'ruleId = ?', whereArgs: [id]);
      await txn.delete('sync_rules', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> setRuleRunStatus(
    int ruleId, {
    required String status,
    String? error,
    DateTime? ranAt,
  }) async {
    final db = await _db;
    await db.update(
      'sync_rules',
      {
        'lastStatus': status,
        'lastError': error,
        'lastRunAt': (ranAt ?? DateTime.now()).toIso8601String(),
        'updatedAt': _now(),
      },
      where: 'id = ?',
      whereArgs: [ruleId],
    );
  }

  Future<void> markRuleBackfilled(int ruleId) async {
    final db = await _db;
    await db.update(
      'sync_rules',
      {'backfillDone': 1, 'updatedAt': _now()},
      where: 'id = ?',
      whereArgs: [ruleId],
    );
  }

  // -------------------------------------------------------------------------
  // Outbox — enqueue
  // -------------------------------------------------------------------------

  /// Enqueue (or reset) one outbox row. `INSERT OR REPLACE` on the
  /// `(ruleId, entityRef, op)` unique key collapses repeated writes of the same
  /// record into a single pending row and resets a previously failed/dead row.
  Future<void> enqueueRow(
    DatabaseExecutor executor, {
    required int ruleId,
    required SyncEntity entity,
    required String entityRef,
    required SyncOp op,
    String? payloadJson,
  }) async {
    final now = _now();
    await executor.insert(
      'sync_outbox',
      {
        'ruleId': ruleId,
        'entity': entity.storage,
        'entityRef': entityRef,
        'op': op.storage,
        'payloadJson': payloadJson,
        'status': SyncOutboxStatus.pending,
        'attempts': 0,
        'nextAttemptAt': now,
        'lastError': null,
        'lastStatusCode': null,
        'createdAt': now,
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // -------------------------------------------------------------------------
  // Outbox — drain
  // -------------------------------------------------------------------------

  /// Reclaim rows stuck in `sending` (process died mid-send) older than [age].
  Future<void> reclaimStaleSending({
    Duration age = const Duration(minutes: 10),
  }) async {
    final db = await _db;
    final cutoff = DateTime.now().subtract(age).toIso8601String();
    await db.update(
      'sync_outbox',
      {'status': SyncOutboxStatus.pending, 'updatedAt': _now()},
      where: 'status = ? AND updatedAt <= ?',
      whereArgs: [SyncOutboxStatus.sending, cutoff],
    );
  }

  /// Atomically claim up to [limit] due rows by flipping them to `sending`,
  /// then return them. The transaction prevents two isolates from both
  /// claiming the same rows.
  Future<List<SyncOutboxItem>> claimDue({int limit = 200}) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final claimed = <SyncOutboxItem>[];
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sync_outbox',
        where: 'status = ? AND nextAttemptAt <= ?',
        whereArgs: [SyncOutboxStatus.pending, now],
        orderBy: 'createdAt ASC, id ASC',
        limit: limit,
      );
      for (final row in rows) {
        final id = row['id'] as int;
        await txn.update(
          'sync_outbox',
          {'status': SyncOutboxStatus.sending, 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        claimed.add(SyncOutboxItem.fromDb({...row, 'status': SyncOutboxStatus.sending}));
      }
    });
    return claimed;
  }

  Future<bool> hasDue() async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'sync_outbox',
      columns: ['id'],
      where: 'status = ? AND nextAttemptAt <= ?',
      whereArgs: [SyncOutboxStatus.pending, now],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> markSent(int outboxId) async {
    final db = await _db;
    await db.update(
      'sync_outbox',
      {
        'status': SyncOutboxStatus.sent,
        'lastError': null,
        'updatedAt': _now(),
      },
      where: 'id = ?',
      whereArgs: [outboxId],
    );
  }

  Future<void> markDead(int outboxId, {int? statusCode, String? error}) async {
    final db = await _db;
    await db.update(
      'sync_outbox',
      {
        'status': SyncOutboxStatus.dead,
        'lastStatusCode': statusCode,
        'lastError': error,
        'updatedAt': _now(),
      },
      where: 'id = ?',
      whereArgs: [outboxId],
    );
  }

  Future<void> reschedule(
    int outboxId, {
    required int attempts,
    required DateTime nextAttemptAt,
    int? statusCode,
    String? error,
  }) async {
    final db = await _db;
    await db.update(
      'sync_outbox',
      {
        'status': SyncOutboxStatus.pending,
        'attempts': attempts,
        'nextAttemptAt': nextAttemptAt.toIso8601String(),
        'lastStatusCode': statusCode,
        'lastError': error,
        'updatedAt': _now(),
      },
      where: 'id = ?',
      whereArgs: [outboxId],
    );
  }

  Future<void> deleteOutboxByRule(int ruleId) async {
    final db = await _db;
    await db.delete('sync_outbox', where: 'ruleId = ?', whereArgs: [ruleId]);
  }

  // -------------------------------------------------------------------------
  // Outbox — log / maintenance
  // -------------------------------------------------------------------------

  Future<List<SyncOutboxItem>> getOutbox({
    String? status,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status],
      orderBy: 'updatedAt DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(SyncOutboxItem.fromDb).toList(growable: false);
  }

  Future<Map<String, int>> outboxStatusCounts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT status, COUNT(*) AS c FROM sync_outbox GROUP BY status',
    );
    return {
      for (final row in rows) (row['status'] as String): (row['c'] as int),
    };
  }

  /// Reset `dead` (and optionally stuck `sending`) rows back to `pending`.
  Future<int> retryFailed() async {
    final db = await _db;
    return db.update(
      'sync_outbox',
      {
        'status': SyncOutboxStatus.pending,
        'attempts': 0,
        'nextAttemptAt': _now(),
        'lastError': null,
        'updatedAt': _now(),
      },
      where: 'status IN (?, ?)',
      whereArgs: [SyncOutboxStatus.dead, SyncOutboxStatus.failed],
    );
  }

  /// Purge `sent` rows older than [age] (housekeeping).
  Future<int> purgeSent({Duration age = const Duration(days: 7)}) async {
    final db = await _db;
    final cutoff = DateTime.now().subtract(age).toIso8601String();
    return db.delete(
      'sync_outbox',
      where: 'status = ? AND updatedAt <= ?',
      whereArgs: [SyncOutboxStatus.sent, cutoff],
    );
  }

  Future<int> clearSent() async {
    final db = await _db;
    return db.delete('sync_outbox', where: 'status = ?', whereArgs: [SyncOutboxStatus.sent]);
  }

  // -------------------------------------------------------------------------
  // Wipe everything (master disable + wipe)
  // -------------------------------------------------------------------------

  Future<void> wipeAll() async {
    final db = await _db;
    final dests = await db.query('sync_destinations', columns: ['id']);
    await db.transaction((txn) async {
      await txn.delete('sync_outbox');
      await txn.delete('sync_rules');
      await txn.delete('sync_destinations');
    });
    for (final row in dests) {
      final id = row['id'] as int?;
      if (id != null) {
        await _secureStorage.delete(key: SyncDestination.secretRefFor(id));
      }
    }
  }
}
