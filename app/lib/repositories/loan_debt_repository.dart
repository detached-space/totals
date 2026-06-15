import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/loan_debt_entry.dart';

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
  }) async {
    final normalizedReference = transactionReference.trim();
    final normalizedName = normalizeLoanDebtPersonName(personName);
    if (normalizedReference.isEmpty || normalizedName.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'loan_debt_entries',
      {
        'transactionReference': normalizedReference,
        'personName': normalizedName,
        'direction': direction.storageValue,
        'status': LoanDebtStatus.active.storageValue,
        'resolvedAt': null,
        'createdAt': now,
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
  }

  Future<void> linkRepayment({
    required String repaymentTransactionReference,
    required String loanDebtTransactionReference,
    required double appliedAmount,
  }) async {
    final normalizedRepaymentReference = repaymentTransactionReference.trim();
    final normalizedLoanDebtReference = loanDebtTransactionReference.trim();
    final normalizedAmount = appliedAmount.isFinite ? appliedAmount.abs() : 0;
    if (normalizedRepaymentReference.isEmpty ||
        normalizedLoanDebtReference.isEmpty ||
        normalizedAmount <= 0) {
      return;
    }

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'loan_debt_repayments',
      {
        'repaymentTransactionReference': normalizedRepaymentReference,
        'loanDebtTransactionReference': normalizedLoanDebtReference,
        'appliedAmount': normalizedAmount,
        'createdAt': now,
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteRepaymentForTransaction(String repaymentReference) async {
    final normalizedReference = repaymentReference.trim();
    if (normalizedReference.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'loan_debt_repayments',
      where: 'repaymentTransactionReference = ?',
      whereArgs: [normalizedReference],
    );
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
    await db.delete(
      'loan_debt_repayments',
      where:
          'loanDebtTransactionReference = ? OR repaymentTransactionReference = ?',
      whereArgs: [normalizedReference, normalizedReference],
    );
  }
}

String normalizeLoanDebtPersonName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
