import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/repositories/shared_expense_repository.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/shared_expense_realtime_bus.dart';
import 'package:totals/services/totals_engine_client.dart';
import 'package:totals/utils/text_utils.dart';

void _sharedExpenseNotificationLog(String message) {
  if (kDebugMode) {
    debugPrint('debug: SharedExpenseNotifications: $message');
  }
}

class SharedExpenseNotificationCoordinator {
  SharedExpenseNotificationCoordinator._();

  static final SharedExpenseNotificationCoordinator instance =
      SharedExpenseNotificationCoordinator._();

  static const _seenPrefix = 'shared_expense_seen_notifications_';
  static const _maxSeenEntriesPerGroup = 500;
  static const _reconnectDelay = Duration(seconds: 3);
  static const _startupGrace = Duration(seconds: 60);

  final SharedExpenseRepository _repository = SharedExpenseRepository();
  final Map<String, StreamSubscription<SharedExpenseGroup>>
      _groupSubscriptions = {};
  final Map<String, Timer> _groupReconnectTimers = {};
  final Set<String> _forbiddenGroupIds = {};

  StreamSubscription<void>? _groupListSubscription;
  StreamSubscription<SharedExpenseGroup>? _busSubscription;
  Timer? _groupListReconnectTimer;
  bool _started = false;
  bool _refreshingGroups = false;
  String _myPublicKey = '';
  int _startedAtMs = 0;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _startedAtMs = DateTime.now().millisecondsSinceEpoch;

