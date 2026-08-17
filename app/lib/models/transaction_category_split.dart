class TransactionCategorySplit {
  static const int minorUnitsPerUnit = 100;

  final int categoryId;
  final int amountMinor;

  const TransactionCategorySplit({
    required this.categoryId,
    required this.amountMinor,
  });

  factory TransactionCategorySplit.fromAmount({
    required int categoryId,
    required double amount,
  }) {
    return TransactionCategorySplit(
      categoryId: categoryId,
      amountMinor: toMinorUnits(amount),
    );
  }

  factory TransactionCategorySplit.fromJson(Map<String, dynamic> json) {
    final categoryId = _toInt(json['categoryId']) ?? 0;
    final storedMinor = _toInt(json['amountMinor']);
    final amountMinor = storedMinor ?? toMinorUnits(_toDouble(json['amount']));
    return TransactionCategorySplit(
      categoryId: categoryId,
      amountMinor: amountMinor,
    );
  }

  double get amount => amountMinor / minorUnitsPerUnit;

  Map<String, dynamic> toJson() => {
        'categoryId': categoryId,
        'amountMinor': amountMinor,
      };

  static int toMinorUnits(double amount) {
    if (!amount.isFinite) return 0;
    return (amount.abs() * minorUnitsPerUnit).round();
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0.0;
    return 0.0;
  }

  @override
  bool operator ==(Object other) {
    return other is TransactionCategorySplit &&
        other.categoryId == categoryId &&
        other.amountMinor == amountMinor;
  }

  @override
  int get hashCode => Object.hash(categoryId, amountMinor);
}
