import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/account_identity.dart';

void main() {
  group('Telebirr account identity', () {
    final bank = _telebirrBank();
    final first = _account(
      number: '0912345678',
      holder: 'Alice',
      subscriptionId: 1,
    );
    final second = _account(
      number: '0976543210',
      holder: 'Bob',
      subscriptionId: 2,
    );
    late List<Account> accounts;

    setUp(() {
      accounts = <Account>[first, second];
    });

    test('normalizes Ethiopian national and international phone formats', () {
      for (final value in <String>[
        '0912345678',
        '912345678',
        '251912345678',
        '+251 912 345 678',
        '00251 912 345 678',
      ]) {
        expect(
          canonicalAccountNumber(bank, value),
          '0912345678',
          reason: 'Expected $value to identify the same Telebirr account',
        );
      }
    });

    test('suggests holder names only from non-generic opening greetings', () {
      expect(
        suggestedAccountHolderNameFromSms(
          'Dear KIDIST\nYou have transferred ETB 50.00.',
        ),
        'KIDIST',
      );
      expect(
        suggestedAccountHolderNameFromSms(
          'Dear Customer\nYou have received ETB 50.00.',
        ),
        isNull,
      );
      expect(
        suggestedAccountHolderNameFromSms(
          'You have transferred ETB 50.00 to EYOSIAS.',
        ),
        isNull,
      );
    });

    test('uses only a unique owner greeting and rejects body mentions', () {
      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: accounts,
          messageBody: 'Dear Alice Example\nYour payment was successful.',
        ),
        same(first),
      );
      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: accounts,
          messageBody: 'You transferred money to Alice.',
        ),
        isNull,
      );
      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: accounts,
          messageBody: 'Dear Customer, your payment was successful.',
        ),
        isNull,
      );
    });

    test('greeting owner wins over an outgoing transfer counterparty', () {
      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: accounts,
          messageBody: '''Dear Alice
You have transferred ETB 50.00 to Bob (+251976543210).
Your current E-Money Account balance is ETB 294.75.''',
          parsedAccountNumber: second.accountNumber,
          sourceSubscriptionId: first.smsSubscriptionId,
        ),
        same(first),
      );
    });

    test('unregistered named greeting vetoes recipient and SIM evidence', () {
      final eyosias = _account(
        number: '0912343583',
        holder: 'EYOSIAS TAMIRAT',
        subscriptionId: 2,
      );
      const body = '''Dear KIDIST
You have transferred ETB 50.00 to EYOSIAS TAMIRAT (2519****3583).
Your current E-Money Account balance is ETB 294.75.''';

      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: <Account>[eyosias],
          messageBody: body,
          parsedAccountNumber: eyosias.accountNumber,
          sourceSubscriptionId: eyosias.smsSubscriptionId,
        ),
        isNull,
        reason: 'The greeting names Kidist as the wallet owner',
      );
      expect(
        hasUnmatchedSpecificAccountGreeting(body, <Account>[eyosias]),
        isTrue,
      );
    });

    test('registered greeting and bound SIM identify the wallet safely', () {
      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: <Account>[second],
          messageBody: 'Dear Bob, your transfer was successful.',
          parsedAccountNumber: first.accountNumber,
        ),
        same(second),
      );
      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: <Account>[second],
          messageBody: 'Your transfer was successful.',
          parsedAccountNumber: first.accountNumber,
          sourceSubscriptionId: second.smsSubscriptionId,
        ),
        same(second),
      );
      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: <Account>[second],
          messageBody: 'Dear Customer, your transfer was successful.',
          parsedAccountNumber: second.accountNumber,
        ),
        isNull,
        reason: 'A wallet counterparty number is not owner evidence',
      );
    });

    test('assigns a completed ATM withdrawal to the greeted wallet owner', () {
      final eyosias = _account(
        number: '0957063583',
        holder: 'EYOSIAS',
      );
      const body = '''Dear EYOSIAS
The request to withdraw ETB 1,000.00 from your telebirr account 251957063583 via secret code 671826 using Bank of Abyssinia ATM with transaction number CFS07I3GTC is successfully completed.
Your current Account balance is ETB 90.82.''';

      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: <Account>[eyosias],
          messageBody: body,
          parsedAccountNumber: '251957063583',
        ),
        same(eyosias),
      );
      expect(
        resolveTransactionOwnership(
          transaction: _transaction(
            'atm-completed',
            accountNumber: '251957063583',
            ownerAccountNumber: eyosias.accountNumber,
          ),
          bank: bank,
          accounts: <Account>[eyosias],
        ),
        same(eyosias),
      );
    });

    test('SIM owner wins over a parsed counterparty without a greeting', () {
      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: accounts,
          messageBody: 'Your transfer was successful.',
          parsedAccountNumber: first.accountNumber,
          sourceSubscriptionId: second.smsSubscriptionId,
        ),
        same(second),
      );
      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: accounts,
          messageBody: 'Your payment was successful.',
          sourceSubscriptionId: -1,
        ),
        isNull,
      );
    });

    test('partitions transactions without double-counting unassigned rows', () {
      final transactions = <Transaction>[
        _transaction('owned-first', ownerAccountNumber: first.accountNumber),
        _transaction('owned-second', ownerAccountNumber: second.accountNumber),
        _transaction('parsed-first', accountNumber: '+251912345678'),
        _transaction(
          'subscription-second',
          sourceSubscriptionId: second.smsSubscriptionId,
        ),
        _transaction('unassigned'),
        _transaction(
          'conflicting',
          accountNumber: first.accountNumber,
          sourceSubscriptionId: second.smsSubscriptionId,
        ),
      ];

      List<Transaction> transactionsFor(Account account) => transactions
          .where(
            (transaction) => transactionBelongsToAccount(
              transaction: transaction,
              account: account,
              bank: bank,
              accounts: accounts,
            ),
          )
          .toList(growable: false);

      final firstTransactions = transactionsFor(first);
      final secondTransactions = transactionsFor(second);
      final firstReferences =
          firstTransactions.map((tx) => tx.reference).toSet();
      final secondReferences =
          secondTransactions.map((tx) => tx.reference).toSet();

      expect(firstReferences, <String>{'owned-first'});
      expect(
        secondReferences,
        <String>{'owned-second', 'subscription-second', 'conflicting'},
      );
      expect(firstReferences.intersection(secondReferences), isEmpty);
      expect(
        firstTransactions.length + secondTransactions.length,
        lessThan(transactions.length),
        reason:
            'Bank activity keeps ambiguous rows without assigning them twice',
      );
    });

    test('keeps evidence-free transactions unmatched with one account', () {
      final transaction = _transaction('legacy-unassigned');

      expect(
        resolveTransactionOwnership(
          transaction: transaction,
          bank: bank,
          accounts: <Account>[first],
        ),
        isNull,
      );
      expect(
        resolveTransactionOwnership(
          transaction: transaction,
          bank: bank,
          accounts: accounts,
        ),
        isNull,
      );
    });

    test('does not use a wallet parsed number as read-time ownership', () {
      final transaction = _transaction(
        'recipient-number-only',
        accountNumber: second.accountNumber,
      );

      expect(
        resolveTransactionOwnership(
          transaction: transaction,
          bank: bank,
          accounts: <Account>[second],
        ),
        isNull,
      );
    });

    test('uses the selected default only for genuinely ambiguous SMS', () {
      final defaultAccount = _account(
        number: '0912345678',
        holder: 'Alice',
        isDefault: true,
      );
      final otherAccount = _account(
        number: '0987654321',
        holder: 'Carol',
      );

      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: <Account>[defaultAccount, otherAccount],
          messageBody: 'Dear Customer, your payment was successful.',
        ),
        same(defaultAccount),
      );
      expect(
        resolveSmsOwnership(
          bank: bank,
          accounts: <Account>[defaultAccount, otherAccount],
          messageBody: 'Dear Bob, your payment was successful.',
        ),
        isNull,
        reason: 'An explicit different owner must not fall back to default',
      );
    });
  });

  group('masked account identity', () {
    final bank = Bank(
      id: 1,
      name: 'Commercial Bank of Ethiopia',
      shortName: 'CBE',
      codes: const <String>['CBE'],
      image: 'assets/images/cbe.png',
      maskPattern: 4,
      uniformMasking: true,
    );
    final first = _account(
      bankId: 1,
      number: '1000001234',
      holder: 'Alice',
    );
    final second = _account(
      bankId: 1,
      number: '2000001234',
      holder: 'Bob',
    );

    test('does not guess when legacy suffix evidence matches two accounts', () {
      expect(
        resolveTransactionOwnership(
          transaction: _transaction(
            'ambiguous-suffix',
            bankId: 1,
            accountNumber: '1234',
          ),
          bank: bank,
          accounts: <Account>[first, second],
        ),
        isNull,
      );
    });

    test('matches a unique three-digit CBE suffix to a longer account', () {
      final runtimeBank = Bank(
        id: 1,
        name: 'Commercial Bank of Ethiopia',
        shortName: 'CBE',
        codes: const <String>['CBE'],
        image: 'assets/images/cbe.png',
        maskPattern: 3,
        uniformMasking: true,
      );
      final account = _account(
        bankId: 1,
        number: '17837',
        holder: 'Eyosias',
      );

      expect(
        resolveTransactionOwnership(
          transaction: _transaction(
            'cbe-secondary',
            bankId: 1,
            accountNumber: '837',
          ),
          bank: runtimeBank,
          accounts: <Account>[account],
        ),
        same(account),
      );
    });

    test('authoritative owner remains exact despite a shared masked suffix',
        () {
      final transaction = _transaction(
        'exact-owner',
        bankId: 1,
        accountNumber: '1234',
        ownerAccountNumber: first.accountNumber,
      );
      final accounts = <Account>[first, second];

      expect(
        resolveTransactionOwnership(
          transaction: transaction,
          bank: bank,
          accounts: accounts,
        ),
        same(first),
      );
      expect(
        transactionBelongsToAccount(
          transaction: transaction,
          account: first,
          bank: bank,
          accounts: accounts,
        ),
        isTrue,
      );
      expect(
        transactionBelongsToAccount(
          transaction: transaction,
          account: second,
          bank: bank,
          accounts: accounts,
        ),
        isFalse,
      );
    });

    test('prefers a Dashen destination account over the sender number', () {
      final dashen = Bank(
        id: 4,
        name: 'Dashen Bank',
        shortName: 'Dashen',
        codes: const <String>['DashenBank'],
        image: 'assets/images/dashen.png',
        maskPattern: 3,
        uniformMasking: true,
      );
      final destination = _account(
        bankId: 4,
        number: '5107635874011',
        holder: 'Eyosias',
      );
      final misleadingSenderSuffix = _account(
        bankId: 4,
        number: '9999999999368',
        holder: 'Another owner',
      );
      const body = '''Dear Customer, You have received ETB 51,450.00 from
telebirr account number 251943685872 Ref No:2603092000308528 on 09/03/2026
at 08:23:58 AM to your bank account '5107**\\****011'. Your account balance
is ETB 51,509.06.''';

      expect(
        resolveSmsOwnership(
          bank: dashen,
          accounts: <Account>[destination, misleadingSenderSuffix],
          messageBody: body,
          parsedAccountNumber: '368',
        ),
        same(destination),
      );
    });

    test('matches changing Dashen masks by their revealed positions', () {
      final dashen = Bank(
        id: 4,
        name: 'Dashen Bank',
        shortName: 'Dashen',
        codes: const <String>['DashenBank', 'Dashen Bank'],
        image: 'assets/images/dashen.png',
        maskPattern: 3,
        uniformMasking: true,
      );
      final destination = _account(
        bankId: 4,
        number: '5107635874011',
        holder: 'Eyosias',
      );
      const oldMaskBody = '''Dear Customer, your account '5107********1' is
debited with ETB 1,000.00 on 27/11/2023. Your current balance is ETB 991.00.''';

      expect(
        accountNumbersMatch(dashen, '5107********1', destination.accountNumber),
        isTrue,
      );
      expect(
        accountNumbersMatch(dashen, '5107********1', '5107**011'),
        isTrue,
        reason: 'Different generations of a bank mask can still be compatible',
      );
      expect(
        resolveSmsOwnership(
          bank: dashen,
          accounts: <Account>[destination],
          messageBody: oldMaskBody,
          parsedAccountNumber: '**1',
        ),
        same(destination),
      );
    });

    test('does not guess when an older prefix mask fits two accounts', () {
      final dashen = Bank(
        id: 4,
        name: 'Dashen Bank',
        shortName: 'Dashen',
        codes: const <String>['Dashen Bank'],
        image: 'assets/images/dashen.png',
        maskPattern: 3,
        uniformMasking: true,
      );
      final first = _account(
        bankId: 4,
        number: '5107635874011',
        holder: 'Eyosias',
      );
      final second = _account(
        bankId: 4,
        number: '5107999999991',
        holder: 'Another owner',
      );
      const body = '''Dear Customer, your account '5107********1' is debited
with ETB 1,000.00 on 27/11/2023. Your current balance is ETB 991.00.''';

      expect(
        resolveSmsOwnership(
          bank: dashen,
          accounts: <Account>[first, second],
          messageBody: body,
          parsedAccountNumber: '**1',
        ),
        isNull,
      );
    });
  });
}

Bank _telebirrBank() {
  return Bank(
    id: 6,
    name: 'Telebirr',
    shortName: 'Telebirr',
    codes: const <String>['127'],
    image: 'assets/images/telebirr.png',
    maskPattern: 0,
    uniformMasking: false,
    simBased: true,
  );
}

Account _account({
  int bankId = 6,
  required String number,
  required String holder,
  int? subscriptionId,
  bool isDefault = false,
}) {
  return Account(
    accountNumber: number,
    bank: bankId,
    balance: 0,
    accountHolderName: holder,
    smsSubscriptionId: subscriptionId,
    isDefault: isDefault,
  );
}

Transaction _transaction(
  String reference, {
  int bankId = 6,
  String? accountNumber,
  String? ownerAccountNumber,
  int? sourceSubscriptionId,
}) {
  return Transaction(
    amount: 10,
    reference: reference,
    bankId: bankId,
    type: 'DEBIT',
    accountNumber: accountNumber,
    ownerAccountNumber: ownerAccountNumber,
    sourceSubscriptionId: sourceSubscriptionId,
  );
}
