import 'package:totals/models/account.dart';
import 'package:totals/models/transaction.dart';

String accountBalanceResolverKey(Account account) {
  return '${account.bank}:${account.accountNumber}';
}

double includedAccountBalanceTotal({
  required Iterable<Account> accounts,
  Map<String, double> resolvedBalances = const <String, double>{},
}) {
  return accounts
      .where((account) => account.includeInTotals && !account.isDormant)
      .fold<double>(
        0.0,
        (sum, account) =>
            sum +
            (resolvedBalances[accountBalanceResolverKey(account)] ??
                account.balance),
      );
}

double resolveDisplayedAccountBalance({
  required Account account,
  required List<Transaction> accountTransactions,
  required int bankAccountCount,
  required double cashBalanceDelta,
  required bool isCashAccount,
}) {
  if (isCashAccount) {
    return account.balance + cashBalanceDelta;
  }

  // For banks with a single linked account, the latest SMS "balance after"
  // is the most reliable remaining balance to show in the UI.
  if (bankAccountCount == 1) {
    final latestBalanceAfter = latestParsedBalanceAfter(accountTransactions);
    if (latestBalanceAfter != null) {
      return latestBalanceAfter;
    }
  }

  return account.balance;
}

double? latestParsedBalanceAfter(Iterable<Transaction> transactions) {
  double? latestBalance;
  DateTime? latestTime;

  for (final transaction in transactions) {
    if (transactionHasCreditLineWalletBalance(transaction)) continue;
    final parsedBalance = _parseBalance(transaction.currentBalance);
    if (parsedBalance == null) continue;

    final transactionTime = _parseTransactionTime(transaction.time);
    if (latestBalance == null) {
      latestBalance = parsedBalance;
      latestTime = transactionTime;
      continue;
    }

    if (transactionTime == null && latestTime != null) {
      continue;
    }

    if (transactionTime != null &&
        (latestTime == null || !transactionTime.isBefore(latestTime))) {
      latestBalance = parsedBalance;
      latestTime = transactionTime;
      continue;
    }

    if (transactionTime == null && latestTime == null) {
      latestBalance = parsedBalance;
    }
  }

  return latestBalance;
}

/// Endekise / credit-line usage is labeled on the transaction so a leftover
/// outstanding figure is never treated as wallet cash.
bool transactionHasCreditLineWalletBalance(Transaction transaction) {
  final creditor = transaction.creditor?.trim().toLowerCase() ?? '';
  final receiver = transaction.receiver?.trim().toLowerCase() ?? '';
  return creditor.contains('endekise') || receiver.contains('endekise');
}

double? _parseBalance(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.trim().replaceAll(',', '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

DateTime? _parseTransactionTime(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toLocal();
  } catch (_) {
    return null;
  }
}
