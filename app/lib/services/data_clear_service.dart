import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/budget_repository.dart';
import 'package:totals/repositories/failed_parse_repository.dart';
import 'package:totals/repositories/loan_debt_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/repositories/user_account_repository.dart';
import 'package:totals/services/auto_categorization_service.dart';

class ClearDataSelection {
  final bool financialData;
  final Set<int>? bankIds;
  final bool budgets;
  final bool quickAccessAccounts;
  final bool autoCategorization;
  final bool loansAndDebts;
  final bool failedParses;

  const ClearDataSelection({
    this.financialData = false,
    this.bankIds,
    this.budgets = false,
    this.quickAccessAccounts = false,
    this.autoCategorization = false,
    this.loansAndDebts = false,
    this.failedParses = false,
  });

  bool get hasSelection =>
      financialData ||
      budgets ||
      quickAccessAccounts ||
      autoCategorization ||
      loansAndDebts ||
      failedParses;
}

class DataClearService {
  Future<void> clear(ClearDataSelection selection) async {
    if (!selection.hasSelection) return;

    if (selection.financialData) {
      final bankIds = selection.bankIds;
      if (bankIds == null) {
        await TransactionRepository().clearAll();
        await AccountRepository().clearAll();
      } else if (bankIds.isNotEmpty) {
        await TransactionRepository().clearBanks(bankIds);
        await AccountRepository().clearBanks(bankIds);
      }
    }
    if (selection.budgets) {
      await BudgetRepository().clearAll();
    }
    if (selection.quickAccessAccounts) {
      await UserAccountRepository().clearAll();
    }
    if (selection.autoCategorization) {
      await AutoCategorizationService.instance.clearAll();
    }
    if (selection.loansAndDebts) {
      await LoanDebtRepository().clearAll();
    }
    if (selection.failedParses) {
      await FailedParseRepository().clear();
    }
  }
}
