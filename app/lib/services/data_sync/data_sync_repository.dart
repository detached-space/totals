import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/account.dart';
import 'package:totals/services/data_sync/sync_models.dart';

class SyncTransactionLogDetails {
  final String reference;
  final double amount;
  final String? creditor;
  final String? receiver;
  final String? note;
  final String? time;
  final String? type;
  final int? bankId;
  final List<String> categoryNames;

  const SyncTransactionLogDetails({
    required this.reference,
    required this.amount,
    this.creditor,
    this.receiver,
    this.note,
    this.time,
    this.type,
    this.bankId,
    this.categoryNames = const <String>[],
  });

  bool get isCredit => type?.trim().toUpperCase() == 'CREDIT';
  bool get isDebit => type?.trim().toUpperCase() == 'DEBIT';

  String? get party {
    final values =
        isCredit ? [creditor, receiver, note] : [receiver, creditor, note];
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  String get title {
    final party = this.party;
    if (party != null) return party;
    return 'Transaction';
  }

  factory SyncTransactionLogDetails.fromDb(
    Map<String, dynamic> row, {
    List<String> categoryNames = const <String>[],
  }) {
    double amountFrom(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    return SyncTransactionLogDetails(
      reference: (row['reference'] as String?) ?? '',
      amount: amountFrom(row['amount']),
      creditor: row['creditor'] as String?,
      receiver: row['receiver'] as String?,
      note: row['note'] as String?,
      time: row['time'] as String?,
      type: row['type'] as String?,
      bankId: (row['bankId'] as num?)?.toInt(),
      categoryNames: categoryNames,
    );
  }
}

class SyncAccountLogDetails {
  final String accountNumber;
  final int bankId;
  final double balance;
  final String accountHolderName;

  const SyncAccountLogDetails({
    required this.accountNumber,
    required this.bankId,
    required this.balance,
    required this.accountHolderName,
  });

  factory SyncAccountLogDetails.fromDb(Map<String, dynamic> row) {
    double amountFrom(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    return SyncAccountLogDetails(
      accountNumber: (row['accountNumber'] as String?) ?? '',
      bankId: (row['bank'] as num?)?.toInt() ?? 0,
      balance: amountFrom(row['balance']),
      accountHolderName: (row['accountHolderName'] as String?) ?? '',
    );
  }
}

class SyncBudgetLogDetails {
  final int id;
  final String name;
  final double amount;
  final String type;
  final bool isActive;
  final List<String> categoryNames;

  const SyncBudgetLogDetails({
    required this.id,
    required this.name,
    required this.amount,
    required this.type,
    required this.isActive,
    this.categoryNames = const <String>[],
  });

  factory SyncBudgetLogDetails.fromDb(
    Map<String, dynamic> row, {
    List<String> categoryNames = const <String>[],
  }) {
    double amountFrom(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    return SyncBudgetLogDetails(
      id: (row['id'] as num?)?.toInt() ?? 0,
      name: (row['name'] as String?) ?? '',
      amount: amountFrom(row['amount']),
      type: (row['type'] as String?) ?? 'budget',
      isActive: (row['isActive'] as num? ?? 1) != 0,
      categoryNames: categoryNames,
    );
  }
}

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
    final rows =
        await db.query('sync_destinations', orderBy: 'name COLLATE NOCASE ASC');
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
        await txn
            .delete('sync_outbox', where: 'ruleId = ?', whereArgs: [ruleId]);
      }
      await txn
          .delete('sync_rules', where: 'destinationId = ?', whereArgs: [id]);
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
    final rows =
        await db.query('sync_rules', orderBy: 'name COLLATE NOCASE ASC');
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

  /// Enabled rules that need the background heartbeat (any time-based schedule).
  Future<int> countRulesNeedingSchedule() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM sync_rules WHERE enabled = 1 AND scheduleMode != 'off'",
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> touchSchedule(int ruleId, DateTime at) async {
    final db = await _db;
    await db.update(
      'sync_rules',
      {'lastScheduledAt': at.toIso8601String(), 'updatedAt': _now()},
      where: 'id = ?',
      whereArgs: [ruleId],
    );
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

  Future<List<Account>> getAccountsForFilter({int? profileId}) async {
    final db = await _db;
    final rows = await db.query(
      'accounts',
      where: profileId == null ? null : 'profileId = ?',
      whereArgs: profileId == null ? null : [profileId],
      orderBy: 'bank ASC, accountNumber ASC',
    );
    return rows.map((row) {
      return Account.fromJson({
        'accountNumber': row['accountNumber'],
        'bank': row['bank'],
        'balance': row['balance'],
        'accountHolderName': row['accountHolderName'],
        'settledBalance': row['settledBalance'],
        'pendingCredit': row['pendingCredit'],
        'profileId': row['profileId'],
      });
    }).toList(growable: false);
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
  /// claiming the same rows. When [ruleIds] is provided, only rows for those
  /// rules are claimed (used to honor per-rule schedules); an empty set claims
  /// nothing.
  Future<List<SyncOutboxItem>> claimDue(
      {int limit = 200, Set<int>? ruleIds}) async {
    if (ruleIds != null && ruleIds.isEmpty) return const [];
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final claimed = <SyncOutboxItem>[];
    final where = StringBuffer('status = ? AND nextAttemptAt <= ?');
    final args = <Object?>[SyncOutboxStatus.pending, now];
    if (ruleIds != null) {
      where.write(
          ' AND ruleId IN (${List.filled(ruleIds.length, '?').join(', ')})');
      args.addAll(ruleIds);
    }
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sync_outbox',
        where: where.toString(),
        whereArgs: args,
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
        claimed.add(SyncOutboxItem.fromDb(
            {...row, 'status': SyncOutboxStatus.sending}));
      }
    });
    return claimed;
  }

  Future<int> countDue({Set<int>? ruleIds}) async {
    if (ruleIds != null && ruleIds.isEmpty) return 0;
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final where = StringBuffer('status = ? AND nextAttemptAt <= ?');
    final args = <Object?>[SyncOutboxStatus.pending, now];
    if (ruleIds != null) {
      where.write(
          ' AND ruleId IN (${List.filled(ruleIds.length, '?').join(', ')})');
      args.addAll(ruleIds);
    }
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_outbox WHERE $where',
      args,
    );
    return (rows.first['c'] as int?) ?? 0;
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

  Future<int> releaseSending({
    int? ruleId,
    Iterable<int>? outboxIds,
  }) async {
    final ids = outboxIds?.toSet().toList(growable: false);
    if (ids != null && ids.isEmpty) return 0;

    final db = await _db;
    final where = StringBuffer('status = ?');
    final args = <Object?>[SyncOutboxStatus.sending];
    if (ruleId != null) {
      where.write(' AND ruleId = ?');
      args.add(ruleId);
    }
    if (ids != null) {
      where.write(' AND id IN (${List.filled(ids.length, '?').join(', ')})');
      args.addAll(ids);
    }
    final now = _now();
    return db.update(
      'sync_outbox',
      {
        'status': SyncOutboxStatus.pending,
        'nextAttemptAt': now,
        'updatedAt': now,
      },
      where: where.toString(),
      whereArgs: args,
    );
  }

  Future<void> deleteOutboxByRule(int ruleId) async {
    final db = await _db;
    await db.delete('sync_outbox', where: 'ruleId = ?', whereArgs: [ruleId]);
  }

  /// Drop outbox rows whose rule is disabled or deleted (housekeeping).
  Future<void> purgeOutboxForDisabledRules() async {
    final db = await _db;
    await db.execute(
      'DELETE FROM sync_outbox WHERE ruleId NOT IN '
      '(SELECT id FROM sync_rules WHERE enabled = 1)',
    );
  }

  // -------------------------------------------------------------------------
  // Outbox — log / maintenance
  // -------------------------------------------------------------------------

  Future<List<SyncOutboxItem>> getOutbox({
    String? status,
    List<String>? statuses,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await _db;
    final normalizedStatuses = (statuses ?? const <String>[])
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final where = normalizedStatuses.isNotEmpty
        ? 'status IN (${List.filled(normalizedStatuses.length, '?').join(', ')})'
        : status == null
            ? null
            : 'status = ?';
    final whereArgs = normalizedStatuses.isNotEmpty
        ? normalizedStatuses
        : status == null
            ? null
            : <Object?>[status];
    final rows = await db.query(
      'sync_outbox',
      where: where,
      whereArgs: whereArgs,
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

  Future<String?> acquireDrainLock({
    Duration ttl = const Duration(minutes: 10),
  }) async {
    final db = await _db;
    final now = DateTime.now();
    final owner = '${now.microsecondsSinceEpoch}-${identityHashCode(this)}';
    final nowIso = now.toIso8601String();
    final expiresIso = now.add(ttl).toIso8601String();
    return db.transaction<String?>((txn) async {
      await txn.delete(
        'sync_runtime_locks',
        where: 'name = ? AND expiresAt <= ?',
        whereArgs: ['drain', nowIso],
      );
      try {
        await txn.insert('sync_runtime_locks', {
          'name': 'drain',
          'owner': owner,
          'acquiredAt': nowIso,
          'expiresAt': expiresIso,
        });
        return owner;
      } on DatabaseException {
        return null;
      }
    });
  }

  Future<void> extendDrainLock(
    String owner, {
    Duration ttl = const Duration(minutes: 10),
  }) async {
    final db = await _db;
    await db.update(
      'sync_runtime_locks',
      {'expiresAt': DateTime.now().add(ttl).toIso8601String()},
      where: 'name = ? AND owner = ?',
      whereArgs: ['drain', owner],
    );
  }

  Future<void> releaseDrainLock(String owner) async {
    final db = await _db;
    await db.delete(
      'sync_runtime_locks',
      where: 'name = ? AND owner = ?',
      whereArgs: ['drain', owner],
    );
  }

  Future<Map<String, SyncTransactionLogDetails>> getTransactionLogDetails(
    Iterable<String> references,
  ) async {
    final refs = references
        .map((ref) => ref.trim())
        .where((ref) => ref.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (refs.isEmpty) return const <String, SyncTransactionLogDetails>{};

    final db = await _db;
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < refs.length; i += 900) {
      final slice = refs.sublist(
        i,
        i + 900 > refs.length ? refs.length : i + 900,
      );
      rows.addAll(await db.query(
        'transactions',
        columns: const [
          'reference',
          'amount',
          'creditor',
          'receiver',
          'note',
          'time',
          'type',
          'bankId',
          'categoryId',
          'categoryIds',
        ],
        where: 'reference IN (${List.filled(slice.length, '?').join(', ')})',
        whereArgs: slice,
      ));
    }

    final categoryIdsByRef = <String, List<int>>{};
    final allCategoryIds = <int>{};
    for (final row in rows) {
      final ref = (row['reference'] as String?)?.trim();
      if (ref == null || ref.isEmpty) continue;
      final ids = _categoryIdsFromRow(row);
      categoryIdsByRef[ref] = ids;
      allCategoryIds.addAll(ids);
    }

    final categoryNamesById = await _categoryNamesById(db, allCategoryIds);
    return {
      for (final row in rows)
        if (((row['reference'] as String?)?.trim() ?? '').isNotEmpty)
          (row['reference'] as String).trim(): SyncTransactionLogDetails.fromDb(
            row,
            categoryNames: [
              for (final id
                  in categoryIdsByRef[(row['reference'] as String).trim()] ??
                      const <int>[])
                if (categoryNamesById[id] != null) categoryNamesById[id]!,
            ],
          ),
    };
  }

  Future<Map<String, SyncAccountLogDetails>> getAccountLogDetails(
    Iterable<String> refs,
  ) async {
    final keys = refs
        .map((ref) => ref.trim())
        .where((ref) => ref.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (keys.isEmpty) return const <String, SyncAccountLogDetails>{};

    final db = await _db;
    final rows = await db.query(
      'accounts',
      columns: const [
        'accountNumber',
        'bank',
        'balance',
        'accountHolderName',
      ],
    );
    final wanted = keys.toSet();
    final details = <String, SyncAccountLogDetails>{};
    for (final row in rows) {
      final accountNumber = (row['accountNumber'] as String?)?.trim();
      final bankId = (row['bank'] as num?)?.toInt();
      if (accountNumber == null || accountNumber.isEmpty || bankId == null) {
        continue;
      }
      final key = '$accountNumber|$bankId';
      if (!wanted.contains(key)) continue;
      details[key] = SyncAccountLogDetails.fromDb(row);
    }
    return details;
  }

  Future<Map<String, SyncBudgetLogDetails>> getBudgetLogDetails(
    Iterable<String> refs,
  ) async {
    final idsByRef = <String, int>{};
    for (final ref in refs) {
      final trimmed = ref.trim();
      if (trimmed.isEmpty) continue;
      final id = int.tryParse(trimmed.replaceFirst('budget:', ''));
      if (id != null) idsByRef[trimmed] = id;
    }
    if (idsByRef.isEmpty) return const <String, SyncBudgetLogDetails>{};

    final db = await _db;
    final ids = idsByRef.values.toSet().toList(growable: false);
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += 900) {
      final slice = ids.sublist(
        i,
        i + 900 > ids.length ? ids.length : i + 900,
      );
      rows.addAll(await db.query(
        'budgets',
        columns: const [
          'id',
          'name',
          'amount',
          'type',
          'isActive',
          'categoryId',
          'categoryIds',
        ],
        where: 'id IN (${List.filled(slice.length, '?').join(', ')})',
        whereArgs: slice,
      ));
    }

    final categoryIdsByBudget = <int, List<int>>{};
    final allCategoryIds = <int>{};
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null) continue;
      final categoryIds = _categoryIdsFromRow(row);
      categoryIdsByBudget[id] = categoryIds;
      allCategoryIds.addAll(categoryIds);
    }
    final categoryNamesById = await _categoryNamesById(db, allCategoryIds);
    final detailsById = {
      for (final row in rows)
        if ((row['id'] as num?)?.toInt() != null)
          (row['id'] as num).toInt(): SyncBudgetLogDetails.fromDb(
            row,
            categoryNames: [
              for (final id
                  in categoryIdsByBudget[(row['id'] as num).toInt()] ??
                      const <int>[])
                if (categoryNamesById[id] != null) categoryNamesById[id]!,
            ],
          ),
    };
    return {
      for (final entry in idsByRef.entries)
        if (detailsById[entry.value] != null)
          entry.key: detailsById[entry.value]!,
    };
  }

  static List<int> _categoryIdsFromRow(Map<String, dynamic> row) {
    final ids = <int>[];

    void addId(dynamic value) {
      int? parsed;
      if (value is int) {
        parsed = value;
      } else if (value is num) {
        parsed = value.toInt();
      } else if (value is String) {
        parsed = int.tryParse(value.trim());
      }
      if (parsed == null || parsed <= 0 || ids.contains(parsed)) return;
      ids.add(parsed);
    }

    addId(row['categoryId']);
    final raw = row['categoryIds'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final value in decoded) {
            addId(value);
          }
        }
      } catch (_) {
        for (final value in raw.split(',')) {
          addId(value);
        }
      }
    } else if (raw is List) {
      for (final value in raw) {
        addId(value);
      }
    }

