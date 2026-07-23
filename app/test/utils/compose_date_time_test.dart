import 'package:flutter_test/flutter_test.dart';
import 'package:totals/utils/pattern_parser.dart';

void main() {
  final messageDate = DateTime(2026, 7, 12);

  group('boundary cases — should already be correct', () {
    test('12h midnight: "12:00 AM" -> hour 0', () {
      final r = PatternParser.composeDateTime(messageDate, '12:00 AM');
      expect(DateTime.parse(r!).hour, 0);
    });

    test('12h noon: "12:00 PM" -> hour 12', () {
      final r = PatternParser.composeDateTime(messageDate, '12:00 PM');
      expect(DateTime.parse(r!).hour, 12);
    });

    test('12h with seconds: "2:45:30 PM" -> 14:45:30', () {
      final r = PatternParser.composeDateTime(messageDate, '2:45:30 PM');
      final dt = DateTime.parse(r!);
      expect(dt.hour, 14);
      expect(dt.minute, 45);
      expect(dt.second, 30);
    });

    test('24h with seconds: "08:00:00" -> hour 8', () {
      final r = PatternParser.composeDateTime(messageDate, '08:00:00');
      expect(DateTime.parse(r!).hour, 8);
    });

    test('24h zero hour: "00:15" -> hour 0', () {
      final r = PatternParser.composeDateTime(messageDate, '00:15');
      expect(DateTime.parse(r!).hour, 0);
    });

    test('lowercase am/pm: "2:45pm" -> hour 14', () {
      final r = PatternParser.composeDateTime(messageDate, '2:45pm');
      expect(DateTime.parse(r!).hour, 14);
    });
  });

  group('out-of-range input — requires the bounds-check patch to pass', () {
    test('12h hour > 12 with PM suffix does not roll into next day', () {
      final r = PatternParser.composeDateTime(messageDate, '14:45 PM');
      expect(r, isNull);
    });

    test('minute > 59 does not roll into the next hour', () {
      final r = PatternParser.composeDateTime(messageDate, '2:99 PM');
      expect(r, isNull);
    });

    test('24h hour > 23 does not roll into following days', () {
      final r = PatternParser.composeDateTime(messageDate, '99:15');
      expect(r, isNull);
    });
  });

  group('24h unpadded hour — widened to \d{1,2}, now composes', () {
    test('"9:15" -> hour 9', () {
      final r = PatternParser.composeDateTime(messageDate, '9:15');
      final dt = DateTime.parse(r!);
      expect(dt.hour, 9);
      expect(dt.minute, 15);
    });
  });

  group('malformed input — safe fallthrough, no throw', () {
    test('trailing unit text: "14:30 hrs"', () {
      final r = PatternParser.composeDateTime(messageDate, '14:30 hrs');
      expect(r, isNull);
    });

    test('empty fragment', () {
      final r = PatternParser.composeDateTime(messageDate, '   ');
      expect(r, isNull);
    });

    test('dot separator instead of colon: "2.45 PM"', () {
      final r = PatternParser.composeDateTime(messageDate, '2.45 PM');
      expect(r, isNull);
    });
  });

  group('pattern corpus regression — fill in the two TODOs', () {
    final patterns = <dynamic>[];

    for (final pattern in patterns) {
      final hasTimeGroup = true;
      if (!hasTimeGroup) continue;

      test('${pattern.toString()}: time composes to valid ISO-8601', () async {
        final result = await PatternParser.extractTransactionDetails(
          '',    // TODO: plug in a realistic sample SMS body for this pattern
          '',    // TODO: plug in the matching sender address
          messageDate,
          [],   // TODO: plug in the real 116-pattern list
        );
        expect(result?['time'], isNotNull,
            reason: 'time group present but composition failed');
        expect(DateTime.tryParse(result!['time'] as String), isNotNull,
            reason: 'composed time is not valid ISO-8601');
      });
    }
  });
}
