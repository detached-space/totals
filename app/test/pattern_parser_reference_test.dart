import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/sms_pattern.dart';
import 'package:totals/utils/pattern_parser.dart';

void main() {
  test('recovers a Telebirr transaction number from its receipt link',
      () async {
    final bank = Bank(
      id: 6,
      name: 'Telebirr',
      shortName: 'Telebirr',
      codes: const ['127'],
      image: '',
      simBased: true,
    );
    final pattern = SmsPattern(
      bankId: 6,
      senderId: 'telebirr',
      regex: r'request\s+to\s+withdraw\s+ETB\s?(?<amount>[\d,.]+).*?'
          r'from\s+your\s+telebirr\s+account\s+(?<account>\d+).*?'
          r'(?:The|the)\s+service\s+fee\s*\(including\s+15%\s+VAT\)\s+'
          r'is\s+ETB\s*(?<totalFees>[\d,.]+).*?'
          r'(?:transaction\s+number\s+is\s+(?<reference>[A-Z0-9]+).*?)?'
          r'(?:current\s+)?(?:Account\s+)?balance\s+is\s+ETB\s?'
          r'(?<balance>[\d,.]+)',
      type: 'DEBIT',
      refRequired: false,
      hasAccount: true,
    );
    const body = '''Dear EYOSIAS
The request to withdraw ETB 1,000.00 from your telebirr account 251957063583 via secret code 671826 on 2025-06-28 15:15:39 using Bank of Abyssinia ATM with transaction number CFS07I3GTC is successfully completed. The service fee (including 15% VAT) is ETB 5.75. Your current Account balance is ETB 90.82. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/CFS07I3GTC
Thank you for using telebirr''';

    final details = await PatternParser.extractTransactionDetails(
      body,
      '127',
      DateTime(2025, 6, 28, 15, 15, 45),
      [pattern],
      banks: [bank],
    );

    expect(details, isNotNull);
    expect(details!['reference'], 'CFS07I3GTC');
    expect(details['accountNumber'], '251957063583');
    expect(details['type'], 'DEBIT');
  });

  test('extracts the Dashen destination account despite mask separators',
      () async {
    final bank = Bank(
      id: 4,
      name: 'Dashen Bank',
      shortName: 'Dashen',
      codes: const ['DashenBank'],
      image: '',
      maskPattern: 3,
      uniformMasking: true,
    );
    final pattern = SmsPattern(
      bankId: 4,
      senderId: 'Dashen',
      regex: r'received\s+ETB\s+(?<amount>[\d,.]+).*?'
          r'Ref\s+No:?\s*(?<reference>\d+).*?'
          r'on\s+(?<date>\d{2}\/\d{2}\/\d{4})\s+(?:at\s+)?'
          r'\d{2}:\d{2}:\d{2}(?:\s*[AP]M)?.*?'
          r"account\s+'(?<account>[\dXx*\\/\s-]+)'.*?"
          r'balance\s+is\s+ETB\s+(?<balance>[\d,.]+)',
      type: 'CREDIT',
      refRequired: false,
      hasAccount: true,
    );
    const body = '''Dear Customer, You have received ETB 51,450.00 from
telebirr account number 251943685872 Ref No:2603092000308528 on 09/03/2026
at 08:23:58 AM to your bank account '5107**\\****011'. Your account balance
is ETB 51,509.06.''';

    final details = await PatternParser.extractTransactionDetails(
      body,
      'DashenBank',
      DateTime(2026, 3, 9, 8, 23, 58),
      <SmsPattern>[pattern],
      banks: <Bank>[bank],
    );

    expect(details, isNotNull);
    expect(details!['reference'], '2603092000308528');
    expect(details['accountNumber'], '011');
    expect(details['type'], 'CREDIT');
  });
}
