import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/shared_expense_realtime_bus.dart';
import 'package:totals/services/shared_expense_crypto_service.dart';
import 'package:totals/services/shared_expense_push_notification_service.dart';
import 'package:totals/services/shared_expense_vault_service.dart';
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

enum _PendingPayloadProcessResult {
  changed,
  acknowledged,
  deferred,
}

class SharedExpenseRepository {
  static const _groupsKey = 'shared_expense_groups_v1';
  static const _groupsTable = 'shared_expense_groups';
  static const _groupKeyPrefix = 'shared_expense_group_key_';
  static const _legacyInvitePrefixes = ['totals://join/', 'totals//join/'];
  static const _snapshotPlaintextBudget = 45000;
  static const _maxPendingPullPages = 8;
  static const _fallbackGroupName = 'Shared group';
  static const String fallbackGroupName = _fallbackGroupName;
  static const _fallbackDisplayName = 'Me';

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

  Future<SharedExpenseGroup?> getGroupById(String groupId) {
    return _groupById(groupId);
  }

  Future<List<SharedExpenseGroup>> getGroups() async {
    try {
      final db = await _groupsDatabase();
      final rows = await db.query(
        _groupsTable,
        orderBy: 'createdAt DESC',
      );
      final loaded = rows
          .map(_groupFromDbRow)
          .whereType<SharedExpenseGroup>()
          .where((group) => group.id.isNotEmpty)
          .toList(growable: false);

      // One-shot cleanup: delete any local-only ghost groups left behind by
      // the old createGroup fallback (engine failure → fake localOnly group
      // with a random id that the server never knew about). They can never
      // sync, can never be invited to, and just clutter the list.
      final ghosts = loaded
          .where((g) => g.status == SharedExpenseGroupStatus.localOnly)
          .toList(growable: false);
      for (final ghost in ghosts) {
        _sharedExpenseLog(
          'getGroups pruning ghost localOnly group=${_logId(ghost.id)}',
        );
        await _deleteLocalGroup(ghost.id);
      }
      final groups = ghosts.isEmpty
          ? loaded
          : loaded
              .where(
                  (g) => g.status != SharedExpenseGroupStatus.localOnly)
              .toList(growable: false);

      if (groups.isNotEmpty) {
        final repaired = await _repairCachedGroups(groups);
        _sharedExpenseLog('getGroups loaded ${repaired.length} db groups');
        return repaired;
      }

      final legacyGroups = await _groupsFromLegacyPrefs();
      if (legacyGroups.isNotEmpty) {
        final repaired = await _repairCachedGroups(
          legacyGroups,
          persist: false,
        );
        _sharedExpenseLog(
          'getGroups migrating ${repaired.length} legacy pref groups',
        );
        await _saveGroups(repaired);
        return repaired;
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
    SharedPaymentAddress? paymentAddress,
  }) async {
    final identity = await _cryptoService.getOrCreateIdentity();
    final now = DateTime.now().millisecondsSinceEpoch;
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
        memberMetaUpdatedAt: {identity.publicKeyHex: now},
        paymentAddresses: {
          if (paymentAddress != null && paymentAddress.isValid)
            identity.publicKeyHex: paymentAddress,
        },
        myPaymentAddress: paymentAddress != null && paymentAddress.isValid
            ? paymentAddress
            : null,
        activity: [
          SharedActivityEntry(
            id: _uuid.v4(),
            timestamp: now,
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
      await SharedExpensePushNotificationService.instance.syncRegistration();
      unawaited(SharedExpenseVaultService.instance.syncIfUnlocked());
      return group;
    } catch (error, stackTrace) {
      // No local-only fallback. We used to build a localOnly ghost group
      // here when the engine call failed, but those groups can never sync
      // to the server, never get a Copy invite, never reconcile via
      // refreshGroups — they just clutter the list as orphans. Better to
      // surface the error and let the user retry with connectivity.
      _sharedExpenseLog('createGroup engine failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<SharedExpenseGroup> joinGroup({
    required String inviteOrCode,
    required String displayName,
    SharedPaymentAddress? paymentAddress,
  }) async {
    final groupId = parseInviteCode(inviteOrCode);
    if (groupId == null) {
      _sharedExpenseLog('joinGroup rejected invalid invite/code');
      throw const TotalsEngineException(
          'Enter a valid group code or invite link.');
    }

    _sharedExpenseLog('joinGroup start group=${_logId(groupId)}');
    // Defensive: if a prior leave didn't clean the flag (e.g., app killed
    // mid-leave), wipe it now so the upcoming approval fires its
    // notification.
    final prefs = await SharedPreferences.getInstance();
    final stalePrefsKeys = prefs
        .getKeys()
        .where((k) => k.startsWith('$_approvalNotifiedPrefsPrefix$groupId:'))
        .toList(growable: false);
    for (final k in stalePrefsKeys) {
      await prefs.remove(k);
    }
    await _engineClient.joinGroup(groupId);
    final members = await _engineClient.listMembers(groupId);
    _sharedExpenseLog(
      'joinGroup listed ${members.length} members for group=${_logId(groupId)}',
    );
    final existing = await _groupById(groupId);
    final identity = await _cryptoService.getOrCreateIdentity();
    final now = DateTime.now().millisecondsSinceEpoch;
    final group = SharedExpenseGroup(
      id: groupId,
      name:
          existing == null ? _fallbackGroupName : _bestKnownGroupName(existing),
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
      memberMetaUpdatedAt: {
        ...?existing?.memberMetaUpdatedAt,
        identity.publicKeyHex: now,
      },
      paymentAddresses: {
        ...?existing?.paymentAddresses,
        if (paymentAddress != null && paymentAddress.isValid)
          identity.publicKeyHex: paymentAddress,
      },
      myPaymentAddress: paymentAddress != null && paymentAddress.isValid
          ? paymentAddress
          : existing?.myPaymentAddress,
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
    await SharedExpensePushNotificationService.instance.syncRegistration();
    unawaited(SharedExpenseVaultService.instance.syncIfUnlocked());
    return result;
  }

  Future<void> leaveGroup(SharedExpenseGroup group) async {
    _sharedExpenseLog('leaveGroup start group=${_logId(group.id)}');
    // Pending-approval cancel uses join_cancel (1:1 encrypted because the
    // requester doesn't have the group key yet). Approved members leaving
    // use member_left (group-key encrypted) so peers can render a proper
    // "X left the group" entry instead of just seeing the membership shrink
    // silently on the next refresh. Both are courtesy broadcasts — fire
    // them and the engine unregister off so the user isn't blocked by
    // outbound network on the way out (pending-approval cancel can be
    // O(peers) calls × 12s timeout when the engine is unreachable, which
    // is why the leave spinner used to get stuck for tens of seconds).
    if (group.status == SharedExpenseGroupStatus.pendingApproval) {
      unawaited(_broadcastJoinCancel(group));
    } else if (group.hasGroupKey) {
      unawaited(_broadcastMemberLeft(group));
    }
    unawaited(
      _engineClient.leaveGroup(group.id).catchError((error) {
        _sharedExpenseLog('leaveGroup engine failed: $error');
      }),
    );
    await _deleteLocalGroup(group.id);
    _sharedExpenseLog('leaveGroup done group=${_logId(group.id)}');
    unawaited(SharedExpenseVaultService.instance.syncIfUnlocked());
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
    // Clear all approval-notified flags for this group so that a future
    // rejoin to the same group fires the "you were approved" notification
    // again. Without this, the one-shot flag persists across leave→rejoin
    // cycles and the joiner silently gets no notification on the second
    // (and every subsequent) approval.
    final approvalKeys = prefs
        .getKeys()
        .where((k) => k.startsWith('$_approvalNotifiedPrefsPrefix$groupId:'))
        .toList(growable: false);
    for (final k in approvalKeys) {
      await prefs.remove(k);
    }
  }

  /// Update group metadata and/or my own member display name.
  /// Broadcasts the matching payloads to all approved members.
  Future<SharedExpenseGroup> updateMeta({
    required SharedExpenseGroup group,
    String? name,
    String? myDisplayName,
    bool? backfillNewMembers,
    SharedPaymentAddress? paymentAddress,
  }) async {
    if (name == null &&
        myDisplayName == null &&
        backfillNewMembers == null &&
        paymentAddress == null) {
      return group;
    }

    final identity = await _cryptoService.getOrCreateIdentity();
    final currentPaymentAddress =
        _bestKnownPaymentAddress(group, identity.publicKeyHex);
    final nextPaymentAddress = paymentAddress != null && paymentAddress.isValid
        ? paymentAddress
        : null;
    final nameChanged = name != null && name.trim() != group.name;
    final displayChanged =
        myDisplayName != null && myDisplayName.trim() != group.myDisplayName;
    final backfillChanged = backfillNewMembers != null &&
        backfillNewMembers != group.backfillNewMembers;
    final paymentChanged = nextPaymentAddress != null &&
        nextPaymentAddress != currentPaymentAddress;
    if (!nameChanged &&
        !displayChanged &&
        !backfillChanged &&
        !paymentChanged) {
      return group;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final memberMetaChanged = displayChanged || paymentChanged;
    final metadataChanged =
        nameChanged || displayChanged || backfillChanged || paymentChanged;
    var saved = group.copyWith(
      name: nameChanged ? name.trim() : null,
      myDisplayName: displayChanged ? myDisplayName.trim() : null,
      backfillNewMembers: backfillChanged ? backfillNewMembers : null,
      myPaymentAddress: paymentChanged ? nextPaymentAddress : null,
      pendingMetaBroadcast: metadataChanged ? true : null,
      displayNames: displayChanged
          ? {
              ...group.displayNames,
              identity.publicKeyHex: myDisplayName.trim(),
            }
          : null,
      memberMetaUpdatedAt: memberMetaChanged
          ? {
              ...group.memberMetaUpdatedAt,
              identity.publicKeyHex: now,
            }
          : null,
      paymentAddresses: paymentChanged
          ? {
              ...group.paymentAddresses,
              identity.publicKeyHex: nextPaymentAddress,
            }
          : null,
      activity: nameChanged
          ? [
              ...group.activity,
              SharedActivityEntry(
                id: _uuid.v4(),
                timestamp: now,
                actor: identity.publicKeyHex,
                kind: 'group_renamed',
                data: {'before': group.name, 'after': name.trim()},
              ),
            ]
          : null,
    );

    await _upsertGroup(saved);

    if (metadataChanged && saved.hasGroupKey) {
      final sent = await _broadcastMetaPayloads(saved);
      if (sent) {
        final latest = await _groupById(group.id);
        if (latest != null) {
          saved = latest.copyWith(pendingMetaBroadcast: false);
          await _upsertGroup(saved);
        }
      }
    }
    return saved;
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
    final groupName = _bestKnownGroupName(group);
    final approverDisplayName =
        _bestKnownDisplayName(group, identity.publicKeyHex);
    final approverPaymentAddress =
        _bestKnownPaymentAddress(group, identity.publicKeyHex);
    final approverMetaUpdatedAt =
        _bestKnownMemberMetaUpdatedAt(group, identity.publicKeyHex);
    final approvalEventId = _uuid.v4();

    // Send the group key encrypted with a 1:1 shared secret.
    final encryptedBlob = await _cryptoService.encryptGroupKeyPayload(
      recipientPublicKeyHex: member.devicePublicKey,
      payload: {
        'type': 'key_exchange',
        'groupId': group.id,
        if (!_isFallbackGroupName(groupName)) 'groupName': groupName,
        'groupKey': groupKeyHex,
        'approvedPublicKey': member.devicePublicKey,
        'approvedBy': identity.publicKeyHex,
        if (!_isFallbackDisplayName(approverDisplayName))
          'approverDisplayName': approverDisplayName,
        if (approverPaymentAddress != null && approverPaymentAddress.isValid)
          'approverPaymentAddress': approverPaymentAddress.toJson(),
        if (approverMetaUpdatedAt > 0)
          'approverMemberMetaUpdatedAt': approverMetaUpdatedAt,
        'backfillNewMembers': group.backfillNewMembers,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
    // The notification preview is composed locally on the recipient after they
    // pull and decrypt the payload (doorbell model — see
    // shared_expense_push_notification_service.dart).
    await _engineClient.submitTargetedPayload(
      groupId: group.id,
      encryptedBlob: encryptedBlob,
      recipientPublicKeys: [member.devicePublicKey],
      kind: 'key_exchange',
    );

    final approvedAt = DateTime.now().millisecondsSinceEpoch;
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
          id: approvalEventId,
          timestamp: approvedAt,
          actor: identity.publicKeyHex,
          kind: 'member_approved',
          data: {'memberPk': member.devicePublicKey},
        ),
      ],
    );
    await _emitGroupSnapshotPayload(
      group: updated,
      recipientPublicKey: member.devicePublicKey,
      groupKeyHex: groupKeyHex,
      includeHistory: updated.backfillNewMembers,
    );
    unawaited(_broadcastMemberApproved(
      group: updated,
      approverPublicKey: identity.publicKeyHex,
      approvedPublicKey: member.devicePublicKey,
      groupKeyHex: groupKeyHex,
      approvedAt: approvedAt,
      activityId: approvalEventId,
    ));
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
    // Drop both the pending entry AND the stub member that _applyJoinRequest
    // inserted; otherwise the requester stays as a ghost in `members`.
    final updated = group.copyWith(
      pendingApprovals: group.pendingApprovals
          .where((p) => p.publicKey != publicKey)
          .toList(),
      members:
          group.members.where((m) => m.devicePublicKey != publicKey).toList(),
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
      _sharedExpenseLog(
        'refreshGroups marked inaccessible local group missing from server list '
        'group=${_logId(local.id)}',
      );
      await _upsertGroup(
        local.copyWith(
          status: SharedExpenseGroupStatus.pendingApproval,
          members: const <SharedExpenseMember>[],
          approvedMemberKeys: const <String>{},
          pendingApprovals: const <PendingApproval>[],
          keySharedWith: const <String>{},
        ),
      );
    }

    for (final serverGroup in serverGroups) {
      final cachedLocal = localById[serverGroup.id];
      if (cachedLocal == null) {
        _sharedExpenseLog(
          'refreshGroups skipped unknown server group=${_logId(serverGroup.id)}',
        );
        continue;
      }
      // A refresh can overlap with an Edit Group save. Re-read the latest
      // local record before writing the merged server view so stale refreshes
      // cannot restore older member metadata.
      final local = await _groupById(serverGroup.id) ?? cachedLocal;
      final hasKey = await _readGroupKey(serverGroup.id) != null;
      final isReady = hasKey || local.status == SharedExpenseGroupStatus.ready;

      // Build a set of pubkeys the server currently lists. If a member has
      // left, drop them from approvedMemberKeys / keySharedWith / pending
      // so the next time they rejoin, the approval flow starts clean instead
      // of skipping straight to "they have the key".
      final currentMemberKeys = serverGroup.members
          .map((m) => m.devicePublicKey)
          .where((k) => k.isNotEmpty)
          .toSet();

      final approvedKeys = <String>{
        ...local.approvedMemberKeys.where(
            (k) => k == identity.publicKeyHex || currentMemberKeys.contains(k)),
        if (isReady) identity.publicKeyHex,
      };
      final sharedWith = <String>{
        ...local.keySharedWith.where((k) => currentMemberKeys.contains(k)),
      };
      final pruned = local.pendingApprovals
          .where((p) => currentMemberKeys.contains(p.publicKey))
          .toList();
      final myDisplayName = _bestKnownDisplayName(local, identity.publicKeyHex);
      final myMetaUpdatedAt =
          _bestKnownMemberMetaUpdatedAt(local, identity.publicKeyHex);
      final displayNames =
          myDisplayName.trim().isEmpty || _isFallbackDisplayName(myDisplayName)
              ? local.displayNames
              : _mergeDisplayNames(
                  local.displayNames,
                  {identity.publicKeyHex: myDisplayName},
                  protectedPublicKey: identity.publicKeyHex,
                  existingMetaUpdatedAt: local.memberMetaUpdatedAt,
                  incomingMetaUpdatedAt: myMetaUpdatedAt > 0
                      ? {identity.publicKeyHex: myMetaUpdatedAt}
                      : const {},
                );
      final myPaymentAddress =
          _bestKnownPaymentAddress(local, identity.publicKeyHex);
      final paymentAddresses =
          myPaymentAddress == null || !myPaymentAddress.isValid
              ? local.paymentAddresses
              : _mergePaymentAddresses(
                  local.paymentAddresses,
                  {identity.publicKeyHex: myPaymentAddress},
                  existingMetaUpdatedAt: local.memberMetaUpdatedAt,
                  incomingMetaUpdatedAt: myMetaUpdatedAt > 0
                      ? {identity.publicKeyHex: myMetaUpdatedAt}
                      : const {},
                );
      final memberMetaUpdatedAt = myMetaUpdatedAt > 0
          ? {
              ...local.memberMetaUpdatedAt,
              identity.publicKeyHex: myMetaUpdatedAt,
            }
          : local.memberMetaUpdatedAt;

      final merged = SharedExpenseGroup(
        id: serverGroup.id,
        name: _bestKnownGroupName(local),
        myDisplayName: myDisplayName,
        createdAt: serverGroup.createdAt,
        expiresAt: serverGroup.expiresAt,
        status: isReady
            ? SharedExpenseGroupStatus.ready
            : SharedExpenseGroupStatus.pendingApproval,
        members: serverGroup.members,
        approvedMemberKeys: approvedKeys,
        expenses: local.expenses,
        activity: local.activity,
        displayNames: displayNames,
        paymentAddresses: paymentAddresses,
        memberMetaUpdatedAt: memberMetaUpdatedAt,
        myPaymentAddress: myPaymentAddress,
        pendingApprovals: pruned,
        backfillNewMembers: local.backfillNewMembers,
        keySharedWith: sharedWith,
        lastSyncAt: local.lastSyncAt,
        pendingMetaBroadcast: local.pendingMetaBroadcast,
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

  String _bestKnownGroupName(SharedExpenseGroup group) {
    final current = group.name.trim();
    if (current.isNotEmpty && !_isFallbackGroupName(current)) return current;

    final activity = [...group.activity]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    for (final entry in activity) {
      if (entry.kind == 'group_renamed') {
        final after = entry.data['after'];
        if (after is String && after.trim().isNotEmpty) {
          return after.trim();
        }
      }
    }
    for (final entry in activity) {
      if (entry.kind == 'group_created') {
        final name = entry.data['name'];
        if (name is String && name.trim().isNotEmpty) {
          return name.trim();
        }
      }
    }
    return group.name;
  }

  String _bestKnownDisplayName(SharedExpenseGroup group, String myPublicKey) {
    final current = group.myDisplayName.trim();
    if (current.isNotEmpty && !_isFallbackDisplayName(current)) {
      return current;
    }

    final fromDisplayNames = group.displayNames[myPublicKey]?.trim();
    if (fromDisplayNames != null &&
        fromDisplayNames.isNotEmpty &&
        !_isFallbackDisplayName(fromDisplayNames)) {
      return fromDisplayNames;
    }

    final activity = [...group.activity]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    for (final entry in activity) {
      if (entry.actor != myPublicKey) continue;
      if (entry.kind != 'member_joined') continue;
      final displayName = entry.data['displayName'];
      if (displayName is String &&
          displayName.trim().isNotEmpty &&
          !_isFallbackDisplayName(displayName)) {
        return displayName.trim();
      }
    }

    if (fromDisplayNames != null && fromDisplayNames.isNotEmpty) {
      return fromDisplayNames;
    }
    return group.myDisplayName;
  }

  int _bestKnownMemberMetaUpdatedAt(
    SharedExpenseGroup group,
    String publicKey,
  ) {
    final direct = group.memberMetaUpdatedAt[publicKey];
    if (direct != null && direct > 0) return direct;
    if (publicKey.isEmpty) return 0;
    final hasDisplayName =
        group.displayNames[publicKey]?.trim().isNotEmpty == true;
    final hasPaymentAddress =
        group.paymentAddresses[publicKey]?.isValid == true;
    if (!hasDisplayName && !hasPaymentAddress) return 0;
    return group.createdAt.millisecondsSinceEpoch;
  }

  SharedPaymentAddress? _bestKnownPaymentAddress(
    SharedExpenseGroup group,
    String myPublicKey,
  ) {
    final local = group.myPaymentAddress;
    if (local != null && local.isValid) return local;

    final fromMap = group.paymentAddresses[myPublicKey];
    if (fromMap != null && fromMap.isValid) return fromMap;

    return null;
  }

  Future<List<SharedExpenseGroup>> _repairCachedGroups(
    List<SharedExpenseGroup> groups, {
    bool persist = true,
  }) async {
    if (groups.isEmpty) return groups;

    String? myPublicKey;
    try {
      final identity = await _cryptoService.getOrCreateIdentity();
      myPublicKey = identity.publicKeyHex;
    } catch (error) {
      _sharedExpenseLog('getGroups skipped display-name repair: $error');
    }
    var changed = false;
    final repaired = <SharedExpenseGroup>[];
    for (final group in groups) {
      final name = _bestKnownGroupName(group);
      final myDisplayName = myPublicKey == null
          ? group.myDisplayName
          : _bestKnownDisplayName(group, myPublicKey);
      var displayNames = group.displayNames;
      var paymentAddresses = group.paymentAddresses;
      if (myPublicKey != null &&
          myDisplayName.trim().isNotEmpty &&
          !_isFallbackDisplayName(myDisplayName)) {
        displayNames = _mergeDisplayNames(
          group.displayNames,
          {myPublicKey: myDisplayName},
          protectedPublicKey: myPublicKey,
        );
      }
      final myPaymentAddress = myPublicKey == null
          ? group.myPaymentAddress
          : _bestKnownPaymentAddress(group, myPublicKey);
      if (myPublicKey != null &&
          myPaymentAddress != null &&
          myPaymentAddress.isValid) {
        paymentAddresses = _mergePaymentAddresses(
          group.paymentAddresses,
          {myPublicKey: myPaymentAddress},
        );
      }

      final next = group.copyWith(
        name: name,
        myDisplayName: myDisplayName,
        displayNames: displayNames,
        paymentAddresses: paymentAddresses,
        myPaymentAddress: myPaymentAddress,
      );
      if (jsonEncode(next.toJson()) != jsonEncode(group.toJson())) {
        changed = true;
      }
      repaired.add(next);
    }

    if (changed && persist) {
      await _saveGroups(repaired);
      _sharedExpenseLog('getGroups repaired cached group metadata');
    }
    return changed ? repaired : groups;
  }

  String? _trustedIncomingGroupName(
    SharedExpenseGroup group,
    Object? rawName,
  ) {
    if (rawName is! String) return null;
    final incoming = rawName.trim();
    if (incoming.isEmpty) return null;

    final current = _bestKnownGroupName(group);
    if (_isFallbackGroupName(incoming) &&
        current.trim().isNotEmpty &&
        !_isFallbackGroupName(current)) {
      return null;
    }
    return incoming;
  }

  String? _trustedIncomingDisplayName({
    required String? current,
    required Object? rawName,
    bool protectFallback = false,
  }) {
    if (rawName is! String) return null;
    final incoming = rawName.trim();
    if (incoming.isEmpty) return null;

    final currentName = current?.trim() ?? '';
    if (_isFallbackDisplayName(incoming)) {
      if (protectFallback) return null;
      if (currentName.isNotEmpty && !_isFallbackDisplayName(currentName)) {
        return null;
      }
    }
    return incoming;
  }

  Map<String, String> _mergeDisplayNames(
    Map<String, String> existing,
    Map<String, String> incoming, {
    String? protectedPublicKey,
    Map<String, int> existingMetaUpdatedAt = const {},
    Map<String, int> incomingMetaUpdatedAt = const {},
    bool allowLegacyOverwrite = true,
  }) {
    final merged = <String, String>{...existing};
    for (final entry in incoming.entries) {
      final currentName = merged[entry.key]?.trim() ?? '';
      final hasCurrentName =
          currentName.isNotEmpty && !_isFallbackDisplayName(currentName);
      final currentUpdatedAt = existingMetaUpdatedAt[entry.key] ?? 0;
      final incomingUpdatedAt = incomingMetaUpdatedAt[entry.key] ?? 0;
      if (incomingUpdatedAt > 0 && incomingUpdatedAt < currentUpdatedAt) {
        continue;
      }
      if (incomingUpdatedAt <= 0 && !allowLegacyOverwrite && hasCurrentName) {
        continue;
      }
      final displayName = _trustedIncomingDisplayName(
        current: merged[entry.key],
        rawName: entry.value,
        protectFallback: entry.key == protectedPublicKey,
      );
      if (displayName != null) {
        merged[entry.key] = displayName;
      }
    }
    return merged;
  }

  SharedPaymentAddress? _trustedIncomingPaymentAddress(Object? rawAddress) {
    if (rawAddress is! Map) return null;
    final address = SharedPaymentAddress.fromJson(
      Map<String, dynamic>.from(rawAddress),
    );
    return address.isValid ? address : null;
  }

  Map<String, SharedPaymentAddress> _mergePaymentAddresses(
    Map<String, SharedPaymentAddress> existing,
    Map<String, SharedPaymentAddress> incoming, {
    Map<String, int> existingMetaUpdatedAt = const {},
    Map<String, int> incomingMetaUpdatedAt = const {},
    bool allowLegacyOverwrite = true,
  }) {
    final merged = <String, SharedPaymentAddress>{...existing};
    for (final entry in incoming.entries) {
      if (entry.key.isEmpty || !entry.value.isValid) continue;
      final hasCurrentAddress = merged[entry.key]?.isValid == true;
      final currentUpdatedAt = existingMetaUpdatedAt[entry.key] ?? 0;
      final incomingUpdatedAt = incomingMetaUpdatedAt[entry.key] ?? 0;
      if (incomingUpdatedAt > 0 && incomingUpdatedAt < currentUpdatedAt) {
        continue;
      }
      if (incomingUpdatedAt <= 0 &&
          !allowLegacyOverwrite &&
          hasCurrentAddress) {
        continue;
      }
      merged[entry.key] = entry.value;
    }
    return merged;
  }

  Map<String, SharedPaymentAddress> _paymentAddressMapFromJson(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, SharedPaymentAddress>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final address = _trustedIncomingPaymentAddress(entry.value);
      if (key is String && key.isNotEmpty && address != null) {
        result[key] = address;
      }
    }
    return result;
  }

  Map<String, int> _memberMetaUpdatedAtMapFromJson(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, int>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && key.isNotEmpty && value is num) {
        final timestamp = value.toInt();
        if (timestamp > 0) result[key] = timestamp;
      }
    }
    return result;
  }

  Map<String, int> _mergeMemberMetaUpdatedAt(
    Map<String, int> existing,
    Map<String, int> incoming,
  ) {
    final merged = <String, int>{...existing};
    for (final entry in incoming.entries) {
      final current = merged[entry.key] ?? 0;
      if (entry.key.isNotEmpty && entry.value > current) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  int _incomingMemberMetaUpdatedAt(Map<String, dynamic> decoded) {
    final explicit = decoded['memberMetaUpdatedAt'];
    if (explicit is num) return explicit.toInt();
    final fallback = decoded['timestamp'];
    if (fallback is num) return fallback.toInt();
    return 0;
  }

  bool _shouldApplyIncomingMemberMeta({
    required int incomingUpdatedAt,
    required int currentUpdatedAt,
    required bool hasCurrentValue,
  }) {
    if (incomingUpdatedAt > 0) return incomingUpdatedAt >= currentUpdatedAt;
    if (currentUpdatedAt > 0) return false;
    return !hasCurrentValue;
  }

  Map<String, dynamic> _outboundPaymentAddresses(
    SharedExpenseGroup group,
    String myPublicKey,
  ) {
    final addresses = <String, dynamic>{};
    for (final entry in group.paymentAddresses.entries) {
      if (!entry.value.isValid) continue;
      addresses[entry.key] = entry.value.toJson();
    }

    final myPaymentAddress = _bestKnownPaymentAddress(group, myPublicKey);
    if (myPaymentAddress != null && myPaymentAddress.isValid) {
      addresses[myPublicKey] = myPaymentAddress.toJson();
    }
    return addresses;
  }

  Map<String, String> _outboundDisplayNames(
    SharedExpenseGroup group,
    String myPublicKey,
  ) {
    final names = <String, String>{};
    for (final entry in group.displayNames.entries) {
      final displayName = entry.value.trim();
      if (displayName.isEmpty || _isFallbackDisplayName(displayName)) {
        continue;
      }
      names[entry.key] = displayName;
    }

    final myDisplayName = _bestKnownDisplayName(group, myPublicKey).trim();
    if (myDisplayName.isNotEmpty && !_isFallbackDisplayName(myDisplayName)) {
      names[myPublicKey] = myDisplayName;
    }
    return names;
  }

  Map<String, int> _outboundMemberMetaUpdatedAt(
    SharedExpenseGroup group,
    String myPublicKey,
  ) {
    final timestamps = <String, int>{...group.memberMetaUpdatedAt};
    final myUpdatedAt = _bestKnownMemberMetaUpdatedAt(group, myPublicKey);
    if (myUpdatedAt > 0) timestamps[myPublicKey] = myUpdatedAt;
    return timestamps;
  }

  bool _isFallbackGroupName(String value) => value.trim() == _fallbackGroupName;

  bool _isFallbackDisplayName(String value) =>
      value.trim() == _fallbackDisplayName;

  /// Pull and apply all pending payloads for one group. Returns true if any
  /// state changed locally.
  Future<bool> syncGroup(String groupId) async {
    final group = await _groupById(groupId);
    if (group == null) {
      _sharedExpenseLog('syncGroup unknown group=${_logId(groupId)}');
      return false;
    }
    _sharedExpenseLog('syncGroup start group=${_logId(groupId)}');
    var changed = false;
    final identity = await _cryptoService.getOrCreateIdentity();

    for (var page = 0; page < _maxPendingPullPages; page++) {
      final payloads = await _engineClient.pullPending(groupId);
      _sharedExpenseLog(
        'syncGroup page=${page + 1} payloads=${payloads.length} '
        'group=${_logId(groupId)}',
      );
      if (payloads.isEmpty) break;

      var completedAny = false;
      final acknowledgePayloadIds = <String>[];
      for (final payload in payloads) {
        final result = await _processPendingPayload(
          groupId: groupId,
          myPublicKey: identity.publicKeyHex,
          payload: payload,
          acknowledge: false,
        );
        if (result == _PendingPayloadProcessResult.changed) {
          changed = true;
          completedAny = true;
          acknowledgePayloadIds.add(payload.id);
        } else if (result == _PendingPayloadProcessResult.acknowledged) {
          completedAny = true;
          acknowledgePayloadIds.add(payload.id);
        }
      }
      await _acknowledgePayloads(acknowledgePayloadIds);

      if (!completedAny) {
        _sharedExpenseLog(
          'syncGroup deferred visible payloads group=${_logId(groupId)}',
        );
        break;
      }
    }

    // Stamp lastSyncAt + retry any pending outbound work.
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
      final retriedPendingExpenses = await _retryPendingExpensePayloads(after);
      if (retriedPendingExpenses) changed = true;
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

  Future<bool> _retryPendingExpensePayloads(SharedExpenseGroup group) async {
    if (!group.hasGroupKey) return false;

    final pendingIds = group.expenses
        .where((expense) => expense.status == 'pending')
        .map((expense) => expense.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (pendingIds.isEmpty) return false;

    var changed = false;
    for (final expenseId in pendingIds) {
      final latest = await _groupById(group.id);
      if (latest == null || !latest.hasGroupKey) return changed;

      SharedExpense? current;
      for (final expense in latest.expenses) {
        if (expense.id == expenseId) {
          current = expense;
          break;
        }
      }
      if (current == null || current.status != 'pending') continue;

      try {
        final activityEntries =
            _activityEntriesForExpensePayload(latest, current);
        await _emitExpensePayload(
          latest,
          current,
          previewEntry: activityEntries.isEmpty ? null : activityEntries.last,
          activityEntries: activityEntries,
        );
        final afterSend = await _groupById(group.id);
        if (afterSend == null) return changed;
        final sentVersion = current.revisedAt ?? current.timestamp;
        final nextExpenses = afterSend.expenses.map((expense) {
          if (expense.id != expenseId || expense.status != 'pending') {
            return expense;
          }
          final currentVersion = expense.revisedAt ?? expense.timestamp;
          if (currentVersion != sentVersion) return expense;
          return expense.copyWith(status: 'synced');
        }).toList(growable: false);
        await _upsertGroup(afterSend.copyWith(expenses: nextExpenses));
        changed = true;
        _sharedExpenseLog(
          'retryPendingExpensePayloads sent expense=${_logId(expenseId)} '
          'group=${_logId(group.id)}',
        );
      } catch (error) {
        _sharedExpenseLog(
          'retryPendingExpensePayloads failed expense=${_logId(expenseId)} '
          'group=${_logId(group.id)}: $error',
        );
      }
    }
    return changed;
  }

  /// Legacy alias for callers that still expect the old name.
  Future<bool> processPendingApprovals(String groupId) => syncGroup(groupId);

  Stream<SharedExpenseGroup> watchGroupRealtime(String groupId) async* {
    final identity = await _cryptoService.getOrCreateIdentity();
    _sharedExpenseLog('watchGroupRealtime start group=${_logId(groupId)}');

    await for (final payload in _engineClient.streamPending(groupId)) {
      final result = await _processPendingPayload(
        groupId: groupId,
        myPublicKey: identity.publicKeyHex,
        payload: payload,
      );
      final latest = await _stampRealtimeSync(groupId);
      if (result == _PendingPayloadProcessResult.changed && latest != null) {
        SharedExpenseRealtimeBus.instance.publish(latest);
        yield latest;
      }
    }
  }

  Stream<SharedExpenseGroup> watchAllGroupsRealtime() async* {
    final identity = await _cryptoService.getOrCreateIdentity();
    _sharedExpenseLog('watchAllGroupsRealtime start');

    await for (final payload in _engineClient.streamAllPending()) {
      final result = await _processPendingPayload(
        groupId: payload.groupId,
        myPublicKey: identity.publicKeyHex,
        payload: payload,
      );
      final latest = await _stampRealtimeSync(payload.groupId);
      if (result == _PendingPayloadProcessResult.changed && latest != null) {
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
      throw Exception(
          'This transaction is already linked to a shared expense.');
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
      await _emitExpensePayload(
        updated,
        expense,
        previewEntry: activityEntry,
        activityEntries: [activityEntry],
      );
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
      throw Exception(
          'This transaction is already linked to a shared expense.');
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
      final previewEntries = activity.sublist(group.activity.length);
      await _emitExpensePayload(
        updated,
        after,
        previewEntry: previewEntries.isEmpty ? null : previewEntries.last,
        activityEntries: previewEntries,
      );
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
    final activityEntry = SharedActivityEntry(
      id: _uuid.v4(),
      timestamp: ts,
      actor: identity.publicKeyHex,
      kind: 'expense_deleted',
      data: {'expenseId': expenseId, 'reason': existing.reason},
    );
    var updated = group.copyWith(
      expenses:
          group.expenses.map((e) => e.id == expenseId ? deleted : e).toList(),
      activity: [...group.activity, activityEntry],
    );
    await _upsertGroup(updated);

    try {
      await _emitExpensePayload(
        updated,
        deleted,
        previewEntry: activityEntry,
        activityEntries: [activityEntry],
      );
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
    for (final debt in originalDebtPlanFor(group).debts) {
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

  /// Applies one payload if possible. A deferred payload is left unacked so it
  /// can be retried after key/identity state recovers.
  Future<_PendingPayloadProcessResult> _processPendingPayload({
    required String groupId,
    required String myPublicKey,
    required EnginePendingPayload payload,
    bool acknowledge = true,
  }) async {
    if (!_processingPayloadIds.add(payload.id)) {
      _sharedExpenseLog(
        '_processPendingPayload already processing payload=${_logId(payload.id)}',
      );
      return _PendingPayloadProcessResult.deferred;
    }

    try {
      // Re-read the group key on every payload. If a key_exchange establishes
      // the key, later payloads in the same sync/stream can decrypt immediately.
      final groupKeyHex = await _readGroupKey(groupId);
      final groupKeyBytes = groupKeyHex == null
          ? null
          : SharedExpenseCryptoService.fromHex(groupKeyHex);

      Map<String, dynamic>? decoded;
      var decodedViaGroupKey = false;
      if (groupKeyBytes != null) {
        decoded = await _cryptoService.decryptPayloadWithKey(
          keyBytes: groupKeyBytes,
          encryptedBlob: payload.encryptedBlob,
        );
        if (decoded != null) decodedViaGroupKey = true;
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
        }
        return _PendingPayloadProcessResult.deferred;
      }

      final type = decoded['type'] as String?;
      if (!_isKnownPayloadType(type)) {
        _sharedExpenseLog(
          '_processPendingPayload deferring unknown type=$type '
          'payload=${_logId(payload.id)}',
        );
        return _PendingPayloadProcessResult.deferred;
      }
      _sharedExpenseLog(
        '_processPendingPayload applying type=$type '
        'sender=${_logId(payload.senderPublicKey)}',
      );
      final applied = await _applyPayload(
        groupId: groupId,
        senderPk: payload.senderPublicKey,
        decoded: decoded,
        myPublicKey: myPublicKey,
        decodedViaGroupKey: decodedViaGroupKey,
      );
      if (acknowledge) {
        await _acknowledgePayload(payload.id);
      }
      return applied
          ? _PendingPayloadProcessResult.changed
          : _PendingPayloadProcessResult.acknowledged;
    } finally {
      _processingPayloadIds.remove(payload.id);
    }
  }

  bool _isKnownPayloadType(String? type) {
    switch (type) {
      case 'group_key':
      case 'key_exchange':
      case 'group_meta':
      case 'member_meta':
      case 'expense':
      case 'join_request':
      case 'join_cancel':
      case 'member_left':
      case 'member_approved':
      case 'nudge':
      case 'group_snapshot':
      case 'snapshot_request':
        return true;
      default:
        return false;
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

  Future<void> _acknowledgePayloads(List<String> payloadIds) async {
    final ids = payloadIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;
    if (ids.length == 1) {
      await _acknowledgePayload(ids.single);
      return;
    }
    try {
      await _engineClient.acknowledgePayloads(ids);
    } on TotalsEngineException catch (error) {
      if (error.statusCode == 404) {
        for (final id in ids) {
          await _acknowledgePayload(id);
        }
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
    bool decodedViaGroupKey = false,
  }) async {
    final type = decoded['type'] as String?;
    var group = await _groupById(groupId);
    if (group == null) return false;

    // Frontend-driven approval check. If the sender is currently in our
    // pendingApprovals but the payload was decryptable with the group key,
    // they must have been approved by someone — the group key only leaves
    // an approver's device via an explicit key_exchange in approveMember.
    // Auto-promote them locally so the Approve button clears even when the
    // explicit member_approved broadcast was missed (engine routing,
    // dropped SSE frame, app backgrounded during delivery, …).
    final pendingPksBefore =
        group.pendingApprovals.map((p) => p.publicKey).toSet();
    if (decodedViaGroupKey &&
        senderPk.isNotEmpty &&
        pendingPksBefore.contains(senderPk)) {
      group = await _autoPromotePendingMember(group, senderPk);
    }

    // If the sender is currently in our pendingApprovals list, the only
    // payload types they can drive through us are join_request (to re-state
    // their request), join_cancel (to withdraw it), and member_left (to
    // leave the group). Everything else — member_meta, group_meta,
    // group_snapshot, expense, nudge, key_exchange — gets dropped. Without
    // this gate the joiner could accidentally auto-clear their own pending
    // state on the approver's side by, for example, applying a stale
    // key_exchange in the background and then emitting a member_meta that
    // the approver's _applyMemberMeta would treat as "this person is now an
    // approved member" and add them to approvedMemberKeys, silently making
    // the pending-approval card vanish without the approver ever tapping
    // Approve.
    final pendingPks =
        group.pendingApprovals.map((p) => p.publicKey).toSet();
    const allowedFromPending = {
      'join_request',
      'join_cancel',
      'member_left',
    };
    if (senderPk.isNotEmpty &&
        pendingPks.contains(senderPk) &&
        !allowedFromPending.contains(type)) {
      _sharedExpenseLog(
        '_applyPayload dropped type=$type from pending member '
        'sender=${_logId(senderPk)} group=${_logId(groupId)}',
      );
      return false;
    }

    switch (type) {
      // Legacy alias kept so devices still on `group_key` can be approved.
      case 'group_key':
      case 'key_exchange':
        return _applyKeyExchange(group, senderPk, decoded, myPublicKey);

      case 'group_meta':
        return _applyGroupMeta(group, senderPk, decoded);

      case 'member_meta':
        return _applyMemberMeta(group, senderPk, decoded, myPublicKey);

      case 'expense':
        return _applyExpense(group, senderPk, decoded);

      case 'join_request':
        return _applyJoinRequest(group, senderPk, decoded, myPublicKey);

      case 'join_cancel':
        return _applyJoinCancel(group, senderPk, decoded, myPublicKey);

      case 'member_left':
        return _applyMemberLeft(group, senderPk, decoded, myPublicKey);

      case 'member_approved':
        return _applyMemberApproved(group, senderPk, decoded, myPublicKey);

      case 'snapshot_request':
        return _applySnapshotRequest(group, senderPk, decoded);

      case 'nudge':
        return _applyNudge(group, senderPk, decoded);

      case 'group_snapshot':
        return _applyGroupSnapshot(group, senderPk, decoded, myPublicKey);

      default:
        _sharedExpenseLog('_applyPayload unknown type=$type');
        return false;
    }
  }

  Future<bool> _applyKeyExchange(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
    String myPublicKey,
  ) async {
    final groupKeyHex = decoded['groupKey'] as String?;
    if (groupKeyHex == null || groupKeyHex.length != 64) return false;
    await _writeGroupKey(group.id, groupKeyHex);
    final approvedBy = decoded['approvedBy'] as String?;
    final approvedPk = decoded['approvedPublicKey'] as String?;
    final approverName = _trustedIncomingDisplayName(
      current: approvedBy == null ? null : group.displayNames[approvedBy],
      rawName: decoded['approverDisplayName'],
    );
    final groupName = _trustedIncomingGroupName(group, decoded['groupName']);
    final backfillNewMembers = decoded['backfillNewMembers'] is bool
        ? decoded['backfillNewMembers'] as bool
        : null;
    final newDisplayNames = <String, String>{...group.displayNames};
    final approverMetaUpdatedAt =
        (decoded['approverMemberMetaUpdatedAt'] as num?)?.toInt() ?? 0;
    final currentApproverMetaUpdatedAt =
        approvedBy == null ? 0 : group.memberMetaUpdatedAt[approvedBy] ?? 0;
    final canApplyApproverMeta = approverMetaUpdatedAt > 0
        ? approverMetaUpdatedAt >= currentApproverMetaUpdatedAt
        : currentApproverMetaUpdatedAt == 0;
    if (approvedBy != null && approverName != null && canApplyApproverMeta) {
      newDisplayNames[approvedBy] = approverName;
    }
    final approverPaymentAddress = _trustedIncomingPaymentAddress(
      decoded['approverPaymentAddress'],
    );
    final newPaymentAddresses = <String, SharedPaymentAddress>{
      ...group.paymentAddresses
    };
    if (approvedBy != null &&
        approverPaymentAddress != null &&
        canApplyApproverMeta) {
      newPaymentAddresses[approvedBy] = approverPaymentAddress;
    }
    final newMemberMetaUpdatedAt = <String, int>{
      ...group.memberMetaUpdatedAt,
      if (approvedBy != null &&
          approverMetaUpdatedAt > currentApproverMetaUpdatedAt)
        approvedBy: approverMetaUpdatedAt,
    };
    // The sender of this key_exchange is, by definition, the approver — they
    // hold the group key (otherwise they couldn't have shared it). Always
    // mark them approved, even when the payload omits the explicit fields
    // (e.g. older iOS clients send only {type, groupKey}).
    final approvedKeysAfter = <String>{
      ...group.approvedMemberKeys,
      if (myPublicKey.isNotEmpty) myPublicKey,
      if (senderPk.isNotEmpty) senderPk,
      if (approvedBy != null) approvedBy,
      if (approvedPk != null) approvedPk,
    };
    final approverActor =
        approvedBy ?? (senderPk.isNotEmpty ? senderPk : null);

    final updated = group.copyWith(
      name: groupName,
      status: SharedExpenseGroupStatus.ready,
      backfillNewMembers: backfillNewMembers,
      approvedMemberKeys: approvedKeysAfter,
      keySharedWith: {
        ...group.keySharedWith,
        if (senderPk.isNotEmpty) senderPk,
      },
      displayNames: newDisplayNames,
      paymentAddresses: newPaymentAddresses,
      memberMetaUpdatedAt: newMemberMetaUpdatedAt,
      pendingApprovals: group.pendingApprovals
          .where((p) =>
              p.publicKey != senderPk &&
              p.publicKey != approvedPk &&
              p.publicKey != approvedBy &&
              p.publicKey != myPublicKey)
          .toList(),
    );
    await _upsertGroup(updated);

    // Fire the "you've been approved" notification DIRECTLY here, not via the
    // coordinator+bus pipeline. The bus path was unreliable for this specific
    // event because the joiner's app is in its app-lifetime startup window
    // when the approval arrives, and any of these race conditions could
    // silently swallow the notification: (1) coordinator.start() hasn't yet
    // subscribed to the bus when this publish fires, (2) coordinator's seed
    // pass marks the entry seen before the bus listener fires, (3) freshness
    // window filters the entry out, (4) the seen-set + catch-up race fires
    // duplicates or nothing depending on event ordering. The notification
    // here is one-shot per (group, device) — a SharedPreferences flag
    // guards against replay across app restarts and SSE redelivery.
    if (myPublicKey.isNotEmpty && approverActor != null) {
      unawaited(
        _showApprovedNotificationOnce(
          group: updated,
          approverActor: approverActor,
          myPublicKey: myPublicKey,
        ),
      );
    }
    // Push the freshly-received group key into the vault so a future
    // restore brings it back. No-op if the user hasn't unlocked.
    unawaited(SharedExpenseVaultService.instance.syncIfUnlocked());
    // We now have the key — announce our display name to the approver.
    final joinedAt = _memberJoinedAtMs(updated, myPublicKey);
    await _emitMemberMeta(
      updated,
      previewEntry: SharedActivityEntry(
        id: _memberJoinedActivityId(updated, myPublicKey),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actor: myPublicKey,
        kind: 'member_joined',
        data: {
          'memberPk': myPublicKey,
          'displayName': updated.myDisplayName,
          if (joinedAt != null) 'joinedAt': joinedAt,
        },
      ),
    );
    return true;
  }

  Future<bool> _applyGroupMeta(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
  ) async {
    final newName = _trustedIncomingGroupName(group, decoded['name']);
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
    final incomingActivity = _activityFromPayload(decoded);
    final activity = [...group.activity];
    if (nameChanged) {
      activity.add(SharedActivityEntry(
        id: _activityIdOrNew(incomingActivity, 'group_renamed'),
        timestamp: timestamp,
        actor: senderPk,
        kind: 'group_renamed',
        data: {'before': group.name, 'after': newName},
      ));
    }
    if (isFirstSeen) {
      final joinedAt = _memberJoinedAtMs(group, senderPk);
      final joinedEntry = SharedActivityEntry(
        id: _memberJoinedActivityId(group, senderPk),
        timestamp: timestamp,
        actor: senderPk,
        kind: 'member_joined',
        data: {
          'memberPk': senderPk,
          if (joinedAt != null) 'joinedAt': joinedAt,
        },
      );
      if (!_hasMemberJoinedActivity(
        activity,
        memberPk: senderPk,
        joinedAt: joinedAt,
        activityId: joinedEntry.id,
      )) {
        activity.add(joinedEntry);
      }
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
    String myPublicKey,
  ) async {
    final displayName = _trustedIncomingDisplayName(
      current: group.displayNames[senderPk],
      rawName: decoded['displayName'],
      protectFallback: senderPk == myPublicKey,
    );
    final paymentAddress = _trustedIncomingPaymentAddress(
      decoded['paymentAddress'],
    );
    if ((displayName == null || displayName.isEmpty) &&
        paymentAddress == null) {
      return false;
    }
    final current = group.displayNames[senderPk];
    final currentPaymentAddress = group.paymentAddresses[senderPk];
    final currentUpdatedAt = group.memberMetaUpdatedAt[senderPk] ?? 0;
    final incomingUpdatedAt = _incomingMemberMetaUpdatedAt(decoded);
    final canApplyDisplayName = displayName != null &&
        _shouldApplyIncomingMemberMeta(
          incomingUpdatedAt: incomingUpdatedAt,
          currentUpdatedAt: currentUpdatedAt,
          hasCurrentValue: current != null &&
              current.trim().isNotEmpty &&
              !_isFallbackDisplayName(current),
        );
    final canApplyPaymentAddress = paymentAddress != null &&
        _shouldApplyIncomingMemberMeta(
          incomingUpdatedAt: incomingUpdatedAt,
          currentUpdatedAt: currentUpdatedAt,
          hasCurrentValue:
              currentPaymentAddress != null && currentPaymentAddress.isValid,
        );
    final isFirstSeen = !group.approvedMemberKeys.contains(senderPk);
    final displayChanged = canApplyDisplayName && current != displayName;
    final paymentChanged =
        canApplyPaymentAddress && currentPaymentAddress != paymentAddress;
    final timestampChanged = incomingUpdatedAt > currentUpdatedAt &&
        (canApplyDisplayName || canApplyPaymentAddress);
    if (!displayChanged &&
        !paymentChanged &&
        !timestampChanged &&
        !isFirstSeen) {
      return false;
    }

    final activity = [...group.activity];
    if (isFirstSeen) {
      final joinedAt = _memberJoinedAtMs(group, senderPk);
      final timestamp = (decoded['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      final joinedEntry = SharedActivityEntry(
        id: _memberJoinedActivityId(group, senderPk),
        timestamp: timestamp,
        actor: senderPk,
        kind: 'member_joined',
        data: {
          'memberPk': senderPk,
          if (displayName != null) 'displayName': displayName,
          if (joinedAt != null) 'joinedAt': joinedAt,
        },
      );
      if (!_hasMemberJoinedActivity(
        activity,
        memberPk: senderPk,
        joinedAt: joinedAt,
        activityId: joinedEntry.id,
      )) {
        activity.add(joinedEntry);
      }
    }

    final updated = group.copyWith(
      displayNames: !canApplyDisplayName
          ? group.displayNames
          : {...group.displayNames, senderPk: displayName},
      paymentAddresses: !canApplyPaymentAddress
          ? group.paymentAddresses
          : {
              ...group.paymentAddresses,
              senderPk: paymentAddress,
            },
      memberMetaUpdatedAt: timestampChanged
          ? {
              ...group.memberMetaUpdatedAt,
              senderPk: incomingUpdatedAt,
            }
          : null,
      myPaymentAddress: senderPk == myPublicKey && canApplyPaymentAddress
          ? paymentAddress
          : null,
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
    final incomingActivity = _activityFromPayload(decoded);
    final incomingActivities = _activitiesFromPayload(decoded);

    if (existing.isEmpty) {
      next = [...group.expenses, incoming.copyWith(status: 'synced')];
      if (!incoming.deleted) {
        activity.add(SharedActivityEntry(
          id: _activityIdOrNew(
            _activityForKind(
              incomingActivities,
              incomingActivity,
              incoming.kind == 'settlement'
                  ? 'settlement_created'
                  : 'expense_created',
            ),
            incoming.kind == 'settlement'
                ? 'settlement_created'
                : 'expense_created',
          ),
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
          id: _activityIdOrNew(
            _activityForKind(
              incomingActivities,
              incomingActivity,
              'expense_deleted',
            ),
            'expense_deleted',
          ),
          timestamp: ts,
          actor: actor,
          kind: 'expense_deleted',
          data: {'expenseId': incoming.id, 'reason': cur.reason},
        ));
      } else if (!incoming.deleted) {
        if (incoming.amount != cur.amount) {
          activity.add(SharedActivityEntry(
            id: _activityIdOrNew(
              _activityForKind(
                incomingActivities,
                incomingActivity,
                'expense_amount_changed',
              ),
              'expense_amount_changed',
            ),
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
            id: _activityIdOrNew(
              _activityForKind(
                incomingActivities,
                incomingActivity,
                'expense_reason_changed',
              ),
              'expense_reason_changed',
            ),
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
            id: _activityIdOrNew(
              _activityForKind(
                incomingActivities,
                incomingActivity,
                'expense_paid_by_changed',
              ),
              'expense_paid_by_changed',
            ),
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
            id: _activityIdOrNew(
              _activityForKind(
                incomingActivities,
                incomingActivity,
                'expense_split_changed',
              ),
              'expense_split_changed',
            ),
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

  SharedActivityEntry? _activityFromPayload(Map<String, dynamic> decoded) {
    final raw = decoded['activity'];
    if (raw is! Map) return null;
    final entry = SharedActivityEntry.fromJson(Map<String, dynamic>.from(raw));
    if (entry.id.isEmpty || entry.kind.isEmpty) return null;
    return entry;
  }

  List<SharedActivityEntry> _activitiesFromPayload(
    Map<String, dynamic> decoded,
  ) {
    final raw = decoded['activities'];
    if (raw is! List) return const <SharedActivityEntry>[];
    return raw
        .whereType<Map>()
        .map((item) =>
            SharedActivityEntry.fromJson(Map<String, dynamic>.from(item)))
        .where((entry) => entry.id.isNotEmpty && entry.kind.isNotEmpty)
        .toList(growable: false);
  }

  SharedActivityEntry? _activityForKind(
    List<SharedActivityEntry> entries,
    SharedActivityEntry? fallback,
    String expectedKind,
  ) {
    for (final entry in entries.reversed) {
      if (entry.kind == expectedKind) return entry;
    }
    if (fallback != null && fallback.kind == expectedKind) return fallback;
    return null;
  }

  String _activityIdOrNew(SharedActivityEntry? entry, String expectedKind) {
    if (entry != null && entry.kind == expectedKind && entry.id.isNotEmpty) {
      return entry.id;
    }
    return _uuid.v4();
  }

  int? _memberJoinedAtMs(SharedExpenseGroup group, String memberPk) {
    for (final member in group.members) {
      if (member.devicePublicKey == memberPk) {
        return member.joinedAt?.millisecondsSinceEpoch;
      }
    }
    return null;
  }

  String _memberJoinedActivityId(SharedExpenseGroup group, String memberPk) {
    final joinedAt = _memberJoinedAtMs(group, memberPk);
    final suffix = joinedAt == null ? '' : ':$joinedAt';
    return 'member_joined:${group.id}:$memberPk$suffix';
  }

  bool _hasMemberJoinedActivity(
    List<SharedActivityEntry> activity, {
    required String memberPk,
    required int? joinedAt,
    required String activityId,
  }) {
    for (final entry in activity) {
      if (entry.kind != 'member_joined') continue;
      if (entry.id == activityId) return true;
      if (entry.actor != memberPk) continue;

      final entryJoinedAt = (entry.data['joinedAt'] as num?)?.toInt();
      if (entryJoinedAt == null || joinedAt == null) return true;
      if (entryJoinedAt == joinedAt) return true;
    }
    return false;
  }

  List<SharedActivityEntry> _activityEntriesForExpensePayload(
    SharedExpenseGroup group,
    SharedExpense expense,
  ) {
    final versionTimestamp = expense.revisedAt ?? expense.timestamp;
    final entriesForVersion = group.activity
        .where((entry) =>
            entry.data['expenseId'] == expense.id &&
            entry.timestamp == versionTimestamp)
        .toList(growable: false);
    if (entriesForVersion.isNotEmpty) return entriesForVersion;

    final entriesForExpense = group.activity
        .where((entry) => entry.data['expenseId'] == expense.id)
        .toList(growable: false);
    if (entriesForExpense.isEmpty) return const <SharedActivityEntry>[];
    return [entriesForExpense.last];
  }

  Future<bool> _applyGroupSnapshot(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
    String myPublicKey,
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
    final paymentAddresses =
        _paymentAddressMapFromJson(decoded['paymentAddresses']);
    final incomingMemberMetaUpdatedAt =
        _memberMetaUpdatedAtMapFromJson(decoded['memberMetaUpdatedAt']);
    final approvedMemberKeys =
        _stringListFromJson(decoded['approvedMemberKeys']).toSet();
    final groupName = _trustedIncomingGroupName(group, decoded['groupName']);
    final incomingBackfill = decoded['backfillNewMembers'] is bool
        ? decoded['backfillNewMembers'] as bool
        : null;
    final createdAt = _snapshotDate(decoded['createdAt']);
    final mergedDisplayNames = _mergeDisplayNames(
      group.displayNames,
      displayNames,
      protectedPublicKey: myPublicKey,
      existingMetaUpdatedAt: group.memberMetaUpdatedAt,
      incomingMetaUpdatedAt: incomingMemberMetaUpdatedAt,
      allowLegacyOverwrite: false,
    );
    final mergedPaymentAddresses = _mergePaymentAddresses(
      group.paymentAddresses,
      paymentAddresses,
      existingMetaUpdatedAt: group.memberMetaUpdatedAt,
      incomingMetaUpdatedAt: incomingMemberMetaUpdatedAt,
      allowLegacyOverwrite: false,
    );
    final mergedMemberMetaUpdatedAt = _mergeMemberMetaUpdatedAt(
      group.memberMetaUpdatedAt,
      incomingMemberMetaUpdatedAt,
    );

    final updated = group.copyWith(
      name: groupName,
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
      displayNames: mergedDisplayNames,
      paymentAddresses: mergedPaymentAddresses,
      memberMetaUpdatedAt: mergedMemberMetaUpdatedAt,
      myPaymentAddress:
          mergedPaymentAddresses[myPublicKey] ?? group.myPaymentAddress,
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
    final displayName = _trustedIncomingDisplayName(
      current: group.displayNames[pk],
      rawName: decoded['displayName'],
    );
    final paymentAddress = _trustedIncomingPaymentAddress(
      decoded['paymentAddress'],
    );
    final ts = (decoded['timestamp'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final incomingUpdatedAt = _incomingMemberMetaUpdatedAt(decoded);
    final currentUpdatedAt = group.memberMetaUpdatedAt[pk] ?? 0;

    final currentDisplayName = group.displayNames[pk];
    final currentPaymentAddress = group.paymentAddresses[pk];
    final canApplyDisplayName = displayName != null &&
        _shouldApplyIncomingMemberMeta(
          incomingUpdatedAt: incomingUpdatedAt,
          currentUpdatedAt: currentUpdatedAt,
          hasCurrentValue: currentDisplayName != null &&
              currentDisplayName.trim().isNotEmpty &&
              !_isFallbackDisplayName(currentDisplayName),
        );
    final canApplyPaymentAddress = paymentAddress != null &&
        _shouldApplyIncomingMemberMeta(
          incomingUpdatedAt: incomingUpdatedAt,
          currentUpdatedAt: currentUpdatedAt,
          hasCurrentValue:
              currentPaymentAddress != null && currentPaymentAddress.isValid,
        );
    final approvalDisplayName =
        canApplyDisplayName ? displayName : group.displayNames[pk];

    // Strong idempotency: once we've processed this exact (pk, ts) join
    // request and stamped its activity entry into the log, ignore replays.
    // Without this check, a re-delivered payload (SSE reconnect race,
    // concurrent pullPending + stream) would re-strip approvedMemberKeys and
    // resurrect the pendingApproval entry even AFTER the user approved.
    // Replay is normal — the doorbell pull and the SSE stream can both see a
    // payload between the apply and the ack — so this needs to be cheap and
    // safe to run many times.
    final joinRequestedActivityId = 'join_requested:${group.id}:$pk:$ts';
    final hasExistingActivity = group.activity
        .any((entry) => entry.id == joinRequestedActivityId);
    if (hasExistingActivity) return false;

    // Idempotency: if we already have an identical pending entry for this
    // request, do nothing.
    final existing =
        group.pendingApprovals.where((p) => p.publicKey == pk).toList();
    if (existing.isNotEmpty &&
        existing.first.displayName == approvalDisplayName &&
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
        displayName: approvalDisplayName,
        requestedAt: ts,
      ),
    ];
    final newDisplayNames = <String, String>{...group.displayNames};
    if (canApplyDisplayName && displayName.isNotEmpty) {
      newDisplayNames[pk] = displayName;
    }
    final newPaymentAddresses = <String, SharedPaymentAddress>{
      ...group.paymentAddresses
    };
    if (canApplyPaymentAddress) {
      newPaymentAddresses[pk] = paymentAddress;
    }
    final newMemberMetaUpdatedAt = incomingUpdatedAt > currentUpdatedAt &&
            (canApplyDisplayName || canApplyPaymentAddress)
        ? {
            ...group.memberMetaUpdatedAt,
            pk: incomingUpdatedAt,
          }
        : group.memberMetaUpdatedAt;

    // Surface as a notifiable activity entry so the local notification
    // coordinator (which composes everything from the activity log under the
    // doorbell model) can show "X wants to join Group". Reaching this point
    // means the short-circuit above let us through — there's no entry for
    // this (pk, ts) yet, so append unconditionally.
    final activity = [
      ...group.activity,
      SharedActivityEntry(
        id: joinRequestedActivityId,
        timestamp: ts,
        actor: pk,
        kind: 'join_requested',
        data: {
          'requesterPk': pk,
          if (approvalDisplayName != null && approvalDisplayName.isNotEmpty)
            'requesterDisplayName': approvalDisplayName,
        },
      ),
    ];

    // The card UI's pending-approval list is rendered from the intersection
    // of `members` and `pendingApprovals`. The requester won't appear in our
    // server-side `members` list until the next refreshGroups call, so insert
    // a stub member here so the bus-driven UI update can render the pending
    // card immediately instead of waiting for a manual refresh. When the real
    // member arrives via the next refreshGroups, the stub is overwritten.
    final hasMember =
        group.members.any((member) => member.devicePublicKey == pk);
    final newMembers = hasMember
        ? group.members
        : [
            ...group.members,
            SharedExpenseMember(
              devicePublicKey: pk,
              joinedAt: DateTime.fromMillisecondsSinceEpoch(ts),
            ),
          ];

    final updated = group.copyWith(
      members: newMembers,
      pendingApprovals: newPending,
      displayNames: newDisplayNames,
      paymentAddresses: newPaymentAddresses,
      memberMetaUpdatedAt: newMemberMetaUpdatedAt,
      approvedMemberKeys:
          group.approvedMemberKeys.where((k) => k != pk).toSet(),
      keySharedWith: group.keySharedWith.where((k) => k != pk).toSet(),
      activity: activity,
    );
    await _upsertGroup(updated);
    return true;
  }

  Future<bool> _applyMemberLeft(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
    String myPublicKey,
  ) async {
    final pk = decoded['publicKey'] as String? ?? senderPk;
    if (pk.isEmpty || pk == myPublicKey) return false;

    final incomingActivity = _activityFromPayload(decoded);
    final leftAt = (decoded['leftAt'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final activityId =
        incomingActivity?.id.isNotEmpty == true && incomingActivity!.kind == 'member_left'
            ? incomingActivity.id
            : 'member_left:${group.id}:$pk:$leftAt';

    // Replay safety: if the activity entry is already present, this is the
    // same payload re-delivered (SSE reconnect, concurrent pullPending). Don't
    // re-drop the member or re-fire the notification.
    if (group.activity.any((entry) => entry.id == activityId)) return false;

    final hadMember =
        group.members.any((member) => member.devicePublicKey == pk);
    final hadKeyShared = group.keySharedWith.contains(pk);
    final hadApproval = group.approvedMemberKeys.contains(pk);
    if (!hadMember && !hadKeyShared && !hadApproval) return false;

    final displayName = decoded['displayName'] as String?;
    final activityEntry = SharedActivityEntry(
      id: activityId,
      timestamp: leftAt,
      actor: pk,
      kind: 'member_left',
      data: {
        'memberPk': pk,
        if (displayName != null && displayName.trim().isNotEmpty)
          'displayName': displayName,
      },
    );

    final updated = group.copyWith(
      members:
          group.members.where((m) => m.devicePublicKey != pk).toList(),
      approvedMemberKeys:
          group.approvedMemberKeys.where((k) => k != pk).toSet(),
      keySharedWith: group.keySharedWith.where((k) => k != pk).toSet(),
      pendingApprovals:
          group.pendingApprovals.where((p) => p.publicKey != pk).toList(),
      activity: [...group.activity, activityEntry],
    );
    await _upsertGroup(updated);
    return true;
  }

  /// Frontend safety net: someone other than this device approved the
  /// sender, but we never saw the explicit broadcast. Mirror the same
  /// state change the broadcast handler would produce, and return the
  /// updated group so the caller can continue processing on fresh state.
  /// Triggered when a group-key-encrypted payload arrives from a member
  /// who's still in our local pendingApprovals.
  Future<SharedExpenseGroup> _autoPromotePendingMember(
    SharedExpenseGroup group,
    String senderPk,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final activityId = 'member_approved:${group.id}:$senderPk:auto:$now';
    if (group.activity.any((entry) => entry.id == activityId)) {
      return group;
    }
    _sharedExpenseLog(
      '_autoPromotePendingMember sender=${_logId(senderPk)} group=${_logId(group.id)}',
    );
    final updated = group.copyWith(
      approvedMemberKeys: {...group.approvedMemberKeys, senderPk},
      pendingApprovals: group.pendingApprovals
          .where((p) => p.publicKey != senderPk)
          .toList(),
      activity: [
        ...group.activity,
        SharedActivityEntry(
          id: activityId,
          timestamp: now,
          actor: senderPk,
          kind: 'member_approved',
          data: {'memberPk': senderPk, 'auto': true},
        ),
      ],
    );
    await _upsertGroup(updated);
    return updated;
  }

  /// Mirror of [approveMember]'s local state change for the OTHER approvers.
  /// When one approver taps Approve, they update their own state and send
  /// key_exchange to the new member — without this broadcast handler the
  /// other approvers' pending list never clears and the Approve button
  /// lingers there indefinitely.
  Future<bool> _applyMemberApproved(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
    String myPublicKey,
  ) async {
    final approvedPk = decoded['approvedPublicKey'] as String? ?? '';
    if (approvedPk.isEmpty || approvedPk == myPublicKey) return false;

    final incomingActivity = _activityFromPayload(decoded);
    final approvedAt = (decoded['timestamp'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final activityId = incomingActivity?.id.isNotEmpty == true &&
            incomingActivity!.kind == 'member_approved'
        ? incomingActivity.id
        : 'member_approved:${group.id}:$approvedPk:$approvedAt';

    if (group.activity.any((entry) => entry.id == activityId)) return false;

    final alreadyApproved =
        group.approvedMemberKeys.contains(approvedPk);
    final hadPending =
        group.pendingApprovals.any((p) => p.publicKey == approvedPk);
    if (alreadyApproved && !hadPending) return false;

    final approverPk = decoded['approvedBy'] as String? ?? senderPk;
    final activityEntry = SharedActivityEntry(
      id: activityId,
      timestamp: approvedAt,
      actor: approverPk,
      kind: 'member_approved',
      data: {'memberPk': approvedPk},
    );

    final updated = group.copyWith(
      approvedMemberKeys: {...group.approvedMemberKeys, approvedPk},
      pendingApprovals: group.pendingApprovals
          .where((p) => p.publicKey != approvedPk)
          .toList(),
      activity: [...group.activity, activityEntry],
    );
    await _upsertGroup(updated);
    return true;
  }

  Future<bool> _applyJoinCancel(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
    String myPublicKey,
  ) async {
    final pk = decoded['publicKey'] as String? ?? senderPk;
    if (pk.isEmpty || pk == myPublicKey) return false;
    final hadPending = group.pendingApprovals.any((p) => p.publicKey == pk);
    final hadMember =
        group.members.any((member) => member.devicePublicKey == pk);
    if (!hadPending && !hadMember) return false;
    // Also drop the requester from `members` so the stub we inserted in
    // _applyJoinRequest doesn't linger as a ghost. Kidist's DELETE /members/me
    // removes her server-side too, so the next refreshGroups won't put her
    // back.
    final updated = group.copyWith(
      pendingApprovals:
          group.pendingApprovals.where((p) => p.publicKey != pk).toList(),
      members:
          group.members.where((m) => m.devicePublicKey != pk).toList(),
    );
    await _upsertGroup(updated);
    return true;
  }

  /// Honor a peer's request to re-share the entire group state. Sent by a
  /// device that restored from a vault — it has the seed and group key but
  /// no expenses or activity. We respond by emitting a fresh group_snapshot
  /// targeted at the requester AND record a `member_restored` activity
  /// entry locally so peers see a notification: someone with this person's
  /// identity just restored a device, which is both informational ("Khalid
  /// got a new phone") and a security signal ("if Khalid didn't do this,
  /// someone has his recovery code and PIN").
  Future<bool> _applySnapshotRequest(
    SharedExpenseGroup group,
    String senderPk,
    Map<String, dynamic> decoded,
  ) async {
    if (senderPk.isEmpty) return false;
    // Only respond if the sender is someone we recognize as an approved
    // member. Restored devices reuse the same pubkey they had before, so
    // approvedMemberKeys still contains them. This blocks random callers.
    if (!group.approvedMemberKeys.contains(senderPk)) {
      _sharedExpenseLog(
        '_applySnapshotRequest ignored: sender not approved '
        'sender=${_logId(senderPk)} group=${_logId(group.id)}',
      );
      return false;
    }
    final groupKeyHex = await _readGroupKey(group.id);
    if (groupKeyHex == null) return false;

    final ts = (decoded['timestamp'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final activityId = 'member_restored:${group.id}:$senderPk:$ts';
    final hasExistingEntry =
        group.activity.any((entry) => entry.id == activityId);
    if (!hasExistingEntry) {
      final updated = group.copyWith(
        activity: [
          ...group.activity,
          SharedActivityEntry(
            id: activityId,
            timestamp: ts,
            actor: senderPk,
            kind: 'member_restored',
            data: {'memberPk': senderPk},
          ),
        ],
      );
      await _upsertGroup(updated);
    }

    _sharedExpenseLog(
      '_applySnapshotRequest emit snapshot to ${_logId(senderPk)} '
      'group=${_logId(group.id)} '
      'activityAdded=${!hasExistingEntry}',
    );
    await _emitGroupSnapshotPayload(
      group: group,
      recipientPublicKey: senderPk,
      groupKeyHex: groupKeyHex,
      includeHistory: true,
    );
    return !hasExistingEntry;
  }

  /// After a vault restore we need to create local rows for the groups whose
  /// keys we just wrote into secure storage — `refreshGroups()` won't do that
  /// on its own (it intentionally skips server groups it doesn't already
  /// know about as a safety check). For each `groupId` in [vaultGroupIds]
  /// where (a) the server still lists us as a member AND (b) we have the
  /// group key locally, insert a minimal local row. The next
  /// `refreshGroups()` and subsequent `group_snapshot` arrivals will fill in
  /// the actual name, display names, expenses, etc.
  Future<void> bootstrapGroupsForRestore(List<String> vaultGroupIds) async {
    if (vaultGroupIds.isEmpty) return;
    _sharedExpenseLog(
      'bootstrapGroupsForRestore ${vaultGroupIds.length} candidate groups',
    );
    final serverGroups = await _engineClient.listGroups();
    final identity = await _cryptoService.getOrCreateIdentity();
    final candidateIds = vaultGroupIds.toSet();
    for (final serverGroup in serverGroups) {
      if (!candidateIds.contains(serverGroup.id)) continue;
      final hasKey = await _readGroupKey(serverGroup.id) != null;
      if (!hasKey) {
        _sharedExpenseLog(
          'bootstrapGroupsForRestore skipping no-key group=${_logId(serverGroup.id)}',
        );
        continue;
      }
      final existing = await _groupById(serverGroup.id);
      if (existing != null) continue;
      final group = SharedExpenseGroup(
        id: serverGroup.id,
        name: _fallbackGroupName,
        myDisplayName: '',
        createdAt: serverGroup.createdAt,
        expiresAt: serverGroup.expiresAt,
        status: SharedExpenseGroupStatus.ready,
        members: serverGroup.members,
        approvedMemberKeys: {identity.publicKeyHex},
      );
      await _upsertGroup(group);
      _sharedExpenseLog(
        'bootstrapGroupsForRestore created group=${_logId(serverGroup.id)}',
      );
    }
  }

  /// After a vault restore, ask every other current member to re-share the
  /// group snapshot. Each responder runs [_applySnapshotRequest] above and
  /// targets us with a fresh group_snapshot payload, which our existing
  /// _applyGroupSnapshot merges into our (now-non-empty) local state.
  ///
  /// Public so [SharedExpenseVaultService.restore]'s caller can fire this
  /// after rehydrating the local DB rows via refreshGroups().
  Future<void> requestSnapshotsForAllGroups() async {
    final groups = await getGroups();
    for (final group in groups) {
      if (!group.hasGroupKey) continue;
      if (group.members.isEmpty) continue;
      await _broadcastSnapshotRequest(group);
    }
  }

  Future<void> _broadcastSnapshotRequest(SharedExpenseGroup group) async {
    final groupKeyHex = await _readGroupKey(group.id);
    if (groupKeyHex == null) return;
    final keyBytes = SharedExpenseCryptoService.fromHex(groupKeyHex);
    final identity = await _cryptoService.getOrCreateIdentity();
    final payload = {
      'type': 'snapshot_request',
      'publicKey': identity.publicKeyHex,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    for (final member in group.members) {
      if (member.devicePublicKey == identity.publicKeyHex) continue;
      if (member.devicePublicKey.isEmpty) continue;
      try {
        final encrypted = await _cryptoService.encryptPayloadWithKey(
          keyBytes: keyBytes,
          payload: payload,
        );
        await _engineClient.submitTargetedPayload(
          groupId: group.id,
          encryptedBlob: encrypted,
          recipientPublicKeys: [member.devicePublicKey],
          kind: 'snapshot_request',
        );
      } catch (error) {
        _sharedExpenseLog(
          '_broadcastSnapshotRequest failed recipient='
          '${_logId(member.devicePublicKey)} error=$error',
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Outbound payload emitters
  // -------------------------------------------------------------------------

  Future<void> _emitExpensePayload(
    SharedExpenseGroup group,
    SharedExpense expense, {
    SharedActivityEntry? previewEntry,
    List<SharedActivityEntry> activityEntries = const <SharedActivityEntry>[],
  }) async {
    final groupKeyHex = await _readGroupKey(group.id);
    if (groupKeyHex == null) {
      throw const TotalsEngineException('No group key — cannot share expense.');
    }
    final payloadActivities = activityEntries.isNotEmpty
        ? activityEntries
        : [
            if (previewEntry != null) previewEntry,
          ];
    final payload = {
      'type': 'expense',
      ...expense.toJson(),
      if (previewEntry != null) 'activity': previewEntry.toJson(),
      if (payloadActivities.isNotEmpty)
        'activities': payloadActivities
            .map((entry) => entry.toJson())
            .toList(growable: false),
    };
    final encrypted = await _cryptoService.encryptPayloadWithKey(
      keyBytes: SharedExpenseCryptoService.fromHex(groupKeyHex),
      payload: payload,
    );
    await _engineClient.submitPayload(
      groupId: group.id,
      encryptedBlob: encrypted,
      kind: 'expense',
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

  Future<String?> notificationGroupKey(String groupId) {
    return _readGroupKey(groupId);
  }

  /// For vault backup: read the current group key for a group, or null when
  /// we don't have it (e.g. still in pendingApproval status).
  Future<String?> exportGroupKey(String groupId) {
    return _readGroupKey(groupId);
  }

  /// For vault restore: write a group key back into secure storage from a
  /// just-unsealed vault. Caller is responsible for upserting a matching
  /// SharedExpenseGroup row.
  Future<void> restoreGroupKey({
    required String groupId,
    required String groupKeyHex,
  }) {
    return _writeGroupKey(groupId, groupKeyHex);
  }

  static const _approvalNotifiedPrefsPrefix =
      'shared_expense_approval_notified_';

  Future<void> _showApprovedNotificationOnce({
    required SharedExpenseGroup group,
    required String approverActor,
    required String myPublicKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_approvalNotifiedPrefsPrefix${group.id}:$myPublicKey';
    if (prefs.getBool(key) == true) {
      _sharedExpenseLog(
        'approve-notify skip: already notified group=${_logId(group.id)}',
      );
      return;
    }
    await prefs.setBool(key, true);

    final approverName =
        group.displayNameFor(myPublicKey, approverActor);
    final groupName =
        group.name.trim().isEmpty ? 'your group' : group.name;
    _sharedExpenseLog(
      'approve-notify fire group=${_logId(group.id)} '
      'approver=${_logId(approverActor)}',
    );
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: 'i_was_approved:${group.id}:$myPublicKey',
      groupId: group.id,
      title: 'Join request approved',
      body: '$approverName approved your request to join $groupName.',
    );
  }

  Future<void> _emitGroupSnapshotPayload({
    required SharedExpenseGroup group,
    required String recipientPublicKey,
    required String groupKeyHex,
    required bool includeHistory,
  }) async {
    final keyBytes = SharedExpenseCryptoService.fromHex(groupKeyHex);
    final snapshotId = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final identity = await _cryptoService.getOrCreateIdentity();
    final groupName = _bestKnownGroupName(group);
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
        if (!_isFallbackGroupName(groupName)) 'groupName': groupName,
        'backfillNewMembers': group.backfillNewMembers,
        'createdAt': group.createdAt.millisecondsSinceEpoch,
        'members': group.members.map((member) => member.toJson()).toList(),
        'approvedMemberKeys': group.approvedMemberKeys.toList(),
        'displayNames': _outboundDisplayNames(
          group,
          identity.publicKeyHex,
        ),
        'memberMetaUpdatedAt': _outboundMemberMetaUpdatedAt(
          group,
          identity.publicKeyHex,
        ),
        'paymentAddresses': _outboundPaymentAddresses(
          group,
          identity.publicKeyHex,
        ),
      },
    );

    if (!includeHistory) return;

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
      kind: 'group_snapshot',
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
    final identity = await _cryptoService.getOrCreateIdentity();
    final groupName = _bestKnownGroupName(group);
    final displayName = _bestKnownDisplayName(group, identity.publicKeyHex);
    final paymentAddress =
        _bestKnownPaymentAddress(group, identity.publicKeyHex);
    final memberMetaUpdatedAt =
        _bestKnownMemberMetaUpdatedAt(group, identity.publicKeyHex);
    final groupRenamePreviewEntry = _latestOwnActivity(
      group: group,
      actorPk: identity.publicKeyHex,
      kind: 'group_renamed',
      matches: (entry) {
        final after = entry.data['after'];
        return after is String && after.trim() == groupName;
      },
    );
    var allOk = true;
    if (groupName.isNotEmpty && !_isFallbackGroupName(groupName)) {
      try {
        final encrypted = await _cryptoService.encryptPayloadWithKey(
          keyBytes: keyBytes,
          payload: {
            'type': 'group_meta',
            'name': groupName,
            'backfillNewMembers': group.backfillNewMembers,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            if (groupRenamePreviewEntry != null)
              'activity': groupRenamePreviewEntry.toJson(),
          },
        );
        await _engineClient.submitPayload(
          groupId: group.id,
          encryptedBlob: encrypted,
          kind: 'group_meta',
        );
      } catch (e) {
        _sharedExpenseLog('group_meta send failed: $e');
        allOk = false;
      }
    }
    final hasDisplayName =
        displayName.isNotEmpty && !_isFallbackDisplayName(displayName);
    final hasPaymentAddress = paymentAddress != null && paymentAddress.isValid;
    if (hasDisplayName || hasPaymentAddress) {
      try {
        final encrypted = await _cryptoService.encryptPayloadWithKey(
          keyBytes: keyBytes,
          payload: {
            'type': 'member_meta',
            if (hasDisplayName) 'displayName': displayName,
            if (paymentAddress != null && paymentAddress.isValid)
              'paymentAddress': paymentAddress.toJson(),
            'memberMetaUpdatedAt': memberMetaUpdatedAt,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );
        await _engineClient.submitPayload(
          groupId: group.id,
          encryptedBlob: encrypted,
          kind: 'member_meta',
        );
      } catch (e) {
        _sharedExpenseLog('member_meta send failed: $e');
        allOk = false;
      }
    }
    return allOk;
  }

  Future<void> _emitMemberMeta(
    SharedExpenseGroup group, {
    SharedActivityEntry? previewEntry,
  }) async {
    final groupKeyHex = await _readGroupKey(group.id);
    if (groupKeyHex == null) return;
    final identity = await _cryptoService.getOrCreateIdentity();
    final displayName = _bestKnownDisplayName(group, identity.publicKeyHex);
    final paymentAddress =
        _bestKnownPaymentAddress(group, identity.publicKeyHex);
    final memberMetaUpdatedAt =
        _bestKnownMemberMetaUpdatedAt(group, identity.publicKeyHex);
    if ((displayName.trim().isEmpty || _isFallbackDisplayName(displayName)) &&
        paymentAddress == null) {
      return;
    }
    try {
      final encrypted = await _cryptoService.encryptPayloadWithKey(
        keyBytes: SharedExpenseCryptoService.fromHex(groupKeyHex),
        payload: {
          'type': 'member_meta',
          if (!_isFallbackDisplayName(displayName)) 'displayName': displayName,
          if (paymentAddress != null && paymentAddress.isValid)
            'paymentAddress': paymentAddress.toJson(),
          'memberMetaUpdatedAt': memberMetaUpdatedAt,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          if (previewEntry != null) 'activity': previewEntry.toJson(),
        },
      );
      await _engineClient.submitPayload(
        groupId: group.id,
        encryptedBlob: encrypted,
        kind: 'member_meta',
      );
    } catch (e) {
      _sharedExpenseLog('_emitMemberMeta failed: $e — flagging for retry');
      final latest = await _groupById(group.id);
      if (latest != null) {
        await _upsertGroup(latest.copyWith(pendingMetaBroadcast: true));
      }
    }
  }

  SharedActivityEntry? _latestOwnActivity({
    required SharedExpenseGroup group,
    required String actorPk,
    required String kind,
    bool Function(SharedActivityEntry entry)? matches,
  }) {
    for (final entry in group.activity.reversed) {
      if (entry.actor != actorPk || entry.kind != kind) continue;
      if (matches != null && !matches(entry)) continue;
      return entry;
    }
    return null;
  }

  /// Tell every other approver the request has been handled so the
  /// pending-approval card clears across devices, not just on the approver's.
  /// Group-key encrypted (single broadcast hits every approved member's SSE
  /// stream); the newly-approved member and the approver themselves skip
  /// in [_applyMemberApproved].
  Future<void> _broadcastMemberApproved({
    required SharedExpenseGroup group,
    required String approverPublicKey,
    required String approvedPublicKey,
    required String groupKeyHex,
    required int approvedAt,
    required String activityId,
  }) async {
    final payload = {
      'type': 'member_approved',
      'approvedPublicKey': approvedPublicKey,
      'approvedBy': approverPublicKey,
      'timestamp': approvedAt,
      'activity': SharedActivityEntry(
        id: activityId,
        timestamp: approvedAt,
        actor: approverPublicKey,
        kind: 'member_approved',
        data: {'memberPk': approvedPublicKey},
      ).toJson(),
    };
    try {
      final encrypted = await _cryptoService.encryptPayloadWithKey(
        keyBytes: SharedExpenseCryptoService.fromHex(groupKeyHex),
        payload: payload,
      );
      await _engineClient.submitPayload(
        groupId: group.id,
        encryptedBlob: encrypted,
        kind: 'member_approved',
      );
    } catch (error) {
      _sharedExpenseLog('_broadcastMemberApproved failed error=$error');
    }
  }

  Future<void> _broadcastMemberLeft(SharedExpenseGroup group) async {
    final groupKeyHex = await _readGroupKey(group.id);
    if (groupKeyHex == null) return;
    final identity = await _cryptoService.getOrCreateIdentity();
    final leftAt = DateTime.now().millisecondsSinceEpoch;
    final displayName = _bestKnownDisplayName(group, identity.publicKeyHex);
    final activityId =
        'member_left:${group.id}:${identity.publicKeyHex}:$leftAt';
    final activityEntry = SharedActivityEntry(
      id: activityId,
      timestamp: leftAt,
      actor: identity.publicKeyHex,
      kind: 'member_left',
      data: {
        'memberPk': identity.publicKeyHex,
        if (!_isFallbackDisplayName(displayName)) 'displayName': displayName,
      },
    );
    final payload = {
      'type': 'member_left',
      'publicKey': identity.publicKeyHex,
      'leftAt': leftAt,
      'activity': activityEntry.toJson(),
    };
    try {
      final encrypted = await _cryptoService.encryptPayloadWithKey(
        keyBytes: SharedExpenseCryptoService.fromHex(groupKeyHex),
        payload: payload,
      );
      await _engineClient.submitPayload(
        groupId: group.id,
        encryptedBlob: encrypted,
        kind: 'member_left',
      );
    } catch (error) {
      _sharedExpenseLog('_broadcastMemberLeft failed error=$error');
    }
  }

  Future<void> _broadcastJoinCancel(SharedExpenseGroup group) async {
    final identity = await _cryptoService.getOrCreateIdentity();
    final payload = {
      'type': 'join_cancel',
      'publicKey': identity.publicKeyHex,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    for (final member in group.members) {
      if (member.devicePublicKey == identity.publicKeyHex) continue;
      if (member.devicePublicKey.isEmpty) continue;
      try {
        final encrypted = await _cryptoService.encryptGroupKeyPayload(
          recipientPublicKeyHex: member.devicePublicKey,
          payload: payload,
        );
        await _engineClient.submitTargetedPayload(
          groupId: group.id,
          encryptedBlob: encrypted,
          recipientPublicKeys: [member.devicePublicKey],
          kind: 'join_cancel',
        );
      } catch (error) {
        _sharedExpenseLog(
          '_broadcastJoinCancel failed recipient=${_logId(member.devicePublicKey)} error=$error',
        );
      }
    }
  }

  Future<void> _broadcastJoinRequest(SharedExpenseGroup group) async {
    final identity = await _cryptoService.getOrCreateIdentity();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final displayName = _bestKnownDisplayName(group, identity.publicKeyHex);
    final paymentAddress =
        _bestKnownPaymentAddress(group, identity.publicKeyHex);
    final memberMetaUpdatedAt =
        _bestKnownMemberMetaUpdatedAt(group, identity.publicKeyHex);
    final payload = {
      'type': 'join_request',
      'publicKey': identity.publicKeyHex,
      if (!_isFallbackDisplayName(displayName)) 'displayName': displayName,
      if (paymentAddress != null && paymentAddress.isValid)
        'paymentAddress': paymentAddress.toJson(),
      'memberMetaUpdatedAt': memberMetaUpdatedAt,
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
        await _engineClient.submitTargetedPayload(
          groupId: group.id,
          encryptedBlob: encrypted,
          recipientPublicKeys: [member.devicePublicKey],
          kind: 'join_request',
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
        '_readGroupKey failed group=${_logId(groupId)} error=$error',
      );
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

SettlementPlan originalDebtPlanFor(SharedExpenseGroup group) {
  final balances = computeBalancesFor(group);
  final obligations = <String, Map<String, double>>{};

  void addObligation(String from, String to, double amount) {
    if (from.isEmpty || to.isEmpty || from == to || amount.abs() < 0.005) {
      return;
    }
    final byRecipient = obligations.putIfAbsent(
      from,
      () => <String, double>{},
    );
    byRecipient[to] = (byRecipient[to] ?? 0.0) + amount;
  }

  for (final ex in group.expenses) {
    if (ex.deleted) continue;
    if (ex.amount <= 0) continue;
    if (ex.paidBy.isEmpty || ex.splitAmong.isEmpty) continue;
    final share = ex.amount / ex.splitAmong.length;
    final isSettlement = ex.kind.toLowerCase() == 'settlement';
    for (final pk in ex.splitAmong) {
      if (isSettlement) {
        addObligation(ex.paidBy, pk, -share);
      } else {
        addObligation(pk, ex.paidBy, share);
      }
    }
  }

  final debts = <SettlementDebt>[];
  final seenPairs = <String>{};
  obligations.forEach((from, byRecipient) {
    byRecipient.forEach((to, amount) {
      final pairKey = from.compareTo(to) <= 0 ? '$from|$to' : '$to|$from';
      if (!seenPairs.add(pairKey)) return;

      final oppositeAmount = obligations[to]?[from] ?? 0.0;
      final net = amount - oppositeAmount;
      if (net > 0.005) {
        debts.add(SettlementDebt(from: from, to: to, amount: net));
      } else if (net < -0.005) {
        debts.add(SettlementDebt(from: to, to: from, amount: -net));
      }
    });
  });
  debts.sort((a, b) {
    final amountCompare = b.amount.compareTo(a.amount);
    if (amountCompare != 0) return amountCompare;
    final fromCompare = a.from.compareTo(b.from);
    if (fromCompare != 0) return fromCompare;
    return a.to.compareTo(b.to);
  });

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
