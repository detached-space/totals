class BankSummary {
  final int bankId;
  final double totalCredit;
  final double totalDebit;
  final double settledBalance;
  final double pendingCredit;
  final double totalBalance;
  final int accountCount;

  BankSummary(
      {required this.accountCount,
      required this.bankId,
      required this.totalCredit,
      required this.totalDebit,
      required this.settledBalance,
      required this.totalBalance,
      required this.pendingCredit});
}

class AccountSummary {
  final int bankId;
  final String accountNumber;
  final String accountHolderName;
  final double totalTransactions;
  final double totalCredit;
  final double totalDebit;
  final double settledBalance;
  final double pendingCredit;
  final double balance;
  final bool includeInTotals;
  final bool isDormant;
  final bool isDefault;
  AccountSummary(
      {required this.bankId,
      required this.accountNumber,
      required this.accountHolderName,
      required this.totalTransactions,
      required this.totalCredit,
      required this.totalDebit,
      required this.settledBalance,
      required this.balance,
      required this.pendingCredit,
      this.includeInTotals = true,
      this.isDormant = false,
      this.isDefault = false});
}

class AllSummary {
  final double totalCredit;
  final double totalDebit;
  final int banks;
  final int accounts;
  final double totalBalance;

  AllSummary(
      {required this.totalCredit,
      required this.totalDebit,
      required this.banks,
      required this.totalBalance,
      required this.accounts});
}
