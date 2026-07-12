import 'package:totals/models/transaction.dart';

double transactionFeeAmount(Transaction transaction) {
  return _nonNegative(transaction.serviceCharge) +
      _nonNegative(transaction.vat);
}

double transactionDebitOutflow(Transaction transaction) {
  if (transaction.type != 'DEBIT') return 0.0;
  return _principalAmount(transaction) + transactionFeeAmount(transaction);
}

double transactionIncomeAmount(
  Transaction transaction, {
  required bool isSelfTransfer,
}) {
  if (transaction.type != 'CREDIT' || isSelfTransfer) return 0.0;
  return _principalAmount(transaction);
}

double transactionExpenseAmount(
  Transaction transaction, {
  required bool isSelfTransfer,
}) {
  if (transaction.type != 'DEBIT') return 0.0;
  final principal = isSelfTransfer ? 0.0 : _principalAmount(transaction);
  return principal + transactionFeeAmount(transaction);
}

double transactionBalanceDelta(Transaction transaction) {
  if (transaction.type == 'CREDIT') {
    return _principalAmount(transaction);
  }
  if (transaction.type == 'DEBIT') {
    return -transactionDebitOutflow(transaction);
  }
  return 0.0;
}

double _nonNegative(double? value) {
  if (value == null || !value.isFinite || value <= 0) return 0.0;
  return value;
}

double _principalAmount(Transaction transaction) {
  final amount = transaction.amount.abs();
  return amount.isFinite ? amount : 0.0;
}
