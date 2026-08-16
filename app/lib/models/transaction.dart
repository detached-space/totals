import 'dart:convert';

import 'package:totals/models/transaction_category_split.dart';
import 'package:totals/utils/sms_transaction_source.dart';

class Transaction {
  static const String manualOwnerAssignment = 'manual';
  static const String automaticOwnerAssignment = 'automatic';
  static const String defaultOwnerAssignment = 'default';
  static const String conflictingOwnerAssignment = 'conflict';

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
  /// User-entered account number selected as the authoritative owner.
  final String? ownerAccountNumber;

  /// How [ownerAccountNumber] was chosen. Manual choices are authoritative and
  /// must survive imports, reparses, and duplicate merging.
  final String? ownerAssignmentSource;
  final int? categoryId;
  final List<int>? categoryIds;
  final List<TransactionCategorySplit>? categorySplits;
  final int? profileId;
  final double? serviceCharge;
  final double? vat;
  final String? sourceType;
  final String? sourceMessageId;
  final String? sourceFingerprint;

  /// Android SMS subscription that delivered the source message. Device-local
  /// routing metadata; [ownerAccountNumber] is the durable ownership identity.
  final int? sourceSubscriptionId;

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
    this.ownerAccountNumber,
    this.ownerAssignmentSource,
    int? categoryId,
    List<int>? categoryIds,
    List<TransactionCategorySplit>? categorySplits,
    this.profileId,
    this.serviceCharge,
    this.vat,
    this.sourceType,
    this.sourceMessageId,
    this.sourceFingerprint,
    this.sourceSubscriptionId,
  })  : categorySplits = _normalizeCategorySplits(categorySplits),
        categoryId = _resolvePrimaryCategoryId(
          _primaryCategoryIdFromSplits(categorySplits) ?? categoryId,
          _categoryIdsFromSplits(categorySplits) ?? categoryIds,
        ),
        categoryIds = _normalizeCategoryIds(
          _categoryIdsFromSplits(categorySplits) ?? categoryIds,
          primaryCategoryId: _resolvePrimaryCategoryId(
            _primaryCategoryIdFromSplits(categorySplits) ?? categoryId,
            _categoryIdsFromSplits(categorySplits) ?? categoryIds,
          ),
        );

  static List<TransactionCategorySplit>? _decodeCategorySplits(dynamic raw) {
    if (raw == null) return null;
    dynamic decoded = raw;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      try {
        decoded = jsonDecode(trimmed);
      } catch (_) {
        return null;
      }
    }
    if (decoded is! Iterable) return null;

    final splits = <TransactionCategorySplit>[];
    for (final value in decoded) {
      if (value is! Map) continue;
      splits.add(
        TransactionCategorySplit.fromJson(
          Map<String, dynamic>.from(value.cast<String, dynamic>()),
        ),
      );
    }
    return _normalizeCategorySplits(splits);
  }

  static List<TransactionCategorySplit>? _normalizeCategorySplits(
    List<TransactionCategorySplit>? splits,
  ) {
    if (splits == null || splits.isEmpty) return null;
    final order = <int>[];
    final amountsByCategory = <int, int>{};
    for (final split in splits) {
      if (split.categoryId <= 0 || split.amountMinor <= 0) continue;
      if (!amountsByCategory.containsKey(split.categoryId)) {
        order.add(split.categoryId);
      }
      amountsByCategory.update(
        split.categoryId,
        (amount) => amount + split.amountMinor,
        ifAbsent: () => split.amountMinor,
      );
    }
    if (order.isEmpty) return null;
    return List<TransactionCategorySplit>.unmodifiable(
      order.map(
        (categoryId) => TransactionCategorySplit(
          categoryId: categoryId,
          amountMinor: amountsByCategory[categoryId]!,
        ),
      ),
    );
  }

  static List<int>? _categoryIdsFromSplits(
    List<TransactionCategorySplit>? splits,
  ) {
    final normalized = _normalizeCategorySplits(splits);
    if (normalized == null) return null;
    return normalized.map((split) => split.categoryId).toList(growable: false);
  }

  static int? _primaryCategoryIdFromSplits(
    List<TransactionCategorySplit>? splits,
  ) {
    final normalized = _normalizeCategorySplits(splits);
    return normalized == null || normalized.isEmpty
        ? null
        : normalized.first.categoryId;
  }

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

  int get amountMinor => TransactionCategorySplit.toMinorUnits(amount);

  bool get hasCategorySplit {
    final splits = categorySplits;
    if (splits == null || splits.length < 2 || amountMinor <= 0) return false;
    return splits.fold<int>(0, (sum, split) => sum + split.amountMinor) ==
        amountMinor;
  }

  /// Returns the amount attributed to each category. A valid split is scaled
  /// proportionally when [totalAmount] includes fees or reimbursements.
  /// Unsplit transactions keep their existing single-primary-category
  /// behavior, including a `null` key for uncategorized transactions.
  Map<int?, double> categoryAmounts({double? totalAmount}) {
    final targetMinor = TransactionCategorySplit.toMinorUnits(
      totalAmount ?? amount,
    );
    if (targetMinor <= 0) return const <int?, double>{};

    final splits = categorySplits;
    if (!hasCategorySplit || splits == null) {
      return <int?, double>{categoryId: targetMinor / 100};
    }

    final sourceTotal = splits.fold<int>(
      0,
      (sum, split) => sum + split.amountMinor,
    );
    final amounts = <int?, double>{};
    var allocatedMinor = 0;
    for (var index = 0; index < splits.length; index++) {
      final split = splits[index];
      final isLast = index == splits.length - 1;
      final splitMinor = isLast
          ? targetMinor - allocatedMinor
          : (targetMinor * split.amountMinor) ~/ sourceTotal;
      allocatedMinor += splitMinor;
      amounts[split.categoryId] = splitMinor / 100;
    }
    return Map<int?, double>.unmodifiable(amounts);
  }

  /// Bank-provided transaction number without Totals' SMS row-identity suffix.
  String get displayReference => SmsTransactionSource.displayReference(
        bankId: bankId,
        storedReference: reference,
      );

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
      ownerAccountNumber: json['ownerAccountNumber']?.toString(),
      ownerAssignmentSource: json['ownerAssignmentSource']?.toString(),
      categoryId: toInt(json['categoryId']),
      categoryIds: _decodeCategoryIds(json['categoryIds']),
      categorySplits: _decodeCategorySplits(
        json['categorySplits'] ?? json['category_splits'],
      ),
      profileId: toInt(json['profileId']),
      serviceCharge: toDouble(json['serviceCharge']),
      vat: toDouble(json['vat']),
      sourceType: json['sourceType']?.toString(),
      sourceMessageId: json['sourceMessageId']?.toString(),
      sourceFingerprint: json['sourceFingerprint']?.toString(),
      sourceSubscriptionId: toInt(json['sourceSubscriptionId']),
    );
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'reference': reference,
        'bankReference': displayReference,
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
        'ownerAccountNumber': ownerAccountNumber,
        'ownerAssignmentSource': ownerAssignmentSource,
        'categoryId': primaryCategoryId,
        'categoryIds': selectedCategoryIds.isEmpty ? null : selectedCategoryIds,
        'categorySplits': hasCategorySplit
            ? categorySplits!.map((split) => split.toJson()).toList()
            : null,
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
    String? ownerAccountNumber,
    String? ownerAssignmentSource,
    int? categoryId,
    List<int>? categoryIds,
    List<TransactionCategorySplit>? categorySplits,
    int? profileId,
    double? serviceCharge,
    double? vat,
    String? sourceType,
    String? sourceMessageId,
    String? sourceFingerprint,
    int? sourceSubscriptionId,
    bool clearCategoryId = false, // Flag to explicitly clear categoryId
    bool clearCategoryIds = false,
    bool clearCategorySplits = false,
    bool clearNote = false,
    bool clearOwnerAccountNumber = false,
  }) {
    int? nextCategoryId;
    List<int>? nextCategoryIds;
    List<TransactionCategorySplit>? nextCategorySplits;

    if (clearCategoryId || clearCategoryIds) {
      nextCategoryId = null;
      nextCategoryIds = null;
      nextCategorySplits = null;
    } else if (categorySplits != null) {
      nextCategorySplits = _normalizeCategorySplits(categorySplits);
      nextCategoryIds = _categoryIdsFromSplits(nextCategorySplits);
      nextCategoryId = _primaryCategoryIdFromSplits(nextCategorySplits);
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
      nextCategorySplits = null;
    } else if (categoryId != null) {
      nextCategoryId = _resolvePrimaryCategoryId(categoryId, const <int>[]);
      nextCategoryIds = _normalizeCategoryIds(
        <int>[categoryId],
        primaryCategoryId: nextCategoryId,
      );
      nextCategorySplits = null;
    } else {
      nextCategoryId = this.categoryId;
      nextCategoryIds = this.categoryIds;
      nextCategorySplits = clearCategorySplits ? null : this.categorySplits;
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
      ownerAccountNumber: clearOwnerAccountNumber
          ? null
          : (ownerAccountNumber ?? this.ownerAccountNumber),
      ownerAssignmentSource:
          ownerAssignmentSource ?? this.ownerAssignmentSource,
      categoryId: nextCategoryId,
      categoryIds: nextCategoryIds,
      categorySplits: nextCategorySplits,
      profileId: profileId ?? this.profileId,
      serviceCharge: serviceCharge ?? this.serviceCharge,
      vat: vat ?? this.vat,
      sourceType: sourceType ?? this.sourceType,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
      sourceSubscriptionId: sourceSubscriptionId ?? this.sourceSubscriptionId,
    );
  }

  bool get hasManualOwnerAssignment =>
      ownerAssignmentSource == manualOwnerAssignment;
}
