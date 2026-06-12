import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/utils/text_utils.dart';

class SharedExpensePushPreview {
  final String title;
  final String body;
  final String groupId;
  final String eventId;

  const SharedExpensePushPreview({
    required this.title,
    required this.body,
    required this.groupId,
    required this.eventId,
  });
}

/// Builds the notification text for a shared-expense activity entry.
///
/// Composition happens entirely on the recipient device after it has pulled
/// and decrypted the payload (the doorbell model — see
/// shared_expense_push_notification_service.dart and CLAUDE.md). Nothing here
/// is ever sent over the FCM wire.
class SharedExpensePushPreviewService {
  static SharedExpensePushPreview? buildForActivity({
    required SharedExpenseGroup group,
    required SharedActivityEntry entry,
    SharedExpense? expense,
  }) {
    if (entry.id.isEmpty || entry.actor.isEmpty) return null;

    final actorName = group.displayNameFor(entry.actor, entry.actor);
    final reason = _entryReason(entry, expense);
    final groupName = group.name.trim().isEmpty ? 'your group' : group.name;

    switch (entry.kind) {
      case 'nudge_sent':
        final amount = _doubleValue(entry.data['amount']);
        final amountText =
            amount > 0 ? 'ETB ${formatNumberWithComma(amount)}' : 'what you owe';
        return SharedExpensePushPreview(
          title: 'Settle up with $actorName',
          body: 'Pay $amountText to $actorName on $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'expense_created':
        final amount = _doubleValue(entry.data['amount']);
        final amountText =
            amount > 0 ? ' for ETB ${formatNumberWithComma(amount)}' : '';
        return SharedExpensePushPreview(
          title: 'Shared expense added',
          body: '$actorName added $reason$amountText on $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'settlement_created':
        final amount = _doubleValue(entry.data['amount']);
        if (amount <= 0) return null;
        return SharedExpensePushPreview(
          title: 'Debt settled',
          body:
              '$actorName marked ETB ${formatNumberWithComma(amount)} settled on $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'expense_amount_changed':
        final amount = _doubleValue(entry.data['after']);
        if (amount <= 0) return null;
        return SharedExpensePushPreview(
          title: 'Shared expense updated',
          body:
              '$actorName changed $reason to ETB ${formatNumberWithComma(amount)} on $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'expense_reason_changed':
        return SharedExpensePushPreview(
          title: 'Shared expense renamed',
          body:
              '$actorName renamed an expense to ${_reasonText(entry.data['after'])} on $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'expense_paid_by_changed':
        final payerPk = _stringValue(entry.data['after']);
        final payerName = payerPk.isEmpty
            ? 'someone else'
            : group.displayNameFor(entry.actor, payerPk);
        return SharedExpensePushPreview(
          title: 'Payer changed',
          body:
              '$actorName changed who paid for $reason to $payerName on $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'expense_split_changed':
        return SharedExpensePushPreview(
          title: 'Split updated',
          body: '$actorName changed who is included in $reason on $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'expense_date_changed':
        return SharedExpensePushPreview(
          title: 'Expense date updated',
          body: '$actorName changed the date for $reason on $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'expense_linked_transaction_changed':
        final linked = _stringValue(entry.data['after']).trim().isNotEmpty;
        return SharedExpensePushPreview(
          title: linked ? 'Transaction linked' : 'Transaction unlinked',
          body: linked
              ? '$actorName linked a transaction to $reason on $groupName.'
              : '$actorName removed the linked transaction from $reason on $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'expense_deleted':
        return SharedExpensePushPreview(
          title: 'Shared expense removed',
          body: '$actorName removed $reason from $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'member_joined':
        return SharedExpensePushPreview(
          title: 'New group member',
          body: '$actorName joined $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'member_left':
        return SharedExpensePushPreview(
          title: 'Group member left',
          body: '$actorName left $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'member_restored':
        return SharedExpensePushPreview(
          title: 'Device restored',
          body: '$actorName restored their backup on a new device — '
              '$groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'group_renamed':
        final nextName = _stringValue(entry.data['after']).trim();
        return SharedExpensePushPreview(
          title: 'Group renamed',
          body: nextName.isEmpty
              ? '$actorName renamed a shared group.'
              : '$actorName renamed the group to $nextName.',
          groupId: group.id,
          eventId: entry.id,
        );
      case 'join_requested':
        final requesterName = _stringValue(entry.data['requesterDisplayName'])
            .trim();
        final name = requesterName.isEmpty ? 'Someone' : requesterName;
        return SharedExpensePushPreview(
          title: 'Join request',
          body: '$name wants to join $groupName.',
          groupId: group.id,
          eventId: entry.id,
        );
      // i_was_approved is fired directly from
      // SharedExpenseRepository._applyKeyExchange (not via this preview
      // builder) — see _showApprovedNotificationOnce.
    }

    return null;
  }

  static String _entryReason(
    SharedActivityEntry entry,
    SharedExpense? expense,
  ) {
    if (entry.kind == 'expense_reason_changed') {
      return _reasonText(entry.data['after']);
    }
    final explicitReason = _reasonText(entry.data['reason']);
    if (explicitReason != 'an expense') return explicitReason;
    return _reasonText(expense?.reason);
  }

  static String _reasonText(Object? value) {
    final reason = _stringValue(value).trim();
    return reason.isEmpty ? 'an expense' : reason;
  }

  static String _stringValue(Object? value) => value is String ? value : '';

  static double _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    return 0;
  }
}
