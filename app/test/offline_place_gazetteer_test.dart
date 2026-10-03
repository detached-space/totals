import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/offline_place_gazetteer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflinePlaceGazetteer gazetteer;

  setUpAll(() async {
    gazetteer = await OfflinePlaceGazetteer.loadEthiopianCities();
  });

  test('bundled data limits detailed coverage to Addis subcities', () {
    expect(gazetteer.schemaVersion, 3);
    expect(gazetteer.detailedCityId, 'addis_ababa');
    expect(
      gazetteer.sources.map((source) => source.id),
      containsAll(<String>[
        'overture_divisions',
        'overture_places',
        'addis_cadastre',
      ]),
    );
    expect(gazetteer.cities, hasLength(23));
    expect(gazetteer.places, hasLength(34));
    expect(
      gazetteer.places
          .map((place) => '${place.sourceId}/${place.sourceRecordId}')
          .toSet(),
      hasLength(gazetteer.places.length),
    );

    for (final city in gazetteer.cities) {
      final cityRecords = gazetteer.places.where(
        (place) => place.cityId == city.id && place.isCity,
      );
      final subcityRecords = gazetteer.places.where(
        (place) => place.cityId == city.id && place.isSubcity,
      );
      expect(cityRecords, hasLength(1), reason: city.name);
      expect(
        subcityRecords,
        hasLength(city.subcityRecordCount),
        reason: city.name,
      );
      expect(
        city.subcityRecordCount,
        city.id == 'addis_ababa' ? 11 : 0,
        reason: city.name,
      );
    }

    for (final subcity in gazetteer.places.where(
      (place) => place.isSubcity,
    )) {
      expect(
        subcity.contains(
          latitude: subcity.latitude,
          longitude: subcity.longitude,
        ),
        isTrue,
        reason: subcity.name,
      );
    }
  });

  test('resolves Addis coordinates only as current subcities', () {
    final cmc = gazetteer.nearestPlace(
      latitude: 9.033,
      longitude: 38.842,
    );
    final bole = gazetteer.nearestPlace(
      latitude: 8.997,
      longitude: 38.787,
    );
    final lemiKura = gazetteer.nearestPlace(
      latitude: 9.01255,
      longitude: 38.8670875,
    );

    expect(cmc?.place.displayName('en'), 'Yeka');
    expect(cmc?.place.displayName('am'), 'የካ');
    expect(cmc?.place.isSubcity, isTrue);
    expect(bole?.place.displayName('en'), 'Bole');
    expect(bole?.place.isSubcity, isTrue);
    expect(lemiKura?.place.displayName('en'), 'Lemi Kura');
    expect(lemiKura?.place.isSubcity, isTrue);
  });

  test('uses city names instead of detailed places outside Addis', () {
    final hawassa = gazetteer.nearestPlace(
      latitude: 7.0493053,
      longitude: 38.4762902,
    );
    final direDawa = gazetteer.nearestPlace(
      latitude: 9.6,
      longitude: 41.84667,
    );
    final bishoftu = gazetteer.nearestPlace(
      latitude: 8.75225,
      longitude: 38.97846,
    );

    expect(hawassa?.place.displayName('en'), 'Hawassa');
    expect(hawassa?.place.isCity, isTrue);
    expect(direDawa?.place.displayName('en'), 'Dire Dawa');
    expect(direDawa?.place.isCity, isTrue);
    expect(bishoftu?.place.displayName('en'), 'Bishoftu');
    expect(bishoftu?.place.isCity, isTrue);
  });

  test('falls back to Addis Ababa outside the official subcity polygons', () {
    final match = gazetteer.nearestPlace(
      latitude: 9.035,
      longitude: 38.65,
    );

    expect(match?.place.displayName('en'), 'Addis Ababa');
    expect(match?.place.isCity, isTrue);
  });

  test('does not invent a city name for an uncovered rural coordinate', () {
    expect(
      gazetteer.nearestPlace(latitude: 5, longitude: 40),
      isNull,
    );
  });

  test('rejects the replaced gazetteer schema', () {
    expect(
      () => OfflinePlaceGazetteer.fromJson('{"schemaVersion":2}'),
      throwsFormatException,
    );
  });
}
