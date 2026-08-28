import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/transaction_location.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/transaction_location_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dotenv.loadFromString(
      envString: 'SHARED_EXPENSES_URL=https://example.invalid',
    );
  });

  testWidgets('transaction details shows and edits the saved location name',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final transaction = Transaction(
      amount: 45,
      reference: 'details-location',
      bankId: 1,
      type: 'DEBIT',
    );
    final locationRepository = _FakeTransactionLocationRepository(
      TransactionLocation(
        transactionReference: transaction.reference,
        latitude: 8.9806,
        longitude: 38.7578,
        capturedAt: DateTime.utc(2026, 8, 28),
        placeName: 'Coffee Shop',
      ),
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

    await tester.ensureVisible(locationRow);
    await tester.tap(locationRow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final editor = find.descendant(
      of: find.byKey(
        const ValueKey<String>('place-name-editor-keyboard-inset'),
      ),
      matching: find.byType(TextField),
    );
    expect(editor, findsOneWidget);
    await tester.enterText(editor, 'Home');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('place-name-editor-save')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(locationRepository.savedName, 'Home');
    expect(find.text('Home'), findsWidgets);
  });
}

class _FakeTransactionLocationRepository extends TransactionLocationRepository {
  _FakeTransactionLocationRepository(this.location);

  TransactionLocation location;
  String? savedName;

  @override
  Future<List<TransactionLocation>> getForTransactionReferences(
    Set<String> transactionReferences,
  ) async {
    return transactionReferences.contains(location.transactionReference)
        ? <TransactionLocation>[location]
        : const <TransactionLocation>[];
  }

  @override
  Future<void> setPlaceNameForTransactionReferences(
    Iterable<String> transactionReferences,
    String? placeName,
  ) async {
    if (!transactionReferences.contains(location.transactionReference)) return;
    savedName = normalizeTransactionPlaceName(placeName);
    location = location.copyWith(
      placeName: savedName,
      clearPlaceName: savedName == null,
    );
  }
}

class _LocationTestProvider extends TransactionProvider {
  @override
  List<Category> get categories => const <Category>[];

  @override
  Category? getCategoryById(int? id) => null;
}
