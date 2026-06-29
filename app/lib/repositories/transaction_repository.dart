import 'dart:convert';

import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/auto_categorization_service.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';
import 'package:totals/services/data_sync/sync_enqueuer.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/constants/cash_constants.dart';

class TransactionRepository {
  final BankConfigService _bankConfigService = BankConfigService();
  final ProfileRepository _profileRepo = ProfileRepository();
  final AutoCategorizationService _autoCategorizationService =
      AutoCategorizationService.instance;

  Future<int?> _getActiveProfileId() async {
    return await _profileRepo.getActiveProfileId();
  }

  Future<List<Transaction>> getTransactions() async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();

    final List<Map<String, dynamic>> maps = activeProfileId != null
        ? await db.query(
            'transactions',
            where: 'profileId = ?',
            whereArgs: [activeProfileId],
            orderBy: 'time DESC, id DESC',
          )
        : await db.query('transactions', orderBy: 'time DESC, id DESC');

    return maps.map<Transaction>(_transactionFromMap).toList();
  }

  Future<Transaction?> getTransactionByReference(String reference) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();

    List<Map<String, dynamic>> maps;
    if (activeProfileId != null) {
      maps = await db.query(
        'transactions',
        where: 'reference = ? AND profileId = ?',
        whereArgs: [reference, activeProfileId],
        limit: 1,
      );
      if (maps.isEmpty) {
        maps = await db.query(
          'transactions',
          where: 'reference = ?',
          whereArgs: [reference],
          limit: 1,
        );
      }
    } else {
      maps = await db.query(
        'transactions',
        where: 'reference = ?',
        whereArgs: [reference],
        limit: 1,
      );
    }

    if (maps.isEmpty) return null;
    return _transactionFromMap(maps.first);
  }

  Transaction _transactionFromMap(Map<String, dynamic> map) {
    return Transaction.fromJson({
      'amount': map['amount'],
      'reference': map['reference'],
      'creditor': map['creditor'],
      'receiver': map['receiver'],
      'note': map['note'],
      'time': map['time'],
      'status': map['status'],
      'currentBalance': map['currentBalance'],
      'serviceCharge': map['serviceCharge'],
      'vat': map['vat'],
      'bankId': map['bankId'],
      'type': map['type'],
      'transactionLink': map['transactionLink'],
      'accountNumber': map['accountNumber'],
      'categoryId': map['categoryId'],
      'categoryIds': map['categoryIds'],
      'profileId': map['profileId'],
      'sourceType': map['sourceType'],
      'sourceMessageId': map['sourceMessageId'],
      'sourceFingerprint': map['sourceFingerprint'],
    });
  }

  Future<void> saveTransaction(
    Transaction transaction, {
    bool skipAutoCategorization = false,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();

    // Use transaction's profileId if provided, otherwise use active profile
    final profileId = transaction.profileId ?? activeProfileId;

    // Apply auto-categorization if enabled and transaction has no category
    // Skip if explicitly requested (e.g., when user clears category)
    Transaction transactionToSave = transaction;
    if (!skipAutoCategorization && transaction.categoryId == null) {
      final selection =
          await _autoCategorizationService.getCategorySelectionForTransaction(
        type: transaction.type,
        receiver: transaction.receiver,
        creditor: transaction.creditor,
      );
      if (selection != null && !selection.isEmpty) {
        transactionToSave = transaction.copyWith(
          categoryId: selection.primaryCategoryId,
          categoryIds: selection.categoryIds,
        );
        print(
            "debug: Auto-categorized transaction ${transaction.reference} with categoryIds ${selection.categoryIds.join(',')}");
      }
    } else if (skipAutoCategorization) {
      print(
          "debug: Skipping auto-categorization for transaction ${transaction.reference}, categoryId: ${transaction.categoryId}");
    }

    // Parse and extract date components for faster queries
    int? year, month, day, week;
    if (transactionToSave.time != null) {
      try {
        final date = DateTime.parse(transactionToSave.time!);
        year = date.year;
        month = date.month;
        day = date.day;
        week = ((date.day - 1) ~/ 7) + 1;
      } catch (e) {
        // Handle parse error - date columns will remain null
      }
    }

    final dataToSave = {
      'amount': transactionToSave.amount,
      'reference': transactionToSave.reference,
      'creditor': transactionToSave.creditor,
      'receiver': transactionToSave.receiver,
      'note': transactionToSave.note,
      'time': transactionToSave.time,
      'status': transactionToSave.status,
      'currentBalance': transactionToSave.currentBalance,
      'serviceCharge': transactionToSave.serviceCharge,
      'vat': transactionToSave.vat,
      'bankId': transactionToSave.bankId,
      'type': transactionToSave.type,
      'transactionLink': transactionToSave.transactionLink,
      'accountNumber': transactionToSave.accountNumber,
      'categoryId': transactionToSave.categoryId,
      'categoryIds': transactionToSave.selectedCategoryIds.isEmpty
          ? null
          : jsonEncode(transactionToSave.selectedCategoryIds),
      'sourceType': transactionToSave.sourceType,
      'sourceMessageId': transactionToSave.sourceMessageId,
      'sourceFingerprint': transactionToSave.sourceFingerprint,
      'year': year,
      'month': month,
      'day': day,
      'week': week,
    };

    print(
        "debug: Saving transaction ${transactionToSave.reference} with categoryId: ${dataToSave['categoryId']}");

    // Add profileId to dataToSave
    dataToSave['profileId'] = profileId;

    await db.insert(
      'transactions',
      dataToSave,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print(
        "debug: Transaction ${transactionToSave.reference} saved successfully");

    await SyncEnqueuer.instance.onEntityWritten(
      entity: SyncEntity.transactions,
      entityRef: transactionToSave.reference,
      op: SyncOp.upsert,
      row: Map<String, dynamic>.from(dataToSave),
    );
  }

  Future<void> saveAllTransactions(
    List<Transaction> transactions, {
    bool skipAutoCategorization = true,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    final batch = db.batch();
    final syncRecords = <MapEntry<String, Map<String, dynamic>>>[];

    for (var transaction in transactions) {
      var transactionToSave = transaction;
      if (!skipAutoCategorization && transaction.categoryId == null) {
        final selection =
            await _autoCategorizationService.getCategorySelectionForTransaction(
          type: transaction.type,
          receiver: transaction.receiver,
          creditor: transaction.creditor,
        );
        if (selection != null && !selection.isEmpty) {
          transactionToSave = transaction.copyWith(
            categoryId: selection.primaryCategoryId,
            categoryIds: selection.categoryIds,
          );
        }
      }

      // Use transaction's profileId if provided, otherwise use active profile
      final profileId = transactionToSave.profileId ?? activeProfileId;

      // Parse and extract date components for faster queries
      int? year, month, day, week;
      if (transactionToSave.time != null) {
        try {
          final date = DateTime.parse(transactionToSave.time!);
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
          'amount': transactionToSave.amount,
          'reference': transactionToSave.reference,
          'creditor': transactionToSave.creditor,
          'receiver': transactionToSave.receiver,
          'note': transactionToSave.note,
          'time': transactionToSave.time,
          'status': transactionToSave.status,
          'currentBalance': transactionToSave.currentBalance,
          'serviceCharge': transactionToSave.serviceCharge,
          'vat': transactionToSave.vat,
          'bankId': transactionToSave.bankId,
          'type': transactionToSave.type,
          'transactionLink': transactionToSave.transactionLink,
          'accountNumber': transactionToSave.accountNumber,
          'categoryId': transactionToSave.categoryId,
          'categoryIds': transactionToSave.selectedCategoryIds.isEmpty
              ? null
              : jsonEncode(transactionToSave.selectedCategoryIds),
          'profileId': profileId,
          'sourceType': transactionToSave.sourceType,
          'sourceMessageId': transactionToSave.sourceMessageId,
          'sourceFingerprint': transactionToSave.sourceFingerprint,
          'year': year,
          'month': month,
          'day': day,
          'week': week,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      syncRecords.add(MapEntry(transactionToSave.reference, {
        'reference': transactionToSave.reference,
        'type': transactionToSave.type,
        'amount': transactionToSave.amount,
        'bankId': transactionToSave.bankId,
        'time': transactionToSave.time,
        'profileId': profileId,
        'sourceType': transactionToSave.sourceType,
        'sourceMessageId': transactionToSave.sourceMessageId,
        'sourceFingerprint': transactionToSave.sourceFingerprint,
      }));
    }

    await batch.commit(noResult: true);

    await SyncEnqueuer.instance.onManyWritten(
      entity: SyncEntity.transactions,
      records: syncRecords,
    );
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
    final activeProfileId = await _getActiveProfileId();

    // Filter by profile if active
    if (activeProfileId != null) {
      whereParts.add('profileId = ?');
      whereArgs.add(activeProfileId);
    }

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

    return maps.map<Transaction>(_transactionFromMap).toList();
  }

  /// Get transactions by month with optional bank filter
  /// Uses indexed date columns for fast queries
  Future<List<Transaction>> getTransactionsByMonth(
    int year,
    int month, {
    int? bankId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();

    final whereParts = <String>['year = ? AND month = ?'];
    final whereArgs = <dynamic>[year, month];

    if (activeProfileId != null) {
      whereParts.add('profileId = ?');
      whereArgs.add(activeProfileId);
    }

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

    return maps.map<Transaction>(_transactionFromMap).toList();
  }

  /// Get transactions by week with optional filters
  /// Uses indexed date columns for fast queries
  Future<List<Transaction>> getTransactionsByWeek(
    DateTime weekStart,
    DateTime weekEnd, {
    int? bankId,
    String? type,
  }) async {
    return getTransactionsByDateRange(weekStart, weekEnd,
        bankId: bankId, type: type);
  }

  /// Delete transactions associated with an account
  /// Uses the same matching logic as TransactionProvider to identify transactions
  /// Only deletes transactions within the current active profile
  Future<void> deleteTransactionsByAccount(
      String accountNumber, int bank) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    if (bank == CashConstants.bankId) {
      final whereParts = <String>[];
      final whereArgs = <dynamic>[];

      if (activeProfileId != null) {
        whereParts.add('profileId = ?');
        whereArgs.add(activeProfileId);
      }

      whereParts.add('bankId = ?');
      whereArgs.add(bank);

      if (accountNumber.isNotEmpty) {
        whereParts.add('accountNumber = ?');
        whereArgs.add(accountNumber);
      }

      await _deleteTransactionsAndEnqueue(
        db,
        where: whereParts.join(' AND '),
        whereArgs: whereArgs,
      );
      return;
    }

    final banks = await _bankConfigService.getBanks();
    final currentBank = banks.firstWhere((b) => b.id == bank);

    // Build where clause with profile filtering
    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    if (activeProfileId != null) {
      whereParts.add('profileId = ?');
      whereArgs.add(activeProfileId);
    }

    // For banks that match by bankId only (Awash=2, Telebirr=6), delete all transactions for that bank
    if (currentBank.uniformMasking == false) {
      whereParts.add('bankId = ?');
      whereArgs.add(bank);

      await _deleteTransactionsAndEnqueue(
        db,
        where: whereParts.join(' AND '),
        whereArgs: whereArgs,
      );
      return;
    }

    // For other banks, match by accountNumber substring logic
    String? accountSuffix;

    if (currentBank.uniformMasking == true) {
      accountSuffix = accountNumber
          .substring(accountNumber.length - currentBank.maskPattern!);
    }

    if (accountSuffix != null) {
      whereParts.add('bankId = ?');
      whereArgs.add(bank);
      whereParts.add('accountNumber IS NOT NULL');
      whereParts.add('accountNumber LIKE ?');
      whereArgs.add('%$accountSuffix');

      // Delete transactions where bankId matches and accountNumber ends with the suffix
      // Using SQL LIKE pattern matching to match the suffix at the end
      await _deleteTransactionsAndEnqueue(
        db,
        where: whereParts.join(' AND '),
        whereArgs: whereArgs,
      );
    } else {
      // Fallback: delete all transactions for this bank (except NULL accountNumber ones)
      whereParts.add('bankId = ?');
      whereArgs.add(bank);
      whereParts.add('accountNumber IS NOT NULL');

      await _deleteTransactionsAndEnqueue(
        db,
        where: whereParts.join(' AND '),
        whereArgs: whereArgs,
      );
    }
  }

  Future<void> deleteTransactionsByReferences(
      Iterable<String> references) async {
    final refs = references.toSet();
    if (refs.isEmpty) return;

    const maxSqlVars = 900;
    final refList = refs.toList();
    final db = await DatabaseHelper.instance.database;

    for (var i = 0; i < refList.length; i += maxSqlVars) {
      final chunkEnd =
          (i + maxSqlVars) > refList.length ? refList.length : i + maxSqlVars;
      final chunk = refList.sublist(i, chunkEnd);
      final placeholders = List.filled(chunk.length, '?').join(', ');
      await db.delete(
        'transactions',
        where: 'reference IN ($placeholders)',
        whereArgs: chunk,
      );
    }

    for (final ref in refList) {
      await SyncEnqueuer.instance.onEntityWritten(
        entity: SyncEntity.transactions,
        entityRef: ref,
        op: SyncOp.delete,
        deleteSnapshot: {'reference': ref},
      );
    }
  }

  /// Deletes transactions matching [where]/[whereArgs] and, when Data Sync is
  /// enabled, enqueues a delete for each removed reference. The reference
  /// lookup is skipped entirely when sync is off so the delete path stays cheap.
  Future<void> _deleteTransactionsAndEnqueue(
    Database db, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    List<String> refs = const [];
    bool syncOn = false;
    try {
      syncOn = await DataSyncSettingsService.readEnabledFromPrefs();
    } catch (_) {}
    if (syncOn) {
      try {
        final rows = await db.query(
          'transactions',
          columns: ['reference'],
          where: where,
          whereArgs: whereArgs,
        );
        refs = rows
            .map((r) => r['reference'] as String?)
            .whereType<String>()
            .toList(growable: false);
      } catch (_) {}
    }

    await db.delete('transactions', where: where, whereArgs: whereArgs);

    for (final ref in refs) {
      await SyncEnqueuer.instance.onEntityWritten(
        entity: SyncEntity.transactions,
        entityRef: ref,
        op: SyncOp.delete,
        deleteSnapshot: {'reference': ref},
      );
    }
  }
}
