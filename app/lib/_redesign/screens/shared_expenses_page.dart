import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/transaction.dart' as totals;
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/services/totals_engine_sync_service.dart';

enum _SharedView { overview, transactions, activity }

enum _TransactionFilter { all, paidByMe, involvingMe }

class RedesignSharedExpensesPage extends StatefulWidget {
  const RedesignSharedExpensesPage({super.key});

  @override
  State<RedesignSharedExpensesPage> createState() =>
      _RedesignSharedExpensesPageState();
}

class _RedesignSharedExpensesPageState
    extends State<RedesignSharedExpensesPage> {
  static const _storageKey = 'redesign_shared_expense_groups_v1';
  static const _profileNameKey = 'redesign_shared_profile_name_v1';
  static const _profileColorKey = 'redesign_shared_profile_color_v1';

  final _random = Random();
  final _dateFormatter = DateFormat('dd MMM, HH:mm');
  final _sync = TotalsEngineSyncService.instance;
  final _accountRepository = AccountRepository();

  _SharedView _view = _SharedView.overview;
  _TransactionFilter _filter = _TransactionFilter.all;
  List<_SharedGroup> _groups = [];
  int _selectedGroupIndex = 0;
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _syncStatus;
  String? _localMemberId;
  String _localProfileName = 'You';
  int _localProfileColorValue = 0xFFE24A0A;

  String get _meId => _localMemberId ?? 'me';

  _SharedGroup? get _selectedGroup {
    if (_groups.isEmpty) return null;
    return _groups[_selectedGroupIndex.clamp(0, _groups.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final localMemberId = await _sync.devicePublicKeyHex();
    final prefs = await SharedPreferences.getInstance();
    final profile = await _loadLocalSharedProfile(prefs, localMemberId);
    final raw = prefs.getString(_storageKey);
    final loaded = <_SharedGroup>[];
    var didMigrate = false;

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          final group = _SharedGroup.fromJson(item as Map<String, dynamic>);
          final migrated = _applyLocalProfileToGroup(
            _migrateLegacyMember(group, localMemberId),
            profile,
            memberId: localMemberId,
          );
          loaded.add(migrated);
          didMigrate = didMigrate || migrated != group;
        }
      } catch (_) {
        loaded.clear();
      }
    }

    if (!mounted) return;
    setState(() {
      _localMemberId = localMemberId;
      _localProfileName = profile.name;
      _localProfileColorValue = profile.colorValue;
      _groups = loaded;
      _selectedGroupIndex =
          loaded.isEmpty ? 0 : _selectedGroupIndex.clamp(0, loaded.length - 1);
      _isLoading = false;
    });
    if (didMigrate) {
      await _saveGroups();
    }
  }

  Future<_SharedProfile> _loadLocalSharedProfile(
    SharedPreferences prefs,
    String localMemberId,
  ) async {
    final savedName = prefs.getString(_profileNameKey)?.trim();
    final savedColor = prefs.getInt(_profileColorKey);
    final name = savedName == null || savedName.isEmpty
        ? await _defaultProfileNameFromAccounts()
        : savedName;
    final colorValue = savedColor ?? _randomProfileColor(localMemberId);

    if (savedName == null || savedName.isEmpty) {
      await prefs.setString(_profileNameKey, name);
    }
    if (savedColor == null) {
      await prefs.setInt(_profileColorKey, colorValue);
    }

    return _SharedProfile(name: name, colorValue: colorValue);
  }

  Future<String> _defaultProfileNameFromAccounts() async {
    try {
      final accounts = await _accountRepository.getAccounts();
      final holderName = accounts
          .where((account) => account.bank != CashConstants.bankId)
          .map((account) => account.accountHolderName.trim())
          .firstWhere((name) => name.isNotEmpty, orElse: () => '');
      if (holderName.isNotEmpty) {
        return holderName.split(RegExp(r'\s+')).first;
      }
    } catch (_) {
      // Fall back to a neutral local name if accounts are unavailable.
    }
    return 'You';
  }

  int _randomProfileColor(String seed) {
    const colors = [
      0xFFE24A0A,
      0xFF0560B5,
      0xFF2F7D1A,
      0xFF6D5DF6,
      0xFFB45309,
      0xFF0F766E,
      0xFFBE185D,
    ];
    final offset = DateTime.now().microsecondsSinceEpoch + seed.hashCode;
    return colors[offset.abs() % colors.length];
  }

  _SharedProfile get _localProfile => _SharedProfile(
        name: _localProfileName,
        colorValue: _localProfileColorValue,
      );

  _SharedMember _localMember() => _SharedMember(
        id: _meId,
        name: _localProfileName,
        initial: _memberInitial(_localProfileName),
        colorValue: _localProfileColorValue,
      );

  _SharedGroup _applyLocalProfileToGroup(
    _SharedGroup group,
    _SharedProfile profile, {
    String? memberId,
  }) {
    final targetMemberId = memberId ?? _meId;
    final memberIndex =
        group.members.indexWhere((member) => member.id == targetMemberId);
    if (memberIndex == -1) {
      return group;
    }
    final targetInitial = _memberInitial(profile.name);
    final currentMember = group.members[memberIndex];
    if (currentMember.name == profile.name &&
        currentMember.initial == targetInitial &&
        currentMember.colorValue == profile.colorValue) {
      return group;
    }
    return group.copyWith(
      members: group.members
          .map(
            (member) => member.id == targetMemberId
                ? member.copyWith(
                    name: profile.name,
                    initial: targetInitial,
                    colorValue: profile.colorValue,
                  )
                : member,
          )
          .toList(),
    );
  }

  Future<void> _updateLocalProfile(_SharedProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileNameKey, profile.name);
    await prefs.setInt(_profileColorKey, profile.colorValue);
    final previousName = _localProfileName;

    final updatedGroups = _groups.map((group) {
      final updated = _applyLocalProfileToGroup(group, profile);
      return updated == group
          ? group
          : updated.copyWith(
              activities: [
                _activity(
                  action: 'profile_updated',
                  targetTitle: profile.name,
                  detail: previousName == profile.name
                      ? 'Changed profile color'
                      : 'Changed name from $previousName',
                ),
                ...updated.activities,
              ],
              revision: group.revision + 1,
            );
    }).toList();
    if (!mounted) return;
    setState(() {
      _localProfileName = profile.name;
      _localProfileColorValue = profile.colorValue;
      _groups = updatedGroups;
    });
    await _saveGroups();
    final group = _selectedGroup;
    if (group != null) _queueSync(group);
  }

  _SharedGroup _migrateLegacyMember(_SharedGroup group, String localMemberId) {
    const legacyId = 'me';
    if (legacyId == localMemberId ||
        !group.members.any((member) => member.id == legacyId)) {
      return group;
    }

    return group.copyWith(
      members: group.members
          .map((member) => member.id == legacyId
              ? member.copyWith(id: localMemberId)
              : member)
          .toList(),
      expenses: group.expenses
          .map(
            (expense) => expense.copyWith(
              paidBy:
                  expense.paidBy == legacyId ? localMemberId : expense.paidBy,
              participants: expense.participants
                  .map((id) => id == legacyId ? localMemberId : id)
                  .toList(),
            ),
          )
          .toList(),
      settlements: group.settlements
          .map(
            (settlement) => settlement.copyWith(
              from:
                  settlement.from == legacyId ? localMemberId : settlement.from,
              to: settlement.to == legacyId ? localMemberId : settlement.to,
            ),
          )
          .toList(),
      activities: group.activities
          .map(
            (activity) => activity.actorId == legacyId
                ? activity.copyWith(actorId: localMemberId)
                : activity,
          )
          .toList(),
    );
  }

  Future<void> _saveGroups() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_groups.map((group) => group.toJson()).toList()),
    );
  }

  String _newId(String prefix) {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = _random.nextInt(0xfffff).toRadixString(36);
    return '$prefix-$stamp-$suffix';
  }

  String _money(num value) {
    final rounded = value.round();
    final sign = rounded < 0 ? '-' : '';
    final digits = rounded.abs().toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
    return '${sign}ETB $digits';
  }

  String _compactMoney(num value) {
    final abs = value.abs();
    if (abs >= 1000) {
      final compact = (abs / 1000).toStringAsFixed(abs >= 10000 ? 0 : 1);
      return '${value < 0 ? '-' : ''}ETB ${compact.replaceAll('.0', '')}k';
    }
    return _money(value);
  }

  void _replaceSelectedGroup(_SharedGroup group) {
    final index = _selectedGroupIndex.clamp(0, _groups.length - 1);
    setState(() => _groups[index] = group);
    _saveGroups();
  }

  void _replaceGroupById(_SharedGroup group) {
    final index = _groups.indexWhere((item) => item.id == group.id);
    if (index == -1) return;
    setState(() => _groups[index] = group);
    _saveGroups();
  }

  void _queueSync(_SharedGroup group) {
    unawaited(_syncGroup(group, showSuccess: false));
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  _SharedActivity _activity({
    required String action,
    String? targetId,
    String? targetTitle,
    num? amount,
    String? detail,
    DateTime? createdAt,
  }) {
    return _SharedActivity(
      id: _newId('activity'),
      actorId: _meId,
      action: action,
      targetId: targetId,
      targetTitle: targetTitle,
      amount: amount,
      detail: detail,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  Future<_CreatedGroupResult> _createGroup({
    required String name,
  }) async {
    final cleanName = name.trim().isEmpty ? 'Shared group' : name.trim();
    final now = DateTime.now();
    final group = _SharedGroup(
      id: _newId('group'),
      name: cleanName,
      inviteCode:
          '${cleanName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${_random.nextInt(9999).toString().padLeft(4, '0')}',
      members: [_localMember()],
      expenses: const [],
      settlements: const [],
      activities: [
        _activity(
          action: 'group_created',
          targetTitle: cleanName,
          createdAt: now,
        ),
      ],
      createdAt: now,
    );

    setState(() {
      _groups = [..._groups, group];
      _selectedGroupIndex = _groups.length - 1;
      _view = _SharedView.overview;
    });
    await _saveGroups();

    try {
      final syncedGroup = await _ensureEngineGroup(group);
      _queueSync(syncedGroup);
      return _CreatedGroupResult(
        group: syncedGroup,
        inviteLink: _inviteLink(syncedGroup),
      );
    } catch (error) {
      _queueSync(group);
      return _CreatedGroupResult(
        group: group,
        errorMessage: _syncErrorMessage(error),
      );
    }
  }

  Future<bool> _joinGroup(String invite) async {
    final parsed = _parseInvite(invite);
    if (parsed == null) {
      _showSnack('Paste a Totals invite link with a group key');
      return false;
    }

    try {
      await _sync.joinGroup(parsed.groupId);
    } catch (error) {
      _showSnack(_syncErrorMessage(error));
      return false;
    }

    final group = _SharedGroup(
      id: _newId('group'),
      name: 'Shared group',
      inviteCode: parsed.groupId,
      members: [_localMember()],
      expenses: const [],
      settlements: const [],
      activities: [
        _activity(
          action: 'member_joined',
          detail: 'Joined from invite',
        ),
      ],
      createdAt: DateTime.now(),
      engineGroupId: parsed.groupId,
      groupKeyHex: parsed.groupKeyHex,
    );

    setState(() {
      _groups = [..._groups, group];
      _selectedGroupIndex = _groups.length - 1;
      _view = _SharedView.overview;
    });
    await _saveGroups();
    await _syncGroup(group, showSuccess: false);
    _showSnack('Joined group');
    return true;
  }

  _EngineInvite? _parseInvite(String invite) {
    final trimmed = invite.trim();
    if (trimmed.isEmpty) return null;

    try {
      final uri = Uri.parse(trimmed);
      if (uri.scheme == 'totals' && uri.host == 'join') {
        final groupId = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
        final fragmentParams = uri.fragment.isEmpty
            ? const <String, String>{}
            : Uri.splitQueryString(uri.fragment);
        final groupKeyHex =
            uri.queryParameters['key'] ?? fragmentParams['key'] ?? '';
        if (groupId.isNotEmpty && groupKeyHex.isNotEmpty) {
          return _EngineInvite(groupId: groupId, groupKeyHex: groupKeyHex);
        }
      }
    } catch (_) {
      // Fall through to the compact parser below.
    }

    final compactMatch = RegExp(r'^([0-9a-fA-F-]{36})[#?]key=([0-9a-fA-F]+)$')
        .firstMatch(trimmed);
    if (compactMatch == null) return null;
    return _EngineInvite(
      groupId: compactMatch.group(1)!,
      groupKeyHex: compactMatch.group(2)!,
    );
  }

  String _inviteLink(_SharedGroup group) {
    final engineGroupId = group.engineGroupId;
    final groupKeyHex = group.groupKeyHex;
    if (engineGroupId == null || groupKeyHex == null) {
      return 'totals://join/${group.inviteCode}';
    }
    return 'totals://join/$engineGroupId#key=$groupKeyHex';
  }

  Future<_SharedGroup> _ensureEngineGroup(_SharedGroup group) async {
    if (group.engineGroupId != null && group.groupKeyHex != null) {
      return group;
    }

    final engineGroupId = await _sync.createGroup();
    final updated = group.copyWith(
      inviteCode: engineGroupId,
      engineGroupId: engineGroupId,
      groupKeyHex: _sync.generateGroupKeyHex(),
    );
    if (mounted) {
      _replaceGroupById(updated);
    }
    return updated;
  }

  Future<void> _syncSelectedGroup({bool showSuccess = true}) async {
    final group = _selectedGroup;
    if (group == null) return;
    await _syncGroup(group, showSuccess: showSuccess);
  }

  Future<void> _syncGroup(
    _SharedGroup group, {
    required bool showSuccess,
  }) async {
    if (_isSyncing) return;

    if (mounted) {
      setState(() {
        _isSyncing = true;
        _syncStatus = 'Syncing...';
      });
    }

    try {
      var working = await _ensureEngineGroup(group);
      final engineGroupId = working.engineGroupId!;
      final groupKeyHex = working.groupKeyHex!;

      final pending = await _sync.pullEvents(
        groupId: engineGroupId,
        groupKeyHex: groupKeyHex,
      );

      for (final payload in pending) {
        final event = payload.event;
        if (event['schema'] == 'totals.sharedExpenses.v1' &&
            event['type'] == 'group_snapshot') {
          final rawGroup = event['group'];
          if (rawGroup is Map) {
            final remote = _SharedGroup.fromSyncJson(
              Map<String, dynamic>.from(rawGroup),
              localId: working.id,
              engineGroupId: engineGroupId,
              groupKeyHex: groupKeyHex,
            );
            working = _mergeGroupSnapshots(working, remote);
          }
        }
        await _sync.acknowledgePayload(payload.id);
      }

      final latestIndex = _groups.indexWhere((item) => item.id == working.id);
      if (latestIndex != -1) {
        working = _mergeGroupSnapshots(_groups[latestIndex], working);
      }

      final snapshotHash = _syncHash(working);
      if (snapshotHash != working.lastSyncedHash) {
        await _sync.submitEvent(
          groupId: engineGroupId,
          groupKeyHex: groupKeyHex,
          event: {
            'schema': 'totals.sharedExpenses.v1',
            'type': 'group_snapshot',
            'sentAt': DateTime.now().toIso8601String(),
            'group': working.toSyncJson(),
          },
        );
      }

      final synced = working.copyWith(
        lastSyncedHash: snapshotHash,
        lastSyncAt: DateTime.now(),
      );
      if (!mounted) return;
      _replaceGroupById(synced);
      setState(() {
        _syncStatus = 'Synced ${_dateFormatter.format(synced.lastSyncAt!)}';
      });
      if (showSuccess) {
        _showSnack('Shared group synced');
      }
    } catch (error) {
      final message = _syncErrorMessage(error);
      if (mounted) {
        setState(() => _syncStatus = message);
      }
      if (showSuccess) {
        _showSnack(message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  _SharedGroup _mergeGroupSnapshots(_SharedGroup local, _SharedGroup remote) {
    final membersById = <String, _SharedMember>{};
    for (final member in remote.members) {
      membersById[member.id] = member;
    }
    for (final member in local.members) {
      membersById[member.id] = member;
    }

    final remoteIsNewer = remote.revision > local.revision;
    final localIsNewer = local.revision > remote.revision;
    final expenses = remoteIsNewer
        ? remote.expenses
        : localIsNewer
            ? local.expenses
            : _mergeExpenses(local.expenses, remote.expenses);
    final settlements = remoteIsNewer
        ? remote.settlements
        : localIsNewer
            ? local.settlements
            : _mergeSettlements(local.settlements, remote.settlements);
    final activities = _mergeActivities(local.activities, remote.activities);
    final remoteName = remote.name.trim();

    return local.copyWith(
      name: remoteName.isNotEmpty &&
              (remoteIsNewer || local.name == 'Shared group')
          ? remoteName
          : local.name,
      members: membersById.values.toList(),
      expenses: [...expenses]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      settlements: [...settlements]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      activities: activities,
      revision: max(local.revision, remote.revision),
      engineGroupId: local.engineGroupId ?? remote.engineGroupId,
      groupKeyHex: local.groupKeyHex ?? remote.groupKeyHex,
      inviteCode:
          local.engineGroupId ?? remote.engineGroupId ?? local.inviteCode,
    );
  }

  List<_SharedExpense> _mergeExpenses(
    List<_SharedExpense> local,
    List<_SharedExpense> remote,
  ) {
    final byId = <String, _SharedExpense>{};
    for (final expense in remote) {
      byId[expense.id] = expense;
    }
    for (final expense in local) {
      byId[expense.id] = expense;
    }
    return byId.values.toList();
  }

  List<_Settlement> _mergeSettlements(
    List<_Settlement> local,
    List<_Settlement> remote,
  ) {
    final byId = <String, _Settlement>{};
    for (final settlement in remote) {
      byId[settlement.id] = settlement;
    }
    for (final settlement in local) {
      byId[settlement.id] = settlement;
    }
    return byId.values.toList();
  }

  List<_SharedActivity> _mergeActivities(
    List<_SharedActivity> local,
    List<_SharedActivity> remote,
  ) {
    final byId = <String, _SharedActivity>{};
    for (final activity in remote) {
      byId[activity.id] = activity;
    }
    for (final activity in local) {
      byId[activity.id] = activity;
    }
    return byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  String _syncHash(_SharedGroup group) => jsonEncode(group.toSyncJson());

  String _syncErrorMessage(Object error) {
    if (error is TotalsEngineException) {
      return 'Sync failed: ${error.message}';
    }
    return 'Sync failed: $error';
  }

  String _memberInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }

  Future<void> _flagTransactionAsShared({
    required totals.Transaction transaction,
    required String paidBy,
    required Set<String> participants,
  }) async {
    final group = _selectedGroup;
    if (group == null || participants.isEmpty) return;

    final reference = transaction.reference.trim();
    if (reference.isNotEmpty &&
        group.expenses.any(
          (expense) => expense.sourceTransactionReference == reference,
        )) {
      _showSnack('That transaction is already shared in this group');
      return;
    }

    final expense = _SharedExpense(
      id: _newId('expense'),
      title: _transactionTitle(transaction),
      amount: transaction.amount.abs(),
      paidBy: paidBy,
      participants: participants.toList(growable: false),
      createdAt: _transactionDate(transaction) ?? DateTime.now(),
      sourceTransactionReference: reference.isEmpty ? null : reference,
    );

    final updated = group.copyWith(
      expenses: [expense, ...group.expenses],
      activities: [
        _activity(
          action: 'expense_added',
          targetId: expense.id,
          targetTitle: expense.title,
          amount: expense.amount,
        ),
        ...group.activities,
      ],
      revision: group.revision + 1,
    );
    _replaceSelectedGroup(updated);
    _queueSync(updated);
    _showSnack('Transaction added');
  }

  Future<void> _deleteExpense(_SharedExpense expense) async {
    final group = _selectedGroup;
    if (group == null) return;
    final updated = group.copyWith(
      expenses: group.expenses.where((item) => item.id != expense.id).toList(),
      activities: [
        _activity(
          action: 'expense_deleted',
          targetId: expense.id,
          targetTitle: expense.title,
          amount: expense.amount,
        ),
        ...group.activities,
      ],
      revision: group.revision + 1,
    );
    _replaceSelectedGroup(updated);
    _queueSync(updated);
  }

  Future<void> _recordSettlement(_Debt debt) async {
    final group = _selectedGroup;
    if (group == null) return;
    final settlement = _Settlement(
      id: _newId('settlement'),
      from: debt.from,
      to: debt.to,
      amount: debt.amount,
      createdAt: DateTime.now(),
    );
    final updated = group.copyWith(
      settlements: [settlement, ...group.settlements],
      activities: [
        _activity(
          action: 'settlement_recorded',
          targetId: settlement.id,
          targetTitle:
              '${group.memberById(debt.from).name} paid ${group.memberById(debt.to).name}',
          amount: settlement.amount,
        ),
        ...group.activities,
      ],
      revision: group.revision + 1,
    );
    _replaceSelectedGroup(updated);
    _queueSync(updated);
    _showSnack('Settlement recorded');
  }

  _SharedSummary _summary(_SharedGroup group) {
    final balances = {for (final member in group.members) member.id: 0.0};

    for (final expense in group.expenses) {
      if (expense.participants.isEmpty) continue;
      final share = expense.amount / expense.participants.length;
      balances[expense.paidBy] =
          (balances[expense.paidBy] ?? 0) + expense.amount;
      for (final participant in expense.participants) {
        balances[participant] = (balances[participant] ?? 0) - share;
      }
    }

    for (final settlement in group.settlements) {
      balances[settlement.from] =
          (balances[settlement.from] ?? 0) + settlement.amount;
      balances[settlement.to] =
          (balances[settlement.to] ?? 0) - settlement.amount;
    }

    final debtors = balances.entries
        .where((entry) => entry.value < -0.5)
        .map((entry) => MapEntry(entry.key, -entry.value))
        .toList();
    final creditors = balances.entries
        .where((entry) => entry.value > 0.5)
        .map((entry) => MapEntry(entry.key, entry.value))
        .toList();
    final debts = <_Debt>[];
    var debtorIndex = 0;
    var creditorIndex = 0;

    while (debtorIndex < debtors.length && creditorIndex < creditors.length) {
      final debtor = debtors[debtorIndex];
      final creditor = creditors[creditorIndex];
      final amount = min(debtor.value, creditor.value);
      debts.add(_Debt(from: debtor.key, to: creditor.key, amount: amount));
      debtors[debtorIndex] = MapEntry(debtor.key, debtor.value - amount);
      creditors[creditorIndex] =
          MapEntry(creditor.key, creditor.value - amount);
      if (debtors[debtorIndex].value <= 0.5) debtorIndex++;
      if (creditors[creditorIndex].value <= 0.5) creditorIndex++;
    }

    return _SharedSummary(balances: balances, debts: debts);
  }

  List<_SharedExpense> _filteredExpenses(_SharedGroup group) {
    switch (_filter) {
      case _TransactionFilter.all:
        return group.expenses;
      case _TransactionFilter.paidByMe:
        return group.expenses
            .where((expense) => expense.paidBy == _meId)
            .toList();
      case _TransactionFilter.involvingMe:
        return group.expenses
            .where((expense) => expense.participants.contains(_meId))
            .toList();
    }
  }

  void _showCreateGroupSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateGroupSheet(
        onCreate: _createGroup,
        onJoin: _joinGroup,
      ),
    );
  }

  void _showJoinGroupSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JoinGroupSheet(onJoin: _joinGroup),
    );
  }

  void _showProfileSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SharedProfileSheet(
        profile: _localProfile,
        onSave: _updateLocalProfile,
      ),
    );
  }

  Future<void> _showInviteSheet(_SharedGroup group) async {
    _SharedGroup syncedGroup;
    try {
      syncedGroup = await _ensureEngineGroup(group);
    } catch (error) {
      _showSnack(_syncErrorMessage(error));
      return;
    }
    if (!mounted) return;
    final inviteLink = _inviteLink(syncedGroup);
    _queueSync(syncedGroup);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InviteSheet(
        group: syncedGroup,
        inviteLink: inviteLink,
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: inviteLink));
          if (!mounted) return;
          Navigator.pop(context);
          _showSnack('Invite link copied');
        },
      ),
    );
  }

  void _showAddExpenseSheet(_SharedGroup group) {
    final transactionProvider = context.read<TransactionProvider>();
    unawaited(transactionProvider.loadData());

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FlagTransactionSheet(
        group: group,
        localMemberId: _meId,
        formatMoney: _money,
        dateFormatter: _dateFormatter,
        onFlag: _flagTransactionAsShared,
      ),
    );
  }

  void _showSettleSheet(_SharedGroup group, _SharedSummary summary) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettleSheet(
        group: group,
        debts: summary.debts,
        formatMoney: _money,
        onRecord: _recordSettlement,
      ),
    );
  }

  void _showExpenseDetails(_SharedGroup group, _SharedExpense expense) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExpenseDetailsSheet(
        group: group,
        expense: expense,
        formatMoney: _money,
        dateFormatter: _dateFormatter,
        onDelete: () async {
          Navigator.pop(context);
          await _deleteExpense(expense);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = _selectedGroup;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      floatingActionButton: group == null || _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddExpenseSheet(group),
              backgroundColor: AppColors.primaryLight,
              foregroundColor: Colors.white,
              icon: const Icon(AppIcons.add),
              label: const Text(
                'Add transaction',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : group == null
                ? _EmptyGroupsView(
                    onCreateGroup: _showCreateGroupSheet,
                    onJoinGroup: _showJoinGroupSheet,
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _view == _SharedView.overview
                        ? _OverviewBody(
                            key: const ValueKey('overview'),
                            group: group,
                            groups: _groups,
                            selectedGroupIndex: _selectedGroupIndex,
                            summary: _summary(group),
                            formatMoney: _money,
                            compactMoney: _compactMoney,
                            dateFormatter: _dateFormatter,
                            localMemberId: _meId,
                            isSyncing: _isSyncing,
                            syncStatus: _syncStatus ??
                                (group.lastSyncAt == null
                                    ? 'Local changes sync when Totals Engine is reachable'
                                    : 'Synced ${_dateFormatter.format(group.lastSyncAt!)}'),
                            onGroupSelected: (index) {
                              setState(() => _selectedGroupIndex = index);
                            },
                            onAddGroup: _showCreateGroupSheet,
                            onAddExpense: () => _showAddExpenseSheet(group),
                            onInvite: () => _showInviteSheet(group),
                            onEditProfile: _showProfileSheet,
                            onSync: _syncSelectedGroup,
                            onShowActivity: () {
                              setState(() => _view = _SharedView.activity);
                            },
                            onDebtTap: (_) =>
                                _showSettleSheet(group, _summary(group)),
                            onShowTransactions: () {
                              setState(() => _view = _SharedView.transactions);
                            },
                            onExpenseTap: (expense) =>
                                _showExpenseDetails(group, expense),
                          )
                        : _view == _SharedView.transactions
                            ? _TransactionsBody(
                                key: const ValueKey('transactions'),
                                group: group,
                                expenses: _filteredExpenses(group),
                                filter: _filter,
                                formatMoney: _money,
                                dateFormatter: _dateFormatter,
                                onBack: () {
                                  setState(() => _view = _SharedView.overview);
                                },
                                onFilterChanged: (filter) {
                                  setState(() => _filter = filter);
                                },
                                onExpenseTap: (expense) =>
                                    _showExpenseDetails(group, expense),
                              )
                            : _ActivitiesBody(
                                key: const ValueKey('activity'),
                                group: group,
                                activities: group.activities,
                                formatMoney: _money,
                                dateFormatter: _dateFormatter,
                                onBack: () {
                                  setState(() => _view = _SharedView.overview);
                                },
                              ),
                  ),
      ),
    );
  }
}

