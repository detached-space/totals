import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/reimbursement_allocation.dart';
import 'package:totals/utils/transaction_amounts.dart';

class ReimbursementRepository {
  static const double _epsilon = 0.005;

  Future<List<ReimbursementAllocation>> getAllocations() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'reimbursement_allocations',
      orderBy: 'id ASC',
    );
    return rows.map(ReimbursementAllocation.fromDb).toList(growable: false);
  }

  Future<List<ReimbursementAllocation>> getForReimbursement(
    String reimbursementReference,
  ) async {
    final reference = reimbursementReference.trim();
    if (reference.isEmpty) return const <ReimbursementAllocation>[];
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'reimbursement_allocations',
      where: 'reimbursementTransactionReference = ?',
      whereArgs: [reference],
      orderBy: 'id ASC',
    );
    return rows.map(ReimbursementAllocation.fromDb).toList(growable: false);
  }

  Future<List<ReimbursementAllocation>> getForExpense(
    String expenseReference,
  ) async {
    final reference = expenseReference.trim();
    if (reference.isEmpty) return const <ReimbursementAllocation>[];
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'reimbursement_allocations',
      where: 'expenseTransactionReference = ?',
      whereArgs: [reference],
      orderBy: 'id ASC',
    );
    return rows.map(ReimbursementAllocation.fromDb).toList(growable: false);
  }

  Future<Map<String, double>> getAppliedTotalsForExpenses(
    Iterable<String> expenseReferences,
  ) async {
    final references = expenseReferences
        .map((reference) => reference.trim())
        .where((reference) => reference.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (references.isEmpty) return const <String, double>{};

    const chunkSize = 800;
    final db = await DatabaseHelper.instance.database;
    final totals = <String, double>{};
    for (var index = 0; index < references.length; index += chunkSize) {
      final end = (index + chunkSize).clamp(0, references.length);
      final chunk = references.sublist(index, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await db.rawQuery(
        '''
        SELECT expenseTransactionReference, SUM(appliedAmount) AS total
        FROM reimbursement_allocations
        WHERE expenseTransactionReference IN ($placeholders)
        GROUP BY expenseTransactionReference
        ''',
        chunk,
      );
      for (final row in rows) {
        final reference = row['expenseTransactionReference'] as String?;
        if (reference == null || reference.isEmpty) continue;
        totals[reference] = (row['total'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return totals;
  }

  Future<Set<String>> getLinkedReimbursementReferences(
    Iterable<String> reimbursementReferences,
  ) async {
    final references = reimbursementReferences
        .map((reference) => reference.trim())
        .where((reference) => reference.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (references.isEmpty) return <String>{};

    const chunkSize = 800;
    final db = await DatabaseHelper.instance.database;
    final linked = <String>{};
    for (var index = 0; index < references.length; index += chunkSize) {
      final end = (index + chunkSize).clamp(0, references.length);
      final chunk = references.sublist(index, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await db.query(
        'reimbursement_allocations',
        columns: const ['reimbursementTransactionReference'],
        where: 'reimbursementTransactionReference IN ($placeholders)',
        whereArgs: chunk,
        distinct: true,
      );
      for (final row in rows) {
        final reference =
            row['reimbursementTransactionReference']?.toString().trim();
        if (reference != null && reference.isNotEmpty) {
          linked.add(reference);
        }
      }
    }
    return linked;
  }

  Future<void> replaceForReimbursement({
    required String reimbursementTransactionReference,
    required Iterable<ReimbursementAllocationDraft> allocations,
  }) async {
    final reimbursementReference = reimbursementTransactionReference.trim();
    if (reimbursementReference.isEmpty) {
      throw ArgumentError.value(
        reimbursementTransactionReference,
        'reimbursementTransactionReference',
        'A transaction reference is required.',
      );
    }

    final normalizedByExpense = <String, double>{};
    for (final allocation in allocations) {
      final expenseReference = allocation.expenseTransactionReference.trim();
      final amount = allocation.appliedAmount;
      if (expenseReference.isEmpty || !amount.isFinite || amount <= _epsilon) {
        continue;
      }
      normalizedByExpense.update(
        expenseReference,
        (current) => current + amount,
        ifAbsent: () => amount,
      );
    }

    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final reimbursementRows = await txn.query(
        'transactions',
        where: 'reference = ?',
        whereArgs: [reimbursementReference],
        limit: 1,
      );
      if (reimbursementRows.isEmpty) {
        throw StateError('The reimbursement transaction no longer exists.');
      }
      final reimbursement = reimbursementRows.single;
      if ((reimbursement['type'] as String?)?.toUpperCase() != 'CREDIT') {
        throw StateError('Only credit transactions can be reimbursements.');
      }
      final reimbursementAmount =
          ((reimbursement['amount'] as num?)?.toDouble() ?? 0.0).abs();
      final totalRequested = normalizedByExpense.values.fold<double>(
        0.0,
        (sum, amount) => sum + amount,
      );
      if (totalRequested - reimbursementAmount > _epsilon) {
        throw StateError(
          'Applied reimbursements cannot exceed the received amount.',
        );
      }

      for (final entry in normalizedByExpense.entries) {
        final expenseRows = await txn.query(
          'transactions',
          where: 'reference = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (expenseRows.isEmpty) {
          throw StateError('A selected expense no longer exists.');
        }
        final expense = expenseRows.single;
        if ((expense['type'] as String?)?.toUpperCase() != 'DEBIT') {
          throw StateError('Reimbursements can only be applied to expenses.');
        }

        final otherRows = await txn.rawQuery(
          '''
          SELECT COALESCE(SUM(appliedAmount), 0) AS total
          FROM reimbursement_allocations
          WHERE expenseTransactionReference = ?
            AND reimbursementTransactionReference <> ?
          ''',
          [entry.key, reimbursementReference],
        );
        final alreadyApplied =
            (otherRows.single['total'] as num?)?.toDouble() ?? 0.0;
        final expenseAmount = transactionDebitOutflowFromValues(
          amount: (expense['amount'] as num?)?.toDouble() ?? 0.0,
          serviceCharge: (expense['serviceCharge'] as num?)?.toDouble(),
          vat: (expense['vat'] as num?)?.toDouble(),
        );
        final available = expenseAmount - alreadyApplied;
        if (entry.value - available > _epsilon) {
          throw StateError(
            'An allocation exceeds the amount still available on an expense.',
          );
        }
      }

      await txn.delete(
        'reimbursement_allocations',
        where: 'reimbursementTransactionReference = ?',
        whereArgs: [reimbursementReference],
      );

      final now = DateTime.now().toIso8601String();
      for (final entry in normalizedByExpense.entries) {
        await txn.insert(
          'reimbursement_allocations',
          {
            'reimbursementTransactionReference': reimbursementReference,
            'expenseTransactionReference': entry.key,
            'appliedAmount': entry.value,
            'createdAt': now,
            'updatedAt': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteForReimbursement(String reimbursementReference) async {
    final reference = reimbursementReference.trim();
    if (reference.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'reimbursement_allocations',
      where: 'reimbursementTransactionReference = ?',
      whereArgs: [reference],
    );
  }

  Future<void> clearAll() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('reimbursement_allocations');
  }
}
