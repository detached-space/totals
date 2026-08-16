class CashConstants {
  static const int bankId = 100;
  static const String displayName = 'Cash Wallet';
  static const String bankName = displayName;
  static const String bankShortName = displayName;
  static const String bankImage = 'assets/images/cash.png';
  static const List<String> bankColors = ['#0f766e', '#14b8a6'];
  static const String defaultAccountNumber = 'CASH';
  static const String defaultAccountHolderName = displayName;
  static const String atmReferencePrefix = 'cash_atm_';
  static const String manualReferencePrefix = 'cash_manual_';

  static String buildAtmReference(String bankReference) {
    return '$atmReferencePrefix$bankReference';
  }

  static String buildManualReference(int micros) {
    return '$manualReferencePrefix$micros';
  }
}