    try {
      _myPublicKey = await _repository.myPublicKey();
      final groups = await _repository.getGroups();
      await _seedExistingActivity(groups);
      _syncGroupSubscriptions(groups);
      _startGroupListSubscription();

      _busSubscription =
          SharedExpenseRealtimeBus.instance.stream.listen(_handleGroupUpdated);

      // Catch up on any entries that landed DURING startup. Between the
      // `await myPublicKey()` yield at the top and this line, the SSE / FCM
      // consumers may have applied a payload and published to the bus while
      // _busSubscription didn't exist yet. Those entries are unseen (we kept
      // them out of the seed pass via _isFreshEnough), so trigger a one-shot
      // notify pass now to render them.
      for (final group in groups) {
        unawaited(notifyForUnseenActivities(group));
      }

      unawaited(_refreshGroupsAndSubscriptions());
    } catch (error, stackTrace) {
      _sharedExpenseNotificationLog('start failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> stop() async {
    _started = false;
    await _groupListSubscription?.cancel();
    _groupListSubscription = null;
    await _busSubscription?.cancel();
    _busSubscription = null;

    for (final subscription in _groupSubscriptions.values) {
      await subscription.cancel();
    }
    _groupSubscriptions.clear();

    for (final timer in _groupReconnectTimers.values) {
      timer.cancel();
    }
    _groupReconnectTimers.clear();
    _forbiddenGroupIds.clear();
    _groupListReconnectTimer?.cancel();
    _groupListReconnectTimer = null;
  }

  Future<void> markActivitySeenFromPush({
    required String groupId,
    required String eventId,
  }) async {
    final cleanGroupId = groupId.trim();
    final cleanEventId = eventId.trim();
    if (cleanGroupId.isEmpty || cleanEventId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _seenKey(cleanGroupId);
    final merged = <String>[
      ...?prefs.getStringList(key),
      cleanEventId,
    ];
    final deduped = <String>[];
    for (final id in merged) {
      if (id.isEmpty || deduped.contains(id)) continue;
      deduped.add(id);
    }
    final start = deduped.length > _maxSeenEntriesPerGroup
        ? deduped.length - _maxSeenEntriesPerGroup
        : 0;
    await prefs.setStringList(key, deduped.sublist(start));
  }

  Future<bool> isActivitySeen({
    required String groupId,
    required String eventId,
  }) async {
    final cleanGroupId = groupId.trim();
    final cleanEventId = eventId.trim();
    if (cleanGroupId.isEmpty || cleanEventId.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    return prefs
            .getStringList(_seenKey(cleanGroupId))
            ?.contains(cleanEventId) ??
        false;
  }

  Future<void> _seedExistingActivity(List<SharedExpenseGroup> groups) async {
    final prefs = await SharedPreferences.getInstance();
    for (final group in groups) {
      final ids = <String>[];
      for (final entry in group.activity) {
        // Skip entries inside the startup grace window. If a payload landed
        // during the awaits in start() (e.g., SSE delivered a key_exchange
        // before we could subscribe to the bus), its activity entry would be
        // here. Marking it seen at this point would silently swallow its
        // notification. The catch-up call at the end of start() relies on
        // these entries being absent from the seen set.
        if (!_isFreshEnough(entry)) {
          if (entry.id.isNotEmpty) ids.add(entry.id);
          final semanticKey = _semanticSeenKeyForEntry(group, entry);
          if (semanticKey != null) ids.add(semanticKey);
        }
      }
      if (ids.isEmpty) continue;
      await _markSeen(
        prefs: prefs,
        group: group,
        entryIds: ids,
      );
    }
  }

  void _startGroupListSubscription() {
    if (_groupListSubscription != null) return;
    _groupListSubscription = _repository.watchGroupListRealtime().listen(
      (_) => _refreshGroupsAndSubscriptions(),
      onError: (Object error, StackTrace stackTrace) {
        _sharedExpenseNotificationLog('group list stream failed: $error');
        if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
        _groupListSubscription = null;
        _scheduleGroupListReconnect();
      },
      onDone: () {
        _groupListSubscription = null;
        _scheduleGroupListReconnect();
      },
    );
  }

  void _scheduleGroupListReconnect() {
    if (!_started || _groupListReconnectTimer != null) return;
    _groupListReconnectTimer = Timer(_reconnectDelay, () {
      _groupListReconnectTimer = null;
      if (_started) _startGroupListSubscription();
    });
  }

  Future<void> _refreshGroupsAndSubscriptions() async {
    if (!_started || _refreshingGroups) return;
    _refreshingGroups = true;
    try {
      final groups = await _repository.refreshGroups();
      _syncGroupSubscriptions(groups);
    } catch (error, stackTrace) {
      _sharedExpenseNotificationLog('group refresh failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
    } finally {
      _refreshingGroups = false;
    }
  }

  void _syncGroupSubscriptions(List<SharedExpenseGroup> groups) {
    final desiredIds =
        groups.where(_shouldStreamGroup).map((group) => group.id).toSet();

    for (final groupId in _groupSubscriptions.keys.toList()) {
      if (!desiredIds.contains(groupId)) _stopGroupSubscription(groupId);
    }
    for (final groupId in _groupReconnectTimers.keys.toList()) {
      if (!desiredIds.contains(groupId)) {
        _groupReconnectTimers.remove(groupId)?.cancel();
      }
    }
    for (final groupId in desiredIds) {
      if (_groupSubscriptions.containsKey(groupId)) continue;
      if (_groupReconnectTimers.containsKey(groupId)) continue;
      _startGroupSubscription(groupId);
    }
  }

  bool _shouldStreamGroup(SharedExpenseGroup group) {
    if (group.id.isEmpty || _forbiddenGroupIds.contains(group.id)) {
      return false;
    }
    switch (group.status) {
      case SharedExpenseGroupStatus.localOnly:
        return false;
      case SharedExpenseGroupStatus.ready:
        return true;
      case SharedExpenseGroupStatus.pendingApproval:
        return _myPublicKey.isNotEmpty &&
            group.members.any(
              (member) => member.devicePublicKey == _myPublicKey,
            );
    }
  }

  void _startGroupSubscription(String groupId) {
    if (!_started || _groupSubscriptions.containsKey(groupId)) return;

    final subscription = _repository.watchGroupRealtime(groupId).listen(
      _handleGroupUpdated,
      onError: (Object error, StackTrace stackTrace) {
        _sharedExpenseNotificationLog('group stream failed: $error');
        if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
        _groupSubscriptions.remove(groupId);
        if (error is TotalsEngineException && error.statusCode == 403) {
          _forbiddenGroupIds.add(groupId);
          unawaited(_refreshGroupsAndSubscriptions());
          return;
        }
        _scheduleGroupReconnect(groupId);
      },
      onDone: () {
        _groupSubscriptions.remove(groupId);
        _scheduleGroupReconnect(groupId);
      },
    );
    _groupSubscriptions[groupId] = subscription;
  }

  void _stopGroupSubscription(String groupId) {
    _groupSubscriptions.remove(groupId)?.cancel();
  }

  void _scheduleGroupReconnect(String groupId) {
    if (!_started || _groupReconnectTimers.containsKey(groupId)) return;
    _groupReconnectTimers[groupId] = Timer(_reconnectDelay, () {
      _groupReconnectTimers.remove(groupId);
      if (_started) _startGroupSubscription(groupId);
    });
  }

  Future<void> _handleGroupUpdated(SharedExpenseGroup group) async {
    if (!_started || group.id.isEmpty || _myPublicKey.isEmpty) return;
    await _processGroupForNotifications(group, respectStartupGrace: true);
  }

  /// One-shot notification render pass for a freshly-synced group, callable
  /// from the FCM background isolate where the coordinator's `start()` was
  /// never run. Reads/writes the same `seen` set in SharedPreferences so a
  /// later foreground render won't duplicate.
  Future<void> notifyForUnseenActivities(SharedExpenseGroup group) async {
    if (group.id.isEmpty) return;
    if (_myPublicKey.isEmpty) {
      try {
        _myPublicKey = await _repository.myPublicKey();
      } catch (error) {
        _sharedExpenseNotificationLog(
            'notifyForUnseenActivities pubkey load failed: $error');
        return;
      }
    }
    if (_myPublicKey.isEmpty) return;
    await _processGroupForNotifications(group, respectStartupGrace: false);
  }

  Future<void> _processGroupForNotifications(
    SharedExpenseGroup group, {
    required bool respectStartupGrace,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenKey(group.id))?.toSet() ?? <String>{};
    final unseenEntries = group.activity
        .where((entry) => entry.id.isNotEmpty && !seen.contains(entry.id))
        .toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (unseenEntries.isEmpty) return;
    final entriesToNotify = <SharedActivityEntry>[];
    final seenKeysToMark = <String>[];
    final semanticSeenThisBatch = <String>{};
    for (final entry in unseenEntries) {
      seenKeysToMark.add(entry.id);
      final semanticKey = _semanticSeenKeyForEntry(group, entry);
      if (semanticKey != null) {
        seenKeysToMark.add(semanticKey);
        if (seen.contains(semanticKey) ||
            !semanticSeenThisBatch.add(semanticKey)) {
          continue;
        }
      }
      entriesToNotify.add(entry);
    }

    // Persist the seen set BEFORE we start showing notifications. If we did it
    // after, a concurrent firing (per-group SSE + bus + background push all
    // landing within the same tick) could each observe the entries as unseen
    // and notify twice.
    await _markSeen(
      prefs: prefs,
      group: group,
      entryIds: seenKeysToMark,
    );

    for (final entry in entriesToNotify) {
      if (respectStartupGrace && !_isFreshEnough(entry)) continue;
      await _showNotificationIfNeeded(group, entry);
    }
  }

  bool _isFreshEnough(SharedActivityEntry entry) {
    final oldestNotifiable = _startedAtMs - _startupGrace.inMilliseconds;
    return entry.timestamp >= oldestNotifiable;
  }

  Future<void> _markSeen({
    required SharedPreferences prefs,
    required SharedExpenseGroup group,
    required Iterable<String> entryIds,
  }) async {
    final merged = <String>{
      ...?prefs.getStringList(_seenKey(group.id)),
      ...entryIds.where((id) => id.isNotEmpty),
    };

    final ordered = group.activity
        .map((entry) => entry.id)
        .where((id) => id.isNotEmpty && merged.contains(id))
        .toList(growable: false);
    final overflow = merged.difference(ordered.toSet()).toList();
    final capped = [...overflow, ...ordered];
    final start = capped.length > _maxSeenEntriesPerGroup
        ? capped.length - _maxSeenEntriesPerGroup
        : 0;
    await prefs.setStringList(_seenKey(group.id), capped.sublist(start));
  }

  String _seenKey(String groupId) => '$_seenPrefix$groupId';

  String? _semanticSeenKeyForEntry(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) {
    if (entry.kind != 'member_joined') return null;
    final actorPk = entry.actor.trim();
    if (actorPk.isEmpty) return null;

    final joinedAt = (entry.data['joinedAt'] as num?)?.toInt() ??
        _memberJoinedAtMs(group, actorPk);
    final joinedAtSuffix = joinedAt == null ? '' : ':$joinedAt';
    return 'semantic:member_joined:$actorPk$joinedAtSuffix';
  }

  int? _memberJoinedAtMs(SharedExpenseGroup group, String memberPk) {
    for (final member in group.members) {
      if (member.devicePublicKey == memberPk) {
        return member.joinedAt?.millisecondsSinceEpoch;
      }
    }
    return null;
  }

  Future<void> _showNotificationIfNeeded(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final actorPk = entry.actor;
    if (actorPk.isEmpty || actorPk == _myPublicKey) return;

    switch (entry.kind) {
      case 'nudge_sent':
        await _showNudgeNotification(group, entry);
        return;
      case 'expense_created':
        await _showExpenseCreatedNotification(group, entry);
        return;
      case 'settlement_created':
        await _showSettlementNotification(group, entry);
        return;
      case 'expense_amount_changed':
        await _showExpenseAmountChangedNotification(group, entry);
        return;
      case 'expense_reason_changed':
        await _showExpenseReasonChangedNotification(group, entry);
        return;
      case 'expense_paid_by_changed':
        await _showExpensePaidByChangedNotification(group, entry);
        return;
      case 'expense_split_changed':
        await _showExpenseSplitChangedNotification(group, entry);
        return;
      case 'expense_date_changed':
        await _showExpenseDateChangedNotification(group, entry);
        return;
      case 'expense_linked_transaction_changed':
        await _showExpenseLinkedTransactionChangedNotification(group, entry);
        return;
      case 'expense_deleted':
        await _showExpenseDeletedNotification(group, entry);
        return;
      case 'member_joined':
        await _showMemberJoinedNotification(group, entry);
        return;
      case 'member_left':
        await _showMemberLeftNotification(group, entry);
        return;
      case 'member_restored':
        await _showMemberRestoredNotification(group, entry);
        return;
      case 'group_renamed':
        await _showGroupRenamedNotification(group, entry);
        return;
      case 'join_requested':
        await _showJoinRequestedNotification(group, entry);
        return;
    }
  }

  Future<void> _showJoinRequestedNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final rawName = _stringValue(entry.data['requesterDisplayName']).trim();
    final requesterName = rawName.isEmpty
        ? group.displayNameFor(_myPublicKey, entry.actor)
        : rawName;
    final cleanName = requesterName.trim().isEmpty ? 'Someone' : requesterName;
    final groupName = group.name.trim().isEmpty ? 'your group' : group.name;
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Join request',
      body: '$cleanName wants to join $groupName.',
    );
  }

  // The "you were approved" notification is fired directly from
  // SharedExpenseRepository._applyKeyExchange via a SharedPreferences-flagged
  // one-shot call — see _showApprovedNotificationOnce in the repository. We
  // do NOT surface it via this coordinator because the joiner's app is in its
  // startup window when the approval arrives and the bus / seed-set race
  // conditions made the notification unreliable.

  Future<void> _showNudgeNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final debtorPks = _stringList(entry.data['debtorPks']).toSet();
    if (!debtorPks.contains(_myPublicKey)) return;

    final amount = _nudgeAmountForRecipient(
      group: group,
      actorPk: entry.actor,
      recipientPk: _myPublicKey,
      data: entry.data,
    );
    if (amount < 0.5) return;

    await NotificationService.instance.showSharedExpenseNudgeNotification(
      nudgeId: entry.id,
      groupId: group.id,
      groupName: group.name,
      payeeName: group.displayNameFor(_myPublicKey, entry.actor),
      amount: amount,
    );
  }

  Future<void> _showExpenseCreatedNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final paidBy = _stringValue(entry.data['paidBy']);
    final splitAmong = _stringList(entry.data['splitAmong']);
    if (paidBy != _myPublicKey && !splitAmong.contains(_myPublicKey)) return;

    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    final amount = _doubleValue(entry.data['amount']);
    final reason = _reasonText(entry.data['reason']);
    final shouldMentionSplit =
        splitAmong.contains(_myPublicKey) && paidBy != _myPublicKey;
    final amountText = 'ETB ${formatNumberWithComma(amount)}';
    final body = shouldMentionSplit && amount > 0
        ? '$actorName split $amountText with you on ${group.name}.'
        : '$actorName added $reason on ${group.name}.';

    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Shared expense added',
      body: body,
    );
  }

  Future<void> _showSettlementNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final paidBy = _stringValue(entry.data['paidBy']);
    final splitAmong = _stringList(entry.data['splitAmong']);
    if (paidBy != _myPublicKey && !splitAmong.contains(_myPublicKey)) return;

    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    final amount = _doubleValue(entry.data['amount']);
    if (amount <= 0) return;
    final amountText = 'ETB ${formatNumberWithComma(amount)}';
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Debt settled',
      body: '$actorName marked $amountText settled on ${group.name}.',
    );
  }

  Future<void> _showExpenseAmountChangedNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final expense = _expenseForEntry(group, entry);
    if (!_isCurrentUserAffectedByExpenseEdit(entry, expense)) return;

    final amount = _doubleValue(entry.data['after']);
    if (amount <= 0) return;

    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    final reason = _entryReason(entry, expense);
    final amountText = 'ETB ${formatNumberWithComma(amount)}';
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Shared expense updated',
      body: '$actorName changed $reason to $amountText on ${group.name}.',
    );
  }

  Future<void> _showExpenseReasonChangedNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final expense = _expenseForEntry(group, entry);
    if (!_isCurrentUserAffectedByExpenseEdit(entry, expense)) return;

    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    final reason = _reasonText(entry.data['after']);
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Shared expense renamed',
      body: '$actorName renamed an expense to $reason on ${group.name}.',
    );
  }

  Future<void> _showExpensePaidByChangedNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final expense = _expenseForEntry(group, entry);
    if (!_isCurrentUserAffectedByExpenseEdit(entry, expense)) return;

    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    final payerPk = _stringValue(entry.data['after']);
    final payerName = payerPk.isEmpty
        ? 'someone else'
        : group.displayNameFor(_myPublicKey, payerPk);
    final reason = _entryReason(entry, expense);
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Payer changed',
      body:
          '$actorName changed who paid for $reason to $payerName on ${group.name}.',
    );
  }

  Future<void> _showExpenseSplitChangedNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final expense = _expenseForEntry(group, entry);
    if (!_isCurrentUserAffectedByExpenseEdit(entry, expense)) return;

    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    final reason = _entryReason(entry, expense);
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Split updated',
      body: '$actorName changed who is included in $reason on ${group.name}.',
    );
  }

  Future<void> _showExpenseDateChangedNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final expense = _expenseForEntry(group, entry);
    if (!_isCurrentUserAffectedByExpenseEdit(entry, expense)) return;

    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    final reason = _entryReason(entry, expense);
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Expense date updated',
      body: '$actorName changed the date for $reason on ${group.name}.',
    );
  }

  Future<void> _showExpenseLinkedTransactionChangedNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final expense = _expenseForEntry(group, entry);
    if (!_isCurrentUserAffectedByExpenseEdit(entry, expense)) return;

    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    final reason = _entryReason(entry, expense);
    final linked = _stringValue(entry.data['after']).trim().isNotEmpty;
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: linked ? 'Transaction linked' : 'Transaction unlinked',
      body: linked
          ? '$actorName linked a transaction to $reason on ${group.name}.'
          : '$actorName removed the linked transaction from $reason on ${group.name}.',
    );
  }

  Future<void> _showExpenseDeletedNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final expense = _expenseForEntry(group, entry);
    if (!_isCurrentUserAffectedByExpenseEdit(entry, expense)) return;

    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    final reason = _entryReason(entry, expense);
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Shared expense removed',
      body: '$actorName removed $reason from ${group.name}.',
    );
  }

  Future<void> _showMemberJoinedNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'New group member',
      body: '$actorName joined ${group.name}.',
    );
  }

  Future<void> _showMemberLeftNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final fallbackName =
        _stringValue(entry.data['displayName']).trim();
    final actorName = fallbackName.isNotEmpty
        ? fallbackName
        : group.displayNameFor(_myPublicKey, entry.actor);
    final groupName = group.name.trim().isEmpty ? 'your group' : group.name;
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Group member left',
      body: '$actorName left $groupName.',
    );
  }

  Future<void> _showMemberRestoredNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    final groupName = group.name.trim().isEmpty ? 'your group' : group.name;
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Device restored',
      body: '$actorName restored their backup on a new device — $groupName. '
          'If this wasn\'t them, the recovery code + PIN may be compromised.',
    );
  }

  Future<void> _showGroupRenamedNotification(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) async {
    final actorName = group.displayNameFor(_myPublicKey, entry.actor);
    final nextName = _stringValue(entry.data['after']).trim();
    await NotificationService.instance.showSharedExpenseEventNotification(
      eventId: entry.id,
      groupId: group.id,
      title: 'Group renamed',
      body: nextName.isEmpty
          ? '$actorName renamed a shared group.'
          : '$actorName renamed the group to $nextName.',
    );
  }

  double _nudgeAmountForRecipient({
    required SharedExpenseGroup group,
    required String actorPk,
    required String recipientPk,
    required Map<String, dynamic> data,
  }) {
    final amountByDebtorPk = _doubleMap(data['amountByDebtorPk']);
    final explicitAmount = amountByDebtorPk[recipientPk];
    if (explicitAmount != null && explicitAmount > 0) return explicitAmount;

    for (final debt in originalDebtPlanFor(group).debts) {
      if (debt.from == recipientPk && debt.to == actorPk && debt.amount > 0) {
        return debt.amount;
      }
    }

    final debtorCount = _stringList(data['debtorPks']).toSet().length;
    final fallback = _doubleValue(data['amount']);
    if (debtorCount > 1 && fallback > 0) return fallback / debtorCount;
    return fallback;
  }

  String _reasonText(Object? value) {
    final reason = _stringValue(value).trim();
    return reason.isEmpty ? 'an expense' : reason;
  }

  SharedExpense? _expenseForEntry(
    SharedExpenseGroup group,
    SharedActivityEntry entry,
  ) {
    final expenseId = _stringValue(entry.data['expenseId']);
    if (expenseId.isEmpty) return null;
    for (final expense in group.expenses) {
      if (expense.id == expenseId) return expense;
    }
    return null;
  }

  String _entryReason(SharedActivityEntry entry, SharedExpense? expense) {
    if (entry.kind == 'expense_reason_changed') {
      return _reasonText(entry.data['after']);
    }
    final explicitReason = _reasonText(entry.data['reason']);
    if (explicitReason != 'an expense') return explicitReason;
    return _reasonText(expense?.reason);
  }

  bool _isCurrentUserAffectedByExpenseEdit(
    SharedActivityEntry entry,
    SharedExpense? expense,
  ) {
    final affectedPks = <String>{};

    if (expense != null) {
      affectedPks.add(expense.paidBy);
      affectedPks.addAll(expense.splitAmong);
    }

    switch (entry.kind) {
      case 'expense_paid_by_changed':
        affectedPks.add(_stringValue(entry.data['before']));
        affectedPks.add(_stringValue(entry.data['after']));
        break;
      case 'expense_split_changed':
        affectedPks.addAll(_stringList(entry.data['before']));
        affectedPks.addAll(_stringList(entry.data['after']));
        break;
    }

    affectedPks.remove('');
    if (affectedPks.isEmpty) return true;
    return affectedPks.contains(_myPublicKey);
  }

  String _stringValue(Object? value) => value is String ? value : '';

  List<String> _stringList(Object? value) {
    if (value is List) return value.whereType<String>().toList(growable: false);
    return const <String>[];
  }

  double _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    return 0;
  }

  Map<String, double> _doubleMap(Object? value) {
    if (value is! Map) return const <String, double>{};
    final result = <String, double>{};
    value.forEach((key, raw) {
      if (key is String && raw is num) result[key] = raw.toDouble();
    });
    return result;
  }
}