class _EmptyGroupsView extends StatelessWidget {
  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;

  const _EmptyGroupsView({
    required this.onCreateGroup,
    required this.onJoinGroup,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Text(
          'Shared',
          style: theme.textTheme.titleLarge?.copyWith(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.cardColor(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  AppIcons.usersThree,
                  color: AppColors.primaryLight,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No shared groups yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a group for roommates, trips, or recurring bills. Add existing Totals transactions, then sync encrypted through Totals Engine.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _CompactButton(
                      icon: AppIcons.add,
                      label: 'Create',
                      filled: true,
                      onTap: onCreateGroup,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CompactButton(
                      icon: AppIcons.qr_code_scanner_rounded,
                      label: 'Join',
                      onTap: onJoinGroup,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewBody extends StatelessWidget {
  final _SharedGroup group;
  final List<_SharedGroup> groups;
  final int selectedGroupIndex;
  final _SharedSummary summary;
  final String Function(num value) formatMoney;
  final String Function(num value) compactMoney;
  final DateFormat dateFormatter;
  final String localMemberId;
  final bool isSyncing;
  final String syncStatus;
  final ValueChanged<int> onGroupSelected;
  final VoidCallback onAddGroup;
  final VoidCallback onAddExpense;
  final VoidCallback onInvite;
  final VoidCallback onEditProfile;
  final VoidCallback onSync;
  final VoidCallback onShowActivity;
  final ValueChanged<_Debt> onDebtTap;
  final VoidCallback onShowTransactions;
  final ValueChanged<_SharedExpense> onExpenseTap;

  const _OverviewBody({
    super.key,
    required this.group,
    required this.groups,
    required this.selectedGroupIndex,
    required this.summary,
    required this.formatMoney,
    required this.compactMoney,
    required this.dateFormatter,
    required this.localMemberId,
    required this.isSyncing,
    required this.syncStatus,
    required this.onGroupSelected,
    required this.onAddGroup,
    required this.onAddExpense,
    required this.onInvite,
    required this.onEditProfile,
    required this.onSync,
    required this.onShowActivity,
    required this.onDebtTap,
    required this.onShowTransactions,
    required this.onExpenseTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Shared',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                    _IconAction(
                      icon: AppIcons.person_outline_rounded,
                      onTap: onEditProfile,
                    ),
                    const SizedBox(width: 8),
                    _IconAction(
                      icon: AppIcons.schedule_rounded,
                      onTap: onShowActivity,
                    ),
                    const SizedBox(width: 8),
                    _IconAction(
                      icon: AppIcons.refresh,
                      onTap: isSyncing ? null : onSync,
                      busy: isSyncing,
                    ),
                    const SizedBox(width: 8),
                    _IconAction(
                      icon: AppIcons.qr_code_scanner_rounded,
                      onTap: onInvite,
                    ),
                    const SizedBox(width: 8),
                    _IconAction(
                      icon: AppIcons.add,
                      onTap: onAddExpense,
                      filled: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _BalanceBubbleMap(
                  group: group,
                  summary: summary,
                  compactMoney: compactMoney,
                  localMemberId: localMemberId,
                ),
                const SizedBox(height: 4),
                _GroupSelector(
                  groups: groups,
                  selectedIndex: selectedGroupIndex,
                  onSelected: onGroupSelected,
                  onAdd: onAddGroup,
                ),
                const SizedBox(height: 8),
                _SyncStatusPill(
                  status: syncStatus,
                  isSyncing: isSyncing,
                ),
                const SizedBox(height: 18),
                _SectionHeader(
                  title: 'Transactions',
                  action: group.expenses.isEmpty ? null : 'See all',
                  onTap: onShowTransactions,
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        if (group.expenses.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Center(
                child: Text(
                  'No expenses yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: min(3, group.expenses.length),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final expense = group.expenses[index];
                return _ExpenseTile(
                  expense: expense,
                  group: group,
                  formatMoney: formatMoney,
                  dateFormatter: dateFormatter,
                  onTap: () => onExpenseTap(expense),
                );
              },
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Text(
              'Debts',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (summary.debts.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Center(
                child: Text(
                  'Everyone is settled',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: _DebtSummaryPanel(
                debts: summary.debts,
                group: group,
                formatMoney: formatMoney,
                onDebtTap: onDebtTap,
              ),
            ),
          ),
      ],
    );
  }
}

class _TransactionsBody extends StatelessWidget {
  final _SharedGroup group;
  final List<_SharedExpense> expenses;
  final _TransactionFilter filter;
  final String Function(num value) formatMoney;
  final DateFormat dateFormatter;
  final VoidCallback onBack;
  final ValueChanged<_TransactionFilter> onFilterChanged;
  final ValueChanged<_SharedExpense> onExpenseTap;

  const _TransactionsBody({
    super.key,
    required this.group,
    required this.expenses,
    required this.filter,
    required this.formatMoney,
    required this.dateFormatter,
    required this.onBack,
    required this.onFilterChanged,
    required this.onExpenseTap,
  });

  Map<String, List<_SharedExpense>> _groupByMonth() {
    final formatter = DateFormat('MMMM yyyy');
    final result = <String, List<_SharedExpense>>{};
    for (final expense in expenses) {
      final key = formatter.format(expense.createdAt);
      result.putIfAbsent(key, () => []).add(expense);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = _groupByMonth();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.cardColor(context),
              border: Border(
                bottom: BorderSide(color: AppColors.borderColor(context)),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _IconAction(
                        icon: AppIcons.arrow_back_rounded, onTap: onBack),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Transactions',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Icon(
                      AppIcons.filter_list,
                      color: AppColors.textSecondary(context),
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _FilterPills(selected: filter, onChanged: onFilterChanged),
              ],
            ),
          ),
        ),
        if (expenses.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _SharedEmptyState(
              title: 'No matching expenses',
              subtitle: 'Try another filter or add another transaction.',
            ),
          )
        else
          for (final entry in sections.entries) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${entry.key} (${entry.value.length})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(
                        entry.value.fold<num>(
                          0,
                          (sum, expense) => sum + expense.amount,
                        ),
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.separated(
                itemCount: entry.value.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final expense = entry.value[index];
                  return _ExpenseTile(
                    expense: expense,
                    group: group,
                    formatMoney: formatMoney,
                    dateFormatter: dateFormatter,
                    onTap: () => onExpenseTap(expense),
                  );
                },
              ),
            ),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }
}

class _ActivitiesBody extends StatelessWidget {
  final _SharedGroup group;
  final List<_SharedActivity> activities;
  final String Function(num value) formatMoney;
  final DateFormat dateFormatter;
  final VoidCallback onBack;

  const _ActivitiesBody({
    super.key,
    required this.group,
    required this.activities,
    required this.formatMoney,
    required this.dateFormatter,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...activities]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.cardColor(context),
              border: Border(
                bottom: BorderSide(color: AppColors.borderColor(context)),
              ),
            ),
            child: Row(
              children: [
                _IconAction(icon: AppIcons.arrow_back_rounded, onTap: onBack),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Activity',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  AppIcons.schedule_rounded,
                  color: AppColors.textSecondary(context),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
        if (sorted.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _SharedEmptyState(
              title: 'No activity yet',
              subtitle:
                  'Flags, deletes, settlements, and profile updates appear here.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            sliver: SliverList.separated(
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _ActivityTile(
                  activity: sorted[index],
                  group: group,
                  formatMoney: formatMoney,
                  dateFormatter: dateFormatter,
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final _SharedActivity activity;
  final _SharedGroup group;
  final String Function(num value) formatMoney;
  final DateFormat dateFormatter;

  const _ActivityTile({
    required this.activity,
    required this.group,
    required this.formatMoney,
    required this.dateFormatter,
  });

  IconData get _icon {
    switch (activity.action) {
      case 'expense_added':
      case 'expense_flagged':
        return AppIcons.receipt_long_rounded;
      case 'expense_deleted':
        return AppIcons.delete_outline_rounded;
      case 'settlement_recorded':
        return AppIcons.swap;
      case 'profile_updated':
        return AppIcons.person_outline_rounded;
      case 'group_created':
      case 'member_joined':
        return AppIcons.usersThree;
      default:
        return AppIcons.info_outline_rounded;
    }
  }

  Color _tone(BuildContext context) {
    switch (activity.action) {
      case 'expense_deleted':
        return AppColors.red;
      case 'settlement_recorded':
        return AppColors.blue;
      case 'group_created':
      case 'member_joined':
        return AppColors.incomeSuccess;
      default:
        return AppColors.primaryLight;
    }
  }

  String _title() {
    final actor = group.memberById(activity.actorId).name;
    final target = activity.targetTitle?.trim();
    switch (activity.action) {
      case 'expense_added':
      case 'expense_flagged':
        return '$actor added ${target == null || target.isEmpty ? 'a transaction' : target}';
      case 'expense_deleted':
        return '$actor removed ${target == null || target.isEmpty ? 'a shared expense' : target}';
      case 'settlement_recorded':
        return '$actor recorded a settlement';
      case 'profile_updated':
        return '$actor updated their profile';
      case 'group_created':
        return '$actor created ${target == null || target.isEmpty ? 'this group' : target}';
      case 'member_joined':
        return '$actor joined the group';
      default:
        return '$actor updated the group';
    }
  }

  String _subtitle() {
    final parts = <String>[];
    if (activity.amount != null) {
      parts.add(formatMoney(activity.amount!));
    }
    final detail = activity.detail?.trim();
    if (detail != null && detail.isNotEmpty) {
      parts.add(detail);
    }
    parts.add(dateFormatter.format(activity.createdAt));
    return parts.join(' - ');
  }

  @override
  Widget build(BuildContext context) {
    final actor = group.memberById(activity.actorId);
    final tone = _tone(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        children: [
          _MemberAvatar(member: actor, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon, color: tone, size: 18),
          ),
        ],
      ),
    );
  }
}

class _GroupSelector extends StatelessWidget {
  final List<_SharedGroup> groups;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onAdd;

  const _GroupSelector({
    required this.groups,
    required this.selectedIndex,
    required this.onSelected,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == groups.length) {
            return _GroupChip(
              label: '',
              selected: false,
              icon: AppIcons.add,
              onTap: onAdd,
            );
          }

          return _GroupChip(
            label: groups[index].name,
            selected: index == selectedIndex,
            onTap: () => onSelected(index),
          );
        },
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  const _GroupChip({
    required this.label,
    required this.selected,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppColors.primaryLight : AppColors.textSecondary(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 38,
          constraints: icon == null
              ? const BoxConstraints(minWidth: 52, maxWidth: 132)
              : const BoxConstraints.tightFor(width: 38),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: selected
                ? Border(bottom: BorderSide(color: color, width: 2))
                : null,
          ),
          child: icon == null
              ? Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                )
              : Icon(icon, color: AppColors.textSecondary(context), size: 20),
        ),
      ),
    );
  }
}

class _BalanceBubbleMap extends StatelessWidget {
  final _SharedGroup group;
  final _SharedSummary summary;
  final String Function(num value) compactMoney;
  final String localMemberId;

  const _BalanceBubbleMap({
    required this.group,
    required this.summary,
    required this.compactMoney,
    required this.localMemberId,
  });

  @override
  Widget build(BuildContext context) {
    final entries = group.members
        .map((member) => MapEntry(member, summary.balances[member.id] ?? 0.0))
        .where((entry) => entry.value.abs() > 0.5)
        .toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    if (entries.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(
          child: _BalanceBubble(
            member: group.members.firstWhere(
              (member) => member.id == localMemberId,
              orElse: () => group.members.first,
            ),
            balance: 0,
            size: 154,
            compactMoney: compactMoney,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final visible = entries.take(3).toList(growable: false);
        final bubbleSpecs = [
          _BubbleSpec(size: 172, left: (width - 172) / 2, top: 56),
          const _BubbleSpec(size: 104, left: 18, top: 16),
          _BubbleSpec(size: 120, left: max(width - 142, 0), top: 6),
        ];

        return SizedBox(
          height: 258,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var index = visible.length - 1; index >= 0; index--)
                Positioned(
                  left: bubbleSpecs[index].left,
                  top: bubbleSpecs[index].top,
                  child: _BalanceBubble(
                    member: visible[index].key,
                    balance: visible[index].value,
                    size: bubbleSpecs[index].size,
                    compactMoney: compactMoney,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BubbleSpec {
  final double size;
  final double left;
  final double top;

  const _BubbleSpec({
    required this.size,
    required this.left,
    required this.top,
  });
}

class _BalanceBubble extends StatelessWidget {
  final _SharedMember member;
  final num balance;
  final double size;
  final String Function(num value) compactMoney;

  const _BalanceBubble({
    required this.member,
    required this.balance,
    required this.size,
    required this.compactMoney,
  });

  @override
  Widget build(BuildContext context) {
    final isEven = balance.abs() <= 0.5;
    final isDebtor = balance < -0.5;
    final fill = isEven
        ? AppColors.incomeSuccess
        : isDebtor
            ? member.color
            : member.color;
    final amount = isEven
        ? 'settled'
        : isDebtor
            ? '-${compactMoney(balance.abs())}'
            : compactMoney(balance);
    final label = isEven
        ? 'even'
        : isDebtor
            ? 'should pay'
            : 'gets back';

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill.withValues(alpha: AppColors.isDark(context) ? 0.72 : 0.84),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.84),
                    fontSize: size * 0.15,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            SizedBox(height: size * 0.06),
            Text(
              amount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontSize: size * 0.12,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            if (size >= 140) ...[
              SizedBox(height: size * 0.08),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: size * 0.11,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncStatusPill extends StatelessWidget {
  final String status;
  final bool isSyncing;

  const _SyncStatusPill({
    required this.status,
    required this.isSyncing,
  });

  @override
  Widget build(BuildContext context) {
    final isError = status.toLowerCase().contains('failed');
    final tone = isError
        ? AppColors.red
        : isSyncing
            ? AppColors.blue
            : AppColors.textSecondary(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? AppIcons.wifi_off : AppIcons.shield_check,
            color: tone,
            size: 14,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final _SharedExpense expense;
  final _SharedGroup group;
  final String Function(num value) formatMoney;
  final DateFormat dateFormatter;
  final VoidCallback onTap;

  const _ExpenseTile({
    required this.expense,
    required this.group,
    required this.formatMoney,
    required this.dateFormatter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final payer = group.memberById(expense.paidBy);

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              _MemberAvatar(member: payer, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      expense.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateFormatter.format(expense.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${payer.name} paid',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(expense.amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 10),
                  _ParticipantStack(
                    members: [
                      for (final id in expense.participants)
                        group.memberById(id),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebtSummaryPanel extends StatelessWidget {
  final List<_Debt> debts;
  final _SharedGroup group;
  final String Function(num value) formatMoney;
  final ValueChanged<_Debt>? onDebtTap;

  const _DebtSummaryPanel({
    required this.debts,
    required this.group,
    required this.formatMoney,
    this.onDebtTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < debts.length; index++) ...[
            _DebtSummaryRow(
              debt: debts[index],
              group: group,
              formatMoney: formatMoney,
              onTap: onDebtTap == null ? null : () => onDebtTap!(debts[index]),
            ),
            if (index != debts.length - 1)
              Divider(
                height: 14,
                color: AppColors.borderColor(context).withValues(alpha: 0.7),
              ),
          ],
        ],
      ),
    );
  }
}

class _DebtSummaryRow extends StatelessWidget {
  final _Debt debt;
  final _SharedGroup group;
  final String Function(num value) formatMoney;
  final VoidCallback? onTap;

  const _DebtSummaryRow({
    required this.debt,
    required this.group,
    required this.formatMoney,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final from = group.memberById(debt.from);
    final to = group.memberById(debt.to);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _MemberAvatar(member: from, size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      from.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      formatMoney(debt.amount),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                AppIcons.arrow_forward,
                color: AppColors.textPrimary(context),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  to.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 10),
              _MemberAvatar(member: to, size: 44),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  final _Debt debt;
  final _SharedGroup group;
  final String Function(num value) formatMoney;
  final VoidCallback? onRecord;

  const _DebtTile({
    required this.debt,
    required this.group,
    required this.formatMoney,
    this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    final from = group.memberById(debt.from);
    final to = group.memberById(debt.to);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        children: [
          _MemberAvatar(member: from, size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  from.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  formatMoney(debt.amount),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          Icon(
            AppIcons.arrow_forward,
            color: AppColors.textPrimary(context),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              to.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          _MemberAvatar(member: to, size: 42),
          if (onRecord != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onRecord,
              icon: const Icon(
                AppIcons.check_circle_rounded,
                color: AppColors.primaryLight,
                size: 22,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ParticipantStack extends StatelessWidget {
  final List<_SharedMember> members;

  const _ParticipantStack({required this.members});

  @override
  Widget build(BuildContext context) {
    final visible = members.take(3).toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: 22.0 + (visible.length - 1).clamp(0, 2) * 18,
      height: 24,
      child: Stack(
        children: [
          for (var index = 0; index < visible.length; index++)
            Positioned(
              left: index * 18,
              child: _MemberAvatar(member: visible[index], size: 24),
            ),
        ],
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  final _SharedMember member;
  final double size;

  const _MemberAvatar({required this.member, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: member.color,
        border: Border.all(
          color: AppColors.cardColor(context),
          width: size <= 26 ? 1.5 : 0,
        ),
      ),
      child: Text(
        member.initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onTap;

  const _SectionHeader({required this.title, this.action, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              action!,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool busy;

  const _IconAction({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Material(
      color: filled
          ? AppColors.primaryLight
          : AppColors.cardColor(context).withValues(alpha: enabled ? 1 : 0.6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
          ),
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color:
                        filled ? Colors.white : AppColors.textPrimary(context),
                  ),
                )
              : Icon(
                  icon,
                  color: filled
                      ? Colors.white
                      : AppColors.textPrimary(context)
                          .withValues(alpha: enabled ? 1 : 0.45),
                  size: 20,
                ),
        ),
      ),
    );
  }
}

class _CompactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  const _CompactButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Material(
      color: filled
          ? AppColors.primaryLight
          : AppColors.cardColor(context).withValues(alpha: enabled ? 1 : 0.55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: filled
                  ? AppColors.primaryLight
                  : AppColors.borderColor(context),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: filled
                    ? Colors.white
                    : enabled
                        ? AppColors.primaryLight
                        : AppColors.textTertiary(context),
                size: 18,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: filled
                            ? Colors.white
                            : enabled
                                ? AppColors.textPrimary(context)
                                : AppColors.textTertiary(context),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  final _TransactionFilter selected;
  final ValueChanged<_TransactionFilter> onChanged;

  const _FilterPills({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final filters = [
      (_TransactionFilter.all, 'All'),
      (_TransactionFilter.paidByMe, 'Paid by me'),
      (_TransactionFilter.involvingMe, 'Mine'),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index].$1;
          final label = filters[index].$2;
          final isSelected = filter == selected;

          return ChoiceChip(
            selected: isSelected,
            label: Text(label),
            onSelected: (_) => onChanged(filter),
            selectedColor: AppColors.primaryLight.withValues(alpha: 0.14),
            backgroundColor: AppColors.surfaceColor(context),
            side: BorderSide(
              color: isSelected
                  ? AppColors.primaryLight
                  : AppColors.borderColor(context),
            ),
            labelStyle: TextStyle(
              color: isSelected
                  ? AppColors.primaryLight
                  : AppColors.textSecondary(context),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          );
        },
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InlineEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textTertiary(context), size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
          ),
        ],
      ),
    );
  }
}

class _SharedEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SharedEmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.receipt_long_rounded,
              color: AppColors.textTertiary(context),
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BaseSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _BaseSheet({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.cardColor(context),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
            border:
                Border(top: BorderSide(color: AppColors.borderColor(context))),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.mutedFill(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child:
                          Icon(icon, color: AppColors.primaryLight, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppColors.textPrimary(context),
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        AppIcons.close_rounded,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SharedProfileSheet extends StatefulWidget {
  final _SharedProfile profile;
  final Future<void> Function(_SharedProfile profile) onSave;

  const _SharedProfileSheet({
    required this.profile,
    required this.onSave,
  });

  @override
  State<_SharedProfileSheet> createState() => _SharedProfileSheetState();
}

class _SharedProfileSheetState extends State<_SharedProfileSheet> {
  late final TextEditingController _nameController;
  late int _colorValue;
  bool _isSaving = false;

  static const _colors = [
    0xFFE24A0A,
    0xFF0560B5,
    0xFF2F7D1A,
    0xFF6D5DF6,
    0xFFB45309,
    0xFF0F766E,
    0xFFBE185D,
    0xFF3B82F6,
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _colorValue = widget.profile.colorValue;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim().isEmpty
        ? 'You'
        : _nameController.text.trim();
    setState(() => _isSaving = true);
    try {
      await widget.onSave(
        _SharedProfile(name: name, colorValue: _colorValue),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _SharedMember(
      id: 'preview',
      name: _nameController.text.trim().isEmpty
          ? 'You'
          : _nameController.text.trim(),
      initial: _nameController.text.trim().isEmpty
          ? 'Y'
          : _nameController.text.trim().characters.first.toUpperCase(),
      colorValue: _colorValue,
    );

    return _BaseSheet(
      title: 'Shared profile',
      icon: AppIcons.person_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MemberAvatar(member: preview, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This name and color appear in shared groups on this device.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SheetTextField(
            controller: _nameController,
            label: 'Name',
            hint: 'Your name',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          const _SheetLabel('Color'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final colorValue in _colors)
                _ProfileColorSwatch(
                  colorValue: colorValue,
                  selected: colorValue == _colorValue,
                  onTap: () => setState(() => _colorValue = colorValue),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _isSaving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(_isSaving ? 'Saving...' : 'Save profile'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileColorSwatch extends StatelessWidget {
  final int colorValue;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileColorSwatch({
    required this.colorValue,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? AppColors.textPrimary(context) : Colors.white,
            width: selected ? 3 : 2,
          ),
        ),
        child: selected
            ? const Icon(AppIcons.check_rounded, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}

enum _GroupSheetMode { create, join }

class _CreateGroupSheet extends StatefulWidget {
  final Future<_CreatedGroupResult> Function({
    required String name,
  }) onCreate;
  final Future<bool> Function(String invite) onJoin;

  const _CreateGroupSheet({
    required this.onCreate,
    required this.onJoin,
  });

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameController = TextEditingController();
  final _inviteController = TextEditingController();
  _GroupSheetMode _mode = _GroupSheetMode.create;
  _CreatedGroupResult? _createdResult;
  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final result = await widget.onCreate(name: _nameController.text);
    if (!mounted) return;
    setState(() {
      _createdResult = result;
      _isBusy = false;
      _error = result.errorMessage;
    });
  }

  Future<void> _join() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final joined = await widget.onJoin(_inviteController.text);
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (!joined || !context.mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final createdResult = _createdResult;

    return _BaseSheet(
      title: createdResult == null ? 'Shared group' : 'Group details',
      icon: createdResult == null
          ? AppIcons.usersThree
          : AppIcons.check_circle_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (createdResult == null) ...[
            _GroupSheetModeSwitch(
              selected: _mode,
              onChanged: (mode) => setState(() {
                _mode = mode;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_mode == _GroupSheetMode.create) ...[
              _SheetTextField(
                controller: _nameController,
                label: 'Group name',
                hint: 'Weekend trip',
              ),
              const SizedBox(height: 14),
              _CompactButton(
                icon: AppIcons.add,
                label: _isBusy ? 'Creating...' : 'Create group',
                filled: true,
                onTap: _isBusy ? null : _create,
              ),
            ] else ...[
              _SheetTextField(
                controller: _inviteController,
                label: 'Invite link',
                hint: 'totals://join/group-id#key=...',
              ),
              const SizedBox(height: 14),
              _CompactButton(
                icon: AppIcons.check_rounded,
                label: _isBusy ? 'Joining...' : 'Join group',
                filled: true,
                onTap: _isBusy ? null : _join,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _SheetNotice(message: _error!),
            ],
          ] else
            _CreatedGroupDetails(result: createdResult),
        ],
      ),
    );
  }
}

class _GroupSheetModeSwitch extends StatelessWidget {
  final _GroupSheetMode selected;
  final ValueChanged<_GroupSheetMode> onChanged;

  const _GroupSheetModeSwitch({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.mutedFill(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _GroupSheetModeButton(
            label: 'Create',
            icon: AppIcons.add,
            selected: selected == _GroupSheetMode.create,
            onTap: () => onChanged(_GroupSheetMode.create),
          ),
          const SizedBox(width: 4),
          _GroupSheetModeButton(
            label: 'Join',
            icon: AppIcons.qr_code_scanner_rounded,
            selected: selected == _GroupSheetMode.join,
            onTap: () => onChanged(_GroupSheetMode.join),
          ),
        ],
      ),
    );
  }
}

class _GroupSheetModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _GroupSheetModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? AppColors.primaryLight : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? Colors.white
                      : AppColors.textSecondary(context),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: selected
                            ? Colors.white
                            : AppColors.textSecondary(context),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreatedGroupDetails extends StatelessWidget {
  final _CreatedGroupResult result;

  const _CreatedGroupDetails({required this.result});

  Future<void> _copy(BuildContext context) async {
    final inviteLink = result.inviteLink;
    if (inviteLink == null || inviteLink.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: inviteLink));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite link copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inviteLink = result.inviteLink;
    final group = result.group;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.incomeSuccess.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                AppIcons.check_circle_rounded,
                color: AppColors.incomeSuccess,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  Text(
                    '${group.members.length} member - ${group.expenses.length} transactions',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _GroupDetailRow(
            label: 'Group ID', value: group.engineGroupId ?? group.inviteCode),
        const SizedBox(height: 8),
        _GroupDetailRow(
          label: 'Invite link',
          value: inviteLink ?? 'Totals Engine is not reachable yet',
        ),
        if (result.errorMessage != null) ...[
          const SizedBox(height: 12),
          _SheetNotice(message: result.errorMessage!),
        ],
        const SizedBox(height: 14),
        _CompactButton(
          icon: AppIcons.copy,
          label: 'Copy invite link',
          filled: true,
          onTap: inviteLink == null ? null : () => _copy(context),
        ),
      ],
    );
  }
}

class _GroupDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _GroupDetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _SheetNotice extends StatelessWidget {
  final String message;

  const _SheetNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _JoinGroupSheet extends StatefulWidget {
  final Future<bool> Function(String invite) onJoin;

  const _JoinGroupSheet({required this.onJoin});

  @override
  State<_JoinGroupSheet> createState() => _JoinGroupSheetState();
}

class _JoinGroupSheetState extends State<_JoinGroupSheet> {
  final _inviteController = TextEditingController();

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _BaseSheet(
      title: 'Join group',
      icon: AppIcons.qr_code_scanner_rounded,
      child: Column(
        children: [
          _SheetTextField(
            controller: _inviteController,
            label: 'Invite link or code',
            hint: 'totals://join/weekend-trip-1234',
          ),
          const SizedBox(height: 14),
          _CompactButton(
            icon: AppIcons.check_rounded,
            label: 'Join locally',
            filled: true,
            onTap: () async {
              final joined = await widget.onJoin(_inviteController.text);
              if (!context.mounted) return;
              if (!joined) return;
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _FlagTransactionSheet extends StatefulWidget {
  final _SharedGroup group;
  final String localMemberId;
  final String Function(num value) formatMoney;
  final DateFormat dateFormatter;
  final Future<void> Function({
    required totals.Transaction transaction,
    required String paidBy,
    required Set<String> participants,
  }) onFlag;

  const _FlagTransactionSheet({
    required this.group,
    required this.localMemberId,
    required this.formatMoney,
    required this.dateFormatter,
    required this.onFlag,
  });

  @override
  State<_FlagTransactionSheet> createState() => _FlagTransactionSheetState();
}

class _FlagTransactionSheetState extends State<_FlagTransactionSheet> {
  final _searchController = TextEditingController();
  totals.Transaction? _selectedTransaction;
  late String _paidBy = widget.group.members
      .firstWhere(
        (member) => member.id == widget.localMemberId,
        orElse: () => widget.group.members.first,
      )
      .id;
  late Set<String> _participants =
      widget.group.members.map((member) => member.id).toSet();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<totals.Transaction> _availableTransactions(
    TransactionProvider provider,
  ) {
    final flaggedReferences = widget.group.expenses
        .map((expense) => expense.sourceTransactionReference)
        .whereType<String>()
        .toSet();
    final query = _searchController.text.trim().toLowerCase();

    return provider.allTransactions.where((transaction) {
      if (transaction.type != 'DEBIT') return false;
      if (flaggedReferences.contains(transaction.reference)) return false;
      if (query.isEmpty) return true;
      final searchable = [
        _transactionTitle(transaction),
        transaction.reference,
        transaction.receiver,
        transaction.note,
        provider.getBankShortName(transaction.bankId),
      ].whereType<String>().join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final transactions = _availableTransactions(provider);
    final selected = _selectedTransaction;

    return _BaseSheet(
      title: 'Add transaction',
      icon: AppIcons.receipt_long_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetTextField(
            controller: _searchController,
            label: 'Search transactions',
            hint: 'Merchant, note, reference',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: provider.isLoading && provider.allTransactions.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : transactions.isEmpty
                    ? const _InlineEmptyState(
                        icon: AppIcons.receipt_long_rounded,
                        title: 'No unshared transactions',
                        subtitle:
                            'Import bank transactions first, or clear the search.',
                      )
                    : ListView.separated(
                        itemCount: min(transactions.length, 40),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final transaction = transactions[index];
                          final isSelected =
                              selected?.reference == transaction.reference;
                          return _TransactionPickTile(
                            transaction: transaction,
                            selected: isSelected,
                            formatMoney: widget.formatMoney,
                            dateFormatter: widget.dateFormatter,
                            bankLabel:
                                provider.getBankShortName(transaction.bankId),
                            onTap: () {
                              setState(() {
                                _selectedTransaction = transaction;
                              });
                            },
                          );
                        },
                      ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 12),
            const _SheetLabel('Paid by'),
            const SizedBox(height: 8),
            _MemberPicker(
              members: widget.group.members,
              selectedId: _paidBy,
              onSelected: (id) => setState(() => _paidBy = id),
            ),
            const SizedBox(height: 12),
            const _SheetLabel('Split among'),
            const SizedBox(height: 8),
            _ParticipantPicker(
              members: widget.group.members,
              selectedIds: _participants,
              onChanged: (ids) => setState(() => _participants = ids),
            ),
          ],
          const SizedBox(height: 14),
          _CompactButton(
            icon: AppIcons.check_rounded,
            label:
                selected == null ? 'Select a transaction' : 'Add transaction',
            filled: true,
            onTap: selected == null || _participants.isEmpty
                ? null
                : () async {
                    await widget.onFlag(
                      transaction: selected,
                      paidBy: _paidBy,
                      participants: _participants,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
          ),
        ],
      ),
    );
  }
}

class _TransactionPickTile extends StatelessWidget {
  final totals.Transaction transaction;
  final bool selected;
  final String Function(num value) formatMoney;
  final DateFormat dateFormatter;
  final String bankLabel;
  final VoidCallback onTap;

  const _TransactionPickTile({
    required this.transaction,
    required this.selected,
    required this.formatMoney,
    required this.dateFormatter,
    required this.bankLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = _transactionDate(transaction);

    return Material(
      color: selected
          ? AppColors.primaryLight.withValues(alpha: 0.14)
          : AppColors.surfaceColor(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.primaryLight
                  : AppColors.borderColor(context),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.blue,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  bankLabel.trim().isEmpty
                      ? 'T'
                      : bankLabel.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _transactionTitle(transaction),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      date == null
                          ? bankLabel
                          : '$bankLabel - ${dateFormatter.format(date)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatMoney(transaction.amount.abs()),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettleSheet extends StatelessWidget {
  final _SharedGroup group;
  final List<_Debt> debts;
  final String Function(num value) formatMoney;
  final Future<void> Function(_Debt debt) onRecord;

  const _SettleSheet({
    required this.group,
    required this.debts,
    required this.formatMoney,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    return _BaseSheet(
      title: 'Settle balances',
      icon: AppIcons.swap,
      child: debts.isEmpty
          ? const _InlineEmptyState(
              icon: AppIcons.check_circle_rounded,
              title: 'Nothing to settle',
              subtitle: 'Everyone is even in this group.',
            )
          : Column(
              children: [
                for (final debt in debts) ...[
                  _DebtTile(
                    debt: debt,
                    group: group,
                    formatMoney: formatMoney,
                    onRecord: () async {
                      await onRecord(debt);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }
}

class _InviteSheet extends StatelessWidget {
  final _SharedGroup group;
  final String inviteLink;
  final VoidCallback onCopy;

  const _InviteSheet({
    required this.group,
    required this.inviteLink,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return _BaseSheet(
      title: 'Invite to ${group.name}',
      icon: AppIcons.qr_code_scanner_rounded,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: Column(
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: AppColors.cardColor(context),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 3,
                    ),
                    itemCount: 49,
                    itemBuilder: (context, index) {
                      final filled = (index * 7 + group.name.length) % 5 != 0;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: filled
                              ? AppColors.textPrimary(context)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  inviteLink,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CompactButton(
            icon: AppIcons.copy,
            label: 'Copy invite link',
            filled: true,
            onTap: onCopy,
          ),
        ],
      ),
    );
  }
}

class _ExpenseDetailsSheet extends StatelessWidget {
  final _SharedGroup group;
  final _SharedExpense expense;
  final String Function(num value) formatMoney;
  final DateFormat dateFormatter;
  final VoidCallback onDelete;

  const _ExpenseDetailsSheet({
    required this.group,
    required this.expense,
    required this.formatMoney,
    required this.dateFormatter,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final payer = group.memberById(expense.paidBy);

    return _BaseSheet(
      title: expense.title,
      icon: AppIcons.receipt_long_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MemberAvatar(member: payer, size: 46),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatMoney(expense.amount),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      '${payer.name} paid - ${dateFormatter.format(expense.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (expense.sourceTransactionReference != null) ...[
            const SizedBox(height: 12),
            _ReferencePill(reference: expense.sourceTransactionReference!),
          ],
          const SizedBox(height: 14),
          const _SheetLabel('Split among'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in expense.participants)
                _MemberToken(member: group.memberById(id)),
            ],
          ),
          const SizedBox(height: 16),
          _CompactButton(
            icon: AppIcons.delete_outline_rounded,
            label: 'Remove shared flag',
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _ReferencePill extends StatelessWidget {
  final String reference;

  const _ReferencePill({required this.reference});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppIcons.receipt_long_rounded,
            size: 16,
            color: AppColors.textSecondary(context),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Totals transaction $reference',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary(context),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String>? onChanged;

  const _SheetTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.next,
      style: TextStyle(
        color: AppColors.textPrimary(context),
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.surfaceColor(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primaryLight),
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  final String text;

  const _SheetLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _MemberPicker extends StatelessWidget {
  final List<_SharedMember> members;
  final String selectedId;
  final ValueChanged<String> onSelected;

  const _MemberPicker({
    required this.members,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final member in members)
          ChoiceChip(
            selected: member.id == selectedId,
            label: Text(member.name),
            avatar: _MemberAvatar(member: member, size: 22),
            onSelected: (_) => onSelected(member.id),
            selectedColor: AppColors.primaryLight.withValues(alpha: 0.14),
            backgroundColor: AppColors.surfaceColor(context),
            side: BorderSide(color: AppColors.borderColor(context)),
          ),
      ],
    );
  }
}

class _ParticipantPicker extends StatelessWidget {
  final List<_SharedMember> members;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  const _ParticipantPicker({
    required this.members,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final member in members)
          FilterChip(
            selected: selectedIds.contains(member.id),
            label: Text(member.name),
            avatar: _MemberAvatar(member: member, size: 22),
            onSelected: (selected) {
              final next = {...selectedIds};
              if (selected) {
                next.add(member.id);
              } else {
                next.remove(member.id);
              }
              onChanged(next);
            },
            selectedColor: AppColors.primaryLight.withValues(alpha: 0.14),
            backgroundColor: AppColors.surfaceColor(context),
            side: BorderSide(color: AppColors.borderColor(context)),
          ),
      ],
    );
  }
}

class _MemberToken extends StatelessWidget {
  final _SharedMember member;

  const _MemberToken({required this.member});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MemberAvatar(member: member, size: 22),
          const SizedBox(width: 6),
          Text(
            member.name,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

String _transactionTitle(totals.Transaction transaction) {
  final candidates = <String?>[
    transaction.note,
    transaction.receiver,
    transaction.creditor,
    transaction.reference,
  ];

  for (final candidate in candidates) {
    final value = candidate?.trim();
    if (value != null && value.isNotEmpty) return value;
  }

  return 'Shared transaction';
}

DateTime? _transactionDate(totals.Transaction transaction) {
  final raw = transaction.time;
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw);
}

class _EngineInvite {
  final String groupId;
  final String groupKeyHex;

  const _EngineInvite({
    required this.groupId,
    required this.groupKeyHex,
  });
}

class _CreatedGroupResult {
  final _SharedGroup group;
  final String? inviteLink;
  final String? errorMessage;

  const _CreatedGroupResult({
    required this.group,
    this.inviteLink,
    this.errorMessage,
  });
}

class _SharedProfile {
  final String name;
  final int colorValue;

  const _SharedProfile({
    required this.name,
    required this.colorValue,
  });
}

class _SharedSummary {
  final Map<String, double> balances;
  final List<_Debt> debts;

  const _SharedSummary({
    required this.balances,
    required this.debts,
  });
}

class _SharedGroup {
  final String id;
  final String name;
  final String inviteCode;
  final List<_SharedMember> members;
  final List<_SharedExpense> expenses;
  final List<_Settlement> settlements;
  final List<_SharedActivity> activities;
  final DateTime createdAt;
  final int revision;
  final String? engineGroupId;
  final String? groupKeyHex;
  final String? lastSyncedHash;
  final DateTime? lastSyncAt;

  const _SharedGroup({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.members,
    required this.expenses,
    required this.settlements,
    this.activities = const [],
    required this.createdAt,
    this.revision = 0,
    this.engineGroupId,
    this.groupKeyHex,
    this.lastSyncedHash,
    this.lastSyncAt,
  });

  num get totalSpent =>
      expenses.fold<num>(0, (sum, expense) => sum + expense.amount);

  _SharedMember memberById(String id) => members.firstWhere(
        (member) => member.id == id,
        orElse: () => _SharedMember(
          id: id,
          name: 'Unknown',
          initial: '?',
          colorValue: 0xFF6B7280,
        ),
      );

  _SharedGroup copyWith({
    String? id,
    String? name,
    String? inviteCode,
    List<_SharedMember>? members,
    List<_SharedExpense>? expenses,
    List<_Settlement>? settlements,
    List<_SharedActivity>? activities,
    DateTime? createdAt,
    int? revision,
    String? engineGroupId,
    String? groupKeyHex,
    String? lastSyncedHash,
    DateTime? lastSyncAt,
  }) {
    return _SharedGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      inviteCode: inviteCode ?? this.inviteCode,
      members: members ?? this.members,
      expenses: expenses ?? this.expenses,
      settlements: settlements ?? this.settlements,
      activities: activities ?? this.activities,
      createdAt: createdAt ?? this.createdAt,
      revision: revision ?? this.revision,
      engineGroupId: engineGroupId ?? this.engineGroupId,
      groupKeyHex: groupKeyHex ?? this.groupKeyHex,
      lastSyncedHash: lastSyncedHash ?? this.lastSyncedHash,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'inviteCode': inviteCode,
        'members': members.map((member) => member.toJson()).toList(),
        'expenses': expenses.map((expense) => expense.toJson()).toList(),
        'settlements':
            settlements.map((settlement) => settlement.toJson()).toList(),
        'activities': activities.map((activity) => activity.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'revision': revision,
        'engineGroupId': engineGroupId,
        'groupKeyHex': groupKeyHex,
        'lastSyncedHash': lastSyncedHash,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
      };

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'name': name,
        'inviteCode': inviteCode,
        'members': members.map((member) => member.toJson()).toList(),
        'expenses': expenses.map((expense) => expense.toJson()).toList(),
        'settlements':
            settlements.map((settlement) => settlement.toJson()).toList(),
        'activities': activities.map((activity) => activity.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'revision': revision,
      };

  factory _SharedGroup.fromJson(Map<String, dynamic> json) {
    final expenses = (json['expenses'] as List<dynamic>? ?? const [])
        .map((item) => _SharedExpense.fromJson(item as Map<String, dynamic>))
        .toList();
    final settlements = (json['settlements'] as List<dynamic>? ?? const [])
        .map((item) => _Settlement.fromJson(item as Map<String, dynamic>))
        .toList();
    final activities = (json['activities'] as List<dynamic>? ?? const [])
        .map((item) => _SharedActivity.fromJson(item as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return _SharedGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      inviteCode: json['inviteCode'] as String,
      members: (json['members'] as List<dynamic>)
          .map((item) => _SharedMember.fromJson(item as Map<String, dynamic>))
          .toList(),
      expenses: expenses,
      settlements: settlements,
      activities: activities,
      createdAt: DateTime.parse(json['createdAt'] as String),
      revision:
          json['revision'] as int? ?? expenses.length + settlements.length,
      engineGroupId: json['engineGroupId'] as String?,
      groupKeyHex: json['groupKeyHex'] as String?,
      lastSyncedHash: json['lastSyncedHash'] as String?,
      lastSyncAt: json['lastSyncAt'] == null
          ? null
          : DateTime.parse(json['lastSyncAt'] as String),
    );
  }

  factory _SharedGroup.fromSyncJson(
    Map<String, dynamic> json, {
    required String localId,
    required String engineGroupId,
    required String groupKeyHex,
  }) {
    final expenses = (json['expenses'] as List<dynamic>? ?? const [])
        .map((item) => _SharedExpense.fromJson(item as Map<String, dynamic>))
        .toList();
    final settlements = (json['settlements'] as List<dynamic>? ?? const [])
        .map((item) => _Settlement.fromJson(item as Map<String, dynamic>))
        .toList();
    final activities = (json['activities'] as List<dynamic>? ?? const [])
        .map((item) => _SharedActivity.fromJson(item as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return _SharedGroup(
      id: localId,
      name: json['name'] as String? ?? 'Shared group',
      inviteCode: json['inviteCode'] as String? ?? engineGroupId,
      members: (json['members'] as List<dynamic>? ?? const [])
          .map((item) => _SharedMember.fromJson(item as Map<String, dynamic>))
          .toList(),
      expenses: expenses,
      settlements: settlements,
      activities: activities,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      revision:
          json['revision'] as int? ?? expenses.length + settlements.length,
      engineGroupId: engineGroupId,
      groupKeyHex: groupKeyHex,
    );
  }
}

class _SharedMember {
  final String id;
  final String name;
  final String initial;
  final int colorValue;

  const _SharedMember({
    required this.id,
    required this.name,
    required this.initial,
    required this.colorValue,
  });

  Color get color => Color(colorValue);

  _SharedMember copyWith({
    String? id,
    String? name,
    String? initial,
    int? colorValue,
  }) {
    return _SharedMember(
      id: id ?? this.id,
      name: name ?? this.name,
      initial: initial ?? this.initial,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'initial': initial,
        'colorValue': colorValue,
      };

  factory _SharedMember.fromJson(Map<String, dynamic> json) {
    return _SharedMember(
      id: json['id'] as String,
      name: json['name'] as String,
      initial: json['initial'] as String,
      colorValue: json['colorValue'] as int,
    );
  }
}

class _SharedActivity {
  final String id;
  final String actorId;
  final String action;
  final String? targetId;
  final String? targetTitle;
  final num? amount;
  final String? detail;
  final DateTime createdAt;

  const _SharedActivity({
    required this.id,
    required this.actorId,
    required this.action,
    this.targetId,
    this.targetTitle,
    this.amount,
    this.detail,
    required this.createdAt,
  });

  _SharedActivity copyWith({
    String? id,
    String? actorId,
    String? action,
    String? targetId,
    String? targetTitle,
    num? amount,
    String? detail,
    DateTime? createdAt,
  }) {
    return _SharedActivity(
      id: id ?? this.id,
      actorId: actorId ?? this.actorId,
      action: action ?? this.action,
      targetId: targetId ?? this.targetId,
      targetTitle: targetTitle ?? this.targetTitle,
      amount: amount ?? this.amount,
      detail: detail ?? this.detail,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'actorId': actorId,
        'action': action,
        'targetId': targetId,
        'targetTitle': targetTitle,
        'amount': amount,
        'detail': detail,
        'createdAt': createdAt.toIso8601String(),
      };

  factory _SharedActivity.fromJson(Map<String, dynamic> json) {
    return _SharedActivity(
      id: json['id'] as String,
      actorId: json['actorId'] as String,
      action: json['action'] as String,
      targetId: json['targetId'] as String?,
      targetTitle: json['targetTitle'] as String?,
      amount: json['amount'] as num?,
      detail: json['detail'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class _SharedExpense {
  final String id;
  final String title;
  final num amount;
  final String paidBy;
  final List<String> participants;
  final DateTime createdAt;
  final String? sourceTransactionReference;

  const _SharedExpense({
    required this.id,
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.participants,
    required this.createdAt,
    this.sourceTransactionReference,
  });

  _SharedExpense copyWith({
    String? id,
    String? title,
    num? amount,
    String? paidBy,
    List<String>? participants,
    DateTime? createdAt,
    String? sourceTransactionReference,
  }) {
    return _SharedExpense(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      paidBy: paidBy ?? this.paidBy,
      participants: participants ?? this.participants,
      createdAt: createdAt ?? this.createdAt,
      sourceTransactionReference:
          sourceTransactionReference ?? this.sourceTransactionReference,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'paidBy': paidBy,
        'participants': participants,
        'createdAt': createdAt.toIso8601String(),
        'sourceTransactionReference': sourceTransactionReference,
      };

  factory _SharedExpense.fromJson(Map<String, dynamic> json) {
    return _SharedExpense(
      id: json['id'] as String,
      title: json['title'] as String,
      amount: json['amount'] as num,
      paidBy: json['paidBy'] as String,
      participants: List<String>.from(json['participants'] as List<dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
      sourceTransactionReference: json['sourceTransactionReference'] as String?,
    );
  }
}

class _Settlement {
  final String id;
  final String from;
  final String to;
  final num amount;
  final DateTime createdAt;

  const _Settlement({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.createdAt,
  });

  _Settlement copyWith({
    String? id,
    String? from,
    String? to,
    num? amount,
    DateTime? createdAt,
  }) {
    return _Settlement(
      id: id ?? this.id,
      from: from ?? this.from,
      to: to ?? this.to,
      amount: amount ?? this.amount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'amount': amount,
        'createdAt': createdAt.toIso8601String(),
      };

  factory _Settlement.fromJson(Map<String, dynamic> json) {
    return _Settlement(
      id: json['id'] as String,
      from: json['from'] as String,
      to: json['to'] as String,
      amount: json['amount'] as num,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class _Debt {
  final String from;
  final String to;
  final num amount;

  const _Debt({
    required this.from,
    required this.to,
    required this.amount,
  });
}
