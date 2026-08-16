import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/widgets/transaction_category_sheet.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';

void main() {
  testWidgets('creates and selects a category from the batch sheet',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transactionProvider = _BatchCategoryTestProvider();
    addTearDown(transactionProvider.dispose);
    final transaction = Transaction(
      amount: 25,
      reference: 'batch-new-category',
      time: '2026-07-14T12:00:00.000',
      bankId: 6,
      type: 'DEBIT',
    );
    int? changed;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  changed = await showBatchTransactionCategorySheet(
                    context: context,
                    transactions: <Transaction>[transaction],
                    provider: transactionProvider,
                  );
                },
                child: const Text('Open batch categories'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open batch categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ New'));
    await tester.pumpAndSettle();

    expect(find.text('New expense category'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final applyButton =
        find.byKey(const ValueKey<String>('batch-category-apply'));
    final applyButtonContext = tester.element(applyButton);
    final mediaQuery = MediaQuery.of(applyButtonContext);
    final viewportBottom =
        tester.getBottomRight(find.byType(Scaffold).first).dy;
    final keyboardTop = viewportBottom - mediaQuery.viewInsets.bottom;
    final sheetInset = find.ancestor(
      of: find.text('Apply category'),
      matching: find.byType(AnimatedPadding),
    );
    expect(sheetInset, findsOneWidget);
    final appliedInset = tester
        .widget<AnimatedPadding>(sheetInset)
        .padding
        .resolve(TextDirection.ltr)
        .bottom;
    expect(appliedInset, greaterThan(mediaQuery.viewInsets.bottom));
    expect(
      tester.getBottomRight(applyButton).dy,
      lessThanOrEqualTo(keyboardTop - 24),
    );

    await tester.enterText(find.byType(TextField), 'Weekend');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(transactionProvider.createdCategory?.name, 'Weekend');
    expect(transactionProvider.createdCategory?.flow, 'expense');
    expect(find.text('Weekend'), findsOneWidget);

    await tester.tap(find.text('Apply category'));
    await tester.pumpAndSettle();

    expect(changed, 1);
    expect(transactionProvider.appliedDebitCategory?.name, 'Weekend');
  });
}

class _BatchCategoryTestProvider extends TransactionProvider {
  final List<Category> _testCategories = <Category>[
    const Category(
      id: 1,
      name: 'Food',
      essential: false,
      flow: 'expense',
      colorKey: 'amber',
    ),
  ];

  Category? createdCategory;
  Category? appliedDebitCategory;

  @override
  List<Category> get categories => List<Category>.unmodifiable(_testCategories);

  @override
  Category? getCategoryById(int? id) {
    for (final category in _testCategories) {
      if (category.id == id) return category;
    }
    return null;
  }

  @override
  Future<void> createCategory({
    required String name,
    required bool essential,
    bool uncategorized = false,
    String? iconKey,
    String? colorKey,
    String? description,
    String flow = 'expense',
    bool recurring = false,
  }) async {
    final category = Category(
      id: _testCategories.length + 1,
      name: name,
      essential: essential,
      uncategorized: uncategorized,
      iconKey: iconKey,
      colorKey: colorKey,
      description: description,
      flow: flow,
      recurring: recurring,
    );
    _testCategories.add(category);
    createdCategory = category;
    notifyListeners();
  }

  @override
  Future<int> setCategoriesForTransactionsByType(
    Iterable<Transaction> transactions, {
    Category? debitCategory,
    Category? creditCategory,
  }) async {
    appliedDebitCategory = debitCategory;
    return transactions.length;
  }
}
