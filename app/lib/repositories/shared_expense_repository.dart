import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/services/shared_expense_realtime_bus.dart';
import 'package:totals/services/shared_expense_crypto_service.dart';
import 'package:totals/services/totals_engine_client.dart';
import 'package:uuid/uuid.dart';

void _sharedExpenseLog(String message) {
  if (kDebugMode) {
    debugPrint('debug: SharedExpensesRepo: $message');
  }
}

String _logId(String value) {
  if (value.length <= 12) return value;
  return '${value.substring(0, 8)}...${value.substring(value.length - 4)}';
}

/// Result of computing balances + simplified settlements.
class SettlementPlan {
  final Map<String, double> balances;
  final List<SettlementDebt> debts;
  const SettlementPlan({required this.balances, required this.debts});
}

class SettlementDebt {
  /// pubkey of the debtor (who pays)
  final String from;

  /// pubkey of the creditor (who receives)
  final String to;
  final double amount;
  const SettlementDebt({
    required this.from,
    required this.to,
    required this.amount,
  });
}

class SharedExpenseRepository {
  static const _groupsKey = 'shared_expense_groups_v1';
  static const _groupsTable = 'shared_expense_groups';
  static const _groupKeyPrefix = 'shared_expense_group_key_';
  static const _legacyInvitePrefixes = ['totals://join/', 'totals//join/'];
  static const _snapshotPlaintextBudget = 45000;

  final TotalsEngineClient _engineClient;
  final SharedExpenseCryptoService _cryptoService;
  final FlutterSecureStorage _secureStorage;
  final Uuid _uuid;
  static final Set<String> _processingPayloadIds = {};

  SharedExpenseRepository({
    TotalsEngineClient? engineClient,
    SharedExpenseCryptoService? cryptoService,
    FlutterSecureStorage? secureStorage,
    Uuid? uuid,
  })  : _cryptoService = cryptoService ?? SharedExpenseCryptoService(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _uuid = uuid ?? const Uuid(),
        _engineClient = engineClient ??
            TotalsEngineClient(
              cryptoService: cryptoService ?? SharedExpenseCryptoService(),
            );

  // -------------------------------------------------------------------------
  // Identity / read API
  // -------------------------------------------------------------------------

  Future<String> myPublicKey() async {
    final identity = await _cryptoService.getOrCreateIdentity();
    return identity.publicKeyHex;
  }

  Future<List<SharedExpenseGroup>> getGroups() async {
    try {
      final db = await _groupsDatabase();
      final rows = await db.query(
        _groupsTable,
        orderBy: 'createdAt DESC',
      );
      final groups = rows
          .map(_groupFromDbRow)
          .whereType<SharedExpenseGroup>()
          .where((group) => group.id.isNotEmpty)
          .toList(growable: false);
      if (groups.isNotEmpty) {
        _sharedExpenseLog('getGroups loaded ${groups.length} db groups');
        return groups;
      }

      final legacyGroups = await _groupsFromLegacyPrefs();
      if (legacyGroups.isNotEmpty) {
        _sharedExpenseLog(
          'getGroups migrating ${legacyGroups.length} legacy pref groups',
        );
        await _saveGroups(legacyGroups);
        return legacyGroups;
      }

      _sharedExpenseLog('getGroups local cache empty');
      return const [];
    } catch (error, stackTrace) {
      _sharedExpenseLog('getGroups failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<List<SharedExpenseGroup>> _groupsFromLegacyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_groupsKey);
      if (raw == null || raw.isEmpty) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _sharedExpenseLog('getGroups ignored non-list legacy cache payload');
        return const [];
      }

      return decoded
          .whereType<Map>()
          .map((group) => SharedExpenseGroup.fromJson(
                Map<String, dynamic>.from(group),
              ))
          .where((group) => group.id.isNotEmpty)
          .toList(growable: false);
    } catch (error, stackTrace) {
      _sharedExpenseLog('getGroups ignored invalid legacy cache: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      return const [];
    }
  }

  SharedExpenseGroup? _groupFromDbRow(Map<String, Object?> row) {
    try {
      final payload = row['payload'];
      if (payload is! String || payload.isEmpty) {
        _sharedExpenseLog('getGroups ignored empty db payload');
        return null;
      }

      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        _sharedExpenseLog('getGroups ignored non-map db payload');
        return null;
      }

      return SharedExpenseGroup.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error, stackTrace) {
      _sharedExpenseLog('getGroups skipped invalid db row: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<Database> _groupsDatabase() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_groupsTable (
        id TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_shared_expense_groups_createdAt '
      'ON $_groupsTable(createdAt)',
    );
    return db;
  }

  // -------------------------------------------------------------------------
  // Group create / join / leave / rename
  // -------------------------------------------------------------------------

  Future<SharedExpenseGroup> createGroup({
    required String name,
    required String displayName,
  }) async {
    final identity = await _cryptoService.getOrCreateIdentity();
    _sharedExpenseLog('createGroup start name="$name"');
    try {
      final response = await _engineClient.createGroup();
      final groupKey = _cryptoService.randomBytes(32);
      await _writeGroupKey(
          response.id, SharedExpenseCryptoService.toHex(groupKey));

      final group = SharedExpenseGroup(
        id: response.id,
        name: name,
        myDisplayName: displayName,
        createdAt: response.createdAt,
        expiresAt: response.expiresAt,
        status: SharedExpenseGroupStatus.ready,
        members: [
          SharedExpenseMember(
            devicePublicKey: identity.publicKeyHex,
            joinedAt: response.createdAt,
          ),
        ],
        approvedMemberKeys: {identity.publicKeyHex},
        displayNames: {identity.publicKeyHex: displayName},
        activity: [
          SharedActivityEntry(
            id: _uuid.v4(),
            timestamp: DateTime.now().millisecondsSinceEpoch,
            actor: identity.publicKeyHex,
            kind: 'group_created',
            data: {'name': name},
          ),
        ],
      );
      await _upsertGroup(group);
      _sharedExpenseLog(
        'createGroup engine success group=${_logId(group.id)}',
      );
      return group;
    } catch (error, stackTrace) {
      _sharedExpenseLog('createGroup engine failed, using local group: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      final localId = _uuid.v4();
      final group = SharedExpenseGroup(
        id: localId,
        name: name,
        myDisplayName: displayName,
        createdAt: DateTime.now(),
        status: SharedExpenseGroupStatus.localOnly,
        members: [
          SharedExpenseMember(devicePublicKey: identity.publicKeyHex),
        ],
        approvedMemberKeys: {identity.publicKeyHex},
        displayNames: {identity.publicKeyHex: displayName},
      );
      await _writeGroupKey(
        localId,
        SharedExpenseCryptoService.toHex(_cryptoService.randomBytes(32)),
      );
      await _upsertGroup(group);
      _sharedExpenseLog('createGroup local fallback group=${_logId(group.id)}');
      return group;
    }
  }

  Future<SharedExpenseGroup> joinGroup({
    required String inviteOrCode,
    required String displayName,
  }) async {
    final groupId = parseInviteCode(inviteOrCode);
    if (groupId == null) {
      _sharedExpenseLog('joinGroup rejected invalid invite/code');
      throw const TotalsEngineException(
          'Enter a valid group code or invite link.');
    }

    _sharedExpenseLog('joinGroup start group=${_logId(groupId)}');
    await _engineClient.joinGroup(groupId);
    final members = await _engineClient.listMembers(groupId);
    _sharedExpenseLog(
      'joinGroup listed ${members.length} members for group=${_logId(groupId)}',
    );
    final existing = await _groupById(groupId);
    final identity = await _cryptoService.getOrCreateIdentity();
    final group = SharedExpenseGroup(
      id: groupId,
      name: existing?.name ?? 'Shared group',
      myDisplayName: displayName,
      createdAt: existing?.createdAt ?? DateTime.now(),
      expiresAt: existing?.expiresAt,
      status: existing?.hasGroupKey == true
          ? SharedExpenseGroupStatus.ready
          : SharedExpenseGroupStatus.pendingApproval,
      members: members,
      approvedMemberKeys: existing?.approvedMemberKeys ?? const <String>{},
      expenses: existing?.expenses ?? const [],
      activity: existing?.activity ?? const [],
      displayNames: {
        ...?existing?.displayNames,
        identity.publicKeyHex: displayName,
      },
      pendingApprovals: existing?.pendingApprovals ?? const [],
      backfillNewMembers: existing?.backfillNewMembers ?? false,
      keySharedWith: existing?.keySharedWith ?? const {},
    );
    await _upsertGroup(group);

    // Broadcast join_request to each existing member so they can approve us.
    await _broadcastJoinRequest(group);

    // Now try to pull any pending payloads in case we were already approved.
    final changed = await syncGroup(groupId);
    final result = (await _groupById(groupId)) ?? group;
    _sharedExpenseLog(
      'joinGroup done group=${_logId(groupId)} status=${result.status.name} '
      'syncApplied=$changed',
    );
    return result;
  }

  Future<void> leaveGroup(SharedExpenseGroup group) async {
    _sharedExpenseLog('leaveGroup start group=${_logId(group.id)}');
    try {
      await _engineClient.leaveGroup(group.id);
    } catch (error) {
      _sharedExpenseLog('leaveGroup engine failed (continuing local): $error');
    }
    await _deleteLocalGroup(group.id);
    _sharedExpenseLog('leaveGroup done group=${_logId(group.id)}');
  }

  Future<void> _deleteLocalGroup(String groupId) async {
    final db = await _groupsDatabase();
    await db.delete(_groupsTable, where: 'id = ?', whereArgs: [groupId]);
    await _secureStorage.delete(key: '$_groupKeyPrefix$groupId');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_groupsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final filtered = decoded
              .whereType<Map>()
              .map((g) => Map<String, dynamic>.from(g))
              .where((g) => g['id'] != groupId)
              .toList();
          await prefs.setString(_groupsKey, jsonEncode(filtered));
        }
      } catch (_) {/* ignore */}
    }
  }

