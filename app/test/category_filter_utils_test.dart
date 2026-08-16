import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/category_filter_utils.dart';

void main() {
  test('uncategorized filter matches only transactions without categories', () {
    final uncategorized = Transaction(
      amount: 10,
      reference: 'uncategorized',
    );
    final categorized = Transaction(
      amount: 10,
      reference: 'categorized',
      categoryIds: const <int>[7],
    );

    expect(
      matchesTransactionCategoryFilter(
        uncategorized,
        uncategorizedCategoryFilterId,
      ),
      isTrue,
    );
    expect(
      matchesTransactionCategoryFilter(
        categorized,
        uncategorizedCategoryFilterId,
      ),
      isFalse,
    );
    expect(matchesTransactionCategoryFilter(categorized, 7), isTrue);
    expect(matchesTransactionCategoryFilter(uncategorized, null), isTrue);
  });

  test('multiple category filters match any selected category', () {
    final categorized = Transaction(
      amount: 10,
      reference: 'categorized',
      categoryIds: const <int>[7, 8],
    );
    final uncategorized = Transaction(
      amount: 10,
      reference: 'uncategorized',
    );

    expect(
      matchesTransactionCategoryFilters(categorized, const <int>{5, 8}),
      isTrue,
    );
    expect(
      matchesTransactionCategoryFilters(categorized, const <int>{5, 6}),
      isFalse,
    );
    expect(
      matchesTransactionCategoryFilters(
        uncategorized,
        const <int>{uncategorizedCategoryFilterId, 7},
      ),
      isTrue,
    );
  });

  test('derived Self category is not treated as uncategorized', () {
    final detectedSelfTransfer = Transaction(
      amount: 10,
      reference: 'detected-self-transfer',
      type: 'DEBIT',
    );

    expect(
      matchesTransactionCategoryFilters(
        detectedSelfTransfer,
        const <int>{uncategorizedCategoryFilterId},
        effectiveCategoryIds: const <int>[],
        hasDerivedCategory: true,
      ),
      isFalse,
    );
    expect(
      matchesTransactionCategoryFilters(
        detectedSelfTransfer,
        const <int>{4},
        effectiveCategoryIds: const <int>[4],
        hasDerivedCategory: true,
      ),
      isTrue,
    );
  });

  test('self categories lead regular categories with expense before income',
      () {
    const categories = <Category>[
      Category(id: 1, name: 'Salary', essential: true, flow: 'income'),
      Category(id: 2, name: 'Self', essential: false, flow: 'income'),
      Category(id: 3, name: 'Groceries', essential: true, flow: 'expense'),
      Category(id: 4, name: 'Self', essential: false, flow: 'expense'),
    ];

    final ordered = orderedCategoriesForFilter(categories);

    expect(ordered.map((category) => category.id), <int>[4, 2, 3, 1]);
  });
}
