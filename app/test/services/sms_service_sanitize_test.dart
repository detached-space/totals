import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/sms_service.dart';

void main() {
  group('SmsService.sanitizeAmount', () {
    test('parses a plain number', () {
      expect(SmsService.sanitizeAmount('1234.56'), equals(1234.56));
    });

    test('removes commas from formatted amount', () {
      expect(SmsService.sanitizeAmount('1,234.56'), equals(1234.56));
    });

    test('removes commas from large amounts', () {
      expect(SmsService.sanitizeAmount('1,000,000.00'), equals(1000000.0));
    });

    test('returns 0.0 for null', () {
      expect(SmsService.sanitizeAmount(null), equals(0.0));
    });

    test('returns 0.0 for empty string', () {
      expect(SmsService.sanitizeAmount(''), equals(0.0));
    });

    test('returns 0.0 for non-numeric string', () {
      expect(SmsService.sanitizeAmount('ETB'), equals(0.0));
    });

    test('handles trailing dot', () {
      expect(SmsService.sanitizeAmount('500.'), equals(500.0));
    });

    test('handles integer string', () {
      expect(SmsService.sanitizeAmount('750'), equals(750.0));
    });

    test('handles whitespace around the value', () {
      expect(SmsService.sanitizeAmount('  200.00  '), equals(200.0));
    });

    test('handles multiple dots — keeps first decimal only', () {
      expect(SmsService.sanitizeAmount('1.2.3'), equals(1.23));
    });
  });
}
