import 'dart:math' as math;

const double spendingMapSameLocationRadiusMeters = 50;
const double _spendingMapClusterRadiusPixels = 70;
const double _earthRadiusMeters = 6371008.8;
const double _metersPerDegree = 111320;

class SpendingMapPlaceSummary {
  const SpendingMapPlaceSummary({
    required this.mainName,
    required this.otherNameCount,
  });

  final String mainName;
  final int otherNameCount;

  String get label =>
      otherNameCount == 0 ? mainName : '$mainName +$otherNameCount';
}

SpendingMapPlaceSummary? summarizeSpendingMapPlaceNames(
  Iterable<String> names, {
  Iterable<String> customNames = const [],
}) {
  final normalizedCustomNames = customNames
      .map((name) => name.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .toSet();
  final frequenciesByName = <String, _PlaceNameFrequency>{};
  for (final rawName in names) {
    final displayName = rawName.trim();
    if (displayName.isEmpty) continue;
    final normalizedName = displayName.toLowerCase();
    final frequency = frequenciesByName[normalizedName];
    if (frequency == null) {
      frequenciesByName[normalizedName] = _PlaceNameFrequency(
        displayName: displayName,
        normalizedName: normalizedName,
      );
    } else {
      frequency.count += 1;
    }
  }
  if (frequenciesByName.isEmpty) return null;

  final frequencies = frequenciesByName.values.toList(growable: false)
    ..sort((first, second) {
      final firstIsCustom =
          normalizedCustomNames.contains(first.normalizedName);
      final secondIsCustom =
          normalizedCustomNames.contains(second.normalizedName);
      if (firstIsCustom != secondIsCustom) return firstIsCustom ? -1 : 1;
      final countComparison = second.count.compareTo(first.count);
      return countComparison != 0
          ? countComparison
          : first.normalizedName.compareTo(second.normalizedName);
    });
  return SpendingMapPlaceSummary(
    mainName: frequencies.first.displayName,
    otherNameCount: frequencies.length - 1,
  );
}

class SpendingMapCluster<T> {
  const SpendingMapCluster({
    required this.members,
    required this.latitude,
    required this.longitude,
  });

  final List<T> members;
  final double latitude;
  final double longitude;
}

double spendingMapGroupingRadiusMeters({
  required double zoom,
  required double latitude,
}) {
  final safeZoom = zoom.isFinite ? zoom : 20;
  final safeLatitude = latitude.isFinite ? latitude.clamp(-85, 85) : 0;
  final latitudeRadians = safeLatitude * math.pi / 180;
  final metersPerPixel =
      156543.03392 * math.cos(latitudeRadians) / math.pow(2, safeZoom);
  return math.max(
    spendingMapSameLocationRadiusMeters,
    metersPerPixel * _spendingMapClusterRadiusPixels,
  );
}

bool spendingMapClusterUsesPuck({
  required int transactionCount,
  required int savedLocationCount,
}) {
  return transactionCount > 0 || savedLocationCount > 1;
}

double spendingMapDistanceMeters({
  required double firstLatitude,
  required double firstLongitude,
  required double secondLatitude,
  required double secondLongitude,
}) {
  final firstLatitudeRadians = firstLatitude * math.pi / 180;
  final secondLatitudeRadians = secondLatitude * math.pi / 180;
  final latitudeDelta = (secondLatitude - firstLatitude) * math.pi / 180;
  final longitudeDelta = (secondLongitude - firstLongitude) * math.pi / 180;
  final latitudeSin = math.sin(latitudeDelta / 2);
  final longitudeSin = math.sin(longitudeDelta / 2);
  final haversine = latitudeSin * latitudeSin +
      math.cos(firstLatitudeRadians) *
          math.cos(secondLatitudeRadians) *
          longitudeSin *
          longitudeSin;
  final angularDistance = 2 *
      math.atan2(
        math.sqrt(haversine.clamp(0, 1)),
        math.sqrt((1 - haversine).clamp(0, 1)),
      );
  return _earthRadiusMeters * angularDistance;
}

List<SpendingMapCluster<T>> clusterSpendingMapLocations<T>({
  required Iterable<T> locations,
  required double Function(T location) latitudeOf,
  required double Function(T location) longitudeOf,
  required String Function(T location) stableKeyOf,
  required double radiusMeters,
}) {
  final sortedLocations = locations.toList(growable: true)
    ..sort((first, second) {
      final keyComparison = stableKeyOf(first).compareTo(stableKeyOf(second));
      if (keyComparison != 0) return keyComparison;
      final latitudeComparison =
          latitudeOf(first).compareTo(latitudeOf(second));
      if (latitudeComparison != 0) return latitudeComparison;
      return longitudeOf(first).compareTo(longitudeOf(second));
    });
  if (sortedLocations.isEmpty) return const [];
  if (!radiusMeters.isFinite || radiusMeters <= 0) {
    throw ArgumentError.value(
      radiusMeters,
      'radiusMeters',
      'The grouping radius must be a positive, finite distance.',
    );
  }

  final referenceLatitude = sortedLocations
          .map(latitudeOf)
          .fold<double>(0, (sum, latitude) => sum + latitude) /
      sortedLocations.length;
  final longitudeScale = math.max(
    _metersPerDegree *
        math.cos(referenceLatitude.clamp(-85, 85) * math.pi / 180),
    1,
  );
  final clustersByCell = <(int, int), List<_SpendingMapClusterBuilder<T>>>{};
  final builders = <_SpendingMapClusterBuilder<T>>[];

  for (final location in sortedLocations) {
    final latitude = latitudeOf(location);
    final longitude = longitudeOf(location);
    final projectedX = longitude * longitudeScale;
    final projectedY = latitude * _metersPerDegree;
    final cellX = (projectedX / radiusMeters).floor();
    final cellY = (projectedY / radiusMeters).floor();

    _SpendingMapClusterBuilder<T>? nearestCluster;
    var nearestDistance = double.infinity;
    // Two cells of padding keeps the lookup safe across the small projection
    // distortion between northern and southern Ethiopia.
    for (var xOffset = -2; xOffset <= 2; xOffset++) {
      for (var yOffset = -2; yOffset <= 2; yOffset++) {
        final candidates = clustersByCell[(
          cellX + xOffset,
          cellY + yOffset,
        )];
        if (candidates == null) continue;
        for (final candidate in candidates) {
          final distance = spendingMapDistanceMeters(
            firstLatitude: latitude,
            firstLongitude: longitude,
            secondLatitude: candidate.anchorLatitude,
            secondLongitude: candidate.anchorLongitude,
          );
          if (distance <= radiusMeters && distance < nearestDistance) {
            nearestCluster = candidate;
            nearestDistance = distance;
          }
        }
      }
    }

    if (nearestCluster != null) {
      nearestCluster.add(location, latitude, longitude);
      continue;
    }

    final cluster = _SpendingMapClusterBuilder<T>(
      firstMember: location,
      latitude: latitude,
      longitude: longitude,
    );
    builders.add(cluster);
    clustersByCell.putIfAbsent(
        (cellX, cellY), () => <_SpendingMapClusterBuilder<T>>[]).add(cluster);
  }

  return builders
      .map(
        (builder) => SpendingMapCluster<T>(
          members: List<T>.unmodifiable(builder.members),
          latitude: builder.latitudeTotal / builder.members.length,
          longitude: builder.longitudeTotal / builder.members.length,
        ),
      )
      .toList(growable: false);
}

class _PlaceNameFrequency {
  _PlaceNameFrequency({
    required this.displayName,
    required this.normalizedName,
  });

  final String displayName;
  final String normalizedName;
  int count = 1;
}

class _SpendingMapClusterBuilder<T> {
  _SpendingMapClusterBuilder({
    required T firstMember,
    required double latitude,
    required double longitude,
  })  : members = <T>[firstMember],
        anchorLatitude = latitude,
        anchorLongitude = longitude,
        latitudeTotal = latitude,
        longitudeTotal = longitude;

  final List<T> members;
  final double anchorLatitude;
  final double anchorLongitude;
  double latitudeTotal;
  double longitudeTotal;

  void add(T member, double latitude, double longitude) {
    members.add(member);
    latitudeTotal += latitude;
    longitudeTotal += longitude;
  }
}
