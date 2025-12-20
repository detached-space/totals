import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/category.dart' as models;

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
    }
    await batch.commit(noResult: true);
  }

  Future<List<models.Category>> getCategories() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'categories',
      orderBy: "flow ASC, essential DESC, name COLLATE NOCASE ASC",
    );
    return rows.map(models.Category.fromDb).toList();
  }

  Future<models.Category> createCategory({
    required String name,
    required bool essential,
    String? iconKey,
    String? description,
    String flow = 'expense',
    bool recurring = false,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final trimmed = name.trim();
    final id = await db.insert('categories', {
      'name': trimmed,
      'essential': essential ? 1 : 0,
      'iconKey': iconKey,
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
      iconKey: iconKey,
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
        'iconKey': category.iconKey,
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
      await txn.update(
        'transactions',
        {'categoryId': null},
        where: 'categoryId = ?',
        whereArgs: [category.id],
      );
      await txn.delete(
        'categories',
        where: 'id = ?',
        whereArgs: [category.id],
      );
    });
  }
}
