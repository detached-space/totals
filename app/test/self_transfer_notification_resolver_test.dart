import 'package:flutter_test/flutter_test.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/self_transfer_notification_resolver.dart';

void main() {
  final resolver = SelfTransferNotificationResolver();
  final cbe = _bank(1, 'Commercial Bank of Ethiopia', 'CBE');
  final telebirr = _bank(6, 'Telebirr', 'Telebirr');
  final cbeAccount = _account(1, '1000561235345', 'Eyosias');
  final telebirrAccount = _account(6, '0920945085', 'Eyosias');

  test('suppresses both sides of a detected owned-account transfer', () {
    final debit = _transaction(
      bankId: 1,
      owner: cbeAccount.accountNumber,
      reference: 'cbe-debit',
      type: 'DEBIT',
      amount: 5000,
      time: '2026-07-12T14:00:00',
    );
    final credit = _transaction(
      bankId: 6,
      owner: telebirrAccount.accountNumber,
      reference: 'telebirr-credit',
      type: 'CREDIT',
      amount: 5000,
      time: '2026-07-12T14:04:00',
      creditor: 'Commercial Bank of Ethiopia',
    );

    final suppressed = resolver.transactionsToSuppress(
      transaction: credit,
      transactions: <Transaction>[debit, credit],
      banks: <Bank>[cbe, telebirr],
      accounts: <Account>[cbeAccount, telebirrAccount],
      categories: const <Category>[],
    );

    expect(
      suppressed.map((transaction) => transaction.reference),
      containsAll(<String>['cbe-debit', 'telebirr-credit']),
    );
  });

  test('suppresses a transaction assigned to the Self category', () {
    final transaction = _transaction(
      bankId: 1,
      owner: cbeAccount.accountNumber,
      reference: 'manual-self',
      type: 'DEBIT',
      amount: 250,
      time: '2026-07-12T15:00:00',
      categoryIds: const <int>[42],
    );

    final suppressed = resolver.transactionsToSuppress(
      transaction: transaction,
      transactions: <Transaction>[transaction],
      banks: <Bank>[cbe],
      accounts: <Account>[cbeAccount],
      categories: const <Category>[
        Category(id: 42, name: 'Self', essential: false),
      ],
    );

    expect(suppressed, <Transaction>[transaction]);
  });

  test('keeps an unmatched external transaction notification', () {
    final transaction = _transaction(
      bankId: 1,
      owner: cbeAccount.accountNumber,
      reference: 'external-debit',
      type: 'DEBIT',
      amount: 250,
      time: '2026-07-12T15:30:00',
    );

    final suppressed = resolver.transactionsToSuppress(
      transaction: transaction,
      transactions: <Transaction>[transaction],
      banks: <Bank>[cbe, telebirr],
      accounts: <Account>[cbeAccount, telebirrAccount],
      categories: const <Category>[],
    );

    expect(suppressed, isEmpty);
  });

  test('suppresses the linked bank notification for an ATM cash transfer', () {
    final withdrawal = _transaction(
      bankId: 1,
      owner: cbeAccount.accountNumber,
      reference: 'atm-withdrawal',
      type: 'DEBIT',
      amount: 1000,
      time: '2026-07-12T16:00:00',
    );
    final cashCredit = _transaction(
      bankId: CashConstants.bankId,
      owner: CashConstants.defaultAccountNumber,
      reference: CashConstants.buildAtmReference(withdrawal.reference),
      type: 'CREDIT',
      amount: 1000,
      time: '2026-07-12T16:00:00',
    );

    final suppressed = resolver.transactionsToSuppress(
      transaction: withdrawal,
      transactions: <Transaction>[withdrawal, cashCredit],
      banks: <Bank>[cbe],
      accounts: <Account>[cbeAccount],
      categories: const <Category>[],
    );

    expect(
      suppressed.map((transaction) => transaction.reference),
      containsAll(<String>[withdrawal.reference, cashCredit.reference]),
    );
  });
}

Bank _bank(int id, String name, String shortName) {
  return Bank(
    id: id,
    name: name,
    shortName: shortName,
    codes: <String>[shortName],
    image: '',
  );
}

Account _account(int bankId, String number, String holder) {
  return Account(
    accountNumber: number,
    bank: bankId,
    balance: 0,
    accountHolderName: holder,
  );
}

Transaction _transaction({
  required int bankId,
  required String owner,
  required String reference,
  required String type,
  required double amount,
  required String time,
  String? creditor,
  List<int>? categoryIds,
}) {
  return Transaction(
    bankId: bankId,
    ownerAccountNumber: owner,
    reference: reference,
    type: type,
    amount: amount,
    time: time,
    creditor: creditor,
    categoryIds: categoryIds,
  );
}
