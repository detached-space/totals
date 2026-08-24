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
    final repaymentReferences = <String>{};
    for (final source in sourceMessages) {
      final reference = source.transactionReference.trim();
      if (reference.isEmpty) continue;
      if (SmsMessageClassifier.isTelebirrCreditLineNotice(source.body)) {
        obsoleteReferences.add(reference);
      } else if (SmsMessageClassifier.isTelebirrCreditLineRepayment(
        source.body,
      )) {
        repaymentReferences.add(reference);
      }
    }
    repaymentReferences.removeAll(obsoleteReferences);

    if (obsoleteReferences.isNotEmpty) {
      await transactionRepo.deleteTransactionsByReferences(obsoleteReferences);
    }
    for (final reference in repaymentReferences) {
      final existing = await transactionRepo.getTransactionByReference(
        reference,
      );
      if (existing == null) continue;
      final type = existing.type?.trim().toUpperCase();
      final alreadyDebit = type == 'DEBIT';
      final hasWalletBalance = (existing.currentBalance ?? '').trim().isNotEmpty;
      if (alreadyDebit && !hasWalletBalance) continue;
      await transactionRepo.saveTransaction(
        existing.copyWith(
          type: 'DEBIT',
          creditor: (existing.creditor?.trim().isNotEmpty ?? false)
              ? existing.creditor
              : 'Endekise',
          receiver: (existing.receiver?.trim().isNotEmpty ?? false)
              ? existing.receiver
              : 'Endekise',
          clearCurrentBalance: true,
        ),
        skipAutoCategorization: true,
      );
    }
    if (obsoleteReferences.isEmpty && repaymentReferences.isEmpty) return 0;

    await _refreshSimAccountBalances(
      transactionRepo: transactionRepo,
    );
    return obsoleteReferences.length + repaymentReferences.length;
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
