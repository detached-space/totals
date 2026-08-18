import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

const ethiopiaCityPlacesAsset = 'assets/maps/ethiopia_city_places.json';

class OfflinePlaceGazetteer {
  const OfflinePlaceGazetteer({
    required this.schemaVersion,
    required this.detailedCityId,
    required this.sources,
    required this.bounds,
    required this.cities,
    required this.places,
  });

  final int schemaVersion;
  final String detailedCityId;
  final List<OfflinePlaceSource> sources;
  final OfflinePlaceBounds bounds;
  final List<OfflineCityCoverage> cities;
  final List<OfflinePlace> places;

  static Future<OfflinePlaceGazetteer> loadEthiopianCities({
    AssetBundle? bundle,
  }) async {
    final json = await (bundle ?? rootBundle).loadString(
      ethiopiaCityPlacesAsset,
    );
    return OfflinePlaceGazetteer.fromJson(json);
  }

  factory OfflinePlaceGazetteer.fromJson(String sourceJson) {
    final decoded = jsonDecode(sourceJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Gazetteer root must be a JSON object.');
    }

    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion != 3) {
      throw FormatException(
        'Unsupported offline gazetteer schema: $schemaVersion',
      );
    }

    final detailedCityId = _requiredString(decoded, 'detailedCityId');

    final sources = _requiredObjectList(decoded, 'sources')
        .map(OfflinePlaceSource.fromJson)
        .toList(growable: false);
    if (sources.isEmpty) {
      throw const FormatException(
        'Gazetteer must contain at least one source.',
      );
    }
    final sourceIds = sources.map((source) => source.id).toSet();
    if (sourceIds.length != sources.length) {
      throw const FormatException('Gazetteer source IDs must be unique.');
    }

    final bounds = OfflinePlaceBounds.fromJson(
      _requiredMap(decoded, 'bounds'),
    );
    final cities = _requiredObjectList(decoded, 'cities')
        .map(OfflineCityCoverage.fromJson)
        .toList(growable: false);
    if (cities.isEmpty) {
      throw const FormatException('Gazetteer must cover at least one city.');
    }
    final cityIds = cities.map((city) => city.id).toSet();
    if (cityIds.length != cities.length) {
      throw const FormatException('Gazetteer city IDs must be unique.');
    }
    if (!cityIds.contains(detailedCityId)) {
      throw FormatException(
        'Unknown detailed gazetteer city ID: $detailedCityId',
      );
    }

    final places = _requiredObjectList(decoded, 'places')
        .map(OfflinePlace.fromJson)
        .toList(growable: false);
    if (places.isEmpty) {
      throw const FormatException('Gazetteer must contain at least one place.');
    }

    final recordIds = <String>{};
    for (final place in places) {
      if (!sourceIds.contains(place.sourceId)) {
        throw FormatException(
          'Unknown gazetteer source ID: ${place.sourceId}',
        );
      }
      if (!cityIds.contains(place.cityId)) {
        throw FormatException('Unknown gazetteer city ID: ${place.cityId}');
      }
      if (!bounds.contains(
        latitude: place.latitude,
        longitude: place.longitude,
      )) {
        throw FormatException(
          'Gazetteer record is outside the dataset bounds: '
          '${place.sourceId}/${place.sourceRecordId}',
        );
      }
      for (final polygon in place.polygons) {
        for (final ring in polygon) {
          for (final coordinate in ring) {
            if (!bounds.contains(
              latitude: coordinate.latitude,
              longitude: coordinate.longitude,
            )) {
              throw FormatException(
                'Gazetteer polygon is outside the dataset bounds: '
                '${place.sourceId}/${place.sourceRecordId}',
              );
            }
          }
        }
      }
      if (place.isSubcity && place.cityId != detailedCityId) {
        throw FormatException(
          'Subcity detail is only allowed for $detailedCityId.',
        );
      }
      final recordId = '${place.sourceId}/${place.sourceRecordId}';
      if (!recordIds.add(recordId)) {
        throw FormatException('Duplicate gazetteer record: $recordId');
      }
    }

