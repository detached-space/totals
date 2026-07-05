import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/models/category.dart' as models;

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('totals.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    final db = await openDatabase(
      path,
      version: 27,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );

    // Defensive schema guard: ensure required columns exist even if an upgrade
    // didn't run (e.g., hot reload or DB version mismatch).
    await _ensureCategoriesSchema(db);
    await _migrateLegacyCategoryColorKeys(db);
    await _ensureBudgetsSchema(db);
    await _ensureGiftCategories(db);
    await _assignBuiltInCategoryKeys(db);
    await _seedBuiltInCategories(db);
    await _ensureProfileSchema(db);
    await _ensureTransactionFeesSchema(db);
    await _ensureTransactionNotesSchema(db);
    await _ensureTransactionCategoryIdsSchema(db);
    await _ensureTransactionSourceSchema(db);
    await _ensureAutoCategorizationSchema(db);
    await _ensureLoanDebtSchema(db);
    await _migrateLegacyReceiverMappingsToAutoRules(db);
    await _ensureSyncSchema(db);

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
      'CREATE INDEX idx_user_accounts_bankId ON user_accounts(bankId)',
    );
    await db.execute(
      'CREATE INDEX idx_user_accounts_accountNumber ON user_accounts(accountNumber)',
    );

    await _ensureLoanDebtSchema(db);

    await _seedBuiltInCategories(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
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
        await db.update('accounts', {
          'profileId': activeProfileId,
        }, where: 'profileId IS NULL');
        print("debug: Migrated existing accounts to profile $activeProfileId");

        // Update all existing transactions to use active profile
        await db.update('transactions', {
          'profileId': activeProfileId,
        }, where: 'profileId IS NULL');
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

  Future<void> _seedBuiltInCategories(Database db) async {
    final batch = db.batch();
    for (final category in models.BuiltInCategories.all) {
      batch.insert('categories', {
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
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
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

  Future<void> _ensureBudgetsSchema(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='budgets'",
    );
    if (tables.isEmpty) return;

    final cols = await db.rawQuery('PRAGMA table_info(budgets)');
    final names = cols
        .map((r) => (r['name'] as String?)?.trim())
        .whereType<String>()
        .toSet();

    Future<void> addColumn(String ddl) async {
      try {
        await db.execute(ddl);
      } catch (_) {}
    }

    if (!names.contains('timeFrame')) {
      await addColumn('ALTER TABLE budgets ADD COLUMN timeFrame TEXT');
    }
    if (!names.contains('categoryIds')) {
      await addColumn('ALTER TABLE budgets ADD COLUMN categoryIds TEXT');
    }
    if (!names.contains('calendar')) {
      await addColumn(
        "ALTER TABLE budgets ADD COLUMN calendar TEXT NOT NULL DEFAULT 'gregorian'",
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_budgets_calendar ON budgets(calendar)',
    );
  }

  Future<void> _ensureProfileSchema(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('accounts', 'transactions', 'profiles')",
    );
    final tableNames = tables
        .map((r) => (r['name'] as String?)?.trim())
        .whereType<String>()
        .toSet();

    Future<Set<String>> columnNames(String table) async {
      final cols = await db.rawQuery('PRAGMA table_info($table)');
      return cols
          .map((r) => (r['name'] as String?)?.trim())
          .whereType<String>()
          .toSet();
    }

    if (tableNames.contains('accounts')) {
      final names = await columnNames('accounts');
      if (!names.contains('profileId')) {
        await db.execute('ALTER TABLE accounts ADD COLUMN profileId INTEGER');
      }
      await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_accounts_profileId ON accounts(profileId)",
      );
    }

    if (tableNames.contains('transactions')) {
      final names = await columnNames('transactions');
      if (!names.contains('profileId')) {
        await db.execute(
          'ALTER TABLE transactions ADD COLUMN profileId INTEGER',
        );
      }
      await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_transactions_profileId ON transactions(profileId)",
      );
    }

    if (!tableNames.contains('profiles')) {
      await db.execute('''
        CREATE TABLE profiles (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          updatedAt TEXT
        )
      ''');
      tableNames.add('profiles');
    }

    if (!tableNames.contains('profiles')) return;

    final prefs = await SharedPreferences.getInstance();
    int? activeProfileId = prefs.getInt('active_profile_id');

    if (activeProfileId == null) {
      final profileResult = await db.query(
        'profiles',
        orderBy: 'createdAt ASC',
        limit: 1,
      );

      if (profileResult.isNotEmpty) {
        activeProfileId = profileResult.first['id'] as int?;
      }

      if (activeProfileId == null) {
        activeProfileId = await db.insert('profiles', {
          'name': 'Personal',
          'createdAt': DateTime.now().toIso8601String(),
        });
      }

      await prefs.setInt('active_profile_id', activeProfileId);
    }

    if (tableNames.contains('accounts')) {
      await db.update('accounts', {
        'profileId': activeProfileId,
      }, where: 'profileId IS NULL');
    }

    if (tableNames.contains('transactions')) {
      await db.update('transactions', {
        'profileId': activeProfileId,
      }, where: 'profileId IS NULL');
    }
  }

  Future<void> _ensureTransactionFeesSchema(Database db) async {
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

    if (!names.contains('serviceCharge')) {
      await addColumn('ALTER TABLE transactions ADD COLUMN serviceCharge REAL');
    }
    if (!names.contains('vat')) {
      await addColumn('ALTER TABLE transactions ADD COLUMN vat REAL');
    }
  }

  Future<void> _ensureTransactionNotesSchema(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'",
    );
    if (tables.isEmpty) return;

    final cols = await db.rawQuery('PRAGMA table_info(transactions)');
    final names = cols
        .map((r) => (r['name'] as String?)?.trim())
        .whereType<String>()
        .toSet();

    if (names.contains('note')) return;

    try {
      await db.execute('ALTER TABLE transactions ADD COLUMN note TEXT');
    } catch (_) {}
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
      await db.update('loan_debt_entries', {
        'source': 'repayment_surplus',
      }, where: 'principalAmount IS NOT NULL');
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
    final ruleColNames = ruleCols
        .map((c) => c['name'] as String?)
        .whereType<String>()
        .toSet();
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
      batch.insert('auto_category_rules', {
        'counterparty': row['counterparty'],
        'normalizedCounterparty': normalizedCounterparty,
        'flow': flow,
        'categoryId': categoryId,
        'isPrimary': isPrimary ? 1 : 0,
        'createdAt': row['createdAt'] ?? DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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
      batch.insert('auto_category_rules', {
        'counterparty': counterparty.replaceAll(RegExp(r'\s+'), ' '),
        'normalizedCounterparty': normalizeCounterparty(counterparty),
        'flow': flow == 'income' ? 'income' : 'expense',
        'categoryId': categoryId,
        'isPrimary': 1,
        'createdAt': (row['createdAt'] as String?)?.trim().isNotEmpty == true
            ? row['createdAt']
            : DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await db.delete('receiver_category_mappings');
  }

  Future<void> _assignBuiltInCategoryKeys(Database db) async {
    for (final builtIn in models.BuiltInCategories.all) {
      final key = builtIn.builtInKey;
      if (key == null || key.isEmpty) continue;

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

    bool hasGiftsGiven = rows.any((r) => r['name'] == 'Gifts given');
    bool hasGiftsReceived = rows.any((r) => r['name'] == 'Gifts received');

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
      await db.insert('categories', {
        'name': 'Gifts given',
        'essential': 0,
        'iconKey': 'gift',
        'description': 'Gifts you give to others',
        'flow': 'expense',
        'recurring': 0,
        'builtIn': 1,
        'builtInKey': 'expense_gifts_given',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    if (!hasGiftsReceived) {
      await db.insert('categories', {
        'name': 'Gifts received',
        'essential': 0,
        'iconKey': 'gift',
        'description': 'Gifts you receive from others',
        'flow': 'income',
        'recurring': 0,
        'builtIn': 1,
        'builtInKey': 'income_gifts_received',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
