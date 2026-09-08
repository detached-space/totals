import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';

/// An assigned Misc category excludes the transaction from reporting, including
/// its fees. Transactions with no assigned category still count normally.
bool isMiscTransaction(
  Transaction transaction, {
  required Category? Function(int?) getCategoryById,
}) {
  return transaction.selectedCategoryIds.any(
    (id) => getCategoryById(id)?.uncategorized == true,
  );
}
