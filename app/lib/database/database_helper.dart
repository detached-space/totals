import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
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
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
