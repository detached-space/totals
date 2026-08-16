import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/category.dart' as models;
import 'package:totals/models/transaction_category_split.dart';
import 'package:totals/services/auto_categorization_service.dart';
import 'package:totals/utils/reimbursement_utils.dart';

class CategoryRepository {
  Future<void> ensureSeeded() async {
    final db = await DatabaseHelper.instance.database;
    final reimbursementDefinition = models.BuiltInCategories.all.firstWhere(
      (category) => category.builtInKey == reimbursementBuiltInKey,
    );
    await _ensureReimbursementSeeded(db, reimbursementDefinition);
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
      if (category.builtInKey == 'income_refund') {
        batch.update(
          'categories',
          {'description': category.description},
          where: '''
            builtInKey = ?
            AND (
              description IS NULL
              OR TRIM(description) = ''
              OR description = ?
            )
          ''',
          whereArgs: const [
            'income_refund',
            'Refunds and reimbursements',
          ],
        );
      }
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
      if (category.builtInKey == reimbursementBuiltInKey) {
        batch.update(
          'categories',
          {
            'flow': 'income',
            'builtIn': 1,
          },
          where: 'builtInKey = ?',
          whereArgs: [category.builtInKey],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _ensureReimbursementSeeded(
    Database db,
    models.Category definition,
  ) async {
    final existing = await db.query(
      'categories',
      columns: const ['id'],
      where: 'builtInKey = ?',
      whereArgs: const [reimbursementBuiltInKey],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    var name = definition.name;
    var suffix = 1;
    while ((await db.query(
      'categories',
      columns: const ['id'],
      where: 'name = ? COLLATE NOCASE AND flow = ?',
      whereArgs: [name, definition.flow],
      limit: 1,
    ))
        .isNotEmpty) {
      name = suffix == 1
          ? '${definition.name} (Totals)'
          : '${definition.name} (Totals $suffix)';
      suffix++;
    }

    await db.insert(
      'categories',
      {
        'name': name,
        'essential': definition.essential ? 1 : 0,
        'uncategorized': definition.uncategorized ? 1 : 0,
        'iconKey': definition.iconKey,
        'colorKey': definition.colorKey,
        'description': definition.description,
        'flow': 'income',
        'recurring': definition.recurring ? 1 : 0,
        'builtIn': 1,
        'builtInKey': reimbursementBuiltInKey,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
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
        columns: ['id', 'categoryId', 'categoryIds', 'categorySplits'],
        where:
            'categoryId = ? OR categoryIds IS NOT NULL OR categorySplits IS NOT NULL',
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

      List<TransactionCategorySplit> decodeCategorySplits(dynamic raw) {
        if (raw == null || (raw is String && raw.trim().isEmpty)) {
          return const <TransactionCategorySplit>[];
        }
        try {
          final decoded = raw is String ? jsonDecode(raw) : raw;
          if (decoded is! Iterable) {
            return const <TransactionCategorySplit>[];
          }
          return decoded
              .whereType<Map<Object?, Object?>>()
              .map(
                (value) => TransactionCategorySplit.fromJson(
                  Map<String, dynamic>.from(
                    value.map(
                      (key, entry) => MapEntry(key.toString(), entry),
                    ),
                  ),
                ),
              )
              .where((split) => split.categoryId > 0 && split.amountMinor > 0)
              .toList(growable: false);
        } catch (_) {
          return const <TransactionCategorySplit>[];
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

        final categorySplits = decodeCategorySplits(row['categorySplits']);
        if (!selectedCategoryIds.contains(category.id) &&
            !categorySplits.any((split) => split.categoryId == category.id)) {
          continue;
        }

        var remainingIds = selectedCategoryIds
            .where((id) => id != category.id)
            .toSet()
            .toList(growable: false);
        String? encodedCategorySplits = row['categorySplits']?.toString();
        final removedSplitAmount = categorySplits
            .where((split) => split.categoryId == category.id)
            .fold<int>(0, (sum, split) => sum + split.amountMinor);
        if (removedSplitAmount > 0) {
          final remainingSplits = categorySplits
              .where((split) => split.categoryId != category.id)
              .toList(growable: true);
          if (remainingSplits.length >= 2) {
            final first = remainingSplits.first;
            remainingSplits[0] = TransactionCategorySplit(
              categoryId: first.categoryId,
              amountMinor: first.amountMinor + removedSplitAmount,
            );
            remainingIds = remainingSplits
                .map((split) => split.categoryId)
                .toList(growable: false);
            encodedCategorySplits = jsonEncode(
              remainingSplits.map((split) => split.toJson()).toList(),
            );
          } else {
            if (remainingSplits.length == 1) {
              remainingIds = <int>[remainingSplits.single.categoryId];
            }
            encodedCategorySplits = null;
          }
        }

        batch.update(
          'transactions',
          {
            'categoryId': remainingIds.isEmpty ? null : remainingIds.first,
            'categoryIds':
                remainingIds.isEmpty ? null : jsonEncode(remainingIds),
            'categorySplits': encodedCategorySplits,
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
