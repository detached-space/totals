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
        'isDefault': 1,
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
    final bankWhere = <String>['bank = ?'];
    final bankWhereArgs = <Object?>[account.bank];
    if (profileId != null) {
      bankWhere.add('profileId = ?');
      bankWhereArgs.add(profileId);
    } else {
      bankWhere.add('profileId IS NULL');
    }
    final existingBankAccounts = await db.query(
      'accounts',
      columns: const <String>['id'],
      where: bankWhere.join(' AND '),
      whereArgs: bankWhereArgs,
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
      // Balance refreshes and other legacy callers should never reset the
      // user's account preferences. Those are changed only through
      // updateAccountPreferences below.
      'includeInTotals': existing.isEmpty
          ? (account.includeInTotals ? 1 : 0)
          : existing.first['includeInTotals'],
      'isDormant': existing.isEmpty
          ? (account.isDormant ? 1 : 0)
          : existing.first['isDormant'],
      'isDefault': existing.isEmpty
          ? (existingBankAccounts.isEmpty ? 1 : 0)
          : existing.first['isDefault'],
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
        'includeInTotals': data['includeInTotals'],
        'isDormant': data['isDormant'],
        'isDefault': data['isDefault'],
      },
    );
  }

  Future<void> saveAllAccounts(List<Account> accounts) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    final batch = db.batch();
    final syncRecords = <MapEntry<String, Map<String, dynamic>>>[];
    final existingRows = await db.query(
      'accounts',
      columns: const <String>['bank', 'profileId', 'isDefault'],
    );
    String bankProfileKey(int bank, int? profileId) =>
        '$bank|${profileId ?? ''}';
    final banksWithAccounts = existingRows
        .map((row) => bankProfileKey(
              (row['bank'] as num).toInt(),
              (row['profileId'] as num?)?.toInt(),
            ))
        .toSet();
    final banksWithDefaults = existingRows
        .where((row) => row['isDefault'] == 1)
        .map((row) => bankProfileKey(
              (row['bank'] as num).toInt(),
              (row['profileId'] as num?)?.toInt(),
            ))
        .toSet();
    final preferredImportedDefaults = <String, String>{};
    for (final account in accounts) {
      final profileId = account.profileId ?? activeProfileId;
      final key = bankProfileKey(account.bank, profileId);
      final current = preferredImportedDefaults[key];
      if (current == null || account.isDefault) {
        preferredImportedDefaults[key] = account.accountNumber;
      }
    }

    for (var account in accounts) {
      // Use account's profileId if provided, otherwise use active profile
      final profileId = account.profileId ?? activeProfileId;
      final bankKey = bankProfileKey(account.bank, profileId);
      final canChooseImportedDefault = !banksWithAccounts.contains(bankKey) &&
          !banksWithDefaults.contains(bankKey);
      final isDefault = canChooseImportedDefault &&
          preferredImportedDefaults[bankKey] == account.accountNumber;
      if (isDefault) banksWithDefaults.add(bankKey);

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
          'includeInTotals': account.includeInTotals ? 1 : 0,
          'isDormant': account.isDormant ? 1 : 0,
          'isDefault': isDefault ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      syncRecords.add(MapEntry('${account.accountNumber}|${account.bank}', {
        'accountNumber': account.accountNumber,
        'bank': account.bank,
        'profileId': profileId,
        'includeInTotals': account.includeInTotals ? 1 : 0,
        'isDormant': account.isDormant ? 1 : 0,
        'isDefault': isDefault ? 1 : 0,
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

  Future<bool> updateAccountPreferences({
    required String accountNumber,
    required int bank,
    bool? includeInTotals,
    bool? isDormant,
  }) async {
    if (includeInTotals == null && isDormant == null) return false;

    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    final values = <String, Object?>{
      if (includeInTotals != null) 'includeInTotals': includeInTotals ? 1 : 0,
      if (isDormant != null) 'isDormant': isDormant ? 1 : 0,
    };
    if (isDormant == true) values['includeInTotals'] = 0;
    final where = <String>['accountNumber = ?', 'bank = ?'];
    final whereArgs = <Object?>[accountNumber, bank];
    if (activeProfileId != null) {
      where.add('profileId = ?');
      whereArgs.add(activeProfileId);
    }

    final changed = await db.update(
      'accounts',
      values,
      where: where.join(' AND '),
      whereArgs: whereArgs,
    );
    if (changed == 0) return false;

    await SyncEnqueuer.instance.onEntityWritten(
      entity: SyncEntity.accounts,
      entityRef: '$accountNumber|$bank',
      op: SyncOp.upsert,
      row: {
        'accountNumber': accountNumber,
        'bank': bank,
        if (activeProfileId != null) 'profileId': activeProfileId,
        ...values,
      },
    );
    return true;
  }

  Future<bool> setDefaultAccount({
    required String accountNumber,
    required int bank,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final activeProfileId = await _getActiveProfileId();
    final where = <String>['bank = ?'];
    final whereArgs = <Object?>[bank];
    if (activeProfileId != null) {
      where.add('profileId = ?');
      whereArgs.add(activeProfileId);
    } else {
      where.add('profileId IS NULL');
    }

    final rows = await db.query(
      'accounts',
      columns: const <String>['accountNumber'],
      where: where.join(' AND '),
      whereArgs: whereArgs,
    );
    if (!rows.any((row) => row['accountNumber'] == accountNumber)) {
      return false;
    }

    await db.transaction((txn) async {
      await txn.update(
        'accounts',
        const <String, Object?>{'isDefault': 0},
        where: where.join(' AND '),
        whereArgs: whereArgs,
      );
      await txn.update(
        'accounts',
        const <String, Object?>{'isDefault': 1},
        where: '${where.join(' AND ')} AND accountNumber = ?',
        whereArgs: <Object?>[...whereArgs, accountNumber],
      );
    });

    await SyncEnqueuer.instance.onManyWritten(
      entity: SyncEntity.accounts,
      records: rows.map((row) {
        final number = row['accountNumber'].toString();
        return MapEntry('$number|$bank', <String, dynamic>{
          'accountNumber': number,
          'bank': bank,
          if (activeProfileId != null) 'profileId': activeProfileId,
          'isDefault': number == accountNumber ? 1 : 0,
        });
      }).toList(growable: false),
    );
    return true;
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
    final activeProfileId = await _getActiveProfileId();
    final bankAccountWhere = <String>['bank = ?'];
    final bankAccountArgs = <Object?>[bank];
    if (activeProfileId != null) {
      bankAccountWhere.add('profileId = ?');
      bankAccountArgs.add(activeProfileId);
    } else {
      bankAccountWhere.add('profileId IS NULL');
    }
    final bankAccountRows = await db.query(
      'accounts',
      columns: const <String>['accountNumber'],
      where: bankAccountWhere.join(' AND '),
      whereArgs: bankAccountArgs,
    );
    final isDeletingFinalAccount = bankAccountRows.length == 1 &&
        bankAccountRows.single['accountNumber'] == accountNumber;
    final accountDeleteWhere = <String>[
      'accountNumber = ?',
      'bank = ?',
      if (activeProfileId != null) 'profileId = ?' else 'profileId IS NULL',
    ];
    final accountDeleteArgs = <Object?>[
      accountNumber,
      bank,
      if (activeProfileId != null) activeProfileId,
    ];

    if (bank == CashConstants.bankId) {
      final transactionRepo = TransactionRepository();
      await transactionRepo.deleteTransactionsByAccount(accountNumber, bank);
      await db.delete(
        'accounts',
        where: accountDeleteWhere.join(' AND '),
        whereArgs: accountDeleteArgs,
      );
      await _ensureDefaultAccountForBank(db, bank, activeProfileId);
      return;
    }

    final transactionRepo = TransactionRepository();
    if (isDeletingFinalAccount) {
      await transactionRepo.deleteTransactionsByBank(bank);
    } else {
      // With other accounts still registered, remove only rows belonging to
      // this owner and preserve the shared Other-transactions bucket.
      await transactionRepo.deleteTransactionsByAccount(accountNumber, bank);
    }

    // Finally, delete the account itself
    await db.delete(
      'accounts',
      where: accountDeleteWhere.join(' AND '),
      whereArgs: accountDeleteArgs,
    );
    await _ensureDefaultAccountForBank(db, bank, activeProfileId);
  }

  Future<void> _ensureDefaultAccountForBank(
    Database db,
    int bank,
    int? profileId,
  ) async {
    final where = <String>['bank = ?'];
    final args = <Object?>[bank];
    if (profileId != null) {
      where.add('profileId = ?');
      args.add(profileId);
    } else {
      where.add('profileId IS NULL');
    }
    final rows = await db.query(
      'accounts',
      columns: const <String>['id', 'accountNumber', 'isDefault'],
      where: where.join(' AND '),
      whereArgs: args,
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
          if (profileId != null) 'profileId': profileId,
          'isDefault': 1,
        },
      );
    }
  }
}
