enum LoanDebtDirection {
  lent,
  borrowed,
}

enum LoanDebtStatus {
  active,
  settled,
  forgiven,
}

enum LoanDebtEntrySource {
  transaction,
  repaymentSurplus,
}

extension LoanDebtDirectionStorage on LoanDebtDirection {
  String get storageValue {
    switch (this) {
      case LoanDebtDirection.lent:
        return 'lent';
      case LoanDebtDirection.borrowed:
        return 'borrowed';
    }
  }
}

LoanDebtDirection loanDebtDirectionFromStorage(String? value) {
  return value == LoanDebtDirection.borrowed.storageValue
      ? LoanDebtDirection.borrowed
      : LoanDebtDirection.lent;
}

extension LoanDebtStatusStorage on LoanDebtStatus {
  String get storageValue {
    switch (this) {
      case LoanDebtStatus.active:
        return 'active';
      case LoanDebtStatus.settled:
        return 'settled';
      case LoanDebtStatus.forgiven:
        return 'forgiven';
    }
  }
}

LoanDebtStatus loanDebtStatusFromStorage(String? value) {
  switch (value) {
    case 'settled':
      return LoanDebtStatus.settled;
    case 'forgiven':
      return LoanDebtStatus.forgiven;
    case 'active':
    default:
      return LoanDebtStatus.active;
  }
}

extension LoanDebtEntrySourceStorage on LoanDebtEntrySource {
  String get storageValue {
    switch (this) {
      case LoanDebtEntrySource.transaction:
        return 'transaction';
      case LoanDebtEntrySource.repaymentSurplus:
        return 'repayment_surplus';
    }
  }
}

LoanDebtEntrySource loanDebtEntrySourceFromStorage(String? value) {
  return value == LoanDebtEntrySource.repaymentSurplus.storageValue
      ? LoanDebtEntrySource.repaymentSurplus
      : LoanDebtEntrySource.transaction;
}

class LoanDebtEntry {
  final int? id;
  final String transactionReference;
  final String personName;
  final LoanDebtDirection direction;
  final LoanDebtStatus status;
  final double? principalAmount;
  final LoanDebtEntrySource source;
  final DateTime? returnDate;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LoanDebtEntry({
    this.id,
    required this.transactionReference,
    required this.personName,
    required this.direction,
    this.status = LoanDebtStatus.active,
    this.principalAmount,
    this.source = LoanDebtEntrySource.transaction,
    this.returnDate,
    this.resolvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LoanDebtEntry.fromDb(Map<String, dynamic> row) {
    final createdAt = DateTime.tryParse(row['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(row['updatedAt'] as String? ?? '');
    final now = DateTime.now();
    return LoanDebtEntry(
      id: row['id'] as int?,
      transactionReference: (row['transactionReference'] as String?) ?? '',
      personName: (row['personName'] as String?) ?? '',
      direction: loanDebtDirectionFromStorage(
        row['direction'] as String?,
      ),
      status: loanDebtStatusFromStorage(row['status'] as String?),
      principalAmount: (row['principalAmount'] as num?)?.toDouble(),
      source: loanDebtEntrySourceFromStorage(row['source'] as String?),
      returnDate: DateTime.tryParse(row['returnDate'] as String? ?? ''),
      resolvedAt: DateTime.tryParse(row['resolvedAt'] as String? ?? ''),
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? createdAt ?? now,
    );
  }

  Map<String, dynamic> toDb() {
    return {
      if (id != null) 'id': id,
      'transactionReference': transactionReference,
      'personName': personName,
      'direction': direction.storageValue,
      'status': status.storageValue,
      'principalAmount': principalAmount,
      'source': source.storageValue,
      'returnDate': returnDate?.toIso8601String(),
      'resolvedAt': resolvedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() => toDb();

  factory LoanDebtEntry.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    final resolvedAt = DateTime.tryParse(json['resolvedAt'] as String? ?? '');
    final returnDate = DateTime.tryParse(json['returnDate'] as String? ?? '');
    final now = DateTime.now();
    double? toNullableDouble(Object? value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value.trim());
      return null;
    }

    return LoanDebtEntry(
      id: json['id'] is int ? json['id'] as int : null,
      transactionReference: (json['transactionReference'] as String?) ?? '',
      personName: (json['personName'] as String?) ?? '',
      direction: loanDebtDirectionFromStorage(json['direction'] as String?),
      status: loanDebtStatusFromStorage(json['status'] as String?),
      principalAmount: toNullableDouble(json['principalAmount']),
      source: loanDebtEntrySourceFromStorage(json['source'] as String?),
      returnDate: returnDate,
      resolvedAt: resolvedAt,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? createdAt ?? now,
    );
  }
}

class LoanDebtRepayment {
  final int? id;
  final String repaymentTransactionReference;
  final String loanDebtTransactionReference;
  final double appliedAmount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LoanDebtRepayment({
    this.id,
    required this.repaymentTransactionReference,
    required this.loanDebtTransactionReference,
    required this.appliedAmount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LoanDebtRepayment.fromDb(Map<String, dynamic> row) {
    final createdAt = DateTime.tryParse(row['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(row['updatedAt'] as String? ?? '');
    final now = DateTime.now();
    return LoanDebtRepayment(
      id: row['id'] as int?,
      repaymentTransactionReference:
          (row['repaymentTransactionReference'] as String?) ?? '',
      loanDebtTransactionReference:
          (row['loanDebtTransactionReference'] as String?) ?? '',
      appliedAmount: (row['appliedAmount'] as num?)?.toDouble() ?? 0,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? createdAt ?? now,
    );
  }

  Map<String, dynamic> toDb() {
    return {
      if (id != null) 'id': id,
      'repaymentTransactionReference': repaymentTransactionReference,
      'loanDebtTransactionReference': loanDebtTransactionReference,
      'appliedAmount': appliedAmount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() => toDb();

  factory LoanDebtRepayment.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    final now = DateTime.now();

    double toDouble(Object? value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value.trim()) ?? 0;
      return 0;
    }

    return LoanDebtRepayment(
      id: json['id'] is int ? json['id'] as int : null,
      repaymentTransactionReference:
          (json['repaymentTransactionReference'] as String?) ?? '',
      loanDebtTransactionReference:
          (json['loanDebtTransactionReference'] as String?) ?? '',
      appliedAmount: toDouble(json['appliedAmount']),
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? createdAt ?? now,
    );
  }
}
