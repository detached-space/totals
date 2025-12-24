import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/transaction.dart' as models;
import 'package:totals/models/failed_parse.dart';
import 'package:totals/models/sms_pattern.dart';
import 'package:totals/models/account.dart';
import 'package:sqflite/sqflite.dart';

class MigrationHelper {
  static const String _migrationKey = 'migrated_to_sqlite_v1';

  /// Migrates data from SharedPreferences to SQLite
  /// Returns true if migration was performed, false if already migrated
  static Future<bool> migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool(_migrationKey) ?? false;

    if (migrated) {
      print("debug: Migration already completed");
      return false;
    }

    print("debug: Starting migration from SharedPreferences to SQLite...");
    final db = await DatabaseHelper.instance.database;

    try {
      // Migrate transactions
      await _migrateTransactions(prefs, db);

      // Migrate failed parses
      await _migrateFailedParses(prefs, db);

      // Migrate SMS patterns
      await _migrateSmsPatterns(prefs, db);

      // Migrate accounts
      await _migrateAccounts(prefs, db);

      // Mark migration as complete
      await prefs.setBool(_migrationKey, true);
      print("debug: Migration completed successfully");
      return true;
    } catch (e) {
      print("debug: Migration error: $e");
      rethrow;
    }
  }

  static Future<void> _migrateTransactions(
      SharedPreferences prefs, Database db) async {
    const String key = "transactions";
    final List<String>? transactionsList = prefs.getStringList(key);

    if (transactionsList == null || transactionsList.isEmpty) {
      print("debug: No transactions to migrate");
      return;
    }

    final batch = db.batch();
    int count = 0;

    for (var jsonStr in transactionsList) {
      try {
        final json = jsonDecode(jsonStr);
        final transaction = models.Transaction.fromJson(json);

        batch.insert(
          'transactions',
          {
            'amount': transaction.amount,
            'reference': transaction.reference,
            'creditor': transaction.creditor,
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
        count++;
      } catch (e) {
        print("debug: Error migrating transaction: $e");
      }
    }

    if (count > 0) {
      await batch.commit(noResult: true);
      print("debug: Migrated $count transactions");
    }
  }

  static Future<void> _migrateFailedParses(
      SharedPreferences prefs, Database db) async {
    const String key = "failed_parses_v1";
    final List<String>? raw = prefs.getStringList(key);

    if (raw == null || raw.isEmpty) {
      print("debug: No failed parses to migrate");
      return;
    }

    final batch = db.batch();
    int count = 0;

    for (var jsonStr in raw) {
      try {
        final json = jsonDecode(jsonStr);
        final failedParse = FailedParse.fromJson(json);

        batch.insert('failed_parses', {
          'address': failedParse.address,
          'body': failedParse.body,
          'reason': failedParse.reason,
          'timestamp': failedParse.timestamp,
        });
        count++;
      } catch (e) {
        print("debug: Error migrating failed parse: $e");
      }
    }

    if (count > 0) {
      await batch.commit(noResult: true);
      print("debug: Migrated $count failed parses");
    }
  }

  static Future<void> _migrateSmsPatterns(
      SharedPreferences prefs, Database db) async {
    const String key = "sms_patterns_config_v3";
    final List<String>? storedPatterns = prefs.getStringList(key);

    if (storedPatterns == null || storedPatterns.isEmpty) {
      print("debug: No SMS patterns to migrate");
      return;
    }

    final batch = db.batch();
    int count = 0;

    for (var jsonStr in storedPatterns) {
      try {
        final json = jsonDecode(jsonStr);
        final pattern = SmsPattern.fromJson(json);

        batch.insert('sms_patterns', {
          'bankId': pattern.bankId,
          'senderId': pattern.senderId,
          'regex': pattern.regex,
          'type': pattern.type,
          'description': pattern.description,
          'refRequired': pattern.refRequired == null
              ? null
              : (pattern.refRequired! ? 1 : 0),
          'hasAccount':
              pattern.hasAccount == null ? null : (pattern.hasAccount! ? 1 : 0),
        });
        count++;
      } catch (e) {
        print("debug: Error migrating SMS pattern: $e");
      }
    }

    if (count > 0) {
      await batch.commit(noResult: true);
      print("debug: Migrated $count SMS patterns");
    }
  }

  static Future<void> _migrateAccounts(
      SharedPreferences prefs, Database db) async {
    const String key = "accounts";
    final List<String>? accountsList = prefs.getStringList(key);

    if (accountsList == null || accountsList.isEmpty) {
      print("debug: No accounts to migrate");
      return;
    }

    final batch = db.batch();
    int count = 0;

    for (var jsonStr in accountsList) {
      try {
        final json = jsonDecode(jsonStr);
        final account = Account.fromJson(json);

        batch.insert('accounts', {
          'accountNumber': account.accountNumber,
          'bank': account.bank,
          'balance': account.balance,
          'accountHolderName': account.accountHolderName,
          'settledBalance': account.settledBalance,
          'pendingCredit': account.pendingCredit,
        });
        count++;
      } catch (e) {
        print("debug: Error migrating account: $e");
      }
    }

    if (count > 0) {
      await batch.commit(noResult: true);
      print("debug: Migrated $count accounts");
    }
  }
}
