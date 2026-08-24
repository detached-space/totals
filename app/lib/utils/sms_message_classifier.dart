/// Classifies SMS messages that look financial but are not ledger entries.
class SmsMessageClassifier {
  SmsMessageClassifier._();

  static final RegExp _telebirrAtmAuthorization = RegExp(
    r'\bATM\s+withdraw(?:al)?\s+secret\s+code\s+is\s+(\d{4,8})\b',
    caseSensitive: false,
  );

  static final List<RegExp> _telebirrAirtimeReceiptPatterns = <RegExp>[
    RegExp(
      r'you\s+have\s+received\s+ETB\s+[\d,.]+\s+airtime\s+from\s+\S+[\s\S]*?transaction\s+number\s+is\s+([A-Z0-9@-]+)',
      caseSensitive: false,
    ),
    RegExp(
      r'[\d,.]+\s+ብር[\s\S]*?ተሞልቶሎታል[\s\S]*?ቁጥርዎ\s+([A-Z0-9@-]+)',
      caseSensitive: false,
    ),
  ];

  /// Telebirr sends this authorization notice before the ATM withdrawal is
  /// completed. It contains an amount and code, but no money has moved yet.
  static bool isTelebirrAtmAuthorization(String messageBody) {
    return _telebirrAtmAuthorization.hasMatch(messageBody);
  }

  static String? telebirrAtmAuthorizationCode(String messageBody) {
    return _telebirrAtmAuthorization.firstMatch(messageBody)?.group(1);
  }

  /// Telebirr also sends the receiving phone an airtime acknowledgement.
  /// Airtime was delivered, but the recipient's E-Money balance was not
  /// credited, so treating this acknowledgement as income double-counts the
  /// sender-side recharge (and invents income for third-party airtime gifts).
  static bool isTelebirrAirtimeReceipt(String messageBody) {
    return telebirrAirtimeReceiptReference(messageBody) != null;
  }

  /// Bank reference carried by a non-ledger airtime acknowledgement.
  static String? telebirrAirtimeReceiptReference(String messageBody) {
    for (final pattern in _telebirrAirtimeReceiptPatterns) {
      final value = pattern.firstMatch(messageBody)?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static final RegExp _telebirrEndekise = RegExp(
    r'\bendekise\b',
    caseSensitive: false,
  );

  static final RegExp _usedCreditAmount = RegExp(
    r'used\s+ETB\s+[\d,.]+\s+credit\s+amount',
    caseSensitive: false,
  );

  static final RegExp _creditLineOutstanding = RegExp(
    r'unpaid\s+credit\s+amount|'
    r'outstanding\s+credit\s+(?:amount|balance)|'
    r'paid\s+a\s+credit\s+amount\s+of',
    caseSensitive: false,
  );

  static final RegExp _overdraftOutstanding = RegExp(
    r'overdraft[\s\S]{0,120}outstanding\s+amount',
    caseSensitive: false,
  );

  /// Telebirr Endekise notices describe a loan draw, not E-Money.
  ///
  /// The actual merchant/wallet SMS already records the spend and the real
  /// wallet balance. Parsing this companion SMS treats outstanding debt as
  /// cash and can count "credit amount" as income.
  static bool isTelebirrCreditLineNotice(String messageBody) {
    if (_telebirrEndekise.hasMatch(messageBody)) return true;
    return _usedCreditAmount.hasMatch(messageBody);
  }

  /// True when an SMS reports loan/overdraft outstanding rather than wallet
  /// cash. That figure must not overwrite `Account.balance`.
  static bool reportsLiabilityOutstanding(String messageBody) {
    if (isTelebirrCreditLineNotice(messageBody)) return true;
    if (_creditLineOutstanding.hasMatch(messageBody)) return true;
    return _overdraftOutstanding.hasMatch(messageBody);
  }

  static bool isTelebirrNonLedgerNotice(String messageBody) {
    return isTelebirrAtmAuthorization(messageBody) ||
        isTelebirrAirtimeReceipt(messageBody) ||
        isTelebirrCreditLineNotice(messageBody);
  }
}
