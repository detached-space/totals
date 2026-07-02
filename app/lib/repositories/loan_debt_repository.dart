import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/loan_debt_entry.dart';
import 'package:totals/services/notification_service.dart';

class LoanDebtRepaymentAllocation {
  final String loanDebtTransactionReference;
  final double appliedAmount;

  const LoanDebtRepaymentAllocation({
    required this.loanDebtTransactionReference,
    required this.appliedAmount,
  });
}

class LoanDebtReturnReminderCandidate {
  final String transactionReference;
  final String personName;
  final LoanDebtDirection direction;
  final DateTime returnDate;
  final double? amount;

  const LoanDebtReturnReminderCandidate({
    required this.transactionReference,
    required this.personName,
    required this.direction,
    required this.returnDate,
    required this.amount,
  });
}

class LoanDebtRepository {
  Future<List<LoanDebtEntry>> getEntries() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'loan_debt_entries',
      orderBy: 'updatedAt DESC, id DESC',
    );
    return rows.map(LoanDebtEntry.fromDb).toList(growable: false);
  }

  Future<List<LoanDebtRepayment>> getRepayments() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'loan_debt_repayments',
      orderBy: 'updatedAt DESC, id DESC',
    );
    return rows.map(LoanDebtRepayment.fromDb).toList(growable: false);
  }

  Future<LoanDebtRepayment?> getRepaymentForTransaction(
    String repaymentReference,
  ) async {
    final normalizedReference = repaymentReference.trim();
    if (normalizedReference.isEmpty) return null;

    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'loan_debt_repayments',
      where: 'repaymentTransactionReference = ?',
      whereArgs: [normalizedReference],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LoanDebtRepayment.fromDb(rows.first);
  }

  Future<List<LoanDebtRepayment>> getRepaymentsForTransaction(
    String repaymentReference,
  ) async {
    final normalizedReference = repaymentReference.trim();
    if (normalizedReference.isEmpty) return const <LoanDebtRepayment>[];

    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'loan_debt_repayments',
      where: 'repaymentTransactionReference = ?',
      whereArgs: [normalizedReference],
      orderBy: 'id ASC',
    );
    return rows.map(LoanDebtRepayment.fromDb).toList(growable: false);
  }

  Future<LoanDebtEntry?> getEntryForTransaction(String reference) async {
    final normalizedReference = reference.trim();
    if (normalizedReference.isEmpty) return null;

    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'loan_debt_entries',
      where: 'transactionReference = ?',
      whereArgs: [normalizedReference],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LoanDebtEntry.fromDb(rows.first);
  }

  Future<List<String>> getKnownPeople() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT personName, MAX(updatedAt) AS lastUpdated
      FROM loan_debt_entries
      WHERE TRIM(personName) <> ''
      GROUP BY LOWER(TRIM(personName))
      ORDER BY lastUpdated DESC, personName COLLATE NOCASE ASC
    ''');

    return rows
        .map((row) => (row['personName'] as String?)?.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> upsertTransactionPerson({
    required String transactionReference,
    required String personName,
    required LoanDebtDirection direction,
    double? principalAmount,
    DateTime? returnDate,
    bool replaceReturnDate = false,
  }) async {
    final normalizedReference = transactionReference.trim();
    final normalizedName = normalizeLoanDebtPersonName(personName);
    if (normalizedReference.isEmpty || normalizedName.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    final existingRows = await db.query(
      'loan_debt_entries',
      where: 'transactionReference = ?',
      whereArgs: [normalizedReference],
      limit: 1,
    );
    final existing =
        existingRows.isEmpty ? null : LoanDebtEntry.fromDb(existingRows.first);
    final now = DateTime.now();
    final existingIsSurplus =
        existing?.source == LoanDebtEntrySource.repaymentSurplus;
    final normalizedPrincipal =
        principalAmount != null && principalAmount.isFinite
            ? principalAmount.abs()
            : (existingIsSurplus ? existing?.principalAmount : null);
    final normalizedReturnDate = _normalizeReturnDate(returnDate);
    final effectiveReturnDate =
        replaceReturnDate ? normalizedReturnDate : existing?.returnDate;
    final source = existingIsSurplus
        ? LoanDebtEntrySource.repaymentSurplus
        : LoanDebtEntrySource.transaction;
    final data = {
      'transactionReference': normalizedReference,
      'personName': normalizedName,
      'direction': direction.storageValue,
      'status': LoanDebtStatus.active.storageValue,
      'principalAmount': normalizedPrincipal,
      'source': source.storageValue,
      'returnDate': effectiveReturnDate?.toIso8601String(),
      'resolvedAt': null,
      'createdAt': (existing?.createdAt ?? now).toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };

    if (existing == null) {
      await db.insert('loan_debt_entries', data);
    } else {
      await db.update(
        'loan_debt_entries',
        data,
        where: 'transactionReference = ?',
        whereArgs: [normalizedReference],
      );
    }

    await _syncReturnReminderForStoredEntry(db, normalizedReference);
  }

  Future<void> updateEntryStatus({
    required String transactionReference,
    required LoanDebtStatus status,
  }) async {
    final normalizedReference = transactionReference.trim();
    if (normalizedReference.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'loan_debt_entries',
      {
        'status': status.storageValue,
        'resolvedAt': status == LoanDebtStatus.active ? null : now,
        'updatedAt': now,
      },
      where: 'transactionReference = ?',
      whereArgs: [normalizedReference],
    );

    await _syncReturnReminderForStoredEntry(db, normalizedReference);
  }

  Future<void> linkRepayment({
    required String repaymentTransactionReference,
    required String loanDebtTransactionReference,
    required double appliedAmount,
  }) async {
    await saveRepaymentFlow(
      repaymentTransactionReference: repaymentTransactionReference,
      allocations: [
        LoanDebtRepaymentAllocation(
          loanDebtTransactionReference: loanDebtTransactionReference,
          appliedAmount: appliedAmount,
        ),
      ],
    );
  }

  Future<void> saveRepaymentFlow({
    required String repaymentTransactionReference,
    required List<LoanDebtRepaymentAllocation> allocations,
    String? surplusPersonName,
    LoanDebtDirection? surplusDirection,
    double? surplusPrincipalAmount,
    bool allowResolvedTargets = false,
  }) async {
    final normalizedRepaymentReference = repaymentTransactionReference.trim();
    if (normalizedRepaymentReference.isEmpty) return;

    final normalizedAllocations = <LoanDebtRepaymentAllocation>[];
    final seenLoanDebtReferences = <String>{};
    for (final allocation in allocations) {
      final loanDebtReference = allocation.loanDebtTransactionReference.trim();
      final amount = allocation.appliedAmount.isFinite
          ? allocation.appliedAmount.abs()
          : 0.0;
      if (loanDebtReference.isEmpty || amount <= 0) continue;
      if (!seenLoanDebtReferences.add(loanDebtReference)) continue;
      normalizedAllocations.add(
        LoanDebtRepaymentAllocation(
          loanDebtTransactionReference: loanDebtReference,
          appliedAmount: amount,
        ),
      );
    }

    final normalizedSurplusName =
        normalizeLoanDebtPersonName(surplusPersonName ?? '');
    final normalizedSurplusAmount =
        surplusPrincipalAmount != null && surplusPrincipalAmount.isFinite
            ? surplusPrincipalAmount.abs()
            : 0.0;
    final shouldSaveSurplus = normalizedSurplusName.isNotEmpty &&
        surplusDirection != null &&
        normalizedSurplusAmount > 0;

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final existingRepaymentRows = await db.query(
      'loan_debt_repayments',
      columns: ['loanDebtTransactionReference'],
      where: 'repaymentTransactionReference = ?',
      whereArgs: [normalizedRepaymentReference],
    );
    final affectedLoanDebtReferences = <String>{
      for (final row in existingRepaymentRows)
        if (((row['loanDebtTransactionReference'] as String?) ?? '')
            .trim()
            .isNotEmpty)
          ((row['loanDebtTransactionReference'] as String?) ?? '').trim(),
      for (final allocation in normalizedAllocations)
        allocation.loanDebtTransactionReference,
      normalizedRepaymentReference,
    };

    await db.transaction((txn) async {
      if (normalizedAllocations.isNotEmpty || shouldSaveSurplus) {
        await _requireTransactionExists(
          txn,
          normalizedRepaymentReference,
          role: 'Repayment',
        );
      }
      await _validateRepaymentAllocations(
        txn,
        repaymentTransactionReference: normalizedRepaymentReference,
        allocations: normalizedAllocations,
        allowResolvedTargets: allowResolvedTargets,
      );

      await txn.delete(
        'loan_debt_repayments',
        where: 'repaymentTransactionReference = ?',
        whereArgs: [normalizedRepaymentReference],
      );

      final batch = txn.batch();
      for (final allocation in normalizedAllocations) {
        batch.insert(
          'loan_debt_repayments',
          {
            'repaymentTransactionReference': normalizedRepaymentReference,
            'loanDebtTransactionReference':
                allocation.loanDebtTransactionReference,
            'appliedAmount': allocation.appliedAmount,
            'createdAt': nowIso,
            'updatedAt': nowIso,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);

      if (shouldSaveSurplus) {
        final existingRows = await txn.query(
          'loan_debt_entries',
          where: 'transactionReference = ?',
          whereArgs: [normalizedRepaymentReference],
          limit: 1,
        );
        final existing = existingRows.isEmpty
            ? null
            : LoanDebtEntry.fromDb(existingRows.first);
        final data = {
          'transactionReference': normalizedRepaymentReference,
          'personName': normalizedSurplusName,
          'direction': surplusDirection.storageValue,
          'status': LoanDebtStatus.active.storageValue,
          'principalAmount': normalizedSurplusAmount,
          'source': LoanDebtEntrySource.repaymentSurplus.storageValue,
          'resolvedAt': null,
          'createdAt': (existing?.createdAt ?? now).toIso8601String(),
          'updatedAt': nowIso,
        };
        if (existing == null) {
          await txn.insert('loan_debt_entries', data);
        } else {
          await txn.update(
            'loan_debt_entries',
            data,
            where: 'transactionReference = ?',
            whereArgs: [normalizedRepaymentReference],
          );
        }
      } else {
        await txn.delete(
          'loan_debt_entries',
          where:
              "transactionReference = ? AND (source = ? OR principalAmount IS NOT NULL)",
          whereArgs: [
            normalizedRepaymentReference,
            LoanDebtEntrySource.repaymentSurplus.storageValue,
          ],
        );
        await txn.delete(
          'loan_debt_repayments',
          where: 'loanDebtTransactionReference = ?',
          whereArgs: [normalizedRepaymentReference],
        );
      }
    });

    for (final reference in affectedLoanDebtReferences) {
      await _syncReturnReminderForStoredEntry(db, reference);
    }
  }

  Future<void> deleteRepaymentForTransaction(String repaymentReference) async {
    final normalizedReference = repaymentReference.trim();
    if (normalizedReference.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    final existingRepaymentRows = await db.query(
      'loan_debt_repayments',
      columns: ['loanDebtTransactionReference'],
      where: 'repaymentTransactionReference = ?',
      whereArgs: [normalizedReference],
    );
    final affectedLoanDebtReferences = <String>{
      for (final row in existingRepaymentRows)
        if (((row['loanDebtTransactionReference'] as String?) ?? '')
            .trim()
            .isNotEmpty)
          ((row['loanDebtTransactionReference'] as String?) ?? '').trim(),
      normalizedReference,
    };
    await db.transaction((txn) async {
      await txn.delete(
        'loan_debt_repayments',
        where: 'repaymentTransactionReference = ?',
        whereArgs: [normalizedReference],
      );
      await txn.delete(
        'loan_debt_entries',
        where:
            "transactionReference = ? AND (source = ? OR principalAmount IS NOT NULL)",
        whereArgs: [
          normalizedReference,
          LoanDebtEntrySource.repaymentSurplus.storageValue,
        ],
      );
      await txn.delete(
        'loan_debt_repayments',
        where: 'loanDebtTransactionReference = ?',
        whereArgs: [normalizedReference],
      );
    });
    for (final reference in affectedLoanDebtReferences) {
      await _syncReturnReminderForStoredEntry(db, reference);
    }
  }

  Future<void> deleteEntryForTransaction(String reference) async {
    final normalizedReference = reference.trim();
    if (normalizedReference.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'loan_debt_entries',
      where: 'transactionReference = ?',
      whereArgs: [normalizedReference],
    );
    await _cancelReturnReminder(normalizedReference);
  }

  Future<void> syncReturnReminders() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'loan_debt_entries',
      columns: ['transactionReference'],
    );
    for (final row in rows) {
      final reference = (row['transactionReference'] as String?)?.trim();
      if (reference == null || reference.isEmpty) continue;
      await _syncReturnReminderForStoredEntry(db, reference);
    }
  }

  Future<List<LoanDebtReturnReminderCandidate>>
      getActiveFutureReturnReminderCandidates() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'loan_debt_entries',
      where: 'status = ? AND returnDate IS NOT NULL',
      whereArgs: [LoanDebtStatus.active.storageValue],
      orderBy: 'returnDate ASC, updatedAt DESC, id DESC',
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final candidates = <LoanDebtReturnReminderCandidate>[];

    for (final row in rows) {
      final entry = LoanDebtEntry.fromDb(row);
      final normalizedReference = entry.transactionReference.trim();
      final normalizedName = normalizeLoanDebtPersonName(entry.personName);
      final returnDate = _normalizeReturnDate(entry.returnDate);
      if (normalizedReference.isEmpty ||
          normalizedName.isEmpty ||
          returnDate == null ||
          returnDate.isBefore(today)) {
        continue;
      }

      final originalAmount = await _amountForEntry(
        db,
        normalizedReference,
        principalAmount: entry.principalAmount,
      );
      final repaidAmount = await _totalAppliedAmountForLoanDebtReference(
        db,
        normalizedReference,
      );
      final remainingAmount = originalAmount == null
          ? null
          : (originalAmount - repaidAmount <= 0.005
              ? 0.0
              : originalAmount - repaidAmount);
      if (remainingAmount == 0) continue;

      candidates.add(
        LoanDebtReturnReminderCandidate(
          transactionReference: normalizedReference,
          personName: normalizedName,
          direction: entry.direction,
          returnDate: returnDate,
          amount: remainingAmount != null && remainingAmount > 0
              ? remainingAmount
              : originalAmount,
        ),
      );
    }

    return candidates;
  }

  Future<int> showActiveFutureReturnReminderTestNotifications() async {
    final candidates = await getActiveFutureReturnReminderCandidates();
    var shownCount = 0;
    for (final candidate in candidates) {
      final shown =
          await NotificationService.instance.showLoanDebtReturnReminderNow(
        transactionReference: candidate.transactionReference,
        personName: candidate.personName,
        direction: candidate.direction,
        amount: candidate.amount,
        useTestId: true,
        ignoreEnabledCheck: true,
      );
      if (shown) shownCount++;
    }
    return shownCount;
  }

  Future<void> _syncReturnReminderForStoredEntry(
    DatabaseExecutor executor,
    String reference,
  ) async {
    final normalizedReference = reference.trim();
    if (normalizedReference.isEmpty) return;

    final rows = await executor.query(
      'loan_debt_entries',
      where: 'transactionReference = ?',
      whereArgs: [normalizedReference],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _cancelReturnReminder(normalizedReference);
      return;
    }

    final entry = LoanDebtEntry.fromDb(rows.first);
    final originalAmount = await _amountForEntry(
      executor,
      normalizedReference,
      principalAmount: entry.principalAmount,
    );
    final repaidAmount = await _totalAppliedAmountForLoanDebtReference(
      executor,
      normalizedReference,
    );
    final remainingAmount = originalAmount == null
        ? null
        : (originalAmount - repaidAmount <= 0.005
            ? 0.0
            : originalAmount - repaidAmount);
    final effectiveStatus =
        entry.status == LoanDebtStatus.active && remainingAmount == 0
            ? LoanDebtStatus.settled
            : entry.status;

    await _syncReturnReminder(
      transactionReference: normalizedReference,
      personName: entry.personName,
      direction: entry.direction,
      status: effectiveStatus,
      returnDate: entry.returnDate,
      amount: remainingAmount != null && remainingAmount > 0
          ? remainingAmount
          : originalAmount,
    );
  }

  Future<void> _syncReturnReminder({
    required String transactionReference,
    required String personName,
    required LoanDebtDirection direction,
    required LoanDebtStatus status,
    required DateTime? returnDate,
    required double? amount,
  }) async {
    final normalizedReference = transactionReference.trim();
    final normalizedName = normalizeLoanDebtPersonName(personName);
    if (normalizedReference.isEmpty) return;

    if (status != LoanDebtStatus.active ||
        normalizedName.isEmpty ||
        returnDate == null) {
      await _cancelReturnReminder(normalizedReference);
      return;
    }

    await NotificationService.instance.scheduleLoanDebtReturnReminder(
      transactionReference: normalizedReference,
      personName: normalizedName,
      direction: direction,
      returnDate: returnDate,
      amount: amount,
    );
  }

  Future<void> _cancelReturnReminder(String transactionReference) async {
    await NotificationService.instance.cancelLoanDebtReturnReminder(
      transactionReference,
    );
  }

  Future<double?> _amountForEntry(
    DatabaseExecutor executor,
    String reference, {
    double? principalAmount,
  }) async {
    if (principalAmount != null && principalAmount.isFinite) {
      return principalAmount.abs();
    }

    final rows = await executor.query(
      'transactions',
      columns: ['amount'],
      where: 'reference = ?',
      whereArgs: [reference],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['amount'] as num?)?.toDouble().abs();
  }

  Future<double> _totalAppliedAmountForLoanDebtReference(
    DatabaseExecutor executor,
    String loanDebtReference,
  ) async {
    final rows = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(appliedAmount), 0) AS total
      FROM loan_debt_repayments
      WHERE loanDebtTransactionReference = ?
      ''',
      [loanDebtReference],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<void> _requireTransactionExists(
    DatabaseExecutor executor,
    String reference, {
    required String role,
  }) async {
    final rows = await executor.query(
      'transactions',
      columns: ['reference'],
      where: 'reference = ?',
      whereArgs: [reference],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('$role transaction does not exist.');
    }
  }

  Future<void> _validateRepaymentAllocations(
    DatabaseExecutor executor, {
    required String repaymentTransactionReference,
    required List<LoanDebtRepaymentAllocation> allocations,
    required bool allowResolvedTargets,
  }) async {
    if (allocations.isEmpty) return;

    final repaymentRows = await executor.query(
      'transactions',
      columns: ['type'],
      where: 'reference = ?',
      whereArgs: [repaymentTransactionReference],
      limit: 1,
    );
    if (repaymentRows.isEmpty) {
      throw StateError('Repayment transaction does not exist.');
    }

    final repaymentDirection = _repaymentDirectionForTransactionType(
      repaymentRows.first['type'] as String?,
    );
    final existingRows = await executor.query(
      'loan_debt_repayments',
      columns: ['loanDebtTransactionReference'],
      where: 'repaymentTransactionReference = ?',
      whereArgs: [repaymentTransactionReference],
    );
    final existingTargetReferences = existingRows
        .map((row) => (row['loanDebtTransactionReference'] as String?)?.trim())
        .whereType<String>()
        .where((reference) => reference.isNotEmpty)
        .toSet();

    for (final allocation in allocations) {
      final loanDebtReference = allocation.loanDebtTransactionReference.trim();
      if (loanDebtReference == repaymentTransactionReference) {
        throw StateError('A repayment cannot be applied to itself.');
      }

      final entryRows = await executor.query(
        'loan_debt_entries',
        where: 'transactionReference = ?',
        whereArgs: [loanDebtReference],
        limit: 1,
      );
      if (entryRows.isEmpty) {
        throw StateError('Loan or debt entry does not exist.');
      }

      final entry = LoanDebtEntry.fromDb(entryRows.first);
      if (entry.personName.trim().isEmpty) {
        throw StateError('Loan or debt entry needs a person.');
      }
      if (entry.direction != repaymentDirection) {
        throw StateError('Repayment direction does not match loan or debt.');
      }
      final isExistingTarget = existingTargetReferences.contains(
        loanDebtReference,
      );
      if (entry.status != LoanDebtStatus.active &&
          !allowResolvedTargets &&
          !isExistingTarget) {
        throw StateError('Loan or debt entry is not active.');
      }

      final loanTransactionRows = await executor.query(
        'transactions',
        columns: ['amount'],
        where: 'reference = ?',
        whereArgs: [loanDebtReference],
        limit: 1,
      );
      if (loanTransactionRows.isEmpty) {
        throw StateError('Loan or debt transaction does not exist.');
      }

      final originalAmount = _originalAmountForEntry(
        entry,
        loanTransactionRows.first['amount'],
      );
      final alreadyApplied = await _appliedAmountForLoanDebtReference(
        executor,
        loanDebtReference: loanDebtReference,
        excludingRepaymentReference: repaymentTransactionReference,
      );
      final remaining = originalAmount - alreadyApplied;
      if (allocation.appliedAmount - remaining > 0.005) {
        throw StateError('Repayment exceeds the remaining balance.');
      }
    }
  }

  Future<double> _appliedAmountForLoanDebtReference(
    DatabaseExecutor executor, {
    required String loanDebtReference,
    required String excludingRepaymentReference,
  }) async {
    final rows = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(appliedAmount), 0) AS total
      FROM loan_debt_repayments
      WHERE loanDebtTransactionReference = ?
        AND repaymentTransactionReference <> ?
      ''',
      [loanDebtReference, excludingRepaymentReference],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }
}

String normalizeLoanDebtPersonName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

DateTime? _normalizeReturnDate(DateTime? value) {
  if (value == null) return null;
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

LoanDebtDirection _repaymentDirectionForTransactionType(String? type) {
  return type?.trim().toUpperCase() == 'CREDIT'
      ? LoanDebtDirection.lent
      : LoanDebtDirection.borrowed;
}

double _originalAmountForEntry(LoanDebtEntry entry, Object? transactionAmount) {
  final principalAmount = entry.principalAmount;
  if (principalAmount != null && principalAmount.isFinite) {
    return principalAmount.abs();
  }
  return ((transactionAmount as num?)?.toDouble() ?? 0).abs();
}
