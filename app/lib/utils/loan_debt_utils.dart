import 'package:totals/models/category.dart';
import 'package:totals/models/loan_debt_entry.dart';
import 'package:totals/models/transaction.dart';

bool isLoanDebtCategory(Category category) {
  final key = (category.builtInKey ?? '').trim().toLowerCase();
  final name = category.name.trim().toLowerCase();
  if (key.contains('loan') || key.contains('debt')) return true;
  return name == 'loan' || name == 'loans' || name == 'debt' || name == 'debts';
}

bool transactionHasLoanDebtCategory({
  required Transaction transaction,
  required List<Category> categories,
}) {
  final selectedIds = transaction.selectedCategoryIds.toSet();
  if (selectedIds.isEmpty) return false;
  return categories.any((category) {
    final id = category.id;
    return id != null &&
        selectedIds.contains(id) &&
        isLoanDebtCategory(category);
  });
}

LoanDebtDirection loanDebtDirectionForTransaction(Transaction transaction) {
  return transaction.type?.trim().toUpperCase() == 'CREDIT'
      ? LoanDebtDirection.borrowed
      : LoanDebtDirection.lent;
}
