import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/repositories/shared_expense_repository.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_settings_service.dart';

void _sharedExpenseBackgroundNotificationLog(String message) {
  if (kDebugMode) {
    debugPrint('debug: SharedExpenseBackgroundNotifications: $message');
  }
}

class SharedExpenseBackgroundNotificationService {
  SharedExpenseBackgroundNotificationService._();

  static final SharedExpenseBackgroundNotificationService instance =
      SharedExpenseBackgroundNotificationService._();

  static const _seenPrefix = 'shared_expense_seen_notifications_';
  static const _maxSeenEntriesPerGroup = 500;

  final SharedExpenseRepository _repository = SharedExpenseRepository();

  Future<void> sendMissedActivityDigestIfNeeded() async {
    final enabled = await NotificationSettingsService.instance
        .isSharedExpenseNotificationsEnabled();
    if (!enabled) return;

    try {
      final beforeGroups = await _repository.getGroups();
      final beforeActivityIdsByGroup = {
        for (final group in beforeGroups)
          group.id: group.activity
              .map((entry) => entry.id)
              .where((id) => id.isNotEmpty)
              .toSet(),
      };

      for (final group in beforeGroups) {
        if (group.id.isEmpty) continue;
        if (group.status != SharedExpenseGroupStatus.ready) continue;
        await _repository.syncGroup(group.id);
      }

      final refreshedGroups = await _repository.getGroups();
      final myPublicKey = await _repository.myPublicKey();
      if (myPublicKey.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final markSeenByGroup = <String, Set<String>>{};
      final notifiableUpdates = <_SharedExpenseMissedUpdate>[];

      for (final group in refreshedGroups) {
        if (group.id.isEmpty) continue;
        if (group.status != SharedExpenseGroupStatus.ready) continue;

        final beforeIds =
            beforeActivityIdsByGroup[group.id] ?? const <String>{};
        final seenIds =
            prefs.getStringList(_seenKey(group.id))?.toSet() ?? <String>{};
        final newEntries = group.activity
            .where(
              (entry) =>
                  entry.id.isNotEmpty &&
                  !seenIds.contains(entry.id) &&
                  !beforeIds.contains(entry.id),
            )
            .toList(growable: false)
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        if (newEntries.isEmpty) continue;
        markSeenByGroup
            .putIfAbsent(group.id, () => <String>{})
            .addAll(newEntries.map((entry) => entry.id));

        for (final entry in newEntries) {
          if (_shouldNotifyForEntry(
            group: group,
            entry: entry,
            myPublicKey: myPublicKey,
          )) {
            notifiableUpdates.add(_SharedExpenseMissedUpdate(group: group));
          }
        }
      }

      if (notifiableUpdates.isEmpty) {
        await _markSeenForGroups(
          prefs: prefs,
          groups: refreshedGroups,
          entryIdsByGroup: markSeenByGroup,
        );
        return;
      }

      final groupIds =
          notifiableUpdates.map((update) => update.group.id).toSet();
      final singleGroup =
          groupIds.length == 1 ? notifiableUpdates.first.group : null;

      final shown = await NotificationService.instance
          .showSharedExpenseDigestNotification(
        updateCount: notifiableUpdates.length,
        groupCount: groupIds.length,
        groupName: singleGroup?.name,
        groupId: singleGroup?.id,
      );
      if (!shown) return;

      await _markSeenForGroups(
        prefs: prefs,
        groups: refreshedGroups,
        entryIdsByGroup: markSeenByGroup,
      );
      _sharedExpenseBackgroundNotificationLog(
        'sent digest updates=${notifiableUpdates.length} '
        'groups=${groupIds.length}',
      );
    } catch (error, stackTrace) {
      _sharedExpenseBackgroundNotificationLog('digest failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
    }
  }

  bool _shouldNotifyForEntry({
    required SharedExpenseGroup group,
    required SharedActivityEntry entry,
    required String myPublicKey,
  }) {
    if (entry.actor.isEmpty || entry.actor == myPublicKey) return false;

    switch (entry.kind) {
      case 'nudge_sent':
        return _stringList(entry.data['debtorPks']).contains(myPublicKey);
      case 'expense_created':
      case 'settlement_created':
        return _isCurrentUserInExpensePayload(entry, myPublicKey);
      case 'expense_amount_changed':
      case 'expense_reason_changed':
      case 'expense_paid_by_changed':
      case 'expense_split_changed':
      case 'expense_date_changed':
      case 'expense_linked_transaction_changed':
      case 'expense_deleted':
        return _isCurrentUserAffectedByExpenseEdit(
          group: group,
          entry: entry,
          myPublicKey: myPublicKey,
        );
      case 'member_joined':
      case 'group_renamed':
        return true;
    }
    return false;
  }

  bool _isCurrentUserInExpensePayload(
    SharedActivityEntry entry,
    String myPublicKey,
  ) {
    return _stringValue(entry.data['paidBy']) == myPublicKey ||
        _stringList(entry.data['splitAmong']).contains(myPublicKey);
  }

  bool _isCurrentUserAffectedByExpenseEdit({
    required SharedExpenseGroup group,
    required SharedActivityEntry entry,
    required String myPublicKey,
  }) {
    final affectedPks = <String>{};
    final expense = _expenseForEntry(group, entry);

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
    return affectedPks.contains(myPublicKey);
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

  Future<void> _markSeenForGroups({
    required SharedPreferences prefs,
    required List<SharedExpenseGroup> groups,
    required Map<String, Set<String>> entryIdsByGroup,
  }) async {
    for (final group in groups) {
      final ids = entryIdsByGroup[group.id];
      if (ids == null || ids.isEmpty) continue;
      await _markSeen(prefs: prefs, group: group, entryIds: ids);
    }
  }

  String _seenKey(String groupId) => '$_seenPrefix$groupId';

  String _stringValue(Object? value) => value is String ? value : '';

  List<String> _stringList(Object? value) {
    if (value is List) return value.whereType<String>().toList(growable: false);
    return const <String>[];
  }
}

class _SharedExpenseMissedUpdate {
  final SharedExpenseGroup group;

  const _SharedExpenseMissedUpdate({required this.group});
}