    for (final city in cities) {
      final cityRecordCount = places
          .where((place) => place.cityId == city.id && place.isCity)
          .length;
      final subcityRecordCount = places
          .where((place) => place.cityId == city.id && place.isSubcity)
          .length;
      if (cityRecordCount != 1) {
        throw FormatException(
          'Gazetteer city ${city.id} must have exactly one city record.',
        );
      }
      if (subcityRecordCount != city.subcityRecordCount) {
        throw FormatException(
          'Gazetteer subcity count does not match city ${city.id}.',
        );
      }
    }

    return OfflinePlaceGazetteer(
      schemaVersion: schemaVersion,
      detailedCityId: detailedCityId,
      sources: List<OfflinePlaceSource>.unmodifiable(sources),
      bounds: bounds,
      cities: List<OfflineCityCoverage>.unmodifiable(cities),
      places: List<OfflinePlace>.unmodifiable(places),
    );
  }

  OfflinePlaceSource? sourceById(String id) {
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  OfflinePlaceMatch? nearestPlace({
    required double latitude,
    required double longitude,
  }) {
    if (!bounds.contains(latitude: latitude, longitude: longitude)) {
      return null;
    }

    OfflinePlaceMatch? containingSubcity;
    OfflinePlaceMatch? nearestCity;
    for (final place in places) {
      final distance = _distanceKm(
        latitude,
        longitude,
        place.latitude,
        place.longitude,
      );
      final match = OfflinePlaceMatch(place: place, distanceKm: distance);
      if (place.isCity) {
        if (distance > place.matchRadiusKm) continue;
        if (nearestCity == null || distance < nearestCity.distanceKm) {
          nearestCity = match;
        }
      } else if (place.contains(
            latitude: latitude,
            longitude: longitude,
          ) &&
          (containingSubcity == null ||
              distance < containingSubcity.distanceKm)) {
        containingSubcity = match;
      }
    }
    return containingSubcity ?? nearestCity;
  }
}

class OfflinePlaceSource {
  const OfflinePlaceSource({
    required this.id,
    required this.name,
    required this.attribution,
    required this.license,
    required this.licenseUrl,
    required this.dataTimestamp,
  });

  final String id;
  final String name;
  final String attribution;
  final String license;
  final Uri licenseUrl;
  final DateTime dataTimestamp;

  factory OfflinePlaceSource.fromJson(Map<String, dynamic> json) {
    final licenseUrl = Uri.tryParse(_requiredString(json, 'licenseUrl'));
    final timestamp = DateTime.tryParse(
      _requiredString(json, 'dataTimestamp'),
    );
    if (licenseUrl == null || !licenseUrl.hasScheme || timestamp == null) {
      throw const FormatException('Gazetteer source metadata is invalid.');
    }
    return OfflinePlaceSource(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      attribution: _requiredString(json, 'attribution'),
      license: _requiredString(json, 'license'),
      licenseUrl: licenseUrl,
      dataTimestamp: timestamp,
    );
  }
}

class OfflineCityCoverage {
  const OfflineCityCoverage({
    required this.id,
    required this.name,
    required this.subcityRecordCount,
  });

  final String id;
  final String name;
  final int subcityRecordCount;

  factory OfflineCityCoverage.fromJson(Map<String, dynamic> json) {
    final subcityRecordCount = json['subcityRecordCount'];
    if (subcityRecordCount is! int || subcityRecordCount < 0) {
      throw const FormatException(
        'Gazetteer subcityRecordCount must be a non-negative integer.',
      );
    }
    return OfflineCityCoverage(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      subcityRecordCount: subcityRecordCount,
    );
  }
}

class OfflinePlaceBounds {
  const OfflinePlaceBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  factory OfflinePlaceBounds.fromJson(Map<String, dynamic> json) {
    final bounds = OfflinePlaceBounds(
      south: _requiredDouble(json, 'south'),
      west: _requiredDouble(json, 'west'),
      north: _requiredDouble(json, 'north'),
      east: _requiredDouble(json, 'east'),
    );
    if (bounds.south >= bounds.north || bounds.west >= bounds.east) {
      throw const FormatException('Gazetteer bounds are invalid.');
    }
    return bounds;
  }

