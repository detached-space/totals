import 'dart:math';

import '../models/transaction.dart';

class MathUtils {
  static double findMean(List<double> values) {
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double findSum(List<double> values) {
    return values.fold(0, (sum, value) => sum + value);
  }

  static double findTransactionSum(List<Transaction> txns) {
    return txns.fold(0, (sum, txn) => sum + txn.amount);
  }

  static double findVariance(List<double> values) {
    // early return to guard empty list cases.
    if (values.isEmpty) return 0;

    double mean = findMean(values);
    return values
            .map(
              (x) =>
                  pow(x - mean, 2), // find each value minus mean, and square it
            )
            .reduce((a, b) => a + b) /
        values
            .length; // then sum the resulting squares and divide the sum by total number of values
  }
}