  /// Update group metadata and/or my own member display name.
  /// Broadcasts the matching payloads to all approved members.
  Future<SharedExpenseGroup> updateMeta({
    required SharedExpenseGroup group,
    String? name,
    String? myDisplayName,
    bool? backfillNewMembers,
  }) async {
    if (name == null &&
        myDisplayName == null &&
        backfillNewMembers == null) {
      return group;
    }

    final identity = await _cryptoService.getOrCreateIdentity();
    final nameChanged = name != null && name.trim() != group.name;
    final displayChanged =
        myDisplayName != null && myDisplayName.trim() != group.myDisplayName;
    final backfillChanged = backfillNewMembers != null &&
        backfillNewMembers != group.backfillNewMembers;
    if (!nameChanged && !displayChanged && !backfillChanged) return group;

    final updated = group.copyWith(
      name: nameChanged ? name.trim() : null,
      myDisplayName: displayChanged ? myDisplayName.trim() : null,
      backfillNewMembers: backfillChanged ? backfillNewMembers : null,
      displayNames: displayChanged
          ? {
              ...group.displayNames,
              identity.publicKeyHex: myDisplayName.trim(),
            }
          : null,
      activity: nameChanged
          ? [
              ...group.activity,
              SharedActivityEntry(
                id: _uuid.v4(),
                timestamp: DateTime.now().millisecondsSinceEpoch,
                actor: identity.publicKeyHex,
                kind: 'group_renamed',
                data: {'before': group.name, 'after': name.trim()},
              ),
            ]
          : null,
    );

    await _upsertGroup(updated);

    if (nameChanged || backfillChanged) {
      await _emitGroupMeta(updated);
    }
    if (displayChanged) {
      await _emitMemberMeta(updated);
    }
    return updated;
  }

  // -------------------------------------------------------------------------
  // Member approval (existing member sends group key to a new joiner)
  // -------------------------------------------------------------------------

