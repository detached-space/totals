import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/user_account.dart';

class UserAccountRepository {
  Future<List<UserAccount>> getUserAccounts() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'user_accounts',
      orderBy: 'createdAt DESC',
    );

    return maps
        .map((map) => UserAccount.fromJson({
              'id': map['id'],
              'accountNumber': map['accountNumber'],
              'bankId': map['bankId'],
              'accountHolderName': map['accountHolderName'],
              'createdAt': map['createdAt'],
            }))
        .toList();
  }

  Future<int> saveUserAccount(UserAccount account) async {
    final db = await DatabaseHelper.instance.database;
    return await db.insert(
      'user_accounts',
      account.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteUserAccount(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'user_accounts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteUserAccountByNumberAndBank(
      String accountNumber, int bankId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'user_accounts',
      where: 'accountNumber = ? AND bankId = ?',
      whereArgs: [accountNumber, bankId],
    );
  }

  Future<void> clearAll() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('user_accounts');
  }

  Future<bool> userAccountExists(String accountNumber, int bankId) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
      'user_accounts',
      where: 'accountNumber = ? AND bankId = ?',
      whereArgs: [accountNumber, bankId],
      limit: 1,
    );
    return result.isNotEmpty;
  }
}
