import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/models/category.dart' as models;
import 'package:totals/models/transaction.dart';
import 'package:totals/services/data_sync/data_sync_repository.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';
import 'package:totals/services/data_sync/outbound_http_client.dart';
import 'package:totals/services/data_sync/sync_auth.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/services/notification_service.dart';

void _log(String message) {
  if (kDebugMode) debugPrint('debug: SyncService: $message');
}

/// Snapshot of the latest (or in-progress) sync run, broadcast for the UI.
class SyncRunStatus {
  final bool running;
  final int sent;
  final int failed;
  final int processed;
  final int total;
  final DateTime? at;
  final Set<int> activeRuleIds;
  final Set<int> stoppingRuleIds;
  final bool stopRequested;

  const SyncRunStatus({
    this.running = false,
    this.sent = 0,
    this.failed = 0,
    this.processed = 0,
    this.total = 0,
    this.at,
    this.activeRuleIds = const <int>{},
    this.stoppingRuleIds = const <int>{},
    this.stopRequested = false,
  });

  bool get hasResult => at != null;
  bool get hasProgress => total > 0;
  int get retried => processed - sent - failed;
  int get percent =>
      total <= 0 ? 0 : ((processed / total).clamp(0.0, 1.0) * 100).round();
  String get fraction => total <= 0 ? '0/0' : '$processed/$total';
}

class _BudgetUsagePayload {
  final double usedAmount;
  final double availableAmount;
  final double percentageUsed;
  final bool isExceeded;
  final bool isApproachingLimit;
  final DateTime periodStart;
  final DateTime periodEnd;

  const _BudgetUsagePayload({
    required this.usedAmount,
    required this.availableAmount,
    required this.percentageUsed,
    required this.isExceeded,
    required this.isApproachingLimit,
    required this.periodStart,
    required this.periodEnd,
  });
}

class _SendResult {
  final String? error;
  final bool stopped;

  const _SendResult({this.error, this.stopped = false});

  static const ok = _SendResult();
  static const stoppedByUser = _SendResult(stopped: true);
}