  bool contains({required double latitude, required double longitude}) {
    return latitude >= south &&
        latitude <= north &&
        longitude >= west &&
        longitude <= east;
  }
}

class OfflinePlace {
  const OfflinePlace({
    required this.sourceId,
    required this.sourceRecordId,
    required this.cityId,
    required this.type,
    required this.name,
    required this.nameEn,
    required this.nameAm,
    required this.latitude,
    required this.longitude,
    required this.customMatchRadiusKm,
    required this.polygons,
  });

  final String sourceId;
  final String sourceRecordId;
  final String cityId;
  final String type;
  final String name;
  final String? nameEn;
  final String? nameAm;
  final double latitude;
  final double longitude;
  final double? customMatchRadiusKm;
  final List<List<List<OfflinePlaceCoordinate>>> polygons;

  factory OfflinePlace.fromJson(Map<String, dynamic> json) {
    final type = _requiredString(json, 'type');
    if (type != 'city' && type != 'subcity') {
      throw FormatException('Unsupported gazetteer place type: $type');
    }
    final customMatchRadiusKm = _optionalDouble(json, 'matchRadiusKm');
    final polygons = _optionalMultiPolygon(json, 'polygons');
    if (type == 'city' && customMatchRadiusKm == null) {
      throw const FormatException(
        'Gazetteer city records require matchRadiusKm.',
      );
    }
    if (type == 'city' && polygons.isNotEmpty) {
      throw const FormatException(
        'Gazetteer city records cannot contain subcity polygons.',
      );
    }
    if (type == 'subcity' && polygons.isEmpty) {
      throw const FormatException(
        'Gazetteer subcity records require polygon geometry.',
      );
    }
    if (type == 'subcity' && customMatchRadiusKm != null) {
      throw const FormatException(
        'Gazetteer subcity records cannot use a match radius.',
      );
    }
    if (customMatchRadiusKm != null && customMatchRadiusKm <= 0) {
      throw const FormatException(
        'Gazetteer matchRadiusKm must be positive.',
      );
    }
    return OfflinePlace(
      sourceId: _requiredString(json, 'sourceId'),
      sourceRecordId: _requiredString(json, 'sourceRecordId'),
      cityId: _requiredString(json, 'cityId'),
      type: type,
      name: _requiredString(json, 'name'),
      nameEn: _optionalString(json, 'nameEn'),
      nameAm: _optionalString(json, 'nameAm'),
      latitude: _requiredDouble(json, 'latitude'),
      longitude: _requiredDouble(json, 'longitude'),
      customMatchRadiusKm: customMatchRadiusKm,
      polygons: polygons,
    );
  }

  bool get isCity => type == 'city';

  bool get isSubcity => type == 'subcity';

  double get matchRadiusKm => customMatchRadiusKm ?? 0;

  bool contains({required double latitude, required double longitude}) {
    if (!isSubcity) return false;
    for (final polygon in polygons) {
      if (!_ringContainsPoint(
        polygon.first,
        latitude: latitude,
        longitude: longitude,
      )) {
        continue;
      }
      final insideHole = polygon.skip(1).any(
            (ring) => _ringContainsPoint(
              ring,
              latitude: latitude,
              longitude: longitude,
            ),
          );
      if (!insideHole) return true;
    }
    return false;
  }

  String displayName(String languageCode) {
    if (languageCode.toLowerCase() == 'am') {
      return nameAm ?? name;
    }
    return nameEn ?? name;
  }
}

class OfflinePlaceCoordinate {
  const OfflinePlaceCoordinate({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class OfflinePlaceMatch {
  const OfflinePlaceMatch({required this.place, required this.distanceKm});

  final OfflinePlace place;
  final double distanceKm;
}

Map<String, dynamic> _requiredMap(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException('Gazetteer $key must be a JSON object.');
  }
  return value;
}

List<Map<String, dynamic>> _requiredObjectList(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('Gazetteer $key must be a JSON array.');
  }
  return value.map((entry) {
    if (entry is! Map<String, dynamic>) {
      throw FormatException(
        'Every gazetteer $key entry must be a JSON object.',
      );
    }
    return entry;
  }).toList(growable: false);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Gazetteer $key must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Gazetteer $key must be a non-empty string.');
  }
  return value.trim();
}

