import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/screens/todays_transactions_page.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/transaction_location.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/transaction_location_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.loadFromString(
      envString: 'SHARED_EXPENSES_URL=https://example.invalid',
    );
  });

  testWidgets('map app-bar title creates and removes a custom place name',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    String? savedName;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => ThemeProvider(initialThemeMode: ThemeMode.light),
          ),
          ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ],
        child: MaterialApp(
          home: TodaysTransactionsPage(
            transactionReferences: const <String>{},
            title: 'CMC area',
            subtitle: '1 transaction',
            onTitleChanged: (name) async {
              savedName = name;
              return name ?? 'CMC area';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('CMC area'));
    await tester.pumpAndSettle();
    expect(find.text('Name this place'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Home');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedName, 'Home');
    expect(find.text('Home'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Edit place name'), findsOneWidget);
    await tester.tap(find.text('Remove name'));
    await tester.pumpAndSettle();

    expect(savedName, isNull);
    expect(find.text('CMC area'), findsOneWidget);
  });

  testWidgets(
      'merged puck groups transactions under editable date-style headers',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final transactions = <Transaction>[
      Transaction(
        amount: 20,
        reference: 'home-one',
        receiver: 'Home one',
        bankId: 1,
        type: 'DEBIT',
      ),
      Transaction(
        amount: 30,
        reference: 'office-one',
        receiver: 'Office one',
        bankId: 1,
        type: 'DEBIT',
      ),
      Transaction(
        amount: 40,
        reference: 'home-two',
        receiver: 'Home two',
        bankId: 1,
        type: 'DEBIT',
      ),
    ];
    final transactionProvider = _MapTransactionProvider(transactions);
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(transactionProvider.dispose);
    addTearDown(themeProvider.dispose);
    Set<String>? renamedReferences;
    String? renamedValue;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<TransactionProvider>.value(
            value: transactionProvider,
          ),
        ],
        child: MaterialApp(
          home: TodaysTransactionsPage(
            transactionReferences: transactions
                .map((transaction) => transaction.reference)
                .toSet(),
            title: 'Home + (1)',
            subtitle: '3 transactions',
            locationGroupEntries: const <TransactionLocationGroupEntry>[
              TransactionLocationGroupEntry(
                transactionReference: 'home-one',
                fallbackName: 'Bole',
                customName: 'Home',
              ),
              TransactionLocationGroupEntry(
                transactionReference: 'office-one',
                fallbackName: 'Kazanchis',
                customName: 'Office',
              ),
              TransactionLocationGroupEntry(
                transactionReference: 'home-two',
                fallbackName: 'Bole',
                customName: 'Home',
              ),
            ],
            onLocationGroupNameChanged: (references, value) async {
              renamedReferences = references;
              renamedValue = value;
              return value;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final homeHeader = find.byKey(
      const ValueKey<String>('transaction-location-section-home'),
    );
    final officeHeader = find.byKey(
      const ValueKey<String>('transaction-location-section-office'),
    );
    final homeOne = find.byKey(
      const ValueKey<String>('transaction-list-item-home-one'),
    );
    final homeTwo = find.byKey(
      const ValueKey<String>('transaction-list-item-home-two'),
    );
    final officeOne = find.byKey(
      const ValueKey<String>('transaction-list-item-office-one'),
    );
    expect(homeHeader, findsOneWidget);
    expect(officeHeader, findsOneWidget);
    expect(
      find.descendant(of: homeHeader, matching: find.byType(Divider)),
      findsNothing,
    );
    final homeHeaderText = find.descendant(
      of: homeHeader,
      matching: find.text('Home'),
    );
    final homeHeaderTextWidget = tester.widget<Text>(homeHeaderText);
    expect(homeHeaderTextWidget.style?.fontSize, 15);
    expect(homeHeaderTextWidget.style?.fontWeight, FontWeight.w600);
    expect(
      tester.getTopLeft(homeHeaderText).dx,
      closeTo(tester.getTopLeft(homeOne).dx, 0.1),
    );
    expect(
      tester.getTopLeft(homeHeader).dy,
      lessThan(tester.getTopLeft(homeOne).dy),
    );
    expect(
      tester.getTopLeft(homeOne).dy,
      lessThan(tester.getTopLeft(homeTwo).dy),
    );
    expect(
      tester.getTopLeft(homeTwo).dy,
      lessThan(tester.getTopLeft(officeHeader).dy),
    );
    expect(
      tester.getTopLeft(officeHeader).dy,
      lessThan(tester.getTopLeft(officeOne).dy),
    );

    final homeToggle = find.byKey(
      const ValueKey<String>('transaction-location-section-toggle-home'),
    );
    final officeToggle = find.byKey(
      const ValueKey<String>('transaction-location-section-toggle-office'),
    );
    expect(
      tester.getTopLeft(homeToggle).dx,
      greaterThan(tester.getTopRight(homeHeaderText).dx),
    );
    await tester.tap(homeToggle);
    await tester.pumpAndSettle();
    expect(homeHeader, findsOneWidget);
    expect(homeOne, findsNothing);
    expect(homeTwo, findsNothing);
    expect(officeOne, findsOneWidget);
    expect(find.text('Edit place name'), findsNothing);

    await tester.tap(officeToggle);
    await tester.pumpAndSettle();
    expect(officeOne, findsNothing);
    await tester.tap(homeToggle);
    await tester.pumpAndSettle();
    expect(homeOne, findsOneWidget);
    expect(homeTwo, findsOneWidget);
    expect(officeOne, findsNothing);
    await tester.tap(officeToggle);
    await tester.pumpAndSettle();
    await tester.tap(homeToggle);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey<String>('transaction-location-section-edit-home'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'House');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(renamedReferences, <String>{'home-one', 'home-two'});
    expect(renamedValue, 'House');
    expect(
      find.byKey(
        const ValueKey<String>('transaction-location-section-house'),
      ),
      findsOneWidget,
    );
    expect(officeHeader, findsOneWidget);
    expect(homeOne, findsNothing);
    expect(homeTwo, findsNothing);
    expect(officeOne, findsOneWidget);
    await tester.tap(find.byKey(
      const ValueKey<String>('transaction-location-section-toggle-house'),
    ));
    await tester.pumpAndSettle();
    expect(homeOne, findsOneWidget);
    expect(homeTwo, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('merged puck transactions can be filtered by location name',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final transactions = <Transaction>[
      Transaction(
        amount: 20,
        reference: 'home-filter',
        receiver: 'Home transaction',
        bankId: 1,
        type: 'DEBIT',
      ),
      Transaction(
        amount: 30,
        reference: 'office-filter',
        receiver: 'Office transaction',
        bankId: 2,
        type: 'DEBIT',
      ),
    ];
    final transactionProvider = _MapTransactionProvider(transactions);
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    final locationRepository = _StalledTransactionLocationRepository();
    addTearDown(transactionProvider.dispose);
    addTearDown(themeProvider.dispose);
    addTearDown(locationRepository.complete);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<TransactionProvider>.value(
            value: transactionProvider,
          ),
        ],
        child: MaterialApp(
          home: TodaysTransactionsPage(
            transactionReferences: transactions
                .map((transaction) => transaction.reference)
                .toSet(),
            locationGroupEntries: const <TransactionLocationGroupEntry>[
              TransactionLocationGroupEntry(
                transactionReference: 'home-filter',
                fallbackName: 'Bole',
                customName: 'Home',
              ),
              TransactionLocationGroupEntry(
                transactionReference: 'office-filter',
                fallbackName: 'Kazanchis',
                customName: 'Office',
              ),
            ],
            transactionLocationRepository: locationRepository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filter Transactions'));
    await tester.pumpAndSettle();

    expect(locationRepository.loadCount, 1);
    expect(find.text('LOCATION'), findsOneWidget);
    for (final optionsKey in <String>[
      'today-filter-bank-options',
      'today-filter-account-options',
      'today-filter-category-options',
      'today-filter-location-options',
    ]) {
      final optionStrip = tester.widget<SingleChildScrollView>(
        find.byKey(ValueKey<String>(optionsKey)),
      );
      expect(optionStrip.scrollDirection, Axis.horizontal);
    }
    final homeLocationChip = find.widgetWithText(ChoiceChip, 'Home');
    await tester.ensureVisible(homeLocationChip);
    await tester.pumpAndSettle();
    await tester.tap(homeLocationChip);
    await tester.pump();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('transaction-list-item-home-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('transaction-list-item-office-filter'),
      ),
      findsNothing,
    );
  });
}

class _MapTransactionProvider extends TransactionProvider {
  _MapTransactionProvider(this._transactions);

  final List<Transaction> _transactions;

  @override
  List<Transaction> get allTransactions => _transactions;
}

class _StalledTransactionLocationRepository
    implements TransactionLocationRepository {
  final Completer<List<TransactionLocation>> _completer =
      Completer<List<TransactionLocation>>();
  int loadCount = 0;

  @override
  Future<List<TransactionLocation>> getTransactionLocations() {
    loadCount++;
    return _completer.future;
  }

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete(const <TransactionLocation>[]);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
