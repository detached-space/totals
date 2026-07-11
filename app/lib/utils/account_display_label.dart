import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/transaction.dart';

/// Friendly label for the account a transaction belongs to: the account's
/// name ("Aba - Me") instead of just the bank ("Aba"), whenever the account
/// can be resolved — unique account for that bank in the active profile, or a
/// unique account-number-suffix match. Falls back to [bankLabel] for cash,
/// unresolvable or ambiguous cases, so existing behavior is never worse.
String accountLabelForTransaction(
  Transaction transaction,
  List<Account> accounts, {
  required String bankLabel,
}) {
  final bankId = transaction.bankId;
  if (bankId == null || bankId == CashConstants.bankId) return bankLabel;

  final ofBank = accounts.where((a) => a.bank == bankId).toList();
  if (ofBank.isEmpty) return bankLabel;

  Account? match;
  if (ofBank.length == 1) {
    match = ofBank.single;
  } else {
    final txDigits =
        (transaction.accountNumber ?? '').replaceAll(RegExp(r'\D'), '');
    if (txDigits.isNotEmpty) {
      final k = txDigits.length >= 4 ? 4 : txDigits.length;
      final suffix = txDigits.substring(txDigits.length - k);
      final hits = ofBank.where((a) {
        final n = a.accountNumber.replaceAll(RegExp(r'\D'), '');
        return n.isNotEmpty && n.endsWith(suffix);
      }).toList();
      if (hits.length == 1) match = hits.first;
    }
  }

  final name = match?.accountHolderName.trim() ?? '';
  return name.isNotEmpty ? name : bankLabel;
}
