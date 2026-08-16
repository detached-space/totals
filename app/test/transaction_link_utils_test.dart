import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/transaction_link_utils.dart';

void main() {
  group('Telebirr receipt links', () {
    test('resolves a scoped credit transaction to its public receipt', () {
      final transaction = Transaction(
        amount: 500,
        reference: 'DA99NXARVP__totals_tb_leg_credit',
        bankId: 6,
        type: 'CREDIT',
      );

      expect(
        TransactionLinkUtils.resolveReferenceLink(transaction),
        'https://transactioninfo.ethiotelecom.et/receipt/DA99NXARVP',
      );
    });

    test('does not create a receipt link for an internal fallback reference',
        () {
      final transaction = Transaction(
        amount: 500,
        reference: '6_2026-07-26T12:00:00.000',
        bankId: 6,
        type: 'CREDIT',
      );

      expect(TransactionLinkUtils.resolveReferenceLink(transaction), isNull);
    });

    test('removes legacy sentence punctuation from the receipt reference', () {
      expect(
        TransactionLinkUtils.inferTransactionLink(
          bankId: 6,
          reference: 'DA99NXARVP.',
        ),
        'https://transactioninfo.ethiotelecom.et/receipt/DA99NXARVP',
      );
    });
  });
}
