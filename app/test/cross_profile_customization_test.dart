import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';

/// Cross-profile multi-account customization (see money_page / account_identity).
///
/// Locks the invariants introduced when "move transactions" and "set default"
/// were made to span profiles:
///   * the default is ONE account per bank, global across every profile;
///   * moving a transaction to another profile's account relocates its profile.
///
/// Runs against a REAL sqlite (ffi) database opened through [DatabaseHelper] at
/// the current schema version, so the enforced index shape is the real one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // The active profile is read from prefs by several code paths.
    SharedPreferences.setMockInitialValues({'active_profile_id': 1});
    final dbPath = p.join(await getDatabasesPath(), 'totals.db');
    await deleteDatabase(dbPath);
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await db.delete('transactions');
    await db.delete('accounts');
  });

  Future<void> insertAccount(
    String number,
    int bank,
    int profileId, {
    bool isDefault = false,
  }) async {
    await db.insert('accounts', <String, Object?>{
      'accountNumber': number,
      'bank': bank,
      'balance': 0,
      'accountHolderName': number,
      'profileId': profileId,
      'includeInTotals': 1,
      'isDormant': 0,
      'isDefault': isDefault ? 1 : 0,
    });
  }

  Future<void> insertTransaction(String reference, {int profileId = 1}) async {
    await db.insert('transactions', <String, Object?>{
      'amount': 100.0,
      'reference': reference,
      'type': 'CREDIT',
      'bankId': 7,
      'ownerAccountNumber': 'AW-P1',
      'ownerAssignmentSource': Transaction.automaticOwnerAssignment,
      'profileId': profileId,
    });
  }

  test('a bank may have only ONE default account, global across profiles',
      () async {
    await insertAccount('AW-P1', 7, 1, isDefault: true);
    await insertAccount('AW-P2', 7, 2); // same bank, different profile

    // The rebuilt unique index is on (bank) alone, so a second default for the
    // same bank — even in another profile — must be rejected.
    await expectLater(
      db.update(
        'accounts',
        <String, Object?>{'isDefault': 1},
        where: 'accountNumber = ?',
        whereArgs: <Object?>['AW-P2'],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('setDefaultAccount clears the previous default in every profile',
      () async {
    await insertAccount('AW-P1', 7, 1, isDefault: true);
    await insertAccount('AW-P2', 7, 2);

    final ok = await AccountRepository()
        .setDefaultAccount(accountNumber: 'AW-P2', bank: 7);
    expect(ok, isTrue);

    final rows = await db.query(
      'accounts',
      columns: <String>['accountNumber', 'isDefault'],
      where: 'bank = 7',
    );
    final byNumber = <String, Object?>{
      for (final r in rows) r['accountNumber'] as String: r['isDefault'],
    };
    expect(byNumber['AW-P2'], 1);
    expect(byNumber['AW-P1'], 0,
        reason: 'the old default must be cleared even in its own profile');
  });

  test('updateTransactionOwnership relocates the transaction to the target '
      'account profile', () async {
    await insertAccount('AW-P1', 7, 1, isDefault: true);
    await insertAccount('AW-P2', 7, 2);
    await insertTransaction('TX1', profileId: 1);

    final moved = await TransactionRepository().updateTransactionOwnership(
      reference: 'TX1',
      ownerAccountNumber: 'AW-P2',
      ownerAssignmentSource: Transaction.manualOwnerAssignment,
      targetProfileId: 2,
    );
    expect(moved, isTrue);

    final row = (await db.query(
      'transactions',
      where: 'reference = ?',
      whereArgs: <Object?>['TX1'],
    ))
        .single;
    expect(row['ownerAccountNumber'], 'AW-P2');
    expect(row['ownerAssignmentSource'], Transaction.manualOwnerAssignment);
    expect(row['profileId'], 2, reason: 'moved into the target account profile');
  });

  test('updateTransactionOwnership without a target profile leaves the profile '
      'untouched (same-profile move)', () async {
    await insertAccount('AW-P1', 7, 1, isDefault: true);
    await insertAccount('AW-P1B', 7, 1); // second account, SAME profile
    await insertTransaction('TX1', profileId: 1);

    await TransactionRepository().updateTransactionOwnership(
      reference: 'TX1',
      ownerAccountNumber: 'AW-P1B',
      ownerAssignmentSource: Transaction.manualOwnerAssignment,
      targetProfileId: 1,
    );

    final row = (await db.query(
      'transactions',
      where: 'reference = ?',
      whereArgs: <Object?>['TX1'],
    ))
        .single;
    expect(row['ownerAccountNumber'], 'AW-P1B');
    expect(row['profileId'], 1);
  });

  test('moveTransactionsToAccount relocates every selected transaction',
      () async {
    await insertAccount('AW-P1', 7, 1, isDefault: true);
    await insertAccount('AW-P2', 7, 2);
    for (final ref in <String>['TX1', 'TX2', 'TX3']) {
      await insertTransaction(ref, profileId: 1);
    }

    final moved = await TransactionRepository().moveTransactionsToAccount(
      references: <String>['TX1', 'TX2', 'TX3'],
      ownerAccountNumber: 'AW-P2',
      targetProfileId: 2,
    );
    expect(moved, 3);

    final relocated = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM transactions '
      'WHERE profileId = 2 AND ownerAccountNumber = ?',
      <Object?>['AW-P2'],
    ));
    expect(relocated, 3);
  });
}
