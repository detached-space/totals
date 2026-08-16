class ReimbursementAllocation {
  final int? id;
  final String reimbursementTransactionReference;
  final String expenseTransactionReference;
  final double appliedAmount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReimbursementAllocation({
    this.id,
    required this.reimbursementTransactionReference,
    required this.expenseTransactionReference,
    required this.appliedAmount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReimbursementAllocation.fromDb(Map<String, dynamic> row) {
    final createdAt = DateTime.tryParse(row['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(row['updatedAt'] as String? ?? '');
    final now = DateTime.now();
    return ReimbursementAllocation(
      id: row['id'] as int?,
      reimbursementTransactionReference:
          (row['reimbursementTransactionReference'] as String?) ?? '',
      expenseTransactionReference:
          (row['expenseTransactionReference'] as String?) ?? '',
      appliedAmount: (row['appliedAmount'] as num?)?.toDouble() ?? 0.0,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? createdAt ?? now,
    );
  }

  Map<String, dynamic> toDb() {
    return {
      if (id != null) 'id': id,
      'reimbursementTransactionReference': reimbursementTransactionReference,
      'expenseTransactionReference': expenseTransactionReference,
      'appliedAmount': appliedAmount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() => toDb();
}

class ReimbursementAllocationDraft {
  final String expenseTransactionReference;
  final double appliedAmount;

  const ReimbursementAllocationDraft({
    required this.expenseTransactionReference,
    required this.appliedAmount,
  });
}
