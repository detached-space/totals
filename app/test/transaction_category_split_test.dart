import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/widgets/transaction_category_sheet.dart';
import 'package:totals/_redesign/widgets/transaction_split_sheet.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/transaction_category_split.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/financial_insights.dart';
import 'package:totals/utils/map_keys.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(
      envString: 'SHARED_EXPENSES_URL=https://example.invalid',
    );
  });

  group('Transaction category splits', () {
    test('round-trips exact minor-unit allocations', () {
      final transaction = Transaction(
        amount: 100.01,
        reference: 'split-round-trip',
        type: 'DEBIT',
        categorySplits: const <TransactionCategorySplit>[
          TransactionCategorySplit(categoryId: 1, amountMinor: 3333),
          TransactionCategorySplit(categoryId: 2, amountMinor: 6668),
        ],
      );

      expect(transaction.hasCategorySplit, isTrue);
      expect(transaction.selectedCategoryIds, <int>[1, 2]);
      expect(transaction.categoryId, 1);

      final restored = Transaction.fromJson(transaction.toJson());
      expect(restored.hasCategorySplit, isTrue);
      expect(restored.categorySplits, transaction.categorySplits);
    });

    test('scales split shares without losing a cent', () {
      final transaction = Transaction(
        amount: 100.01,
        reference: 'split-scaling',
        type: 'DEBIT',
        categorySplits: const <TransactionCategorySplit>[
          TransactionCategorySplit(categoryId: 1, amountMinor: 3333),
          TransactionCategorySplit(categoryId: 2, amountMinor: 6668),
        ],
      );

      final amounts = transaction.categoryAmounts(totalAmount: 90);
      expect(amounts[1], 29.99);
      expect(amounts[2], 60.01);
      expect(amounts.values.fold<double>(0, (sum, value) => sum + value), 90);
    });

    test('category-filtered totals use only the selected split share', () {
      final provider = _CategorySplitTestProvider();
      addTearDown(provider.dispose);
      final bakeryOnly = Transaction(
        amount: 1000,
        reference: 'bakery-whole',
        type: 'DEBIT',
        categoryId: 1,
        categoryIds: const <int>[1],
      );
      final evenlySplit = Transaction(
        amount: 1000,
        reference: 'bakery-split',
        type: 'DEBIT',
        categorySplits: const <TransactionCategorySplit>[
          TransactionCategorySplit(categoryId: 1, amountMinor: 50000),
          TransactionCategorySplit(categoryId: 2, amountMinor: 50000),
        ],
      );

      final bakeryTotal = <Transaction>[bakeryOnly, evenlySplit].fold<double>(
        0,
        (sum, transaction) =>
            sum + provider.amountForCategorySelection(transaction, const {1}),
      );

      expect(
        provider.amountForCategorySelection(evenlySplit, const {1}),
        500,
      );
      expect(
        provider.categoryAmountsForSelection(evenlySplit, const {1}),
        const <int?, double>{1: 500},
      );
      expect(bakeryTotal, 1500);

      final bakeryInsights = InsightsService(
        () => <Transaction>[bakeryOnly, evenlySplit],
        getCategoryById: provider.getCategoryById,
        expenseAmountForTransaction: (transaction) =>
            provider.amountForCategorySelection(transaction, const {1}),
        categoryAmountsForTransaction: (transaction) =>
            provider.categoryAmountsForSelection(transaction, const {1}),
      ).summarize();
      expect(bakeryInsights[MapKeys.totalExpense], 1500);
      final patterns = bakeryInsights[MapKeys.patterns] as Map<String, dynamic>;
      expect(patterns[MapKeys.essentialSpend], 1500);
      expect(patterns[MapKeys.nonEssentialSpend], 0);
    });

    test('unsplit multi-category records remain filter-compatible', () {
      final provider = _CategorySplitTestProvider();
      addTearDown(provider.dispose);
      final transaction = Transaction(
        amount: 1000,
        reference: 'legacy-unsplit-categories',
        type: 'DEBIT',
        categoryId: 1,
        categoryIds: const <int>[1, 2],
      );

      expect(transaction.hasCategorySplit, isFalse);
      expect(
        provider.amountForCategorySelection(transaction, const {2}),
        1000,
      );
      expect(
        provider.categoryAmountsForSelection(transaction, const {2}),
        const <int?, double>{2: 1000},
      );
      expect(
        provider.amountForCategorySelection(transaction, const {1, 2}),
        1000,
      );
    });

    test('choosing a whole category clears an existing split', () {
      final split = Transaction(
        amount: 50,
        reference: 'clear-split',
        type: 'DEBIT',
        categorySplits: const <TransactionCategorySplit>[
          TransactionCategorySplit(categoryId: 1, amountMinor: 2000),
          TransactionCategorySplit(categoryId: 2, amountMinor: 3000),
        ],
      );

      final whole = split.copyWith(
        categoryId: 3,
        categoryIds: const <int>[3],
      );

      expect(whole.hasCategorySplit, isFalse);
      expect(whole.categorySplits, isNull);
      expect(whole.selectedCategoryIds, <int>[3]);
    });

    test('formats each saved amount for the transaction details preview', () {
      final transaction = Transaction(
        amount: 100,
        reference: 'split-summary',
        type: 'DEBIT',
        categorySplits: const <TransactionCategorySplit>[
          TransactionCategorySplit(categoryId: 1, amountMinor: 3333),
          TransactionCategorySplit(categoryId: 2, amountMinor: 6667),
        ],
      );

      expect(
        transactionSplitAmountSummary(transaction),
        'ETB 33.33 + ETB 66.67',
      );
    });
  });

  testWidgets('editor keeps the final part as an exact remainder',
      (tester) async {
    final transaction = Transaction(
      amount: 100,
      reference: 'split-widget',
      type: 'DEBIT',
      categoryId: 1,
      categoryIds: <int>[1, 2],
    );
    const categories = <Category>[
      Category(
        id: 1,
        name: 'Food',
        essential: true,
        flow: 'expense',
        iconKey: 'restaurant',
      ),
      Category(
        id: 2,
        name: 'Household',
        essential: true,
        flow: 'expense',
        iconKey: 'home',
      ),
    ];
    List<TransactionCategorySplit>? savedSplits;
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(themeProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<Transaction>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => TransactionSplitSheet(
                      transaction: transaction,
                      categories: categories,
                      onSave: (splits) async {
                        savedSplits = splits;
                        return transaction.copyWith(categorySplits: splits);
                      },
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('split-part-0-color-dot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('split-part-1-color-dot')),
      findsOneWidget,
    );
    expect(find.textContaining('gets the remaining'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('split-part-0-amount')),
      '33.33',
    );
    await tester.pump();

    expect(find.text('ETB 66.67'), findsWidgets);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('save-transaction-split')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('save-transaction-split')),
    );
    await tester.pumpAndSettle();

    expect(savedSplits, isNotNull);
    expect(savedSplits, hasLength(2));
    expect(savedSplits![0].amountMinor, 3333);
    expect(savedSplits![1].amountMinor, 6667);
    expect(
      savedSplits!.fold<int>(0, (sum, split) => sum + split.amountMinor),
      10000,
    );
  });

  testWidgets('a second category opens the standalone amount sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transactionProvider = _CategorySplitTestProvider();
    addTearDown(transactionProvider.dispose);
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(themeProvider.dispose);
    final transaction = Transaction(
      amount: 100,
      reference: 'split-auto-open',
      type: 'DEBIT',
      categoryId: 1,
      categoryIds: const <int>[1],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTransactionCategorySheet(
                  context: context,
                  transaction: transaction,
                  provider: transactionProvider,
                  allowAutoCategorizationRuleUpdates: false,
                ),
                child: const Text('Choose categories'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Choose categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Household'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('transaction-split-sheet')),
      findsOneWidget,
    );
    expect(transactionProvider.lastUpdated?.selectedCategoryIds, <int>[2, 1]);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Household'), findsOneWidget);
    expect(find.text('ETB 50.00'), findsOneWidget);
    final firstAmountField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('split-part-0-amount')),
    );
    expect(firstAmountField.controller?.text, '50.00');

    expect(
      find.text(
        "Closing this sheet won't save a split. "
        'Your selected categories will stay as they are.',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('close-transaction-split')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('transaction-split-sheet')),
      findsNothing,
    );
    expect(transactionProvider.lastUpdated?.hasCategorySplit, isFalse);
    expect(transactionProvider.lastUpdated?.selectedCategoryIds, <int>[2, 1]);
  });

  testWidgets('closing the editor keeps an existing split unchanged',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transactionProvider = _CategorySplitTestProvider();
    addTearDown(transactionProvider.dispose);
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(themeProvider.dispose);
    final transaction = Transaction(
      amount: 100,
      reference: 'remove-split-keep-categories',
      type: 'DEBIT',
      categorySplits: const <TransactionCategorySplit>[
        TransactionCategorySplit(categoryId: 1, amountMinor: 4000),
        TransactionCategorySplit(categoryId: 2, amountMinor: 6000),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTransactionSplitSheet(
                  context: context,
                  transaction: transaction,
                  provider: transactionProvider,
                ),
                child: const Text('Edit split'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit split'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Closing this sheet won't save your edits. "
        'Your current split will stay as it is.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('close-transaction-split')),
    );
    await tester.pumpAndSettle();

    expect(transactionProvider.lastUpdated, isNull);
    expect(transaction.hasCategorySplit, isTrue);
    expect(transaction.selectedCategoryIds, <int>[1, 2]);
  });

  testWidgets('the category picker does not show an amount split action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transactionProvider = _CategorySplitTestProvider();
    addTearDown(transactionProvider.dispose);
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(themeProvider.dispose);
    final transaction = Transaction(
      amount: 100,
      reference: 'split-category-picker',
      type: 'DEBIT',
      categorySplits: const <TransactionCategorySplit>[
        TransactionCategorySplit(categoryId: 1, amountMinor: 4000),
        TransactionCategorySplit(categoryId: 2, amountMinor: 6000),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTransactionCategorySheet(
                  context: context,
                  transaction: transaction,
                  provider: transactionProvider,
                  allowAutoCategorizationRuleUpdates: false,
                ),
                child: const Text('Open category picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open category picker'));
    await tester.pumpAndSettle();

    expect(find.text('Amount split'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('transaction-split-sheet')),
      findsNothing,
    );
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Household'), findsOneWidget);
  });
}

class _CategorySplitTestProvider extends TransactionProvider {
  static const List<Category> _testCategories = <Category>[
    Category(
      id: 1,
      name: 'Food',
      essential: true,
      flow: 'expense',
      iconKey: 'restaurant',
    ),
    Category(
      id: 2,
      name: 'Household',
      essential: false,
      flow: 'expense',
      iconKey: 'home',
    ),
  ];

  Transaction? lastUpdated;

  @override
  List<Category> get categories => _testCategories;

  @override
  Category? getCategoryById(int? id) {
    for (final category in _testCategories) {
      if (category.id == id) return category;
    }
    return null;
  }

  @override
  Future<Transaction> updateCategoriesForTransaction(
    Transaction transaction, {
    required List<int> categoryIds,
    int? primaryCategoryId,
  }) async {
    final updated = transaction.copyWith(
      categoryId: primaryCategoryId,
      categoryIds: categoryIds,
    );
    lastUpdated = updated;
    return updated;
  }
}
