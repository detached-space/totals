import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/account.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/bank_config_service.dart';

class AccountRepository {
  Future<List<Account>> getAccounts() async {
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
      });
    }).toList();
  }

  Future<void> saveAccount(Account account) async {
    final db = await DatabaseHelper.instance.database;

    await db.insert(
      'accounts',
      {
        'accountNumber': account.accountNumber,
        'bank': account.bank,
        'balance': account.balance,
        'accountHolderName': account.accountHolderName,
        'settledBalance': account.settledBalance,
        'pendingCredit': account.pendingCredit,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveAllAccounts(List<Account> accounts) async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();

    for (var account in accounts) {
      batch.insert(
        'accounts',
        {
          'accountNumber': account.accountNumber,
          'bank': account.bank,
          'balance': account.balance,
          'accountHolderName': account.accountHolderName,
          'settledBalance': account.settledBalance,
          'pendingCredit': account.pendingCredit,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<bool> accountExists(String accountNumber, int bank) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
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
    final db = await DatabaseHelper.instance.database;

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
