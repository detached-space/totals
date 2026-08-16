import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';

const reimbursementBuiltInKey = 'income_reimbursement';

bool isReimbursementCategory(Category category) {
  return category.builtInKey?.trim().toLowerCase() == reimbursementBuiltInKey;
}

bool transactionHasReimbursementCategory({
  required Transaction transaction,
  required Iterable<Category> categories,
}) {
  final selectedIds = transaction.selectedCategoryIds.toSet();
  if (selectedIds.isEmpty) return false;
  return categories.any((category) {
    final id = category.id;
    return id != null &&
        selectedIds.contains(id) &&
        isReimbursementCategory(category);
  });
}
