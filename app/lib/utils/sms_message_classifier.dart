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
}
