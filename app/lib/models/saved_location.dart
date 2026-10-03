import 'package:totals/models/transaction_location.dart';

const int savedLocationIdMaxLength = 128;

class SavedLocation {
  const SavedLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.updatedAt,
    this.profileId,
  });

  final String id;
  final int? profileId;
  final String name;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory SavedLocation.fromMap(Map<String, Object?> map) {
    return SavedLocation(
      id: _validatedId(map['id']),
      profileId: (map['profileId'] as num?)?.toInt(),
      name: _validatedName(map['name']),
      latitude: _validatedLatitude(map['latitude']),
      longitude: _validatedLongitude(map['longitude']),
      createdAt: _validatedDateTime(map['createdAt'], 'createdAt'),
      updatedAt: _validatedDateTime(map['updatedAt'], 'updatedAt'),
    );
  }

  factory SavedLocation.fromBackupJson(Map<String, dynamic> json) {
    try {
      return SavedLocation.fromMap(json);
    } on ArgumentError {
      throw const FormatException('Invalid saved location backup row.');
    } on FormatException {
      throw const FormatException('Invalid saved location backup row.');
    } on TypeError {
      throw const FormatException('Invalid saved location backup row.');
    }
  }

  Map<String, Object?> toDatabaseMap({int? overrideProfileId}) {
    return <String, Object?>{
      'id': id,
      'profileId': overrideProfileId ?? profileId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toBackupJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  SavedLocation copyWith({
    String? name,
    double? latitude,
    double? longitude,
    DateTime? updatedAt,
  }) {
    return SavedLocation(
      id: id,
      profileId: profileId,
      name: normalizeTransactionPlaceName(name) ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _validatedId(Object? value) {
    final id = value?.toString().trim() ?? '';
    if (id.isEmpty || id.length > savedLocationIdMaxLength) {
      throw ArgumentError.value(value, 'id', 'Invalid saved location ID.');
    }
    return id;
  }

  static String _validatedName(Object? value) {
    final name = normalizeTransactionPlaceName(value?.toString());
    if (name == null) {
      throw ArgumentError.value(value, 'name', 'A place name is required.');
    }
    return name;
  }

  static double _validatedLatitude(Object? value) {
    final latitude = _double(value);
    if (latitude == null ||
        !latitude.isFinite ||
        latitude < -90 ||
        latitude > 90) {
      throw ArgumentError.value(value, 'latitude', 'Invalid latitude.');
    }
    return latitude;
  }

  static double _validatedLongitude(Object? value) {
    final longitude = _double(value);
    if (longitude == null ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError.value(value, 'longitude', 'Invalid longitude.');
    }
    return longitude;
  }

  static DateTime _validatedDateTime(Object? value, String field) {
    final parsed = value is DateTime
        ? value
        : DateTime.tryParse(value?.toString().trim() ?? '');
    if (parsed == null) {
      throw FormatException('Invalid $field.');
    }
    return parsed.toUtc();
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }
}
