import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/owned_account_transfer_service.dart';

void main() {
  final cbe = _bank(1, 'Commercial Bank of Ethiopia', 'CBE');
  final dashen = _bank(4, 'Dashen Bank', 'Dashen');
  final telebirr = _bank(6, 'Telebirr', 'Telebirr', simBased: true);
  final cbeAccount = _account(1, '1000561235345', 'Eyosias');
  final dashenAccount = _account(4, '5107635874011', 'Eyosias');
  final telebirrAccount = _account(6, '0920945085', 'Kidist');
  final secondTelebirrAccount = _account(6, '0957063583', 'Eyosias');
  final service = OwnedAccountTransferService();

  test('matches bank debit to wallet credit using bank evidence', () {
    final matches = service.findMatches(
      transactions: <Transaction>[
        _transaction(
          bankId: 1,
          owner: cbeAccount.accountNumber,
          reference: 'cbe-debit',
          type: 'DEBIT',
          amount: 5000,
          time: '2026-07-12T14:00:00',
        ),
        _transaction(
          bankId: 6,
          owner: telebirrAccount.accountNumber,
          reference: 'telebirr-credit',
          type: 'CREDIT',
          amount: 5000,
          time: '2026-07-12T14:04:00',
          creditor: 'Commercial Bank of Ethiopia',
        ),
      ],
      banks: <Bank>[cbe, dashen, telebirr],
      accounts: <Account>[cbeAccount, dashenAccount, telebirrAccount],
    );

    expect(matches, hasLength(1));
    expect(matches.single.debitTransaction.reference, 'cbe-debit');
    expect(matches.single.creditTransaction.reference, 'telebirr-credit');
  });

  test('matches the reverse wallet-to-bank direction', () {
    final matches = service.findMatches(
      transactions: <Transaction>[
        _transaction(
          bankId: 6,
          owner: telebirrAccount.accountNumber,
          reference: 'telebirr-debit',
          type: 'DEBIT',
          amount: 3900,
          time: '2026-07-09T10:08:18',
          receiver: 'Dashen Bank SC',
        ),
        _transaction(
          bankId: 4,
          owner: dashenAccount.accountNumber,
          reference: 'dashen-credit',
          type: 'CREDIT',
          amount: 3900,
          time: '2026-07-09T10:08:22',
          creditor: 'telebirr Sender Name: KIDIST',
        ),
      ],
      banks: <Bank>[cbe, dashen, telebirr],
      accounts: <Account>[cbeAccount, dashenAccount, telebirrAccount],
    );

    expect(matches, hasLength(1));
    expect(matches.single.debitAccount.accountNumber, '0920945085');
    expect(matches.single.creditAccount.accountNumber, '5107635874011');
  });

  test('matches bank-to-bank transfers with a tight timestamp', () {
    final matches = service.findMatches(
      transactions: <Transaction>[
        _transaction(
          bankId: 4,
          owner: dashenAccount.accountNumber,
          reference: 'dashen-debit',
          type: 'DEBIT',
          amount: 10000,
          time: '2026-05-29T13:23:39',
        ),
        _transaction(
          bankId: 1,
          owner: cbeAccount.accountNumber,
          reference: 'cbe-credit',
          type: 'CREDIT',
          amount: 10000,
          time: '2026-05-29T13:23:54',
        ),
      ],
      banks: <Bank>[cbe, dashen, telebirr],
      accounts: <Account>[cbeAccount, dashenAccount, telebirrAccount],
    );

    expect(matches, hasLength(1));
  });

  test('matches transfers between two accounts at the same bank', () {
    final matches = service.findMatches(
      transactions: <Transaction>[
        _transaction(
          bankId: 6,
          owner: telebirrAccount.accountNumber,
          reference: 'kidist-debit',
          type: 'DEBIT',
          amount: 300,
          time: '2026-07-12T14:01:00',
          receiver: 'EYOSIAS',
        ),
        _transaction(
          bankId: 6,
          owner: secondTelebirrAccount.accountNumber,
          reference: 'eyosias-credit',
          type: 'CREDIT',
          amount: 300,
          time: '2026-07-12T14:01:05',
          creditor: 'KIDIST',
        ),
      ],
      banks: <Bank>[cbe, dashen, telebirr],
      accounts: <Account>[
        cbeAccount,
        dashenAccount,
        telebirrAccount,
        secondTelebirrAccount,
      ],
    );

    expect(matches, hasLength(1));
    expect(matches.single.debitAccount.accountHolderName, 'Kidist');
    expect(matches.single.creditAccount.accountHolderName, 'Eyosias');
  });

  test('does not match same amount without identity or tight timing', () {
    final matches = service.findMatches(
      transactions: <Transaction>[
        _transaction(
          bankId: 6,
          owner: telebirrAccount.accountNumber,
          reference: 'unrelated-debit',
          type: 'DEBIT',
          amount: 500,
          time: '2026-07-12T12:00:00',
          receiver: 'Someone Else',
        ),
        _transaction(
          bankId: 1,
          owner: cbeAccount.accountNumber,
          reference: 'unrelated-credit',
          type: 'CREDIT',
          amount: 500,
          time: '2026-07-12T12:01:00',
        ),
      ],
      banks: <Bank>[cbe, dashen, telebirr],
      accounts: <Account>[cbeAccount, dashenAccount, telebirrAccount],
    );

    expect(matches, isEmpty);
  });

  test('does not use timing alone when an external recipient is named', () {
    final matches = service.findMatches(
      transactions: <Transaction>[
        _transaction(
          bankId: 6,
          owner: telebirrAccount.accountNumber,
          reference: 'external-debit',
          type: 'DEBIT',
          amount: 500,
          time: '2026-07-12T12:00:00',
          receiver: 'Someone Else',
        ),
        _transaction(
          bankId: 1,
          owner: cbeAccount.accountNumber,
          reference: 'nearby-credit',
          type: 'CREDIT',
          amount: 500,
          time: '2026-07-12T12:00:05',
        ),
      ],
      banks: <Bank>[cbe, dashen, telebirr],
      accounts: <Account>[cbeAccount, dashenAccount, telebirrAccount],
    );

    expect(matches, isEmpty);
  });

  test('does not treat CBEBirr as evidence for a CBE account', () {
    final matches = service.findMatches(
      transactions: <Transaction>[
        _transaction(
          bankId: 6,
          owner: telebirrAccount.accountNumber,
          reference: 'cbebirr-debit',
          type: 'DEBIT',
          amount: 750,
          time: '2026-07-12T12:00:00',
          receiver: 'CBEBirr subscriber',
        ),
        _transaction(
          bankId: 1,
          owner: cbeAccount.accountNumber,
          reference: 'unrelated-cbe-credit',
          type: 'CREDIT',
          amount: 750,
          time: '2026-07-12T12:01:00',
        ),
      ],
      banks: <Bank>[cbe, dashen, telebirr],
      accounts: <Account>[cbeAccount, dashenAccount, telebirrAccount],
    );

    expect(matches, isEmpty);
  });
}

Bank _bank(int id, String name, String shortName, {bool? simBased}) {
  return Bank(
    id: id,
    name: name,
    shortName: shortName,
    codes: <String>[shortName],
    image: '',
    simBased: simBased,
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
  String? receiver,
}) {
  return Transaction(
    bankId: bankId,
    ownerAccountNumber: owner,
    reference: reference,
    type: type,
    amount: amount,
    time: time,
    creditor: creditor,
    receiver: receiver,
  );
}
