import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';

/// Canonicalizes an account identifier for matching.
///
/// SIM-backed Ethiopian wallets commonly expose the same user-entered number
/// as `09xxxxxxxx`, `9xxxxxxxx`, `2519xxxxxxxx`, or `+2519xxxxxxxx`.
/// Those representations must resolve to one account identity.
String? canonicalAccountNumber(Bank bank, String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;

  if (bank.simBased == true) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00251') && digits.length == 14) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('251') && digits.length == 12) {
      return '0${digits.substring(3)}';
    }
    if (digits.length == 9 &&
        (digits.startsWith('9') || digits.startsWith('7'))) {
      return '0$digits';
    }
    return digits.isEmpty ? null : digits;
  }

  final compact = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return compact.isEmpty ? null : compact;
}

String? canonicalAccountHolderName(String? raw) {
  final value = raw?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  return value.replaceAll(RegExp(r'\s+'), ' ');
}

bool accountNumbersMatch(Bank bank, String? left, String? right) {
  final leftValue = canonicalAccountNumber(bank, left);
  final rightValue = canonicalAccountNumber(bank, right);
  if (leftValue == null || rightValue == null) return false;

  if (bank.simBased == true) return leftValue == rightValue;

  final maskLength = bank.uniformMasking == true ? bank.maskPattern : null;
  if (maskLength != null && maskLength > 0) {
    if (leftValue.length < maskLength || rightValue.length < maskLength) {
      return false;
    }
    return leftValue.substring(leftValue.length - maskLength) ==
        rightValue.substring(rightValue.length - maskLength);
  }

  return leftValue == rightValue;
}

/// Compares two durable, user-entered account identities.
///
/// Unlike [accountNumbersMatch], this never falls back to a bank's displayed
/// suffix. It is used for persisted ownership and account-to-account checks,
/// where the complete registered number is available on both sides.
bool registeredAccountNumbersMatch(Bank bank, String? left, String? right) {
  final leftValue = canonicalAccountNumber(bank, left);
  final rightValue = canonicalAccountNumber(bank, right);
  return leftValue != null && rightValue != null && leftValue == rightValue;
}

bool accountHolderNamesMatch(String? left, String? right) {
  final leftValue = canonicalAccountHolderName(left);
  final rightValue = canonicalAccountHolderName(right);
  return leftValue != null && leftValue == rightValue;
}

/// Finds the registered account that owns parsed SMS data.
///
/// A unique greeting name is strongest because parsed numbers in a transfer
/// can describe the counterparty. A learned device-local SIM subscription is
/// next, followed by a uniquely matching parsed number. This precedence is
/// deliberate: wallet transfer parsers can extract the counterparty number,
/// while the greeting and delivering SIM describe the user's wallet.
Account? resolveAccountOwnership({
  required Bank bank,
  required Iterable<Account> accounts,
  String? parsedAccountNumber,
  String? parsedAccountHolderName,
  int? sourceSubscriptionId,
}) {
  final bankAccounts =
      accounts.where((account) => account.bank == bank.id).toList();
  if (bankAccounts.isEmpty) return null;

  final subscriptionMatches = sourceSubscriptionId != null &&
          sourceSubscriptionId >= 0
      ? bankAccounts
          .where((account) => account.smsSubscriptionId == sourceSubscriptionId)
          .toList()
      : const <Account>[];
  final numberMatches = parsedAccountNumber?.trim().isNotEmpty == true
      ? bankAccounts
          .where((account) => accountNumbersMatch(
                bank,
                parsedAccountNumber,
                account.accountNumber,
              ))
          .toList()
      : const <Account>[];
  final nameMatches = parsedAccountHolderName?.trim().isNotEmpty == true
      ? bankAccounts
          .where((account) => accountHolderNamesMatch(
                parsedAccountHolderName,
                account.accountHolderName,
              ))
          .toList()
      : const <Account>[];

  // A greeting match is explicit owner context. A different parsed number is
  // commonly the transfer counterparty, so it must not override the greeting.
  if (nameMatches.length == 1) {
    return nameMatches.single;
  }

  // The delivering SIM identifies the user's wallet. A parsed number can
  // still be the receiver/sender mentioned inside the transaction body.
  if (subscriptionMatches.length == 1) {
    return subscriptionMatches.single;
  }

  if (numberMatches.length == 1) return numberMatches.single;

  return null;
}

