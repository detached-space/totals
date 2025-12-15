import 'dart:convert';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/failed_parse.dart';
import 'package:totals/models/sms_pattern.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/repositories/failed_parse_repository.dart';
import 'package:totals/services/sms_config_service.dart';

class DataExportImportService {
  final AccountRepository _accountRepo = AccountRepository();
  final TransactionRepository _transactionRepo = TransactionRepository();
  final FailedParseRepository _failedParseRepo = FailedParseRepository();
  final SmsConfigService _smsConfigService = SmsConfigService();

  /// Export all data to JSON
  Future<String> exportAllData() async {
    try {
      final accounts = await _accountRepo.getAccounts();
      final transactions = await _transactionRepo.getTransactions();
      final failedParses = await _failedParseRepo.getAll();
      final smsPatterns = await _smsConfigService.getPatterns();

      final exportData = {
        'version': '1.0',
        'exportDate': DateTime.now().toIso8601String(),
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'failedParses': failedParses.map((f) => f.toJson()).toList(),
        'smsPatterns': smsPatterns.map((p) => p.toJson()).toList(),
      };

      return jsonEncode(exportData);
    } catch (e) {
      throw Exception('Failed to export data: $e');
    }
  }

  /// Import all data from JSON (appends to existing data)
  Future<void> importAllData(String jsonData) async {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonData);
      final db = await DatabaseHelper.instance.database;

      // Validate version (for future compatibility)
      final version = data['version'] ?? '1.0';

      // Import accounts (append, skip duplicates)
      if (data['accounts'] != null) {
        final accountsList = (data['accounts'] as List)
            .map((json) => Account.fromJson(json as Map<String, dynamic>))
            .toList();
        final batch = db.batch();
        for (var account in accountsList) {
          batch.insert(
            'accounts',
            {
              'accountNumber': account.accountNumber,
              'bank': account.bank,
              'balance': account.balance,
              'accountHolderName': account.accountHolderName,
              'settledBalance': account.settledBalance,
              'pendingCredit': account.pendingCredit,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore, // Skip if exists
          );
        }
        await batch.commit(noResult: true);
      }

      // Import transactions (append, skip duplicates based on reference)
      if (data['transactions'] != null) {
        final transactionsList = (data['transactions'] as List)
            .map((json) => Transaction.fromJson(json as Map<String, dynamic>))
            .toList();
        final batch = db.batch();
        for (var transaction in transactionsList) {
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
            conflictAlgorithm: ConflictAlgorithm.ignore, // Skip if reference exists
          );
        }
        await batch.commit(noResult: true);
      }

      // Import failed parses (append)
      if (data['failedParses'] != null) {
        final batch = db.batch();
        for (var json in data['failedParses'] as List) {
          final failedParse = FailedParse.fromJson(json as Map<String, dynamic>);
          batch.insert('failed_parses', {
            'address': failedParse.address,
            'body': failedParse.body,
            'reason': failedParse.reason,
            'timestamp': failedParse.timestamp,
          });
        }
        await batch.commit(noResult: true);
      }

      // Import SMS patterns (replace - these are configuration)
      if (data['smsPatterns'] != null) {
        final patternsList = (data['smsPatterns'] as List)
            .map((json) => SmsPattern.fromJson(json as Map<String, dynamic>))
            .toList();
        await _smsConfigService.savePatterns(patternsList);
      }
    } catch (e) {
      throw Exception('Failed to import data: $e');
    }
  }
}

