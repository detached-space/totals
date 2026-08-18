import 'package:flutter_test/flutter_test.dart';
import 'package:totals/utils/spending_map_metrics.dart';

void main() {
  group('Spending Map net amount', () {
    test('calculates credit minus debit using amount magnitudes', () {
      final credit = spendingMapNetContribution(
        transactionType: ' credit ',
        amount: -1250,
      );
      final debit = spendingMapNetContribution(
        transactionType: 'DEBIT',
        amount: 300,
      );

      expect(credit + debit, 950);
    });

    test('ignores unsupported and non-finite values', () {
      expect(
        spendingMapNetContribution(transactionType: 'OTHER', amount: 100),
        0,
      );
      expect(
        spendingMapNetContribution(
          transactionType: 'CREDIT',
          amount: double.infinity,
        ),
        0,
      );
    });

    test('formats compact signed puck labels', () {
      expect(formatSpendingMapNetPuckLabel(0), '0');
      expect(formatSpendingMapNetPuckLabel(-450), '-450');
      expect(formatSpendingMapNetPuckLabel(1250), startsWith('+'));
      expect(formatSpendingMapNetPuckLabel(1250), contains('K'));
    });
  });
}
