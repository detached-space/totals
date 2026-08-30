import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/saved_location.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/transaction_location.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/saved_location_repository.dart';
import 'package:totals/repositories/transaction_location_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dotenv.loadFromString(
      envString: 'SHARED_EXPENSES_URL=https://example.invalid',
    );
  });

  testWidgets(
      'transaction details shows inline location choices beneath the row',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final transaction = Transaction(
      amount: 45,
      reference: 'details-location',
      bankId: 1,
      type: 'DEBIT',
    );
    final currentLocation = TransactionLocation(
      transactionReference: transaction.reference,
      latitude: 8.9806,
      longitude: 38.7578,
      capturedAt: DateTime.utc(2026, 8, 28),
      placeName: 'Coffee Shop',
    );
    final locationRepository = _FakeTransactionLocationRepository(
      currentLocation,
      additionalKnownLocations: <TransactionLocation>[
        TransactionLocation(
          transactionReference: 'newer-coffee-shop-transaction',
          latitude: 9.04,
          longitude: 38.82,
          capturedAt: DateTime.utc(2026, 8, 29),
          placeName: 'Coffee Shop',
        ),
        TransactionLocation(
          transactionReference: 'bakery-transaction',
          latitude: 9.01,
          longitude: 38.78,
          capturedAt: DateTime.utc(2026, 8, 27),
          placeName: 'Bakery',
        ),
      ],
    );
    final savedLocationRepository = _FakeSavedLocationRepository(
      <SavedLocation>[
        _savedLocation(id: 'office-id', name: 'Office'),
        _savedLocation(id: 'home-id', name: 'Home'),
      ],
    );
    final transactionProvider = _LocationTestProvider();
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(transactionProvider.dispose);
    addTearDown(themeProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTransactionDetailsSheet(
                  context: context,
                  transaction: transaction,
                  provider: transactionProvider,
                  transactionLocationRepository: locationRepository,
                  savedLocationRepository: savedLocationRepository,
                ),
                child: const Text('Open details'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final locationRow = find.byKey(
      const ValueKey<String>('transaction-details-location-row'),
    );
    expect(locationRow, findsOneWidget);
    expect(find.text('Coffee Shop'), findsWidgets);
    expect(
      tester.getTopLeft(find.text('Location')).dy,
      greaterThan(tester.getTopLeft(find.text('Reason')).dy),
    );

    await tester.ensureVisible(locationRow);
    final locationToggle = find.byKey(
      const ValueKey<String>('transaction-location-toggle'),
    );
    expect(locationToggle, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('transaction-location-picker')),
      findsNothing,
    );
    await tester.tap(locationToggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final locationPicker = find.byKey(
      const ValueKey<String>('transaction-location-picker'),
    );
    expect(locationPicker, findsOneWidget);
    expect(find.text('Saved Locations'), findsNothing);
    expect(find.text('All Locations'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
    expect(find.text('Bakery'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'transaction-saved-location-option-home-id',
        ),
      ),
      findsOneWidget,
    );
    final homeOption = find.byKey(
      const ValueKey<String>('transaction-saved-location-option-home-id'),
    );
    final officeOption = find.byKey(
      const ValueKey<String>('transaction-saved-location-option-office-id'),
    );
    final bakeryOption = find.byKey(
      const ValueKey<String>(
        'transaction-known-location-option-bakery-transaction',
      ),
    );
    final coffeeShopOption = find.byKey(
      const ValueKey<String>(
        'transaction-known-location-option-details-location',
      ),
    );
    final editOption = find.byKey(
      const ValueKey<String>('transaction-location-add-name'),
    );
    expect(editOption, findsOneWidget);
    final locationOptionsWrap =
        find.ancestor(of: coffeeShopOption, matching: find.byType(Wrap)).first;
    expect(
      find.descendant(of: locationOptionsWrap, matching: editOption),
      findsOneWidget,
    );
    expect(_chipIsSelected(tester, coffeeShopOption), isTrue);
    expect(
      tester.getTopLeft(bakeryOption).dx,
      closeTo(tester.getTopLeft(locationPicker).dx, 0.1),
    );
    expect(
      tester.getTopLeft(bakeryOption).dx,
      lessThan(tester.getTopLeft(coffeeShopOption).dx),
    );
    expect(
      tester.getTopLeft(coffeeShopOption).dx,
      lessThan(tester.getTopLeft(homeOption).dx),
    );
    expect(
      tester.getTopLeft(homeOption).dx,
      lessThan(tester.getTopLeft(officeOption).dx),
    );
    expect(find.text('Use approximate location'), findsNothing);
    expect(
      find.descendant(
        of: locationRow,
        matching: find.byType(PopupMenuButton),
      ),
      findsNothing,
    );
    expect(
      tester.getTopLeft(locationPicker).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(locationRow).dy),
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'transaction-saved-location-option-office-id',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(locationRepository.assignedLocationId, 'office-id');
    expect(find.text('Office'), findsWidgets);
    expect(_chipIsSelected(tester, officeOption), isTrue);

    await tester.tap(editOption);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final savedLocationNameField = find.byKey(
      const ValueKey<String>('saved-location-name-field'),
    );
    expect(savedLocationNameField, findsOneWidget);
    await tester.enterText(savedLocationNameField, 'Work');
    await tester.tap(
      find.byKey(const ValueKey<String>('saved-location-save')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(savedLocationRepository.updatedLocation?.name, 'Work');
    expect(find.text('Work'), findsWidgets);
  });

  testWidgets(
      'a saved map location can be assigned to an unlocated transaction',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transaction = Transaction(
      amount: 18,
      reference: 'unlocated-details',
      bankId: 1,
      type: 'DEBIT',
    );
    final locationRepository = _FakeTransactionLocationRepository(null);
    final savedLocationRepository = _FakeSavedLocationRepository(
      <SavedLocation>[_savedLocation(id: 'gym-id', name: 'Gym')],
    );
    final transactionProvider = _LocationTestProvider();
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(transactionProvider.dispose);
    addTearDown(themeProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTransactionDetailsSheet(
                  context: context,
                  transaction: transaction,
                  provider: transactionProvider,
                  transactionLocationRepository: locationRepository,
                  savedLocationRepository: savedLocationRepository,
                ),
                child: const Text('Open unlocated details'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open unlocated details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Not set'), findsWidgets);

    final toggle = find.byKey(
      const ValueKey<String>('transaction-location-toggle'),
    );
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'transaction-saved-location-option-gym-id',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(locationRepository.assignedLocationId, 'gym-id');
    expect(find.text('Gym'), findsWidgets);
    expect(
      _chipIsSelected(
        tester,
        find.byKey(
          const ValueKey<String>(
            'transaction-saved-location-option-gym-id',
          ),
        ),
      ),
      isTrue,
    );
  });

  testWidgets(
      'automatically named transaction locations can be assigned from the left-aligned list',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transaction = Transaction(
      amount: 22,
      reference: 'automatic-location-target',
      bankId: 1,
      type: 'DEBIT',
    );
    final locationRepository = _FakeTransactionLocationRepository(
      null,
      additionalKnownLocations: <TransactionLocation>[
        TransactionLocation(
          transactionReference: 'automatic-location-source',
          latitude: 8.9806,
          longitude: 38.7578,
          capturedAt: DateTime.utc(2026, 8, 27),
        ),
      ],
    );
    final transactionProvider = _LocationTestProvider();
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(transactionProvider.dispose);
    addTearDown(themeProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTransactionDetailsSheet(
                  context: context,
                  transaction: transaction,
                  provider: transactionProvider,
                  transactionLocationRepository: locationRepository,
                  savedLocationRepository:
                      _FakeSavedLocationRepository(const <SavedLocation>[]),
                  loadOfflinePlaceGazetteer: () async =>
                      throw StateError('Use the deterministic regional name.'),
                ),
                child: const Text('Open automatic location details'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open automatic location details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final toggle = find.byKey(
      const ValueKey<String>('transaction-location-toggle'),
    );
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();

    final automaticOption = find.byKey(
      const ValueKey<String>(
        'transaction-known-location-option-automatic-location-source',
      ),
    );
    expect(automaticOption, findsOneWidget);
    expect(find.text('Central Ethiopia'), findsOneWidget);
    await tester.tap(automaticOption);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(locationRepository.assignedKnownName, 'Central Ethiopia');
    expect(locationRepository.assignedKnownLatitude, 8.9806);
    expect(locationRepository.assignedKnownLongitude, 38.7578);
    expect(find.text('Central Ethiopia'), findsWidgets);
  });
}

class _FakeTransactionLocationRepository extends TransactionLocationRepository {
  _FakeTransactionLocationRepository(
    this.location, {
    this.additionalKnownLocations = const <TransactionLocation>[],
  });

  TransactionLocation? location;
  final List<TransactionLocation> additionalKnownLocations;
  String? savedName;
  String? assignedLocationId;
  String? assignedKnownName;
  double? assignedKnownLatitude;
  double? assignedKnownLongitude;

  @override
  Future<List<TransactionLocation>> getForTransactionReferences(
    Set<String> transactionReferences,
  ) async {
    final currentLocation = location;
    return currentLocation != null &&
            transactionReferences.contains(currentLocation.transactionReference)
        ? <TransactionLocation>[currentLocation]
        : const <TransactionLocation>[];
  }

  @override
  Future<List<TransactionLocation>> getTransactionLocations() async {
    return <TransactionLocation>[
      ...additionalKnownLocations.where(
        (knownLocation) =>
            knownLocation.transactionReference !=
            location?.transactionReference,
      ),
      if (location != null) location!,
    ];
  }

  @override
  Future<void> setPlaceNameForTransactionReferences(
    Iterable<String> transactionReferences,
    String? placeName,
  ) async {
    final currentLocation = location;
    if (currentLocation == null ||
        !transactionReferences.contains(currentLocation.transactionReference)) {
      return;
    }
    savedName = normalizeTransactionPlaceName(placeName);
    location = currentLocation.copyWith(
      placeName: savedName,
      clearPlaceName: savedName == null,
    );
  }

  @override
  Future<TransactionLocation> assignSavedLocation({
    required Transaction transaction,
    required SavedLocation savedLocation,
  }) async {
    assignedLocationId = savedLocation.id;
    return location = TransactionLocation(
      transactionReference: transaction.reference,
      latitude: savedLocation.latitude,
      longitude: savedLocation.longitude,
      capturedAt: DateTime.utc(2026, 8, 30),
      placeName: savedLocation.name,
      savedLocationId: savedLocation.id,
    );
  }

  @override
  Future<TransactionLocation> assignLocation({
    required Transaction transaction,
    required double latitude,
    required double longitude,
    required String placeName,
    String? savedLocationId,
  }) async {
    assignedKnownName = placeName;
    assignedKnownLatitude = latitude;
    assignedKnownLongitude = longitude;
    return location = TransactionLocation(
      transactionReference: transaction.reference,
      latitude: latitude,
      longitude: longitude,
      capturedAt: DateTime.utc(2026, 8, 30),
      placeName: placeName,
      savedLocationId: savedLocationId,
    );
  }
}

class _FakeSavedLocationRepository extends SavedLocationRepository {
  _FakeSavedLocationRepository(List<SavedLocation> locations)
      : locations = List<SavedLocation>.of(locations);

  final List<SavedLocation> locations;
  SavedLocation? updatedLocation;

  @override
  Future<List<SavedLocation>> getSavedLocations() async => locations;

  @override
  Future<SavedLocation> updateLocation(
    SavedLocation location, {
    String? name,
    double? latitude,
    double? longitude,
  }) async {
    final updated = location.copyWith(
      name: name,
      latitude: latitude,
      longitude: longitude,
      updatedAt: DateTime.utc(2026, 8, 31),
    );
    updatedLocation = updated;
    final index =
        locations.indexWhere((candidate) => candidate.id == location.id);
    if (index >= 0) locations[index] = updated;
    return updated;
  }
}

bool _chipIsSelected(WidgetTester tester, Finder chip) {
  final semantics = tester.widget<Semantics>(
    find.descendant(of: chip, matching: find.byType(Semantics)).first,
  );
  return semantics.properties.selected ?? false;
}

SavedLocation _savedLocation({required String id, required String name}) {
  return SavedLocation(
    id: id,
    name: name,
    latitude: 9.03,
    longitude: 38.74,
    createdAt: DateTime.utc(2026, 8, 30),
    updatedAt: DateTime.utc(2026, 8, 30),
  );
}

class _LocationTestProvider extends TransactionProvider {
  @override
  List<Category> get categories => const <Category>[];

  @override
  Category? getCategoryById(int? id) => null;
}
