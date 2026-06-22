import 'package:totals/models/category.dart';
import 'package:totals/models/loan_debt_entry.dart';
import 'package:totals/models/transaction.dart';

bool isLoanDebtCategory(Category category) {
  final key = (category.builtInKey ?? '').trim().toLowerCase();
  final name = category.name.trim().toLowerCase();
  if (key.contains('repayment') || name == 'repayment') return false;
  if (key.contains('loan') || key.contains('debt')) return true;
  return name == 'loan' || name == 'loans' || name == 'debt' || name == 'debts';
}

bool isRepaymentCategory(Category category) {
  final key = (category.builtInKey ?? '').trim().toLowerCase();
  final name = category.name.trim().toLowerCase();
  return key.contains('repayment') || name == 'repayment';
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

bool hasEligibleRepaymentLinkCandidate({
  required Transaction repaymentTransaction,
  required List<Transaction> transactions,
  required List<LoanDebtEntry> entries,
  required List<LoanDebtRepayment> repayments,
}) {
  final repaymentDirection = repaymentDirectionForTransaction(
    repaymentTransaction,
  );
  final currentRepaymentReference = repaymentTransaction.reference.trim();
  final transactionsByReference = <String, Transaction>{
    for (final transaction in transactions)
      if (transaction.reference.trim().isNotEmpty)
        transaction.reference.trim(): transaction,
  };
  final repaidByLoanReference = <String, double>{};

  for (final repayment in repayments) {
    if (repayment.repaymentTransactionReference.trim() ==
        currentRepaymentReference) {
      continue;
    }
    final loanReference = repayment.loanDebtTransactionReference.trim();
    if (loanReference.isEmpty) continue;
    repaidByLoanReference[loanReference] =
        (repaidByLoanReference[loanReference] ?? 0) +
            repayment.appliedAmount.abs();
  }

  for (final entry in entries) {
    final loanReference = entry.transactionReference.trim();
    if (loanReference.isEmpty) continue;
    if (entry.personName.trim().isEmpty) continue;
    if (entry.direction != repaymentDirection) continue;
    if (entry.status != LoanDebtStatus.active) continue;

    final loanTransaction = transactionsByReference[loanReference];
    if (loanTransaction == null) continue;
    final principalAmount = entry.principalAmount;
    final originalAmount = principalAmount != null && principalAmount.isFinite
        ? principalAmount.abs()
        : loanTransaction.amount.abs();
    final remainingAmount =
        originalAmount - (repaidByLoanReference[loanReference] ?? 0);
    if (remainingAmount > 0.005) return true;
  }

  return false;
}

LoanDebtDirection loanDebtDirectionForTransaction(Transaction transaction) {
  return transaction.type?.trim().toUpperCase() == 'CREDIT'
      ? LoanDebtDirection.borrowed
      : LoanDebtDirection.lent;
}

LoanDebtDirection repaymentDirectionForTransaction(Transaction transaction) {
  return transaction.type?.trim().toUpperCase() == 'CREDIT'
      ? LoanDebtDirection.lent
      : LoanDebtDirection.borrowed;
}
