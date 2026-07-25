import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/models/category.dart' as models;

class DatabaseMigrationException implements Exception {
  const DatabaseMigrationException({
    required this.stage,
    required this.cause,
  });

  final String stage;
  final Object cause;

  @override
  String toString() => 'Database migration failed during "$stage".';
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  final String? _pathOverride;
  final DatabaseFactory _databaseFactory;
  Database? _database;

  DatabaseHelper._init()
      : _pathOverride = null,
        _databaseFactory = databaseFactory;

  /// Opens a database through an injected factory while exercising the same
  /// create, upgrade, and validation path as the production singleton.
  DatabaseHelper.forTesting({
    required String path,
    required DatabaseFactory databaseFactory,
  })  : _pathOverride = path,
        _databaseFactory = databaseFactory;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('totals.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final path = _pathOverride ??
        join(await _databaseFactory.getDatabasesPath(), filePath);

    final db = await _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 32,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
      ),
    );

    // Schema mutations belong in onCreate/onUpgrade so they are atomic. Keep
    // the post-open path read-only and fail with a useful invariant name if a
    // database was produced by an unknown or interrupted build.
    try {
      await _validateV32Schema(db);
    } catch (_) {
      await db.close();
      rethrow;
    }

    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    // Categories table (seeded with built-ins)
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        essential INTEGER NOT NULL DEFAULT 0,
        uncategorized INTEGER NOT NULL DEFAULT 0,
        iconKey TEXT,
        colorKey TEXT,
        description TEXT,
        flow TEXT NOT NULL DEFAULT 'expense',
        recurring INTEGER NOT NULL DEFAULT 0,
        builtIn INTEGER NOT NULL DEFAULT 0,
        builtInKey TEXT
      )
    ''');
    await db.execute(
      "CREATE UNIQUE INDEX idx_categories_name_flow ON categories(name COLLATE NOCASE, flow)",
    );
    await db.execute(
      "CREATE UNIQUE INDEX idx_categories_builtInKey ON categories(builtInKey) WHERE builtInKey IS NOT NULL",
    );

    // Transactions table
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        reference TEXT NOT NULL UNIQUE,
        creditor TEXT,
        receiver TEXT,
        note TEXT,
        time TEXT,
        status TEXT,
        currentBalance TEXT,
        serviceCharge REAL,
        vat REAL,
        bankId INTEGER,
        type TEXT,
        transactionLink TEXT,
        accountNumber TEXT,
        ownerAccountNumber TEXT,
        categoryId INTEGER,
        categoryIds TEXT,
        year INTEGER,
        month INTEGER,
        day INTEGER,
        week INTEGER,
        profileId INTEGER,
        sourceType TEXT,
        sourceMessageId TEXT,
        sourceFingerprint TEXT,
        sourceSubscriptionId INTEGER,
        ownerAssignmentSource TEXT
      )
    ''');

    // Failed parses table
    await db.execute('''
      CREATE TABLE failed_parses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT NOT NULL,
        body TEXT NOT NULL,
        reason TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    // SMS patterns table
    await db.execute('''
      CREATE TABLE sms_patterns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bankId INTEGER NOT NULL,
        senderId TEXT NOT NULL,
        regex TEXT NOT NULL,
        type TEXT NOT NULL,
        description TEXT,
        refRequired INTEGER,
        hasAccount INTEGER
      )
    ''');

    // Banks table
    await db.execute('''
      CREATE TABLE banks (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        shortName TEXT NOT NULL,
        codes TEXT NOT NULL,
        image TEXT NOT NULL,
        maskPattern INTEGER,
        uniformMasking INTEGER,
        simBased INTEGER,
        colors TEXT
      )
    ''');

    // Accounts table
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountNumber TEXT NOT NULL,
        bank INTEGER NOT NULL,
        balance REAL NOT NULL DEFAULT 0,
        accountHolderName TEXT NOT NULL,
        settledBalance REAL,
        pendingCredit REAL,
        profileId INTEGER,
        smsSubscriptionId INTEGER,
        includeInTotals INTEGER NOT NULL DEFAULT 1,
        isDormant INTEGER NOT NULL DEFAULT 0,
        isDefault INTEGER NOT NULL DEFAULT 0,
        UNIQUE(accountNumber, bank)
      )
    ''');

    // Profiles table
    await db.execute('''
      CREATE TABLE profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT
      )
    ''');

    // Budgets table
    await db.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        categoryId INTEGER,
        categoryIds TEXT,
        startDate TEXT NOT NULL,
        endDate TEXT,
        rollover INTEGER NOT NULL DEFAULT 0,
        alertThreshold REAL NOT NULL DEFAULT 80.0,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        timeFrame TEXT,
        calendar TEXT NOT NULL DEFAULT 'gregorian'
      )
    ''');

    // Receiver category mappings table
    await db.execute('''
      CREATE TABLE receiver_category_mappings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountNumber TEXT NOT NULL,
        categoryId INTEGER NOT NULL,
        accountType TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        UNIQUE(accountNumber, accountType)
      )
    ''');
    await db.execute(
      "CREATE INDEX idx_receiver_mappings_accountNumber ON receiver_category_mappings(accountNumber)",
    );
    await db.execute(
      "CREATE INDEX idx_receiver_mappings_categoryId ON receiver_category_mappings(categoryId)",
    );

    await _createAutoCategorizationRulesTable(db);

    await db.execute('''
      CREATE TABLE auto_category_prompt_dismissals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        counterparty TEXT NOT NULL,
        normalizedCounterparty TEXT NOT NULL,
        flow TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        UNIQUE(normalizedCounterparty, flow)
      )
    ''');
    await db.execute(
      "CREATE INDEX idx_auto_category_prompt_dismissals_flow ON auto_category_prompt_dismissals(flow)",
    );

    // User accounts table (for quick access accounts)
    await db.execute('''
      CREATE TABLE user_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountNumber TEXT NOT NULL,
        bankId INTEGER NOT NULL,
        accountHolderName TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        UNIQUE(accountNumber, bankId)
      )
    ''');

    // Create indexes for better query performance
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
      'CREATE INDEX idx_transactions_categoryId ON transactions(categoryId)',
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
    await db.execute('CREATE INDEX idx_budgets_type ON budgets(type)');
    await db.execute(
      'CREATE INDEX idx_budgets_categoryId ON budgets(categoryId)',
    );
    await db.execute('CREATE INDEX idx_budgets_isActive ON budgets(isActive)');
    await db.execute('CREATE INDEX idx_budgets_calendar ON budgets(calendar)');
    await db.execute(
      'CREATE INDEX idx_budgets_startDate ON budgets(startDate)',
    );
    await db.execute(
      'CREATE INDEX idx_accounts_profileId ON accounts(profileId)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_profileId ON transactions(profileId)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_sourceMessageId ON transactions(sourceType, sourceMessageId)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_sourceFingerprint ON transactions(sourceType, sourceFingerprint)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_ownerAccount ON transactions(profileId, bankId, ownerAccountNumber, time)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_sourceSubscriptionId ON transactions(sourceType, sourceSubscriptionId)',
    );
    await db.execute(
      'CREATE INDEX idx_accounts_smsSubscriptionId ON accounts(bank, smsSubscriptionId)',
    );
    await db.execute('''
      CREATE UNIQUE INDEX idx_accounts_one_default_per_bank
      ON accounts(bank, COALESCE(profileId, -1))
      WHERE isDefault = 1
    ''');
    await db.execute(
      'CREATE INDEX idx_user_accounts_bankId ON user_accounts(bankId)',
    );
    await db.execute(
      'CREATE INDEX idx_user_accounts_accountNumber ON user_accounts(accountNumber)',
    );

    await _ensureLoanDebtSchema(db);
    await _ensureReimbursementSchema(db);

    await _seedBuiltInCategories(db);
    await _ensureSyncSchema(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // Every pre-v28 schema is rescued from its observed invariants instead of
    // replaying the mutable historical chain below. Several shipped branches
    // reused version numbers with different table shapes, and the old <=v8
    // path seeds modern category fields before those columns exist.
    if (oldVersion < 28) {
      await _migrateAnySchemaToV28(db);
      if (newVersion >= 29) {
        await _migrateV28ToV29(db);
      }
      if (newVersion >= 30) {
        await _migrateV29ToV30(db);
      }
      if (newVersion >= 31) {
        await _migrateV30ToV31(db);
      }
      if (newVersion >= 32) {
        await _migrateV31ToV32(db);
      }
      return;
    }

    if (oldVersion < 29) {
      await _migrateV28ToV29(db);
      if (newVersion >= 30) {
        await _migrateV29ToV30(db);
      }
      if (newVersion >= 31) {
        await _migrateV30ToV31(db);
      }
      if (newVersion >= 32) {
        await _migrateV31ToV32(db);
      }
      return;
    }

    if (oldVersion < 30) {
      await _migrateV29ToV30(db);
      if (newVersion >= 31) {
        await _migrateV30ToV31(db);
      }
      if (newVersion >= 32) {
        await _migrateV31ToV32(db);
      }
      return;
    }

    if (oldVersion < 31) {
      await _migrateV30ToV31(db);
      if (newVersion >= 32) {
        await _migrateV31ToV32(db);
      }
      return;
    }

    if (oldVersion < 32) {
      await _migrateV31ToV32(db);
      return;
    }

    if (oldVersion < 2) {
      // Add accounts table for version 2
      await db.execute('''
        CREATE TABLE IF NOT EXISTS accounts (
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

      // Create indexes
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_accounts_bank ON accounts(bank)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_accounts_accountNumber ON accounts(accountNumber)',
      );
    }

    if (oldVersion < 3) {
      // Add receiver column to transactions table for version 3
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN receiver TEXT');
        print("debug: Added receiver column to transactions table");
      } catch (e) {
        print("debug: Error adding receiver column (might already exist): $e");
      }
    }

    if (oldVersion < 16) {
      try {
        await db.execute(
          'ALTER TABLE transactions ADD COLUMN serviceCharge REAL',
        );
      } catch (e) {
        print(
          "debug: Error adding serviceCharge column (might already exist): $e",
        );
      }
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN vat REAL');
      } catch (e) {
        print("debug: Error adding vat column (might already exist): $e");
      }
    }

    if (oldVersion < 4) {
      // Add date columns and indexes for version 4
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN year INTEGER');
        await db.execute('ALTER TABLE transactions ADD COLUMN month INTEGER');
        await db.execute('ALTER TABLE transactions ADD COLUMN day INTEGER');
        await db.execute('ALTER TABLE transactions ADD COLUMN week INTEGER');

        // Create indexes for date queries
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_time ON transactions(time)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_year_month ON transactions(year, month)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_year_month_day ON transactions(year, month, day)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_bank_year_month ON transactions(bankId, year, month)',
        );

        print("debug: Added date columns and indexes to transactions table");

        // Populate date columns for existing transactions
        final transactions = await db.query(
          'transactions',
          columns: ['id', 'time'],
        );
        final batch = db.batch();

        for (var tx in transactions) {
          if (tx['time'] != null) {
            try {
              final date = DateTime.parse(tx['time'] as String);
              batch.update(
                'transactions',
                {
                  'year': date.year,
                  'month': date.month,
                  'day': date.day,
                  'week': ((date.day - 1) ~/ 7) + 1,
                },
                where: 'id = ?',
                whereArgs: [tx['id']],
              );
            } catch (e) {
              print(
                "debug: Error parsing date for transaction ${tx['id']}: $e",
              );
            }
          }
        }

        await batch.commit(noResult: true);
        print("debug: Populated date columns for existing transactions");
      } catch (e) {
        print("debug: Error adding date columns (might already exist): $e");
      }
    }

    if (oldVersion < 5) {
      // Categories table (from HEAD/categories branch)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          essential INTEGER NOT NULL DEFAULT 0,
          uncategorized INTEGER NOT NULL DEFAULT 0,
          iconKey TEXT,
          colorKey TEXT,
          description TEXT,
          flow TEXT,
          recurring INTEGER NOT NULL DEFAULT 0
        )
      ''');

      try {
        await db.execute(
          'ALTER TABLE transactions ADD COLUMN categoryId INTEGER',
        );
      } catch (e) {
        print(
          "debug: Error adding categoryId column (might already exist): $e",
        );
      }

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_categoryId ON transactions(categoryId)',
      );

      await _seedBuiltInCategories(db);

      // sms_patterns refRequired column (from dynamic branch)
      try {
        await db.execute(
          'ALTER TABLE sms_patterns ADD COLUMN refRequired INTEGER',
        );
        print("debug: Added refRequired column to sms_patterns table");
      } catch (e) {
        print(
          "debug: Error adding refRequired column (might already exist): $e",
        );
      }
    }

    if (oldVersion < 6) {
      // Categories iconKey (from HEAD/categories branch)
      try {
        await db.execute('ALTER TABLE categories ADD COLUMN iconKey TEXT');
      } catch (e) {
        print("debug: Error adding iconKey column (might already exist): $e");
      }
      await _seedBuiltInCategories(db);

      // sms_patterns hasAccount column (from dynamic branch)
      try {
        await db.execute(
          'ALTER TABLE sms_patterns ADD COLUMN hasAccount INTEGER',
        );
        print("debug: Added hasAccount column to sms_patterns table");
      } catch (e) {
        print(
          "debug: Error adding hasAccount column (might already exist): $e",
        );
      }
    }

    if (oldVersion < 7) {
      // Categories description (from HEAD/categories branch)
      try {
        await db.execute('ALTER TABLE categories ADD COLUMN description TEXT');
      } catch (e) {
        print(
          "debug: Error adding description column (might already exist): $e",
        );
      }
      await _seedBuiltInCategories(db);

      // Banks table (from dynamic branch)
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS banks (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            shortName TEXT NOT NULL,
            codes TEXT NOT NULL,
            image TEXT NOT NULL,
            maskPattern INTEGER,
            uniformMasking INTEGER,
            simBased INTEGER,
            colors TEXT
          )
        ''');
        print("debug: Added banks table");
      } catch (e) {
        print("debug: Error adding banks table (might already exist): $e");
      }
    }

    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE categories ADD COLUMN flow TEXT');
      } catch (e) {
        print("debug: Error adding flow column (might already exist): $e");
      }

      try {
        await db.execute('ALTER TABLE categories ADD COLUMN recurring INTEGER');
      } catch (e) {
        print("debug: Error adding recurring column (might already exist): $e");
      }

      await _seedBuiltInCategories(db);
    }

    if (oldVersion < 9) {
      await _ensureGiftCategories(db);
      await _seedBuiltInCategories(db);
    }

    if (oldVersion < 10) {
      await _migrateCategoriesToNameFlowUniqueness(db);
      await _ensureGiftCategories(db);
      await _seedBuiltInCategories(db);
    }

    if (oldVersion < 11) {
      await _ensureCategoriesSchema(db);
      await _assignBuiltInCategoryKeys(db);
      await _seedBuiltInCategories(db);
    }

    if (oldVersion < 12) {
      // Add profiles table for version 12
      await db.execute('''
        CREATE TABLE IF NOT EXISTS profiles (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          updatedAt TEXT
        )
      ''');

      // Initialize default "Personal" profile if no profiles exist
      final profileCount = await db.rawQuery(
        'SELECT COUNT(*) as count FROM profiles',
      );
      if ((profileCount.first['count'] as int) == 0) {
        await db.insert('profiles', {
          'name': 'Personal',
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    }

    if (oldVersion < 13) {
      // Add colors column to banks table for version 13
      try {
        await db.execute('ALTER TABLE banks ADD COLUMN colors TEXT');
        print("debug: Added colors column to banks table");
      } catch (e) {
        print("debug: Error adding colors column (might already exist): $e");
      }
    }

    if (oldVersion < 14) {
      // Add budgets table for version 14
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS budgets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            categoryId INTEGER,
            categoryIds TEXT,
            startDate TEXT NOT NULL,
            endDate TEXT,
            rollover INTEGER NOT NULL DEFAULT 0,
            alertThreshold REAL NOT NULL DEFAULT 80.0,
            isActive INTEGER NOT NULL DEFAULT 1,
            createdAt TEXT NOT NULL,
            updatedAt TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_budgets_type ON budgets(type)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_budgets_categoryId ON budgets(categoryId)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_budgets_isActive ON budgets(isActive)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_budgets_startDate ON budgets(startDate)',
        );
        print("debug: Added budgets table");
      } catch (e) {
        print("debug: Error adding budgets table (might already exist): $e");
      }

      // Add receiver category mappings table for version 14
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS receiver_category_mappings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            accountNumber TEXT NOT NULL,
            categoryId INTEGER NOT NULL,
            accountType TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            UNIQUE(accountNumber, accountType)
          )
        ''');
        await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_receiver_mappings_accountNumber ON receiver_category_mappings(accountNumber)",
        );
        await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_receiver_mappings_categoryId ON receiver_category_mappings(categoryId)",
        );
        print("debug: Added receiver_category_mappings table");
      } catch (e) {
        print(
          "debug: Error adding receiver_category_mappings table (might already exist): $e",
        );
      }
    }

    if (oldVersion < 16) {
      // Add user_accounts table for version 16
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS user_accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            accountNumber TEXT NOT NULL,
            bankId INTEGER NOT NULL,
            accountHolderName TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            UNIQUE(accountNumber, bankId)
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_user_accounts_bankId ON user_accounts(bankId)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_user_accounts_accountNumber ON user_accounts(accountNumber)',
        );
        print("debug: Added user_accounts table");
      } catch (e) {
        print(
          "debug: Error adding user_accounts table (might already exist): $e",
        );
      }
    }

    if (oldVersion < 15) {
      // Add profileId columns to accounts and transactions tables for version 15
      try {
        // Add profileId to accounts table
        await db.execute('ALTER TABLE accounts ADD COLUMN profileId INTEGER');
        print("debug: Added profileId column to accounts table");

        // Add profileId to transactions table
        await db.execute(
          'ALTER TABLE transactions ADD COLUMN profileId INTEGER',
        );
        print("debug: Added profileId column to transactions table");

        // Create indexes for better query performance
        await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_accounts_profileId ON accounts(profileId)",
        );
        await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_transactions_profileId ON transactions(profileId)",
        );
        print("debug: Created indexes for profileId columns");

        // Migrate existing data: assign all existing accounts/transactions to active profile
        // Get active profile ID (or first profile if none active)
        // Access SharedPreferences directly to avoid circular dependency during migration
        final prefs = await SharedPreferences.getInstance();
        int? activeProfileId = prefs.getInt('active_profile_id');

        if (activeProfileId == null) {
          // Get first profile from database
          final profileResult = await db.query(
            'profiles',
            orderBy: 'createdAt ASC',
            limit: 1,
          );

          if (profileResult.isNotEmpty) {
            activeProfileId = profileResult.first['id'] as int?;
            if (activeProfileId != null) {
              await prefs.setInt('active_profile_id', activeProfileId);
            }
          } else {
            // Create default profile
            final defaultProfileId = await db.insert('profiles', {
              'name': 'Personal',
              'createdAt': DateTime.now().toIso8601String(),
            });
            activeProfileId = defaultProfileId;
            await prefs.setInt('active_profile_id', activeProfileId);
          }
        }

        // Update all existing accounts to use active profile
        await db.update(
            'accounts',
            {
              'profileId': activeProfileId,
            },
            where: 'profileId IS NULL');
        print("debug: Migrated existing accounts to profile $activeProfileId");

        // Update all existing transactions to use active profile
        await db.update(
            'transactions',
            {
              'profileId': activeProfileId,
            },
            where: 'profileId IS NULL');
        print(
          "debug: Migrated existing transactions to profile $activeProfileId",
        );
      } catch (e) {
        print(
          "debug: Error adding profileId columns (might already exist): $e",
        );
      }
    }

    if (oldVersion < 16) {
      // Add timeFrame column to budgets table for version 16
      try {
        await db.execute('ALTER TABLE budgets ADD COLUMN timeFrame TEXT');
        print("debug: Added timeFrame column to budgets table");
      } catch (e) {
        print("debug: Error adding timeFrame column (might already exist): $e");
      }
    }

    if (oldVersion < 17) {
      // Add categoryIds column to budgets table for multi-category budgets
      try {
        await db.execute('ALTER TABLE budgets ADD COLUMN categoryIds TEXT');
        print("debug: Added categoryIds column to budgets table");
      } catch (e) {
        print(
          "debug: Error adding categoryIds column (might already exist): $e",
        );
      }
    }

    if (oldVersion < 18) {
      // Add colorKey to categories table for category-specific colors.
      try {
        await db.execute('ALTER TABLE categories ADD COLUMN colorKey TEXT');
        print("debug: Added colorKey column to categories table");
      } catch (e) {
        print("debug: Error adding colorKey column (might already exist): $e");
      }
      await _migrateLegacyCategoryColorKeys(db);
    }

    if (oldVersion < 19) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN note TEXT');
        print("debug: Added note column to transactions table");
      } catch (e) {
        print("debug: Error adding note column (might already exist): $e");
      }
    }

    if (oldVersion < 20) {
      await _ensureAutoCategorizationSchema(db);
      await _migrateLegacyReceiverMappingsToAutoRules(db);
    }

    if (oldVersion < 21) {
      await _ensureTransactionCategoryIdsSchema(db);
    }

    if (oldVersion < 22) {
      await _ensureAutoCategorizationSchema(db);
    }

    if (oldVersion < 23) {
      try {
        await db.execute(
          "ALTER TABLE budgets ADD COLUMN calendar TEXT NOT NULL DEFAULT 'gregorian'",
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_budgets_calendar ON budgets(calendar)',
        );
      } catch (_) {}
    }

    if (oldVersion < 24) {
      await _ensureLoanDebtSchema(db);
    }

    if (oldVersion < 25) {
      await _ensureLoanDebtSchema(db);
    }

    if (oldVersion < 26) {
      await _ensureSyncSchema(db);
    }

    if (oldVersion < 27) {
      await _ensureTransactionSourceSchema(db);
      await _ensureSyncSchema(db);
    }
  }

  Future<void> _migrateV28ToV29(Database db) async {
    await _runV28Stage('v29 account ownership columns', () async {
      await _v28EnsureColumns(db, 'transactions', {
        'ownerAccountNumber':
            'ALTER TABLE transactions ADD COLUMN ownerAccountNumber TEXT',
        'sourceSubscriptionId':
            'ALTER TABLE transactions ADD COLUMN sourceSubscriptionId INTEGER',
      });
      await _v28EnsureColumns(db, 'accounts', {
        'smsSubscriptionId':
            'ALTER TABLE accounts ADD COLUMN smsSubscriptionId INTEGER',
      });
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_ownerAccount '
        'ON transactions(profileId, bankId, ownerAccountNumber, time)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_sourceSubscriptionId '
        'ON transactions(sourceType, sourceSubscriptionId)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_accounts_smsSubscriptionId '
        'ON accounts(bank, smsSubscriptionId)',
      );
    });
    await _runV28Stage('v29 final validation', () => _validateV29Schema(db));
  }

  Future<void> _migrateV29ToV30(Database db) async {
    await _runV28Stage('v30 account preferences', () async {
      await _v28EnsureColumns(db, 'accounts', {
        'includeInTotals':
            'ALTER TABLE accounts ADD COLUMN includeInTotals INTEGER NOT NULL DEFAULT 1',
        'isDormant':
            'ALTER TABLE accounts ADD COLUMN isDormant INTEGER NOT NULL DEFAULT 0',
      });
    });
    await _runV28Stage('v30 final validation', () => _validateV30Schema(db));
  }

  Future<void> _migrateV30ToV31(Database db) async {
    await _runV28Stage('v31 account assignment controls', () async {
      await _v28EnsureColumns(db, 'accounts', {
        'isDefault':
            'ALTER TABLE accounts ADD COLUMN isDefault INTEGER NOT NULL DEFAULT 0',
      });
      await _v28EnsureColumns(db, 'transactions', {
        'ownerAssignmentSource':
            'ALTER TABLE transactions ADD COLUMN ownerAssignmentSource TEXT',
      });

      // Every bank starts with one deterministic default. When more accounts
      // are added, this first account remains the default until the user
      // explicitly changes it.
      await db.execute('UPDATE accounts SET isDefault = 0');
      await db.execute('''
        UPDATE accounts
        SET isDefault = 1
        WHERE id IN (
          SELECT MIN(id)
          FROM accounts
          GROUP BY bank, COALESCE(profileId, -1)
        )
      ''');
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_one_default_per_bank
        ON accounts(bank, COALESCE(profileId, -1))
        WHERE isDefault = 1
      ''');
    });
    await _runV28Stage('v31 final validation', () => _validateV31Schema(db));
  }

  Future<void> _migrateV31ToV32(Database db) async {
    await _runV28Stage(
      'v32 reimbursements',
      () async {
        await _ensureReimbursementSchema(db);
        await _ensureReimbursementBuiltInCategory(db);
        await _refineRefundCategoryDescription(db);
      },
    );
    await _runV28Stage('v32 final validation', () => _validateV32Schema(db));
  }

  Future<void> _runV28Stage(
    String stage,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DatabaseMigrationException(stage: stage, cause: error),
        stackTrace,
      );
    }
  }

  Future<bool> _v28TableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> _v28Columns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info("$table")');
    return rows
        .map((row) => row['name'] as String?)
        .whereType<String>()
        .toSet();
  }

  Future<void> _v28EnsureColumns(
    Database db,
    String table,
    Map<String, String> additions,
  ) async {
    var columns = await _v28Columns(db, table);
    for (final entry in additions.entries) {
      if (columns.contains(entry.key)) continue;
      await db.execute(entry.value);
      columns = await _v28Columns(db, table);
      if (!columns.contains(entry.key)) {
        throw StateError('$table.${entry.key} was not created');
      }
    }
  }

  Future<void> _migrateAnySchemaToV28(Database db) async {
    await _runV28Stage('core tables and columns', () => _repairCoreV28(db));
    await _runV28Stage('categories', () => _repairCategoriesV28(db));
    await _runV28Stage('profiles and transaction data', () async {
      await _repairProfilesV28(db);
      await _backfillTransactionFieldsV28(db);
    });
    await _runV28Stage(
      'auto categorization',
      () => _repairAutoCategorizationV28(db),
    );
    await _runV28Stage('loan and debt tables', () => _repairLoanDebtV28(db));
    await _runV28Stage('sync tables', () => _ensureSyncSchema(db));
    await _runV28Stage('indexes', () => _createV28Indexes(db));
    await _runV28Stage('final validation', () => _validateV28Schema(db));
  }

  Future<void> _repairCoreV28(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        reference TEXT NOT NULL UNIQUE,
        creditor TEXT,
        receiver TEXT,
        note TEXT,
        time TEXT,
        status TEXT,
        currentBalance TEXT,
        serviceCharge REAL,
        vat REAL,
        bankId INTEGER,
        type TEXT,
        transactionLink TEXT,
        accountNumber TEXT,
        categoryId INTEGER,
        categoryIds TEXT,
        year INTEGER,
        month INTEGER,
        day INTEGER,
        week INTEGER,
        profileId INTEGER,
        sourceType TEXT,
        sourceMessageId TEXT,
        sourceFingerprint TEXT
      )
    ''');
    await _v28EnsureColumns(db, 'transactions', {
      'receiver': 'ALTER TABLE transactions ADD COLUMN receiver TEXT',
      'note': 'ALTER TABLE transactions ADD COLUMN note TEXT',
      'serviceCharge': 'ALTER TABLE transactions ADD COLUMN serviceCharge REAL',
      'vat': 'ALTER TABLE transactions ADD COLUMN vat REAL',
      'categoryId': 'ALTER TABLE transactions ADD COLUMN categoryId INTEGER',
      'categoryIds': 'ALTER TABLE transactions ADD COLUMN categoryIds TEXT',
      'year': 'ALTER TABLE transactions ADD COLUMN year INTEGER',
      'month': 'ALTER TABLE transactions ADD COLUMN month INTEGER',
      'day': 'ALTER TABLE transactions ADD COLUMN day INTEGER',
      'week': 'ALTER TABLE transactions ADD COLUMN week INTEGER',
      'profileId': 'ALTER TABLE transactions ADD COLUMN profileId INTEGER',
      'sourceType': 'ALTER TABLE transactions ADD COLUMN sourceType TEXT',
      'sourceMessageId':
          'ALTER TABLE transactions ADD COLUMN sourceMessageId TEXT',
      'sourceFingerprint':
          'ALTER TABLE transactions ADD COLUMN sourceFingerprint TEXT',
    });

    await db.execute('''
      CREATE TABLE IF NOT EXISTS failed_parses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT NOT NULL,
        body TEXT NOT NULL,
        reason TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sms_patterns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bankId INTEGER NOT NULL,
        senderId TEXT NOT NULL,
        regex TEXT NOT NULL,
        type TEXT NOT NULL,
        description TEXT,
        refRequired INTEGER,
        hasAccount INTEGER
      )
    ''');
    await _v28EnsureColumns(db, 'sms_patterns', {
      'refRequired': 'ALTER TABLE sms_patterns ADD COLUMN refRequired INTEGER',
      'hasAccount': 'ALTER TABLE sms_patterns ADD COLUMN hasAccount INTEGER',
    });
    await db.execute('''
      CREATE TABLE IF NOT EXISTS banks (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        shortName TEXT NOT NULL,
        codes TEXT NOT NULL,
        image TEXT NOT NULL,
        maskPattern INTEGER,
        uniformMasking INTEGER,
        simBased INTEGER,
        colors TEXT
      )
    ''');
    await _v28EnsureColumns(db, 'banks', {
      'colors': 'ALTER TABLE banks ADD COLUMN colors TEXT',
    });
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountNumber TEXT NOT NULL,
        bank INTEGER NOT NULL,
        balance REAL NOT NULL DEFAULT 0,
        accountHolderName TEXT NOT NULL,
        settledBalance REAL,
        pendingCredit REAL,
        profileId INTEGER,
        UNIQUE(accountNumber, bank)
      )
    ''');
    await _v28EnsureColumns(db, 'accounts', {
      'profileId': 'ALTER TABLE accounts ADD COLUMN profileId INTEGER',
    });
    await db.execute('''
      CREATE TABLE IF NOT EXISTS profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT
      )
    ''');
    await _v28EnsureColumns(db, 'profiles', {
      'updatedAt': 'ALTER TABLE profiles ADD COLUMN updatedAt TEXT',
    });
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        categoryId INTEGER,
        categoryIds TEXT,
        startDate TEXT NOT NULL,
        endDate TEXT,
        rollover INTEGER NOT NULL DEFAULT 0,
        alertThreshold REAL NOT NULL DEFAULT 80.0,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        timeFrame TEXT,
        calendar TEXT NOT NULL DEFAULT 'gregorian'
      )
    ''');
    await _v28EnsureColumns(db, 'budgets', {
      'categoryIds': 'ALTER TABLE budgets ADD COLUMN categoryIds TEXT',
      'timeFrame': 'ALTER TABLE budgets ADD COLUMN timeFrame TEXT',
      'calendar':
          "ALTER TABLE budgets ADD COLUMN calendar TEXT NOT NULL DEFAULT 'gregorian'",
    });
    await db.execute('''
      CREATE TABLE IF NOT EXISTS receiver_category_mappings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountNumber TEXT NOT NULL,
        categoryId INTEGER NOT NULL,
        accountType TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        UNIQUE(accountNumber, accountType)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountNumber TEXT NOT NULL,
        bankId INTEGER NOT NULL,
        accountHolderName TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        UNIQUE(accountNumber, bankId)
      )
    ''');
  }

  String _v28Flow(Object? value) {
    final flow = value?.toString().trim().toLowerCase();
    return flow == 'income' ? 'income' : 'expense';
  }

  int _v28Flag(Object? value, {int fallback = 0}) {
    if (value is num) return value == 0 ? 0 : 1;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return 1;
    if (text == 'false' || text == '0') return 0;
    return fallback;
  }

  String _v28NoCase(String value) {
    return String.fromCharCodes(value.codeUnits.map((unit) {
      return unit >= 65 && unit <= 90 ? unit + 32 : unit;
    }));
  }

  Future<bool> _categoriesNeedV28Rebuild(Database db) async {
    final required = {
      'id',
      'name',
      'essential',
      'uncategorized',
      'iconKey',
      'colorKey',
      'description',
      'flow',
      'recurring',
      'builtIn',
      'builtInKey',
    };
    final columns = await _v28Columns(db, 'categories');
    if (!columns.containsAll(required)) return true;

    final sqlRows = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='categories'",
    );
    final createSql =
        (sqlRows.isEmpty ? '' : sqlRows.first['sql'] as String? ?? '')
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ');
    if (!createSql.contains("flow text not null default 'expense'")) {
      return true;
    }

    final indexes = await db.rawQuery("PRAGMA index_list('categories')");
    for (final index in indexes) {
      if ((index['unique'] as num?)?.toInt() != 1) continue;
      final name = index['name'] as String?;
      if (name == null) continue;
      final info = await db.rawQuery('PRAGMA index_info("$name")');
      final names = info.map((row) => row['name'] as String?).toList();
      if (names.length == 1 && names.single == 'name') return true;
    }

    final invalidFlow = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM categories WHERE flow IS NULL OR LOWER(TRIM(flow)) NOT IN ('income', 'expense')",
        )) ??
        0;
    if (invalidFlow > 0) return true;
    final duplicateNames = await db.rawQuery('''
      SELECT 1 FROM categories
      GROUP BY name COLLATE NOCASE, flow
      HAVING COUNT(*) > 1 LIMIT 1
    ''');
    if (duplicateNames.isNotEmpty) return true;
    final duplicateKeys = await db.rawQuery('''
      SELECT 1 FROM categories
      WHERE builtInKey IS NOT NULL AND TRIM(builtInKey) <> ''
      GROUP BY TRIM(builtInKey)
      HAVING COUNT(*) > 1 LIMIT 1
    ''');
    return duplicateKeys.isNotEmpty;
  }

  Future<void> _repairCategoriesV28(Database db) async {
    if (!await _v28TableExists(db, 'categories')) {
      await _createCategoriesV28Table(db, 'categories');
    } else if (await _categoriesNeedV28Rebuild(db)) {
      await _rebuildCategoriesV28(db);
    }

    await _seedBuiltInsV28(db);
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_name_flow ON categories(name COLLATE NOCASE, flow)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_builtInKey ON categories(builtInKey) WHERE builtInKey IS NOT NULL',
    );
  }

  Future<void> _createCategoriesV28Table(Database db, String table) async {
    await db.execute('''
      CREATE TABLE "$table" (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        essential INTEGER NOT NULL DEFAULT 0,
        uncategorized INTEGER NOT NULL DEFAULT 0,
        iconKey TEXT,
        colorKey TEXT,
        description TEXT,
        flow TEXT NOT NULL DEFAULT 'expense',
        recurring INTEGER NOT NULL DEFAULT 0,
        builtIn INTEGER NOT NULL DEFAULT 0,
        builtInKey TEXT
      )
    ''');
  }

  Future<void> _rebuildCategoriesV28(Database db) async {
    const nextTable = 'categories_v28_new';
    const oldTable = 'categories_v28_old';
    if (await _v28TableExists(db, nextTable) ||
        await _v28TableExists(db, oldTable)) {
      throw StateError('reserved category rescue table already exists');
    }

    final source = await db.query('categories', orderBy: 'id ASC');
    final rows = <Map<String, Object?>>[];
    for (final raw in source) {
      final idValue = raw['id'];
      if (idValue is! num) throw StateError('category without integer id');
      final keyText = raw['builtInKey']?.toString().trim();
      rows.add({
        'id': idValue.toInt(),
        'name': raw['name']?.toString() ?? '',
        'essential': _v28Flag(raw['essential']),
        'uncategorized': _v28Flag(raw['uncategorized']),
        'iconKey': raw['iconKey'],
        'colorKey': raw['colorKey'],
        'description': raw['description'],
        'flow': _v28Flow(raw['flow']),
        'recurring': _v28Flag(raw['recurring']),
        'builtIn': _v28Flag(raw['builtIn']),
        'builtInKey': keyText == null || keyText.isEmpty ? null : keyText,
      });
    }

    // The lowest existing ID owns a duplicated key. Crucially, an existing
    // key owner keeps its user-edited name and is never reassigned by name.
    final keyOwners = <String, int>{};
    for (final row in rows) {
      final key = row['builtInKey'] as String?;
      if (key == null) continue;
      final id = row['id'] as int;
      final owner = keyOwners[key];
      if (owner == null) {
        keyOwners[key] = id;
      } else {
        row['builtInKey'] = null;
        row['builtIn'] = 0;
      }
    }

    final groups = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final group = '${row['flow']}\u0000${_v28NoCase(row['name'] as String)}';
      groups.putIfAbsent(group, () => []).add(row);
    }
    final usedNames = <String>{};
    final losers = <Map<String, Object?>>[];
    for (final group in groups.values) {
      group.sort((a, b) {
        final keyOrder = (b['builtInKey'] != null ? 1 : 0)
            .compareTo(a['builtInKey'] != null ? 1 : 0);
        return keyOrder != 0
            ? keyOrder
            : (a['id'] as int).compareTo(b['id'] as int);
      });
      final winner = group.first;
      usedNames.add(
        '${winner['flow']}\u0000${_v28NoCase(winner['name'] as String)}',
      );
      losers.addAll(group.skip(1));
    }
    losers.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    for (final row in losers) {
      final id = row['id'] as int;
      final original =
          (row['name'] as String).isEmpty ? 'Category' : row['name'] as String;
      var attempt = 0;
      while (true) {
        final suffix = attempt == 0 ? '$id' : '$id-${attempt + 1}';
        final candidate = '$original ($suffix)';
        final key = '${row['flow']}\u0000${_v28NoCase(candidate)}';
        if (usedNames.add(key)) {
          row['name'] = candidate;
          break;
        }
        attempt++;
      }
    }

    await _createCategoriesV28Table(db, nextTable);
    for (final row in rows) {
      await db.insert(nextTable, row);
    }
    await db.execute('ALTER TABLE categories RENAME TO $oldTable');
    await db.execute('ALTER TABLE $nextTable RENAME TO categories');
    await db.execute('DROP TABLE $oldTable');
  }

  Future<void> _seedBuiltInsV28(Database db) async {
    final existingKeys = <String>{};
    final keyedRows = await db.query(
      'categories',
      columns: ['builtInKey'],
      where: "builtInKey IS NOT NULL AND TRIM(builtInKey) <> ''",
    );
    for (final row in keyedRows) {
      existingKeys.add((row['builtInKey'] as String).trim());
    }

    for (final category in models.BuiltInCategories.all) {
      final key = category.builtInKey?.trim();
      if (key == null || key.isEmpty) continue;
      if (existingKeys.contains(key)) {
        await db.update(
          'categories',
          {'builtIn': 1},
          where: 'builtInKey = ?',
          whereArgs: [key],
        );
        continue;
      }

      final matches = await db.query(
        'categories',
        columns: ['id', 'builtInKey'],
        where: 'name = ? COLLATE NOCASE AND flow = ?',
        whereArgs: [category.name, category.flow],
        orderBy: 'id ASC',
        limit: 1,
      );
      if (key != 'income_reimbursement' &&
          matches.isNotEmpty &&
          matches.first['builtInKey'] == null) {
        await db.update(
          'categories',
          {'builtIn': 1, 'builtInKey': key},
          where: 'id = ?',
          whereArgs: [matches.first['id']],
        );
        existingKeys.add(key);
        continue;
      }

      var name = category.name;
      var attempt = 0;
      while ((await db.query(
        'categories',
        columns: ['id'],
        where: 'name = ? COLLATE NOCASE AND flow = ?',
        whereArgs: [name, category.flow],
        limit: 1,
      ))
          .isNotEmpty) {
        attempt++;
        name = '${category.name} [built-in${attempt == 1 ? '' : ' $attempt'}]';
      }
      await db.insert('categories', {
        'name': name,
        'essential': category.essential ? 1 : 0,
        'uncategorized': category.uncategorized ? 1 : 0,
        'iconKey': category.iconKey,
        'colorKey': category.colorKey,
        'description': category.description,
        'flow': category.flow,
        'recurring': category.recurring ? 1 : 0,
        'builtIn': 1,
        'builtInKey': key,
      });
      existingKeys.add(key);
    }
  }

  Future<void> _repairProfilesV28(Database db) async {
    final profiles =
        await db.query('profiles', orderBy: 'createdAt ASC', limit: 1);
    final profileId = profiles.isNotEmpty
        ? profiles.first['id'] as int
        : await db.insert('profiles', {
            'name': 'Personal',
            'createdAt': DateTime.now().toIso8601String(),
          });
    await db.update('accounts', {'profileId': profileId},
        where: 'profileId IS NULL');
    await db.update('transactions', {'profileId': profileId},
        where: 'profileId IS NULL');
  }

  Future<void> _backfillTransactionFieldsV28(Database db) async {
    final rows = await db.query('transactions', columns: [
      'id',
      'time',
      'year',
      'month',
      'day',
      'week',
      'categoryId',
      'categoryIds'
    ]);
    final batch = db.batch();
    for (final row in rows) {
      final values = <String, Object?>{};
      final time = row['time'] as String?;
      if (time != null &&
          (row['year'] == null || row['month'] == null || row['day'] == null)) {
        final date = DateTime.tryParse(time);
        if (date != null) {
          values.addAll({
            'year': date.year,
            'month': date.month,
            'day': date.day,
            'week': ((date.day - 1) ~/ 7) + 1,
          });
        }
      }
      final categoryId = row['categoryId'];
      final categoryIds = row['categoryIds'] as String?;
      if (categoryId is num &&
          categoryId.toInt() > 0 &&
          (categoryIds == null || categoryIds.trim().isEmpty)) {
        values['categoryIds'] = jsonEncode([categoryId.toInt()]);
      }
      if (values.isNotEmpty) {
        batch.update('transactions', values,
            where: 'id = ?', whereArgs: [row['id']]);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _repairAutoCategorizationV28(Database db) async {
    if (!await _v28TableExists(db, 'auto_category_rules')) {
      await _createAutoCategorizationRulesTable(db);
    } else {
      final columns = await _v28Columns(db, 'auto_category_rules');
      final sqlRows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='auto_category_rules'",
      );
      final tableSql = (sqlRows.first['sql'] as String? ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ');
      final isCanonical = columns.contains('isPrimary') &&
          tableSql.contains('unique(normalizedcounterparty, flow, categoryid)');
      if (isCanonical) {
        await _ensureAutoCategoryPromptDismissalsV28(db);
        await _copyReceiverMappingsV28(db);
        return;
      }

      const next = 'auto_category_rules_v28_new';
      const old = 'auto_category_rules_v28_old';
      if (await _v28TableExists(db, next) || await _v28TableExists(db, old)) {
        throw StateError('reserved auto-category rescue table already exists');
      }
      final rows = await db.query('auto_category_rules', orderBy: 'id ASC');
      await db.execute('''
        CREATE TABLE $next (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          counterparty TEXT NOT NULL,
          normalizedCounterparty TEXT NOT NULL,
          flow TEXT NOT NULL,
          categoryId INTEGER NOT NULL,
          isPrimary INTEGER NOT NULL DEFAULT 0,
          createdAt TEXT NOT NULL,
          UNIQUE(normalizedCounterparty, flow, categoryId)
        )
      ''');
      final primaryOwnerByGroup = <String, int>{};
      for (final row in rows) {
        final group =
            '${(row['normalizedCounterparty'] as String).trim()}\u0000${_v28Flow(row['flow'])}';
        final id = (row['id'] as num).toInt();
        if (columns.contains('isPrimary') && _v28Flag(row['isPrimary']) == 1) {
          primaryOwnerByGroup[group] = id;
        } else {
          primaryOwnerByGroup.putIfAbsent(group, () => id);
        }
      }
      for (final row in rows) {
        final normalized = (row['normalizedCounterparty'] as String).trim();
        final flow = _v28Flow(row['flow']);
        final group = '$normalized\u0000$flow';
        final isPrimary =
            primaryOwnerByGroup[group] == (row['id'] as num).toInt();
        await db.insert(next, {
          'id': row['id'],
          'counterparty': row['counterparty'],
          'normalizedCounterparty': normalized,
          'flow': flow,
          'categoryId': row['categoryId'],
          'isPrimary': isPrimary ? 1 : 0,
          'createdAt': row['createdAt'] ?? DateTime.now().toIso8601String(),
        });
      }
      await db.execute('ALTER TABLE auto_category_rules RENAME TO $old');
      await db.execute('ALTER TABLE $next RENAME TO auto_category_rules');
      await db.execute('DROP TABLE $old');
    }
    await _ensureAutoCategoryPromptDismissalsV28(db);
    await _copyReceiverMappingsV28(db);
  }

  Future<void> _ensureAutoCategoryPromptDismissalsV28(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS auto_category_prompt_dismissals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        counterparty TEXT NOT NULL,
        normalizedCounterparty TEXT NOT NULL,
        flow TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        UNIQUE(normalizedCounterparty, flow)
      )
    ''');
  }

  Future<void> _copyReceiverMappingsV28(Database db) async {
    final mappings = await db.rawQuery('''
      SELECT m.accountNumber, m.categoryId, m.createdAt, c.flow
      FROM receiver_category_mappings m
      JOIN categories c ON c.id = m.categoryId
      WHERE TRIM(m.accountNumber) <> ''
    ''');
    for (final row in mappings) {
      final counterparty = (row['accountNumber'] as String).trim();
      final normalized =
          counterparty.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      final flow = _v28Flow(row['flow']);
      final categoryId = row['categoryId'];
      final exists = await db.query('auto_category_rules',
          columns: ['id'],
          where: 'normalizedCounterparty = ? AND flow = ? AND categoryId = ?',
          whereArgs: [normalized, flow, categoryId],
          limit: 1);
      if (exists.isEmpty) {
        final groupExists = await db.query('auto_category_rules',
            columns: ['id'],
            where: 'normalizedCounterparty = ? AND flow = ?',
            whereArgs: [normalized, flow],
            limit: 1);
        await db.insert('auto_category_rules', {
          'counterparty': counterparty,
          'normalizedCounterparty': normalized,
          'flow': flow,
          'categoryId': categoryId,
          'isPrimary': groupExists.isEmpty ? 1 : 0,
          'createdAt': row['createdAt'] ?? DateTime.now().toIso8601String(),
        });
      }
    }
  }

  Future<void> _repairLoanDebtV28(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_debt_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transactionReference TEXT NOT NULL UNIQUE,
        personName TEXT NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        principalAmount REAL,
        source TEXT NOT NULL DEFAULT 'transaction',
        returnDate TEXT,
        resolvedAt TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    final before = await _v28Columns(db, 'loan_debt_entries');
    await _v28EnsureColumns(db, 'loan_debt_entries', {
      'status':
          "ALTER TABLE loan_debt_entries ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
      'principalAmount':
          'ALTER TABLE loan_debt_entries ADD COLUMN principalAmount REAL',
      'source':
          "ALTER TABLE loan_debt_entries ADD COLUMN source TEXT NOT NULL DEFAULT 'transaction'",
      'returnDate': 'ALTER TABLE loan_debt_entries ADD COLUMN returnDate TEXT',
      'resolvedAt': 'ALTER TABLE loan_debt_entries ADD COLUMN resolvedAt TEXT',
    });
    if (!before.contains('source')) {
      await db.update('loan_debt_entries', {'source': 'repayment_surplus'},
          where: 'principalAmount IS NOT NULL');
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_debt_repayments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        repaymentTransactionReference TEXT NOT NULL,
        loanDebtTransactionReference TEXT NOT NULL,
        appliedAmount REAL NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        UNIQUE(repaymentTransactionReference, loanDebtTransactionReference)
      )
    ''');
    final sql = (await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='loan_debt_repayments'",
        ))
            .first['sql'] as String? ??
        '';
    if (sql
        .toLowerCase()
        .contains('repaymenttransactionreference text not null unique')) {
      const old = 'loan_debt_repayments_v28_old';
      if (await _v28TableExists(db, old)) {
        throw StateError('$old already exists');
      }
      await db.execute('ALTER TABLE loan_debt_repayments RENAME TO $old');
      await db.execute('''
        CREATE TABLE loan_debt_repayments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          repaymentTransactionReference TEXT NOT NULL,
          loanDebtTransactionReference TEXT NOT NULL,
          appliedAmount REAL NOT NULL,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL,
          UNIQUE(repaymentTransactionReference, loanDebtTransactionReference)
        )
      ''');
      await db.execute('''
        INSERT INTO loan_debt_repayments
        SELECT id, repaymentTransactionReference, loanDebtTransactionReference,
               appliedAmount, createdAt, updatedAt FROM $old
      ''');
      await db.execute('DROP TABLE $old');
    }
  }

  Future<void> _createV28Indexes(Database db) async {
    const statements = <String>[
      'CREATE INDEX IF NOT EXISTS idx_transactions_reference ON transactions(reference)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_bankId ON transactions(bankId)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_time ON transactions(time)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_categoryId ON transactions(categoryId)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_year_month ON transactions(year, month)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_year_month_day ON transactions(year, month, day)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_bank_year_month ON transactions(bankId, year, month)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_profileId ON transactions(profileId)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_sourceMessageId ON transactions(sourceType, sourceMessageId)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_sourceFingerprint ON transactions(sourceType, sourceFingerprint)',
      'CREATE INDEX IF NOT EXISTS idx_failed_parses_timestamp ON failed_parses(timestamp)',
      'CREATE INDEX IF NOT EXISTS idx_sms_patterns_bankId ON sms_patterns(bankId)',
      'CREATE INDEX IF NOT EXISTS idx_accounts_bank ON accounts(bank)',
      'CREATE INDEX IF NOT EXISTS idx_accounts_accountNumber ON accounts(accountNumber)',
      'CREATE INDEX IF NOT EXISTS idx_accounts_profileId ON accounts(profileId)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_type ON budgets(type)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_categoryId ON budgets(categoryId)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_isActive ON budgets(isActive)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_calendar ON budgets(calendar)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_startDate ON budgets(startDate)',
      'CREATE INDEX IF NOT EXISTS idx_receiver_mappings_accountNumber ON receiver_category_mappings(accountNumber)',
      'CREATE INDEX IF NOT EXISTS idx_receiver_mappings_categoryId ON receiver_category_mappings(categoryId)',
      'CREATE INDEX IF NOT EXISTS idx_user_accounts_bankId ON user_accounts(bankId)',
      'CREATE INDEX IF NOT EXISTS idx_user_accounts_accountNumber ON user_accounts(accountNumber)',
      'CREATE INDEX IF NOT EXISTS idx_auto_category_rules_flow ON auto_category_rules(flow)',
      'CREATE INDEX IF NOT EXISTS idx_auto_category_rules_categoryId ON auto_category_rules(categoryId)',
      'CREATE INDEX IF NOT EXISTS idx_auto_category_rules_counterparty_flow ON auto_category_rules(normalizedCounterparty, flow)',
      'CREATE INDEX IF NOT EXISTS idx_auto_category_prompt_dismissals_flow ON auto_category_prompt_dismissals(flow)',
      'CREATE INDEX IF NOT EXISTS idx_loan_debt_entries_personName ON loan_debt_entries(personName COLLATE NOCASE)',
      'CREATE INDEX IF NOT EXISTS idx_loan_debt_entries_direction ON loan_debt_entries(direction)',
      'CREATE INDEX IF NOT EXISTS idx_loan_debt_entries_status ON loan_debt_entries(status)',
      'CREATE INDEX IF NOT EXISTS idx_loan_debt_entries_returnDate ON loan_debt_entries(returnDate)',
      'CREATE INDEX IF NOT EXISTS idx_loan_debt_repayments_loan ON loan_debt_repayments(loanDebtTransactionReference)',
      'CREATE INDEX IF NOT EXISTS idx_loan_debt_repayments_repayment ON loan_debt_repayments(repaymentTransactionReference)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_loan_debt_repayments_pair ON loan_debt_repayments(repaymentTransactionReference, loanDebtTransactionReference)',
    ];
    for (final statement in statements) {
      await db.execute(statement);
    }
  }

  Future<void> _validateV28Schema(Database db) async {
    const required = <String, Set<String>>{
      'categories': {'id', 'name', 'flow', 'builtIn', 'builtInKey'},
      'transactions': {
        'id',
        'reference',
        'categoryIds',
        'profileId',
        'sourceType',
        'sourceMessageId',
        'sourceFingerprint'
      },
      'accounts': {'id', 'profileId'},
      'profiles': {'id', 'name', 'createdAt'},
      'budgets': {'id', 'categoryIds', 'timeFrame', 'calendar'},
      'auto_category_rules': {
        'id',
        'normalizedCounterparty',
        'flow',
        'categoryId',
        'isPrimary'
      },
      'loan_debt_entries': {
        'id',
        'status',
        'principalAmount',
        'source',
        'returnDate'
      },
      'loan_debt_repayments': {
        'id',
        'repaymentTransactionReference',
        'loanDebtTransactionReference'
      },
      'sync_destinations': {'id', 'baseUrl', 'authType'},
      'sync_rules': {
        'id',
        'entity',
        'scheduleMode',
        'scheduleIntervalMinutes',
        'scheduleTimes',
        'lastScheduledAt'
      },
      'sync_outbox': {'id', 'ruleId', 'status', 'nextAttemptAt'},
      'sync_runtime_locks': {'name', 'owner', 'expiresAt'},
    };
    for (final entry in required.entries) {
      if (!await _v28TableExists(db, entry.key)) {
        throw StateError('v28 invariant missing table ${entry.key}');
      }
      final columns = await _v28Columns(db, entry.key);
      final missing = entry.value.difference(columns);
      if (missing.isNotEmpty) {
        throw StateError(
            'v28 invariant ${entry.key} missing ${missing.join(', ')}');
      }
    }
    final categoryIndexes =
        (await db.rawQuery("PRAGMA index_list('categories')"))
            .map((row) => row['name'])
            .toSet();
    if (!categoryIndexes.contains('idx_categories_name_flow') ||
        !categoryIndexes.contains('idx_categories_builtInKey')) {
      throw StateError('v28 category uniqueness indexes are missing');
    }
  }

  Future<void> _validateV29Schema(Database db) async {
    await _validateV28Schema(db);
    final transactionColumns = await _v28Columns(db, 'transactions');
    const requiredTransactionColumns = {
      'ownerAccountNumber',
      'sourceSubscriptionId',
    };
    final missingTransactionColumns =
        requiredTransactionColumns.difference(transactionColumns);
    if (missingTransactionColumns.isNotEmpty) {
      throw StateError(
        'v29 invariant transactions missing '
        '${missingTransactionColumns.join(', ')}',
      );
    }

    final accountColumns = await _v28Columns(db, 'accounts');
    if (!accountColumns.contains('smsSubscriptionId')) {
      throw StateError('v29 invariant accounts missing smsSubscriptionId');
    }
  }

  Future<void> _validateV30Schema(Database db) async {
    await _validateV29Schema(db);
    final accountColumns = await _v28Columns(db, 'accounts');
    const requiredAccountColumns = {'includeInTotals', 'isDormant'};
    final missingAccountColumns =
        requiredAccountColumns.difference(accountColumns);
    if (missingAccountColumns.isNotEmpty) {
      throw StateError(
        'v30 invariant accounts missing ${missingAccountColumns.join(', ')}',
      );
    }
  }

  Future<void> _validateV31Schema(Database db) async {
    await _validateV30Schema(db);
    final accountColumns = await _v28Columns(db, 'accounts');
    if (!accountColumns.contains('isDefault')) {
      throw StateError('v31 invariant accounts missing isDefault');
    }
    final transactionColumns = await _v28Columns(db, 'transactions');
    if (!transactionColumns.contains('ownerAssignmentSource')) {
      throw StateError(
        'v31 invariant transactions missing ownerAssignmentSource',
      );
    }
    final accountIndexes = (await db.rawQuery("PRAGMA index_list('accounts')"))
        .map((row) => row['name'])
        .toSet();
    if (!accountIndexes.contains('idx_accounts_one_default_per_bank')) {
      throw StateError('v31 invariant default-account index missing');
    }
  }

  Future<void> _validateV32Schema(Database db) async {
    await _validateV31Schema(db);
    if (!await _v28TableExists(db, 'reimbursement_allocations')) {
      throw StateError(
        'v32 invariant missing table reimbursement_allocations',
      );
    }
    final columns = await _v28Columns(db, 'reimbursement_allocations');
    const requiredColumns = {
      'id',
      'reimbursementTransactionReference',
      'expenseTransactionReference',
      'appliedAmount',
      'createdAt',
      'updatedAt',
    };
    final missingColumns = requiredColumns.difference(columns);
    if (missingColumns.isNotEmpty) {
      throw StateError(
        'v32 invariant reimbursement_allocations missing '
        '${missingColumns.join(', ')}',
      );
    }
    final indexes = (await db.rawQuery(
      "PRAGMA index_list('reimbursement_allocations')",
    ))
        .map((row) => row['name'])
        .toSet();
    const requiredIndexes = {
      'idx_reimbursement_allocations_reimbursement',
      'idx_reimbursement_allocations_expense',
      'idx_reimbursement_allocations_pair',
    };
    if (!indexes.containsAll(requiredIndexes)) {
      throw StateError('v32 reimbursement allocation indexes are missing');
    }
  }

  Future<void> _ensureReimbursementSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reimbursement_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reimbursementTransactionReference TEXT NOT NULL,
        expenseTransactionReference TEXT NOT NULL,
        appliedAmount REAL NOT NULL CHECK(appliedAmount > 0),
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_reimbursement_allocations_reimbursement
      ON reimbursement_allocations(reimbursementTransactionReference)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_reimbursement_allocations_expense
      ON reimbursement_allocations(expenseTransactionReference)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_reimbursement_allocations_pair
      ON reimbursement_allocations(
        reimbursementTransactionReference,
        expenseTransactionReference
      )
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_reimbursement_allocations_tx_delete
      AFTER DELETE ON transactions
      BEGIN
        DELETE FROM reimbursement_allocations
        WHERE reimbursementTransactionReference = OLD.reference
           OR expenseTransactionReference = OLD.reference;
      END
    ''');
  }

  Future<void> _ensureReimbursementBuiltInCategory(Database db) async {
    const builtInKey = 'income_reimbursement';
    final keyedRows = await db.query(
      'categories',
      columns: ['id'],
      where: 'builtInKey = ?',
      whereArgs: [builtInKey],
      limit: 1,
    );
    if (keyedRows.isNotEmpty) {
      await db.update(
        'categories',
        {'builtIn': 1, 'flow': 'income'},
        where: 'builtInKey = ?',
        whereArgs: [builtInKey],
      );
      return;
    }

    final definition = models.BuiltInCategories.all.firstWhere(
      (category) => category.builtInKey == builtInKey,
    );
    var name = definition.name;
    var suffix = 1;
    while ((await db.query(
      'categories',
      columns: ['id'],
      where: 'name = ? COLLATE NOCASE AND flow = ?',
      whereArgs: [name, definition.flow],
      limit: 1,
    ))
        .isNotEmpty) {
      name = suffix == 1
          ? '${definition.name} (Totals)'
          : '${definition.name} (Totals $suffix)';
      suffix++;
    }
    await db.insert('categories', {
      'name': name,
      'essential': definition.essential ? 1 : 0,
      'uncategorized': definition.uncategorized ? 1 : 0,
      'iconKey': definition.iconKey,
      'colorKey': definition.colorKey,
      'description': definition.description,
      'flow': definition.flow,
      'recurring': definition.recurring ? 1 : 0,
      'builtIn': 1,
      'builtInKey': builtInKey,
    });
  }

  Future<void> _refineRefundCategoryDescription(Database db) async {
    final definition = models.BuiltInCategories.all.firstWhere(
      (category) => category.builtInKey == 'income_refund',
    );
    await db.update(
      'categories',
      {'description': definition.description},
      where: '''
        builtInKey = ?
        AND (
          description IS NULL
          OR TRIM(description) = ''
          OR description = ?
        )
      ''',
      whereArgs: const [
        'income_refund',
        'Refunds and reimbursements',
      ],
    );
  }

  Future<void> _seedBuiltInCategories(Database db) async {
    final batch = db.batch();
    for (final category in models.BuiltInCategories.all) {
      batch.insert(
          'categories',
          {
            'name': category.name,
            'essential': category.essential ? 1 : 0,
            'uncategorized': category.uncategorized ? 1 : 0,
            'iconKey': category.iconKey,
            'colorKey': category.colorKey,
            'description': category.description,
            'flow': category.flow,
            'recurring': category.recurring ? 1 : 0,
            'builtIn': category.builtIn ? 1 : 0,
            'builtInKey': category.builtInKey,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      batch.update(
        'categories',
        {'iconKey': category.iconKey},
        where: "builtInKey = ? AND (iconKey IS NULL OR iconKey = '')",
        whereArgs: [category.builtInKey],
      );
      batch.update(
        'categories',
        {'description': category.description},
        where: "builtInKey = ? AND (description IS NULL OR description = '')",
        whereArgs: [category.builtInKey],
      );
      batch.update(
        'categories',
        {'builtIn': 1},
        where: "builtInKey = ?",
        whereArgs: [category.builtInKey],
      );
      batch.update(
        'categories',
        {'uncategorized': category.uncategorized ? 1 : 0},
        where: "builtInKey = ?",
        whereArgs: [category.builtInKey],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _migrateCategoriesToNameFlowUniqueness(Database db) async {
    await _ensureCategoriesSchema(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='categories'",
    );
    if (tables.isEmpty) return;

    final indexes = await db.rawQuery("PRAGMA index_list('categories')");
    final hasNameFlowIndex = indexes.any(
      (r) => (r['name'] as String?) == 'idx_categories_name_flow',
    );
    if (hasNameFlowIndex) return;

    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE categories_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          essential INTEGER NOT NULL DEFAULT 0,
          uncategorized INTEGER NOT NULL DEFAULT 0,
          iconKey TEXT,
          colorKey TEXT,
          description TEXT,
          flow TEXT NOT NULL DEFAULT 'expense',
          recurring INTEGER NOT NULL DEFAULT 0,
          builtIn INTEGER NOT NULL DEFAULT 0,
          builtInKey TEXT
        )
      ''');

      await txn.execute('''
        INSERT INTO categories_new (id, name, essential, uncategorized, iconKey, colorKey, description, flow, recurring, builtIn, builtInKey)
        SELECT
          id,
          name,
          COALESCE(essential, 0),
          COALESCE(uncategorized, 0),
          iconKey,
          colorKey,
          description,
          CASE
            WHEN flow IS NULL OR TRIM(flow) = '' THEN 'expense'
            WHEN LOWER(TRIM(flow)) = 'income' THEN 'income'
            ELSE 'expense'
          END,
          COALESCE(recurring, 0),
          COALESCE(builtIn, 0),
          builtInKey
        FROM categories
      ''');

      await txn.execute('DROP TABLE categories');
      await txn.execute('ALTER TABLE categories_new RENAME TO categories');
      await txn.execute(
        "CREATE UNIQUE INDEX idx_categories_name_flow ON categories(name COLLATE NOCASE, flow)",
      );
      await txn.execute(
        "CREATE UNIQUE INDEX idx_categories_builtInKey ON categories(builtInKey) WHERE builtInKey IS NOT NULL",
      );
    });
  }

  Future<void> _ensureCategoriesSchema(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='categories'",
    );
    if (tables.isEmpty) return;

    final cols = await db.rawQuery('PRAGMA table_info(categories)');
    final names = cols
        .map((r) => (r['name'] as String?)?.trim())
        .whereType<String>()
        .toSet();

    Future<void> addColumn(String ddl) async {
      try {
        await db.execute(ddl);
      } catch (_) {}
    }

    if (!names.contains('iconKey')) {
      await addColumn('ALTER TABLE categories ADD COLUMN iconKey TEXT');
    }
    if (!names.contains('colorKey')) {
      await addColumn('ALTER TABLE categories ADD COLUMN colorKey TEXT');
    }
    if (!names.contains('description')) {
      await addColumn('ALTER TABLE categories ADD COLUMN description TEXT');
    }
    if (!names.contains('uncategorized')) {
      await addColumn(
        'ALTER TABLE categories ADD COLUMN uncategorized INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!names.contains('flow')) {
      await addColumn('ALTER TABLE categories ADD COLUMN flow TEXT');
    }
    if (!names.contains('recurring')) {
      await addColumn('ALTER TABLE categories ADD COLUMN recurring INTEGER');
    }
    if (!names.contains('builtIn')) {
      await addColumn(
        'ALTER TABLE categories ADD COLUMN builtIn INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!names.contains('builtInKey')) {
      await addColumn('ALTER TABLE categories ADD COLUMN builtInKey TEXT');
    }

    try {
      await db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_name_flow ON categories(name COLLATE NOCASE, flow)",
      );
    } catch (_) {}
    try {
      await db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_builtInKey ON categories(builtInKey) WHERE builtInKey IS NOT NULL",
      );
    } catch (_) {}
  }

  Future<void> _migrateLegacyCategoryColorKeys(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='categories'",
    );
    if (tables.isEmpty) return;

    final cols = await db.rawQuery('PRAGMA table_info(categories)');
    final names = cols
        .map((r) => (r['name'] as String?)?.trim())
        .whereType<String>()
        .toSet();
    if (!names.contains('colorKey')) return;

    await db.execute('''
      UPDATE categories
      SET
        colorKey = TRIM(SUBSTR(iconKey, 7)),
        iconKey = 'more_horiz'
      WHERE
        iconKey LIKE 'color:%'
        AND (colorKey IS NULL OR TRIM(colorKey) = '')
    ''');
  }

  Future<void> _ensureTransactionCategoryIdsSchema(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'",
    );
    if (tables.isEmpty) return;

    final cols = await db.rawQuery('PRAGMA table_info(transactions)');
    final names = cols
        .map((r) => (r['name'] as String?)?.trim())
        .whereType<String>()
        .toSet();

    Future<void> addColumn(String ddl) async {
      try {
        await db.execute(ddl);
      } catch (_) {}
    }

    if (!names.contains('categoryIds')) {
      await addColumn('ALTER TABLE transactions ADD COLUMN categoryIds TEXT');
    }

    final rows = await db.query(
      'transactions',
      columns: ['id', 'categoryId', 'categoryIds'],
      where:
          'categoryId IS NOT NULL AND (categoryIds IS NULL OR TRIM(categoryIds) = \'\')',
    );
    if (rows.isEmpty) return;

    final batch = db.batch();
    for (final row in rows) {
      final id = row['id'];
      final categoryId = row['categoryId'] as int?;
      if (id == null || categoryId == null || categoryId <= 0) continue;
      batch.update(
        'transactions',
        {
          'categoryIds': jsonEncode(<int>[categoryId]),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _ensureTransactionSourceSchema(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'",
    );
    if (tables.isEmpty) return;

    final cols = await db.rawQuery('PRAGMA table_info(transactions)');
    final names = cols
        .map((r) => (r['name'] as String?)?.trim())
        .whereType<String>()
        .toSet();

    Future<void> addColumn(String ddl) async {
      try {
        await db.execute(ddl);
      } catch (_) {}
    }

    if (!names.contains('sourceType')) {
      await addColumn('ALTER TABLE transactions ADD COLUMN sourceType TEXT');
    }
    if (!names.contains('sourceMessageId')) {
      await addColumn(
        'ALTER TABLE transactions ADD COLUMN sourceMessageId TEXT',
      );
    }
    if (!names.contains('sourceFingerprint')) {
      await addColumn(
        'ALTER TABLE transactions ADD COLUMN sourceFingerprint TEXT',
      );
    }

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_sourceMessageId ON transactions(sourceType, sourceMessageId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_sourceFingerprint ON transactions(sourceType, sourceFingerprint)',
    );
  }

  Future<void> _ensureAutoCategorizationSchema(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='auto_category_rules'",
    );
    if (tables.isEmpty) {
      await _createAutoCategorizationRulesTable(db, ifNotExists: true);
    } else {
      final cols = await db.rawQuery('PRAGMA table_info(auto_category_rules)');
      final names = cols
          .map((r) => (r['name'] as String?)?.trim())
          .whereType<String>()
          .toSet();
      if (!names.contains('isPrimary')) {
        await _rebuildAutoCategorizationRulesTable(db);
      }
    }

    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_auto_category_rules_flow ON auto_category_rules(flow)",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_auto_category_rules_categoryId ON auto_category_rules(categoryId)",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_auto_category_rules_counterparty_flow ON auto_category_rules(normalizedCounterparty, flow)",
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS auto_category_prompt_dismissals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        counterparty TEXT NOT NULL,
        normalizedCounterparty TEXT NOT NULL,
        flow TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        UNIQUE(normalizedCounterparty, flow)
      )
    ''');
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_auto_category_prompt_dismissals_flow ON auto_category_prompt_dismissals(flow)",
    );
  }

  Future<void> _ensureLoanDebtSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_debt_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transactionReference TEXT NOT NULL UNIQUE,
        personName TEXT NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        principalAmount REAL,
        source TEXT NOT NULL DEFAULT 'transaction',
        returnDate TEXT,
        resolvedAt TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_debt_repayments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        repaymentTransactionReference TEXT NOT NULL,
        loanDebtTransactionReference TEXT NOT NULL,
        appliedAmount REAL NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        UNIQUE(repaymentTransactionReference, loanDebtTransactionReference)
      )
    ''');
    final columns = await db.rawQuery('PRAGMA table_info(loan_debt_entries)');
    final names = columns.map((column) => column['name'] as String?).toSet();
    Future<void> addColumn(String sql) async {
      try {
        await db.execute(sql);
      } catch (_) {}
    }

    if (!names.contains('status')) {
      await addColumn(
        "ALTER TABLE loan_debt_entries ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
      );
    }
    if (!names.contains('resolvedAt')) {
      await addColumn(
        'ALTER TABLE loan_debt_entries ADD COLUMN resolvedAt TEXT',
      );
    }
    if (!names.contains('principalAmount')) {
      await addColumn(
        'ALTER TABLE loan_debt_entries ADD COLUMN principalAmount REAL',
      );
    }
    if (!names.contains('source')) {
      await addColumn(
        "ALTER TABLE loan_debt_entries ADD COLUMN source TEXT NOT NULL DEFAULT 'transaction'",
      );
      await db.update(
          'loan_debt_entries',
          {
            'source': 'repayment_surplus',
          },
          where: 'principalAmount IS NOT NULL');
    }
    if (!names.contains('returnDate')) {
      await addColumn(
        'ALTER TABLE loan_debt_entries ADD COLUMN returnDate TEXT',
      );
    }
    await _ensureLoanDebtRepaymentSplitSchema(db);
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_loan_debt_entries_personName ON loan_debt_entries(personName COLLATE NOCASE)",
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loan_debt_entries_direction ON loan_debt_entries(direction)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loan_debt_entries_status ON loan_debt_entries(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loan_debt_entries_returnDate ON loan_debt_entries(returnDate)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loan_debt_repayments_loan ON loan_debt_repayments(loanDebtTransactionReference)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loan_debt_repayments_repayment ON loan_debt_repayments(repaymentTransactionReference)',
    );
  }

  Future<void> _ensureLoanDebtRepaymentSplitSchema(Database db) async {
    final rows = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='loan_debt_repayments'",
    );
    if (rows.isEmpty) return;

    final createSql = ((rows.first['sql'] as String?) ?? '').toLowerCase();
    final hasSingleRepaymentUnique = createSql.contains(
      'repaymenttransactionreference text not null unique',
    );
    if (hasSingleRepaymentUnique) {
      await db.transaction((txn) async {
        await txn.execute(
          'ALTER TABLE loan_debt_repayments RENAME TO loan_debt_repayments_legacy',
        );
        await txn.execute('''
          CREATE TABLE loan_debt_repayments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            repaymentTransactionReference TEXT NOT NULL,
            loanDebtTransactionReference TEXT NOT NULL,
            appliedAmount REAL NOT NULL,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            UNIQUE(repaymentTransactionReference, loanDebtTransactionReference)
          )
        ''');
        await txn.execute('''
          INSERT OR IGNORE INTO loan_debt_repayments (
            id,
            repaymentTransactionReference,
            loanDebtTransactionReference,
            appliedAmount,
            createdAt,
            updatedAt
          )
          SELECT
            id,
            repaymentTransactionReference,
            loanDebtTransactionReference,
            appliedAmount,
            createdAt,
            updatedAt
          FROM loan_debt_repayments_legacy
          WHERE TRIM(repaymentTransactionReference) <> ''
            AND TRIM(loanDebtTransactionReference) <> ''
            AND appliedAmount > 0
        ''');
        await txn.execute('DROP TABLE loan_debt_repayments_legacy');
      });
    }

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_loan_debt_repayments_pair ON loan_debt_repayments(repaymentTransactionReference, loanDebtTransactionReference)',
    );
  }

  /// Data Sync feature tables (v26). Purely additive; created with
  /// `IF NOT EXISTS` so a hot reload or version skew is safe. Secret values
  /// for destinations live in FlutterSecureStorage (keyed by secretRef), never
  /// in these tables.
  Future<void> _ensureSyncSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_destinations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        baseUrl TEXT NOT NULL,
        authType TEXT NOT NULL DEFAULT 'none',
        authHeaderName TEXT,
        authUsername TEXT,
        secretRef TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        destinationId INTEGER NOT NULL,
        name TEXT NOT NULL,
        entity TEXT NOT NULL,
        filterJson TEXT,
        method TEXT NOT NULL DEFAULT 'POST',
        pathTemplate TEXT NOT NULL,
        fieldMapJson TEXT,
        sendUnmapped INTEGER NOT NULL DEFAULT 0,
        batchMode TEXT NOT NULL DEFAULT 'per_record',
        triggerManual INTEGER NOT NULL DEFAULT 1,
        triggerPeriodic INTEGER NOT NULL DEFAULT 0,
        triggerOnNewTxn INTEGER NOT NULL DEFAULT 0,
        triggerOnConnectivity INTEGER NOT NULL DEFAULT 0,
        scheduleMode TEXT NOT NULL DEFAULT 'off',
        scheduleIntervalMinutes INTEGER,
        scheduleTimes TEXT,
        lastScheduledAt TEXT,
        enabled INTEGER NOT NULL DEFAULT 0,
        backfillDone INTEGER NOT NULL DEFAULT 0,
        lastStatus TEXT,
        lastRunAt TEXT,
        lastError TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_rules_entity ON sync_rules(entity)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_rules_enabled ON sync_rules(enabled)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ruleId INTEGER NOT NULL,
        entity TEXT NOT NULL,
        entityRef TEXT NOT NULL,
        op TEXT NOT NULL DEFAULT 'upsert',
        payloadJson TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        nextAttemptAt TEXT NOT NULL,
        lastError TEXT,
        lastStatusCode INTEGER,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        UNIQUE(ruleId, entityRef, op)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_due ON sync_outbox(status, nextAttemptAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_rule ON sync_outbox(ruleId)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_runtime_locks (
        name TEXT PRIMARY KEY,
        owner TEXT NOT NULL,
        acquiredAt TEXT NOT NULL,
        expiresAt TEXT NOT NULL
      )
    ''');

    // Defensive: add the per-rule schedule columns (v27) to an existing
    // sync_rules table created under v26.
    final ruleCols = await db.rawQuery('PRAGMA table_info(sync_rules)');
    final ruleColNames =
        ruleCols.map((c) => c['name'] as String?).whereType<String>().toSet();
    Future<void> addRuleColumn(String name, String ddl) async {
      if (!ruleColNames.contains(name)) {
        try {
          await db.execute(ddl);
        } catch (_) {}
      }
    }

    await addRuleColumn(
      'scheduleMode',
      "ALTER TABLE sync_rules ADD COLUMN scheduleMode TEXT NOT NULL DEFAULT 'off'",
    );
    await addRuleColumn(
      'scheduleIntervalMinutes',
      'ALTER TABLE sync_rules ADD COLUMN scheduleIntervalMinutes INTEGER',
    );
    await addRuleColumn(
      'scheduleTimes',
      'ALTER TABLE sync_rules ADD COLUMN scheduleTimes TEXT',
    );
    await addRuleColumn(
      'lastScheduledAt',
      'ALTER TABLE sync_rules ADD COLUMN lastScheduledAt TEXT',
    );
  }

  Future<void> _createAutoCategorizationRulesTable(
    Database db, {
    bool ifNotExists = false,
  }) async {
    final ifNotExistsClause = ifNotExists ? ' IF NOT EXISTS' : '';
    await db.execute('''
      CREATE TABLE$ifNotExistsClause auto_category_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        counterparty TEXT NOT NULL,
        normalizedCounterparty TEXT NOT NULL,
        flow TEXT NOT NULL,
        categoryId INTEGER NOT NULL,
        isPrimary INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        UNIQUE(normalizedCounterparty, flow, categoryId)
      )
    ''');
  }

  Future<void> _rebuildAutoCategorizationRulesTable(Database db) async {
    await db.execute('DROP TABLE IF EXISTS auto_category_rules_legacy');
    await db.execute(
      'ALTER TABLE auto_category_rules RENAME TO auto_category_rules_legacy',
    );
    await _createAutoCategorizationRulesTable(db);

    final legacyRows = await db.query(
      'auto_category_rules_legacy',
      orderBy:
          'normalizedCounterparty COLLATE NOCASE ASC, flow ASC, createdAt ASC, id ASC',
    );

    final batch = db.batch();
    final seenKeys = <String>{};
    final promotedGroups = <String>{};
    for (final row in legacyRows) {
      final normalizedCounterparty =
          (row['normalizedCounterparty'] as String?)?.trim() ?? '';
      final flow = (row['flow'] as String?)?.trim() ?? 'expense';
      final categoryId = row['categoryId'] as int?;
      if (normalizedCounterparty.isEmpty ||
          categoryId == null ||
          categoryId <= 0) {
        continue;
      }

      final ruleKey = '$normalizedCounterparty|$flow|$categoryId';
      if (!seenKeys.add(ruleKey)) continue;

      final groupKey = '$normalizedCounterparty|$flow';
      final isPrimary = promotedGroups.add(groupKey);
      batch.insert(
          'auto_category_rules',
          {
            'counterparty': row['counterparty'],
            'normalizedCounterparty': normalizedCounterparty,
            'flow': flow,
            'categoryId': categoryId,
            'isPrimary': isPrimary ? 1 : 0,
            'createdAt': row['createdAt'] ?? DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await db.execute('DROP TABLE IF EXISTS auto_category_rules_legacy');
  }

  Future<void> _migrateLegacyReceiverMappingsToAutoRules(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='receiver_category_mappings'",
    );
    if (tables.isEmpty) return;

    final rows = await db.rawQuery('''
      SELECT
        m.accountNumber,
        m.categoryId,
        m.createdAt,
        c.flow
      FROM receiver_category_mappings m
      INNER JOIN categories c ON c.id = m.categoryId
      WHERE m.accountNumber IS NOT NULL AND TRIM(m.accountNumber) <> ''
      ORDER BY
        CASE
          WHEN m.createdAt IS NULL OR TRIM(m.createdAt) = '' THEN 1
          ELSE 0
        END,
        m.createdAt ASC,
        m.id ASC
    ''');
    if (rows.isEmpty) return;

    String normalizeCounterparty(String value) {
      return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    }

    final batch = db.batch();
    for (final row in rows) {
      final counterparty = (row['accountNumber'] as String?)?.trim();
      final categoryId = row['categoryId'] as int?;
      if (counterparty == null || counterparty.isEmpty || categoryId == null) {
        continue;
      }
      final flow = ((row['flow'] as String?) ?? 'expense').trim().toLowerCase();
      batch.insert(
          'auto_category_rules',
          {
            'counterparty': counterparty.replaceAll(RegExp(r'\s+'), ' '),
            'normalizedCounterparty': normalizeCounterparty(counterparty),
            'flow': flow == 'income' ? 'income' : 'expense',
            'categoryId': categoryId,
            'isPrimary': 1,
            'createdAt':
                (row['createdAt'] as String?)?.trim().isNotEmpty == true
                    ? row['createdAt']
                    : DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await db.delete('receiver_category_mappings');
  }

  Future<bool> _markCategoryBuiltInByKey(Database db, String key) async {
    final rows = await db.query(
      'categories',
      columns: ['id'],
      where: 'builtInKey = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    await db.update(
      'categories',
      {'builtIn': 1},
      where: 'builtInKey = ?',
      whereArgs: [key],
    );
    return true;
  }

  Future<void> _assignBuiltInCategoryKeys(Database db) async {
    for (final builtIn in models.BuiltInCategories.all) {
      final key = builtIn.builtInKey;
      if (key == null || key.isEmpty) continue;
      if (await _markCategoryBuiltInByKey(db, key)) continue;

      // 1) Match by name+flow (works for most cases).
      final byName = await db.query(
        'categories',
        columns: ['id', 'builtInKey'],
        where: 'flow = ? AND name = ? COLLATE NOCASE',
        whereArgs: [builtIn.flow, builtIn.name],
        limit: 1,
      );
      if (byName.isNotEmpty) {
        final id = byName.first['id'] as int?;
        final existingKey = (byName.first['builtInKey'] as String?)?.trim();
        if (id != null && (existingKey == null || existingKey.isEmpty)) {
          await db.update(
            'categories',
            {'builtIn': 1, 'builtInKey': key},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        continue;
      }

      // 2) Best-effort match for "renamed built-ins": match by attributes
      // if there is a single clear candidate with no builtInKey set.
      final candidates = await db.query(
        'categories',
        columns: ['id'],
        where: '''
          (builtInKey IS NULL OR TRIM(builtInKey) = '')
          AND flow = ?
          AND essential = ?
          AND uncategorized = ?
          AND recurring = ?
          AND (iconKey = ? OR iconKey IS NULL OR TRIM(iconKey) = '')
          AND (description = ? OR description IS NULL OR TRIM(description) = '')
        ''',
        whereArgs: [
          builtIn.flow,
          builtIn.essential ? 1 : 0,
          builtIn.uncategorized ? 1 : 0,
          builtIn.recurring ? 1 : 0,
          builtIn.iconKey,
          builtIn.description,
        ],
      );
      if (candidates.length == 1) {
        final id = candidates.first['id'] as int?;
        if (id == null) continue;
        await db.update(
          'categories',
          {'builtIn': 1, 'builtInKey': key},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  Future<void> _ensureGiftCategories(Database db) async {
    // If an older build had a single "Gifts" category, split it into:
    // - "Gifts given" (expense)
    // - "Gifts received" (income)
    //
    // Only rename if the row appears to be the built-in placeholder.
    final rows = await db.query(
      'categories',
      columns: ['id', 'name', 'iconKey', 'description', 'flow', 'essential'],
      where: "name IN ('Gifts', 'Gifts given', 'Gifts received')",
    );

    final hasGiftsGivenKey =
        await _markCategoryBuiltInByKey(db, 'expense_gifts_given');
    final hasGiftsReceivedKey =
        await _markCategoryBuiltInByKey(db, 'income_gifts_received');

    bool hasGiftsGiven =
        hasGiftsGivenKey || rows.any((r) => r['name'] == 'Gifts given');
    bool hasGiftsReceived =
        hasGiftsReceivedKey || rows.any((r) => r['name'] == 'Gifts received');

    final giftsRow = rows.where((r) => r['name'] == 'Gifts').toList();
    if (giftsRow.isNotEmpty && !hasGiftsGiven) {
      final r = giftsRow.first;
      final iconKey = (r['iconKey'] as String?)?.trim();
      final desc = (r['description'] as String?)?.trim();
      final flow = (r['flow'] as String?)?.trim().toLowerCase();

      final looksBuiltIn =
          (iconKey == null || iconKey.isEmpty || iconKey == 'gift') &&
              (flow == null || flow.isEmpty || flow == 'expense') &&
              (desc == null ||
                  desc.isEmpty ||
                  desc == 'Gifts and donations' ||
                  desc == 'Gifts received or given');

      if (looksBuiltIn) {
        await db.update(
          'categories',
          {
            'name': 'Gifts given',
            'flow': 'expense',
            'builtIn': 1,
            'builtInKey': 'expense_gifts_given',
          },
          where: 'id = ?',
          whereArgs: [r['id']],
        );
        hasGiftsGiven = true;
      }
    }

    if (!hasGiftsGiven) {
      await db.insert(
          'categories',
          {
            'name': 'Gifts given',
            'essential': 0,
            'iconKey': 'gift',
            'description': 'Gifts you give to others',
            'flow': 'expense',
            'recurring': 0,
            'builtIn': 1,
            'builtInKey': 'expense_gifts_given',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    if (!hasGiftsReceived) {
      await db.insert(
          'categories',
          {
            'name': 'Gifts received',
            'essential': 0,
            'iconKey': 'gift',
            'description': 'Gifts you receive from others',
            'flow': 'income',
            'recurring': 0,
            'builtIn': 1,
            'builtInKey': 'income_gifts_received',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) return;
    await db.close();
    _database = null;
  }
}
