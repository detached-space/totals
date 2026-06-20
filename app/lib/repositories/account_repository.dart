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

    // Finally, delete the account itself
    await db.delete(
      'accounts',
      where: 'accountNumber = ? AND bank = ?',
      whereArgs: [accountNumber, bank],
    );
  }
}
