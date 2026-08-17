class TransactionLocation {
  const TransactionLocation({
    required this.transactionReference,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.profileId,
    this.accuracy,
    this.amount,
    this.transactionTime,
  });

  final String transactionReference;
  final int? profileId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime capturedAt;
  final double? amount;
  final DateTime? transactionTime;

  factory TransactionLocation.fromMap(Map<String, Object?> map) {
    final transactionTime = map['transactionTime'] as String?;
    return TransactionLocation(
      transactionReference: map['transactionReference'] as String,
      profileId: map['profileId'] as int?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      capturedAt: DateTime.parse(map['capturedAt'] as String),
      amount: (map['amount'] as num?)?.toDouble(),
      transactionTime:
          transactionTime == null ? null : DateTime.tryParse(transactionTime),
    );
  }
}
