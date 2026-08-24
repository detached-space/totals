import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/repositories/transaction_source_sms_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/account_balance_refresh.dart';
import 'package:totals/utils/sms_message_classifier.dart';

/// Removes leftover Endekise / credit-line rows that were stored as cash.
class CreditLineLedgerRepair {
  CreditLineLedgerRepair._();

  static bool _ranThisProcess = false;

  static void debugReset() {
    _ranThisProcess = false;
  }

  static Future<int> repairOnce() async {
    if (_ranThisProcess) return 0;
    _ranThisProcess = true;
    return repair();
  }

  static Future<int> repair() async {
    final sourceRepo = TransactionSourceSmsRepository();
    final transactionRepo = TransactionRepository();
    final sourceMessages = await sourceRepo.getAll();
    if (sourceMessages.isEmpty) return 0;

    final obsoleteReferences = <String>{};
    for (final source in sourceMessages) {
      if (!SmsMessageClassifier.isTelebirrCreditLineNotice(source.body)) {
        continue;
      }
      final reference = source.transactionReference.trim();
      if (reference.isNotEmpty) obsoleteReferences.add(reference);
    }
    if (obsoleteReferences.isEmpty) return 0;

    await transactionRepo.deleteTransactionsByReferences(obsoleteReferences);
    await _refreshSimAccountBalances(
      transactionRepo: transactionRepo,
    );
    return obsoleteReferences.length;
  }

  static Future<void> _refreshSimAccountBalances({
    required TransactionRepository transactionRepo,
  }) async {
    final accountRepo = AccountRepository();
    final accounts = await accountRepo.getAccounts();
    if (accounts.isEmpty) return;

    final banks = await BankConfigService().getBanks(allowRemoteFetch: false);
    final bankById = <int, Bank>{for (final bank in banks) bank.id: bank};
    final transactions = await transactionRepo.getTransactions();

    for (final account in accounts) {
      final bank = bankById[account.bank];
      if (bank == null || bank.simBased != true) continue;
      final balance = resolveRefreshedAccountBalance(
        account: account,
        bank: bank,
        accounts: accounts,
        banksById: bankById,
        transactions: transactions,
      );
      if (balance == null || (balance - account.balance).abs() < 0.0001) {
        continue;
      }
      await accountRepo.saveAccount(
        Account(
          accountNumber: account.accountNumber,
          bank: account.bank,
          balance: balance,
          accountHolderName: account.accountHolderName,
          settledBalance: account.settledBalance,
          pendingCredit: account.pendingCredit,
          profileId: account.profileId,
          smsSubscriptionId: account.smsSubscriptionId,
        ),
      );
    }
  }
}
