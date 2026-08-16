import 'package:flutter_test/flutter_test.dart';
import 'package:totals/utils/sms_transaction_source.dart';

void main() {
  test('builds stable SMS source identity from message parts', () {
    final source = SmsTransactionSource.fromParts(
      bankId: 1,
      messageId: 42,
      senderAddress: ' CBE ',
      body: 'Paid  10\nBirr',
      dateMillis: 1710000000000,
    );

    final sameMessage = SmsTransactionSource.fromParts(
      bankId: 1,
      messageId: 42,
      senderAddress: 'cbe',
      body: 'Paid 10 Birr',
      dateMillis: 1710000000000,
    );

    final inboxCopyWithDifferentProviderDate = SmsTransactionSource.fromParts(
      bankId: 1,
      messageId: 42,
      senderAddress: 'cbe',
      body: 'Paid 10 Birr',
      dateMillis: 1710000000001,
    );

    expect(source.sourceType, SmsTransactionSource.smsType);
    expect(source.sourceMessageId, '42');
    expect(source.sourceFingerprint, isNotNull);
    expect(source.sourceFingerprint, sameMessage.sourceFingerprint);
    expect(
      source.sourceFingerprint,
      inboxCopyWithDifferentProviderDate.sourceFingerprint,
    );
  });

  test('keeps stable fingerprint when SMS date is missing', () {
    final source = SmsTransactionSource.fromParts(
      bankId: 1,
      messageId: 42,
      senderAddress: 'CBE',
      body: 'Paid 10 Birr',
    );

    expect(source.hasIdentity, isTrue);
    expect(source.sourceMessageId, '42');
    expect(source.sourceFingerprint, isNotNull);
  });

  test('keeps message id when fingerprint inputs are incomplete', () {
    final source = SmsTransactionSource.fromParts(
      bankId: 1,
      messageId: 42,
      body: 'Paid 10 Birr',
    );

    expect(source.hasIdentity, isTrue);
    expect(source.sourceMessageId, '42');
    expect(source.sourceFingerprint, isNull);
  });

  test('scopes paired Telebirr debit and credit receipts independently', () {
    final source = SmsTransactionSource.fromParts(
      bankId: 6,
      messageId: 42,
      senderAddress: '127',
      body: 'Telebirr receipt',
    );

    final debit = source.scopeReference(
      bankId: 6,
      reference: 'DA99NXARVP',
      transactionType: 'DEBIT',
    );
    final credit = source.scopeReference(
      bankId: 6,
      reference: 'DA99NXARVP',
      transactionType: 'CREDIT',
    );

    expect(debit, 'DA99NXARVP__totals_tb_leg_debit');
    expect(credit, 'DA99NXARVP__totals_tb_leg_credit');
    expect(debit, isNot(credit));
    expect(
      SmsTransactionSource.displayReference(
        bankId: 6,
        storedReference: debit,
      ),
      'DA99NXARVP',
    );
    expect(
      source.scopeReference(
        bankId: 6,
        reference: debit,
        transactionType: 'DEBIT',
      ),
      debit,
      reason: 'Scoping must be idempotent during reparse',
    );
    expect(
      SmsTransactionSource.logicalLegKey(
        bankId: 6,
        reference: 'DA99NXARVP',
        transactionType: 'DEBIT',
      ),
      SmsTransactionSource.logicalLegKey(
        bankId: 6,
        reference: debit,
        transactionType: 'DEBIT',
      ),
      reason: 'Legacy raw rows must match their scoped reparse leg',
    );
    expect(
      SmsTransactionSource.logicalLegKey(
        bankId: 6,
        reference: debit,
        transactionType: 'DEBIT',
      ),
      isNot(
        SmsTransactionSource.logicalLegKey(
          bankId: 6,
          reference: credit,
          transactionType: 'CREDIT',
        ),
      ),
    );
    expect(
      SmsTransactionSource.logicalLegKey(
        bankId: 6,
        reference: 'DA99NXARVP.',
        transactionType: 'DEBIT',
      ),
      SmsTransactionSource.logicalLegKey(
        bankId: 6,
        reference: debit,
        transactionType: 'DEBIT',
      ),
      reason: 'Sentence punctuation from a legacy parser is not identity',
    );
  });

  test('does not rewrite non-Telebirr references', () {
    final source = SmsTransactionSource.fromParts(
      bankId: 1,
      messageId: 42,
      senderAddress: 'CBE',
      body: 'Payment receipt',
    );

    expect(
      source.scopeReference(
        bankId: 1,
        reference: 'FT123',
        transactionType: 'DEBIT',
      ),
      'FT123',
    );
  });
}