/// Drains the durable outbox: builds requests from rules, sends them via
/// [OutboundHttpClient], and advances each row through the state machine. Runs
/// only on the main isolate (or as a one-shot inside the WorkManager isolate);
/// background isolates enqueue and signal rather than draining directly.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final DataSyncRepository _repo = DataSyncRepository();
  final OutboundHttpClient _http = OutboundHttpClient();
  late final SyncAuth _auth = SyncAuth(_repo);
  final Random _random = Random();

  static const int _maxRowsPerDrain = 200;
  static const int _maxAttempts = 8;
  static const int _bulkChunkSize = 500;

  bool _draining = false;
  bool _drainRequested = false;
  String? _drainLockOwner;
  DateTime? _lastDrainLockRefreshAt;

  /// Live status of the most recent / ongoing drain, for the UI to observe.
  final ValueNotifier<SyncRunStatus> status =
      ValueNotifier<SyncRunStatus>(const SyncRunStatus());
  int _runSent = 0;
  int _runFailed = 0;
  int _runProcessed = 0;
  int _runTotal = 0;
  String _runReason = 'manual';
  int _lastProgressNotificationProcessed = -1;
  DateTime? _lastProgressNotificationAt;
  bool _runProgressNotificationVisible = false;
  bool _stopAllRequested = false;
  final Set<int> _stoppedRuleIds = <int>{};
  final Set<int> _activeRuleIds = <int>{};
  final Set<int> _stoppingRuleIds = <int>{};

  Future<void> primeProgress({
    required String reason,
    required int total,
  }) async {
    if (_draining || total <= 0) return;
    _runSent = 0;
    _runFailed = 0;
    _runProcessed = 0;
    _runTotal = total;
    _runReason = reason;
    _lastProgressNotificationProcessed = -1;
    _lastProgressNotificationAt = null;
    _runProgressNotificationVisible = false;
    _emitStatus(running: true);
    await _maybeNotifyProgress(force: true);
  }

  Future<int> countDue({String reason = 'manual'}) async {
    if (!await DataSyncSettingsService.readEnabledFromPrefs()) return 0;
    await _repo.reclaimStaleSending();
    await _repo.purgeOutboxForDisabledRules();
    return _countDueForReason(reason);
  }

  Future<void> stopAll() async {
    _stopAllRequested = true;
    _drainRequested = false;
    _stoppingRuleIds.addAll(_activeRuleIds);
    _http.cancelInFlight();
    await _repo.releaseSending();
    _emitStatus(running: _draining);
  }

  Future<void> stopRule(int ruleId) async {
    if (ruleId <= 0) return;
    _stoppedRuleIds.add(ruleId);
    _stoppingRuleIds.add(ruleId);
    if (_activeRuleIds.contains(ruleId)) {
      _http.cancelInFlight();
    }
    await _repo.releaseSending(ruleId: ruleId);
    _emitStatus(running: _draining);
  }

  /// Request an outbox drain. Safe to call from anywhere on the main isolate;
  /// concurrent calls coalesce into at most one extra pass.
  Future<void> requestDrain({String reason = 'manual'}) async {
    if (!await DataSyncSettingsService.readEnabledFromPrefs()) return;
    if (_draining) {
      _drainRequested = true;
      return;
    }
    final lockOwner = await _repo.acquireDrainLock();
    if (lockOwner == null) {
      _log('drain skipped; another drain is already running');
      return;
    }
    final primedTotal = status.value.running &&
            _runReason == reason &&
            _runProcessed == 0 &&
            _runTotal > 0
        ? _runTotal
        : 0;
    _draining = true;
    _drainLockOwner = lockOwner;
    _lastDrainLockRefreshAt = null;
    _runSent = 0;
    _runFailed = 0;
    _runProcessed = 0;
    _runTotal = primedTotal;
    _runReason = reason;
    _lastProgressNotificationProcessed = -1;
    _lastProgressNotificationAt = null;
    _runProgressNotificationVisible = false;
    _stopAllRequested = false;
    _stoppedRuleIds.clear();
    _activeRuleIds.clear();
    _stoppingRuleIds.clear();
    _emitStatus(running: true);
    _log('drain start (reason=$reason)');
    try {
      await _repo.reclaimStaleSending();
      await _repo.purgeOutboxForDisabledRules();
      _runTotal = await _countDueForReason(reason);
      _emitStatus(running: true);
      await _maybeNotifyProgress(force: true);
      do {
        _drainRequested = false;
        if (await _shouldStopDrain()) break;
        final processed = await _drainOnce(reason);
        if (processed > 0 && await _repo.hasDue()) {
          final remaining = await _countDueForReason(reason);
          final estimatedTotal = _runProcessed + remaining;
          if (estimatedTotal > _runTotal) {
            _runTotal = estimatedTotal;
            _emitStatus(running: true);
          }
          _drainRequested = true;
        }
      } while (_drainRequested);
      await _repo.purgeSent();
    } catch (error, stack) {
      _log('drain error: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
    } finally {
      _draining = false;
      _emitStatus(running: false, at: DateTime.now());
      await _showTerminalProgressIfNeeded();
      await _maybeNotify();
      _log('drain end (sent=$_runSent failed=$_runFailed)');
      try {
        await _repo.releaseDrainLock(lockOwner);
      } catch (_) {}
      _drainLockOwner = null;
      _lastDrainLockRefreshAt = null;
      _stopAllRequested = false;
      _stoppedRuleIds.clear();
      _activeRuleIds.clear();
      _stoppingRuleIds.clear();
    }
  }

  /// Post a result notification when a run actually did something. It's a
  /// single, self-replacing notification (failures alert; successes update
  /// quietly), gated by the "Notify me about syncs" setting so normal writes
  /// do not crowd the notification shade by default.
  Future<void> _maybeNotify() async {
    final retried = _runProcessed - _runSent - _runFailed;
    if (_runSent == 0 && _runFailed == 0 && retried <= 0) {
      await _dismissProgressNotificationIfNeeded(force: true);
      return;
    }
    try {
      if (!await DataSyncSettingsService.readNotifyFromPrefs()) {
        await _dismissProgressNotificationIfNeeded(force: true);
        return;
      }
      await NotificationService.instance.showDataSyncResult(
        sent: _runSent,
        failed: _runFailed,
        retried: retried,
      );
      _runProgressNotificationVisible = false;
    } catch (_) {}
  }

  Future<void> _maybeNotifyProgress({bool force = false}) async {
    if (_runTotal <= 0) return;
    // Let the terminal result notification own the 100% state. Posting a final
    // progress update immediately before the summary makes Android treat the
    // summary as an easy-to-miss replacement of the same notification.
    if (!force && _runProcessed >= _runTotal) return;
    try {
      if (!await _shouldShowProgressNotification()) return;
      final now = DateTime.now();
      final processedDelta = _runProcessed - _lastProgressNotificationProcessed;
      final elapsed = _lastProgressNotificationAt == null
          ? const Duration(days: 1)
          : now.difference(_lastProgressNotificationAt!);
      final shouldUpdate = force ||
          _runProcessed >= _runTotal ||
          processedDelta >= 10 ||
          elapsed >= const Duration(seconds: 1);
      if (!shouldUpdate) return;
      _lastProgressNotificationProcessed = _runProcessed;
      _lastProgressNotificationAt = now;
      await NotificationService.instance.showDataSyncProgress(
        processed: _runProcessed,
        total: _runTotal,
        sent: _runSent,
        failed: _runFailed,
        reason: _runReason,
      );
      _runProgressNotificationVisible = true;
    } catch (_) {}
  }

  Future<void> _showTerminalProgressIfNeeded() async {
    if (_runTotal <= 0 || _runProcessed < _runTotal) return;
    try {
      if (!await _shouldShowProgressNotification()) return;
      await NotificationService.instance.showDataSyncProgress(
        processed: _runTotal,
        total: _runTotal,
        sent: _runSent,
        failed: _runFailed,
        reason: _runReason,
      );
      _runProgressNotificationVisible = true;
    } catch (_) {}
  }

  Future<bool> _shouldShowProgressNotification() async {
    if (_isRequiredProgressReason(_runReason)) return true;
    return DataSyncSettingsService.readNotifyFromPrefs();
  }

  bool _isRequiredProgressReason(String reason) {
    return reason == 'enabled' || reason == 'backfill';
  }

  Future<void> _dismissProgressNotificationIfNeeded(
      {bool force = false}) async {
    if (!_runProgressNotificationVisible && !force) return;
    try {
      await NotificationService.instance.dismissDataSyncNotification();
      _runProgressNotificationVisible = false;
    } catch (_) {}
  }

  void _emitStatus({required bool running, DateTime? at}) {
    status.value = SyncRunStatus(
      running: running,
      sent: _runSent,
      failed: _runFailed,
      processed: _runProcessed,
      total: _runTotal,
      at: at,
      activeRuleIds: Set<int>.unmodifiable(_activeRuleIds),
      stoppingRuleIds: Set<int>.unmodifiable(_stoppingRuleIds),
      stopRequested: _stopAllRequested,
    );
  }

  Future<bool> _shouldStopDrain() async {
    if (_stopAllRequested) return true;
    final enabled = await DataSyncSettingsService.readEnabledFromPrefs();
    if (!enabled) {
      _stopAllRequested = true;
      _stoppingRuleIds.addAll(_activeRuleIds);
      return true;
    }
    return false;
  }

  Future<bool> _shouldStopRule(int ruleId) async {
    if (_stoppedRuleIds.contains(ruleId)) return true;
    return _shouldStopDrain();
  }

  Future<void> _releaseItems(Iterable<SyncOutboxItem> items) async {
    final ids = [for (final item in items) item.id];
    if (ids.isEmpty) return;
    await _repo.releaseSending(outboxIds: ids);
  }

  Future<int> _countDueForReason(String reason) async {
    final now = DateTime.now();
    final rules = await _repo.getRules();
    final dueRuleIds = _dueRuleIds(rules, reason, now);
    return _repo.countDue(ruleIds: dueRuleIds);
  }

  Set<int> _dueRuleIds(List<SyncRule> rules, String reason, DateTime now) {
    return rules
        .where((r) =>
            r.enabled && r.id != null && syncRuleShouldSend(r, reason, now))
        .map((r) => r.id!)
        .toSet();
  }

  Future<int> _drainOnce(String reason) async {
    if (await _shouldStopDrain()) return 0;
    final processedBefore = _runProcessed;
    await _repo.reclaimStaleSending();
    // Drop rows whose rule was disabled or deleted.
    await _repo.purgeOutboxForDisabledRules();
    if (await _shouldStopDrain()) return 0;

    final now = DateTime.now();
    final rules = await _repo.getRules();
    final rulesById = <int, SyncRule>{
      for (final r in rules)
        if (r.id != null) r.id!: r,
    };
    // Only rules whose trigger/schedule says "send now" for this reason.
    final dueRuleIds = _dueRuleIds(rules, reason, now);
    if (dueRuleIds.isEmpty) return 0;

    final due =
        await _repo.claimDue(limit: _maxRowsPerDrain, ruleIds: dueRuleIds);
    if (due.isEmpty) return 0;
    if (await _shouldStopDrain()) {
      await _releaseItems(due);
      return 0;
    }

    final byRule = <int, List<SyncOutboxItem>>{};
    for (final item in due) {
      byRule.putIfAbsent(item.ruleId, () => []).add(item);
    }

    for (final entry in byRule.entries) {
      if (await _shouldStopDrain()) {
        await _releaseItems(entry.value);
        continue;
      }
      if (_stoppedRuleIds.contains(entry.key)) {
        await _releaseItems(entry.value);
        continue;
      }
      final rule = rulesById[entry.key];
      if (rule == null || !rule.enabled) {
        await _repo.deleteOutboxByRule(entry.key);
        continue;
      }
      final dest = await _repo.getDestination(rule.destinationId);
      if (dest == null || !dest.enabled) {
        // Destination unavailable: release the claimed rows for later.
        for (final item in entry.value) {
          await _repo.reschedule(
            item.id,
            attempts: item.attempts,
            nextAttemptAt: now.add(const Duration(minutes: 30)),
            error: 'Destination disabled or missing.',
          );
          await _noteProcessed();
        }
        continue;
      }
      _activeRuleIds.add(entry.key);
      _emitStatus(running: true);
      try {
        final result = await _sendRuleBatch(rule, dest, entry.value);
        await _repo.setRuleRunStatus(
          rule.id!,
          status: result.stopped
              ? 'stopped'
              : (result.error == null ? 'ok' : 'error'),
          error: result.error,
        );
        // Advance the schedule clock once a time-scheduled rule has fired.
        if (!result.stopped && rule.scheduleMode != SyncScheduleMode.off) {
          await _repo.touchSchedule(rule.id!, now);
        }
      } finally {
        _activeRuleIds.remove(entry.key);
        _stoppingRuleIds.remove(entry.key);
        _emitStatus(running: true);
      }
    }
    return max(0, _runProcessed - processedBefore);
  }

  Future<_SendResult> _sendRuleBatch(
    SyncRule rule,
    SyncDestination dest,
    List<SyncOutboxItem> items,
  ) async {
    final headers = await _auth.headersFor(dest);
    String? lastError;
    final ruleId = rule.id;
    if (ruleId == null) return _SendResult.ok;
    if (rule.batchMode == SyncBatchMode.bulkArray) {
      for (var i = 0; i < items.length; i += _bulkChunkSize) {
        if (await _shouldStopRule(ruleId)) {
          await _releaseItems(items.sublist(i));
          return _SendResult.stoppedByUser;
        }
        final slice = items.sublist(i, min(i + _bulkChunkSize, items.length));
        final result = await _sendBulk(rule, dest, slice, headers);
        if (result.stopped) {
          if (i + slice.length < items.length) {
            await _releaseItems(items.sublist(i + slice.length));
          }
          return result;
        }
        lastError = result.error ?? lastError;
      }
    } else {
      for (var i = 0; i < items.length; i++) {
        if (await _shouldStopRule(ruleId)) {
          await _releaseItems(items.sublist(i));
          return _SendResult.stoppedByUser;
        }
        final result = await _sendOne(rule, dest, items[i], headers);
        if (result.stopped) {
          if (i + 1 < items.length) {
            await _releaseItems(items.sublist(i + 1));
          }
          return result;
        }
        lastError = result.error ?? lastError;
      }
    }
    return _SendResult(error: lastError);
  }

  /// Returns an error message if the send did not succeed, else null.
  Future<_SendResult> _sendOne(
    SyncRule rule,
    SyncDestination dest,
    SyncOutboxItem item,
    Map<String, String> headers,
  ) async {
    final ruleId = rule.id;
    if (ruleId != null && await _shouldStopRule(ruleId)) {
      await _releaseItems([item]);
      return _SendResult.stoppedByUser;
    }
    try {
      final payload = await _resolvePayload(item);
      if (payload == null) {
        // Source row vanished before send → nothing to push.
        await _repo.markSent(item.id);
        _runSent++;
        await _noteProcessed();
        return _SendResult.ok;
      }
      if (ruleId != null && await _shouldStopRule(ruleId)) {
        await _releaseItems([item]);
        return _SendResult.stoppedByUser;
      }
      final mapped = SyncFieldMapper.apply(
        payload,
        rule.fieldMap,
        includeUnmapped: rule.sendUnmapped,
      );
      final uri =
          SyncPathTemplate.resolve(dest.baseUrl, rule.pathTemplate, payload);
      final res = await _http.send(
        method: rule.method,
        uri: uri,
        headers: headers,
        jsonBody: mapped,
      );
      final detail = await _applyOutcome(
        item,
        statusCode: res.statusCode,
        refusedLocally: res.refusedLocally,
        retryAfter: res.retryAfter,
        body: res.bodySnippet(),
      );
      return _SendResult(error: detail);
    } on SyncTemplateException catch (error) {
      await _repo.markDead(item.id, error: error.message);
      _runFailed++;
      await _noteProcessed();
      return _SendResult(error: error.message);
    } on OutboundNetworkException catch (error) {
      if (ruleId != null && await _shouldStopRule(ruleId)) {
        await _releaseItems([item]);
        return _SendResult.stoppedByUser;
      }
      final detail =
          await _applyOutcome(item, networkError: true, error: error.message);
      return _SendResult(error: detail);
    } catch (error) {
      if (ruleId != null && await _shouldStopRule(ruleId)) {
        await _releaseItems([item]);
        return _SendResult.stoppedByUser;
      }
      final detail = await _applyOutcome(item,
          networkError: true, error: error.toString());
      return _SendResult(error: detail);
    }
  }

  Future<_SendResult> _sendBulk(
    SyncRule rule,
    SyncDestination dest,
    List<SyncOutboxItem> items,
    Map<String, String> headers,
  ) async {
    final ruleId = rule.id;
    if (ruleId != null && await _shouldStopRule(ruleId)) {
      await _releaseItems(items);
      return _SendResult.stoppedByUser;
    }
    final payloads = <Map<String, dynamic>>[];
    final live = <SyncOutboxItem>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (ruleId != null && await _shouldStopRule(ruleId)) {
        await _releaseItems(items.sublist(i));
        return _SendResult.stoppedByUser;
      }
      final payload = await _resolvePayload(item);
      if (payload == null) {
        await _repo.markSent(item.id);
        _runSent++;
        await _noteProcessed();
        continue;
      }
      payloads.add(SyncFieldMapper.apply(
        payload,
        rule.fieldMap,
        includeUnmapped: rule.sendUnmapped,
      ));
      live.add(item);
    }
    if (live.isEmpty) return _SendResult.ok;
    if (ruleId != null && await _shouldStopRule(ruleId)) {
      await _releaseItems(live);
      return _SendResult.stoppedByUser;
    }

    final Uri uri;
    try {
      uri = SyncPathTemplate.resolve(dest.baseUrl, rule.pathTemplate, const {});
    } on SyncTemplateException catch (error) {
      const msg =
          'Bulk-array rules cannot use record placeholders in the path.';
      for (final item in live) {
        await _repo.markDead(item.id, error: '$msg ${error.message}');
        _runFailed++;
        await _noteProcessed();
      }
      return const _SendResult(error: msg);
    }

    try {
      final res = await _http.send(
        method: rule.method,
        uri: uri,
        headers: headers,
        jsonBody: payloads,
      );
      String? lastError;
      for (final item in live) {
        lastError = await _applyOutcome(
              item,
              statusCode: res.statusCode,
              refusedLocally: res.refusedLocally,
              retryAfter: res.retryAfter,
              body: res.bodySnippet(),
            ) ??
            lastError;
      }
      return _SendResult(error: lastError);
    } on OutboundNetworkException catch (error) {
      if (ruleId != null && await _shouldStopRule(ruleId)) {
        await _releaseItems(live);
        return _SendResult.stoppedByUser;
      }
      String? lastError;
      for (final item in live) {
        lastError = await _applyOutcome(item,
                networkError: true, error: error.message) ??
            lastError;
      }
      return _SendResult(error: lastError);
    }
  }

  /// Advance an outbox row per the state machine. Returns an error string for a
  /// non-success outcome, else null.
  Future<String?> _applyOutcome(
    SyncOutboxItem item, {
    int? statusCode,
    bool networkError = false,
    bool refusedLocally = false,
    Duration? retryAfter,
    String? body,
    String? error,
  }) async {
    final detail = error ?? body;
    if (refusedLocally) {
      await _repo.markDead(item.id, statusCode: statusCode, error: detail);
      _runFailed++;
      await _noteProcessed();
      return detail ?? 'Refused locally.';
    }

    final outcome = classifySyncResponse(
        statusCode: statusCode, networkError: networkError);
    final transition = nextOutboxTransition(
      currentAttempts: item.attempts,
      outcome: outcome,
      maxAttempts: _maxAttempts,
    );

    switch (transition.status) {
      case SyncOutboxStatus.sent:
        await _repo.markSent(item.id);
        _runSent++;
        await _noteProcessed();
        return null;
      case SyncOutboxStatus.dead:
        await _repo.markDead(item.id, statusCode: statusCode, error: detail);
        _runFailed++;
        await _noteProcessed();
        return detail ?? 'Failed (HTTP $statusCode).';
      default: // pending — schedule a retry
        final base = computeSyncBackoff(transition.attempts);
        final jittered = applySyncJitter(base, _random.nextDouble());
        final delay = retryAfter ?? jittered;
        await _repo.reschedule(
          item.id,
          attempts: transition.attempts,
          nextAttemptAt: DateTime.now().add(delay),
          statusCode: statusCode,
          error: detail,
        );
        await _noteProcessed();
        return detail ?? 'Retry scheduled (HTTP $statusCode).';
    }
  }

  Future<void> _noteProcessed() async {
    _runProcessed++;
    if (_runProcessed > _runTotal) _runTotal = _runProcessed;
    _emitStatus(running: true);
    await _refreshDrainLockIfNeeded();
    await _maybeNotifyProgress();
  }

  Future<void> _refreshDrainLockIfNeeded() async {
    final owner = _drainLockOwner;
    if (owner == null) return;
    final now = DateTime.now();
    final last = _lastDrainLockRefreshAt;
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastDrainLockRefreshAt = now;
    await _repo.extendDrainLock(owner);
  }

  /// Build the live payload for an outbox row. For deletes, return the frozen
  /// identity snapshot. Returns null when the source row no longer exists.
  Future<Map<String, dynamic>?> _resolvePayload(SyncOutboxItem item) async {
    if (item.op == SyncOp.delete) {
      if (item.payloadJson == null || item.payloadJson!.trim().isEmpty) {
        return <String, dynamic>{};
      }
      try {
        final decoded = jsonDecode(item.payloadJson!);
        return decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return _payloadForEntityRef(item.entity, item.entityRef);
  }

  Future<Map<String, dynamic>?> _payloadForEntityRef(
    SyncEntity entity,
    String entityRef,
  ) async {
    final db = await DatabaseHelper.instance.database;
    switch (entity) {
      case SyncEntity.transactions:
        final rows = await db.query(
          'transactions',
          where: 'reference = ?',
          whereArgs: [entityRef],
          limit: 1,
        );
        if (rows.isEmpty) return null;
        final payload =
            Transaction.fromJson(Map<String, dynamic>.from(rows.first))
                .toJson();
        return _withTransactionCategories(db, payload);
      case SyncEntity.accounts:
        final sep = entityRef.lastIndexOf('|');
        if (sep <= 0) return null;
        final accountNumber = entityRef.substring(0, sep);
        final bank = int.tryParse(entityRef.substring(sep + 1));
        if (bank == null) return null;
        final rows = await db.query(
          'accounts',
          where: 'accountNumber = ? AND bank = ?',
          whereArgs: [accountNumber, bank],
          limit: 1,
        );
        if (rows.isEmpty) return null;
        final account = Account.fromJson(Map<String, dynamic>.from(rows.first));
        return _withAccountDetails(db, account);
      case SyncEntity.budgets:
        final id = int.tryParse(entityRef.replaceFirst('budget:', ''));
        if (id == null) return null;
        final rows = await db.query(
          'budgets',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) return null;
        final budget = Budget.fromDb(Map<String, dynamic>.from(rows.first));
        return _withBudgetDetails(db, budget);
    }
  }

  Future<Map<String, dynamic>> _withAccountDetails(
    Database db,
    Account account,
  ) async {
    final payload = account.toJson();
    final bank = await _bankPayloadForId(db, account.bank);
    if (bank != null) {
      payload['bankName'] = _trimmedString(bank['name']);
      payload['bankShortName'] = _trimmedString(bank['shortName']);
    }
    return payload;
  }

  Future<Map<String, dynamic>> _withBudgetDetails(
    Database db,
    Budget budget,
  ) async {
    final payload = budget.toJson();
    final categoryNames = await _categoryNamesForIds(
      db,
      budget.selectedCategoryIds,
    );
    final usage = await _usageForBudget(db, budget);
    final recurrence = _recurrenceForBudget(budget);
    final isRecurring = recurrence != 'never' &&
        (budget.endDate == null || budget.endDate!.isAfter(usage.periodEnd));

    payload['categoryNames'] = categoryNames;
    payload['appliesToAllExpenses'] = budget.appliesToAllExpenses;
    payload['usedAmount'] = usage.usedAmount;
    payload['availableAmount'] = usage.availableAmount;
    payload['percentageUsed'] = usage.percentageUsed;
    payload['isExceeded'] = usage.isExceeded;
    payload['isApproachingLimit'] = usage.isApproachingLimit;
    payload['periodStart'] = usage.periodStart.toIso8601String();
    payload['periodEnd'] = usage.periodEnd.toIso8601String();
    payload['isRecurring'] = isRecurring;
    payload['recurrence'] = recurrence;
    return payload;
  }

  Future<Map<String, dynamic>> _withTransactionCategories(
    Database db,
    Map<String, dynamic> payload,
  ) async {
    final categoryIds = SyncTransactionCategoryPayload.categoryIdsFor(payload);
    if (categoryIds.isEmpty) {
      return SyncTransactionCategoryPayload.enrich(
        payload,
        const <Map<String, dynamic>>[],
      );
    }

    final placeholders = List.filled(categoryIds.length, '?').join(',');
    final rows = await db.query(
      'categories',
      where: 'id IN ($placeholders)',
      whereArgs: categoryIds,
    );
    final categories = rows
        .map((row) => models.Category.fromDb(Map<String, dynamic>.from(row)))
        .map((category) => category.toJson());

    return SyncTransactionCategoryPayload.enrich(payload, categories);
  }

  Future<Map<String, dynamic>?> _bankPayloadForId(
    Database db,
    int bankId,
  ) async {
    final rows = await db.query(
      'banks',
      where: 'id = ?',
      whereArgs: [bankId],
      limit: 1,
    );
    if (rows.isNotEmpty) return Map<String, dynamic>.from(rows.first);
    for (final bank in AllBanksFromAssets.getAllBanks()) {
      if (bank.id == bankId) return bank.toJson();
    }
    return null;
  }

  Future<List<String>> _categoryNamesForIds(
    Database db,
    List<int> categoryIds,
  ) async {
    if (categoryIds.isEmpty) return const <String>[];
    final placeholders = List.filled(categoryIds.length, '?').join(',');
    final rows = await db.query(
      'categories',
      where: 'id IN ($placeholders)',
      whereArgs: categoryIds,
    );
    final byId = <int, String>{};
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      final name = _trimmedString(row['name']);
      if (id == null || name == null) continue;
      byId[id] = name;
    }
    return [
      for (final id in categoryIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<_BudgetUsagePayload> _usageForBudget(
    Database db,
    Budget budget,
  ) async {
    final periodStart = budget.getCurrentPeriodStart();
    final periodEnd = budget.getCurrentPeriodEnd();
    final rows = await db.query(
      'transactions',
      where: 'type = ?',
      whereArgs: ['DEBIT'],
    );
    final categoryIds = budget.selectedCategoryIds.toSet();
    var usedAmount = 0.0;

    for (final row in rows) {
      final transaction = Transaction.fromJson(Map<String, dynamic>.from(row));
      final date = _parseDate(transaction.time);
      if (date == null ||
          date.isBefore(periodStart) ||
          date.isAfter(periodEnd)) {
        continue;
      }
      if (categoryIds.isNotEmpty &&
          !transaction.selectedCategoryIds.any(categoryIds.contains)) {
        continue;
      }
      usedAmount += transaction.amount.abs();
    }

    final availableAmount = budget.amount - usedAmount;
    final percentageUsed =
        budget.amount > 0 ? (usedAmount / budget.amount) * 100 : 0.0;
    return _BudgetUsagePayload(
      usedAmount: usedAmount,
      availableAmount: availableAmount,
      percentageUsed: percentageUsed,
      isExceeded: usedAmount > budget.amount,
      isApproachingLimit: percentageUsed >= budget.alertThreshold,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }

  DateTime? _parseDate(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed);
  }

  String _recurrenceForBudget(Budget budget) {
    final raw = budget.type == 'category'
        ? (budget.timeFrame ?? 'monthly')
        : budget.type;
    return raw == 'unlimited' ? 'never' : raw;
  }

  String? _trimmedString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  // -------------------------------------------------------------------------
  // Backfill — enqueue existing rows when a rule is first enabled.
  // -------------------------------------------------------------------------

  /// Count records that currently match a rule's filter (for the backfill
  /// confirmation dialog).
  Future<int> countMatching(SyncRule rule) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(rule.entity.storage);
    var count = 0;
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row);
      if (rule.filter != null && !rule.filter!.matches(map)) continue;
      if (syncEntityRef(rule.entity, map) != null) count++;
    }
    return count;
  }

  /// Enqueue all existing matching rows (chunked, `INSERT OR IGNORE` so it
  /// never disturbs rows already in flight). Returns the number enqueued.
  Future<int> backfillRule(SyncRule rule) async {
    final ruleId = rule.id;
    if (ruleId == null) return 0;
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(rule.entity.storage);

    final refs = <String>[];
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row);
      if (rule.filter != null && !rule.filter!.matches(map)) continue;
      final ref = syncEntityRef(rule.entity, map);
      if (ref != null) refs.add(ref);
    }

    for (var i = 0; i < refs.length; i += _bulkChunkSize) {
      final slice = refs.sublist(i, min(i + _bulkChunkSize, refs.length));
      final batch = db.batch();
      final now = DateTime.now().toIso8601String();
      for (final ref in slice) {
        batch.insert(
          'sync_outbox',
          {
            'ruleId': ruleId,
            'entity': rule.entity.storage,
            'entityRef': ref,
            'op': SyncOp.upsert.storage,
            'payloadJson': null,
            'status': SyncOutboxStatus.pending,
            'attempts': 0,
            'nextAttemptAt': now,
            'createdAt': now,
            'updatedAt': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    }

    await _repo.markRuleBackfilled(ruleId);
    _log('backfilled ${refs.length} ${rule.entity.storage} for rule $ruleId');
    return refs.length;
  }
}
