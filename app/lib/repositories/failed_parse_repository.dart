import 'package:totals/database/database_helper.dart';
import 'package:totals/models/failed_parse.dart';

class FailedParseRepository {
  Future<List<FailedParse>> getAll() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps =
        await db.query('failed_parses', orderBy: 'timestamp DESC');

    return maps.map((map) {
      return FailedParse.fromJson({
        'id': map['id'],
        'address': map['address'],
        'body': map['body'],
        'reason': map['reason'],
        'timestamp': map['timestamp'],
      });
    }).toList();
  }

  Future<void> add(FailedParse item) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'failed_parses',
      {
        'address': item.address,
        'body': item.body,
        'reason': item.reason,
        'timestamp': item.timestamp,
      },
    );
  }

  Future<void> clear() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('failed_parses');
  }

  Future<void> deleteById(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'failed_parses',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'failed_parses',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}
