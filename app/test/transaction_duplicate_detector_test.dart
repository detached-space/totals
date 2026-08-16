import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/transaction_duplicate_detector.dart';

void main() {
  test('merges a legacy Telebirr row into its scoped SMS-backed row', () {
    final scoped = _transaction(
      'DGC4RFG5GU__totals_tb_leg_debit',
      ownerAccountNumber: '0920945085',
      sourceMessageId: '14315',
      sourceSubscriptionId: 2,
      receiver: 'Abayneh Desta',
    );
    final legacy = _transaction(
      'DGC4RFG5GU',
      sourceFingerprint: '-5e0551b076abc960',
      receiver: 'Abayneh Desta (2519****0000)',
    );

    final plans = buildLegacySmsReferenceDeduplicationPlans(
      transactions: <Transaction>[legacy, scoped],
    );

    expect(plans, hasLength(1));
    expect(plans.single.keeper.reference, scoped.reference);
    expect(plans.single.duplicateReferences, <String>[legacy.reference]);
    expect(
      plans.single.mergedKeeper.ownerAccountNumber,
      scoped.ownerAccountNumber,
    );
    expect(plans.single.mergedKeeper.sourceMessageId, '14315');
    expect(plans.single.mergedKeeper.sourceSubscriptionId, 2);
  });

  test('does not merge opposite Telebirr ledger directions', () {
    final debit = _transaction('DA99NXARVP__totals_tb_leg_debit');
    final legacyCredit = _transaction(
      'DA99NXARVP.',
      type: 'CREDIT',
    );

    expect(
      buildLegacySmsReferenceDeduplicationPlans(
        transactions: <Transaction>[debit, legacyCredit],
      ),
      isEmpty,
    );
  });

  test('leaves conflicting durable owners untouched', () {
    final scoped = _transaction(
      'DGC4RFG5GU__totals_tb_leg_debit',
      ownerAccountNumber: '0920945085',
    );
    final legacy = _transaction(
      'DGC4RFG5GU',
      ownerAccountNumber: '0957063583',
    );

    expect(
      buildLegacySmsReferenceDeduplicationPlans(
        transactions: <Transaction>[scoped, legacy],
      ),
      isEmpty,
    );
  });

  test('manual owner wins while legacy duplicate is still removed', () {
    final scoped = _transaction(
      'DGC4RFG5GU__totals_tb_leg_debit',
      ownerAccountNumber: '0920945085',
      ownerAssignmentSource: Transaction.automaticOwnerAssignment,
      sourceMessageId: '14315',
    );
    final manuallyAssignedLegacy = _transaction(
      'DGC4RFG5GU',
      ownerAccountNumber: '0957063583',
      ownerAssignmentSource: Transaction.manualOwnerAssignment,
    );

    final plans = buildLegacySmsReferenceDeduplicationPlans(
      transactions: <Transaction>[scoped, manuallyAssignedLegacy],
    );

    expect(plans, hasLength(1));
    expect(
      plans.single.mergedKeeper.ownerAccountNumber,
      '0957063583',
    );
    expect(
      plans.single.mergedKeeper.ownerAssignmentSource,
      Transaction.manualOwnerAssignment,
    );
    expect(plans.single.duplicateReferences, hasLength(1));
  });
}

Transaction _transaction(
  String reference, {
  String type = 'DEBIT',
  String? ownerAccountNumber,
  String? ownerAssignmentSource,
  String? sourceMessageId,
  String? sourceFingerprint,
  int? sourceSubscriptionId,
  String? receiver,
}) {
  return Transaction(
    amount: 120,
    reference: reference,
    bankId: 6,
    type: type,
    currentBalance: '563.21',
    ownerAccountNumber: ownerAccountNumber,
    ownerAssignmentSource: ownerAssignmentSource,
    sourceType: 'sms',
    sourceMessageId: sourceMessageId,
    sourceFingerprint: sourceFingerprint,
    sourceSubscriptionId: sourceSubscriptionId,
    receiver: receiver,
  );
}
