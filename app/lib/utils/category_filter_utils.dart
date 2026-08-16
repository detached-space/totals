import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/account_sort.dart';

/// Reserved filter value for transactions that have no assigned categories.
const int uncategorizedCategoryFilterId = -1;

bool matchesTransactionCategoryFilters(
  Transaction transaction,
  Set<int> categoryIds, {
  Iterable<int>? effectiveCategoryIds,
  bool hasDerivedCategory = false,
}) {
  if (categoryIds.isEmpty) return true;

  final transactionCategoryIds = effectiveCategoryIds == null
      ? transaction.selectedCategoryIds.toSet()
      : effectiveCategoryIds.where((id) => id > 0).toSet();

  if (categoryIds.contains(uncategorizedCategoryFilterId) &&
      transactionCategoryIds.isEmpty &&
      !hasDerivedCategory) {
    return true;
  }

  return transactionCategoryIds.any(categoryIds.contains);
}

bool matchesTransactionCategoryFilter(
  Transaction transaction,
  int? categoryId, {
  Iterable<int>? effectiveCategoryIds,
  bool hasDerivedCategory = false,
}) {
  return matchesTransactionCategoryFilters(
    transaction,
    categoryId == null ? const <int>{} : <int>{categoryId},
    effectiveCategoryIds: effectiveCategoryIds,
    hasDerivedCategory: hasDerivedCategory,
  );
}

bool isSelfCategoryFilter(Category category) =>
    category.name.trim().toLowerCase() == 'self';

List<Category> orderedCategoriesForFilter(
  Iterable<Category> categories,
) {
  final ordered = categories
      .where((category) => category.id != null)
      .toList(growable: true);
  ordered.sort(_compareCategoryFilters);
  return ordered;
}

int _compareCategoryFilters(Category left, Category right) {
  final specialComparison =
      _categoryFilterRank(left).compareTo(_categoryFilterRank(right));
  if (specialComparison != 0) return specialComparison;

  final nameComparison = compareDisplayText(left.name, right.name);
  if (nameComparison != 0) return nameComparison;

  final flowComparison =
      _categoryFlowRank(left.flow).compareTo(_categoryFlowRank(right.flow));
  if (flowComparison != 0) return flowComparison;

  return (left.id ?? 0).compareTo(right.id ?? 0);
}

int _categoryFilterRank(Category category) {
  if (!isSelfCategoryFilter(category)) return 2;
  return _categoryFlowRank(category.flow);
}

int _categoryFlowRank(String flow) {
  switch (flow.trim().toLowerCase()) {
    case 'expense':
      return 0;
    case 'income':
      return 1;
    default:
      return 2;
  }
}
