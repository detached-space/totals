import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/services/background_sync_signal_service.dart';
import 'package:totals/services/data_sync/data_sync_repository.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/services/data_sync/sync_service.dart';

/// Hooks the repository write/delete choke-points into the outbox. Designed to
/// be effectively free when Data Sync is disabled (the default): the very first
/// call per isolate reads the master flag once, caches it, and thereafter a
/// disabled feature short-circuits before any database work.
///
/// Every public method is exception-safe — a Data Sync failure must never break
/// a core transaction/account/budget write.
class SyncEnqueuer {
  SyncEnqueuer._();
  static final SyncEnqueuer instance = SyncEnqueuer._();

  /// Set true by the main isolate at startup. The background SMS/WorkManager
  /// isolates leave it false and therefore defer draining to the periodic task
  /// / next foreground launch (the durable outbox makes that safe).
  static bool isMainIsolate = false;

  final DataSyncRepository _repo = DataSyncRepository();

  /// Record that an entity row was written, enqueuing it onto every enabled
  /// rule whose filter matches. [row] is the raw column map (used for filter
  /// evaluation on upserts). For deletes, pass [deleteSnapshot] — the minimal
  /// identity the backend needs — since the live row is already gone.
  Future<void> onEntityWritten({
    required SyncEntity entity,
    required String entityRef,
    required SyncOp op,
    Map<String, dynamic>? row,
    Map<String, dynamic>? deleteSnapshot,
  }) async {
    try {
      if (!await DataSyncSettingsService.readEnabledFromPrefs()) return;
      if (entityRef.trim().isEmpty) return;

      final rules = await _repo.getEnabledRulesForEntity(entity);
      if (rules.isEmpty) return;

      final db = await DatabaseHelper.instance.database;
      final deleteJson =
          deleteSnapshot == null ? null : jsonEncode(deleteSnapshot);
      var enqueuedAny = false;

      for (final rule in rules) {
        // Upserts honor the rule filter. Deletes always enqueue (the row is
        // gone, so we can't evaluate the filter — an unknown ref is a harmless
        // no-op on an idempotent backend).
        if (op == SyncOp.upsert &&
            rule.filter != null &&
            row != null &&
            !rule.filter!.matches(row)) {
          continue;
        }
        await _repo.enqueueRow(
          db,
          ruleId: rule.id!,
          entity: entity,
          entityRef: entityRef,
          op: op,
          payloadJson: op == SyncOp.delete ? deleteJson : null,
        );
        enqueuedAny = true;
      }

      if (enqueuedAny) _signalDrain();
    } catch (error) {
      if (kDebugMode) debugPrint('debug: SyncEnqueuer.onEntityWritten: $error');
    }
  }

  /// Bulk variant for batch writes (imports/restores). Fetches enabled rules
  /// once and enqueues all matching `(entityRef, row)` pairs in a single batch.
  Future<void> onManyWritten({
    required SyncEntity entity,
    required List<MapEntry<String, Map<String, dynamic>>> records,
  }) async {
    try {
      if (records.isEmpty) return;
      if (!await DataSyncSettingsService.readEnabledFromPrefs()) return;

      final rules = await _repo.getEnabledRulesForEntity(entity);
      if (rules.isEmpty) return;

      final db = await DatabaseHelper.instance.database;
      final batch = db.batch();
      final now = DateTime.now().toIso8601String();
      var enqueuedAny = false;

      for (final record in records) {
        final entityRef = record.key;
        if (entityRef.trim().isEmpty) continue;
        final row = record.value;
        for (final rule in rules) {
          if (rule.filter != null && !rule.filter!.matches(row)) continue;
          batch.insert(
            'sync_outbox',
            {
              'ruleId': rule.id!,
              'entity': entity.storage,
              'entityRef': entityRef,
              'op': SyncOp.upsert.storage,
              'payloadJson': null,
              'status': SyncOutboxStatus.pending,
              'attempts': 0,
              'nextAttemptAt': now,
              'createdAt': now,
              'updatedAt': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          enqueuedAny = true;
        }
      }

      if (enqueuedAny) {
        await batch.commit(noResult: true);
        _signalDrain();
      }
    } catch (error) {
      if (kDebugMode) debugPrint('debug: SyncEnqueuer.onManyWritten: $error');
    }
  }

  void _signalDrain() {
    if (isMainIsolate) {
      unawaited(SyncService.instance.requestDrain(reason: 'write'));
    } else {
      // Background isolate: nudge a live main isolate to drain. If none is
      // listening the signal is dropped and the rows wait for the periodic
      // WorkManager task or the next foreground launch.
      BackgroundSyncSignalService.notifyOutboxChanged();
    }
  }
}
