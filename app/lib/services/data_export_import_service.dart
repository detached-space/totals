import 'dart:convert';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/failed_parse.dart';
import 'package:totals/models/sms_pattern.dart';
import 'package:totals/models/user_account.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/budget_repository.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/repositories/failed_parse_repository.dart';
import 'package:totals/repositories/user_account_repository.dart';
import 'package:totals/services/receiver_category_service.dart';
import 'package:totals/services/sms_config_service.dart';

class DataExportImportService {
  final AccountRepository _accountRepo = AccountRepository();
  final BudgetRepository _budgetRepo = BudgetRepository();
  final CategoryRepository _categoryRepo = CategoryRepository();
  final TransactionRepository _transactionRepo = TransactionRepository();
  final FailedParseRepository _failedParseRepo = FailedParseRepository();
  final UserAccountRepository _userAccountRepo = UserAccountRepository();
  final ReceiverCategoryService _receiverCategoryService =
      ReceiverCategoryService.instance;
  final SmsConfigService _smsConfigService = SmsConfigService();

  /// Export all data to JSON
  Future<String> exportAllData() async {
    try {
      final accounts = await _accountRepo.getAccounts();
      final banks = await _getBanksFromDb();
      final budgets = await _budgetRepo.getAllBudgets();
      final categories = await _categoryRepo.getCategories();
      final userAccounts = await _userAccountRepo.getUserAccounts();
      final transactions = await _transactionRepo.getTransactions();
      final failedParses = await _failedParseRepo.getAll();
      final receiverCategoryMappings =
          await _receiverCategoryService.getAllMappings();
      final smsPatterns = await _smsConfigService.getPatterns();

      final exportData = {
        'version': '1.0',
        'exportDate': DateTime.now().toIso8601String(),
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'banks': banks.map((b) => b.toJson()).toList(),
        'budgets': budgets.map((b) => b.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'userAccounts': userAccounts.map((a) => a.toJson()).toList(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'failedParses': failedParses.map((f) => f.toJson()).toList(),
        'receiverCategoryMappings': receiverCategoryMappings.map((mapping) {
          return {
            'accountNumber': mapping['accountNumber'],
            'categoryId': mapping['categoryId'],
            'accountType': mapping['accountType'],
            'createdAt': mapping['createdAt'],
          };
        }).toList(),
        'smsPatterns': smsPatterns.map((p) => p.toJson()).toList(),
      };

      return jsonEncode(exportData);
    } catch (e) {
      throw Exception('Failed to export data: $e');
    }
  }

  /// Import all data from JSON (appends to existing data)
  Future<void> importAllData(String jsonData) async {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonData);
      final db = await DatabaseHelper.instance.database;

      // Validate version (for future compatibility)
      final version = data['version'] ?? '1.0';

      String normalizedFlow(String? flow) {
        final normalized = flow?.trim().toLowerCase();
        return normalized == 'income' ? 'income' : 'expense';
      }

      String categoryKey(String name, String flow) {
        return '${name.trim().toLowerCase()}|${normalizedFlow(flow)}';
      }

      final Map<int, int> categoryIdMap = {};

      // Import banks (replace - configuration)
      if (data['banks'] != null) {
        final banksList = (data['banks'] as List)
            .map((json) => Bank.fromJson(json as Map<String, dynamic>))
            .toList();

        if (banksList.isNotEmpty) {
          await db.delete('banks');
          final batch = db.batch();
          for (final bank in banksList) {
            batch.insert(
              'banks',
              {
                'id': bank.id,
                'name': bank.name,
                'shortName': bank.shortName,
                'codes': jsonEncode(bank.codes),
                'image': bank.image,
                'maskPattern': bank.maskPattern,
                'uniformMasking': bank.uniformMasking == null
                    ? null
                    : (bank.uniformMasking! ? 1 : 0),
                'simBased':
                    bank.simBased == null ? null : (bank.simBased! ? 1 : 0),
                'colors':
                    bank.colors != null ? jsonEncode(bank.colors) : null,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        }
      }

      // Import categories (append, skip duplicates)
      if (data['categories'] != null) {
        final categoriesList = (data['categories'] as List)
            .map((json) => Category.fromJson(json as Map<String, dynamic>))
            .toList();

        final existingCategories = await _categoryRepo.getCategories();
        final builtInKeyMap = <String, Category>{};
        final nameFlowMap = <String, Category>{};

        for (final category in existingCategories) {
          final builtInKey = category.builtInKey?.trim();
          if (builtInKey != null && builtInKey.isNotEmpty) {
            builtInKeyMap[builtInKey] = category;
          }
          nameFlowMap[categoryKey(category.name, category.flow)] = category;
        }

        for (final category in categoriesList) {
          final exportId = category.id;
          final name = category.name.trim();
          if (name.isEmpty) {
            continue;
          }

          final builtInKey = category.builtInKey?.trim();
          final flow = normalizedFlow(category.flow);
          final key = categoryKey(name, flow);
          final isBuiltIn =
              builtInKey != null && builtInKey.isNotEmpty ? true : category.builtIn;

          Category? existing;
          if (builtInKey != null && builtInKey.isNotEmpty) {
            existing = builtInKeyMap[builtInKey];
          }
          existing ??= nameFlowMap[key];

          if (existing != null) {
            if (exportId != null && existing.id != null) {
              categoryIdMap[exportId] = existing.id!;
            }
            continue;
          }

          final insertId = await db.insert(
            'categories',
            {
              'name': name,
              'essential': category.essential ? 1 : 0,
              'uncategorized': category.uncategorized ? 1 : 0,
              'iconKey': category.iconKey,
              'description': category.description,
              'flow': flow,
              'recurring': category.recurring ? 1 : 0,
              'builtIn': isBuiltIn ? 1 : 0,
              'builtInKey': category.builtInKey,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          int? resolvedId = insertId == 0 ? null : insertId;
          if (resolvedId == null) {
            List<Map<String, dynamic>> match = [];
            if (builtInKey != null && builtInKey.isNotEmpty) {
              match = await db.query(
                'categories',
                columns: ['id'],
                where: 'builtInKey = ?',
                whereArgs: [builtInKey],
                limit: 1,
              );
            }
            if (match.isEmpty) {
              match = await db.query(
                'categories',
                columns: ['id'],
                where: 'name = ? COLLATE NOCASE AND flow = ?',
                whereArgs: [name, flow],
                limit: 1,
              );
            }
            if (match.isNotEmpty) {
              resolvedId = match.first['id'] as int?;
            }
          }

          if (resolvedId != null) {
            if (exportId != null) {
              categoryIdMap[exportId] = resolvedId;
            }
            final insertedCategory =
                category.copyWith(id: resolvedId, flow: flow, builtIn: isBuiltIn);
            if (builtInKey != null && builtInKey.isNotEmpty) {
              builtInKeyMap[builtInKey] = insertedCategory;
            }
            nameFlowMap[key] = insertedCategory;
          }
        }
      }

      // Import accounts (append, skip duplicates)
      // Use repository to ensure they're associated with active profile
      if (data['accounts'] != null) {
        final accountsList = (data['accounts'] as List)
            .map((json) => Account.fromJson(json as Map<String, dynamic>))
            .toList();
        // Use saveAllAccounts which will auto-associate with active profile
        await _accountRepo.saveAllAccounts(accountsList);
      }

      // Import saved user accounts (append, skip duplicates based on account+bank)
      if (data['userAccounts'] != null) {
        final userAccountsList = (data['userAccounts'] as List)
            .map((json) => UserAccount.fromJson(json as Map<String, dynamic>))
            .toList();
        final batch = db.batch();
        for (final account in userAccountsList) {
          batch.insert(
            'user_accounts',
            {
              'accountNumber': account.accountNumber,
              'bankId': account.bankId,
              'accountHolderName': account.accountHolderName,
              'createdAt': account.createdAt,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // Import transactions (append, skip duplicates based on reference)
      // Use repository to ensure they're associated with active profile
      if (data['transactions'] != null) {
        final transactionsList = (data['transactions'] as List)
            .map((json) => Transaction.fromJson(json as Map<String, dynamic>))
            .map((transaction) {
              final categoryId = transaction.categoryId;
              if (categoryId == null) return transaction;
              final mappedId = categoryIdMap[categoryId];
              if (mappedId == null || mappedId == categoryId) {
                return transaction;
              }
              return transaction.copyWith(categoryId: mappedId);
            })
            .toList();
        // Use saveAllTransactions which will auto-associate with active profile
        await _transactionRepo.saveAllTransactions(transactionsList);
      }

      // Import budgets (append, skip duplicates)
      if (data['budgets'] != null) {
        String budgetKey(Budget budget) {
          final name = budget.name.trim().toLowerCase();
          final type = budget.type.trim().toLowerCase();
          final category = budget.categoryId?.toString() ?? '';
          final start = budget.startDate.toIso8601String();
          final end = budget.endDate?.toIso8601String() ?? '';
          final amount = budget.amount.toStringAsFixed(2);
          final threshold = budget.alertThreshold.toStringAsFixed(2);
          final rollover = budget.rollover ? '1' : '0';
          final isActive = budget.isActive ? '1' : '0';
          final timeFrame = (budget.timeFrame ?? '').trim().toLowerCase();
          return '$name|$type|$amount|$category|$start|$end|$rollover|$threshold|$isActive|$timeFrame';
        }

        final existingBudgets = await _budgetRepo.getAllBudgets();
        final existingKeys = existingBudgets.map(budgetKey).toSet();

        final budgetsList = (data['budgets'] as List)
            .map((json) => Budget.fromJson(json as Map<String, dynamic>))
            .map((budget) {
              final categoryId = budget.categoryId;
              if (categoryId == null) return budget;
              final mappedId = categoryIdMap[categoryId];
              if (mappedId == null || mappedId == categoryId) {
                return budget;
              }
              return budget.copyWith(categoryId: mappedId);
            })
            .toList();

        for (final budget in budgetsList) {
          final key = budgetKey(budget);
          if (existingKeys.contains(key)) continue;
          final dataToSave = budget.toDb();
          dataToSave.remove('id');
          await db.insert(
            'budgets',
            dataToSave,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          existingKeys.add(key);
        }
      }

      // Import receiver category mappings (append, replace duplicates)
      if (data['receiverCategoryMappings'] != null) {
        final batch = db.batch();
        for (final json in data['receiverCategoryMappings'] as List) {
          final mapping = json as Map<String, dynamic>;
          final categoryId = mapping['categoryId'] as int?;
          final mappedId = categoryId == null ? null : categoryIdMap[categoryId];
          batch.insert(
            'receiver_category_mappings',
            {
              'accountNumber': mapping['accountNumber'],
              'categoryId': mappedId ?? categoryId,
              'accountType': mapping['accountType'],
              'createdAt': mapping['createdAt'],
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // Import failed parses (append)
      if (data['failedParses'] != null) {
        final batch = db.batch();
        for (var json in data['failedParses'] as List) {
          final failedParse = FailedParse.fromJson(json as Map<String, dynamic>);
          batch.insert('failed_parses', {
            'address': failedParse.address,
            'body': failedParse.body,
            'reason': failedParse.reason,
            'timestamp': failedParse.timestamp,
          });
        }
        await batch.commit(noResult: true);
      }

      // Import SMS patterns (replace - these are configuration)
      if (data['smsPatterns'] != null) {
        final patternsList = (data['smsPatterns'] as List)
            .map((json) => SmsPattern.fromJson(json as Map<String, dynamic>))
            .toList();
        await _smsConfigService.savePatterns(patternsList);
      }
    } catch (e) {
      throw Exception('Failed to import data: $e');
    }
  }

  /// Export transactions to CSV format
  Future<String> exportTransactionsCsv() async {
    try {
      final transactions = await _transactionRepo.getTransactions();
      final categories = await _categoryRepo.getCategories();
      final categoryNames = {
        for (final c in categories)
          if (c.id != null) c.id!: c.name
      };

      final buffer = StringBuffer();
      buffer.writeln(
          'Date,Type,Amount (ETB),Creditor,Receiver,Account Number,Bank ID,Balance After,Category,Reference,Service Charge,VAT');

      for (final t in transactions) {
        buffer.writeln([
          _csvField(t.time ?? ''),
          _csvField(t.type ?? ''),
          t.amount.toStringAsFixed(2),
          _csvField(t.creditor ?? ''),
          _csvField(t.receiver ?? ''),
          _csvField(t.accountNumber ?? ''),
          _csvField(t.bankId?.toString() ?? ''),
          _csvField(t.currentBalance ?? ''),
          _csvField(
              t.categoryId != null ? (categoryNames[t.categoryId] ?? '') : ''),
          _csvField(t.reference),
          (t.serviceCharge ?? 0).toStringAsFixed(2),
          (t.vat ?? 0).toStringAsFixed(2),
        ].join(','));
      }

      return buffer.toString();
    } catch (e) {
      throw Exception('Failed to export transactions as CSV: $e');
    }
  }

  String _csvField(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<List<Bank>> _getBanksFromDb() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('banks');

    return rows.map((row) {
      final codesRaw = row['codes'];
      final colorsRaw = row['colors'];
      final codes = codesRaw is String && codesRaw.isNotEmpty
          ? List<String>.from(jsonDecode(codesRaw) as List)
          : <String>[];
      final colors = colorsRaw is String && colorsRaw.isNotEmpty
          ? List<String>.from(jsonDecode(colorsRaw) as List)
          : null;

      return Bank.fromJson({
        'id': row['id'],
        'name': row['name'],
        'shortName': row['shortName'],
        'codes': codes,
        'image': row['image'],
        'maskPattern': row['maskPattern'],
        'uniformMasking': row['uniformMasking'] == null
            ? null
            : (row['uniformMasking'] == 1),
        'simBased': row['simBased'] == null ? null : (row['simBased'] == 1),
        'colors': colors,
      });
    }).toList();
  }
}

