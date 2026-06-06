enum SharedExpenseGroupStatus {
  ready,
  pendingApproval,
  localOnly,
}

class SharedExpenseMember {
  final String devicePublicKey;
  final DateTime? joinedAt;

  const SharedExpenseMember({
    required this.devicePublicKey,
    this.joinedAt,
  });

  factory SharedExpenseMember.fromJson(Map<String, dynamic> json) {
    return SharedExpenseMember(
      devicePublicKey: json['devicePublicKey'] as String? ?? '',
      joinedAt: _dateFromJson(json['joinedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'devicePublicKey': devicePublicKey,
      'joinedAt': joinedAt?.toIso8601String(),
    };
  }
}

/// A pending join request — someone who asked to join the group and is
/// waiting for an existing member to approve them (i.e., send the group key).
class PendingApproval {
  final String publicKey;
  final String? displayName;
  final int requestedAt;

  const PendingApproval({
    required this.publicKey,
    this.displayName,
    required this.requestedAt,
  });

  factory PendingApproval.fromJson(Map<String, dynamic> json) {
    return PendingApproval(
      publicKey: json['publicKey'] as String? ?? '',
      displayName: json['displayName'] as String?,
      requestedAt: (json['requestedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'publicKey': publicKey,
        if (displayName != null) 'displayName': displayName,
        'requestedAt': requestedAt,
      };
}

class SharedPaymentAddress {
  final int bankId;
  final String accountNumber;
  final String accountHolderName;

  const SharedPaymentAddress({
    required this.bankId,
    required this.accountNumber,
    this.accountHolderName = '',
  });

  bool get isValid => bankId > 0 && accountNumber.trim().isNotEmpty;

  factory SharedPaymentAddress.fromJson(Map<String, dynamic> json) {
    return SharedPaymentAddress(
      bankId: (json['bankId'] as num?)?.toInt() ?? 0,
      accountNumber: json['accountNumber'] as String? ?? '',
      accountHolderName: json['accountHolderName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'bankId': bankId,
        'accountNumber': accountNumber,
        if (accountHolderName.trim().isNotEmpty)
          'accountHolderName': accountHolderName,
      };

  @override
  bool operator ==(Object other) {
    return other is SharedPaymentAddress &&
        other.bankId == bankId &&
        other.accountNumber == accountNumber &&
        other.accountHolderName == accountHolderName;
  }

  @override
  int get hashCode => Object.hash(bankId, accountNumber, accountHolderName);
}

/// A single shared expense (or settlement record). Mirrors the iOS shape so
/// payloads encrypted on iOS decrypt to the same structure on Android.
class SharedExpense {
  final String id;
  final double amount;
  final String currency;
  final String reason;
  final String paidBy; // pubkey hex
  final List<String> splitAmong; // pubkey hexes
  final int timestamp; // ms since epoch (when the expense was paid)
  final int? revisedAt; // ms since epoch (last edit) — last-write-wins
  final bool deleted;

  /// "expense" or "settlement"
  final String kind;

  /// If this expense was split from a local SMS-parsed transaction, reference
  /// it here so the personal ledger can reconcile.
  final String? linkedTxRef;

  /// "pending" (still being submitted) or "synced".
  final String? status;

  const SharedExpense({
    required this.id,
    required this.amount,
    required this.currency,
    required this.reason,
    required this.paidBy,
    required this.splitAmong,
    required this.timestamp,
    this.revisedAt,
    this.deleted = false,
    this.kind = 'expense',
    this.linkedTxRef,
    this.status,
  });

  factory SharedExpense.fromJson(Map<String, dynamic> json) {
    final rawSplit = json['splitAmong'];
    final split = (rawSplit is List)
        ? rawSplit.whereType<String>().toList(growable: false)
        : const <String>[];
    return SharedExpense(
      id: json['id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'ETB',
      reason: json['reason'] as String? ?? '',
      paidBy: json['paidBy'] as String? ?? '',
      splitAmong: split,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      revisedAt: (json['revisedAt'] as num?)?.toInt(),
      deleted: json['deleted'] == true,
      kind: json['kind'] as String? ?? 'expense',
      linkedTxRef: json['linkedTxRef'] as String?,
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'currency': currency,
        'reason': reason,
        'paidBy': paidBy,
        'splitAmong': splitAmong,
        'timestamp': timestamp,
        if (revisedAt != null) 'revisedAt': revisedAt,
        if (deleted) 'deleted': true,
        'kind': kind,
        if (linkedTxRef != null) 'linkedTxRef': linkedTxRef,
        if (status != null) 'status': status,
      };

  SharedExpense copyWith({
    String? id,
    double? amount,
    String? currency,
    String? reason,
    String? paidBy,
    List<String>? splitAmong,
    int? timestamp,
    int? revisedAt,
    bool? deleted,
    String? kind,
    String? linkedTxRef,
    String? status,
    bool clearLinkedTxRef = false,
  }) {
    return SharedExpense(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      reason: reason ?? this.reason,
      paidBy: paidBy ?? this.paidBy,
      splitAmong: splitAmong ?? this.splitAmong,
      timestamp: timestamp ?? this.timestamp,
      revisedAt: revisedAt ?? this.revisedAt,
      deleted: deleted ?? this.deleted,
      kind: kind ?? this.kind,
      linkedTxRef: clearLinkedTxRef ? null : (linkedTxRef ?? this.linkedTxRef),
      status: status ?? this.status,
    );
  }
}

/// One activity log entry — emitted on group create, expense create/edit/delete,
/// settlement, member join/leave. One entry per changed field for edits.
class SharedActivityEntry {
  final String id;
  final int timestamp;

  /// pubkey of the actor who performed the action
  final String actor;

  /// e.g. "expense_created", "expense_amount_changed", "expense_reason_changed",
  /// "expense_paid_by_changed", "expense_split_changed", "expense_date_changed",
  /// "expense_deleted", "settlement", "member_joined", "member_left",
  /// "group_renamed".
  final String kind;

  /// Arbitrary per-kind payload (e.g., {expenseId, before, after}).
  final Map<String, dynamic> data;

  const SharedActivityEntry({
    required this.id,
    required this.timestamp,
    required this.actor,
    required this.kind,
    required this.data,
  });

  factory SharedActivityEntry.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return SharedActivityEntry(
      id: json['id'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      actor: json['actor'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'actor': actor,
        'kind': kind,
        'data': data,
      };
}

class SharedExpenseGroup {
  final String id;
  final String name;
  final String myDisplayName;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final SharedExpenseGroupStatus status;
  final List<SharedExpenseMember> members;

  /// Members we treat as "approved" — either us, or someone we've seen a
  /// group-key-encrypted payload from (proving they have the key).
  final Set<String> approvedMemberKeys;

  /// All shared expenses (and settlement records) for this group.
  final List<SharedExpense> expenses;

  /// Per-field activity log entries, newest-last.
  final List<SharedActivityEntry> activity;

  /// pubkey → most recent known display name (from incoming member_meta
  /// payloads or our own profile).
  final Map<String, String> displayNames;

  /// pubkey -> account members prefer to be paid through.
  final Map<String, SharedPaymentAddress> paymentAddresses;

  /// pubkey -> last local/remote update time for that member's display name
  /// and payment account metadata.
  final Map<String, int> memberMetaUpdatedAt;

  /// This device's preferred account for receiving group payments.
  final SharedPaymentAddress? myPaymentAddress;

  /// People who broadcast a join_request to this group and haven't been
  /// approved yet. Surfaced as "Approve Bob?" rows in the UI.
  final List<PendingApproval> pendingApprovals;

  /// When true, approving a new member sends them the existing group history.
  final bool backfillNewMembers;

  /// pubkeys we've already shared the group key + our member_meta with.
  /// Lets us avoid re-broadcasting on every receive.
  final Set<String> keySharedWith;

  /// Last successful sync time (ms epoch) — used for activity badging.
  final int? lastSyncAt;

  /// True when our own member_meta / group_meta broadcast failed (network
  /// blip, etc.) and we should retry on the next syncGroup. Mirrors the iOS
  /// `_needBroadcastMeta` flag.
  final bool pendingMetaBroadcast;

  const SharedExpenseGroup({
    required this.id,
    required this.name,
    required this.myDisplayName,
    required this.createdAt,
    this.expiresAt,
    required this.status,
    required this.members,
    required this.approvedMemberKeys,
    this.expenses = const [],
    this.activity = const [],
    this.displayNames = const {},
    this.paymentAddresses = const {},
    this.memberMetaUpdatedAt = const {},
    this.myPaymentAddress,
    this.pendingApprovals = const [],
    this.backfillNewMembers = false,
    this.keySharedWith = const {},
    this.lastSyncAt,
    this.pendingMetaBroadcast = false,
  });

  int get memberCount => members.isEmpty ? 1 : members.length;

  bool get hasGroupKey => status == SharedExpenseGroupStatus.ready;

  /// Display name for any member — falls back through (our display name for
  /// self), incoming member_meta name, then a shortened pubkey label.
  String displayNameFor(String myPublicKey, String pubkey) {
    if (pubkey == myPublicKey) return myDisplayName;
    final fromMeta = displayNames[pubkey];
    if (fromMeta != null && fromMeta.trim().isNotEmpty) return fromMeta;
    if (pubkey.length <= 12) return pubkey;
    return '${pubkey.substring(0, 6)}…${pubkey.substring(pubkey.length - 4)}';
  }

  List<SharedExpenseMember> pendingApprovalMembers(String myPublicKey) {
    if (!hasGroupKey) return const [];
    final pendingKeys = pendingApprovals
        .map((approval) => approval.publicKey)
        .where((publicKey) => publicKey.isNotEmpty)
        .toSet();
    if (pendingKeys.isEmpty) return const [];
    return members
        .where(
          (member) =>
              member.devicePublicKey.isNotEmpty &&
              member.devicePublicKey != myPublicKey &&
              pendingKeys.contains(member.devicePublicKey) &&
              !approvedMemberKeys.contains(member.devicePublicKey),
        )
        .toList(growable: false);
  }

  SharedExpenseGroup copyWith({
    String? id,
    String? name,
    String? myDisplayName,
    DateTime? createdAt,
    DateTime? expiresAt,
    SharedExpenseGroupStatus? status,
    List<SharedExpenseMember>? members,
    Set<String>? approvedMemberKeys,
    List<SharedExpense>? expenses,
    List<SharedActivityEntry>? activity,
    Map<String, String>? displayNames,
    Map<String, SharedPaymentAddress>? paymentAddresses,
    Map<String, int>? memberMetaUpdatedAt,
    SharedPaymentAddress? myPaymentAddress,
    List<PendingApproval>? pendingApprovals,
    bool? backfillNewMembers,
    Set<String>? keySharedWith,
    int? lastSyncAt,
    bool? pendingMetaBroadcast,
  }) {
    return SharedExpenseGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      myDisplayName: myDisplayName ?? this.myDisplayName,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      members: members ?? this.members,
      approvedMemberKeys: approvedMemberKeys ?? this.approvedMemberKeys,
      expenses: expenses ?? this.expenses,
      activity: activity ?? this.activity,
      displayNames: displayNames ?? this.displayNames,
      paymentAddresses: paymentAddresses ?? this.paymentAddresses,
      memberMetaUpdatedAt: memberMetaUpdatedAt ?? this.memberMetaUpdatedAt,
      myPaymentAddress: myPaymentAddress ?? this.myPaymentAddress,
      pendingApprovals: pendingApprovals ?? this.pendingApprovals,
      backfillNewMembers: backfillNewMembers ?? this.backfillNewMembers,
      keySharedWith: keySharedWith ?? this.keySharedWith,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      pendingMetaBroadcast: pendingMetaBroadcast ?? this.pendingMetaBroadcast,
    );
  }

  factory SharedExpenseGroup.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String?;
    final rawDisplayNames = json['displayNames'];
    final rawPaymentAddresses = json['paymentAddresses'];
    final rawMemberMetaUpdatedAt = json['memberMetaUpdatedAt'];
    final rawPendingApprovals = json['pendingApprovals'];
    final rawMyPaymentAddress = json['myPaymentAddress'];

    return SharedExpenseGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Shared group',
      myDisplayName: json['myDisplayName'] as String? ?? 'Me',
      createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now(),
      expiresAt: _dateFromJson(json['expiresAt']),
      status: SharedExpenseGroupStatus.values.firstWhere(
        (status) => status.name == rawStatus,
        orElse: () => SharedExpenseGroupStatus.pendingApproval,
      ),
      members: ((json['members'] as List?) ?? const [])
          .whereType<Map>()
          .map((member) => SharedExpenseMember.fromJson(
                Map<String, dynamic>.from(member),
              ))
          .where((member) => member.devicePublicKey.isNotEmpty)
          .toList(growable: false),
      approvedMemberKeys:
          ((json['approvedMemberKeys'] as List?) ?? const <dynamic>[])
              .whereType<String>()
              .toSet(),
      expenses: ((json['expenses'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SharedExpense.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      activity: ((json['activity'] as List?) ?? const [])
          .whereType<Map>()
          .map(
              (a) => SharedActivityEntry.fromJson(Map<String, dynamic>.from(a)))
          .toList(),
      displayNames: rawDisplayNames is Map
          ? Map<String, String>.from(
              rawDisplayNames.map(
                (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
              ),
            )
          : const {},
      paymentAddresses: rawPaymentAddresses is Map
          ? {
              for (final entry in rawPaymentAddresses.entries)
                if (entry.key is String && entry.value is Map)
                  (entry.key as String): SharedPaymentAddress.fromJson(
                    Map<String, dynamic>.from(entry.value as Map),
                  ),
            }
              .entries
              .where((entry) => entry.value.isValid)
              .fold<Map<String, SharedPaymentAddress>>(
              <String, SharedPaymentAddress>{},
              (map, entry) => map..[entry.key] = entry.value,
            )
          : const {},
      memberMetaUpdatedAt: rawMemberMetaUpdatedAt is Map
          ? {
              for (final entry in rawMemberMetaUpdatedAt.entries)
                if (entry.key is String && entry.value is num)
                  entry.key as String: (entry.value as num).toInt(),
            }.entries.where((entry) => entry.value > 0).fold<Map<String, int>>(
              <String, int>{},
              (map, entry) => map..[entry.key] = entry.value,
            )
          : const {},
      myPaymentAddress: rawMyPaymentAddress is Map
          ? SharedPaymentAddress.fromJson(
              Map<String, dynamic>.from(rawMyPaymentAddress),
            )
          : null,
      pendingApprovals: rawPendingApprovals is List
          ? rawPendingApprovals
              .whereType<Map>()
              .map(
                  (p) => PendingApproval.fromJson(Map<String, dynamic>.from(p)))
              .toList()
          : const [],
      backfillNewMembers: json['backfillNewMembers'] is bool
          ? json['backfillNewMembers'] as bool
          : true,
      keySharedWith: ((json['keySharedWith'] as List?) ?? const <dynamic>[])
          .whereType<String>()
          .toSet(),
      lastSyncAt: (json['lastSyncAt'] as num?)?.toInt(),
      pendingMetaBroadcast: json['pendingMetaBroadcast'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'myDisplayName': myDisplayName,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'status': status.name,
      'members': members.map((member) => member.toJson()).toList(),
      'approvedMemberKeys': approvedMemberKeys.toList(),
      'expenses': expenses.map((e) => e.toJson()).toList(),
      'activity': activity.map((a) => a.toJson()).toList(),
      'displayNames': displayNames,
      'paymentAddresses': paymentAddresses.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      if (memberMetaUpdatedAt.isNotEmpty)
        'memberMetaUpdatedAt': memberMetaUpdatedAt,
      if (myPaymentAddress != null)
        'myPaymentAddress': myPaymentAddress!.toJson(),
      'pendingApprovals': pendingApprovals.map((p) => p.toJson()).toList(),
      'backfillNewMembers': backfillNewMembers,
      'keySharedWith': keySharedWith.toList(),
      if (lastSyncAt != null) 'lastSyncAt': lastSyncAt,
      if (pendingMetaBroadcast) 'pendingMetaBroadcast': true,
    };
  }
}

DateTime? _dateFromJson(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
