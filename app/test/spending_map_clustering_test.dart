import 'package:flutter_test/flutter_test.dart';
import 'package:totals/utils/spending_map_clustering.dart';

void main() {
  const baseLatitude = 9.03;
  const baseLongitude = 38.74;

  List<SpendingMapCluster<_MapPoint>> clustersFor(
    List<_MapPoint> points, {
    required double radiusMeters,
  }) {
    return clusterSpendingMapLocations<_MapPoint>(
      locations: points,
      latitudeOf: (point) => point.latitude,
      longitudeOf: (point) => point.longitude,
      stableKeyOf: (point) => point.id,
      radiusMeters: radiusMeters,
    );
  }

  group('Spending Map location grouping', () {
    test('uses 50 metres as the detailed-zoom minimum radius', () {
      expect(
        spendingMapGroupingRadiusMeters(
          zoom: 20,
          latitude: baseLatitude,
        ),
        spendingMapSameLocationRadiusMeters,
      );
    });

    test('groups points inside 50 metres and separates points outside it', () {
      const origin = _MapPoint('origin', baseLatitude, baseLongitude);
      final withinRange = _MapPoint(
        'within',
        baseLatitude + _latitudeDegreesForMetres(49),
        baseLongitude,
      );
      final outsideRange = _MapPoint(
        'outside',
        baseLatitude + _latitudeDegreesForMetres(51),
        baseLongitude,
      );

      expect(
        clustersFor(
          [origin, withinRange],
          radiusMeters: spendingMapSameLocationRadiusMeters,
        ),
        hasLength(1),
      );
      expect(
        clustersFor(
          [origin, outsideRange],
          radiusMeters: spendingMapSameLocationRadiusMeters,
        ),
        hasLength(2),
      );
    });

    test('merges at overview zoom and separates 200 metre points in detail',
        () {
      final points = <_MapPoint>[
        const _MapPoint('first', baseLatitude, baseLongitude),
        _MapPoint(
          'second',
          baseLatitude + _latitudeDegreesForMetres(200),
          baseLongitude,
        ),
      ];
      final overviewRadius = spendingMapGroupingRadiusMeters(
        zoom: 15,
        latitude: baseLatitude,
      );
      final detailedRadius = spendingMapGroupingRadiusMeters(
        zoom: 18,
        latitude: baseLatitude,
      );

      expect(overviewRadius, greaterThan(200));
      expect(detailedRadius, spendingMapSameLocationRadiusMeters);
      expect(
        clustersFor(points, radiusMeters: overviewRadius),
        hasLength(1),
      );
      expect(
        clustersFor(points, radiusMeters: detailedRadius),
        hasLength(2),
      );
    });
  });

  group('Spending Map place labels', () {
    test('uses the most frequent name and counts distinct alternatives', () {
      final summary = summarizeSpendingMapPlaceNames([
        'Bole',
        'Kirkos',
        'Bole',
        'Arada',
      ]);

      expect(summary, isNotNull);
      expect(summary!.mainName, 'Bole');
      expect(summary.otherNameCount, 2);
      expect(summary.label, 'Bole +2');
    });

    test('treats case and surrounding whitespace as the same name', () {
      final summary = summarizeSpendingMapPlaceNames([
        'Home',
        ' home ',
        'Office',
      ]);

      expect(summary, isNotNull);
      expect(summary!.mainName, 'Home');
      expect(summary.otherNameCount, 1);
      expect(summary.label, 'Home +1');
    });

    test('breaks equally frequent name ties deterministically', () {
      final summary = summarizeSpendingMapPlaceNames(['Kirkos', 'Arada']);

      expect(summary, isNotNull);
      expect(summary!.mainName, 'Arada');
      expect(summary.label, 'Arada +1');
    });
  });
}

double _latitudeDegreesForMetres(double metres) => metres / 111195;

class _MapPoint {
  const _MapPoint(this.id, this.latitude, this.longitude);

  final String id;
  final double latitude;
  final double longitude;
}
