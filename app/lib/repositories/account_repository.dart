import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/data_sync/sync_enqueuer.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/utils/account_identity.dart';

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
      });
    }).toList();
  }

  Future<void> saveAccount(Account account) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();

    // Use account's profileId if provided, otherwise use active profile
    final profileId = account.profileId ?? activeProfileId;

    final existing = await db.query(
      'accounts',
      where: 'accountNumber = ? AND bank = ?',
      whereArgs: [account.accountNumber, account.bank],
      limit: 1,
    );
    final data = <String, Object?>{
      'accountNumber': account.accountNumber,
      'bank': account.bank,
      'balance': account.balance,
      'accountHolderName': account.accountHolderName,
      'settledBalance': account.settledBalance,
      'pendingCredit': account.pendingCredit,
      'profileId': profileId,
      'smsSubscriptionId': account.smsSubscriptionId ??
          (existing.isEmpty ? null : existing.first['smsSubscriptionId']),
    };

    if (existing.isEmpty) {
      await db.insert('accounts', data);
    } else {
      await db.update(
        'accounts',
        data,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }

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
          'smsSubscriptionId': account.smsSubscriptionId,
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
    final accounts = await getAccounts();
    final banks = await BankConfigService().getBanks(allowRemoteFetch: false);
    Bank? bankInfo;
    for (final candidate in banks) {
      if (candidate.id == bank) {
        bankInfo = candidate;
        break;
      }
    }
    if (bankInfo == null) {
      return accounts.any((account) =>
          account.bank == bank && account.accountNumber == accountNumber);
    }
    return accounts.any((account) =>
        account.bank == bank &&
        registeredAccountNumbersMatch(
          bankInfo!,
          account.accountNumber,
          accountNumber,
        ));
  }

  /// Stores a learned device-local SMS subscription mapping without replacing
  /// the account row or its user-entered name/number.
  Future<bool> bindSmsSubscription({
    required String accountNumber,
    required int bank,
    required int subscriptionId,
  }) async {
    if (subscriptionId < 0) return false;
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    final conflictWhere = <String>['bank = ?', 'smsSubscriptionId = ?'];
    final conflictArgs = <Object?>[bank, subscriptionId];
    if (activeProfileId != null) {
      conflictWhere.add('profileId = ?');
      conflictArgs.add(activeProfileId);
    }
    final conflicts = await db.query(
      'accounts',
      columns: ['accountNumber'],
      where: conflictWhere.join(' AND '),
      whereArgs: conflictArgs,
    );
    if (conflicts.any((row) => row['accountNumber'] != accountNumber)) {
      return false;
    }

    final where = <String>['accountNumber = ?', 'bank = ?'];
    final args = <Object?>[accountNumber, bank];
    if (activeProfileId != null) {
      where.add('profileId = ?');
      args.add(activeProfileId);
    }
    final changed = await db.update(
      'accounts',
      {'smsSubscriptionId': subscriptionId},
      where: where.join(' AND '),
      whereArgs: args,
    );
    return changed > 0;
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

    // The repository uses the same ownership predicate as summaries and
    // navigation. It deletes only rows with evidence for this owner; ambiguous
    // activity remains available if the account is added again later.
    final transactionRepo = TransactionRepository();
    await transactionRepo.deleteTransactionsByAccount(accountNumber, bank);

    // Finally, delete the account itself
    await db.delete(
      'accounts',
      where: 'accountNumber = ? AND bank = ?',
      whereArgs: [accountNumber, bank],
    );
  }
}
