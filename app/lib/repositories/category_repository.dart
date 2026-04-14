import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/category.dart' as models;
import 'package:totals/services/auto_categorization_service.dart';

class CategoryRepository {
  Future<void> ensureSeeded() async {
    final db = await DatabaseHelper.instance.database;
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
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.update(
        'categories',
        {
          'iconKey': category.iconKey,
        },
        where: "builtInKey = ? AND (iconKey IS NULL OR iconKey = '')",
        whereArgs: [category.builtInKey],
      );
      batch.update(
        'categories',
        {
          'description': category.description,
        },
        where: "builtInKey = ? AND (description IS NULL OR description = '')",
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
      batch.update(
        'categories',
        {
          'uncategorized': category.uncategorized ? 1 : 0,
        },
        where: "builtInKey = ?",
        whereArgs: [category.builtInKey],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<models.Category>> getCategories() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'categories',
      orderBy:
          "flow ASC, uncategorized ASC, essential DESC, name COLLATE NOCASE ASC",
    );
    return rows.map(models.Category.fromDb).toList();
  }

  Future<models.Category> createCategory({
    required String name,
    required bool essential,
    bool uncategorized = false,
    String? iconKey,
    String? colorKey,
    String? description,
    String flow = 'expense',
    bool recurring = false,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final trimmed = name.trim();
    final id = await db.insert('categories', {
      'name': trimmed,
      'essential': essential ? 1 : 0,
      'uncategorized': uncategorized ? 1 : 0,
      'iconKey': iconKey,
      'colorKey': colorKey,
      'description': description,
      'flow': flow,
      'recurring': recurring ? 1 : 0,
      'builtIn': 0,
      'builtInKey': null,
    });
    return models.Category(
      id: id,
      name: trimmed,
      essential: essential,
      uncategorized: uncategorized,
      iconKey: iconKey,
      colorKey: colorKey,
      description: description,
      flow: flow,
      recurring: recurring,
      builtIn: false,
      builtInKey: null,
    );
  }

  Future<void> updateCategory(models.Category category) async {
    if (category.id == null) return;
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'categories',
      {
        'name': category.name.trim(),
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
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<void> deleteCategory(models.Category category) async {
    if (category.id == null) return;
    if (category.builtIn) {
      throw StateError('Built-in categories cannot be deleted');
    }
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final affectedTransactions = await txn.query(
        'transactions',
        columns: ['id', 'categoryId', 'categoryIds'],
        where: 'categoryId = ? OR categoryIds IS NOT NULL',
        whereArgs: [category.id],
      );

      List<int> decodeCategoryIds(dynamic raw) {
        if (raw == null) return const <int>[];
        if (raw is String && raw.trim().isEmpty) return const <int>[];
        try {
          final decoded = raw is String ? jsonDecode(raw) : raw;
          if (decoded is! List) return const <int>[];
          return decoded
              .map((value) {
                if (value is int) return value;
                if (value is num) return value.toInt();
                if (value is String) return int.tryParse(value.trim());
                return null;
              })
              .whereType<int>()
              .toList(growable: false);
        } catch (_) {
          return const <int>[];
        }
      }

      final batch = txn.batch();
      for (final row in affectedTransactions) {
        final transactionId = row['id'] as int?;
        if (transactionId == null) continue;

        final selectedCategoryIds =
            decodeCategoryIds(row['categoryIds']).toList(growable: true);
        final primaryCategoryId = row['categoryId'] as int?;
        if (primaryCategoryId != null &&
            primaryCategoryId > 0 &&
            !selectedCategoryIds.contains(primaryCategoryId)) {
          selectedCategoryIds.insert(0, primaryCategoryId);
        }

        if (!selectedCategoryIds.contains(category.id)) {
          continue;
        }

        final remainingIds = selectedCategoryIds
            .where((id) => id != category.id)
            .toSet()
            .toList(growable: false);

        batch.update(
          'transactions',
          {
            'categoryId': remainingIds.isEmpty ? null : remainingIds.first,
            'categoryIds':
                remainingIds.isEmpty ? null : jsonEncode(remainingIds),
          },
          where: 'id = ?',
          whereArgs: [transactionId],
        );
      }
      await batch.commit(noResult: true);

      await txn.delete(
        'categories',
        where: 'id = ?',
        whereArgs: [category.id],
      );
    });
    await AutoCategorizationService.instance
        .deleteRulesForCategory(category.id!);
  }
}
