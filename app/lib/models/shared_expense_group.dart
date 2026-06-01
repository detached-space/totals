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

class SharedExpenseGroup {
  final String id;
  final String name;
  final String myDisplayName;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final SharedExpenseGroupStatus status;
  final List<SharedExpenseMember> members;
  final Set<String> approvedMemberKeys;

  const SharedExpenseGroup({
    required this.id,
    required this.name,
    required this.myDisplayName,
    required this.createdAt,
    this.expiresAt,
    required this.status,
    required this.members,
    required this.approvedMemberKeys,
  });

  int get memberCount => members.isEmpty ? 1 : members.length;

  bool get hasGroupKey => status == SharedExpenseGroupStatus.ready;

  List<SharedExpenseMember> pendingApprovalMembers(String myPublicKey) {
    if (!hasGroupKey) return const [];
    return members
        .where(
          (member) =>
              member.devicePublicKey.isNotEmpty &&
              member.devicePublicKey != myPublicKey &&
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
    );
  }

  factory SharedExpenseGroup.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String?;
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
    };
  }
}

DateTime? _dateFromJson(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
