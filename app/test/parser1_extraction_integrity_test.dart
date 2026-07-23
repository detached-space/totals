import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:totals/models/sms_pattern.dart';
import 'package:totals/utils/pattern_parser.dart';

int _countCaptureGroups(String regex) {
  int count = 0;
  int i = 0;
  bool inClass = false;
  while (i < regex.length) {
    if (regex[i] == '\\') {
      i += 2;
      continue;
    }
    if (regex[i] == '[') {
      inClass = true;
      i++;
      continue;
    }
    if (regex[i] == ']') {
      inClass = false;
      i++;
      continue;
    }
    if (!inClass && regex[i] == '(') {
      if (i + 2 < regex.length && regex[i + 1] == '?' && regex[i + 2] == '<') {
        count++;
        final close = regex.indexOf('>', i + 3);
        i = close + 1;
        continue;
      }
      if (i + 1 < regex.length && regex[i + 1] == '?') {
        i += 3;
        continue;
      }
      count++;
    }
    i++;
  }
  return count;
}

List<SmsPattern> _loadPatterns() {
  final json = jsonDecode(File('assets/sms_patterns.json').readAsStringSync());
  return (json['patterns'] as List)
      .map((e) => SmsPattern.fromJson(e as Map<String, dynamic>))
      .toList();
}

List<String> _loadSampleBodies() {
  String fixJson(String raw) =>
      raw.replaceAll(RegExp(r',\s*}'), '}').replaceAll(RegExp(r',\s*\]'), ']');

  final withRegex = jsonDecode(fixJson(
          File('test/fixtures/unmatched-with-regex.json').readAsStringSync()))
      as List;
  final noRegex = jsonDecode(fixJson(
          File('test/fixtures/unmatched-no-regex.json').readAsStringSync()))
      as List;
  return [
    ...withRegex.map((e) => e['example sms'] as String),
    ...noRegex.map((e) => e['example sms'] as String),
  ];
}

void main() {
  setUpAll(() {
    // PatternParser account masking may touch sqflite; keep extraction quiet.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('fieldMapping / regex-group consistency', () {
    test('mapping index never exceeds the actual capture-group count', () {
      final patterns = _loadPatterns();
      final violations = <String>[];

      for (final pattern in patterns) {
        if (pattern.fieldMapping == null) continue;
        final groupCount = _countCaptureGroups(pattern.regex);
        for (final entry in pattern.fieldMapping!.entries) {
          final index = int.tryParse(entry.value);
          if (index == null) {
            violations.add('${pattern.description}: mapping value for '
                '"${entry.key}" is not a valid integer: "${entry.value}"');
            continue;
          }
          if (index < 0 || index > groupCount) {
            violations.add('${pattern.description}: mapping key '
                '"${entry.key}" -> group $index, but the regex only has '
                '$groupCount capture groups');
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        'extraction snapshot — fixture bodies that match still extract amount',
        () async {
      final patterns = _loadPatterns();
      final bodies = _loadSampleBodies();
      final messageDate = DateTime(2026, 7, 12);
      var matched = 0;

      for (final body in bodies) {
        final result = await PatternParser.extractTransactionDetails(
          body,
          '',
          messageDate,
          patterns,
        );
        if (result == null) continue;
        matched++;
        expect(result['amount'], isNotNull,
            reason: 'matched body must yield an amount:\n$body');
      }

      expect(matched, greaterThan(0),
          reason: 'fixture corpus should produce at least one extraction');
    });
  });

  group('fee computation edge cases', () {
    test(
        'combined totalFee capture takes precedence over serviceCharge+vat '
        'derivation, never sums with it', () async {
      final pattern = SmsPattern(
        bankId: 99,
        senderId: 'SYN',
        regex: r'Debit (?<amount>[\d.]+) SC (?<serviceCharge>[\d.]+) '
            r'VAT (?<vat>[\d.]+) Fees (?<totalFees>[\d.]+)',
        type: 'DEBIT',
        description: 'synthetic combined totalFees',
        fieldMapping: const {
          'amount': '1',
          'serviceCharge': '2',
          'vat': '3',
          'totalFees': '4',
        },
      );
      final result = await PatternParser.extractTransactionDetails(
        'Debit 100.00 SC 5.00 VAT 2.00 Fees 9.00',
        '',
        DateTime(2026, 7, 12),
        [pattern],
      );
      expect(result, isNotNull);
      expect(result!['totalFee'], 9.0,
          reason: 'captured totalFees must win over serviceCharge+vat (7.0)');
    });

    test('missing vat with present serviceCharge does not silently zero '
        'or invent totalFee', () async {
      final pattern = SmsPattern(
        bankId: 99,
        senderId: 'SYN',
        regex: r'Debit (?<amount>[\d.]+) SC (?<serviceCharge>[\d.]+)',
        type: 'DEBIT',
        description: 'synthetic serviceCharge only',
        fieldMapping: const {
          'amount': '1',
          'serviceCharge': '2',
        },
      );
      final result = await PatternParser.extractTransactionDetails(
        'Debit 100.00 SC 5.00',
        '',
        DateTime(2026, 7, 12),
        [pattern],
      );
      expect(result, isNotNull);
      expect(result!.containsKey('totalFee'), isFalse,
          reason: 'without vat, totalFee must not be derived as 0 or partial');
    });
  });

  group('regex safety across the corpus', () {
    test('no pattern regex exhibits catastrophic backtracking on '
        'adversarial input', () {
      final patterns = _loadPatterns();
      final adversarialInput = List.filled(200, '1234567890').join();

      for (final pattern in patterns) {
        RegExp regex;
        try {
          regex = RegExp(pattern.regex,
              caseSensitive: false, multiLine: true, dotAll: true);
        } catch (_) {
          continue;
        }
        final stopwatch = Stopwatch()..start();
        try {
          regex.firstMatch(adversarialInput);
        } catch (_) {}
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000),
            reason: '${pattern.description}: took '
                '${stopwatch.elapsedMilliseconds}ms against a 2000-char '
                'adversarial string — possible catastrophic backtracking');
      }
    });
  });
}
