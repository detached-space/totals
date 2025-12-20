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
        'categoryId': map['categoryId'],
      });
    }).toList();
  }

  Future<void> saveTransaction(Transaction transaction) async {
    final db = await DatabaseHelper.instance.database;

    // Parse and extract date components for faster queries
    int? year, month, day, week;
    if (transaction.time != null) {
      try {
        final date = DateTime.parse(transaction.time!);
        year = date.year;
        month = date.month;
        day = date.day;
        week = ((date.day - 1) ~/ 7) + 1;
      } catch (e) {
        // Handle parse error - date columns will remain null
      }
    }

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
        'categoryId': transaction.categoryId,
        'year': year,
        'month': month,
        'day': day,
        'week': week,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveAllTransactions(List<Transaction> transactions) async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();

    for (var transaction in transactions) {
      // Parse and extract date components for faster queries
      int? year, month, day, week;
      if (transaction.time != null) {
        try {
          final date = DateTime.parse(transaction.time!);
          year = date.year;
          month = date.month;
          day = date.day;
          week = ((date.day - 1) ~/ 7) + 1;
        } catch (e) {
          // Handle parse error - date columns will remain null
        }
      }

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
          'categoryId': transaction.categoryId,
          'year': year,
          'month': month,
          'day': day,
          'week': week,
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

  /// Get transactions by date range with optional filters
  /// Uses indexed date columns for fast queries
  Future<List<Transaction>> getTransactionsByDateRange(
    DateTime startDate,
    DateTime endDate, {
    int? bankId,
    String? type,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final startYear = startDate.year;
    final startMonth = startDate.month;
    final startDay = startDate.day;
    final endYear = endDate.year;
    final endMonth = endDate.month;
    final endDay = endDate.day;

    // Build WHERE clause using date columns for fast indexed queries
    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    // Date range condition using indexed columns
    whereParts.add(
      '(year > ? OR (year = ? AND month > ?) OR (year = ? AND month = ? AND day >= ?)) '
      'AND (year < ? OR (year = ? AND month < ?) OR (year = ? AND month = ? AND day <= ?))',
    );
    whereArgs.addAll([
      startYear,
      startYear,
      startMonth,
      startYear,
      startMonth,
      startDay,
      endYear,
      endYear,
      endMonth,
      endYear,
      endMonth,
      endDay,
    ]);

    if (bankId != null) {
      whereParts.add('bankId = ?');
      whereArgs.add(bankId);
    }

    if (type != null) {
      whereParts.add('type = ?');
      whereArgs.add(type);
    }

    final where = whereParts.join(' AND ');

    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'time DESC, id DESC',
    );

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
        'categoryId': map['categoryId'],
      });
    }).toList();
  }

  /// Get transactions by month with optional bank filter
  /// Uses indexed date columns for fast queries
  Future<List<Transaction>> getTransactionsByMonth(
    int year,
    int month, {
    int? bankId,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final whereParts = <String>['year = ? AND month = ?'];
    final whereArgs = <dynamic>[year, month];

    if (bankId != null) {
      whereParts.add('bankId = ?');
      whereArgs.add(bankId);
    }

    final where = whereParts.join(' AND ');

    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'time DESC, id DESC',
    );

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
        'categoryId': map['categoryId'],
      });
    }).toList();
  }

  /// Get transactions by week with optional filters
  /// Uses indexed date columns for fast queries
  Future<List<Transaction>> getTransactionsByWeek(
    DateTime weekStart,
    DateTime weekEnd, {
    int? bankId,
    String? type,
  }) async {
    return getTransactionsByDateRange(weekStart, weekEnd, bankId: bankId, type: type);
  }

  /// Delete transactions associated with an account
  /// Uses the same matching logic as TransactionProvider to identify transactions
  Future<void> deleteTransactionsByAccount(String accountNumber, int bank) async {
    final db = await DatabaseHelper.instance.database;
    
    // For banks that match by bankId only (Awash=2, Telebirr=6), delete all transactions for that bank
    if (bank == 2 || bank == 6) {
      await db.delete(
        'transactions',
        where: 'bankId = ?',
        whereArgs: [bank],
      );
      return;
    }
    
    // For other banks, match by accountNumber substring logic
    String? accountSuffix;
    
    if (bank == 1 && accountNumber.length >= 4) {
      // CBE: last 4 digits
      accountSuffix = accountNumber.substring(accountNumber.length - 4);
    } else if (bank == 4 && accountNumber.length >= 3) {
      // Dashen: last 3 digits
      accountSuffix = accountNumber.substring(accountNumber.length - 3);
    } else if (bank == 3 && accountNumber.length >= 2) {
      // Bank of Abyssinia: last 2 digits
      accountSuffix = accountNumber.substring(accountNumber.length - 2);
    }
    
    if (accountSuffix != null) {
      // Delete transactions where bankId matches and accountNumber ends with the suffix
      // Using SQL LIKE pattern matching to match the suffix at the end
      await db.delete(
        'transactions',
        where: 'bankId = ? AND accountNumber IS NOT NULL AND accountNumber LIKE ?',
        whereArgs: [bank, '%$accountSuffix'],
      );
    } else {
      // Fallback: delete all transactions for this bank (except NULL accountNumber ones)
      await db.delete(
        'transactions',
        where: 'bankId = ? AND accountNumber IS NOT NULL',
        whereArgs: [bank],
      );
    }
  }
}
