import 'package:totals/models/summary_models.dart';

List<AccountSummary> manualTransactionBankRepresentatives(
  Iterable<AccountSummary> accounts,
) {
  final bankIds = <int>{};
  return accounts
      .where((account) => bankIds.add(account.bankId))
      .toList(growable: false);
}

List<AccountSummary> manualTransactionAccountsForBank(
  Iterable<AccountSummary> accounts,
  int bankId,
) {
  return accounts
      .where((account) => account.bankId == bankId)
      .toList(growable: false);
}

double resolveManualBalanceAfter({
  required double currentBalance,
  required double amount,
  required bool isDebit,
  double? enteredBalanceAfter,
}) {
  return enteredBalanceAfter ?? currentBalance + (isDebit ? -amount : amount);
}
