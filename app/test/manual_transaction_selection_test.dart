import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/utils/manual_transaction_selection.dart';

void main() {
  test('shows one bank choice while retaining every account choice', () {
    final accounts = <AccountSummary>[
      _summary(bankId: 6, number: '0920945085'),
      _summary(bankId: 6, number: '0957063583'),
      _summary(bankId: 1, number: '10001234'),
    ];

    final banks = manualTransactionBankRepresentatives(accounts);
    final telebirrAccounts = manualTransactionAccountsForBank(accounts, 6);

    expect(banks.map((account) => account.bankId), <int>[6, 1]);
    expect(
      telebirrAccounts.map((account) => account.accountNumber),
      <String>['0920945085', '0957063583'],
    );
  });

  test('calculates balance when blank and honors an entered balance', () {
    expect(
      resolveManualBalanceAfter(
        currentBalance: 100,
        amount: 25,
        isDebit: true,
      ),
      75,
    );
    expect(
      resolveManualBalanceAfter(
        currentBalance: 100,
        amount: 25,
        isDebit: true,
        enteredBalanceAfter: 725.50,
      ),
      725.50,
    );
  });
}

AccountSummary _summary({required int bankId, required String number}) {
  return AccountSummary(
    bankId: bankId,
    accountNumber: number,
    accountHolderName: 'Owner',
    totalTransactions: 0,
    totalCredit: 0,
    totalDebit: 0,
    settledBalance: 0,
    balance: 100,
    pendingCredit: 0,
  );
}
