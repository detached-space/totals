import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:totals/database/database_helper.dart';

import 'database_fixture.dart';

const _schemaVersion = 33;

void main() {
  late Directory tempDirectory;
  late String databasePath;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDirectory = await Directory.systemTemp.createTemp(
      'totals_database_migration_test_',
    );
    databasePath =
        '${tempDirectory.path}${Platform.pathSeparator}totals_test.db';
  });

  tearDown(() async {
    await databaseFactoryFfi.deleteDatabase(databasePath);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('fresh database creates a healthy v33 schema and reopens cleanly',
      () async {
    int? categoryCount;

    for (var pass = 0; pass < 2; pass++) {
      await _withDatabase(databasePath, (db) async {
        await _expectHealthyV33(db);
        final count = (await db.rawQuery(
          'SELECT COUNT(*) AS count FROM categories',
        ))
            .single['count'] as int;
        categoryCount ??= count;
        expect(count, categoryCount);
      });
    }
  });

  test('exact v4 schema upgrades to v33 without losing sentinel data',
      () async {
    await DatabaseFixture.createV4(databaseFactoryFfi, databasePath);

    for (var pass = 0; pass < 2; pass++) {
      await _withDatabase(databasePath, (db) async {
        await _expectHealthyV33(db);

        final transaction = (await db.query(
          'transactions',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.legacyTransactionId],
        ))
            .single;
        expect(transaction['reference'], 'legacy-v4-reference');
        expect(transaction['amount'], 123.45);
        expect(transaction['receiver'], 'Legacy receiver');
        expect(transaction['year'], 2025);
        expect(transaction['month'], 12);
        expect(transaction['day'], 14);
        expect(transaction['week'], 2);
        expect(transaction['profileId'], isNotNull);

        final account = (await db.query(
          'accounts',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.legacyAccountId],
        ))
            .single;
        expect(account['accountNumber'], '000401');
        expect(account['balance'], 765.43);
        expect(account['profileId'], transaction['profileId']);

        final failedParse = (await db.query(
          'failed_parses',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.legacyFailedParseId],
        ))
            .single;
        expect(failedParse['body'], 'legacy message body');

        final smsPattern = (await db.query(
          'sms_patterns',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.legacySmsPatternId],
        ))
            .single;
        expect(smsPattern['senderId'], 'LEGACY-BANK');
        expect(smsPattern['description'], 'legacy pattern');
      });
    }
  });

  test(
      'v27 renamed built-in and custom canonical name keep separate identities',
      () async {
    await _withDatabase(databasePath, (db) async {
      await DatabaseFixture.addRenamedBuiltInCollision(db);
      await db.setVersion(27);
    });

    for (var pass = 0; pass < 2; pass++) {
      await _withDatabase(databasePath, (db) async {
        await _expectHealthyV33(db);

        final renamed = (await db.query(
          'categories',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.renamedBuiltInId],
        ))
            .single;
        expect(renamed['name'], 'My repayment');
        expect(renamed['builtInKey'], 'income_repayment');
        expect(renamed['builtIn'], 1);

        final custom = (await db.query(
          'categories',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.customCanonicalId],
        ))
            .single;
        expect(custom['name'], 'Repayment');
        expect(custom['flow'], 'income');
        expect(custom['builtInKey'], isNull);
        expect(custom['builtIn'], 0);

        final keyOwners = (await db.rawQuery(
          'SELECT COUNT(*) AS count FROM categories WHERE builtInKey = ?',
          ['income_repayment'],
        ))
            .single['count'] as int;
        expect(keyOwners, 1);
      });
    }
  });

  test('v27 legacy Gifts row does not steal an existing built-in key',
      () async {
    await _withDatabase(databasePath, (db) async {
      await DatabaseFixture.addLegacyGiftCollision(db);
      await db.setVersion(27);
    });

    for (var pass = 0; pass < 2; pass++) {
      await _withDatabase(databasePath, (db) async {
        await _expectHealthyV33(db);

        final renamed = (await db.query(
          'categories',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.renamedGiftId],
        ))
            .single;
        expect(renamed['name'], 'Presents');
        expect(renamed['builtInKey'], 'expense_gifts_given');
        expect(renamed['builtIn'], 1);

        final legacy = (await db.query(
          'categories',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.legacyGiftId],
        ))
            .single;
        expect(legacy['name'], 'Gifts');
        expect(legacy['builtInKey'], isNull);
        expect(legacy['builtIn'], 0);
      });
    }
  });

  test('v20 auto-categorization rows and receiver mappings survive', () async {
    await _withDatabase(databasePath, (db) async {
      await DatabaseFixture.replaceWithV20AutoCategorizationShape(db);
    });

    for (var pass = 0; pass < 2; pass++) {
      await _withDatabase(databasePath, (db) async {
        await _expectHealthyV33(db);

        final legacyRule = (await db.query(
          'auto_category_rules',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.legacyAutoRuleId],
        ))
            .single;
        expect(legacyRule['normalizedCounterparty'], 'legacy grocer');
        expect(legacyRule['isPrimary'], 1);

        final mappedRules = await db.query(
          'auto_category_rules',
          where: 'normalizedCounterparty = ? AND flow = ?',
          whereArgs: ['mapped merchant', 'expense'],
        );
        expect(mappedRules, hasLength(1));
        expect(mappedRules.single['isPrimary'], 1);
      });
    }
  });

  test('v25 loan and repayment rows survive the pair-uniqueness migration',
      () async {
    await _withDatabase(databasePath, (db) async {
      await DatabaseFixture.replaceWithV25LoanShape(db);
    });

    for (var pass = 0; pass < 2; pass++) {
      await _withDatabase(databasePath, (db) async {
        await _expectHealthyV33(db);

        final entry = (await db.query(
          'loan_debt_entries',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.legacyLoanEntryId],
        ))
            .single;
        expect(entry['transactionReference'], 'legacy-loan-reference');
        expect(entry['personName'], 'Legacy borrower');
        expect(entry['source'], 'transaction');
        expect(entry['returnDate'], isNull);

        final repayment = (await db.query(
          'loan_debt_repayments',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.legacyRepaymentId],
        ))
            .single;
        expect(repayment['appliedAmount'], 25.0);

        if (pass == 0) {
          await db.insert('loan_debt_repayments', {
            'repaymentTransactionReference': 'legacy-repayment-reference',
            'loanDebtTransactionReference': 'second-loan-reference',
            'appliedAmount': 5.0,
            'createdAt': '2026-06-14T12:00:00.000',
            'updatedAt': '2026-06-14T12:00:00.000',
          });
        } else {
          final splitRows = await db.query(
            'loan_debt_repayments',
            where: 'repaymentTransactionReference = ?',
            whereArgs: ['legacy-repayment-reference'],
          );
          expect(splitRows, hasLength(2));
        }
      });
    }
  });

  for (final sourceVersion in <int>[26, 27]) {
    test(
        'v$sourceVersion database missing source and schedule shapes upgrades idempotently',
        () async {
      await _withDatabase(databasePath, (db) async {
        await DatabaseFixture.removeV27SourceAndScheduleShape(
          db,
          version: sourceVersion,
        );
      });

      for (var pass = 0; pass < 2; pass++) {
        await _withDatabase(databasePath, (db) async {
          await _expectHealthyV33(db);

          final transaction = (await db.query(
            'transactions',
            where: 'id = ?',
            whereArgs: [DatabaseFixture.syncTransactionId],
          ))
              .single;
          expect(transaction['reference'], 'sync-shape-v$sourceVersion');
          expect(transaction['amount'], 26.27);
          expect(transaction['sourceType'], isNull);

          final rule = (await db.query(
            'sync_rules',
            where: 'id = ?',
            whereArgs: [DatabaseFixture.syncRuleId],
          ))
              .single;
          expect(rule['name'], 'Legacy transaction rule');
          expect(rule['entity'], 'transactions');
          expect(rule['scheduleMode'], 'off');

          final outbox = (await db.query(
            'sync_outbox',
            where: 'id = ?',
            whereArgs: [DatabaseFixture.syncOutboxId],
          ))
              .single;
          expect(outbox['entityRef'], 'sync-shape-v$sourceVersion');
          expect(outbox['status'], 'pending');
        });
      }
    });
  }

  test('exact v28 schema upgrades through v33 idempotently', () async {
    await _withDatabase(databasePath, (db) async {
      await DatabaseFixture.replaceV29OwnershipShapeWithV28(db);
    });

    for (var pass = 0; pass < 2; pass++) {
      await _withDatabase(databasePath, (db) async {
        await _expectHealthyV33(db);

        final transaction = (await db.query(
          'transactions',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.v28OwnershipTransactionId],
        ))
            .single;
        expect(transaction['reference'], 'v28-ownership-sentinel');
        expect(transaction['amount'], 29.28);
        expect(transaction['accountNumber'], '251911223344');
        expect(transaction['ownerAccountNumber'], isNull);
        expect(transaction['sourceSubscriptionId'], isNull);
        expect(transaction['ownerAssignmentSource'], isNull);

        final account = (await db.query(
          'accounts',
          where: 'id = ?',
          whereArgs: [DatabaseFixture.v28OwnershipAccountId],
        ))
            .single;
        expect(account['accountNumber'], '0911223344');
        expect(account['accountHolderName'], 'V28 owner');
        expect(account['smsSubscriptionId'], isNull);
        expect(account['includeInTotals'], 1);
        expect(account['isDormant'], 0);
        expect(account['isDefault'], 1);
      });
    }
  });

  test(
      'v31 custom Reimbursement survives while the stable built-in is restored',
      () async {
    await _withDatabase(databasePath, (db) async {
      await db.delete(
        'categories',
        where: 'builtInKey = ?',
        whereArgs: ['income_reimbursement'],
      );
      await db.insert('categories', {
        'name': 'Reimbursement',
        'essential': 0,
        'uncategorized': 0,
        'iconKey': 'wallet',
        'description': 'A user-created category',
        'flow': 'income',
        'recurring': 0,
        'builtIn': 0,
        'builtInKey': null,
      });
      await db.execute(
        'DROP TRIGGER IF EXISTS trg_reimbursement_allocations_tx_delete',
      );
      await db.execute('DROP TABLE reimbursement_allocations');
      await db.setVersion(31);
    });

    for (var pass = 0; pass < 2; pass++) {
      await _withDatabase(databasePath, (db) async {
        await _expectHealthyV33(db);

        final custom = (await db.query(
          'categories',
          where: 'name = ? AND flow = ?',
          whereArgs: ['Reimbursement', 'income'],
        ))
            .single;
        expect(custom['builtIn'], 0);
        expect(custom['builtInKey'], isNull);

        final builtIn = (await db.query(
          'categories',
          where: 'builtInKey = ?',
          whereArgs: ['income_reimbursement'],
        ))
            .single;
        expect(builtIn['name'], 'Reimbursement (Totals)');
        expect(builtIn['flow'], 'income');
        expect(builtIn['builtIn'], 1);
      });
    }
  });

  test('v32 database adds durable transaction source SMS storage', () async {
    await _withDatabase(databasePath, (db) async {
      await db.execute(
        'DROP TRIGGER IF EXISTS trg_transaction_source_sms_tx_delete',
      );
      await db.execute('DROP TABLE transaction_source_sms');
      await db.setVersion(32);
    });

    await _withDatabase(databasePath, (db) async {
      await _expectHealthyV33(db);
      await db.insert('transactions', {
        'amount': 25,
        'reference': 'source-sms-migration',
      });
      await db.insert('transaction_source_sms', {
        'transactionReference': 'source-sms-migration',
        'body': 'Original bank message',
        'senderAddress': 'BANK',
      });

      await db.delete(
        'transactions',
        where: 'reference = ?',
        whereArgs: ['source-sms-migration'],
      );

      expect(await db.query('transaction_source_sms'), isEmpty);
    });
  });
}