double _requiredDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('Gazetteer $key must be a finite number.');
  }
  return value.toDouble();
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('Gazetteer $key must be a finite number.');
  }
  return value.toDouble();
}

List<List<List<OfflinePlaceCoordinate>>> _optionalMultiPolygon(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List || value.isEmpty) {
    throw FormatException('Gazetteer $key must be a non-empty array.');
  }

  return List<List<List<OfflinePlaceCoordinate>>>.unmodifiable(
    value.map((polygonValue) {
      if (polygonValue is! List || polygonValue.isEmpty) {
        throw FormatException(
          'Every gazetteer $key polygon must contain a ring.',
        );
      }
      return List<List<OfflinePlaceCoordinate>>.unmodifiable(
        polygonValue.map((ringValue) {
          if (ringValue is! List || ringValue.length < 4) {
            throw FormatException(
              'Every gazetteer $key ring must contain at least four points.',
            );
          }
          final ring = List<OfflinePlaceCoordinate>.unmodifiable(
            ringValue.map((coordinateValue) {
              if (coordinateValue is! List || coordinateValue.length != 2) {
                throw FormatException(
                  'Every gazetteer $key coordinate must be [longitude, latitude].',
                );
              }
              final longitude = coordinateValue[0];
              final latitude = coordinateValue[1];
              if (longitude is! num ||
                  latitude is! num ||
                  !longitude.toDouble().isFinite ||
                  !latitude.toDouble().isFinite) {
                throw FormatException(
                  'Every gazetteer $key coordinate must be finite.',
                );
              }
              return OfflinePlaceCoordinate(
                latitude: latitude.toDouble(),
                longitude: longitude.toDouble(),
              );
            }),
          );
          final first = ring.first;
          final last = ring.last;
          if (first.latitude != last.latitude ||
              first.longitude != last.longitude) {
            throw FormatException(
              'Every gazetteer $key ring must be closed.',
            );
          }
          return ring;
        }),
      );
    }),
  );
}

bool _ringContainsPoint(
  List<OfflinePlaceCoordinate> ring, {
  required double latitude,
  required double longitude,
}) {
  var inside = false;
  for (var index = 0, previous = ring.length - 1;
      index < ring.length;
      previous = index++) {
    final first = ring[previous];
    final second = ring[index];
    if (_pointIsOnSegment(
      longitude,
      latitude,
      first.longitude,
      first.latitude,
      second.longitude,
      second.latitude,
    )) {
      return true;
    }
    final crossesLatitude =
        (first.latitude > latitude) != (second.latitude > latitude);
    if (crossesLatitude &&
        longitude <
            (second.longitude - first.longitude) *
                    (latitude - first.latitude) /
                    (second.latitude - first.latitude) +
                first.longitude) {
      inside = !inside;
    }
  }
  return inside;
}

bool _pointIsOnSegment(
  double pointX,
  double pointY,
  double firstX,
  double firstY,
  double secondX,
  double secondY,
) {
  const tolerance = 1e-10;
  final cross = (pointY - firstY) * (secondX - firstX) -
      (pointX - firstX) * (secondY - firstY);
  if (cross.abs() > tolerance) return false;
  return pointX >= math.min(firstX, secondX) - tolerance &&
      pointX <= math.max(firstX, secondX) + tolerance &&
      pointY >= math.min(firstY, secondY) - tolerance &&
      pointY <= math.max(firstY, secondY) + tolerance;
}

double _distanceKm(
  double firstLatitude,
  double firstLongitude,
  double secondLatitude,
  double secondLongitude,
) {
  const earthRadiusKm = 6371.0;
  final latitudeDelta = _toRadians(secondLatitude - firstLatitude);
  final longitudeDelta = _toRadians(secondLongitude - firstLongitude);
  final firstLatitudeRadians = _toRadians(firstLatitude);
  final secondLatitudeRadians = _toRadians(secondLatitude);
  final haversine = math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(firstLatitudeRadians) *
          math.cos(secondLatitudeRadians) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return earthRadiusKm *
      2 *
      math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
}

double _toRadians(double degrees) => degrees * math.pi / 180;
