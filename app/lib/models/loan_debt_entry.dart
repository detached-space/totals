enum LoanDebtDirection {
  lent,
  borrowed,
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

class LoanDebtEntry {
  final int? id;
  final String transactionReference;
  final String personName;
  final LoanDebtDirection direction;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LoanDebtEntry({
    this.id,
    required this.transactionReference,
    required this.personName,
    required this.direction,
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
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
