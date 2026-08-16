import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/services/data_clear_service.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late String databasePath;

  setUpAll(() {
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
    await _seedClearableData(db);
  });

  tearDown(() async {
    if (db.isOpen) await DatabaseHelper.instance.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test('clears the newly exposed data groups without touching core data',
      () async {
    await DataClearService().clear(
      const ClearDataSelection(
        quickAccessAccounts: true,
        autoCategorization: true,
        loansAndDebts: true,
      ),
    );

    for (final table in const [
      'user_accounts',
      'auto_category_rules',
      'auto_category_prompt_dismissals',
      'receiver_category_mappings',
      'loan_debt_entries',
      'loan_debt_repayments',
    ]) {
      expect(await _count(db, table), 0, reason: table);
    }

    for (final table in const [
      'transactions',
      'accounts',
      'budgets',
      'failed_parses',
      'sms_patterns',
    ]) {
      expect(await _count(db, table), 1, reason: table);
    }
  });

  test('existing clear choices remain independent from the new groups',
      () async {
    await DataClearService().clear(
      const ClearDataSelection(
        financialData: true,
        budgets: true,
        failedParses: true,
      ),
    );

    for (final table in const [
      'transactions',
      'accounts',
      'budgets',
      'failed_parses',
    ]) {
      expect(await _count(db, table), 0, reason: table);
    }

    for (final table in const [
      'user_accounts',
      'auto_category_rules',
      'auto_category_prompt_dismissals',
      'receiver_category_mappings',
      'loan_debt_entries',
      'loan_debt_repayments',
      'sms_patterns',
    ]) {
      expect(await _count(db, table), 1, reason: table);
    }
  });

  test('clears transactions and accounts for only the selected banks',
      () async {
    await db.insert('accounts', {
      'accountNumber': 'second-owned-account',
      'bank': 2,
      'balance': 20,
      'accountHolderName': 'Owner',
    });
    await db.insert('transactions', {
      'amount': 11,
      'reference': 'bank-one-transaction',
      'bankId': 1,
    });
    await db.insert('transactions', {
      'amount': 22,
      'reference': 'bank-two-transaction',
      'bankId': 2,
    });

    await DataClearService().clear(
      const ClearDataSelection(
        financialData: true,
        bankIds: {1},
      ),
    );

    expect(await _countWhere(db, 'accounts', 'bank = ?', [1]), 0);
    expect(await _countWhere(db, 'accounts', 'bank = ?', [2]), 1);
    expect(await _countWhere(db, 'transactions', 'bankId = ?', [1]), 0);
    expect(await _countWhere(db, 'transactions', 'bankId = ?', [2]), 1);
    expect(
      await _countWhere(db, 'transactions', 'bankId IS NULL', const []),
      1,
    );
    expect(await _count(db, 'sms_patterns'), 1);
  });
}

Future<int> _count(Database db, String table) async {
  return Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $table'),
      ) ??
      0;
}

Future<int> _countWhere(
  Database db,
  String table,
  String where,
  List<Object?> whereArgs,
) async {
  return Sqflite.firstIntValue(
        await db.query(
          table,
          columns: const ['COUNT(*)'],
          where: where,
          whereArgs: whereArgs,
        ),
      ) ??
      0;
}

Future<void> _seedClearableData(Database db) async {
  for (final table in const [
    'loan_debt_repayments',
    'loan_debt_entries',
    'auto_category_prompt_dismissals',
    'auto_category_rules',
    'receiver_category_mappings',
    'user_accounts',
    'sms_patterns',
    'failed_parses',
    'budgets',
    'transactions',
    'accounts',
  ]) {
    await db.delete(table);
  }

  final now = DateTime(2026, 7, 24).toIso8601String();
  await db.insert('accounts', {
    'accountNumber': 'owned-account',
    'bank': 1,
    'balance': 10,
    'accountHolderName': 'Owner',
  });
  await db.insert('transactions', {
    'amount': 10,
    'reference': 'transaction-reference',
  });
  await db.insert('budgets', {
    'name': 'Monthly',
    'type': 'expense',
    'amount': 100,
    'startDate': now,
    'rollover': 0,
    'alertThreshold': 80,
    'isActive': 1,
    'createdAt': now,
    'calendar': 'gregorian',
  });
  await db.insert('failed_parses', {
    'address': 'Bank',
    'body': 'Unparsed',
    'reason': 'No match',
    'timestamp': now,
  });
  await db.insert('user_accounts', {
    'accountNumber': 'quick-access-account',
    'bankId': 1,
    'accountHolderName': 'Other Person',
    'createdAt': now,
  });
  await db.insert('auto_category_rules', {
    'counterparty': 'Shop',
    'normalizedCounterparty': 'shop',
    'flow': 'expense',
    'categoryId': 1,
    'isPrimary': 1,
    'createdAt': now,
  });
  await db.insert('auto_category_prompt_dismissals', {
    'counterparty': 'Cafe',
    'normalizedCounterparty': 'cafe',
    'flow': 'expense',
    'createdAt': now,
  });
  await db.insert('receiver_category_mappings', {
    'accountNumber': 'merchant',
    'categoryId': 1,
    'accountType': 'receiver',
    'createdAt': now,
  });
  await db.insert('loan_debt_entries', {
    'transactionReference': 'transaction-reference',
    'personName': 'Person',
    'direction': 'lent',
    'status': 'active',
    'source': 'transaction',
    'createdAt': now,
    'updatedAt': now,
  });
  await db.insert('loan_debt_repayments', {
    'repaymentTransactionReference': 'repayment-reference',
    'loanDebtTransactionReference': 'transaction-reference',
    'appliedAmount': 1,
    'createdAt': now,
    'updatedAt': now,
  });
  await db.insert('sms_patterns', {
    'bankId': 1,
    'senderId': 'Bank',
    'regex': 'amount',
    'type': 'DEBIT',
    'description': 'Pattern',
  });
}
