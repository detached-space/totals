import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/account_balance_refresh.dart';

void main() {
  final telebirr = _bank(6, 'Telebirr');
  final cbeBirr = _bank(37, 'CBE Birr');
  final telebirrAccount = _account(6, balance: 1892.21);
  final cbeBirrAccount = _account(37, balance: 1892.21);
  final banksById = <int, Bank>{6: telebirr, 37: cbeBirr};

  test('does not use another bank transaction as balance evidence', () {
    final balance = resolveRefreshedAccountBalance(
      account: cbeBirrAccount,
      bank: cbeBirr,
      accounts: <Account>[telebirrAccount, cbeBirrAccount],
      banksById: banksById,
      transactions: <Transaction>[
        _transaction(
          bankId: 6,
          balance: '1892.21',
          time: '2026-07-12T15:51:28',
        ),
      ],
    );

    expect(balance, 0);
  });

  test('uses the latest balance from the same bank and account', () {
    final balance = resolveRefreshedAccountBalance(
      account: cbeBirrAccount,
      bank: cbeBirr,
      accounts: <Account>[telebirrAccount, cbeBirrAccount],
      banksById: banksById,
      transactions: <Transaction>[
        _transaction(
          bankId: 37,
          balance: '75.00',
          time: '2026-07-11T10:00:00',
        ),
        _transaction(
          bankId: 37,
          balance: '125.50',
          time: '2026-07-12T10:00:00',
        ),
        _transaction(
          bankId: 6,
          balance: '5000.00',
          time: '2026-07-12T11:00:00',
        ),
      ],
    );

    expect(balance, 125.50);
  });

  test('preserves an unproven imported balance when no evidence exists', () {
    final balance = resolveRefreshedAccountBalance(
      account: _account(37, balance: 600),
      bank: cbeBirr,
      accounts: <Account>[telebirrAccount, cbeBirrAccount],
      banksById: banksById,
      transactions: const <Transaction>[],
    );

    expect(balance, isNull);
  });
}

Bank _bank(int id, String name) {
  return Bank(
    id: id,
    name: name,
    shortName: name,
    codes: <String>[name],
    image: '',
    simBased: true,
    uniformMasking: false,
  );
}

Account _account(int bankId, {required double balance}) {
  return Account(
    accountNumber: '0920945085',
    bank: bankId,
    balance: balance,
    accountHolderName: 'Owner',
    profileId: 1,
  );
}

Transaction _transaction({
  required int bankId,
  required String balance,
  required String time,
}) {
  return Transaction(
    amount: 10,
    reference: '$bankId-$time',
    bankId: bankId,
    type: 'CREDIT',
    time: time,
    currentBalance: balance,
    ownerAccountNumber: '0920945085',
    profileId: 1,
  );
}
