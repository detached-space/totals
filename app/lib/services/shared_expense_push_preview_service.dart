import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/services/shared_expense_crypto_service.dart';
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

  factory SharedExpensePushPreview.fromJson(Map<String, dynamic> json) {
    return SharedExpensePushPreview(
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      groupId: json['groupId'] as String? ?? '',
      eventId: json['eventId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'type': 'shared_expense_push_preview_v1',
        'title': title,
        'body': body,
        'groupId': groupId,
        'eventId': eventId,
      };
}

class SharedExpensePushPreviewService {
  static SharedExpensePushPreview joinRequest({
    required SharedExpenseGroup group,
    required String requesterName,
    required String eventId,
  }) {
    final groupName = group.name.trim().isEmpty ? 'your group' : group.name;
    final name = requesterName.trim().isEmpty ? 'Someone' : requesterName;
    return SharedExpensePushPreview(
      title: 'Join request',
      body: '$name wants to join $groupName.',
      groupId: group.id,
      eventId: eventId,
    );
  }

  static SharedExpensePushPreview memberApproved({
    required SharedExpenseGroup group,
    required String approverName,
    required String eventId,
  }) {
    final groupName = group.name.trim().isEmpty ? 'your group' : group.name;
    final name = approverName.trim().isEmpty ? 'A member' : approverName;
    return SharedExpensePushPreview(
      title: 'Join request approved',
      body: '$name approved your request to join $groupName.',
      groupId: group.id,
      eventId: eventId,
    );
  }

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
        return SharedExpensePushPreview(
          title: 'Payment reminder',
          body: '$actorName sent a payment reminder on $groupName.',
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
    }

    return null;
  }

  static Future<String?> encrypt({
    required SharedExpenseCryptoService cryptoService,
    required String groupKeyHex,
    required SharedExpensePushPreview? preview,
  }) async {
    if (preview == null) return null;
    return cryptoService.encryptPayloadWithKey(
      keyBytes: SharedExpenseCryptoService.fromHex(groupKeyHex),
      payload: preview.toJson(),
    );
  }

  static Future<SharedExpensePushPreview?> decrypt({
    required SharedExpenseCryptoService cryptoService,
    required String groupKeyHex,
    required String encryptedBlob,
  }) async {
    final decoded = await cryptoService.decryptPayloadWithKey(
      keyBytes: SharedExpenseCryptoService.fromHex(groupKeyHex),
      encryptedBlob: encryptedBlob,
    );
    if (decoded == null ||
        decoded['type'] != 'shared_expense_push_preview_v1') {
      return null;
    }
    final preview = SharedExpensePushPreview.fromJson(decoded);
    if (preview.title.trim().isEmpty || preview.body.trim().isEmpty) {
      return null;
    }
    return preview;
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
