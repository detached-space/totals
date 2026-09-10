import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/sms_pattern.dart';
import 'package:totals/utils/pattern_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> rawPatterns;

  setUpAll(() async {
    final body = await rootBundle.loadString('assets/sms_patterns.json');
    final decoded = jsonDecode(body) as List<dynamic>;
    rawPatterns = decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  });

  test('Endekise debt is not returned as the current account balance',
      () async {
    final rawPattern = _patternByDescription(
      rawPatterns,
      'Fallback Telebirr endekise',
    );
    final pattern = SmsPattern.fromJson(rawPattern);
    const body = '''Your transaction is successfully completed using Endekise.
You have used ETB 16.16 credit amount on this transaction.
The service fee is ETB 0.40 and the daily fee will be 22.95 depending on your credit limit.
Your outstanding amount is ETB 3168.62 with due date of 2026-09-22 00:00:00.''';

    final details = await PatternParser.extractTransactionDetails(
      body,
      'telebirr',
      DateTime(2026, 8, 25),
      <SmsPattern>[pattern],
      banks: <Bank>[
        Bank(
          id: 6,
          name: 'Telebirr',
          shortName: 'Telebirr',
          codes: const <String>['telebirr'],
          image: '',
          simBased: true,
        ),
      ],
    );

    expect(details, isNotNull);
    expect(details!['type'], 'DEBIT');
    expect(details['amount'], 16.16);
    expect(details.containsKey('currentBalance'), isFalse);

    final match = RegExp(
      pattern.regex,
      caseSensitive: false,
      multiLine: true,
      dotAll: true,
    ).firstMatch(body);
    expect(match, isNotNull);
    expect(match!.namedGroup('outstandingDebt'), '3168.62');
    expect(match.groupNames, isNot(contains('balance')));
  });

  test('credit and overdraft patterns reserve balance for liquid funds', () {
    const debtPatternNames = <String>[
      'Fallback Telebirr endekise',
      'Fallback Telebirr paid outstanding credit',
      'Fallback Telebirr credit amount paid',
      'Fallback MPESA overdraft used',
    ];

    for (final name in debtPatternNames) {
      final pattern = _patternByDescription(rawPatterns, name);
      expect(pattern['type'], 'DEBIT', reason: name);
      expect(pattern['regex'], contains('(?<outstandingDebt>'), reason: name);
      expect(pattern['regex'], isNot(contains('(?<balance>')), reason: name);
      expect(
        (pattern['mapping'] as Map).containsKey('balance'),
        isFalse,
        reason: name,
      );
    }

    final limitPattern = _patternByDescription(
      rawPatterns,
      'Fallback MPESA overdraft loan paid',
    );
    expect(limitPattern['type'], 'DEBIT');
    expect(limitPattern['regex'], contains('(?<availableCreditLimit>'));
    expect(limitPattern['regex'], isNot(contains('(?<balance>')));
    expect(
      (limitPattern['mapping'] as Map).containsKey('balance'),
      isFalse,
    );

    expect(
      rawPatterns.where(
        (pattern) =>
            pattern['description'] ==
            'Fallback Telebirr overdue credit balance',
      ),
      isEmpty,
    );
  });
}

Map<String, dynamic> _patternByDescription(
  List<Map<String, dynamic>> patterns,
  String description,
) {
  return patterns.singleWhere(
    (pattern) => pattern['description'] == description,
  );
}