    return ids;
  }

  Future<Map<int, String>> _categoryNamesById(
    DatabaseExecutor db,
    Set<int> ids,
  ) async {
    if (ids.isEmpty) return const <int, String>{};

    final names = <int, String>{};
    final idList = ids.toList(growable: false);
    for (var i = 0; i < idList.length; i += 900) {
      final slice = idList.sublist(
        i,
        i + 900 > idList.length ? idList.length : i + 900,
      );
      final rows = await db.query(
        'categories',
        columns: const ['id', 'name'],
        where: 'id IN (${List.filled(slice.length, '?').join(', ')})',
        whereArgs: slice,
      );
      for (final row in rows) {
        final id = row['id'];
        final name = (row['name'] as String?)?.trim();
        if (id is int && name != null && name.isNotEmpty) {
          names[id] = name;
        }
      }
    }
    return names;
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
    return db.delete('sync_outbox',
        where: 'status = ?', whereArgs: [SyncOutboxStatus.sent]);
  }

  /// Debug helper: wipe the entire outbox (the store that tracks which records
  /// have been synced) and re-arm every rule so it backfills and re-schedules
  /// from scratch on the next drain. Lets you re-test sync against the same data.
  Future<void> resetSyncStateForDebug() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('sync_outbox');
      await txn.update('sync_rules', {
        'backfillDone': 0,
        'lastScheduledAt': null,
        'lastStatus': null,
        'lastError': null,
        'lastRunAt': null,
        'updatedAt': _now(),
      });
    });
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
