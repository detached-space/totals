import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/category.dart';

class CategoryRepository {
  Future<void> ensureSeeded() async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (final category in BuiltInCategories.all) {
      batch.insert(
        'categories',
        {
          'name': category.name,
          'essential': category.essential ? 1 : 0,
          'iconKey': category.iconKey,
          'description': category.description,
          'flow': category.flow,
          'recurring': category.recurring ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.update(
        'categories',
        {
          'iconKey': category.iconKey,
        },
        where: "name = ? AND (iconKey IS NULL OR iconKey = '')",
        whereArgs: [category.name],
      );
      batch.update(
        'categories',
        {
          'description': category.description,
        },
        where: "name = ? AND (description IS NULL OR description = '')",
        whereArgs: [category.name],
      );
      batch.update(
        'categories',
        {
          'flow': category.flow,
        },
        where: "name = ? AND (flow IS NULL OR flow = '')",
        whereArgs: [category.name],
      );
      batch.update(
        'categories',
        {
          'recurring': category.recurring ? 1 : 0,
        },
        where: "name = ? AND recurring IS NULL",
        whereArgs: [category.name],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Category>> getCategories() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'categories',
      orderBy: "flow ASC, essential DESC, name COLLATE NOCASE ASC",
    );
    return rows.map(Category.fromDb).toList();
  }

  Future<Category> createCategory({
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
    });
    return Category(
      id: id,
      name: trimmed,
      essential: essential,
      iconKey: iconKey,
      description: description,
      flow: flow,
      recurring: recurring,
    );
  }

  Future<void> updateCategory(Category category) async {
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
      },
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }
}
