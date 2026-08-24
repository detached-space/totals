import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/sms_pattern.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/account_balance_resolver.dart';
import 'package:totals/utils/pattern_parser.dart';

const _endekiseBody = '''Dear Yeabsira
Your transaction is successfully completed using Endekise.
You have used ETB 16.16 credit amount on this transaction.
The service fee is ETB 0.40 and the daily fee will be 22.95 depending on your credit limit.
Your outstanding amount is ETB 3168.62 with due date of 2026-09-22 00:00:00.
Your Contract number is 27825413.
Thank you for using telebirr Ethio telecom in partnership with Dashen Bank''';

void main() {
  final telebirr = Bank(
    id: 6,
    name: 'Telebirr',
    shortName: 'Telebirr',
    codes: const ['127'],
    image: '',
    simBased: true,
  );

  test('does not store Endekise outstanding as the Telebirr wallet balance',
      () async {
    final details = await PatternParser.extractTransactionDetails(
      _endekiseBody,
      '127',
      DateTime(2026, 8, 24, 14, 0),
      _bundledTelebirrPatterns(),
      banks: [telebirr],
    );

    expect(details, isNotNull);
    expect(details!['type'], 'DEBIT');
    expect(details['amount'], 16.16);
    expect(details['currentBalance'], isNull);
    expect(details['creditor'], 'Endekise');
  });

  test('forces Endekise notices to debit even if a credit pattern matches',
      () async {
    final creditPattern = SmsPattern(
      bankId: 6,
      senderId: 'telebirr',
      regex: r'ETB\s*(?<amount>-?[\d,.]+)\s+credit\s+amount'
          r'[\s\S]*?outstanding\s+amount\s+is\s+ETB\s*(?<balance>-?[\d,.]+)',
      type: 'CREDIT',
      description: 'Legacy Endekise credit',
      refRequired: false,
      hasAccount: false,
    );

    final details = await PatternParser.extractTransactionDetails(
      _endekiseBody,
      '127',
      DateTime(2026, 8, 24, 14, 0),
      [creditPattern],
      banks: [telebirr],
    );

    expect(details, isNotNull);
    expect(details!['type'], 'DEBIT');
    expect(details['amount'], 16.16);
    expect(details['currentBalance'], isNull);
  });

  test('keeps a normal Telebirr incoming transfer as wallet credit', () async {
    const body = '''Dear Customer
You have received ETB 200.00 from Abebe on 24/08/2026 14:00:00.
Your transaction number is ABC12XYZ. Your current balance is ETB 50.00.
Thank you for using telebirr''';

    final details = await PatternParser.extractTransactionDetails(
      body,
      '127',
      DateTime(2026, 8, 24, 14, 0),
      _bundledTelebirrPatterns(),
      banks: [telebirr],
    );

    expect(details, isNotNull);
    expect(details!['type'], 'CREDIT');
    expect(details['amount'], 200.00);
    expect(details['currentBalance'], '50.00');
  });

  test('ignores leftover Endekise outstanding when resolving wallet balance',
      () {
    final wallet = Transaction(
      amount: 16.16,
      reference: 'DHO84EG3D8',
      bankId: 6,
      type: 'DEBIT',
      time: '2026-08-24T13:59:00',
      currentBalance: '0.00',
    );
    final endekise = Transaction(
      amount: 16.16,
      reference: '6_2026-08-24T14:00:00.000',
      bankId: 6,
      type: 'DEBIT',
      time: '2026-08-24T14:00:00',
      currentBalance: '3168.62',
      creditor: 'Endekise',
    );

    expect(
      latestParsedBalanceAfter([wallet, endekise]),
      0.00,
    );
  });
}

List<SmsPattern> _bundledTelebirrPatterns() {
  final json = jsonDecode(
    File('assets/sms_patterns.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final patterns = json['patterns'] as List<dynamic>;
  return patterns
      .map((item) => SmsPattern.fromJson(item as Map<String, dynamic>))
      .where((pattern) => pattern.bankId == 6)
      .toList(growable: false);
}
