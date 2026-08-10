import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/transaction_amounts.dart';

void main() {
  test('external debit includes service charge and VAT', () {
    final transaction = Transaction(
      amount: 1000,
      reference: 'debit',
      type: 'DEBIT',
      serviceCharge: 10,
      vat: 1.5,
    );

    expect(transactionFeeAmount(transaction), 11.5);
    expect(transactionDebitOutflow(transaction), 1011.5);
    expect(
      transactionExpenseAmount(transaction, isSelfTransfer: false),
      1011.5,
    );
    expect(transactionBalanceDelta(transaction), -1011.5);
  });

  test('self transfer excludes principal but retains its fees', () {
    final debit = Transaction(
      amount: 1000,
      reference: 'transfer-out',
      type: 'DEBIT',
      serviceCharge: 10,
      vat: 1.5,
    );
    final credit = Transaction(
      amount: 1000,
      reference: 'transfer-in',
      type: 'CREDIT',
    );

    expect(
      transactionExpenseAmount(debit, isSelfTransfer: true),
      11.5,
    );
    expect(
      transactionIncomeAmount(credit, isSelfTransfer: true),
      0,
    );
  });
}
