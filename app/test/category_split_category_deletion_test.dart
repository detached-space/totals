import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/category_repository.dart';

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
    await DatabaseHelper.instance.close();
    databasePath = '${await databaseFactoryFfi.getDatabasesPath()}/totals.db';
    await databaseFactoryFfi.deleteDatabase(databasePath);
    db = await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    if (db.isOpen) await DatabaseHelper.instance.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test('deleting a split category collapses the remaining allocation safely',
      () async {
    final repository = CategoryRepository();
    final groceries = await repository.createCategory(
      name: 'Groceries test',
      essential: true,
    );
    final household = await repository.createCategory(
      name: 'Household test',
      essential: true,
    );

    await db.insert('transactions', <String, Object?>{
      'amount': 100.0,
      'reference': 'category-delete-split',
      'type': 'DEBIT',
      'categoryId': groceries.id,
      'categoryIds': jsonEncode(<int>[groceries.id!, household.id!]),
      'categorySplits': jsonEncode(<Map<String, int>>[
        <String, int>{'categoryId': groceries.id!, 'amountMinor': 3000},
        <String, int>{'categoryId': household.id!, 'amountMinor': 7000},
      ]),
    });

    await repository.deleteCategory(groceries);

    final row = (await db.query(
      'transactions',
      where: 'reference = ?',
      whereArgs: const <Object>['category-delete-split'],
    ))
        .single;
    final transaction = Transaction.fromJson(row);
    expect(transaction.hasCategorySplit, isFalse);
    expect(transaction.categorySplits, isNull);
    expect(transaction.selectedCategoryIds, <int>[household.id!]);
  });
}