Account? resolveSmsOwnership({
  required Bank bank,
  required Iterable<Account> accounts,
  required String messageBody,
  String? parsedAccountNumber,
  int? sourceSubscriptionId,
}) {
  final bankAccounts =
      accounts.where((account) => account.bank == bank.id).toList();
  final greeting = _openingAccountGreeting(messageBody);
  final greetingOwner = _accountHolderNameFromGreeting(
    greeting,
    bankAccounts,
  );

  // A concrete name in the opening greeting describes the wallet owner. If
  // that person has not been added, lower-priority SIM/number evidence must
  // not make the SMS look like it belongs to a registered counterparty.
  if (greeting != null &&
      !_isGenericAccountGreeting(greeting) &&
      greetingOwner == null) {
    return null;
  }
  if (greetingOwner != null) {
    return resolveAccountOwnership(
      bank: bank,
      accounts: bankAccounts,
      parsedAccountHolderName: greetingOwner,
    );
  }

  // Some bank messages mention both a counterparty account and the user's
  // destination/source account. Old parsers could pick the first number in
  // the body (for example, the Telebirr sender in a Dashen credit), so prefer
  // an account number explicitly anchored to "your account". Treat ambiguous
  // or unmatched explicit context as a veto instead of falling back to the
  // counterparty number.
  final contextualNumbers = _ownerAccountNumbersFromMessage(messageBody);
  if (contextualNumbers.isNotEmpty) {
    final contextualMatches = bankAccounts
        .where(
          (account) => contextualNumbers.any(
            (number) => accountNumbersMatch(
              bank,
              number,
              account.accountNumber,
            ),
          ),
        )
        .toList(growable: false);
    if (contextualMatches.length == 1) {
      return contextualMatches.single;
    }
    return null;
  }

  return resolveAccountOwnership(
    bank: bank,
    accounts: bankAccounts,
    // Wallet parsers frequently expose the transfer counterparty as the raw
    // account number. Owner name/SIM evidence is required for SIM wallets.
    parsedAccountNumber: bank.simBased == true ? null : parsedAccountNumber,
    parsedAccountHolderName: greetingOwner,
    sourceSubscriptionId: sourceSubscriptionId,
  );
}

List<String> _ownerAccountNumbersFromMessage(String messageBody) {
  final matches = RegExp(
    r'''\byour\s+(?:(?:e-?money|bank|telebirr)\s+)?account(?:\s+(?:number|no\.?))?\s*(?:is|:)?\s*['"\u2018\u2019]?([+0-9][+0-9Xx*\\/\-\s]{2,39})''',
    caseSensitive: false,
    multiLine: true,
  ).allMatches(messageBody);
  final values = <String>[];
  for (final match in matches) {
    final value = match.group(1)?.trim();
    if (value == null || !RegExp(r'\d').hasMatch(value)) continue;
    if (!values.contains(value)) values.add(value);
  }
  return values;
}

/// Returns a user-entered holder name only when it appears in a greeting at
/// the beginning of the SMS. Arbitrary body matches are deliberately rejected
/// because counterparties may share a name with another registered owner.
String? accountHolderNameFromGreeting(
  String messageBody,
  Iterable<Account> accounts,
) {
  return _accountHolderNameFromGreeting(
    _openingAccountGreeting(messageBody),
    accounts,
  );
}

