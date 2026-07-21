import 'package:totals/models/account.dart';
import 'package:totals/models/transaction.dart';

String accountBalanceResolverKey(Account account) {
  return '${account.bank}:${account.accountNumber}';
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

  if (bankAccountCount == 1) {
    final latestBalanceAfter = latestParsedBalanceAfter(accountTransactions);
    if (latestBalanceAfter != null) {
      return latestBalanceAfter;
    }
  }

  return account.balance;
}

double? latestParsedBalanceAfter(Iterable<Transaction> transactions) {
  final sorted = List<Transaction>.from(transactions)
    ..sort((a, b) {
      final timeA = _parseTransactionTime(a.time);
      final timeB = _parseTransactionTime(b.time);
      if (timeA == null && timeB == null) return 0;
      if (timeA == null) return -1;
      if (timeB == null) return 1;
      return timeA.compareTo(timeB);
    });

  double? runningBalance;

  for (final transaction in sorted) {
    final parsedBalance = _parseBalance(transaction.currentBalance);
    if (parsedBalance != null) {
      runningBalance = parsedBalance;
    } else if (runningBalance != null) {
      final amount = transaction.amount;
      final totalFee = transaction.totalFee ?? 0.0;
      final total = amount + totalFee;
      if (transaction.type == 'CREDIT') {
        runningBalance = runningBalance! + total;
      } else {
        runningBalance = runningBalance! - total;
      }
    }
  }

  return runningBalance;
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
