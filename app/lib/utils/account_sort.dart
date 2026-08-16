String normalizeAccountSortText(String? value) =>
    value?.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase() ?? '';

int compareDisplayText(String? left, String? right) {
  final normalizedLeft = normalizeAccountSortText(left);
  final normalizedRight = normalizeAccountSortText(right);
  return normalizedLeft.compareTo(normalizedRight);
}

int _compareOptionalDisplayText(String? left, String? right) {
  final normalizedLeft = normalizeAccountSortText(left);
  final normalizedRight = normalizeAccountSortText(right);
  final leftIsEmpty = normalizedLeft.isEmpty;
  final rightIsEmpty = normalizedRight.isEmpty;
  if (leftIsEmpty != rightIsEmpty) return leftIsEmpty ? 1 : -1;
  return compareDisplayText(left, right);
}

String _normalizedAccountNumber(String? value) {
  return normalizeAccountSortText(value).replaceAll(
    RegExp(r'[^a-z0-9]'),
    '',
  );
}

/// Shared display ordering for every bank-account list:
/// bank name, then account-holder name, then account number.
int compareAccountDisplayFields({
  required int leftBankId,
  required int rightBankId,
  required String? leftHolderName,
  required String? rightHolderName,
  required String? leftAccountNumber,
  required String? rightAccountNumber,
  required String Function(int bankId) bankNameForId,
}) {
  final bankComparison = compareDisplayText(
    bankNameForId(leftBankId),
    bankNameForId(rightBankId),
  );
  if (bankComparison != 0) return bankComparison;

  // Keep accounts from distinct banks grouped even when two configured banks
  // happen to have the same display label.
  final bankIdComparison = leftBankId.compareTo(rightBankId);
  if (bankIdComparison != 0) return bankIdComparison;

  final holderComparison = _compareOptionalDisplayText(
    leftHolderName,
    rightHolderName,
  );
  if (holderComparison != 0) return holderComparison;

  final leftNumber = _normalizedAccountNumber(leftAccountNumber);
  final rightNumber = _normalizedAccountNumber(rightAccountNumber);
  final numberComparison = leftNumber.compareTo(rightNumber);
  if (numberComparison != 0) return numberComparison;

  return compareDisplayText(leftAccountNumber, rightAccountNumber);
}
