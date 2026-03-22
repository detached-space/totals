import 'package:flutter_test/flutter_test.dart';
import 'package:totals/utils/math_utils.dart';
import 'package:totals/models/transaction.dart';

void main() {
  group('MathUtils.findMean', () {
    test('returns correct mean for a list of values', () {
      expect(MathUtils.findMean([1, 2, 3, 4, 5]), equals(3.0));
    });

    test('returns single value when list has one element', () {
      expect(MathUtils.findMean([42.0]), equals(42.0));
    });

    test('handles decimal values', () {
      expect(MathUtils.findMean([1.5, 2.5, 3.0]), closeTo(2.333, 0.001));
    });
  });

  group('MathUtils.findSum', () {
    test('sums a list of doubles', () {
      expect(MathUtils.findSum([10.0, 20.0, 30.0]), equals(60.0));
    });

    test('returns 0 for list of zeros', () {
      expect(MathUtils.findSum([0.0, 0.0, 0.0]), equals(0.0));
    });

    test('handles single element', () {
      expect(MathUtils.findSum([99.5]), equals(99.5));
    });
  });

  group('MathUtils.findTransactionSum', () {
    Transaction makeTx(double amount) => Transaction(
          amount: amount,
          reference: 'REF',
          type: 'DEBIT',
        );

    test('sums transaction amounts', () {
      final txns = [makeTx(100.0), makeTx(200.0), makeTx(50.0)];
      expect(MathUtils.findTransactionSum(txns), equals(350.0));
    });

    test('returns 0 for empty list', () {
      expect(MathUtils.findTransactionSum([]), equals(0.0));
    });

    test('handles single transaction', () {
      expect(MathUtils.findTransactionSum([makeTx(500.0)]), equals(500.0));
    });
  });

  group('MathUtils.findVariance', () {
    test('returns 0 for empty list', () {
      expect(MathUtils.findVariance([]), equals(0.0));
    });

    test('returns 0 for single element', () {
      expect(MathUtils.findVariance([5.0]), equals(0.0));
    });

    test('returns correct variance for known values', () {
      // values: [2, 4, 4, 4, 5, 5, 7, 9], mean=5, variance=4
      expect(
        MathUtils.findVariance([2, 4, 4, 4, 5, 5, 7, 9]),
        closeTo(4.0, 0.001),
      );
    });

    test('returns 0 when all values are equal', () {
      expect(MathUtils.findVariance([3.0, 3.0, 3.0]), equals(0.0));
    });
  });
}
