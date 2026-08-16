import 'dart:convert';
import 'dart:math' as math;

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
import 'package:totals/models/account.dart';
import 'package:totals/utils/account_identity.dart';
import 'package:totals/utils/reimbursement_utils.dart';

class TransactionOwnershipUpdate {
  final String reference;
  final String? ownerAccountNumber;
  final String? ownerAssignmentSource;
  final int? sourceSubscriptionId;
  final String? sourceMessageId;

  const TransactionOwnershipUpdate({
    required this.reference,
    required this.ownerAccountNumber,
    this.ownerAssignmentSource,
    this.sourceSubscriptionId,
    this.sourceMessageId,
  });
}

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
      'ownerAccountNumber': map['ownerAccountNumber'],
      'ownerAssignmentSource': map['ownerAssignmentSource'],
      'categoryId': map['categoryId'],
      'categoryIds': map['categoryIds'],
      'profileId': map['profileId'],
      'sourceType': map['sourceType'],
      'sourceMessageId': map['sourceMessageId'],
      'sourceFingerprint': map['sourceFingerprint'],
      'sourceSubscriptionId': map['sourceSubscriptionId'],
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
      'ownerAccountNumber': transactionToSave.ownerAccountNumber,
      'ownerAssignmentSource': transactionToSave.ownerAssignmentSource,
      'categoryId': transactionToSave.categoryId,
      'categoryIds': transactionToSave.selectedCategoryIds.isEmpty
          ? null
          : jsonEncode(transactionToSave.selectedCategoryIds),
      'sourceType': transactionToSave.sourceType,
      'sourceMessageId': transactionToSave.sourceMessageId,
      'sourceFingerprint': transactionToSave.sourceFingerprint,
      'sourceSubscriptionId': transactionToSave.sourceSubscriptionId,
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
      row: Map<String, dynamic>.from(dataToSave)
        ..remove('sourceSubscriptionId'),
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
          'ownerAccountNumber': transactionToSave.ownerAccountNumber,
          'ownerAssignmentSource': transactionToSave.ownerAssignmentSource,
          'categoryId': transactionToSave.categoryId,
          'categoryIds': transactionToSave.selectedCategoryIds.isEmpty
              ? null
              : jsonEncode(transactionToSave.selectedCategoryIds),
          'profileId': profileId,
          'sourceType': transactionToSave.sourceType,
          'sourceMessageId': transactionToSave.sourceMessageId,
          'sourceFingerprint': transactionToSave.sourceFingerprint,
          'sourceSubscriptionId': transactionToSave.sourceSubscriptionId,
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
        'ownerAccountNumber': transactionToSave.ownerAccountNumber,
        'ownerAssignmentSource': transactionToSave.ownerAssignmentSource,
      }));
    }

    await batch.commit(noResult: true);

    await SyncEnqueuer.instance.onManyWritten(
      entity: SyncEntity.transactions,
      records: syncRecords,
    );
  }

  /// Updates category fields for existing transactions in one database batch.
  /// All other transaction fields, including SMS source and account ownership,
  /// are left untouched.
  Future<int> updateTransactionCategories(
    Iterable<Transaction> transactions,
  ) async {
    final deduped = <String, Transaction>{
      for (final transaction in transactions)
        if (transaction.reference.trim().isNotEmpty)
          transaction.reference: transaction,
    };
    if (deduped.isEmpty) return 0;

    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    final previousRowsByReference = <String, Map<String, dynamic>>{};
    final references = deduped.keys.toList(growable: false);
    const maxSqlVars = 900;
    for (var start = 0; start < references.length; start += maxSqlVars) {
      final end = math.min(start + maxSqlVars, references.length);
      final chunk = references.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final where = StringBuffer('reference IN ($placeholders)');
      final args = <Object?>[...chunk];
      if (activeProfileId != null) {
        where.write(' AND profileId = ?');
        args.add(activeProfileId);
      }
      final rows = await db.query(
        'transactions',
        where: where.toString(),
        whereArgs: args,
      );
      for (final row in rows) {
        final reference = row['reference']?.toString();
        if (reference == null || reference.isEmpty) continue;
        previousRowsByReference[reference] = Map<String, dynamic>.from(row);
      }
    }

    final updates = deduped.values
        .where(
          (transaction) =>
              previousRowsByReference.containsKey(transaction.reference),
        )
        .toList(growable: false);
    if (updates.isEmpty) return 0;

    final batch = db.batch();
    for (final transaction in updates) {
      final where = <String>['reference = ?'];
      final args = <Object?>[transaction.reference];
      if (activeProfileId != null) {
        where.add('profileId = ?');
        args.add(activeProfileId);
      }
      batch.update(
        'transactions',
        <String, Object?>{
          'categoryId': transaction.categoryId,
          'categoryIds': transaction.selectedCategoryIds.isEmpty
              ? null
              : jsonEncode(transaction.selectedCategoryIds),
        },
        where: where.join(' AND '),
        whereArgs: args,
      );
    }
    await batch.commit(noResult: true);

    final syncRecords = <MapEntry<String, Map<String, dynamic>>>[];
    for (final transaction in updates) {
      final row = Map<String, dynamic>.from(
        previousRowsByReference[transaction.reference]!,
      );
      row['categoryId'] = transaction.categoryId;
      row['categoryIds'] = transaction.selectedCategoryIds.isEmpty
          ? null
          : jsonEncode(transaction.selectedCategoryIds);
      row.remove('sourceSubscriptionId');
      syncRecords.add(MapEntry(transaction.reference, row));
    }
    await SyncEnqueuer.instance.onManyWritten(
      entity: SyncEntity.transactions,
      records: syncRecords,
    );
    return updates.length;
  }

  Future<bool> updateTransactionOwnership({
    required String reference,
    required String ownerAccountNumber,
    required String ownerAssignmentSource,
    int? sourceSubscriptionId,
    String? sourceMessageId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    final where = <String>['reference = ?'];
    final args = <Object?>[reference];
    if (activeProfileId != null) {
      where.add('profileId = ?');
      args.add(activeProfileId);
    }

    final existingRows = await db.query(
      'transactions',
      columns: const <String>['ownerAssignmentSource'],
      where: where.join(' AND '),
      whereArgs: args,
      limit: 1,
    );
    if (existingRows.isNotEmpty &&
        existingRows.single['ownerAssignmentSource'] ==
            Transaction.manualOwnerAssignment &&
        ownerAssignmentSource != Transaction.manualOwnerAssignment) {
      return false;
    }

    final values = <String, Object?>{
      'ownerAccountNumber': ownerAccountNumber,
      'ownerAssignmentSource': ownerAssignmentSource,
      if (sourceSubscriptionId != null && sourceSubscriptionId >= 0)
        'sourceSubscriptionId': sourceSubscriptionId,
      if (sourceMessageId != null && sourceMessageId.trim().isNotEmpty)
        'sourceMessageId': sourceMessageId.trim(),
    };
    final changed = await db.update(
      'transactions',
      values,
      where: where.join(' AND '),
      whereArgs: args,
    );
    if (changed == 0) return false;

    final currentRows = await db.query(
      'transactions',
      where: where.join(' AND '),
      whereArgs: args,
      limit: 1,
    );
    final syncRow = currentRows.isEmpty
        ? <String, dynamic>{
            'reference': reference,
            'ownerAccountNumber': ownerAccountNumber,
            'ownerAssignmentSource': ownerAssignmentSource,
          }
        : Map<String, dynamic>.from(currentRows.single)
      ..remove('sourceSubscriptionId');

    await SyncEnqueuer.instance.onEntityWritten(
      entity: SyncEntity.transactions,
      entityRef: reference,
      op: SyncOp.upsert,
      row: syncRow,
    );
    return true;
  }

  Future<int> updateTransactionOwnerships(
    Iterable<TransactionOwnershipUpdate> updates,
  ) async {
    final deduped = <String, TransactionOwnershipUpdate>{
      for (final update in updates) update.reference: update,
    };
    if (deduped.isEmpty) return 0;

    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    final previousRowsByReference = <String, Map<String, dynamic>>{};
    final references = deduped.keys.toList(growable: false);
    const maxSqlVars = 900;
    for (var start = 0; start < references.length; start += maxSqlVars) {
      final candidateEnd = start + maxSqlVars;
      final end =
          candidateEnd < references.length ? candidateEnd : references.length;
      final chunk = references.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final where = StringBuffer('reference IN ($placeholders)');
      final args = <Object?>[...chunk];
      if (activeProfileId != null) {
        where.write(' AND profileId = ?');
        args.add(activeProfileId);
      }
      final rows = await db.query(
        'transactions',
        where: where.toString(),
        whereArgs: args,
      );
      for (final row in rows) {
        final reference = row['reference']?.toString();
        if (reference == null || reference.isEmpty) continue;
        previousRowsByReference[reference] = Map<String, dynamic>.from(row);
      }
    }
    final updatesToApply = deduped.values.where((update) {
      final previous = previousRowsByReference[update.reference];
      final previousSource = previous?['ownerAssignmentSource']?.toString();
      return previousSource != Transaction.manualOwnerAssignment ||
          update.ownerAssignmentSource == Transaction.manualOwnerAssignment;
    }).toList(growable: false);
    if (updatesToApply.isEmpty) return 0;
    final batch = db.batch();
    for (final update in updatesToApply) {
      final where = <String>['reference = ?'];
      final args = <Object?>[update.reference];
      if (activeProfileId != null) {
        where.add('profileId = ?');
        args.add(activeProfileId);
      }
      batch.update(
        'transactions',
        <String, Object?>{
          'ownerAccountNumber': update.ownerAccountNumber,
          if (update.ownerAssignmentSource != null)
            'ownerAssignmentSource': update.ownerAssignmentSource,
          // Clearing a disproven owner must also clear its SIM shortcut;
          // otherwise read-time ownership would immediately assign it again.
          if (update.ownerAccountNumber == null)
            'sourceSubscriptionId': null
          else if (update.sourceSubscriptionId != null &&
              update.sourceSubscriptionId! >= 0)
            'sourceSubscriptionId': update.sourceSubscriptionId,
          if (update.sourceMessageId?.trim().isNotEmpty == true)
            'sourceMessageId': update.sourceMessageId!.trim(),
        },
        where: where.join(' AND '),
        whereArgs: args,
      );
    }
    await batch.commit(noResult: true);

    // A clear must remove a previously account-scoped remote copy. Queue the
    // delete against the old snapshot first; the current-row upsert below will
    // then recreate it only for broader rules that still match (for example,
    // the whole bank).
    for (final update in updatesToApply) {
      if (update.ownerAccountNumber != null) continue;
      final previous = previousRowsByReference[update.reference];
      if (previous == null) continue;
      await SyncEnqueuer.instance.onEntityWritten(
        entity: SyncEntity.transactions,
        entityRef: update.reference,
        op: SyncOp.delete,
        deleteSnapshot: Map<String, dynamic>.from(previous)
          ..remove('sourceSubscriptionId'),
      );
    }

    final syncRecords = <MapEntry<String, Map<String, dynamic>>>[];
    for (final update in updatesToApply) {
      final row = Map<String, dynamic>.from(
        previousRowsByReference[update.reference] ??
            <String, dynamic>{'reference': update.reference},
      );
      row['ownerAccountNumber'] = update.ownerAccountNumber;
      if (update.ownerAssignmentSource != null) {
        row['ownerAssignmentSource'] = update.ownerAssignmentSource;
      }
      if (update.ownerAccountNumber == null) {
        row['sourceSubscriptionId'] = null;
      } else if (update.sourceSubscriptionId != null &&
          update.sourceSubscriptionId! >= 0) {
        row['sourceSubscriptionId'] = update.sourceSubscriptionId;
      }
      if (update.sourceMessageId?.trim().isNotEmpty == true) {
        row['sourceMessageId'] = update.sourceMessageId!.trim();
      }
      row.remove('sourceSubscriptionId');
      syncRecords.add(MapEntry(update.reference, row));
    }
    await SyncEnqueuer.instance.onManyWritten(
      entity: SyncEntity.transactions,
      records: syncRecords,
    );
    return updatesToApply.length;
  }

  Future<void> clearAll() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('transactions');
  }

  Future<void> clearBanks(Set<int> bankIds) async {
    if (bankIds.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    final ids = bankIds.toList(growable: false);
    final placeholders = List.filled(ids.length, '?').join(', ');
    await _deleteTransactionsMatching(
      db,
      where: 'bankId IN ($placeholders)',
      whereArgs: ids,
      enqueueSyncChanges: false,
    );
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

    final banks = await _bankConfigService.getBanks(allowRemoteFetch: false);
    final currentBank = banks.firstWhere((b) => b.id == bank);
    final accountWhere = <String>['bank = ?'];
    final accountArgs = <Object?>[bank];
    if (activeProfileId != null) {
      accountWhere.add('profileId = ?');
      accountArgs.add(activeProfileId);
    }
    final accountRows = await db.query(
      'accounts',
      where: accountWhere.join(' AND '),
      whereArgs: accountArgs,
    );
    final bankAccounts = accountRows
        .map((row) => Account.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    final targetMatches = bankAccounts
        .where((account) => registeredAccountNumbersMatch(
              currentBank,
              account.accountNumber,
              accountNumber,
            ))
        .toList(growable: false);
    if (targetMatches.length != 1) return;
    final target = targetMatches.single;

    final transactionWhere = <String>['bankId = ?'];
    final transactionArgs = <Object?>[bank];
    if (activeProfileId != null) {
      transactionWhere.add('profileId = ?');
      transactionArgs.add(activeProfileId);
    }
    final rows = await db.query(
      'transactions',
      where: transactionWhere.join(' AND '),
      whereArgs: transactionArgs,
    );
    final references = rows
        .map(_transactionFromMap)
        .where((transaction) => transactionBelongsToAccount(
              transaction: transaction,
              account: target,
              bank: currentBank,
              accounts: bankAccounts,
            ))
        .map((transaction) => transaction.reference);
    await deleteTransactionsByReferences(references);
  }

  /// Deletes every transaction for [bank] in the active profile.
  ///
  /// This is used when the bank's final registered account is removed: once
  /// no account remains, retaining an orphaned Other-transactions bucket is
  /// surprising and leaves totals behind for a bank the user deleted.
  Future<void> deleteTransactionsByBank(int bank) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    final where = <String>['bankId = ?'];
    final args = <dynamic>[bank];
    if (activeProfileId != null) {
      where.add('profileId = ?');
      args.add(activeProfileId);
    }
    await _deleteTransactionsAndEnqueue(
      db,
      where: where.join(' AND '),
      whereArgs: args,
    );
  }

  Future<void> deleteTransactionsByReferences(
      Iterable<String> references) async {
    final refs = references
        .map((reference) => reference.trim())
        .where((reference) => reference.isNotEmpty)
        .toSet();
    if (refs.isEmpty) return;

    final refList = refs.toList(growable: false);
    final db = await DatabaseHelper.instance.database;
    final categorySyncRecords =
        await _deleteReferencesWithReimbursementCleanup(db, refList);
    await _enqueueTransactionDeletionChanges(
      deletedReferences: refList,
      categorySyncRecords: categorySyncRecords,
    );
  }

  /// Removes one reimbursement link and, when it was the credit's final link,
  /// removes the built-in reimbursement category in the same transaction.
  Future<Transaction?> unlinkReimbursementAllocation(int allocationId) async {
    if (allocationId <= 0) return null;

    final db = await DatabaseHelper.instance.database;
    List<MapEntry<String, Map<String, dynamic>>> categorySyncRecords = const [];
    await db.transaction((txn) async {
      final rows = await txn.query(
        'reimbursement_allocations',
        columns: const ['reimbursementTransactionReference'],
        where: 'id = ?',
        whereArgs: [allocationId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final reimbursementReference =
          rows.single['reimbursementTransactionReference']?.toString().trim();
      await txn.delete(
        'reimbursement_allocations',
        where: 'id = ?',
        whereArgs: [allocationId],
      );
      if (reimbursementReference == null || reimbursementReference.isEmpty) {
        return;
      }
      categorySyncRecords = await _removeCategoryFromOrphanedReimbursements(
        txn,
        <String>{reimbursementReference},
      );
    });

    await _enqueueTransactionDeletionChanges(
      deletedReferences: const <String>[],
      categorySyncRecords: categorySyncRecords,
    );
    if (categorySyncRecords.isEmpty) return null;
    return _transactionFromMap(categorySyncRecords.single.value);
  }

  /// Deletes transactions matching [where]/[whereArgs] and, when Data Sync is
  /// enabled, enqueues a delete for each removed reference.
  Future<void> _deleteTransactionsAndEnqueue(
    Database db, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    await _deleteTransactionsMatching(
      db,
      where: where,
      whereArgs: whereArgs,
      enqueueSyncChanges: true,
    );
  }

  Future<void> _deleteTransactionsMatching(
    Database db, {
    required String where,
    required List<dynamic> whereArgs,
    required bool enqueueSyncChanges,
  }) async {
    List<String> refs = const [];
    List<MapEntry<String, Map<String, dynamic>>> categorySyncRecords = const [];
    await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        columns: ['reference'],
        where: where,
        whereArgs: whereArgs,
      );
      refs = rows
          .map((row) => row['reference'] as String?)
          .whereType<String>()
          .toList(growable: false);
      // Capture the credits before deleting their allocations so only
      // reimbursements orphaned by this specific deletion are repaired.
      final affectedReimbursements =
          await _findReimbursementsLinkedToExpenses(txn, refs);
      await txn.delete(
        'transactions',
        where: where,
        whereArgs: whereArgs,
      );
      await _deleteAllocationsForTransactionReferences(txn, refs);
      categorySyncRecords = await _removeCategoryFromOrphanedReimbursements(
        txn,
        affectedReimbursements,
      );
    });

    if (!enqueueSyncChanges) return;
    await _enqueueTransactionDeletionChanges(
      deletedReferences: refs,
      categorySyncRecords: categorySyncRecords,
    );
  }

  Future<List<MapEntry<String, Map<String, dynamic>>>>
      _deleteReferencesWithReimbursementCleanup(
    Database db,
    List<String> references,
  ) {
    return db.transaction((txn) async {
      final affectedReimbursements =
          await _findReimbursementsLinkedToExpenses(txn, references);
      for (var start = 0;
          start < references.length;
          start += _maxSqlVariables) {
        final end = math.min(start + _maxSqlVariables, references.length);
        final chunk = references.sublist(start, end);
        final placeholders = List.filled(chunk.length, '?').join(', ');
        await txn.delete(
          'transactions',
          where: 'reference IN ($placeholders)',
          whereArgs: chunk,
        );
      }
      await _deleteAllocationsForTransactionReferences(txn, references);
      return _removeCategoryFromOrphanedReimbursements(
        txn,
        affectedReimbursements,
      );
    });
  }

  static const int _maxSqlVariables = 900;

  Future<void> _deleteAllocationsForTransactionReferences(
    DatabaseExecutor executor,
    Iterable<String> transactionReferences,
  ) async {
    final references = transactionReferences
        .map((reference) => reference.trim())
        .where((reference) => reference.isNotEmpty)
        .toSet()
        .toList(growable: false);
    for (var start = 0; start < references.length; start += _maxSqlVariables) {
      final end = math.min(start + _maxSqlVariables, references.length);
      final chunk = references.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');
      await executor.delete(
        'reimbursement_allocations',
        where: 'reimbursementTransactionReference IN ($placeholders)',
        whereArgs: chunk,
      );
      await executor.delete(
        'reimbursement_allocations',
        where: 'expenseTransactionReference IN ($placeholders)',
        whereArgs: chunk,
      );
    }
  }

  Future<Set<String>> _findReimbursementsLinkedToExpenses(
    DatabaseExecutor executor,
    Iterable<String> expenseReferences,
  ) async {
    final references = expenseReferences
        .map((reference) => reference.trim())
        .where((reference) => reference.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (references.isEmpty) return <String>{};

    final reimbursements = <String>{};
    for (var start = 0; start < references.length; start += _maxSqlVariables) {
      final end = math.min(start + _maxSqlVariables, references.length);
      final chunk = references.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await executor.query(
        'reimbursement_allocations',
        columns: ['reimbursementTransactionReference'],
        where: 'expenseTransactionReference IN ($placeholders)',
        whereArgs: chunk,
        distinct: true,
      );
      for (final row in rows) {
        final reference =
            row['reimbursementTransactionReference']?.toString().trim();
        if (reference != null && reference.isNotEmpty) {
          reimbursements.add(reference);
        }
      }
    }
    return reimbursements;
  }

  Future<List<MapEntry<String, Map<String, dynamic>>>>
      _removeCategoryFromOrphanedReimbursements(
    DatabaseExecutor executor,
    Set<String> reimbursementReferences,
  ) async {
    if (reimbursementReferences.isEmpty) return const [];

    final stillLinked = <String>{};
    final references = reimbursementReferences.toList(growable: false);
    for (var start = 0; start < references.length; start += _maxSqlVariables) {
      final end = math.min(start + _maxSqlVariables, references.length);
      final chunk = references.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await executor.query(
        'reimbursement_allocations',
        columns: ['reimbursementTransactionReference'],
        where: 'reimbursementTransactionReference IN ($placeholders)',
        whereArgs: chunk,
        distinct: true,
      );
      for (final row in rows) {
        final reference =
            row['reimbursementTransactionReference']?.toString().trim();
        if (reference != null && reference.isNotEmpty) {
          stillLinked.add(reference);
        }
      }
    }

    final orphanedReferences = reimbursementReferences.difference(stillLinked);
    if (orphanedReferences.isEmpty) return const [];

    final categoryRows = await executor.query(
      'categories',
      columns: ['id'],
      where: 'builtInKey = ?',
      whereArgs: const [reimbursementBuiltInKey],
    );
    final reimbursementCategoryIds =
        categoryRows.map((row) => row['id']).whereType<int>().toSet();
    if (reimbursementCategoryIds.isEmpty) return const [];

    final syncRecords = <MapEntry<String, Map<String, dynamic>>>[];
    final orphaned = orphanedReferences.toList(growable: false);
    for (var start = 0; start < orphaned.length; start += _maxSqlVariables) {
      final end = math.min(start + _maxSqlVariables, orphaned.length);
      final chunk = orphaned.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await executor.query(
        'transactions',
        where: 'reference IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final row in rows) {
        final transaction = _transactionFromMap(row);
        if (transaction.type?.trim().toUpperCase() != 'CREDIT') continue;
        // A reimbursement can also carry another income category. Remove only
        // the stable built-in category and promote a surviving category.
        final remainingCategoryIds = transaction.selectedCategoryIds
            .where((id) => !reimbursementCategoryIds.contains(id))
            .toList(growable: false);
        if (remainingCategoryIds.length ==
            transaction.selectedCategoryIds.length) {
          continue;
        }

        final currentPrimary = transaction.categoryId;
        final nextPrimary = currentPrimary != null &&
                remainingCategoryIds.contains(currentPrimary)
            ? currentPrimary
            : (remainingCategoryIds.isEmpty
                ? null
                : remainingCategoryIds.first);
        final encodedCategoryIds = remainingCategoryIds.isEmpty
            ? null
            : jsonEncode(remainingCategoryIds);
        await executor.update(
          'transactions',
          {
            'categoryId': nextPrimary,
            'categoryIds': encodedCategoryIds,
          },
          where: 'reference = ?',
          whereArgs: [transaction.reference],
        );

        final syncRow = Map<String, dynamic>.from(row)
          ..['categoryId'] = nextPrimary
          ..['categoryIds'] = encodedCategoryIds
          ..remove('sourceSubscriptionId');
        syncRecords.add(MapEntry(transaction.reference, syncRow));
      }
    }
    return syncRecords;
  }

  Future<void> _enqueueTransactionDeletionChanges({
    required Iterable<String> deletedReferences,
    required List<MapEntry<String, Map<String, dynamic>>> categorySyncRecords,
  }) async {
    bool syncOn = false;
    try {
      syncOn = await DataSyncSettingsService.readEnabledFromPrefs();
    } catch (_) {}
    if (!syncOn) return;

    for (final ref in deletedReferences) {
      await SyncEnqueuer.instance.onEntityWritten(
        entity: SyncEntity.transactions,
        entityRef: ref,
        op: SyncOp.delete,
        deleteSnapshot: {'reference': ref},
      );
    }
    await SyncEnqueuer.instance.onManyWritten(
      entity: SyncEntity.transactions,
      records: categorySyncRecords,
    );
  }
}
