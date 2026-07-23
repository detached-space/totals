import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'helpers/sqlite_setup.dart';

void main() {
  setUpAll(() {
    setupSqlite();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Future<Database> openPreFixDatabase() async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY,
        amount REAL,
        reference TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE sms_patterns (
        id INTEGER PRIMARY KEY,
        bankId INTEGER,
        regex TEXT
      )
    ''');
    return db;
  }

  Future<Set<String>> columnNames(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((c) => c['name'] as String).toSet();
  }

  Future<String?> columnType(Database db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final match = info.where((c) => c['name'] == column);
    return match.isEmpty ? null : match.first['type'] as String?;
  }

  test('adds totalFee, hasFees, and mapping when missing', () async {
    final db = await openPreFixDatabase();

    expect(await columnNames(db, 'transactions'), isNot(contains('totalFee')));
    expect(await columnNames(db, 'sms_patterns'), isNot(contains('hasFees')));
    expect(await columnNames(db, 'sms_patterns'), isNot(contains('mapping')));

    await DatabaseHelper.instance.repairCoreV28(db);

    expect(await columnNames(db, 'transactions'), contains('totalFee'));
    expect(await columnNames(db, 'sms_patterns'), contains('hasFees'));
    expect(await columnNames(db, 'sms_patterns'), contains('mapping'));

    expect(await columnType(db, 'transactions', 'totalFee'), 'REAL');
    expect(await columnType(db, 'sms_patterns', 'hasFees'), 'INTEGER');
    expect(await columnType(db, 'sms_patterns', 'mapping'), 'TEXT');

    await db.close();
  });

  test('running it twice does not error or duplicate columns', () async {
    final db = await openPreFixDatabase();

    await DatabaseHelper.instance.repairCoreV28(db);
    await DatabaseHelper.instance.repairCoreV28(db);

    final txColumns = await db.rawQuery('PRAGMA table_info(transactions)');
    expect(txColumns.where((c) => c['name'] == 'totalFee').length, 1);

    final patternColumns = await db.rawQuery('PRAGMA table_info(sms_patterns)');
    expect(patternColumns.where((c) => c['name'] == 'hasFees').length, 1);
    expect(patternColumns.where((c) => c['name'] == 'mapping').length, 1);

    await db.close();
  });

  test('running it against a database that already has the columns is a no-op',
      () async {
    final db = await openPreFixDatabase();
    await db.execute('ALTER TABLE transactions ADD COLUMN totalFee REAL');
    await db.execute('ALTER TABLE sms_patterns ADD COLUMN hasFees INTEGER');
    await db.execute('ALTER TABLE sms_patterns ADD COLUMN mapping TEXT');

    await DatabaseHelper.instance.repairCoreV28(db);

    final txColumns = await db.rawQuery('PRAGMA table_info(transactions)');
    expect(txColumns.where((c) => c['name'] == 'totalFee').length, 1);

    final patternColumns = await db.rawQuery('PRAGMA table_info(sms_patterns)');
    expect(patternColumns.where((c) => c['name'] == 'hasFees').length, 1);
    expect(patternColumns.where((c) => c['name'] == 'mapping').length, 1);

    await db.close();
  });
}
