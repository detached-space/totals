import 'package:totals/utils/account_reconciliation.dart';

class BankSummary {
  final int bankId;
  final double totalCredit;
  final double totalDebit;
  final double settledBalance;
  final double pendingCredit;
  final double totalBalance;
  final int accountCount;
  final double transferIn;
  final double transferOut;
  final double feesAndVat;
  final double unreconciledAdjustment;
  final int reconciliationMismatchCount;
  final List<String> reconciliationTransactionReferences;
  final List<ReconciliationMismatchPeriod> reconciliationMismatchPeriods;

  BankSummary(
      {required this.accountCount,
      required this.bankId,
      required this.totalCredit,
      required this.totalDebit,
      required this.settledBalance,
      required this.totalBalance,
      required this.pendingCredit,
      this.transferIn = 0.0,
      this.transferOut = 0.0,
      this.feesAndVat = 0.0,
      this.unreconciledAdjustment = 0.0,
      this.reconciliationMismatchCount = 0,
      this.reconciliationTransactionReferences = const <String>[],
      this.reconciliationMismatchPeriods =
          const <ReconciliationMismatchPeriod>[]});
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
  final double transferIn;
  final double transferOut;
  final double feesAndVat;
  final double? reconciliationOpeningBalance;
  final double? reconciliationClosingBalance;
  final double? reconciliationExpectedClosingBalance;
  final double unreconciledAdjustment;
  final int reconciliationMismatchCount;
  final List<String> reconciliationTransactionReferences;
  final List<ReconciliationMismatchPeriod> reconciliationMismatchPeriods;
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
      this.isDefault = false,
      this.transferIn = 0.0,
      this.transferOut = 0.0,
      this.feesAndVat = 0.0,
      this.reconciliationOpeningBalance,
      this.reconciliationClosingBalance,
      this.reconciliationExpectedClosingBalance,
      this.unreconciledAdjustment = 0.0,
      this.reconciliationMismatchCount = 0,
      this.reconciliationTransactionReferences = const <String>[],
      this.reconciliationMismatchPeriods =
          const <ReconciliationMismatchPeriod>[]});
}

class AllSummary {
  final double totalCredit;
  final double totalDebit;
  final int banks;
  final int accounts;
  final double totalBalance;
  final double transferIn;
  final double transferOut;
  final double feesAndVat;
  final double unreconciledAdjustment;
  final int reconciliationMismatchCount;
  final List<String> reconciliationTransactionReferences;
  final List<ReconciliationMismatchPeriod> reconciliationMismatchPeriods;

  AllSummary(
      {required this.totalCredit,
      required this.totalDebit,
      required this.banks,
      required this.totalBalance,
      required this.accounts,
      this.transferIn = 0.0,
      this.transferOut = 0.0,
      this.feesAndVat = 0.0,
      this.unreconciledAdjustment = 0.0,
      this.reconciliationMismatchCount = 0,
      this.reconciliationTransactionReferences = const <String>[],
      this.reconciliationMismatchPeriods =
          const <ReconciliationMismatchPeriod>[]});
}