  Future<void> approveMember({
    required SharedExpenseGroup group,
    required SharedExpenseMember member,
  }) async {
    final groupKeyHex = await _readGroupKey(group.id);
    if (groupKeyHex == null) {
      _sharedExpenseLog(
        'approveMember missing group key group=${_logId(group.id)} '
        'member=${_logId(member.devicePublicKey)}',
      );
      throw const TotalsEngineException(
          'This device does not have the group key.');
    }

    final identity = await _cryptoService.getOrCreateIdentity();
    _sharedExpenseLog(
      'approveMember start group=${_logId(group.id)} '
      'member=${_logId(member.devicePublicKey)}',
    );

    // Send the group key encrypted with a 1:1 shared secret.
    final encryptedBlob = await _cryptoService.encryptGroupKeyPayload(
      recipientPublicKeyHex: member.devicePublicKey,
      payload: {
        'type': 'key_exchange',
        'groupId': group.id,
        'groupName': group.name,
        'groupKey': groupKeyHex,
        'approvedPublicKey': member.devicePublicKey,
        'approvedBy': identity.publicKeyHex,
        'approverDisplayName': group.myDisplayName,
        'backfillNewMembers': group.backfillNewMembers,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    await _engineClient.submitTargetedPayload(
      groupId: group.id,
      encryptedBlob: encryptedBlob,
      recipientPublicKeys: [member.devicePublicKey],
    );

    final updated = group.copyWith(
      approvedMemberKeys: {
        ...group.approvedMemberKeys,
        member.devicePublicKey,
        identity.publicKeyHex,
      },
      keySharedWith: {
        ...group.keySharedWith,
        member.devicePublicKey,
      },
      pendingApprovals: group.pendingApprovals
          .where((p) => p.publicKey != member.devicePublicKey)
          .toList(),
      activity: [
        ...group.activity,
        SharedActivityEntry(
          id: _uuid.v4(),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          actor: identity.publicKeyHex,
          kind: 'member_approved',
          data: {'memberPk': member.devicePublicKey},
        ),
      ],
    );
    if (updated.backfillNewMembers) {
      await _emitGroupSnapshotPayload(
        group: updated,
        recipientPublicKey: member.devicePublicKey,
        groupKeyHex: groupKeyHex,
      );
    }
    await _upsertGroup(updated);
    _sharedExpenseLog(
      'approveMember done group=${_logId(group.id)} '
      'member=${_logId(member.devicePublicKey)}',
    );
  }

  /// Dismiss a pending join request without approving the requester.
  Future<SharedExpenseGroup> dismissApproval({
    required SharedExpenseGroup group,
    required String publicKey,
  }) async {
    final updated = group.copyWith(
      pendingApprovals: group.pendingApprovals
          .where((p) => p.publicKey != publicKey)
          .toList(),
    );
    await _upsertGroup(updated);
    return updated;
  }

  // -------------------------------------------------------------------------
  // Refresh (full server-side membership sync)
  // -------------------------------------------------------------------------

  Future<List<SharedExpenseGroup>> refreshGroups() async {
    _sharedExpenseLog('refreshGroups start');
    final localGroups = await getGroups();
    final localById = {for (final group in localGroups) group.id: group};
    final serverGroups = await _engineClient.listGroups();
    final serverGroupIds = serverGroups.map((group) => group.id).toSet();
    final identity = await _cryptoService.getOrCreateIdentity();
    _sharedExpenseLog(
      'refreshGroups serverGroups=${serverGroups.length} '
      'localGroups=${localGroups.length}',
    );

    for (final local in localGroups) {
      if (local.status == SharedExpenseGroupStatus.localOnly) continue;
      if (serverGroupIds.contains(local.id)) continue;
      await _deleteLocalGroup(local.id);
      _sharedExpenseLog('refreshGroups pruned group=${_logId(local.id)}');
    }

    for (final serverGroup in serverGroups) {
      final local = localById[serverGroup.id];
      final hasKey = await _readGroupKey(serverGroup.id) != null;

      // Build a set of pubkeys the server currently lists. If a member has
      // left, drop them from approvedMemberKeys / keySharedWith / pending
      // so the next time they rejoin, the approval flow starts clean instead
      // of skipping straight to "they have the key".
      final currentMemberKeys = serverGroup.members
          .map((m) => m.devicePublicKey)
          .where((k) => k.isNotEmpty)
          .toSet();

      final approvedKeys = <String>{
        ...?local?.approvedMemberKeys.where(
            (k) => k == identity.publicKeyHex || currentMemberKeys.contains(k)),
        if (hasKey) identity.publicKeyHex,
      };
      final sharedWith = <String>{
        ...?local?.keySharedWith.where((k) => currentMemberKeys.contains(k)),
      };
      final pruned = local?.pendingApprovals
              .where((p) => currentMemberKeys.contains(p.publicKey))
              .toList() ??
          const [];

      final merged = SharedExpenseGroup(
        id: serverGroup.id,
        name: local?.name ?? 'Shared group',
        myDisplayName: local?.myDisplayName ?? 'Me',
        createdAt: serverGroup.createdAt,
        expiresAt: serverGroup.expiresAt,
        status: hasKey
            ? SharedExpenseGroupStatus.ready
            : SharedExpenseGroupStatus.pendingApproval,
        members: serverGroup.members,
        approvedMemberKeys: approvedKeys,
        expenses: local?.expenses ?? const [],
        activity: local?.activity ?? const [],
        displayNames: local?.displayNames ?? const {},
        pendingApprovals: pruned,
        backfillNewMembers: local?.backfillNewMembers ?? false,
        keySharedWith: sharedWith,
        lastSyncAt: local?.lastSyncAt,
      );
      await _upsertGroup(merged);
      _sharedExpenseLog(
        'refreshGroups merged group=${_logId(merged.id)} '
        'status=${merged.status.name} members=${merged.members.length}',
      );
    }

    for (final serverGroup in serverGroups) {
      final changed = await syncGroup(serverGroup.id);
      if (changed) {
        _sharedExpenseLog(
          'refreshGroups syncApplied group=${_logId(serverGroup.id)}',
        );
      }
    }

    final groups = await getGroups();
    _sharedExpenseLog('refreshGroups done groups=${groups.length}');
    return groups;
  }

  /// Pull and apply all pending payloads for one group. Returns true if any
  /// state changed locally.
  Future<bool> syncGroup(String groupId) async {
    final group = await _groupById(groupId);
    if (group == null) {
      _sharedExpenseLog('syncGroup unknown group=${_logId(groupId)}');
      return false;
    }
    _sharedExpenseLog('syncGroup start group=${_logId(groupId)}');
    final payloads = await _engineClient.pullPending(groupId);
    _sharedExpenseLog(
      'syncGroup payloads=${payloads.length} group=${_logId(groupId)}',
    );
    var changed = false;
    final identity = await _cryptoService.getOrCreateIdentity();

    for (final payload in payloads) {
      final applied = await _processPendingPayload(
        groupId: groupId,
        myPublicKey: identity.publicKeyHex,
        payload: payload,
      );
      if (applied) changed = true;
    }

    // Stamp lastSyncAt + retry any pending meta broadcast.
    final after = await _groupById(groupId);
    if (after != null) {
      await _upsertGroup(after.copyWith(
        lastSyncAt: DateTime.now().millisecondsSinceEpoch,
      ));
      if (after.pendingMetaBroadcast && after.hasGroupKey) {
        final retryOk = await _broadcastMetaPayloads(after);
        if (retryOk) {
          final cleared = await _groupById(groupId);
          if (cleared != null) {
            await _upsertGroup(
              cleared.copyWith(pendingMetaBroadcast: false),
            );
          }
        }
      }
    }

    _sharedExpenseLog(
      'syncGroup done group=${_logId(groupId)} changed=$changed',
    );
    if (changed) {
      final latest = await _groupById(groupId);
      if (latest != null) SharedExpenseRealtimeBus.instance.publish(latest);
    }
    return changed;
  }

  /// Legacy alias for callers that still expect the old name.
  Future<bool> processPendingApprovals(String groupId) => syncGroup(groupId);

  Stream<SharedExpenseGroup> watchGroupRealtime(String groupId) async* {
    final identity = await _cryptoService.getOrCreateIdentity();
    _sharedExpenseLog('watchGroupRealtime start group=${_logId(groupId)}');

    await for (final payload in _engineClient.streamPending(groupId)) {
      final changed = await _processPendingPayload(
        groupId: groupId,
        myPublicKey: identity.publicKeyHex,
        payload: payload,
      );
      final latest = await _stampRealtimeSync(groupId);
      if (changed && latest != null) {
        SharedExpenseRealtimeBus.instance.publish(latest);
        yield latest;
      }
    }
  }

  Stream<void> watchGroupListRealtime() {
    return _engineClient.streamGroupListChanges();
  }

  Future<bool> isEngineReachable() => _engineClient.isReachable();

  /// All transaction refs currently linked to a (non-deleted) shared expense
  /// in any group. The personal ledger uses this to avoid double-counting a
  /// transaction that has been split into a group.
  Future<Set<String>> getAllLinkedTxRefs() async {
    final groups = await getGroups();
    final refs = <String>{};
    for (final group in groups) {
      for (final expense in group.expenses) {
        if (expense.deleted) continue;
        final ref = expense.linkedTxRef;
        if (ref != null && ref.isNotEmpty) refs.add(ref);
      }
    }
    return refs;
  }

  /// Split a local transaction into a shared group. Caller provides the
  /// already-resolved amount/reason/timestamp + tx reference; this just wraps
  /// createExpense with `linkedTxRef` set so the personal ledger reconciles.
  Future<SharedExpenseGroup> splitTransactionIntoGroup({
    required SharedExpenseGroup group,
    required double amount,
    required String reason,
    required String paidBy,
    required List<String> splitAmong,
    required String linkedTxRef,
    int? timestamp,
  }) async {
    return createExpense(
      group: group,
      amount: amount,
      reason: reason,
      paidBy: paidBy,
      splitAmong: splitAmong,
      linkedTxRef: linkedTxRef,
      timestamp: timestamp,
    );
  }

  // -------------------------------------------------------------------------
  // Expense CRUD
  // -------------------------------------------------------------------------

  Future<SharedExpenseGroup> createExpense({
    required SharedExpenseGroup group,
    required double amount,
    required String reason,
    required String paidBy,
    required List<String> splitAmong,
    String currency = 'ETB',
    String kind = 'expense',
    String? linkedTxRef,
    int? timestamp,
  }) async {
    final identity = await _cryptoService.getOrCreateIdentity();
    final normalizedLinkedTxRef = _normalizeLinkedTxRef(linkedTxRef);
    if (normalizedLinkedTxRef != null &&
        await _isLinkedTxRefUsed(normalizedLinkedTxRef)) {
      throw Exception('This transaction is already linked to a shared expense.');
    }
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    final expense = SharedExpense(
      id: _uuid.v4(),
      amount: amount,
      currency: currency,
      reason: reason,
      paidBy: paidBy,
      splitAmong: splitAmong,
      timestamp: timestamp ?? createdAt,
      kind: kind,
      linkedTxRef: normalizedLinkedTxRef,
      status: 'pending',
    );

    final activityEntry = SharedActivityEntry(
      id: _uuid.v4(),
      timestamp: createdAt,
      actor: identity.publicKeyHex,
      kind: kind == 'settlement' ? 'settlement_created' : 'expense_created',
      data: {
        'expenseId': expense.id,
        'amount': amount,
        'reason': reason,
        'paidBy': paidBy,
        'splitAmong': splitAmong,
      },
    );

    var updated = group.copyWith(
      expenses: [...group.expenses, expense],
      activity: [...group.activity, activityEntry],
    );
    await _upsertGroup(updated);

    try {
      await _emitExpensePayload(updated, expense);
      updated = updated.copyWith(
        expenses: updated.expenses
            .map((e) => e.id == expense.id ? e.copyWith(status: 'synced') : e)
            .toList(),
      );
      await _upsertGroup(updated);
    } catch (error) {
      _sharedExpenseLog('createExpense submit failed (kept pending): $error');
    }
    return updated;
  }

  Future<SharedExpenseGroup> updateExpense({
    required SharedExpenseGroup group,
    required SharedExpense before,
    required double amount,
    required String reason,
    required String paidBy,
    required List<String> splitAmong,
    int? timestamp,
    String? linkedTxRef,
    bool clearLinkedTxRef = false,
  }) async {
    final identity = await _cryptoService.getOrCreateIdentity();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final normalizedLinkedTxRef = clearLinkedTxRef
        ? null
        : _normalizeLinkedTxRef(linkedTxRef ?? before.linkedTxRef);
    if (normalizedLinkedTxRef != null &&
        normalizedLinkedTxRef != before.linkedTxRef &&
        await _isLinkedTxRefUsed(normalizedLinkedTxRef)) {
      throw Exception('This transaction is already linked to a shared expense.');
    }
    final after = before.copyWith(
      amount: amount,
      reason: reason,
      paidBy: paidBy,
      splitAmong: splitAmong,
      timestamp: timestamp ?? before.timestamp,
      linkedTxRef: normalizedLinkedTxRef,
      clearLinkedTxRef: clearLinkedTxRef,
      revisedAt: ts,
      status: 'pending',
    );

    final activity = [...group.activity];
    if (amount != before.amount) {
      activity.add(SharedActivityEntry(
        id: _uuid.v4(),
        timestamp: ts,
        actor: identity.publicKeyHex,
        kind: 'expense_amount_changed',
        data: {
          'expenseId': before.id,
          'before': before.amount,
          'after': amount
        },
      ));
    }
    if (reason != before.reason) {
      activity.add(SharedActivityEntry(
        id: _uuid.v4(),
        timestamp: ts,
        actor: identity.publicKeyHex,
        kind: 'expense_reason_changed',
        data: {
          'expenseId': before.id,
          'before': before.reason,
          'after': reason
        },
      ));
    }
    if (paidBy != before.paidBy) {
      activity.add(SharedActivityEntry(
        id: _uuid.v4(),
        timestamp: ts,
        actor: identity.publicKeyHex,
        kind: 'expense_paid_by_changed',
        data: {
          'expenseId': before.id,
          'before': before.paidBy,
          'after': paidBy
        },
      ));
    }
    if (!_sameList(splitAmong, before.splitAmong)) {
      activity.add(SharedActivityEntry(
        id: _uuid.v4(),
        timestamp: ts,
        actor: identity.publicKeyHex,
        kind: 'expense_split_changed',
        data: {
          'expenseId': before.id,
          'before': before.splitAmong,
          'after': splitAmong,
        },
      ));
    }
    if (timestamp != null && timestamp != before.timestamp) {
      activity.add(SharedActivityEntry(
        id: _uuid.v4(),
        timestamp: ts,
        actor: identity.publicKeyHex,
        kind: 'expense_date_changed',
        data: {
          'expenseId': before.id,
          'before': before.timestamp,
          'after': timestamp,
        },
      ));
    }
    if (normalizedLinkedTxRef != before.linkedTxRef) {
      activity.add(SharedActivityEntry(
        id: _uuid.v4(),
        timestamp: ts,
        actor: identity.publicKeyHex,
        kind: 'expense_linked_transaction_changed',
        data: {
          'expenseId': before.id,
          'before': before.linkedTxRef,
          'after': normalizedLinkedTxRef,
        },
      ));
    }

    var updated = group.copyWith(
      expenses:
          group.expenses.map((e) => e.id == before.id ? after : e).toList(),
      activity: activity,
    );
    await _upsertGroup(updated);

    try {
      await _emitExpensePayload(updated, after);
      updated = updated.copyWith(
        expenses: updated.expenses
            .map((e) => e.id == after.id ? e.copyWith(status: 'synced') : e)
            .toList(),
      );
      await _upsertGroup(updated);
    } catch (error) {
      _sharedExpenseLog('updateExpense submit failed: $error');
    }
    return updated;
  }

  String? _normalizeLinkedTxRef(String? linkedTxRef) {
    final trimmed = linkedTxRef?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<bool> _isLinkedTxRefUsed(String linkedTxRef) async {
    final refs = await getAllLinkedTxRefs();
    return refs.contains(linkedTxRef);
  }

  Future<SharedExpenseGroup> deleteExpense({
    required SharedExpenseGroup group,
    required String expenseId,
  }) async {
    final identity = await _cryptoService.getOrCreateIdentity();
    final existing = group.expenses.firstWhere(
      (e) => e.id == expenseId,
      orElse: () => SharedExpense(
        id: expenseId,
        amount: 0,
        currency: 'ETB',
        reason: '',
        paidBy: '',
        splitAmong: const [],
        timestamp: 0,
      ),
    );
    final ts = DateTime.now().millisecondsSinceEpoch;
    final deleted = existing.copyWith(
      deleted: true,
      revisedAt: ts,
      status: 'pending',
    );
    var updated = group.copyWith(
      expenses:
          group.expenses.map((e) => e.id == expenseId ? deleted : e).toList(),
      activity: [
        ...group.activity,
        SharedActivityEntry(
          id: _uuid.v4(),
          timestamp: ts,
          actor: identity.publicKeyHex,
          kind: 'expense_deleted',
          data: {'expenseId': expenseId, 'reason': existing.reason},
        ),
      ],
    );
    await _upsertGroup(updated);

    try {
      await _emitExpensePayload(updated, deleted);
      updated = updated.copyWith(
        expenses: updated.expenses
            .map((e) => e.id == expenseId ? e.copyWith(status: 'synced') : e)
            .toList(),
      );
      await _upsertGroup(updated);
    } catch (error) {
      _sharedExpenseLog('deleteExpense submit failed: $error');
    }
    return updated;
  }

  /// Record a settlement: I (the caller) paid `amount` to `recipientPk`.
  /// Modeled as an expense with kind='settlement' so balances re-converge.
  Future<SharedExpenseGroup> settleUpWith({
    required SharedExpenseGroup group,
    required String recipientPk,
    required double amount,
  }) async {
    final identity = await _cryptoService.getOrCreateIdentity();
    return createExpense(
      group: group,
      amount: amount,
      reason: 'Settlement',
      paidBy: identity.publicKeyHex,
      splitAmong: [recipientPk],
      kind: 'settlement',
    );
  }

  Future<SharedExpenseGroup> sendNudge({
    required SharedExpenseGroup group,
    required double amount,
    required List<String> debtorPks,
  }) async {
    final identity = await _cryptoService.getOrCreateIdentity();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final debtorSet = debtorPks.toSet();
    final amountByDebtorPk = <String, double>{};
    for (final debt in settlementPlanFor(group).debts) {
      if (debt.to != identity.publicKeyHex || !debtorSet.contains(debt.from)) {
        continue;
      }
      amountByDebtorPk.update(
        debt.from,
        (current) => current + debt.amount,
        ifAbsent: () => debt.amount,
      );
    }
    final activityEntry = SharedActivityEntry(
      id: _uuid.v4(),
      timestamp: ts,
      actor: identity.publicKeyHex,
      kind: 'nudge_sent',
      data: {
        'amount': amount,
        'debtorPks': debtorPks,
        'amountByDebtorPk': amountByDebtorPk,
      },
    );

    await _emitNudgePayload(group, activityEntry, debtorPks);
    final updated = group.copyWith(
      activity: [...group.activity, activityEntry],
    );
    await _upsertGroup(updated);
    return updated;
  }

  // -------------------------------------------------------------------------
  // Balance / settlement helpers (delegating to top-level functions so widgets
  // can call them without holding a repository instance).
  // -------------------------------------------------------------------------

  Map<String, double> computeBalances(SharedExpenseGroup group) =>
      computeBalancesFor(group);

  SettlementPlan settlementPlan(SharedExpenseGroup group) =>
      settlementPlanFor(group);

  int memberColor(SharedExpenseGroup group, String pubkey) =>
      memberColorFor(group, pubkey);

  // -------------------------------------------------------------------------
  // Invite parsing
  // -------------------------------------------------------------------------

  String inviteCodeFor(String groupId) => groupId;

  String? parseInviteCode(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    for (final prefix in _legacyInvitePrefixes) {
      if (trimmed.startsWith(prefix)) {
        return _validUuidOrNull(trimmed.substring(prefix.length));
      }
    }

    final uri = Uri.tryParse(trimmed);
    final fromPath =
        uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : trimmed;
    return _validUuidOrNull(fromPath);
  }

  String? _validUuidOrNull(String value) {
    final normalized = value.trim();
    return Uuid.isValidUUID(
      fromString: normalized,
      validationMode: ValidationMode.nonStrict,
    )
        ? normalized.toLowerCase()
        : null;
  }

  // -------------------------------------------------------------------------
  // Internal payload routing
  // -------------------------------------------------------------------------

  /// Returns true if the payload changed local state.
  Future<bool> _processPendingPayload({
    required String groupId,
    required String myPublicKey,
    required EnginePendingPayload payload,
  }) async {
    if (!_processingPayloadIds.add(payload.id)) {
      _sharedExpenseLog(
        '_processPendingPayload already processing payload=${_logId(payload.id)}',
      );
      return false;
    }

    try {
      // Re-read the group key on every payload. If a key_exchange establishes
      // the key, later payloads in the same sync/stream can decrypt immediately.
      final groupKeyHex = await _readGroupKey(groupId);
      final groupKeyBytes = groupKeyHex == null
          ? null
          : SharedExpenseCryptoService.fromHex(groupKeyHex);

      Map<String, dynamic>? decoded;
      if (groupKeyBytes != null) {
        decoded = await _cryptoService.decryptPayloadWithKey(
          keyBytes: groupKeyBytes,
          encryptedBlob: payload.encryptedBlob,
        );
      }
      decoded ??= await _cryptoService.decryptGroupKeyPayload(
        senderPublicKeyHex: payload.senderPublicKey,
        encryptedBlob: payload.encryptedBlob,
      );

      if (decoded == null) {
        _sharedExpenseLog(
          '_processPendingPayload undecryptable payload=${_logId(payload.id)}',
        );
        if (groupKeyHex == null) {
          _sharedExpenseLog(
            '_processPendingPayload waiting for group key payload=${_logId(payload.id)}',
          );
          return false;
        }
        await _acknowledgePayload(payload.id);
        return false;
      }

      final type = decoded['type'] as String?;
      _sharedExpenseLog(
        '_processPendingPayload applying type=$type '
        'sender=${_logId(payload.senderPublicKey)}',
      );
      final applied = await _applyPayload(
        groupId: groupId,
        senderPk: payload.senderPublicKey,
        decoded: decoded,
        myPublicKey: myPublicKey,
      );
      await _acknowledgePayload(payload.id);
      return applied;
    } finally {
      _processingPayloadIds.remove(payload.id);
    }
  }

  Future<void> _acknowledgePayload(String payloadId) async {
    try {
      await _engineClient.acknowledgePayload(payloadId);
    } on TotalsEngineException catch (error) {
      if (error.statusCode == 404) {
        _sharedExpenseLog(
          '_acknowledgePayload ignored missing payload=${_logId(payloadId)}',
        );
        return;
      }
      rethrow;
    }
  }

  Future<SharedExpenseGroup?> _stampRealtimeSync(String groupId) async {
    final after = await _groupById(groupId);
    if (after == null) return null;

    var latest = after.copyWith(
      lastSyncAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _upsertGroup(latest);

    if (latest.pendingMetaBroadcast && latest.hasGroupKey) {
      final retryOk = await _broadcastMetaPayloads(latest);
      if (retryOk) {
        final cleared = await _groupById(groupId);
        if (cleared != null) {
          latest = cleared.copyWith(pendingMetaBroadcast: false);
          await _upsertGroup(latest);
        }
      }
    }

    return latest;
  }

  /// Returns true if the payload changed local state.
  Future<bool> _applyPayload({
    required String groupId,
    required String senderPk,
    required Map<String, dynamic> decoded,
    required String myPublicKey,
  }) async {
    final type = decoded['type'] as String?;
    final group = await _groupById(groupId);
    if (group == null) return false;

    switch (type) {
      // Legacy alias kept so devices still on `group_key` can be approved.
      case 'group_key':
      case 'key_exchange':
        return _applyKeyExchange(group, senderPk, decoded);

      case 'group_meta':
        return _applyGroupMeta(group, senderPk, decoded);

      case 'member_meta':
        return _applyMemberMeta(group, senderPk, decoded);

      case 'expense':
        return _applyExpense(group, senderPk, decoded);

      case 'join_request':
        return _applyJoinRequest(group, senderPk, decoded, myPublicKey);

      case 'nudge':
        return _applyNudge(group, senderPk, decoded);

      case 'group_snapshot':
        return _applyGroupSnapshot(group, senderPk, decoded);

      default:
        _sharedExpenseLog('_applyPayload unknown type=$type');
        return false;
    }
  }

  Future<bool> _applyKeyExchange(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
  ) async {
    final groupKeyHex = decoded['groupKey'] as String?;
    if (groupKeyHex == null || groupKeyHex.length != 64) return false;
    await _writeGroupKey(group.id, groupKeyHex);
    final approvedBy = decoded['approvedBy'] as String?;
    final approvedPk = decoded['approvedPublicKey'] as String?;
    final approverName = decoded['approverDisplayName'] as String?;
    final backfillNewMembers = decoded['backfillNewMembers'] is bool
        ? decoded['backfillNewMembers'] as bool
        : null;
    final newDisplayNames = <String, String>{...group.displayNames};
    if (approvedBy != null && approverName != null) {
      newDisplayNames[approvedBy] = approverName;
    }
    // The sender of this key_exchange is, by definition, the approver — they
    // hold the group key (otherwise they couldn't have shared it). Always
    // mark them approved, even when the payload omits the explicit fields
    // (e.g. older iOS clients send only {type, groupKey}).
    final approvedKeysAfter = <String>{
      ...group.approvedMemberKeys,
      if (senderPk.isNotEmpty) senderPk,
      if (approvedBy != null) approvedBy,
      if (approvedPk != null) approvedPk,
    };
    final updated = group.copyWith(
      name: decoded['groupName'] as String? ?? group.name,
      status: SharedExpenseGroupStatus.ready,
      backfillNewMembers: backfillNewMembers,
      approvedMemberKeys: approvedKeysAfter,
      keySharedWith: {
        ...group.keySharedWith,
        if (senderPk.isNotEmpty) senderPk,
      },
      displayNames: newDisplayNames,
      pendingApprovals: group.pendingApprovals
          .where((p) =>
              p.publicKey != senderPk &&
              p.publicKey != approvedPk &&
              p.publicKey != approvedBy)
          .toList(),
    );
    await _upsertGroup(updated);
    // We now have the key — announce our display name to the approver.
    await _emitMemberMeta(updated);
    return true;
  }

  Future<bool> _applyGroupMeta(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
  ) async {
    final newName = (decoded['name'] as String?)?.trim();
    final incomingBackfill = decoded['backfillNewMembers'] is bool
        ? decoded['backfillNewMembers'] as bool
        : null;
    final nameChanged =
        newName != null && newName.isNotEmpty && newName != group.name;
    final backfillChanged = incomingBackfill != null &&
        incomingBackfill != group.backfillNewMembers;
    final isFirstSeen = !group.approvedMemberKeys.contains(senderPk);
    if (!nameChanged && !backfillChanged && !isFirstSeen) return false;

    final timestamp = (decoded['timestamp'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final activity = [...group.activity];
    if (nameChanged) {
      activity.add(SharedActivityEntry(
        id: _uuid.v4(),
        timestamp: timestamp,
        actor: senderPk,
        kind: 'group_renamed',
        data: {'before': group.name, 'after': newName},
      ));
    }
    if (isFirstSeen) {
      activity.add(SharedActivityEntry(
        id: _uuid.v4(),
        timestamp: timestamp,
        actor: senderPk,
        kind: 'member_joined',
        data: {},
      ));
    }

    final updated = group.copyWith(
      name: nameChanged ? newName : null,
      backfillNewMembers: backfillChanged ? incomingBackfill : null,
      approvedMemberKeys: {
        ...group.approvedMemberKeys,
        if (senderPk.isNotEmpty) senderPk,
      },
      activity: activity,
    );
    await _upsertGroup(updated);
    return true;
  }

  Future<bool> _applyMemberMeta(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
  ) async {
    final displayName = (decoded['displayName'] as String?)?.trim();
    if (displayName == null || displayName.isEmpty) return false;
    final current = group.displayNames[senderPk];
    final isFirstSeen = !group.approvedMemberKeys.contains(senderPk);
    if (current == displayName && !isFirstSeen) return false;

    final activity = [...group.activity];
    if (isFirstSeen) {
      activity.add(SharedActivityEntry(
        id: _uuid.v4(),
        timestamp: (decoded['timestamp'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        actor: senderPk,
        kind: 'member_joined',
        data: {'displayName': displayName},
      ));
    }

    final updated = group.copyWith(
      displayNames: {...group.displayNames, senderPk: displayName},
      approvedMemberKeys: {...group.approvedMemberKeys, senderPk},
      activity: activity,
    );
    await _upsertGroup(updated);
    // If we haven't sent our own key/meta to this person yet, do so now.
    if (!group.keySharedWith.contains(senderPk)) {
      await _emitMemberMeta(updated);
    }
    return true;
  }

  Future<bool> _applyExpense(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
  ) async {
    final incoming = SharedExpense.fromJson(decoded);
    if (incoming.id.isEmpty) return false;
    final existing = group.expenses
        .where((e) => e.id == incoming.id)
        .toList(growable: false);
    List<SharedExpense> next;
    final activity = <SharedActivityEntry>[...group.activity];
    final actor = incoming.paidBy.isNotEmpty ? incoming.paidBy : senderPk;
    final ts = incoming.revisedAt ?? incoming.timestamp;

    if (existing.isEmpty) {
      next = [...group.expenses, incoming.copyWith(status: 'synced')];
      if (!incoming.deleted) {
        activity.add(SharedActivityEntry(
          id: _uuid.v4(),
          timestamp: ts,
          actor: actor,
          kind: incoming.kind == 'settlement'
              ? 'settlement_created'
              : 'expense_created',
          data: {
            'expenseId': incoming.id,
            'amount': incoming.amount,
            'reason': incoming.reason,
            'paidBy': incoming.paidBy,
            'splitAmong': incoming.splitAmong,
          },
        ));
      }
    } else {
      final cur = existing.first;
      // Last-write-wins by revisedAt (or timestamp for first write).
      final curTs = cur.revisedAt ?? cur.timestamp;
      final inTs = incoming.revisedAt ?? incoming.timestamp;
      if (inTs <= curTs) return false;
      next = group.expenses
          .map((e) =>
              e.id == incoming.id ? incoming.copyWith(status: 'synced') : e)
          .toList();

      // Log per-field changes (or a deletion).
      if (incoming.deleted && !cur.deleted) {
        activity.add(SharedActivityEntry(
          id: _uuid.v4(),
          timestamp: ts,
          actor: actor,
          kind: 'expense_deleted',
          data: {'expenseId': incoming.id, 'reason': cur.reason},
        ));
      } else if (!incoming.deleted) {
        if (incoming.amount != cur.amount) {
          activity.add(SharedActivityEntry(
            id: _uuid.v4(),
            timestamp: ts,
            actor: actor,
            kind: 'expense_amount_changed',
            data: {
              'expenseId': incoming.id,
              'before': cur.amount,
              'after': incoming.amount,
            },
          ));
        }
        if (incoming.reason != cur.reason) {
          activity.add(SharedActivityEntry(
            id: _uuid.v4(),
            timestamp: ts,
            actor: actor,
            kind: 'expense_reason_changed',
            data: {
              'expenseId': incoming.id,
              'before': cur.reason,
              'after': incoming.reason,
            },
          ));
        }
        if (incoming.paidBy != cur.paidBy) {
          activity.add(SharedActivityEntry(
            id: _uuid.v4(),
            timestamp: ts,
            actor: actor,
            kind: 'expense_paid_by_changed',
            data: {
              'expenseId': incoming.id,
              'before': cur.paidBy,
              'after': incoming.paidBy,
            },
          ));
        }
        if (!_sameList(incoming.splitAmong, cur.splitAmong)) {
          activity.add(SharedActivityEntry(
            id: _uuid.v4(),
            timestamp: ts,
            actor: actor,
            kind: 'expense_split_changed',
            data: {
              'expenseId': incoming.id,
              'before': cur.splitAmong,
              'after': incoming.splitAmong,
            },
          ));
        }
      }
    }
    final updated = group.copyWith(
      expenses: next,
      activity: activity,
      approvedMemberKeys: {...group.approvedMemberKeys, senderPk},
    );
    await _upsertGroup(updated);
    return true;
  }

  Future<bool> _applyGroupSnapshot(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
  ) async {
    final before = jsonEncode(group.toJson());
    final incomingExpenses = ((decoded['expenses'] as List?) ?? const [])
        .whereType<Map>()
        .map((raw) => SharedExpense.fromJson(Map<String, dynamic>.from(raw)))
        .where((expense) => expense.id.isNotEmpty)
        .toList(growable: false);
    final incomingActivity = ((decoded['activity'] as List?) ?? const [])
        .whereType<Map>()
        .map((raw) =>
            SharedActivityEntry.fromJson(Map<String, dynamic>.from(raw)))
        .where((entry) => entry.id.isNotEmpty)
        .toList(growable: false);
    final incomingMembers = ((decoded['members'] as List?) ?? const [])
        .whereType<Map>()
        .map((raw) =>
            SharedExpenseMember.fromJson(Map<String, dynamic>.from(raw)))
        .where((member) => member.devicePublicKey.isNotEmpty)
        .toList(growable: false);
    final displayNames = _stringMapFromJson(decoded['displayNames']);
    final approvedMemberKeys =
        _stringListFromJson(decoded['approvedMemberKeys']).toSet();
    final groupName = (decoded['groupName'] as String?)?.trim();
    final incomingBackfill = decoded['backfillNewMembers'] is bool
        ? decoded['backfillNewMembers'] as bool
        : null;
    final createdAt = _snapshotDate(decoded['createdAt']);

    final updated = group.copyWith(
      name: groupName == null || groupName.isEmpty ? group.name : groupName,
      createdAt: createdAt ?? group.createdAt,
      status: SharedExpenseGroupStatus.ready,
      backfillNewMembers: incomingBackfill,
      members: incomingMembers.isEmpty
          ? group.members
          : _mergeSnapshotMembers(group.members, incomingMembers),
      approvedMemberKeys: {
        ...group.approvedMemberKeys,
        if (senderPk.isNotEmpty) senderPk,
        ...approvedMemberKeys,
      },
      expenses: _mergeSnapshotExpenses(group.expenses, incomingExpenses),
      activity: _mergeSnapshotActivity(group.activity, incomingActivity),
      displayNames: {
        ...group.displayNames,
        ...displayNames,
      },
    );

    if (jsonEncode(updated.toJson()) == before) return false;
    await _upsertGroup(updated);
    return true;
  }

  Future<bool> _applyNudge(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
  ) async {
    final id = decoded['id'] as String? ?? '';
    if (id.isEmpty || group.activity.any((entry) => entry.id == id)) {
      return false;
    }

    final debtorPks = ((decoded['debtorPks'] as List?) ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final amountByDebtorPk = _doubleMapFromJson(decoded['amountByDebtorPk']);
    final entry = SharedActivityEntry(
      id: id,
      timestamp: (decoded['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      actor: decoded['actor'] as String? ?? senderPk,
      kind: 'nudge_sent',
      data: {
        'amount': (decoded['amount'] as num?)?.toDouble() ?? 0.0,
        'debtorPks': debtorPks,
        'amountByDebtorPk': amountByDebtorPk,
      },
    );

    final updated = group.copyWith(
      activity: [...group.activity, entry],
    );
    await _upsertGroup(updated);
    return true;
  }

  Map<String, double> _doubleMapFromJson(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, double>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is num) {
        result[key] = value.toDouble();
      }
    }
    return result;
  }

  Map<String, String> _stringMapFromJson(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is String && value.trim().isNotEmpty) {
        result[key] = value.trim();
      }
    }
    return result;
  }

  List<String> _stringListFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().where((value) => value.isNotEmpty).toList();
  }

  DateTime? _snapshotDate(Object? raw) {
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  List<SharedExpenseMember> _mergeSnapshotMembers(
    List<SharedExpenseMember> existing,
    List<SharedExpenseMember> incoming,
  ) {
    final byPublicKey = <String, SharedExpenseMember>{
      for (final member in existing)
        if (member.devicePublicKey.isNotEmpty) member.devicePublicKey: member,
    };
    for (final member in incoming) {
      byPublicKey[member.devicePublicKey] = member;
    }
    return byPublicKey.values.toList(growable: false);
  }

  List<SharedExpense> _mergeSnapshotExpenses(
    List<SharedExpense> existing,
    List<SharedExpense> incoming,
  ) {
    if (incoming.isEmpty) return existing;
    final byId = <String, SharedExpense>{
      for (final expense in existing)
        if (expense.id.isNotEmpty) expense.id: expense,
    };
    for (final expense in incoming) {
      final current = byId[expense.id];
      final next = expense.copyWith(status: 'synced');
      if (current == null) {
        byId[expense.id] = next;
        continue;
      }
      final currentTs = current.revisedAt ?? current.timestamp;
      final nextTs = next.revisedAt ?? next.timestamp;
      if (nextTs > currentTs) {
        byId[expense.id] = next;
      }
    }
    final merged = byId.values.toList(growable: false)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return merged;
  }

  List<SharedActivityEntry> _mergeSnapshotActivity(
    List<SharedActivityEntry> existing,
    List<SharedActivityEntry> incoming,
  ) {
    if (incoming.isEmpty) return existing;
    final byId = <String, SharedActivityEntry>{
      for (final entry in existing)
        if (entry.id.isNotEmpty) entry.id: entry,
    };
    for (final entry in incoming) {
      byId.putIfAbsent(entry.id, () => entry);
    }
    final merged = byId.values.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return merged;
  }

  Future<bool> _applyJoinRequest(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
    String myPublicKey,
  ) async {
    // Only existing key-holders should surface approval prompts.
    if (!group.hasGroupKey) return false;
    final pk = decoded['publicKey'] as String? ?? senderPk;
    if (pk.isEmpty || pk == myPublicKey) return false;
    final displayName = (decoded['displayName'] as String?)?.trim();
    final ts = (decoded['timestamp'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;

    // Idempotency: if we already have an identical pending entry for this
    // request, do nothing.
    final existing =
        group.pendingApprovals.where((p) => p.publicKey == pk).toList();
    if (existing.isNotEmpty &&
        existing.first.displayName == displayName &&
        existing.first.requestedAt == ts) {
      return false;
    }

    // A fresh join_request always supersedes any prior approval — when a
    // member leaves and rejoins, their delivery rows are dropped server-side
    // so an old keySharedWith / approvedMemberKeys entry is meaningless.
    // Strip them out and surface the prompt again so the user can re-approve
    // (which sends a fresh key_exchange + group_meta + member_meta).
    final newPending = [
      ...group.pendingApprovals.where((p) => p.publicKey != pk),
      PendingApproval(
        publicKey: pk,
        displayName: displayName,
        requestedAt: ts,
      ),
    ];
    final newDisplayNames = <String, String>{...group.displayNames};
    if (displayName != null && displayName.isNotEmpty) {
      newDisplayNames[pk] = displayName;
    }
    final updated = group.copyWith(
      pendingApprovals: newPending,
      displayNames: newDisplayNames,
      approvedMemberKeys:
          group.approvedMemberKeys.where((k) => k != pk).toSet(),
      keySharedWith: group.keySharedWith.where((k) => k != pk).toSet(),
    );
    await _upsertGroup(updated);
    return true;
  }

  // -------------------------------------------------------------------------
  // Outbound payload emitters
  // -------------------------------------------------------------------------

  Future<void> _emitExpensePayload(
    SharedExpenseGroup group,
    SharedExpense expense,
  ) async {
    final groupKeyHex = await _readGroupKey(group.id);
    if (groupKeyHex == null) {
      throw const TotalsEngineException('No group key — cannot share expense.');
    }
    final payload = {'type': 'expense', ...expense.toJson()};
    final encrypted = await _cryptoService.encryptPayloadWithKey(
      keyBytes: SharedExpenseCryptoService.fromHex(groupKeyHex),
      payload: payload,
    );
    await _engineClient.submitPayload(
      groupId: group.id,
      encryptedBlob: encrypted,
    );
  }

  Future<void> _emitNudgePayload(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
    List<String> recipientPublicKeys,
  ) async {
    final groupKeyHex = await _readGroupKey(group.id);
    if (groupKeyHex == null) {
      throw const TotalsEngineException('No group key — cannot send nudge.');
    }
    final encrypted = await _cryptoService.encryptPayloadWithKey(
      keyBytes: SharedExpenseCryptoService.fromHex(groupKeyHex),
      payload: {
        'type': 'nudge',
        'id': entry.id,
        'timestamp': entry.timestamp,
        'actor': entry.actor,
        'amount': entry.data['amount'],
        'debtorPks': entry.data['debtorPks'],
        'amountByDebtorPk': entry.data['amountByDebtorPk'],
      },
    );
    await _engineClient.submitNudge(
      groupId: group.id,
      encryptedBlob: encrypted,
      recipientPublicKeys: recipientPublicKeys,
    );
  }

  Future<void> _emitGroupSnapshotPayload({
    required SharedExpenseGroup group,
    required String recipientPublicKey,
    required String groupKeyHex,
  }) async {
    final keyBytes = SharedExpenseCryptoService.fromHex(groupKeyHex);
    final snapshotId = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final basePayload = <String, dynamic>{
      'type': 'group_snapshot',
      'snapshotId': snapshotId,
      'timestamp': timestamp,
      'groupId': group.id,
    };

    await _emitGroupSnapshotPart(
      groupId: group.id,
      recipientPublicKey: recipientPublicKey,
      keyBytes: keyBytes,
      payload: {
        ...basePayload,
        'part': 'meta',
        'groupName': group.name,
        'backfillNewMembers': group.backfillNewMembers,
        'createdAt': group.createdAt.millisecondsSinceEpoch,
        'members': group.members.map((member) => member.toJson()).toList(),
        'approvedMemberKeys': group.approvedMemberKeys.toList(),
        'displayNames': group.displayNames,
      },
    );

    final expenseMaps = group.expenses
        .map((expense) => expense.copyWith(status: 'synced').toJson())
        .toList(growable: false);
    for (final chunk in _snapshotMapChunks(
      basePayload: basePayload,
      fieldName: 'expenses',
      values: expenseMaps,
    )) {
      await _emitGroupSnapshotPart(
        groupId: group.id,
        recipientPublicKey: recipientPublicKey,
        keyBytes: keyBytes,
        payload: {
          ...basePayload,
          'part': 'expenses',
          'expenses': chunk,
        },
      );
    }

    final activityMaps =
        group.activity.map((entry) => entry.toJson()).toList(growable: false);
    for (final chunk in _snapshotMapChunks(
      basePayload: basePayload,
      fieldName: 'activity',
      values: activityMaps,
    )) {
      await _emitGroupSnapshotPart(
        groupId: group.id,
        recipientPublicKey: recipientPublicKey,
        keyBytes: keyBytes,
        payload: {
          ...basePayload,
          'part': 'activity',
          'activity': chunk,
        },
      );
    }
  }

  Future<void> _emitGroupSnapshotPart({
    required String groupId,
    required String recipientPublicKey,
    required List<int> keyBytes,
    required Map<String, dynamic> payload,
  }) async {
    final encrypted = await _cryptoService.encryptPayloadWithKey(
      keyBytes: keyBytes,
      payload: payload,
    );
    await _engineClient.submitTargetedPayload(
      groupId: groupId,
      encryptedBlob: encrypted,
      recipientPublicKeys: [recipientPublicKey],
    );
  }

  List<List<Map<String, dynamic>>> _snapshotMapChunks({
    required Map<String, dynamic> basePayload,
    required String fieldName,
    required List<Map<String, dynamic>> values,
  }) {
    final chunks = <List<Map<String, dynamic>>>[];
    var current = <Map<String, dynamic>>[];

    for (final value in values) {
      final candidate = [...current, value];
      final candidatePayload = {
        ...basePayload,
        'part': fieldName,
        fieldName: candidate,
      };
      if (current.isNotEmpty &&
          jsonEncode(candidatePayload).length > _snapshotPlaintextBudget) {
        chunks.add(current);
        current = [value];
      } else {
        current = candidate;
      }
    }

    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  /// Broadcast my display name AND the current group name to all approved
  /// members. Returns true if both submissions succeeded.
  Future<bool> _broadcastMetaPayloads(SharedExpenseGroup group) async {
    final groupKeyHex = await _readGroupKey(group.id);
    if (groupKeyHex == null) return false;
    final keyBytes = SharedExpenseCryptoService.fromHex(groupKeyHex);
    var allOk = true;
    if (group.name.isNotEmpty) {
      try {
        final encrypted = await _cryptoService.encryptPayloadWithKey(
          keyBytes: keyBytes,
          payload: {
            'type': 'group_meta',
            'name': group.name,
            'backfillNewMembers': group.backfillNewMembers,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );
        await _engineClient.submitPayload(
          groupId: group.id,
          encryptedBlob: encrypted,
        );
      } catch (e) {
        _sharedExpenseLog('group_meta send failed: $e');
        allOk = false;
      }
    }
    if (group.myDisplayName.isNotEmpty) {
      try {
        final encrypted = await _cryptoService.encryptPayloadWithKey(
          keyBytes: keyBytes,
          payload: {
            'type': 'member_meta',
            'displayName': group.myDisplayName,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );
        await _engineClient.submitPayload(
          groupId: group.id,
          encryptedBlob: encrypted,
        );
      } catch (e) {
        _sharedExpenseLog('member_meta send failed: $e');
        allOk = false;
      }
    }
    return allOk;
  }

  Future<void> _emitGroupMeta(SharedExpenseGroup group) async {
    final groupKeyHex = await _readGroupKey(group.id);
    if (groupKeyHex == null) return;
    try {
      final encrypted = await _cryptoService.encryptPayloadWithKey(
        keyBytes: SharedExpenseCryptoService.fromHex(groupKeyHex),
        payload: {
          'type': 'group_meta',
          'name': group.name,
          'backfillNewMembers': group.backfillNewMembers,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      await _engineClient.submitPayload(
        groupId: group.id,
        encryptedBlob: encrypted,
      );
    } catch (e) {
      _sharedExpenseLog('_emitGroupMeta failed: $e — flagging for retry');
      final latest = await _groupById(group.id);
      if (latest != null) {
        await _upsertGroup(latest.copyWith(pendingMetaBroadcast: true));
      }
    }
  }

  Future<void> _emitMemberMeta(SharedExpenseGroup group) async {
    final groupKeyHex = await _readGroupKey(group.id);
    if (groupKeyHex == null) return;
    try {
      final encrypted = await _cryptoService.encryptPayloadWithKey(
        keyBytes: SharedExpenseCryptoService.fromHex(groupKeyHex),
        payload: {
          'type': 'member_meta',
          'displayName': group.myDisplayName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      await _engineClient.submitPayload(
        groupId: group.id,
        encryptedBlob: encrypted,
      );
    } catch (e) {
      _sharedExpenseLog('_emitMemberMeta failed: $e — flagging for retry');
      final latest = await _groupById(group.id);
      if (latest != null) {
        await _upsertGroup(latest.copyWith(pendingMetaBroadcast: true));
      }
    }
  }

  Future<void> _broadcastJoinRequest(SharedExpenseGroup group) async {
    final identity = await _cryptoService.getOrCreateIdentity();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      'type': 'join_request',
      'publicKey': identity.publicKeyHex,
      'displayName': group.myDisplayName,
      'timestamp': timestamp,
    };
    for (final member in group.members) {
      if (member.devicePublicKey == identity.publicKeyHex) continue;
      if (member.devicePublicKey.isEmpty) continue;
      try {
        final encrypted = await _cryptoService.encryptGroupKeyPayload(
          recipientPublicKeyHex: member.devicePublicKey,
          payload: payload,
        );
        await _engineClient.submitPayload(
          groupId: group.id,
          encryptedBlob: encrypted,
        );
      } catch (error) {
        _sharedExpenseLog(
          '_broadcastJoinRequest failed recipient=${_logId(member.devicePublicKey)} error=$error',
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  Future<SharedExpenseGroup?> _groupById(String id) async {
    final groups = await getGroups();
    for (final group in groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  Future<void> _upsertGroup(SharedExpenseGroup group) async {
    final groups = await getGroups();
    final next = <SharedExpenseGroup>[];
    var replaced = false;
    for (final existing in groups) {
      if (existing.id == group.id) {
        next.add(group);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) next.add(group);
    next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _saveGroups(next);
    _sharedExpenseLog(
      '_upsertGroup saved group=${_logId(group.id)} status=${group.status.name}',
    );
  }

  Future<void> _saveGroups(List<SharedExpenseGroup> groups) async {
    final db = await _groupsDatabase();
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete(_groupsTable);
      final batch = txn.batch();
      for (final group in groups) {
        batch.insert(
          _groupsTable,
          {
            'id': group.id,
            'payload': jsonEncode(group.toJson()),
            'createdAt': group.createdAt.toIso8601String(),
            'updatedAt': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _groupsKey,
      jsonEncode(groups.map((group) => group.toJson()).toList()),
    );
    _sharedExpenseLog('_saveGroups saved count=${groups.length}');
  }

  Future<String?> _readGroupKey(String groupId) async {
    final key = '$_groupKeyPrefix$groupId';
    try {
      return await _secureStorage.read(key: key);
    } catch (error) {
      _sharedExpenseLog(
        '_readGroupKey decrypt failed group=${_logId(groupId)} error=$error — purging slot',
      );
      try {
        await _secureStorage.delete(key: key);
      } catch (_) {/* ignore */}
      return null;
    }
  }

  Future<void> _writeGroupKey(String groupId, String groupKeyHex) {
    _sharedExpenseLog('_writeGroupKey group=${_logId(groupId)}');
    return _secureStorage.write(
      key: '$_groupKeyPrefix$groupId',
      value: groupKeyHex,
    );
  }
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _MutableDebt {
  final String pk;
  double amount;
  _MutableDebt(this.pk, this.amount);
}

// =============================================================================
// Pure helpers — usable from widgets without a repository instance.
// =============================================================================

/// Deterministic 12-color palette; member colors derive from sorted-pubkey
/// index. Same scheme as the iOS client so the same person gets the same color
/// across devices.
const List<int> kSharedMemberPalette = [
  0xFF6366F1, // indigo
  0xFFEC4899, // pink
  0xFF10B981, // emerald
  0xFFF59E0B, // amber
  0xFF3B82F6, // blue
  0xFFEF4444, // red
  0xFF8B5CF6, // violet
  0xFF14B8A6, // teal
  0xFFF97316, // orange
  0xFF22C55E, // green
  0xFFA855F7, // purple
  0xFF06B6D4, // cyan
];

Map<String, double> computeBalancesFor(SharedExpenseGroup group) {
  final balances = <String, double>{
    for (final m in group.members) m.devicePublicKey: 0.0,
  };
  for (final ex in group.expenses) {
    if (ex.deleted) continue;
    if (ex.amount <= 0) continue;
    if (ex.paidBy.isEmpty || ex.splitAmong.isEmpty) continue;
    balances[ex.paidBy] = (balances[ex.paidBy] ?? 0) + ex.amount;
    final share = ex.amount / ex.splitAmong.length;
    for (final pk in ex.splitAmong) {
      balances[pk] = (balances[pk] ?? 0) - share;
    }
  }
  return balances;
}

SettlementPlan settlementPlanFor(SharedExpenseGroup group) {
  final balances = computeBalancesFor(group);
  final creditors = <_MutableDebt>[];
  final debtors = <_MutableDebt>[];
  balances.forEach((pk, bal) {
    if (bal > 0.005) creditors.add(_MutableDebt(pk, bal));
    if (bal < -0.005) debtors.add(_MutableDebt(pk, -bal));
  });
  creditors.sort((a, b) => b.amount.compareTo(a.amount));
  debtors.sort((a, b) => b.amount.compareTo(a.amount));

  final debts = <SettlementDebt>[];
  while (creditors.isNotEmpty && debtors.isNotEmpty) {
    final c = creditors.first;
    final d = debtors.first;
    final pay = c.amount < d.amount ? c.amount : d.amount;
    debts.add(SettlementDebt(from: d.pk, to: c.pk, amount: pay));
    c.amount -= pay;
    d.amount -= pay;
    if (c.amount < 0.005) creditors.removeAt(0);
    if (d.amount < 0.005) debtors.removeAt(0);
  }
  return SettlementPlan(balances: balances, debts: debts);
}

int memberColorFor(SharedExpenseGroup group, String pubkey) {
  final keys = group.members
      .map((m) => m.devicePublicKey)
      .where((k) => k.isNotEmpty)
      .toList()
    ..sort();
  final idx = keys.indexOf(pubkey);
  if (idx < 0) return kSharedMemberPalette.first;
  return kSharedMemberPalette[idx % kSharedMemberPalette.length];
}
