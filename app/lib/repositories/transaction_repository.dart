import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/transaction.dart';

class TransactionRepository {
  Future<List<Transaction>> getTransactions() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps =
        await db.query('transactions', orderBy: 'time DESC, id DESC');

    return maps.map<Transaction>((map) {
      return Transaction.fromJson({
        'amount': map['amount'],
        'reference': map['reference'],
        'creditor': map['creditor'],
        'receiver': map['receiver'],
        'time': map['time'],
        'status': map['status'],
        'currentBalance': map['currentBalance'],
        'bankId': map['bankId'],
        'type': map['type'],
        'transactionLink': map['transactionLink'],
        'accountNumber': map['accountNumber'],
      });
    }).toList();
  }

  Future<void> saveTransaction(Transaction transaction) async {
    final db = await DatabaseHelper.instance.database;

    await db.insert(
      'transactions',
      {
        'amount': transaction.amount,
        'reference': transaction.reference,
        'creditor': transaction.creditor,
        'receiver': transaction.receiver,
        'time': transaction.time,
        'status': transaction.status,
        'currentBalance': transaction.currentBalance,
        'bankId': transaction.bankId,
        'type': transaction.type,
        'transactionLink': transaction.transactionLink,
        'accountNumber': transaction.accountNumber,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveAllTransactions(List<Transaction> transactions) async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();

    for (var transaction in transactions) {
      batch.insert(
        'transactions',
        {
          'amount': transaction.amount,
          'reference': transaction.reference,
          'creditor': transaction.creditor,
          'receiver': transaction.receiver,
          'time': transaction.time,
          'status': transaction.status,
          'currentBalance': transaction.currentBalance,
          'bankId': transaction.bankId,
          'type': transaction.type,
          'transactionLink': transaction.transactionLink,
          'accountNumber': transaction.accountNumber,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> clearAll() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('transactions');
  }
}
