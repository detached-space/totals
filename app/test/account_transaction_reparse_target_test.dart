import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/account_transaction_reparse_service.dart';

void main() {
  final transaction = Transaction(amount: 10, reference: 'ref');

  test('registered account targets retain their account identity', () {
    final target = AccountTransactionReparseTarget(
      accountNumber: '10001234',
      transactions: <Transaction>[transaction],
    );

    expect(target.unmatchedOnly, isFalse);
    expect(target.targetKey, 'account:10001234');
    expect(target.displayLabel, '10001234');
  });

  test('Other transactions uses a distinct unmatched target', () {
    final target = AccountTransactionReparseTarget.otherTransactions(
      transactions: <Transaction>[transaction],
    );

    expect(target.unmatchedOnly, isTrue);
    expect(target.targetKey, 'other-transactions');
    expect(target.displayLabel, 'Other transactions');
    expect(
      target.accountNumber,
      AccountTransactionReparseTarget.unmatchedAccountKey,
    );
  });
}
