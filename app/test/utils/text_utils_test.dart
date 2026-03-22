import 'package:flutter_test/flutter_test.dart';
import 'package:totals/utils/text_utils.dart';

void main() {
  group('formatNumberWithComma', () {
    test('formats thousands with comma', () {
      expect(formatNumberWithComma(1000.0), equals('1,000.00'));
    });

    test('formats millions', () {
      expect(formatNumberWithComma(1000000.0), equals('1,000,000.00'));
    });

    test('formats small number with two decimal places', () {
      expect(formatNumberWithComma(42.5), equals('42.50'));
    });

    test('returns 0.00 for null', () {
      expect(formatNumberWithComma(null), equals('0.00'));
    });

    test('handles zero', () {
      expect(formatNumberWithComma(0.0), equals('0.00'));
    });
  });

  group('formatNumberAbbreviated', () {
    test('abbreviates millions', () {
      expect(formatNumberAbbreviated(1500000.0), equals('1.5 M'));
    });

    test('abbreviates thousands', () {
      expect(formatNumberAbbreviated(2500.0), equals('2.5 k'));
    });

    test('returns integer string for values under 1000', () {
      expect(formatNumberAbbreviated(500.0), equals('500'));
    });

    test('returns 0 for null', () {
      expect(formatNumberAbbreviated(null), equals('0'));
    });

    test('handles negative millions', () {
      expect(formatNumberAbbreviated(-2000000.0), equals('-2 M'));
    });

    test('handles negative thousands', () {
      expect(formatNumberAbbreviated(-1500.0), equals('-1.5 k'));
    });

    test('handles exact 1000', () {
      expect(formatNumberAbbreviated(1000.0), equals('1 k'));
    });
  });

  group('formatTime', () {
    test('formats a full ISO timestamp', () {
      expect(
        formatTime('2025-03-10 22:19:45.000'),
        equals('10 Mar 2025 | 22:19'),
      );
    });

    test('returns Invalid time input for garbage input', () {
      expect(formatTime('not-a-date'), equals('Invalid time input'));
    });
  });

  group('formatTelebirrSenderName', () {
    test('returns plain name unchanged', () {
      expect(formatTelebirrSenderName('Abebe Bikila'), equals('Abebe Bikila'));
    });

    test('strips phone number from name with digits', () {
      expect(
        formatTelebirrSenderName('Abebe Bikila (0911234567)'),
        equals('Abebe Bikila'),
      );
    });

    test('returns empty string for empty input', () {
      expect(formatTelebirrSenderName(''), equals(''));
    });

    test('handles single word name', () {
      expect(formatTelebirrSenderName('Abebe'), equals('Abebe'));
    });

    test('returns first two words for multi-word name with digits', () {
      expect(
        formatTelebirrSenderName('Abebe Bikila Bekele 0911234567'),
        equals('Abebe Bikila'),
      );
    });
  });
}
