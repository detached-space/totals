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

    test(
        'an empty manual place joins a transaction puck only inside the zoom radius',
        () {
      const transaction = _MapPoint(
        'transaction:coffee',
        baseLatitude,
        baseLongitude,
      );
      final emptyManualPlace = _MapPoint(
        'saved:home',
        baseLatitude + _latitudeDegreesForMetres(200),
        baseLongitude,
      );
      final overviewClusters = clustersFor(
        <_MapPoint>[transaction, emptyManualPlace],
        radiusMeters: spendingMapGroupingRadiusMeters(
          zoom: 15,
          latitude: baseLatitude,
        ),
      );
      final detailedClusters = clustersFor(
        <_MapPoint>[transaction, emptyManualPlace],
        radiusMeters: spendingMapGroupingRadiusMeters(
          zoom: 18,
          latitude: baseLatitude,
        ),
      );

      expect(overviewClusters, hasLength(1));
      expect(
        overviewClusters.single.members
            .where((point) => point.id.startsWith('transaction:')),
        hasLength(1),
      );
      expect(detailedClusters, hasLength(2));
    });

    test('multiple empty manual places form a puck but one stays a pin', () {
      expect(
        spendingMapClusterUsesPuck(
          transactionCount: 0,
          savedLocationCount: 1,
        ),
        isFalse,
      );
      expect(
        spendingMapClusterUsesPuck(
          transactionCount: 0,
          savedLocationCount: 2,
        ),
        isTrue,
      );
      expect(
        spendingMapClusterUsesPuck(
          transactionCount: 1,
          savedLocationCount: 0,
        ),
        isTrue,
      );
    });

    test('manual-only places merge and separate with the zoom radius', () {
      final manualPlaces = <_MapPoint>[
        const _MapPoint('saved:home', baseLatitude, baseLongitude),
        _MapPoint(
          'saved:office',
          baseLatitude + _latitudeDegreesForMetres(200),
          baseLongitude,
        ),
      ];
      final overviewClusters = clustersFor(
        manualPlaces,
        radiusMeters: spendingMapGroupingRadiusMeters(
          zoom: 15,
          latitude: baseLatitude,
        ),
      );
      final detailedClusters = clustersFor(
        manualPlaces,
        radiusMeters: spendingMapGroupingRadiusMeters(
          zoom: 18,
          latitude: baseLatitude,
        ),
      );

      expect(overviewClusters, hasLength(1));
      expect(
        spendingMapClusterUsesPuck(
          transactionCount: 0,
          savedLocationCount: overviewClusters.single.members.length,
        ),
        isTrue,
      );
      expect(detailedClusters, hasLength(2));
      expect(
        detailedClusters.every(
          (cluster) => !spendingMapClusterUsesPuck(
            transactionCount: 0,
            savedLocationCount: cluster.members.length,
          ),
        ),
        isTrue,
      );
    });
  });

  group('Spending Map place labels', () {
    test('custom names take priority over more frequent bundled names', () {
      final summary = summarizeSpendingMapPlaceNames(
        ['Bole', 'Bole', 'Bole', 'Home'],
        customNames: ['Home'],
      );
      expect(summary!.mainName, 'Home');
      expect(summary.label, 'Home +1');
    });

    test('custom names keep frequency ordering and deterministic ties', () {
      final summary = summarizeSpendingMapPlaceNames(
        ['Bole', 'Bole', 'Bole', 'Home', 'Office', 'Office'],
        customNames: [' home ', 'office'],
      );
      expect(summary!.mainName, 'Office');
      expect(summary.otherNameCount, 2);
      final tied = summarizeSpendingMapPlaceNames(
        ['Bole', 'Bole', 'Office', 'Home'],
        customNames: ['Office', 'Home'],
      );
      expect(tied!.mainName, 'Home');
    });

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
