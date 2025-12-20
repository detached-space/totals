import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
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
      version: 11,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );

    // Defensive schema guard: ensure required columns exist even if an upgrade
    // didn't run (e.g., hot reload or DB version mismatch).
    await _ensureCategoriesSchema(db);
    await _ensureGiftCategories(db);
    await _assignBuiltInCategoryKeys(db);
    await _seedBuiltInCategories(db);

    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    // Categories table (seeded with built-ins)
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        essential INTEGER NOT NULL DEFAULT 0,
        iconKey TEXT,
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
        time TEXT,
        status TEXT,
        currentBalance TEXT,
        bankId INTEGER,
        type TEXT,
        transactionLink TEXT,
        accountNumber TEXT,
        categoryId INTEGER,
        year INTEGER,
        month INTEGER,
        day INTEGER,
        week INTEGER
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
        description TEXT
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
        UNIQUE(accountNumber, bank)
      )
    ''');

    // Create indexes for better query performance
    await db.execute(
        'CREATE INDEX idx_transactions_reference ON transactions(reference)');
    await db.execute(
        'CREATE INDEX idx_transactions_bankId ON transactions(bankId)');
    await db.execute(
        'CREATE INDEX idx_transactions_time ON transactions(time)');
    await db.execute(
        'CREATE INDEX idx_transactions_categoryId ON transactions(categoryId)');
    await db.execute(
        'CREATE INDEX idx_transactions_year_month ON transactions(year, month)');
    await db.execute(
        'CREATE INDEX idx_transactions_year_month_day ON transactions(year, month, day)');
    await db.execute(
        'CREATE INDEX idx_transactions_bank_year_month ON transactions(bankId, year, month)');
    await db.execute(
        'CREATE INDEX idx_failed_parses_timestamp ON failed_parses(timestamp)');
    await db.execute(
        'CREATE INDEX idx_sms_patterns_bankId ON sms_patterns(bankId)');
    await db.execute('CREATE INDEX idx_accounts_bank ON accounts(bank)');
    await db.execute(
        'CREATE INDEX idx_accounts_accountNumber ON accounts(accountNumber)');

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
          'CREATE INDEX IF NOT EXISTS idx_accounts_bank ON accounts(bank)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_accounts_accountNumber ON accounts(accountNumber)');
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

    if (oldVersion < 4) {
      // Add date columns and indexes for version 4
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN year INTEGER');
        await db.execute('ALTER TABLE transactions ADD COLUMN month INTEGER');
        await db.execute('ALTER TABLE transactions ADD COLUMN day INTEGER');
        await db.execute('ALTER TABLE transactions ADD COLUMN week INTEGER');
        
        // Create indexes for date queries
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transactions_time ON transactions(time)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transactions_year_month ON transactions(year, month)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transactions_year_month_day ON transactions(year, month, day)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transactions_bank_year_month ON transactions(bankId, year, month)');
        
        print("debug: Added date columns and indexes to transactions table");
        
        // Populate date columns for existing transactions
        final transactions = await db.query('transactions', columns: ['id', 'time']);
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
              print("debug: Error parsing date for transaction ${tx['id']}: $e");
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
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          essential INTEGER NOT NULL DEFAULT 0,
          iconKey TEXT,
          description TEXT,
          flow TEXT,
          recurring INTEGER NOT NULL DEFAULT 0
        )
      ''');

      try {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN categoryId INTEGER');
      } catch (e) {
        print("debug: Error adding categoryId column (might already exist): $e");
      }

      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_categoryId ON transactions(categoryId)');

      await _seedBuiltInCategories(db);
    }

    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE categories ADD COLUMN iconKey TEXT');
      } catch (e) {
        print("debug: Error adding iconKey column (might already exist): $e");
      }
      await _seedBuiltInCategories(db);
    }

    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE categories ADD COLUMN description TEXT');
      } catch (e) {
        print(
            "debug: Error adding description column (might already exist): $e");
      }
      await _seedBuiltInCategories(db);
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
  }

  Future<void> _seedBuiltInCategories(Database db) async {
    final batch = db.batch();
    for (final category in models.BuiltInCategories.all) {
      batch.insert(
        'categories',
        {
          'name': category.name,
          'essential': category.essential ? 1 : 0,
          'iconKey': category.iconKey,
          'description': category.description,
          'flow': category.flow,
          'recurring': category.recurring ? 1 : 0,
          'builtIn': category.builtIn ? 1 : 0,
          'builtInKey': category.builtInKey,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.update(
        'categories',
        {
          'iconKey': category.iconKey,
        },
        where:
            "builtInKey = ? AND (iconKey IS NULL OR iconKey = '')",
        whereArgs: [category.builtInKey],
      );
      batch.update(
        'categories',
        {
          'description': category.description,
        },
        where:
            "builtInKey = ? AND (description IS NULL OR description = '')",
        whereArgs: [category.builtInKey],
      );
      batch.update(
        'categories',
        {
          'builtIn': 1,
        },
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
          iconKey TEXT,
          description TEXT,
          flow TEXT NOT NULL DEFAULT 'expense',
          recurring INTEGER NOT NULL DEFAULT 0,
          builtIn INTEGER NOT NULL DEFAULT 0,
          builtInKey TEXT
        )
      ''');

      await txn.execute('''
        INSERT INTO categories_new (id, name, essential, iconKey, description, flow, recurring, builtIn, builtInKey)
        SELECT
          id,
          name,
          COALESCE(essential, 0),
          iconKey,
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
        "SELECT name FROM sqlite_master WHERE type='table' AND name='categories'");
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
    if (!names.contains('description')) {
      await addColumn('ALTER TABLE categories ADD COLUMN description TEXT');
    }
    if (!names.contains('flow')) {
      await addColumn('ALTER TABLE categories ADD COLUMN flow TEXT');
    }
    if (!names.contains('recurring')) {
      await addColumn(
          'ALTER TABLE categories ADD COLUMN recurring INTEGER');
    }
    if (!names.contains('builtIn')) {
      await addColumn(
          'ALTER TABLE categories ADD COLUMN builtIn INTEGER NOT NULL DEFAULT 0');
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
        columns: [
          'id',
        ],
        where: '''
          (builtInKey IS NULL OR TRIM(builtInKey) = '')
          AND flow = ?
          AND essential = ?
          AND recurring = ?
          AND (iconKey = ? OR iconKey IS NULL OR TRIM(iconKey) = '')
          AND (description = ? OR description IS NULL OR TRIM(description) = '')
        ''',
        whereArgs: [
          builtIn.flow,
          builtIn.essential ? 1 : 0,
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

      final looksBuiltIn = (iconKey == null || iconKey.isEmpty || iconKey == 'gift') &&
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
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
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
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
