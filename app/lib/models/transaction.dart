import 'dart:convert';

class Transaction {
  final double amount; // required
  final String reference; // required
  final String? creditor;
  final String? receiver;
  final String? note;
  final String? time; // ISO string
  final String? status; // PENDING, CLEARED, SYNCED
  final String? currentBalance;
  final int? bankId;
  final String? type; // CREDIT or DEBIT
  final String? transactionLink;
  final String? accountNumber; // Last 4 digits
  final int? categoryId;
  final List<int>? categoryIds;
  final int? profileId;
  final double? serviceCharge;
  final double? vat;
  final String? sourceType;
  final String? sourceMessageId;
  final String? sourceFingerprint;

  Transaction({
    required this.amount,
    required this.reference,
    this.creditor,
    this.receiver,
    this.note,
    this.time,
    this.status,
    this.currentBalance,
    this.bankId,
    this.type,
    this.transactionLink,
    this.accountNumber,
    int? categoryId,
    List<int>? categoryIds,
    this.profileId,
    this.serviceCharge,
    this.vat,
    this.sourceType,
    this.sourceMessageId,
    this.sourceFingerprint,
  })  : categoryId = _resolvePrimaryCategoryId(categoryId, categoryIds),
        categoryIds = _normalizeCategoryIds(
          categoryIds,
          primaryCategoryId: _resolvePrimaryCategoryId(categoryId, categoryIds),
        );

  static List<int>? _decodeCategoryIds(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      final parsed = raw
          .map((value) {
            if (value is int) return value;
            if (value is num) return value.toInt();
            if (value is String) return int.tryParse(value.trim());
            return null;
          })
          .whereType<int>()
          .toList(growable: false);
      return parsed.isEmpty ? null : parsed;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      try {
        final decoded = jsonDecode(trimmed);
        return _decodeCategoryIds(decoded);
      } catch (_) {
        final parsed = trimmed
            .split(',')
            .map((value) => int.tryParse(value.trim()))
            .whereType<int>()
            .toList(growable: false);
        return parsed.isEmpty ? null : parsed;
      }
    }
    return null;
  }

  static List<int>? _normalizeCategoryIds(
    List<int>? ids, {
    int? primaryCategoryId,
  }) {
    final ordered = <int>[];

    void addId(int? value) {
      if (value == null || value <= 0 || ordered.contains(value)) return;
      ordered.add(value);
    }

    addId(primaryCategoryId);
    if (ids != null) {
      for (final id in ids) {
        addId(id);
      }
    }

    return ordered.isEmpty ? null : List<int>.unmodifiable(ordered);
  }

  static int? _resolvePrimaryCategoryId(
    int? categoryId,
    List<int>? categoryIds,
  ) {
    if (categoryId != null && categoryId > 0) return categoryId;
    final normalized = _normalizeCategoryIds(categoryIds);
    if (normalized == null || normalized.isEmpty) return null;
    return normalized.first;
  }

  List<int> get selectedCategoryIds {
    final normalized = _normalizeCategoryIds(
      categoryIds,
      primaryCategoryId: categoryId,
    );
    return normalized == null ? const <int>[] : List<int>.from(normalized);
  }

  int? get primaryCategoryId => categoryId;

  bool includesCategory(int? id) {
    if (id == null) return false;
    return selectedCategoryIds.contains(id);
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    return Transaction(
      amount: toDouble(json['amount']),
      reference: json['reference'] ?? '',
      creditor: json['creditor'],
      receiver: json['receiver'],
      note: json['note'],
      time: json['time'],
      status: json['status'],
      currentBalance: json['currentBalance']?.toString(),
      bankId: json['bankId'],
      type: json['type'],
      transactionLink: json['transactionLink'],
      accountNumber: json['accountNumber'],
      categoryId: toInt(json['categoryId']),
      categoryIds: _decodeCategoryIds(json['categoryIds']),
      profileId: toInt(json['profileId']),
      serviceCharge: toDouble(json['serviceCharge']),
      vat: toDouble(json['vat']),
      sourceType: json['sourceType']?.toString(),
      sourceMessageId: json['sourceMessageId']?.toString(),
      sourceFingerprint: json['sourceFingerprint']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'reference': reference,
        'creditor': creditor,
        'receiver': receiver,
        'note': note,
        'time': time,
        'status': status,
        'currentBalance': currentBalance,
        'bankId': bankId,
        'type': type,
        'transactionLink': transactionLink,
        'accountNumber': accountNumber,
        'categoryId': primaryCategoryId,
        'categoryIds': selectedCategoryIds.isEmpty ? null : selectedCategoryIds,
        if (profileId != null) 'profileId': profileId,
        if (serviceCharge != null) 'serviceCharge': serviceCharge,
        if (vat != null) 'vat': vat,
        if (sourceType != null) 'sourceType': sourceType,
        if (sourceMessageId != null) 'sourceMessageId': sourceMessageId,
        if (sourceFingerprint != null) 'sourceFingerprint': sourceFingerprint,
      };

  Transaction copyWith({
    double? amount,
    String? reference,
    String? creditor,
    String? receiver,
    String? note,
    String? time,
    String? status,
    String? currentBalance,
    int? bankId,
    String? type,
    String? transactionLink,
    String? accountNumber,
    int? categoryId,
    List<int>? categoryIds,
    int? profileId,
    double? serviceCharge,
    double? vat,
    String? sourceType,
    String? sourceMessageId,
    String? sourceFingerprint,
    bool clearCategoryId = false, // Flag to explicitly clear categoryId
    bool clearCategoryIds = false,
    bool clearNote = false,
  }) {
    int? nextCategoryId;
    List<int>? nextCategoryIds;

    if (clearCategoryId || clearCategoryIds) {
      nextCategoryId = null;
      nextCategoryIds = null;
    } else if (categoryIds != null) {
      final normalizedIds = _normalizeCategoryIds(categoryIds);
      final currentPrimaryStillSelected = categoryId == null &&
          this.categoryId != null &&
          (normalizedIds?.contains(this.categoryId) ?? false);
      final preferredPrimary =
          categoryId ?? (currentPrimaryStillSelected ? this.categoryId : null);
      nextCategoryId = _resolvePrimaryCategoryId(
        preferredPrimary,
        normalizedIds,
      );
      nextCategoryIds = _normalizeCategoryIds(
        normalizedIds,
        primaryCategoryId: nextCategoryId,
      );
    } else if (categoryId != null) {
      nextCategoryId = _resolvePrimaryCategoryId(categoryId, const <int>[]);
      nextCategoryIds = _normalizeCategoryIds(
        <int>[categoryId],
        primaryCategoryId: nextCategoryId,
      );
    } else {
      nextCategoryId = this.categoryId;
      nextCategoryIds = this.categoryIds;
    }

    return Transaction(
      amount: amount ?? this.amount,
      reference: reference ?? this.reference,
      creditor: creditor ?? this.creditor,
      receiver: receiver ?? this.receiver,
      note: clearNote ? null : (note ?? this.note),
      time: time ?? this.time,
      status: status ?? this.status,
      currentBalance: currentBalance ?? this.currentBalance,
      bankId: bankId ?? this.bankId,
      type: type ?? this.type,
      transactionLink: transactionLink ?? this.transactionLink,
      accountNumber: accountNumber ?? this.accountNumber,
      categoryId: nextCategoryId,
      categoryIds: nextCategoryIds,
      profileId: profileId ?? this.profileId,
      serviceCharge: serviceCharge ?? this.serviceCharge,
      vat: vat ?? this.vat,
      sourceType: sourceType ?? this.sourceType,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
    );
  }
}
