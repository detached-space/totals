import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/account.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/data_sync/sync_enqueuer.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/constants/cash_constants.dart';

class AccountRepository {
  final ProfileRepository _profileRepo = ProfileRepository();

  Future<int?> _getActiveProfileId() async {
    return await _profileRepo.getActiveProfileId();
  }

  Future<void> _ensureCashAccount(Database db, int? profileId) async {
    final whereParts = <String>[
      'bank = ?',
      'accountNumber = ?',
    ];
    final whereArgs = <dynamic>[
      CashConstants.bankId,
      CashConstants.defaultAccountNumber,
    ];
    if (profileId != null) {
      whereParts.add('profileId = ?');
      whereArgs.add(profileId);
    }

    final existing = await db.query(
      'accounts',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    await db.insert(
      'accounts',
      {
        'accountNumber': CashConstants.defaultAccountNumber,
        'bank': CashConstants.bankId,
        'balance': 0.0,
        'accountHolderName': CashConstants.defaultAccountHolderName,
        'settledBalance': 0.0,
        'pendingCredit': 0.0,
        if (profileId != null) 'profileId': profileId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Account>> getAccounts() async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    await _ensureCashAccount(db, activeProfileId);
    
    final List<Map<String, dynamic>> maps = activeProfileId != null
        ? await db.query(
            'accounts',
            where: 'profileId = ?',
            whereArgs: [activeProfileId],
          )
        : await db.query('accounts');

    return maps.map((map) {
      return Account.fromJson({
        'accountNumber': map['accountNumber'],
        'bank': map['bank'],
        'balance': map['balance'],
        'accountHolderName': map['accountHolderName'],
        'settledBalance': map['settledBalance'],
        'pendingCredit': map['pendingCredit'],
        'profileId': map['profileId'],
        'smsSubscriptionId': map['smsSubscriptionId'],
        'includeInTotals': map['includeInTotals'],
        'isDormant': map['isDormant'],
        'isDefault': map['isDefault'],
      });
    }).toList();
  }

  /// All accounts across every profile, unfiltered. Used by SMS ingestion to
  /// match a message to its owning account regardless of the active profile.
  Future<List<Account>> getAllAccounts() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('accounts');

    return maps.map((map) {
      return Account.fromJson({
        'accountNumber': map['accountNumber'],
        'bank': map['bank'],
        'balance': map['balance'],
        'accountHolderName': map['accountHolderName'],
        'settledBalance': map['settledBalance'],
        'pendingCredit': map['pendingCredit'],
        'profileId': map['profileId'],
        'smsSubscriptionId': map['smsSubscriptionId'],
        'includeInTotals': map['includeInTotals'],
        'isDormant': map['isDormant'],
        'isDefault': map['isDefault'],
      });
    }).toList();
  }

  Future<void> saveAccount(Account account) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    
    // Use account's profileId if provided, otherwise use active profile
    final profileId = account.profileId ?? activeProfileId;

    await db.insert(
      'accounts',
      {
        'accountNumber': account.accountNumber,
        'bank': account.bank,
        'balance': account.balance,
        'accountHolderName': account.accountHolderName,
        'settledBalance': account.settledBalance,
        'pendingCredit': account.pendingCredit,
        'profileId': profileId,
        'smsSubscriptionId': account.smsSubscriptionId,
        'includeInTotals': account.includeInTotals ? 1 : 0,
        'isDormant': account.isDormant ? 1 : 0,
        'isDefault': account.isDefault ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await SyncEnqueuer.instance.onEntityWritten(
      entity: SyncEntity.accounts,
      entityRef: '${account.accountNumber}|${account.bank}',
      op: SyncOp.upsert,
      row: {
        'accountNumber': account.accountNumber,
        'bank': account.bank,
        'profileId': profileId,
      },
    );
  }

  Future<void> saveAllAccounts(List<Account> accounts) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    final batch = db.batch();
    final syncRecords = <MapEntry<String, Map<String, dynamic>>>[];

    for (var account in accounts) {
      // Use account's profileId if provided, otherwise use active profile
      final profileId = account.profileId ?? activeProfileId;

      batch.insert(
        'accounts',
        {
          'accountNumber': account.accountNumber,
          'bank': account.bank,
          'balance': account.balance,
          'accountHolderName': account.accountHolderName,
          'settledBalance': account.settledBalance,
          'pendingCredit': account.pendingCredit,
          'profileId': profileId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      syncRecords.add(MapEntry('${account.accountNumber}|${account.bank}', {
        'accountNumber': account.accountNumber,
        'bank': account.bank,
        'profileId': profileId,
      }));
    }

    await batch.commit(noResult: true);

    await SyncEnqueuer.instance.onManyWritten(
      entity: SyncEntity.accounts,
      records: syncRecords,
    );
  }

  /// Updates the include-in-totals / dormant preferences for one account.
  /// Marking an account dormant also removes it from totals. Accounts are
  /// UNIQUE by (accountNumber, bank), so match on that pair — filtering by
  /// profileId would miss migrated rows with a NULL profileId.
  Future<bool> updateAccountPreferences({
    required String accountNumber,
    required int bank,
    bool? includeInTotals,
    bool? isDormant,
  }) async {
    if (includeInTotals == null && isDormant == null) return false;

    final db = await DatabaseHelper.instance.database;
    final values = <String, Object?>{
      if (includeInTotals != null) 'includeInTotals': includeInTotals ? 1 : 0,
      if (isDormant != null) 'isDormant': isDormant ? 1 : 0,
    };
    if (isDormant == true) values['includeInTotals'] = 0;

    final changed = await db.update(
      'accounts',
      values,
      where: 'accountNumber = ? AND bank = ?',
      whereArgs: [accountNumber, bank],
    );
    if (changed == 0) return false;

    await SyncEnqueuer.instance.onEntityWritten(
      entity: SyncEntity.accounts,
      entityRef: '$accountNumber|$bank',
      op: SyncOp.upsert,
      row: {
        'accountNumber': accountNumber,
        'bank': bank,
        ...values,
      },
    );
    return true;
  }

  /// Makes [accountNumber] the default (catch-all) account for its bank.
  /// Clears the default from the other accounts in the same bank+profile group
  /// so the one-default-per-bank invariant holds.
  Future<bool> setDefaultAccount({
    required String accountNumber,
    required int bank,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final target = await db.query(
      'accounts',
      columns: const <String>['profileId'],
      where: 'accountNumber = ? AND bank = ?',
      whereArgs: [accountNumber, bank],
      limit: 1,
    );
    if (target.isEmpty) return false;
    final profileId = target.single['profileId'] as int?;
    final profileClause =
        profileId == null ? 'profileId IS NULL' : 'profileId = ?';
    final profileArgs = profileId == null ? <Object?>[] : <Object?>[profileId];

    final groupRows = await db.query(
      'accounts',
      columns: const <String>['accountNumber'],
      where: 'bank = ? AND $profileClause',
      whereArgs: [bank, ...profileArgs],
    );

    await db.transaction((txn) async {
      await txn.update(
        'accounts',
        const <String, Object?>{'isDefault': 0},
        where: 'bank = ? AND $profileClause',
        whereArgs: [bank, ...profileArgs],
      );
      await txn.update(
        'accounts',
        const <String, Object?>{'isDefault': 1},
        where: 'accountNumber = ? AND bank = ?',
        whereArgs: [accountNumber, bank],
      );
    });

    await SyncEnqueuer.instance.onManyWritten(
      entity: SyncEntity.accounts,
      records: groupRows.map((row) {
        final number = row['accountNumber'].toString();
        return MapEntry('$number|$bank', <String, dynamic>{
          'accountNumber': number,
          'bank': bank,
          'isDefault': number == accountNumber ? 1 : 0,
        });
      }).toList(growable: false),
    );
    return true;
  }

  /// If a bank+profile group has accounts but no default, promotes the
  /// lowest-id account so unmatched transactions always have a catch-all.
  Future<void> _ensureDefaultAccountForBank(
    Database db,
    int bank,
    int? profileId,
  ) async {
    final profileClause =
        profileId == null ? 'profileId IS NULL' : 'profileId = ?';
    final profileArgs = profileId == null ? <Object?>[] : <Object?>[profileId];
    final rows = await db.query(
      'accounts',
      columns: const <String>['id', 'accountNumber', 'isDefault'],
      where: 'bank = ? AND $profileClause',
      whereArgs: [bank, ...profileArgs],
      orderBy: 'id ASC',
    );
    if (rows.isEmpty || rows.any((row) => row['isDefault'] == 1)) return;
    await db.update(
      'accounts',
      const <String, Object?>{'isDefault': 1},
      where: 'id = ?',
      whereArgs: <Object?>[rows.first['id']],
    );
    final promotedNumber = rows.first['accountNumber']?.toString();
    if (promotedNumber != null && promotedNumber.isNotEmpty) {
      await SyncEnqueuer.instance.onEntityWritten(
        entity: SyncEntity.accounts,
        entityRef: '$promotedNumber|$bank',
        op: SyncOp.upsert,
        row: <String, dynamic>{
          'accountNumber': promotedNumber,
          'bank': bank,
          'isDefault': 1,
        },
      );
    }
  }

  Future<bool> accountExists(String accountNumber, int bank) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    
    final result = activeProfileId != null
        ? await db.query(
            'accounts',
            where: 'accountNumber = ? AND bank = ? AND profileId = ?',
            whereArgs: [accountNumber, bank, activeProfileId],
            limit: 1,
          )
        : await db.query(
            'accounts',
            where: 'accountNumber = ? AND bank = ?',
            whereArgs: [accountNumber, bank],
            limit: 1,
          );
    return result.isNotEmpty;
  }

  Future<void> clearAll() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('accounts');
  }

  Future<void> deleteAccount(String accountNumber, int bank) async {
    await SyncEnqueuer.instance.onEntityWritten(
      entity: SyncEntity.accounts,
      entityRef: '$accountNumber|$bank',
      op: SyncOp.delete,
      deleteSnapshot: {'accountNumber': accountNumber, 'bank': bank},
    );

    final db = await DatabaseHelper.instance.database;

    if (bank == CashConstants.bankId) {
      final transactionRepo = TransactionRepository();
      await transactionRepo.deleteTransactionsByAccount(accountNumber, bank);
      await db.delete(
        'accounts',
        where: 'accountNumber = ? AND bank = ?',
        whereArgs: [accountNumber, bank],
      );
      return;
    }

    // First, check if this is the only account for this bank
    // If so, we should also delete transactions with NULL accountNumber for this bank
    final bankAccounts = await db.query(
      'accounts',
      where: 'bank = ?',
      whereArgs: [bank],
    );
    final isOnlyAccount = bankAccounts.length == 1;

    // Delete associated transactions
    final transactionRepo = TransactionRepository();
    await transactionRepo.deleteTransactionsByAccount(accountNumber, bank);

    // If this was the only account for this bank, also delete transactions with NULL accountNumber
    // (This handles legacy data that was associated with this account)
    // NOTE: Skip this for banks that match by bankId only (uniformMasking == false)
    // because those banks don't use account numbers for matching
    if (isOnlyAccount) {
      try {
        final bankConfigService = BankConfigService();
        final banks = await bankConfigService.getBanks();
        final bankInfo = banks.firstWhere((b) => b.id == bank);

        // Only delete NULL accountNumber transactions for banks that match by account number
        if (bankInfo.uniformMasking != false) {
          await db.delete(
            'transactions',
            where: 'bankId = ? AND accountNumber IS NULL',
            whereArgs: [bank],
          );
        }
      } catch (e) {
        // Bank not found in database, skip orphaned transactions deletion
        print(
            "debug: Bank not found when deleting account, skipping NULL transactions: $e");
      }
    }

    // Capture the account's profile before deleting so we can re-elect a
    // default within the same bank+profile group.
    final deletedRows = await db.query(
      'accounts',
      columns: const <String>['profileId'],
      where: 'accountNumber = ? AND bank = ?',
      whereArgs: [accountNumber, bank],
      limit: 1,
    );
    final deletedProfileId =
        deletedRows.isEmpty ? null : deletedRows.single['profileId'] as int?;

    // Finally, delete the account itself
    await db.delete(
      'accounts',
      where: 'accountNumber = ? AND bank = ?',
      whereArgs: [accountNumber, bank],
    );

    // If the deleted account was the bank's default, promote another so
    // unmatched transactions keep a catch-all.
    if (bank != CashConstants.bankId) {
      await _ensureDefaultAccountForBank(db, bank, deletedProfileId);
    }
  }
}
