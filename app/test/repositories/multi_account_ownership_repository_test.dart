import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/transaction.dart' as models;
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';
import 'package:totals/utils/sms_transaction_source.dart';

const _telebirrBankId = 6;
const _firstAccountNumber = '0911223344';
const _secondAccountNumber = '0922334455';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late String databasePath;

  setUpAll(() {
    dotenv.loadFromString(
      envString: 'SHARED_EXPENSES_URL=https://example.invalid',
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DataSyncSettingsService.cachedEnabled = false;

    await DatabaseHelper.instance.close();
    databasePath = '${await databaseFactoryFfi.getDatabasesPath()}/totals.db';
    await databaseFactoryFfi.deleteDatabase(databasePath);
    db = await DatabaseHelper.instance.database;

    // Keep BankConfigService on its local/read-only path during repository
    // deletion. It may enrich this row from the bundled asset, but never needs
    // a network request.
    await db.insert('banks', <String, Object?>{
      'id': _telebirrBankId,
      'name': 'Telebirr',
      'shortName': 'Telebirr',
      'codes': '["127"]',
      'image': 'assets/images/telebirr.png',
      'maskPattern': 0,
      'uniformMasking': 0,
      'simBased': 1,
      'colors': '["#1d38e5", "#90d5ee"]',
    });
  });

  tearDown(() async {
    if (db.isOpen) {
      await DatabaseHelper.instance.close();
    }
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test(
    'deleting one of two Telebirr accounts removes only its transactions',
    () async {
      final accountRepository = AccountRepository();
      final transactionRepository = TransactionRepository();

      await accountRepository.saveAccount(_account(
        number: _firstAccountNumber,
        name: 'First Owner',
      ));
      await accountRepository.saveAccount(_account(
        number: _secondAccountNumber,
        name: 'Second Owner',
      ));

      await transactionRepository.saveTransaction(
        _transaction(
          reference: 'owned-by-first',
          ownerAccountNumber: _firstAccountNumber,
          // Parsed SMS evidence may describe a counterparty. The durable owner
          // must take precedence when the account is deleted.
          parsedAccountNumber: _secondAccountNumber,
        ),
        skipAutoCategorization: true,
      );
      await transactionRepository.saveTransaction(
        _transaction(
          reference: 'owned-by-second',
          ownerAccountNumber: _secondAccountNumber,
        ),
        skipAutoCategorization: true,
      );
      await transactionRepository.saveTransaction(
        _transaction(
          reference: 'unassigned',
          parsedAccountNumber: '0933445566',
        ),
        skipAutoCategorization: true,
      );

      await accountRepository.deleteAccount(
        _firstAccountNumber,
        _telebirrBankId,
      );

      final remainingReferences = (await db.query(
        'transactions',
        columns: <String>['reference'],
        orderBy: 'reference',
      ))
          .map((row) => row['reference'])
          .toList(growable: false);
      expect(
        remainingReferences,
        <String>['owned-by-second', 'unassigned'],
      );

      final remainingTelebirrAccounts = await db.query(
        'accounts',
        columns: <String>['accountNumber'],
        where: 'bank = ?',
        whereArgs: <Object?>[_telebirrBankId],
      );
      expect(remainingTelebirrAccounts, hasLength(1));
      expect(
        remainingTelebirrAccounts.single['accountNumber'],
        _secondAccountNumber,
      );
    },
  );

  test('deleting the final account also removes Other transactions', () async {
    final accountRepository = AccountRepository();
    final transactionRepository = TransactionRepository();
    await accountRepository.saveAccount(_account(
      number: _firstAccountNumber,
      name: 'Only Owner',
    ));
    await transactionRepository.saveTransaction(
      _transaction(
        reference: 'owned-by-only-account',
        ownerAccountNumber: _firstAccountNumber,
      ),
      skipAutoCategorization: true,
    );
    await transactionRepository.saveTransaction(
      _transaction(
        reference: 'unmatched-after-final-delete',
        parsedAccountNumber: '0999999999',
      ),
      skipAutoCategorization: true,
    );

    await accountRepository.deleteAccount(
      _firstAccountNumber,
      _telebirrBankId,
    );

    expect(
      await db.query(
        'transactions',
        where: 'bankId = ?',
        whereArgs: <Object?>[_telebirrBankId],
      ),
      isEmpty,
    );
    expect(
      await db.query(
        'accounts',
        where: 'bank = ?',
        whereArgs: <Object?>[_telebirrBankId],
      ),
      isEmpty,
    );
  });

  test('account updates preserve row id and learned SIM subscription',
      () async {
    final repository = AccountRepository();
    await repository.saveAccount(_account(
      number: _firstAccountNumber,
      name: 'Original Owner',
      balance: 100,
      smsSubscriptionId: 2,
    ));

    final before = (await db.query(
      'accounts',
      where: 'accountNumber = ? AND bank = ?',
      whereArgs: <Object?>[_firstAccountNumber, _telebirrBankId],
    ))
        .single;

    await repository.saveAccount(_account(
      number: _firstAccountNumber,
      name: 'Updated Owner',
      balance: 275,
    ));

    final afterRows = await db.query(
      'accounts',
      where: 'accountNumber = ? AND bank = ?',
      whereArgs: <Object?>[_firstAccountNumber, _telebirrBankId],
    );
    expect(afterRows, hasLength(1));
    final after = afterRows.single;
    expect(after['id'], before['id']);
    expect(after['accountHolderName'], 'Updated Owner');
    expect(after['balance'], 275.0);
    expect(after['smsSubscriptionId'], 2);

    final loaded = (await repository.getAccounts())
        .where((account) => account.bank == _telebirrBankId)
        .single;
    expect(loaded.smsSubscriptionId, 2);
  });

  test('first account stays default until the user changes it', () async {
    final repository = AccountRepository();
    await repository.saveAccount(_account(
      number: _firstAccountNumber,
      name: 'First Owner',
    ));
    await repository.saveAccount(_account(
      number: _secondAccountNumber,
      name: 'Second Owner',
    ));

    var accounts = (await repository.getAccounts())
        .where((account) => account.bank == _telebirrBankId)
        .toList(growable: false);
    expect(
      accounts.singleWhere((account) => account.isDefault).accountNumber,
      _firstAccountNumber,
    );

    expect(
      await repository.setDefaultAccount(
        accountNumber: _secondAccountNumber,
        bank: _telebirrBankId,
      ),
      isTrue,
    );
    accounts = (await repository.getAccounts())
        .where((account) => account.bank == _telebirrBankId)
        .toList(growable: false);
    expect(
      accounts.singleWhere((account) => account.isDefault).accountNumber,
      _secondAccountNumber,
    );
  });

  test('transaction repository round-trips durable owner and local SIM id',
      () async {
    final repository = TransactionRepository();
    await repository.saveTransaction(
      _transaction(
        reference: 'ownership-round-trip',
        ownerAccountNumber: _firstAccountNumber,
        parsedAccountNumber: '3344',
        sourceSubscriptionId: 2,
      ),
      skipAutoCategorization: true,
    );

    final loaded =
        await repository.getTransactionByReference('ownership-round-trip');
    expect(loaded, isNotNull);
    expect(loaded!.ownerAccountNumber, _firstAccountNumber);
    expect(loaded.accountNumber, '3344');
    expect(loaded.sourceSubscriptionId, 2);

    final row = (await db.query(
      'transactions',
      where: 'reference = ?',
      whereArgs: <Object?>['ownership-round-trip'],
    ))
        .single;
    expect(row['ownerAccountNumber'], _firstAccountNumber);
    expect(row['sourceSubscriptionId'], 2);
  });

  test('automatic reconciliation cannot overwrite a manual owner', () async {
    final repository = TransactionRepository();
    await repository.saveTransaction(
      _transaction(
        reference: 'manual-owner',
        ownerAccountNumber: _firstAccountNumber,
        ownerAssignmentSource: models.Transaction.manualOwnerAssignment,
      ),
      skipAutoCategorization: true,
    );

    final changed = await repository.updateTransactionOwnership(
      reference: 'manual-owner',
      ownerAccountNumber: _secondAccountNumber,
      ownerAssignmentSource: models.Transaction.automaticOwnerAssignment,
    );

    expect(changed, isFalse);
    final loaded = await repository.getTransactionByReference('manual-owner');
    expect(loaded?.ownerAccountNumber, _firstAccountNumber);
    expect(
      loaded?.ownerAssignmentSource,
      models.Transaction.manualOwnerAssignment,
    );
  });

  test('bulk manual assignment updates rows without creating duplicates',
      () async {
    final repository = TransactionRepository();
    await repository.saveTransaction(
      _transaction(reference: 'bulk-owner-one'),
      skipAutoCategorization: true,
    );
    await repository.saveTransaction(
      _transaction(reference: 'bulk-owner-two'),
      skipAutoCategorization: true,
    );
    final before = await repository.getTransactions();

    final changed = await repository.updateTransactionOwnerships(const [
      TransactionOwnershipUpdate(
        reference: 'bulk-owner-one',
        ownerAccountNumber: _firstAccountNumber,
        ownerAssignmentSource: models.Transaction.manualOwnerAssignment,
      ),
      TransactionOwnershipUpdate(
        reference: 'bulk-owner-two',
        ownerAccountNumber: _firstAccountNumber,
        ownerAssignmentSource: models.Transaction.manualOwnerAssignment,
      ),
    ]);

    final after = await repository.getTransactions();
    expect(changed, 2);
    expect(after, hasLength(before.length));
    expect(
      after.map((transaction) => transaction.reference).toSet(),
      before.map((transaction) => transaction.reference).toSet(),
    );
    expect(
      after.every(
        (transaction) =>
            transaction.ownerAccountNumber == _firstAccountNumber &&
            transaction.ownerAssignmentSource ==
                models.Transaction.manualOwnerAssignment,
      ),
      isTrue,
    );
  });

  test('ownership reconciliation can clear a disproven owner and SIM shortcut',
      () async {
    final repository = TransactionRepository();
    await repository.saveTransaction(
      _transaction(
        reference: 'wrong-owner',
        ownerAccountNumber: _secondAccountNumber,
        parsedAccountNumber: _secondAccountNumber,
        sourceSubscriptionId: 2,
      ),
      skipAutoCategorization: true,
    );

    final changed = await repository.updateTransactionOwnerships(const [
      TransactionOwnershipUpdate(
        reference: 'wrong-owner',
        ownerAccountNumber: null,
      ),
    ]);

    expect(changed, 1);
    final loaded = await repository.getTransactionByReference('wrong-owner');
    expect(loaded, isNotNull);
    expect(loaded!.ownerAccountNumber, isNull);
    expect(loaded.sourceSubscriptionId, isNull);
  });

  test(
    'provider exposes the same durable account partition to details and filters',
    () async {
      final accountRepository = AccountRepository();
      final transactionRepository = TransactionRepository();
      await accountRepository.saveAccount(_account(
        number: _firstAccountNumber,
        name: 'Kidist',
      ));
      await accountRepository.saveAccount(_account(
        number: _secondAccountNumber,
        name: 'Eyosias',
      ));

      await transactionRepository.saveTransaction(
        _transaction(
          reference: 'kidist-outgoing',
          ownerAccountNumber: _firstAccountNumber,
          parsedAccountNumber: _secondAccountNumber,
        ),
        skipAutoCategorization: true,
      );
      await transactionRepository.saveTransaction(
        _transaction(
          reference: 'eyosias-outgoing',
          ownerAccountNumber: _secondAccountNumber,
        ),
        skipAutoCategorization: true,
      );
      await transactionRepository.saveTransaction(
        _transaction(
          reference: 'other-transaction',
          parsedAccountNumber: '0933445566',
        ),
        skipAutoCategorization: true,
      );

      final provider = TransactionProvider();
      await provider.loadData();
      addTearDown(provider.dispose);

      final byReference = <String, models.Transaction>{
        for (final transaction in provider.allTransactions)
          transaction.reference: transaction,
      };
      final kidistTransaction = byReference['kidist-outgoing']!;
      expect(
        provider.accountSummaryForTransaction(kidistTransaction)?.accountNumber,
        _firstAccountNumber,
      );
      expect(
        provider
            .accountSummaryForTransaction(
              kidistTransaction.copyWith(note: 'edited copy'),
            )
            ?.accountNumber,
        _firstAccountNumber,
      );
      expect(
        provider
            .transactionsForAccount(_telebirrBankId, _firstAccountNumber)
            .map((transaction) => transaction.reference),
        contains('kidist-outgoing'),
      );
      expect(
        provider
            .transactionsForAccount(_telebirrBankId, _secondAccountNumber)
            .map((transaction) => transaction.reference),
        contains('eyosias-outgoing'),
      );
      expect(
        provider
            .unmatchedTransactionsForBank(_telebirrBankId)
            .map((transaction) => transaction.reference),
        contains('other-transaction'),
      );
      expect(
        provider
            .accountSummaryForTransaction(byReference['other-transaction']!),
        isNull,
      );
    },
  );

  test(
      'paired Telebirr ledger legs survive unique-reference storage and delete',
      () async {
    final accountRepository = AccountRepository();
    final transactionRepository = TransactionRepository();
    await accountRepository.saveAccount(_account(
      number: _firstAccountNumber,
      name: 'Kidist',
    ));
    await accountRepository.saveAccount(_account(
      number: _secondAccountNumber,
      name: 'Eyosias',
    ));

    final kidistSource = SmsTransactionSource.fromParts(
      bankId: _telebirrBankId,
      messageId: 12248,
      senderAddress: '127',
      body: 'Dear KIDIST You transferred ETB 50 to EYOSIAS.',
    );
    final eyosiasSource = SmsTransactionSource.fromParts(
      bankId: _telebirrBankId,
      messageId: 12249,
      senderAddress: '127',
      body: 'Dear EYOSIAS You received ETB 50 from KIDIST.',
    );
    final debitReference = kidistSource.scopeReference(
      bankId: _telebirrBankId,
      reference: 'DA99NXARVP',
      transactionType: 'DEBIT',
    )!;
    final creditReference = eyosiasSource.scopeReference(
      bankId: _telebirrBankId,
      reference: 'DA99NXARVP',
      transactionType: 'CREDIT',
    )!;

    await transactionRepository.saveTransaction(
      _transaction(
        reference: debitReference,
        ownerAccountNumber: _firstAccountNumber,
      ),
      skipAutoCategorization: true,
    );
    await transactionRepository.saveTransaction(
      models.Transaction(
        amount: 50,
        reference: creditReference,
        time: '2026-07-12T10:00:01.000',
        bankId: _telebirrBankId,
        type: 'CREDIT',
        ownerAccountNumber: _secondAccountNumber,
        sourceType: 'sms',
        sourceMessageId: eyosiasSource.sourceMessageId,
        sourceFingerprint: eyosiasSource.sourceFingerprint,
      ),
      skipAutoCategorization: true,
    );

    final paired = await transactionRepository.getTransactions();
    expect(paired, hasLength(2));
    expect(paired.map((transaction) => transaction.displayReference).toSet(),
        <String>{'DA99NXARVP'});
    expect(paired.map((transaction) => transaction.type).toSet(),
        <String?>{'DEBIT', 'CREDIT'});

    await accountRepository.deleteAccount(
      _firstAccountNumber,
      _telebirrBankId,
    );
    final remaining = await transactionRepository.getTransactions();
    expect(remaining, hasLength(1));
    expect(remaining.single.type, 'CREDIT');
    expect(remaining.single.ownerAccountNumber, _secondAccountNumber);
  });
}

Account _account({
  required String number,
  required String name,
  double balance = 0,
  int? smsSubscriptionId,
}) {
  return Account(
    accountNumber: number,
    bank: _telebirrBankId,
    balance: balance,
    accountHolderName: name,
    smsSubscriptionId: smsSubscriptionId,
  );
}

models.Transaction _transaction({
  required String reference,
  String? ownerAccountNumber,
  String? ownerAssignmentSource,
  String? parsedAccountNumber,
  int? sourceSubscriptionId,
}) {
  return models.Transaction(
    amount: 25,
    reference: reference,
    time: '2026-07-12T10:00:00.000',
    bankId: _telebirrBankId,
    type: 'DEBIT',
    accountNumber: parsedAccountNumber,
    ownerAccountNumber: ownerAccountNumber,
    ownerAssignmentSource: ownerAssignmentSource,
    sourceType: 'sms',
    sourceMessageId: 'sms-$reference',
    sourceFingerprint: 'fingerprint-$reference',
    sourceSubscriptionId: sourceSubscriptionId,
  );
}