/// Whether the SMS explicitly greets a person who is not uniquely represented
/// by one of the supplied accounts.
///
/// This is useful when repairing old rows: `Dear KIDIST ... to EYOSIAS` proves
/// that an Eyosias owner assignment is wrong even if Kidist is not currently a
/// registered account.
bool hasUnmatchedSpecificAccountGreeting(
  String messageBody,
  Iterable<Account> accounts,
) {
  final greeting = _openingAccountGreeting(messageBody);
  if (greeting == null || _isGenericAccountGreeting(greeting)) return false;
  return _accountHolderNameFromGreeting(greeting, accounts) == null;
}

String? _openingAccountGreeting(String messageBody) {
  final greetingMatch = RegExp(
    r'^\s*(?:dear|hi|hello)\s+([^,;:\r\n]{1,100})',
    caseSensitive: false,
  ).firstMatch(messageBody);
  return canonicalAccountHolderName(greetingMatch?.group(1));
}

bool _isGenericAccountGreeting(String greeting) {
  return RegExp(
    r'^(?:(?:valued|dear)\s+)?(?:customer|user|client|member|sir|madam)\b',
    caseSensitive: false,
  ).hasMatch(greeting);
}

String? _accountHolderNameFromGreeting(
  String? greeting,
  Iterable<Account> accounts,
) {
  if (greeting == null || _isGenericAccountGreeting(greeting)) return null;

  final fullMatches = <String>[];
  final firstNameMatches = <String>[];
  for (final account in accounts) {
    final name = canonicalAccountHolderName(account.accountHolderName);
    if (name == null) continue;
    final nameParts = name.split(' ').where((part) => part.isNotEmpty).toList();
    final firstName = nameParts.isEmpty ? name : nameParts.first;
    final fullNameMatch = RegExp(
      '(?:^|\\s)${RegExp.escape(name)}(?:\\s|\$)',
      caseSensitive: false,
    ).hasMatch(greeting);
    final firstNameMatch = RegExp(
      '(?:^|\\s)${RegExp.escape(firstName)}(?:\\s|\$)',
      caseSensitive: false,
    ).hasMatch(greeting);
    if (fullNameMatch && !fullMatches.contains(account.accountHolderName)) {
      fullMatches.add(account.accountHolderName);
    }
    if (firstNameMatch &&
        !firstNameMatches.contains(account.accountHolderName)) {
      firstNameMatches.add(account.accountHolderName);
    }
  }
  if (fullMatches.length == 1) return fullMatches.single;
  if (fullMatches.length > 1) return null;
  return firstNameMatches.length == 1 ? firstNameMatches.single : null;
}

/// Shared predicate for summaries, lists, APIs, reparse, and deletion.
Account? resolveTransactionOwnership({
  required Transaction transaction,
  required Bank bank,
  required Iterable<Account> accounts,
}) {
  if (transaction.bankId != bank.id) return null;
  final bankAccounts =
      accounts.where((account) => account.bank == bank.id).toList();
  if (bankAccounts.isEmpty) return null;

  final ownedNumber = transaction.ownerAccountNumber?.trim();
  if (ownedNumber != null && ownedNumber.isNotEmpty) {
    final matches = bankAccounts
        .where((account) => registeredAccountNumbersMatch(
              bank,
              ownedNumber,
              account.accountNumber,
            ))
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  return resolveAccountOwnership(
    bank: bank,
    accounts: bankAccounts,
    // For SIM-backed wallets this field may identify the transfer recipient,
    // not the user's wallet. Only persisted owner/SIM evidence is safe here.
    parsedAccountNumber:
        bank.simBased == true ? null : transaction.accountNumber,
    sourceSubscriptionId: transaction.sourceSubscriptionId,
  );
}

bool transactionBelongsToAccount({
  required Transaction transaction,
  required Account account,
  required Bank bank,
  required Iterable<Account> accounts,
}) {
  final owner = resolveTransactionOwnership(
    transaction: transaction,
    bank: bank,
    accounts: accounts,
  );
  return owner != null &&
      registeredAccountNumbersMatch(
        bank,
        owner.accountNumber,
        account.accountNumber,
      );
}
