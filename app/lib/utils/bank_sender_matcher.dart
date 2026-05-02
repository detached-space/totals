import 'package:totals/models/bank.dart';

String normalizeBankSenderToken(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

Bank? findBestBankForSenderAddress(String? address, Iterable<Bank> banks) {
  final normalizedAddress =
      address == null ? '' : normalizeBankSenderToken(address);
  if (normalizedAddress.isEmpty) return null;

  _BankSenderMatch? bestMatch;
  for (final bank in banks) {
    for (final code in bank.codes) {
      final normalizedCode = normalizeBankSenderToken(code);
      if (normalizedCode.isEmpty) continue;

      final matchIndex = normalizedAddress.indexOf(normalizedCode);
      if (matchIndex < 0) continue;

      final match = _BankSenderMatch(
        bank: bank,
        codeLength: normalizedCode.length,
        isExact: normalizedAddress == normalizedCode,
        startsAtBeginning: matchIndex == 0,
        unmatchedLength: normalizedAddress.length - normalizedCode.length,
      );
      if (match.isBetterThan(bestMatch)) bestMatch = match;
    }
  }

  return bestMatch?.bank;
}

bool senderAddressMatchesBank(
  Bank bank,
  String? address, {
  Iterable<Bank>? allBanks,
}) {
  if (allBanks != null) {
    final bestMatch = findBestBankForSenderAddress(address, allBanks);
    if (bestMatch != null) return bestMatch.id == bank.id;
  }

  final normalizedAddress =
      address == null ? '' : normalizeBankSenderToken(address);
  if (normalizedAddress.isEmpty) return false;

  for (final code in bank.codes) {
    final normalizedCode = normalizeBankSenderToken(code);
    if (normalizedCode.isEmpty) continue;
    if (normalizedAddress.contains(normalizedCode)) return true;
  }
  return false;
}

class _BankSenderMatch {
  final Bank bank;
  final int codeLength;
  final bool isExact;
  final bool startsAtBeginning;
  final int unmatchedLength;

  const _BankSenderMatch({
    required this.bank,
    required this.codeLength,
    required this.isExact,
    required this.startsAtBeginning,
    required this.unmatchedLength,
  });

  bool isBetterThan(_BankSenderMatch? other) {
    if (other == null) return true;
    if (isExact != other.isExact) return isExact;
    if (codeLength != other.codeLength) return codeLength > other.codeLength;
    if (startsAtBeginning != other.startsAtBeginning) {
      return startsAtBeginning;
    }
    if (unmatchedLength != other.unmatchedLength) {
      return unmatchedLength < other.unmatchedLength;
    }
    return false;
  }
}
