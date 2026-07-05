import 'package:totals/database/database_helper.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/services/data_sync/sync_enqueuer.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/theme/app_calendar_option.dart';
import 'package:totals/utils/app_calendar_date_utils.dart';

class BudgetRepository {
  String? _normalizeCalendar(String? calendar) {
    final value = calendar?.trim();
    if (value == null || value.isEmpty) return null;
    return AppCalendarOption.fromStorage(value).storageValue;
  }

  Future<List<Budget>> getAllBudgets({String? calendar}) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedCalendar = _normalizeCalendar(calendar);
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: normalizedCalendar == null ? null : 'calendar = ?',
      whereArgs: normalizedCalendar == null ? null : [normalizedCalendar],
      orderBy: 'createdAt DESC',
    );

    return maps.map<Budget>((map) => Budget.fromDb(map)).toList();
  }

  Future<List<Budget>> getActiveBudgets({String? calendar}) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedCalendar = _normalizeCalendar(calendar);
    final where = <String>['isActive = ?'];
    final whereArgs = <Object?>[1];
    if (normalizedCalendar != null) {
      where.add('calendar = ?');
      whereArgs.add(normalizedCalendar);
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
    );

    return maps.map<Budget>((map) => Budget.fromDb(map)).toList();
  }

  Future<List<Budget>> getBudgetsByType(String type, {String? calendar}) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedCalendar = _normalizeCalendar(calendar);
    final where = <String>['type = ?', 'isActive = ?'];
    final whereArgs = <Object?>[type, 1];
    if (normalizedCalendar != null) {
      where.add('calendar = ?');
      whereArgs.add(normalizedCalendar);
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
    );

    return maps.map<Budget>((map) => Budget.fromDb(map)).toList();
  }

  Future<List<Budget>> getCategoryBudgets({String? calendar}) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedCalendar = _normalizeCalendar(calendar);
    final where = <String>['type = ?', 'isActive = ?'];
    final whereArgs = <Object?>['category', 1];
    if (normalizedCalendar != null) {
      where.add('calendar = ?');
      whereArgs.add(normalizedCalendar);
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
    );

    return maps.map<Budget>((map) => Budget.fromDb(map)).toList();
  }

  Future<List<Budget>> getBudgetsByCategory(
    int categoryId, {
    String? calendar,
  }) async {
    final budgets = await getActiveBudgets(calendar: calendar);
    return budgets.where((b) => b.includesCategory(categoryId)).toList();
  }

  Future<Budget?> getBudgetById(int id) async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Budget.fromDb(maps.first);
  }

  Future<int> insertBudget(Budget budget) async {
    final db = await DatabaseHelper.instance.database;
    final data = budget.toDb();
    data.remove('id'); // Remove id for insert
    data['updatedAt'] = DateTime.now().toIso8601String();
    final id = await db.insert('budgets', data);
    await SyncEnqueuer.instance.onEntityWritten(
      entity: SyncEntity.budgets,
      entityRef: 'budget:$id',
      op: SyncOp.upsert,
      row: {...data, 'id': id},
    );
    return id;
  }

  Future<int> updateBudget(Budget budget) async {
    final db = await DatabaseHelper.instance.database;
    final data = budget.toDb();
    data['updatedAt'] = DateTime.now().toIso8601String();
    final result = await db.update(
      'budgets',
      data,
      where: 'id = ?',
      whereArgs: [budget.id],
    );
    if (budget.id != null) {
      await SyncEnqueuer.instance.onEntityWritten(
        entity: SyncEntity.budgets,
        entityRef: 'budget:${budget.id}',
        op: SyncOp.upsert,
        row: data,
      );
    }
    return result;
  }

  /// Applies edits only to the given month while preserving original values
  /// for months after the selected one.
  Future<int> updateBudgetForMonthOnly({
    required Budget originalBudget,
    required Budget editedBudget,
    required DateTime month,
    bool keepFutureSegment = true,
  }) async {
    if (originalBudget.id == null) {
      throw ArgumentError('Original budget must have an id.');
    }

    final db = await DatabaseHelper.instance.database;
    final calendar = AppCalendarOption.fromStorage(editedBudget.calendar);
    final monthStart = AppCalendarDateUtils.monthStart(
      month,
      calendar: calendar,
    );
    final nextMonthStart = AppCalendarDateUtils.nextMonthStart(
      month,
      calendar: calendar,
    );
    final monthEnd = nextMonthStart.subtract(const Duration(seconds: 1));
    final originalEnd = originalBudget.endDate;
    final hadPastSegment = originalBudget.startDate.isBefore(monthStart);
    final hasFutureSegment = keepFutureSegment &&
        (originalEnd == null || originalEnd.isAfter(monthEnd));
    final nowIso = DateTime.now().toIso8601String();

    late int editedBudgetId;

    await db.transaction((txn) async {
      final editedData = editedBudget
          .copyWith(
            startDate: monthStart,
            endDate: monthEnd,
          )
          .toDb();
      editedData.remove('id');
      editedData['updatedAt'] = nowIso;

      if (hadPastSegment) {
        await txn.update(
          'budgets',
          {
            'endDate': monthStart
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
            'updatedAt': nowIso,
          },
          where: 'id = ?',
          whereArgs: [originalBudget.id],
        );

        editedBudgetId = await txn.insert('budgets', editedData);
      } else {
        await txn.update(
          'budgets',
          editedData,
          where: 'id = ?',
          whereArgs: [originalBudget.id],
        );
        editedBudgetId = originalBudget.id!;
      }

      if (hasFutureSegment) {
        final futureData = originalBudget
            .copyWith(
              id: null,
              startDate: nextMonthStart,
              endDate: originalEnd,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            )
            .toDb();
        futureData.remove('id');
        futureData['updatedAt'] = nowIso;
        await txn.insert('budgets', futureData);
      }
    });

    return editedBudgetId;
  }

  Future<int> deleteBudget(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'budgets',
      columns: const ['id', 'name'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final name = rows.isEmpty ? null : rows.first['name'] as String?;
    final result = await db.delete(
      'budgets',
      where: 'id = ?',
      whereArgs: [id],
    );
    await SyncEnqueuer.instance.onEntityWritten(
      entity: SyncEntity.budgets,
      entityRef: 'budget:$id',
      op: SyncOp.delete,
      deleteSnapshot: {
        'id': id,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      },
    );
    return result;
  }

  Future<void> deleteBudgetForMonth({
    required Budget originalBudget,
    required DateTime month,
    bool deleteFutureBudgets = false,
  }) async {
    if (originalBudget.id == null) {
      throw ArgumentError('Original budget must have an id.');
    }

    final db = await DatabaseHelper.instance.database;
    final calendar = AppCalendarOption.fromStorage(originalBudget.calendar);
    final monthStart = AppCalendarDateUtils.monthStart(
      month,
      calendar: calendar,
    );
    final nextMonthStart = AppCalendarDateUtils.nextMonthStart(
      month,
      calendar: calendar,
    );
    final monthEnd = nextMonthStart.subtract(const Duration(seconds: 1));
    final originalEnd = originalBudget.endDate;
    final hadPastSegment = originalBudget.startDate.isBefore(monthStart);
    final hasFutureSegment =
        originalEnd == null || originalEnd.isAfter(monthEnd);
    final nowIso = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      if (deleteFutureBudgets) {
        if (hadPastSegment) {
          await txn.update(
            'budgets',
            {
              'endDate': monthStart
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
              'updatedAt': nowIso,
            },
            where: 'id = ?',
            whereArgs: [originalBudget.id],
          );
        } else {
          await txn.delete(
            'budgets',
            where: 'id = ?',
            whereArgs: [originalBudget.id],
          );
        }
        return;
      }

      if (hadPastSegment && hasFutureSegment) {
        await txn.update(
          'budgets',
          {
            'endDate': monthStart
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
            'updatedAt': nowIso,
          },
          where: 'id = ?',
          whereArgs: [originalBudget.id],
        );

        final futureData = originalBudget
            .copyWith(
              id: null,
              startDate: nextMonthStart,
              endDate: originalEnd,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            )
            .toDb();
        futureData.remove('id');
        futureData['updatedAt'] = nowIso;
        await txn.insert('budgets', futureData);
        return;
      }

      if (hadPastSegment) {
        await txn.update(
          'budgets',
          {
            'endDate': monthStart
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
            'updatedAt': nowIso,
          },
          where: 'id = ?',
          whereArgs: [originalBudget.id],
        );
        return;
      }

      if (hasFutureSegment) {
        await txn.update(
          'budgets',
          {
            'startDate': nextMonthStart.toIso8601String(),
            'updatedAt': nowIso,
          },
          where: 'id = ?',
          whereArgs: [originalBudget.id],
        );
        return;
      }

      await txn.delete(
        'budgets',
        where: 'id = ?',
        whereArgs: [originalBudget.id],
      );
    });
  }

  Future<void> deactivateBudget(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'budgets',
      {
        'isActive': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> activateBudget(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'budgets',
      {
        'isActive': 1,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAll() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('budgets');
  }

  // Get active budgets for current period
  Future<List<Budget>> getActiveBudgetsForCurrentPeriod(
    String type, {
    String? calendar,
  }) async {
    final now = DateTime.now();
    final db = await DatabaseHelper.instance.database;
    final normalizedCalendar = _normalizeCalendar(calendar);
    final calendarOption = AppCalendarOption.fromStorage(normalizedCalendar);

    DateTime periodStart;
    DateTime periodEnd;

    switch (type) {
      case 'daily':
        periodStart = AppCalendarDateUtils.periodStart(
          now,
          'daily',
          calendar: calendarOption,
        );
        periodEnd = AppCalendarDateUtils.periodEndInclusive(
          periodStart,
          'daily',
          calendar: calendarOption,
        );
        break;
      case 'monthly':
        periodStart = AppCalendarDateUtils.periodStart(
          now,
          'monthly',
          calendar: calendarOption,
        );
        periodEnd = AppCalendarDateUtils.periodEndInclusive(
          periodStart,
          'monthly',
          calendar: calendarOption,
        );
        break;
      case 'yearly':
        periodStart = AppCalendarDateUtils.periodStart(
          now,
          'yearly',
          calendar: calendarOption,
        );
        periodEnd = AppCalendarDateUtils.periodEndInclusive(
          periodStart,
          'yearly',
          calendar: calendarOption,
        );
        break;
      default:
        periodStart = AppCalendarDateUtils.periodStart(
          now,
          'monthly',
          calendar: calendarOption,
        );
        periodEnd = AppCalendarDateUtils.periodEndInclusive(
          periodStart,
          'monthly',
          calendar: calendarOption,
        );
    }

    final where = <String>[
      'type = ?',
      'isActive = ?',
      'startDate <= ?',
      '(endDate IS NULL OR endDate >= ?)',
    ];
    final whereArgs = <Object?>[
      type,
      1,
      periodEnd.toIso8601String(),
      periodStart.toIso8601String(),
    ];
    if (normalizedCalendar != null) {
      where.add('calendar = ?');
      whereArgs.add(normalizedCalendar);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
    );

    return maps.map<Budget>((map) => Budget.fromDb(map)).toList();
  }
}
