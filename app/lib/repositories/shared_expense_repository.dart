import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/services/shared_expense_crypto_service.dart';
import 'package:totals/services/totals_engine_client.dart';

void _sharedExpenseLog(String message) {
  if (kDebugMode) {
    debugPrint('debug: SharedExpensesRepo: $message');
  }
}

String _logId(String value) {
  if (value.length <= 12) return value;
  return '${value.substring(0, 8)}...${value.substring(value.length - 4)}';
}

class SharedExpenseRepository {
  static const _groupsKey = 'shared_expense_groups_v1';
  static const _groupKeyPrefix = 'shared_expense_group_key_';
  static const _legacyInvitePrefixes = ['totals://join/', 'totals//join/'];

  final TotalsEngineClient _engineClient;
  final SharedExpenseCryptoService _cryptoService;
  final FlutterSecureStorage _secureStorage;
  final Uuid _uuid;

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

  Future<String> myPublicKey() async {
    final identity = await _cryptoService.getOrCreateIdentity();
    return identity.publicKeyHex;
  }

  Future<List<SharedExpenseGroup>> getGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_groupsKey);
      if (raw == null || raw.isEmpty) {
        _sharedExpenseLog('getGroups local cache empty');
        return const [];
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _sharedExpenseLog('getGroups ignored non-list cache payload');
        return const [];
      }

      final groups = decoded
          .whereType<Map>()
          .map((group) => SharedExpenseGroup.fromJson(
                Map<String, dynamic>.from(group),
              ))
          .where((group) => group.id.isNotEmpty)
          .toList(growable: false);
      _sharedExpenseLog('getGroups loaded ${groups.length} local groups');
      return groups;
    } catch (error, stackTrace) {
      _sharedExpenseLog('getGroups failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

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
    );
    await _upsertGroup(group);
    final changed = await processPendingApprovals(groupId);
    final result = (await _groupById(groupId)) ?? group;
    _sharedExpenseLog(
      'joinGroup done group=${_logId(groupId)} status=${result.status.name} '
      'approvalPayloadApplied=$changed',
    );
    return result;
  }

  Future<List<SharedExpenseGroup>> refreshGroups() async {
    _sharedExpenseLog('refreshGroups start');
    final localGroups = await getGroups();
    final localById = {for (final group in localGroups) group.id: group};
    final serverGroups = await _engineClient.listGroups();
    final identity = await _cryptoService.getOrCreateIdentity();
    _sharedExpenseLog(
      'refreshGroups serverGroups=${serverGroups.length} '
      'localGroups=${localGroups.length}',
    );

    for (final serverGroup in serverGroups) {
      final local = localById[serverGroup.id];
      final hasKey = await _readGroupKey(serverGroup.id) != null;
      final approvedKeys = <String>{
        ...?local?.approvedMemberKeys,
        if (hasKey) identity.publicKeyHex,
      };
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
      );
      await _upsertGroup(merged);
      _sharedExpenseLog(
        'refreshGroups merged group=${_logId(merged.id)} '
        'status=${merged.status.name} members=${merged.members.length}',
      );
    }

    for (final serverGroup in serverGroups) {
      final changed = await processPendingApprovals(serverGroup.id);
      if (changed) {
        _sharedExpenseLog(
          'refreshGroups applied approval payload group=${_logId(serverGroup.id)}',
        );
      }
    }

    final groups = await getGroups();
    _sharedExpenseLog('refreshGroups done groups=${groups.length}');
    return groups;
  }

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
    final encryptedBlob = await _cryptoService.encryptGroupKeyPayload(
      recipientPublicKeyHex: member.devicePublicKey,
      payload: {
        'type': 'group_key',
        'groupId': group.id,
        'groupName': group.name,
        'groupKey': groupKeyHex,
        'approvedPublicKey': member.devicePublicKey,
        'approvedBy': identity.publicKeyHex,
        'approverDisplayName': group.myDisplayName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    await _engineClient.submitPayload(
      groupId: group.id,
      encryptedBlob: encryptedBlob,
    );

    final updated = group.copyWith(
      approvedMemberKeys: {
        ...group.approvedMemberKeys,
        member.devicePublicKey,
        identity.publicKeyHex,
      },
    );
    await _upsertGroup(updated);
    _sharedExpenseLog(
      'approveMember done group=${_logId(group.id)} '
      'member=${_logId(member.devicePublicKey)}',
    );
  }

  Future<bool> processPendingApprovals(String groupId) async {
    final group = await _groupById(groupId);
    if (group?.hasGroupKey == true) {
      _sharedExpenseLog(
        'processPendingApprovals skipped, already has key group=${_logId(groupId)}',
      );
      return false;
    }

    _sharedExpenseLog('processPendingApprovals start group=${_logId(groupId)}');
    final payloads = await _engineClient.pullPending(groupId);
    _sharedExpenseLog(
      'processPendingApprovals payloads=${payloads.length} group=${_logId(groupId)}',
    );
    var changed = false;
    for (final payload in payloads) {
      final decoded = await _cryptoService.decryptGroupKeyPayload(
        senderPublicKeyHex: payload.senderPublicKey,
        encryptedBlob: payload.encryptedBlob,
      );
      if (decoded == null || decoded['type'] != 'group_key') {
        _sharedExpenseLog(
          'processPendingApprovals skipped unreadable payload=${_logId(payload.id)}',
        );
        continue;
      }

      final groupKey = decoded['groupKey'] as String?;
      if (groupKey == null || groupKey.length != 64) {
        _sharedExpenseLog(
          'processPendingApprovals skipped invalid group key payload=${_logId(payload.id)}',
        );
        continue;
      }

      await _writeGroupKey(groupId, groupKey);
      final latestGroup = await _groupById(groupId);
      final updated = (latestGroup ?? group)?.copyWith(
        name: decoded['groupName'] as String? ?? latestGroup?.name,
        status: SharedExpenseGroupStatus.ready,
        approvedMemberKeys: {
          ...?latestGroup?.approvedMemberKeys,
          if (decoded['approvedBy'] is String) decoded['approvedBy'] as String,
          if (decoded['approvedPublicKey'] is String)
            decoded['approvedPublicKey'] as String,
        },
      );
      if (updated != null) await _upsertGroup(updated);
      changed = true;
      await _engineClient.acknowledgePayload(payload.id);
      _sharedExpenseLog(
        'processPendingApprovals accepted payload=${_logId(payload.id)} '
        'group=${_logId(groupId)}',
      );
    }
    _sharedExpenseLog(
      'processPendingApprovals done group=${_logId(groupId)} changed=$changed',
    );
    return changed;
  }

  Future<bool> isEngineReachable() => _engineClient.isReachable();

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _groupsKey,
      jsonEncode(groups.map((group) => group.toJson()).toList()),
    );
    _sharedExpenseLog('_saveGroups saved count=${groups.length}');
  }

  Future<String?> _readGroupKey(String groupId) {
    return _secureStorage.read(key: '$_groupKeyPrefix$groupId');
  }

  Future<void> _writeGroupKey(String groupId, String groupKeyHex) {
    _sharedExpenseLog('_writeGroupKey group=${_logId(groupId)}');
    return _secureStorage.write(
      key: '$_groupKeyPrefix$groupId',
      value: groupKeyHex,
    );
  }
}
