import 'package:flutter_test/flutter_test.dart';
import 'package:totals/utils/account_sort.dart';

void main() {
  test('orders accounts by bank, holder name, then account number', () {
    final accounts = <({int bank, String holder, String number})>[
      (bank: 2, holder: 'Alice', number: '200'),
      (bank: 1, holder: 'Bob', number: '300'),
      (bank: 2, holder: 'alice', number: '100'),
      (bank: 1, holder: 'Alice', number: '900'),
      (bank: 1, holder: '', number: '100'),
    ]..sort(
        (left, right) => compareAccountDisplayFields(
          leftBankId: left.bank,
          rightBankId: right.bank,
          leftHolderName: left.holder,
          rightHolderName: right.holder,
          leftAccountNumber: left.number,
          rightAccountNumber: right.number,
          bankNameForId: (bankId) => switch (bankId) {
            1 => 'Abyssinia Bank',
            2 => 'Commercial Bank',
            _ => 'Unknown',
          },
        ),
      );

    expect(
      accounts
          .map((account) =>
              '${account.bank}:${account.holder}:${account.number}')
          .toList(growable: false),
      <String>[
        '1:Alice:900',
        '1:Bob:300',
        '1::100',
        '2:alice:100',
        '2:Alice:200',
      ],
    );
  });
}
