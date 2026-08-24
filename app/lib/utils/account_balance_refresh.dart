import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/account_balance_resolver.dart';
import 'package:totals/utils/account_identity.dart';

/// Finds the balance that may safely be persisted for a SIM-backed account.
///
/// A balance-after value is valid only when the transaction belongs to the
/// same bank and account. Older versions compared phone-shaped account numbers
/// across every bank, which allowed a Telebirr balance to leak into CBE Birr.
///
/// Returns `null` when there is no new balance evidence. Returns `0` only when
/// the existing non-zero balance can be traced to that legacy cross-bank leak.
double? resolveRefreshedAccountBalance({
  required Account account,
  required Bank bank,
  required Iterable<Account> accounts,
  required Map<int, Bank> banksById,
  required Iterable<Transaction> transactions,
}) {
  Transaction? latest;
  DateTime? latestTime;

  for (final transaction in transactions) {
    if (transaction.bankId != account.bank ||
        !_profilesCanMatch(account, transaction) ||
        !registeredAccountNumbersMatch(
          bank,
          transaction.ownerAccountNumber,
          account.accountNumber,
        ) ||
        transactionHasCreditLineWalletBalance(transaction) ||
        _parseBalance(transaction.currentBalance) == null) {
      continue;
    }

    final transactionTime = DateTime.tryParse(transaction.time ?? '');
    if (latest == null ||
        (transactionTime != null &&
            (latestTime == null || transactionTime.isAfter(latestTime)))) {
      latest = transaction;
      latestTime = transactionTime;
    }
  }

  final ownBankBalance = _parseBalance(latest?.currentBalance);
  if (ownBankBalance != null) return ownBankBalance;
  if (account.balance.abs() < 0.0001) return null;

  // Repair balances already written by the old unscoped lookup. To avoid
  // clearing a legitimate imported balance, require an exact balance value
  // from another registered account with the same durable phone identity.
  for (final transaction in transactions) {
    final otherBankId = transaction.bankId;
    if (otherBankId == null ||
        otherBankId == account.bank ||
        !_profilesCanMatch(account, transaction)) {
      continue;
    }
    final leakedBalance = _parseBalance(transaction.currentBalance);
    if (leakedBalance == null ||
        (leakedBalance - account.balance).abs() >= 0.0001 ||
        !registeredAccountNumbersMatch(
          bank,
          transaction.ownerAccountNumber,
          account.accountNumber,
        )) {
      continue;
    }

    final otherBank = banksById[otherBankId];
    if (otherBank == null) continue;
    final hasRegisteredSourceAccount = accounts.any(
      (candidate) =>
          candidate.bank == otherBankId &&
          _accountProfilesCanMatch(account, candidate) &&
          registeredAccountNumbersMatch(
            otherBank,
            transaction.ownerAccountNumber,
            candidate.accountNumber,
          ),
    );
    if (hasRegisteredSourceAccount) return 0.0;
  }

  return null;
}

bool _profilesCanMatch(Account account, Transaction transaction) {
  return account.profileId == null ||
      transaction.profileId == null ||
      account.profileId == transaction.profileId;
}

bool _accountProfilesCanMatch(Account left, Account right) {
  return left.profileId == null ||
      right.profileId == null ||
      left.profileId == right.profileId;
}

double? _parseBalance(String? raw) {
  final value = raw?.trim().replaceAll(',', '');
  if (value == null || value.isEmpty) return null;
  return double.tryParse(value);
}
