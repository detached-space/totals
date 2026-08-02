import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/services/data_export_import_service.dart';

/// Reproduces the Telegram-restore symptom ("imported successfully but empty")
/// with no device: seed a DB, exportAllData(), then importAllData() and check
/// the data survives. importAllData wipes each table before reinserting, so an
/// empty export — or an import that fails to repopulate — leaves an empty DB.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exportAllData -> importAllData round-trips accounts + transactions',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dbPath = p.join(await getDatabasesPath(), 'totals.db');
    await deleteDatabase(dbPath);

    // Create the v33 schema and seed one bank/account/transaction.
    final db = await DatabaseHelper.instance.database;
    await db.insert('banks', {
      'id': 3,
      'name': 'Awash Bank',
      'shortName': 'Awash',
      'codes': '["Awash"]',
      'image': '',
      'maskPattern': 0,
      'uniformMasking': 0,
      'simBased': 0,
    });
    await db.insert('accounts', {
      'accountNumber': '1000123456',
      'bank': 3,
      'balance': 500.0,
      'accountHolderName': 'Test User',
    });
    await db.insert('transactions', {
      'amount': 100.0,
      'reference': 'ROUNDTRIP-REF-1',
      'bankId': 3,
      'type': 'CREDIT',
      'accountNumber': '1000123456',
      'time': '2026-01-01T10:00:00.000',
    });

    // Export.
    final exported = await DataExportImportService().exportAllData();
    expect(exported.contains('ROUNDTRIP-REF-1'), isTrue,
        reason: 'export must contain the seeded transaction — an empty export '
            'is the backup bug');
    expect(exported.contains('1000123456'), isTrue,
        reason: 'export must contain the seeded account');

    // Import the export back (this wipes tables then reinserts).
    await DataExportImportService().importAllData(exported);

    // Verify the data survived the round-trip.
    final accounts = await db.query('accounts',
        where: 'accountNumber = ?', whereArgs: ['1000123456']);
    final txns = await db.query('transactions',
        where: 'reference = ?', whereArgs: ['ROUNDTRIP-REF-1']);
    expect(accounts, isNotEmpty,
        reason: 'account must survive export->import');
    expect(txns, isNotEmpty,
        reason: 'transaction must survive export->import');
  });
}
