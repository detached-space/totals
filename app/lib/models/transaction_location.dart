const int transactionPlaceNameMaxLength = 80;

String? normalizeTransactionPlaceName(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized.length > transactionPlaceNameMaxLength) {
    throw ArgumentError.value(
      value,
      'value',
      'Place names must be $transactionPlaceNameMaxLength characters or fewer.',
    );
  }
  return normalized;
}

class TransactionLocation {
  const TransactionLocation({
    required this.transactionReference,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.profileId,
    this.accuracy,
    this.amount,
    this.transactionType,
    this.transactionTime,
    this.placeName,
    this.savedLocationId,
  });

  final String transactionReference;
  final int? profileId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime capturedAt;
  final double? amount;
  final String? transactionType;
  final DateTime? transactionTime;
  final String? placeName;
  final String? savedLocationId;

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
      transactionType: map['transactionType']?.toString(),
      transactionTime:
          transactionTime == null ? null : DateTime.tryParse(transactionTime),
      placeName: normalizeTransactionPlaceName(map['placeName'] as String?),
      savedLocationId: _normalizedSavedLocationId(map['savedLocationId']),
    );
  }

  factory TransactionLocation.fromBackupJson(Map<String, dynamic> json) {
    final transactionReference =
        json['transactionReference']?.toString().trim() ?? '';
    final latitude = _backupDouble(json['latitude']);
    final longitude = _backupDouble(json['longitude']);
    final accuracy =
        json['accuracy'] == null ? null : _backupDouble(json['accuracy']);
    final capturedAt =
        DateTime.tryParse(json['capturedAt']?.toString().trim() ?? '');
    String? placeName;
    String? savedLocationId;
    try {
      placeName = normalizeTransactionPlaceName(json['placeName']?.toString());
      savedLocationId = _normalizedSavedLocationId(json['savedLocationId']);
    } on ArgumentError {
      throw const FormatException('Invalid transaction location place name.');
    }

    if (transactionReference.isEmpty ||
        latitude == null ||
        !latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude == null ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        (accuracy != null && (!accuracy.isFinite || accuracy < 0)) ||
        capturedAt == null) {
      throw const FormatException('Invalid transaction location backup row.');
    }

    return TransactionLocation(
      transactionReference: transactionReference,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      capturedAt: capturedAt.toUtc(),
      placeName: placeName,
      savedLocationId: savedLocationId,
    );
  }

  Map<String, dynamic> toBackupJson() {
    return <String, dynamic>{
      'transactionReference': transactionReference,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'capturedAt': capturedAt.toUtc().toIso8601String(),
      'placeName': placeName,
      'savedLocationId': savedLocationId,
    };
  }

  TransactionLocation copyWith({
    String? placeName,
    bool clearPlaceName = false,
  }) {
    return TransactionLocation(
      transactionReference: transactionReference,
      profileId: profileId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      capturedAt: capturedAt,
      amount: amount,
      transactionType: transactionType,
      transactionTime: transactionTime,
      placeName: clearPlaceName ? null : placeName ?? this.placeName,
      savedLocationId: savedLocationId,
    );
  }

  static String? _normalizedSavedLocationId(Object? value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.length > 128) {
      throw ArgumentError.value(
        value,
        'savedLocationId',
        'Invalid saved location ID.',
      );
    }
    return normalized;
  }

  static double? _backupDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }
}
