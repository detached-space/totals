import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/account.dart';
import 'package:totals/utils/account_balance_resolver.dart';

void main() {
  test('legacy accounts default to active and included in totals', () {
    final account = Account.fromJson(<String, dynamic>{
      'accountNumber': '5107635874011',
      'bank': 4,
      'balance': 78.20,
      'accountHolderName': 'Eyosias',
    });

    expect(account.includeInTotals, isTrue);
    expect(account.isDormant, isFalse);
  });

  test('account total and dormancy preferences survive export data', () {
    final source = Account(
      accountNumber: '0920945085',
      bank: 6,
      balance: 563.21,
      accountHolderName: 'Kidist',
      includeInTotals: false,
      isDormant: true,
      isDefault: true,
    );

    final restored = Account.fromJson(source.toJson());

    expect(restored.includeInTotals, isFalse);
    expect(restored.isDormant, isTrue);
    expect(restored.isDefault, isTrue);
  });

  test('excluded accounts do not contribute to aggregate balances', () {
    final included = Account(
      accountNumber: '1001',
      bank: 1,
      balance: 150,
      accountHolderName: 'Included',
    );
    final excluded = Account(
      accountNumber: '1002',
      bank: 1,
      balance: 900,
      accountHolderName: 'Excluded',
      includeInTotals: false,
      isDormant: true,
    );
    final dormant = Account(
      accountNumber: '1003',
      bank: 1,
      balance: 700,
      accountHolderName: 'Dormant',
      includeInTotals: true,
      isDormant: true,
    );

    expect(
      includedAccountBalanceTotal(
        accounts: <Account>[included, excluded, dormant],
      ),
      150,
    );
  });
}