Future<T> _withDatabase<T>(
  String path,
  Future<T> Function(Database db) callback,
) async {
  final helper = DatabaseHelper.forTesting(
    path: path,
    databaseFactory: databaseFactoryFfi,
  );
  final db = await helper.database;
  try {
    return await callback(db);
  } finally {
    if (db.isOpen) {
      await db.close();
    }
  }
}

Future<void> _expectHealthyV33(Database db) async {
  expect(await db.getVersion(), _schemaVersion);

  final integrity = await db.rawQuery('PRAGMA integrity_check');
  expect(integrity.single.values.single, 'ok');
  expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

  final tableRows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  final tables = tableRows.map((row) => row['name'] as String).toSet();
  expect(
    tables,
    containsAll(<String>{
      'categories',
      'transactions',
      'failed_parses',
      'sms_patterns',
      'banks',
      'accounts',
      'profiles',
      'budgets',
      'receiver_category_mappings',
      'auto_category_rules',
      'auto_category_prompt_dismissals',
      'user_accounts',
      'loan_debt_entries',
      'loan_debt_repayments',
      'reimbursement_allocations',
      'transaction_source_sms',
      'sync_destinations',
      'sync_rules',
      'sync_outbox',
      'sync_runtime_locks',
    }),
  );

  expect(
    await _columnNames(db, 'transactions'),
    containsAll(<String>{
      'note',
      'serviceCharge',
      'vat',
      'categoryIds',
      'profileId',
      'sourceType',
      'sourceMessageId',
      'sourceFingerprint',
      'ownerAccountNumber',
      'sourceSubscriptionId',
      'ownerAssignmentSource',
    }),
  );
  expect(
    await _columnNames(db, 'accounts'),
    containsAll(<String>{
      'smsSubscriptionId',
      'includeInTotals',
      'isDormant',
      'isDefault',
    }),
  );
  expect(
    await _columnNames(db, 'categories'),
    containsAll(<String>{
      'uncategorized',
      'flow',
      'recurring',
      'builtIn',
      'builtInKey',
    }),
  );
  expect(
    await _columnNames(db, 'sync_rules'),
    containsAll(<String>{
      'scheduleMode',
      'scheduleIntervalMinutes',
      'scheduleTimes',
      'lastScheduledAt',
    }),
  );

  expect(
    await _indexNames(db, 'transactions'),
    containsAll(<String>{
      'idx_transactions_ownerAccount',
      'idx_transactions_sourceSubscriptionId',
    }),
  );
  expect(
    await _indexNames(db, 'accounts'),
    containsAll(<String>{
      'idx_accounts_smsSubscriptionId',
      'idx_accounts_one_default_per_bank',
    }),
  );
  expect(
    await _columnNames(db, 'reimbursement_allocations'),
    containsAll(<String>{
      'id',
      'reimbursementTransactionReference',
      'expenseTransactionReference',
      'appliedAmount',
      'createdAt',
      'updatedAt',
    }),
  );
  expect(
    await _indexNames(db, 'reimbursement_allocations'),
    containsAll(<String>{
      'idx_reimbursement_allocations_reimbursement',
      'idx_reimbursement_allocations_expense',
      'idx_reimbursement_allocations_pair',
    }),
  );
  expect(
    await _columnNames(db, 'transaction_source_sms'),
    containsAll(<String>{
      'transactionReference',
      'body',
      'senderAddress',
      'receivedAt',
      'messageId',
    }),
  );

  final reimbursementCategories = await db.query(
    'categories',
    where: 'builtInKey = ?',
    whereArgs: ['income_reimbursement'],
  );
  expect(reimbursementCategories, hasLength(1));
  expect(reimbursementCategories.single['flow'], 'income');
  expect(reimbursementCategories.single['builtIn'], 1);

  final refundCategories = await db.query(
    'categories',
    where: 'builtInKey = ?',
    whereArgs: ['income_refund'],
  );
  expect(refundCategories, hasLength(1));
  expect(
    refundCategories.single['description'],
    'Money returned by a merchant for a purchase',
  );

  final reimbursementTriggers = await db.rawQuery('''
    SELECT name
    FROM sqlite_master
    WHERE type = 'trigger'
      AND name = 'trg_reimbursement_allocations_tx_delete'
  ''');
  expect(reimbursementTriggers, hasLength(1));

  final sourceSmsTriggers = await db.rawQuery('''
    SELECT name
    FROM sqlite_master
    WHERE type = 'trigger'
      AND name = 'trg_transaction_source_sms_tx_delete'
  ''');
  expect(sourceSmsTriggers, hasLength(1));

  final duplicateBuiltInKeys = await db.rawQuery('''
    SELECT builtInKey
    FROM categories
    WHERE builtInKey IS NOT NULL AND TRIM(builtInKey) <> ''
    GROUP BY builtInKey
    HAVING COUNT(*) > 1
  ''');
  expect(duplicateBuiltInKeys, isEmpty);

  final duplicateNames = await db.rawQuery('''
    SELECT LOWER(TRIM(name)) AS normalizedName, LOWER(TRIM(flow)) AS normalizedFlow
    FROM categories
    GROUP BY normalizedName, normalizedFlow
    HAVING COUNT(*) > 1
  ''');
  expect(duplicateNames, isEmpty);

  final temporaryTables = await db.rawQuery('''
    SELECT name
    FROM sqlite_master
    WHERE type = 'table'
      AND (name LIKE '%_legacy' OR name LIKE '%_new')
  ''');
  expect(temporaryTables, isEmpty);
}

Future<Set<String>> _columnNames(Database db, String table) async {
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  return columns.map((column) => column['name'] as String).toSet();
}

Future<Set<String>> _indexNames(Database db, String table) async {
  final indexes = await db.rawQuery('PRAGMA index_list($table)');
  return indexes.map((index) => index['name'] as String).toSet();
}
