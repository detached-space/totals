import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/repositories/transaction_source_sms_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/account_balance_refresh.dart';
import 'package:totals/utils/account_balance_resolver.dart';
import 'package:totals/utils/sms_message_classifier.dart';

/// Removes leftover Endekise / credit-line rows that were stored as cash.
class CreditLineLedgerRepair {
  CreditLineLedgerRepair._();

  /// Bump when repair logic changes so existing installs re-run cleanup.
  static const int repairVersion = 2;
  static const String _prefsKey = 'credit_line_ledger_repair_version';

  static bool _ranThisProcess = false;

  static void debugReset() {
    _ranThisProcess = false;
  }

  static Future<int> repairOnce() async {
    if (_ranThisProcess) return 0;
    _ranThisProcess = true;

    final prefs = await SharedPreferences.getInstance();
    final completedVersion = prefs.getInt(_prefsKey) ?? 0;
    if (completedVersion >= repairVersion) {
      // Still refresh Telebirr display balances in case account.balance was
      // left polluted while newer wallet SMS exist.
      await _refreshSimAccountBalances(
        transactionRepo: TransactionRepository(),
      );
      return 0;
    }

    final fixed = await repair();
    await prefs.setInt(_prefsKey, repairVersion);
    debugPrint('debug: CreditLineLedgerRepair fixed $fixed rows');
    return fixed;
  }

  static Future<int> repair() async {
    final sourceRepo = TransactionSourceSmsRepository();
    final transactionRepo = TransactionRepository();
    final sourceMessages = await sourceRepo.getAll();
    final sourcesByReference = <String, String>{};
    for (final source in sourceMessages) {
      final reference = source.transactionReference.trim();
      if (reference.isEmpty) continue;
      sourcesByReference[reference] = source.body;
    }

    final obsoleteReferences = <String>{};
    final repaymentReferences = <String>{};
    for (final entry in sourcesByReference.entries) {
      if (SmsMessageClassifier.isTelebirrCreditLineNotice(entry.value)) {
        obsoleteReferences.add(entry.key);
      } else if (SmsMessageClassifier.isTelebirrCreditLineRepayment(
        entry.value,
      )) {
        repaymentReferences.add(entry.key);
      }
    }
    repaymentReferences.removeAll(obsoleteReferences);

    if (obsoleteReferences.isNotEmpty) {
      await transactionRepo.deleteTransactionsByReferences(obsoleteReferences);
    }

    final transactions = await transactionRepo.getTransactions();
    var repairedCount = obsoleteReferences.length;

    for (final transaction in transactions) {
      if (obsoleteReferences.contains(transaction.reference)) continue;

      final sourceBody = sourcesByReference[transaction.reference];
      final isRepayment = repaymentReferences.contains(transaction.reference) ||
          (sourceBody != null &&
              SmsMessageClassifier.isTelebirrCreditLineRepayment(sourceBody));
      final labeledEndekise =
          transactionHasCreditLineWalletBalance(transaction);
      final heuristicLiability =
          _looksLikeUnlabeledTelebirrCreditLineBalance(transaction);
      final looksLikeLiabilityBalance = transaction.bankId == 6 &&
          (transaction.currentBalance?.trim().isNotEmpty ?? false) &&
          (isRepayment ||
              labeledEndekise ||
              heuristicLiability ||
              (sourceBody != null &&
                  SmsMessageClassifier.reportsLiabilityOutstanding(
                    sourceBody,
                  )));

      if (!isRepayment && !looksLikeLiabilityBalance) continue;

      final type = transaction.type?.trim().toUpperCase();
      final alreadyDebit = type == 'DEBIT';
      final hasWalletBalance =
          (transaction.currentBalance ?? '').trim().isNotEmpty;
      if (alreadyDebit &&
          !hasWalletBalance &&
          labeledEndekise &&
          !isRepayment) {
        continue;
      }

      await transactionRepo.saveTransaction(
        transaction.copyWith(
          type: 'DEBIT',
          creditor: (transaction.creditor?.trim().isNotEmpty ?? false)
              ? transaction.creditor
              : 'Endekise',
          receiver: (transaction.receiver?.trim().isNotEmpty ?? false)
              ? transaction.receiver
              : 'Endekise',
          clearCurrentBalance: true,
        ),
        skipAutoCategorization: true,
      );
      repairedCount++;
    }

    await _refreshSimAccountBalances(transactionRepo: transactionRepo);
    return repairedCount;
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
      if (balance == null) {
        // Polluted Endekise outstanding with no later wallet SMS: fall back to
        // the latest non-liability parsed balance, else leave unchanged.
        final walletBalance = latestParsedBalanceAfter(
          transactions.where(
            (transaction) =>
                transaction.bankId == account.bank &&
                !transactionHasCreditLineWalletBalance(transaction),
          ),
        );
        if (walletBalance == null ||
            (walletBalance - account.balance).abs() < 0.0001) {
          continue;
        }
        await accountRepo.saveAccount(
          Account(
            accountNumber: account.accountNumber,
            bank: account.bank,
            balance: walletBalance,
            accountHolderName: account.accountHolderName,
            settledBalance: account.settledBalance,
            pendingCredit: account.pendingCredit,
            profileId: account.profileId,
            smsSubscriptionId: account.smsSubscriptionId,
          ),
        );
        continue;
      }
      if ((balance - account.balance).abs() < 0.0001) continue;
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

  /// Endekise / credit-line SMS often have no account or receipt link and use
  /// the generated `6_<iso>` reference. Their `currentBalance` is outstanding
  /// debt and must not drive the wallet tile.
  static bool _looksLikeUnlabeledTelebirrCreditLineBalance(
    Transaction transaction,
  ) {
    if (transaction.bankId != 6) return false;
    if ((transaction.currentBalance ?? '').trim().isEmpty) return false;
    if ((transaction.accountNumber ?? '').trim().isNotEmpty) return false;
    if ((transaction.transactionLink ?? '').trim().isNotEmpty) return false;
    return RegExp(r'^6_\d{4}-\d{2}-\d{2}T').hasMatch(transaction.reference);
  }
}
