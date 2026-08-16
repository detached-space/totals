import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseFixture {
  static const legacyTransactionId = 401;
  static const legacyAccountId = 402;
  static const legacyFailedParseId = 403;
  static const legacySmsPatternId = 404;

  static const syncTransactionId = 2601;
  static const syncDestinationId = 2602;
  static const syncRuleId = 2603;
  static const syncOutboxId = 2604;

  static const v28OwnershipTransactionId = 2901;
  static const v28OwnershipAccountId = 2902;

  static const legacyAutoRuleId = 2001;
  static const legacyReceiverMappingId = 2002;

  static const legacyLoanEntryId = 2501;
  static const legacyRepaymentId = 2502;

  static const renamedBuiltInId = 2801;
  static const customCanonicalId = 2802;
  static const renamedGiftId = 2803;
  static const legacyGiftId = 2804;

  static Future<void> createV4(
    DatabaseFactory factory,
    String path,
  ) async {
    await factory.deleteDatabase(path);
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await db.execute('''
        CREATE TABLE transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL NOT NULL,
          reference TEXT NOT NULL UNIQUE,
          creditor TEXT,
          receiver TEXT,
          time TEXT,
          status TEXT,
          currentBalance TEXT,
          bankId INTEGER,
          type TEXT,
          transactionLink TEXT,
          accountNumber TEXT,
          year INTEGER,
          month INTEGER,
          day INTEGER,
          week INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE failed_parses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          address TEXT NOT NULL,
          body TEXT NOT NULL,
          reason TEXT NOT NULL,
          timestamp TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE sms_patterns (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bankId INTEGER NOT NULL,
          senderId TEXT NOT NULL,
          regex TEXT NOT NULL,
          type TEXT NOT NULL,
          description TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE accounts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          accountNumber TEXT NOT NULL,
          bank INTEGER NOT NULL,
          balance REAL NOT NULL DEFAULT 0,
          accountHolderName TEXT NOT NULL,
          settledBalance REAL,
          pendingCredit REAL,
          UNIQUE(accountNumber, bank)
        )
      ''');

      await db.execute(
        'CREATE INDEX idx_transactions_reference ON transactions(reference)',
      );
      await db.execute(
        'CREATE INDEX idx_transactions_bankId ON transactions(bankId)',
      );
      await db.execute(
        'CREATE INDEX idx_transactions_time ON transactions(time)',
      );
      await db.execute(
        'CREATE INDEX idx_transactions_year_month ON transactions(year, month)',
      );
      await db.execute(
        'CREATE INDEX idx_transactions_year_month_day ON transactions(year, month, day)',
      );
      await db.execute(
        'CREATE INDEX idx_transactions_bank_year_month ON transactions(bankId, year, month)',
      );
      await db.execute(
        'CREATE INDEX idx_failed_parses_timestamp ON failed_parses(timestamp)',
      );
      await db.execute(
        'CREATE INDEX idx_sms_patterns_bankId ON sms_patterns(bankId)',
      );
      await db.execute('CREATE INDEX idx_accounts_bank ON accounts(bank)');
      await db.execute(
        'CREATE INDEX idx_accounts_accountNumber ON accounts(accountNumber)',
      );

      await db.insert('transactions', {
        'id': legacyTransactionId,
        'amount': 123.45,
        'reference': 'legacy-v4-reference',
        'creditor': 'Legacy sender',
        'receiver': 'Legacy receiver',
        'time': '2025-12-14T10:11:12.000',
        'status': 'completed',
        'currentBalance': '765.43',
        'bankId': 3,
        'type': 'DEBIT',
        'transactionLink': 'https://example.test/legacy',
        'accountNumber': '000401',
        'year': 2025,
        'month': 12,
        'day': 14,
        'week': 2,
      });
      await db.insert('accounts', {
        'id': legacyAccountId,
        'accountNumber': '000401',
        'bank': 3,
        'balance': 765.43,
        'accountHolderName': 'Legacy account holder',
        'settledBalance': 700.0,
        'pendingCredit': 65.43,
      });
      await db.insert('failed_parses', {
        'id': legacyFailedParseId,
        'address': 'LEGACY-BANK',
        'body': 'legacy message body',
        'reason': 'legacy parse reason',
        'timestamp': '2025-12-14T10:11:13.000',
      });
      await db.insert('sms_patterns', {
        'id': legacySmsPatternId,
        'bankId': 3,
        'senderId': 'LEGACY-BANK',
        'regex': r'legacy\s+(\d+)',
        'type': 'DEBIT',
        'description': 'legacy pattern',
      });
      await db.setVersion(4);
    } finally {
      await db.close();
    }
  }

  static Future<void> addRenamedBuiltInCollision(Database db) async {
    final rows = await db.query(
      'categories',
      columns: ['id'],
      where: 'builtInKey = ?',
      whereArgs: ['income_repayment'],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Fresh schema did not seed income_repayment');
    }

    final sourceId = rows.single['id'] as int;
    await db.update(
      'categories',
      {'id': renamedBuiltInId, 'name': 'My repayment'},
      where: 'id = ?',
      whereArgs: [sourceId],
    );
    await db.insert('categories', {
      'id': customCanonicalId,
      'name': 'Repayment',
      'essential': 0,
      'uncategorized': 0,
      'iconKey': 'savings',
      'description': 'A user-created category with the canonical name',
      'flow': 'income',
      'recurring': 0,
      'builtIn': 0,
      'builtInKey': null,
    });
  }

  static Future<void> addLegacyGiftCollision(Database db) async {
    final rows = await db.query(
      'categories',
      columns: ['id'],
      where: 'builtInKey = ?',
      whereArgs: ['expense_gifts_given'],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Fresh schema did not seed expense_gifts_given');
    }

    final sourceId = rows.single['id'] as int;
    await db.update(
      'categories',
      {'id': renamedGiftId, 'name': 'Presents'},
      where: 'id = ?',
      whereArgs: [sourceId],
    );
    await db.insert('categories', {
      'id': legacyGiftId,
      'name': 'Gifts',
      'essential': 0,
      'uncategorized': 0,
      'iconKey': 'gift',
      'description': 'Gifts and donations',
      'flow': 'expense',
      'recurring': 0,
      'builtIn': 0,
      'builtInKey': null,
    });
  }

  static Future<void> replaceWithV20AutoCategorizationShape(Database db) async {
    final categoryRows = await db.query(
      'categories',
      columns: ['id'],
      where: 'builtInKey = ?',
      whereArgs: ['expense_groceries'],
      limit: 1,
    );
    if (categoryRows.isEmpty) {
      throw StateError('Fresh schema did not seed expense_groceries');
    }
    final categoryId = categoryRows.single['id'] as int;

    await db.execute('DROP TABLE auto_category_rules');
    await db.execute('''
      CREATE TABLE auto_category_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        counterparty TEXT NOT NULL,
        normalizedCounterparty TEXT NOT NULL,
        flow TEXT NOT NULL,
        categoryId INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        UNIQUE(normalizedCounterparty, flow)
      )
    ''');
    await db.insert('auto_category_rules', {
      'id': legacyAutoRuleId,
      'counterparty': 'Legacy Grocer',
      'normalizedCounterparty': 'legacy grocer',
      'flow': 'expense',
      'categoryId': categoryId,
      'createdAt': '2026-03-29T10:00:00.000',
    });
    await db.insert('receiver_category_mappings', {
      'id': legacyReceiverMappingId,
      'accountNumber': 'Mapped Merchant',
      'categoryId': categoryId,
      'accountType': 'receiver',
      'createdAt': '2026-03-29T11:00:00.000',
    });
    await db.setVersion(20);
  }

  static Future<void> replaceWithV25LoanShape(Database db) async {
    await db.execute('DROP TABLE loan_debt_repayments');
    await db.execute('DROP TABLE loan_debt_entries');
    await db.execute('''
      CREATE TABLE loan_debt_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transactionReference TEXT NOT NULL UNIQUE,
        personName TEXT NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        resolvedAt TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE loan_debt_repayments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        repaymentTransactionReference TEXT NOT NULL UNIQUE,
        loanDebtTransactionReference TEXT NOT NULL,
        appliedAmount REAL NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await db.insert('loan_debt_entries', {
      'id': legacyLoanEntryId,
      'transactionReference': 'legacy-loan-reference',
      'personName': 'Legacy borrower',
      'direction': 'lent',
      'status': 'active',
      'createdAt': '2026-06-14T10:00:00.000',
      'updatedAt': '2026-06-14T10:00:00.000',
    });
    await db.insert('loan_debt_repayments', {
      'id': legacyRepaymentId,
      'repaymentTransactionReference': 'legacy-repayment-reference',
      'loanDebtTransactionReference': 'legacy-loan-reference',
      'appliedAmount': 25.0,
      'createdAt': '2026-06-14T11:00:00.000',
      'updatedAt': '2026-06-14T11:00:00.000',
    });
    await db.setVersion(25);
  }

  static Future<void> removeV27SourceAndScheduleShape(
    Database db, {
    required int version,
  }) async {
    await db.insert('transactions', {
      'id': syncTransactionId,
      'amount': 26.27,
      'reference': 'sync-shape-v$version',
      'time': '2026-06-26T12:00:00.000',
      'type': 'DEBIT',
    });
    await db.insert('sync_destinations', {
      'id': syncDestinationId,
      'name': 'Legacy destination',
      'baseUrl': 'https://sync.example.test',
      'authType': 'none',
      'enabled': 1,
      'createdAt': '2026-06-26T12:00:00.000',
      'updatedAt': '2026-06-26T12:00:00.000',
    });
    await db.insert('sync_rules', {
      'id': syncRuleId,
      'destinationId': syncDestinationId,
      'name': 'Legacy transaction rule',
      'entity': 'transactions',
      'pathTemplate': '/transactions/{reference}',
      'enabled': 1,
      'createdAt': '2026-06-26T12:00:00.000',
      'updatedAt': '2026-06-26T12:00:00.000',
    });
    await db.insert('sync_outbox', {
      'id': syncOutboxId,
      'ruleId': syncRuleId,
      'entity': 'transactions',
      'entityRef': 'sync-shape-v$version',
      'nextAttemptAt': '2026-06-26T12:01:00.000',
      'createdAt': '2026-06-26T12:00:00.000',
      'updatedAt': '2026-06-26T12:00:00.000',
    });

    await db.execute('DROP INDEX IF EXISTS idx_transactions_sourceMessageId');
    await db.execute(
      'DROP INDEX IF EXISTS idx_transactions_sourceFingerprint',
    );
    await db.execute(
      'DROP INDEX IF EXISTS idx_transactions_sourceSubscriptionId',
    );
    await db.execute('ALTER TABLE transactions DROP COLUMN sourceMessageId');
    await db.execute('ALTER TABLE transactions DROP COLUMN sourceFingerprint');
    await db.execute('ALTER TABLE transactions DROP COLUMN sourceType');

    await db.execute('ALTER TABLE sync_rules DROP COLUMN lastScheduledAt');
    await db.execute('ALTER TABLE sync_rules DROP COLUMN scheduleTimes');
    await db.execute(
      'ALTER TABLE sync_rules DROP COLUMN scheduleIntervalMinutes',
    );
    await db.execute('ALTER TABLE sync_rules DROP COLUMN scheduleMode');
    await db.execute('DROP TABLE IF EXISTS sync_runtime_locks');
    await db.setVersion(version);
  }

  static Future<void> replaceV29OwnershipShapeWithV28(Database db) async {
    await db.insert('accounts', {
      'id': v28OwnershipAccountId,
      'accountNumber': '0911223344',
      'bank': 6,
      'balance': 128.0,
      'accountHolderName': 'V28 owner',
    });
    await db.insert('transactions', {
      'id': v28OwnershipTransactionId,
      'amount': 29.28,
      'reference': 'v28-ownership-sentinel',
      'time': '2026-06-28T12:00:00.000',
      'bankId': 6,
      'type': 'DEBIT',
      'accountNumber': '251911223344',
    });

    await db.execute('DROP INDEX IF EXISTS idx_transactions_ownerAccount');
    await db.execute(
      'DROP INDEX IF EXISTS idx_transactions_sourceSubscriptionId',
    );
    await db.execute('DROP INDEX IF EXISTS idx_accounts_smsSubscriptionId');
    await db.execute(
      'ALTER TABLE transactions DROP COLUMN ownerAccountNumber',
    );
    await db.execute(
      'ALTER TABLE transactions DROP COLUMN sourceSubscriptionId',
    );
    await db.execute('ALTER TABLE accounts DROP COLUMN smsSubscriptionId');
    await db.setVersion(28);
  }
}
