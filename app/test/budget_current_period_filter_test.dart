import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/repositories/budget_repository.dart';
import 'package:totals/services/budget_alert_service.dart';
import 'package:totals/services/budget_service.dart';

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

  test(
    'current statuses and alerts ignore past and future budget segments',
    () async {
      final now = DateTime.now();
      final currentStart = DateTime(now.year, now.month);
      final nextStart = DateTime(now.year, now.month + 1);
      final previousStart = DateTime(now.year, now.month - 1);
      final currentEnd = nextStart.subtract(const Duration(seconds: 1));
      final previousEnd = currentStart.subtract(const Duration(seconds: 1));
      final categoryId = await _expenseCategoryId(db);
      final repository = BudgetRepository();

      final pastId = await repository.insertBudget(
        _budget(
          name: 'Utilities',
          amount: 4000,
          categoryId: categoryId,
          startDate: previousStart,
          endDate: previousEnd,
        ),
      );
      final currentId = await repository.insertBudget(
        _budget(
          name: 'Utilities',
          amount: 40000,
          categoryId: categoryId,
          startDate: currentStart,
          endDate: currentEnd,
        ),
      );
      final futureId = await repository.insertBudget(
        _budget(
          name: 'Utilities',
          amount: 4000,
          categoryId: categoryId,
          startDate: nextStart,
        ),
      );

      await db.insert('transactions', {
        'amount': 3756.0,
        'reference': 'current-utilities-expense',
        'time': DateTime(
          now.year,
          now.month,
          now.day,
          12,
        ).toIso8601String(),
        'type': 'DEBIT',
        'categoryId': categoryId,
        'categoryIds': '[$categoryId]',
        'year': now.year,
        'month': now.month,
        'day': now.day,
      });

      final service = BudgetService();
      final statuses = await service.getAllBudgetStatuses();

      expect(statuses, hasLength(1));
      expect(statuses.single.budget.id, currentId);
      expect(statuses.single.percentageUsed, closeTo(9.39, 0.001));
      expect(statuses.single.isApproachingLimit, isFalse);

      final categoryBudgets = await service.getBudgetsByCategory(categoryId);
      expect(categoryBudgets.map((budget) => budget.id), [currentId]);

      expect(
        await service.getCurrentBudgetStatus(
          (await repository.getBudgetById(pastId))!,
        ),
        isNull,
      );
      expect(
        await service.getCurrentBudgetStatus(
          (await repository.getBudgetById(futureId))!,
        ),
        isNull,
      );
      expect(await BudgetAlertService().checkBudgetAlerts(), isEmpty);
    },
  );
}

Future<int> _expenseCategoryId(Database db) async {
  final rows = await db.query(
    'categories',
    columns: const ['id'],
    where: 'flow = ?',
    whereArgs: const ['expense'],
    limit: 1,
  );
  return rows.single['id']! as int;
}

Budget _budget({
  required String name,
  required double amount,
  required int categoryId,
  required DateTime startDate,
  DateTime? endDate,
}) {
  return Budget(
    name: name,
    type: 'category',
    amount: amount,
    categoryId: categoryId,
    categoryIds: [categoryId],
    startDate: startDate,
    endDate: endDate,
    alertThreshold: 80,
    timeFrame: 'monthly',
    createdAt: DateTime.now(),
  );
}
