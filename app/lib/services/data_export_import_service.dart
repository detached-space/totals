import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/auto_categorization.dart';
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
import 'package:totals/services/auto_categorization_service.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/utils/transaction_duplicate_detector.dart';

const int _dashenBankId = 4;

class DataExportImportService {
  static const int currentSchemaVersion = 4;
  static const int minimumSchemaVersion = 1;

  final AccountRepository _accountRepo = AccountRepository();
  final BudgetRepository _budgetRepo = BudgetRepository();
  final CategoryRepository _categoryRepo = CategoryRepository();
  final TransactionRepository _transactionRepo = TransactionRepository();
  final FailedParseRepository _failedParseRepo = FailedParseRepository();
  final UserAccountRepository _userAccountRepo = UserAccountRepository();
  final AutoCategorizationService _autoCategorizationService =
      AutoCategorizationService.instance;
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
      final autoCategoryRules = await _autoCategorizationService.getRules();
      final autoCategoryPromptDismissals =
          await _autoCategorizationService.getDismissals();
      final smsPatterns = await _smsConfigService.getPatterns();

      final exportData = {
        'schemaVersion': currentSchemaVersion,
        'version': '1.0',
        'exportDate': DateTime.now().toIso8601String(),
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'banks': banks.map((b) => b.toJson()).toList(),
        'budgets': budgets.map((b) => b.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'userAccounts': userAccounts.map((a) => a.toJson()).toList(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'failedParses': failedParses.map((f) => f.toJson()).toList(),
        'autoCategoryRules':
            autoCategoryRules.map((rule) => rule.toJson()).toList(),
        'autoCategoryPromptDismissals': autoCategoryPromptDismissals
            .map((dismissal) => dismissal.toJson())
            .toList(),
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
      final data = normalizeImportPayload(jsonData);
      final db = await DatabaseHelper.instance.database;

      final categoriesRaw = _asMapList(data['categories']);
      final categoryIdsCanBeMapped = categoriesRaw.isNotEmpty;

      String normalizedFlow(String? flow) {
        final normalized = flow?.trim().toLowerCase();
        return normalized == 'income' ? 'income' : 'expense';
      }

      String categoryKey(String name, String flow) {
        return '${name.trim().toLowerCase()}|${normalizedFlow(flow)}';
      }

      final Map<int, int> categoryIdMap = {};

      // Import banks (replace - configuration)
      final banksRaw = _asMapList(data['banks']);
      if (banksRaw.isNotEmpty) {
        final banksList =
            banksRaw.map(Bank.fromJson).map(_normalizeImportedBank).toList();

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
                'colors': bank.colors != null ? jsonEncode(bank.colors) : null,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        }
      }

      // Import categories (append, skip duplicates)
      if (categoriesRaw.isNotEmpty) {
        final categoriesList = categoriesRaw.map(Category.fromJson).toList();

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
          final isBuiltIn = builtInKey != null && builtInKey.isNotEmpty
              ? true
              : category.builtIn;

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
            final insertedCategory = category.copyWith(
                id: resolvedId, flow: flow, builtIn: isBuiltIn);
            if (builtInKey != null && builtInKey.isNotEmpty) {
              builtInKeyMap[builtInKey] = insertedCategory;
            }
            nameFlowMap[key] = insertedCategory;
          }
        }
      }

      // Import accounts (append, skip duplicates)
      // Use repository to ensure they're associated with active profile
      final accountsRaw = _asMapList(data['accounts']);
      if (accountsRaw.isNotEmpty) {
        final existingAccountKeys = await _getExistingAccountKeys(db);
        final accountsList = <Account>[];
        for (final rawAccount in accountsRaw) {
          final account = Account.fromJson(rawAccount);
          final accountNumber = account.accountNumber.trim();
          if (accountNumber.isEmpty) {
            continue;
          }
          final key = _accountKey(accountNumber, account.bank);
          if (existingAccountKeys.contains(key)) {
            // Preserve local account balances for existing accounts.
            continue;
          }

          accountsList.add(
            Account(
              accountNumber: accountNumber,
              bank: account.bank,
              balance: account.balance,
              accountHolderName: account.accountHolderName,
              settledBalance: account.settledBalance,
              pendingCredit: account.pendingCredit,
              profileId: account.profileId,
            ),
          );
          existingAccountKeys.add(key);
        }
        // Use saveAllAccounts which will auto-associate with active profile
        if (accountsList.isNotEmpty) {
          await _accountRepo.saveAllAccounts(accountsList);
        }
      }

      // Import saved user accounts (append, skip duplicates based on account+bank)
      final userAccountsRaw = _asMapList(data['userAccounts']);
      if (userAccountsRaw.isNotEmpty) {
        final userAccountsList =
            userAccountsRaw.map(UserAccount.fromJson).toList();
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
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
      }

      // Import transactions (append, skip duplicates based on reference)
      // Use repository to ensure they're associated with active profile
      final transactionsRaw = _asMapList(data['transactions']);
      if (transactionsRaw.isNotEmpty) {
        final existingReferences = await _getExistingTransactionReferences(db);
        final transactionsList = <Transaction>[];

        for (final rawTransaction in transactionsRaw) {
          var transaction = Transaction.fromJson(rawTransaction);
          final reference = transaction.reference.trim();
          if (reference.isEmpty || existingReferences.contains(reference)) {
            continue;
          }

          if (reference != transaction.reference) {
            transaction = transaction.copyWith(reference: reference);
          }

          final categoryId = transaction.categoryId;
          if (categoryId != null) {
            final mappedId = categoryIdMap[categoryId];
            if (mappedId != null) {
              transaction = transaction.copyWith(categoryId: mappedId);
            } else if (categoryIdsCanBeMapped) {
              // If categories are included but this ID is unresolved, clear it
              // to avoid linking to a wrong category in the destination DB.
              transaction = transaction.copyWith(clearCategoryId: true);
            }
          }

          transactionsList.add(transaction);
          existingReferences.add(reference);
        }

        // Use saveAllTransactions which will auto-associate with active profile
        if (transactionsList.isNotEmpty) {
          await _transactionRepo.saveAllTransactions(transactionsList);
        }

        await _removeImportedDashenDuplicates();
      }

      // Import budgets (append, skip duplicates)
      final budgetsRaw = _asMapList(data['budgets']);
      if (budgetsRaw.isNotEmpty) {
        String budgetKey(Budget budget) {
          final name = budget.name.trim().toLowerCase();
          final type = budget.type.trim().toLowerCase();
          final category = budget.selectedCategoryIds.toList()
            ..sort((a, b) => a - b);
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

        final budgetsList = budgetsRaw.map(Budget.fromJson).map((budget) {
          final sourceIds = budget.selectedCategoryIds;
          if (sourceIds.isEmpty) return budget;
          final mappedIds = <int>[];
          for (final id in sourceIds) {
            final mapped = categoryIdMap[id];
            if (mapped != null) {
              mappedIds.add(mapped);
            }
          }
          if (mappedIds.isNotEmpty) {
            mappedIds.sort();
            final deduped = mappedIds.toSet().toList(growable: false);
            return budget.copyWith(
              categoryId: deduped.first,
              categoryIds: deduped,
            );
          }
          if (categoryIdsCanBeMapped) {
            final cleared = Map<String, dynamic>.from(budget.toJson());
            cleared['categoryId'] = null;
            cleared['categoryIds'] = null;
            return Budget.fromJson(cleared);
          }
          return budget;
        }).toList();

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

      // Import explicit auto-category rules.
      final autoCategoryRulesRaw = _asMapList(data['autoCategoryRules']);
      if (autoCategoryRulesRaw.isNotEmpty) {
        final rules = autoCategoryRulesRaw
            .map(AutoCategorizationRule.fromJson)
            .toList(growable: false);
        final batch = db.batch();
        for (final rule in rules) {
          final categoryId = categoryIdMap[rule.categoryId] ?? rule.categoryId;
          if (categoryId == 0) continue;
          if (categoryIdsCanBeMapped &&
              categoryIdMap.isNotEmpty &&
              categoryId == rule.categoryId &&
              !categoryIdMap.containsKey(rule.categoryId)) {
            continue;
          }
          batch.insert(
            'auto_category_rules',
            {
              'counterparty': rule.counterparty,
              'normalizedCounterparty': rule.normalizedCounterparty.isNotEmpty
                  ? rule.normalizedCounterparty
                  : _autoCategorizationService.normalizeCounterparty(
                      rule.counterparty,
                    ),
              'flow': rule.flow,
              'categoryId': categoryId,
              'createdAt': rule.createdAt,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // Import dismissed prompts.
      final autoCategoryPromptDismissalsRaw =
          _asMapList(data['autoCategoryPromptDismissals']);
      if (autoCategoryPromptDismissalsRaw.isNotEmpty) {
        final dismissals = autoCategoryPromptDismissalsRaw
            .map(AutoCategoryPromptDismissal.fromJson)
            .toList(growable: false);
        final batch = db.batch();
        for (final dismissal in dismissals) {
          batch.insert(
            'auto_category_prompt_dismissals',
            {
              'counterparty': dismissal.counterparty,
              'normalizedCounterparty':
                  dismissal.normalizedCounterparty.isNotEmpty
                      ? dismissal.normalizedCounterparty
                      : _autoCategorizationService.normalizeCounterparty(
                          dismissal.counterparty,
                        ),
              'flow': dismissal.flow,
              'createdAt': dismissal.createdAt,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // Import legacy receiver category mappings by converting them into
      // flow-aware auto-category rules.
      final mappingsRaw = _asMapList(data['receiverCategoryMappings']);
      if (mappingsRaw.isNotEmpty) {
        final categoriesById = {
          for (final category in await _categoryRepo.getCategories())
            if (category.id != null) category.id!: category,
        };
        final batch = db.batch();
        for (final mapping in mappingsRaw) {
          final categoryId = _asInt(mapping['categoryId']);
          final mappedId =
              categoryId == null ? null : categoryIdMap[categoryId];
          if (mappedId == null &&
              categoryId != null &&
              categoryIdsCanBeMapped) {
            // Skip unresolved mappings when categories are part of the backup.
            continue;
          }
          final resolvedCategoryId = mappedId ?? categoryId;
          if (resolvedCategoryId == null) continue;
          final category = categoriesById[resolvedCategoryId];
          if (category == null) continue;
          final rawCounterparty = mapping['accountNumber']?.toString().trim();
          if (rawCounterparty == null || rawCounterparty.isEmpty) continue;
          batch.insert(
            'auto_category_rules',
            {
              'counterparty': rawCounterparty,
              'normalizedCounterparty':
                  _autoCategorizationService.normalizeCounterparty(
                rawCounterparty,
              ),
              'flow': _autoCategorizationService.normalizeFlow(category.flow),
              'categoryId': resolvedCategoryId,
              'createdAt':
                  mapping['createdAt'] ?? DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // Import failed parses (append)
      final failedParsesRaw = _asMapList(data['failedParses']);
      if (failedParsesRaw.isNotEmpty) {
        final batch = db.batch();
        for (final json in failedParsesRaw) {
          final failedParse = FailedParse.fromJson(json);
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
      final smsPatternsRaw = _asMapList(data['smsPatterns']);
      if (smsPatternsRaw.isNotEmpty) {
        final patternsList = smsPatternsRaw.map(SmsPattern.fromJson).toList();
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

  /// Export transactions to a formatted PDF bank statement
  Future<List<int>> exportTransactionsPdf() async {
    try {
      final transactions = await _transactionRepo.getTransactions();
      final categories = await _categoryRepo.getCategories();
      final categoryNames = {
        for (final c in categories)
          if (c.id != null) c.id!: c.name
      };

      final totalCredit = transactions
          .where((t) => t.type == 'CREDIT')
          .fold(0.0, (sum, t) => sum + t.amount);
      final totalDebit = transactions
          .where((t) => t.type == 'DEBIT')
          .fold(0.0, (sum, t) => sum + t.amount);

      final doc = pw.Document();
      final exportDate = DateTime.now();
      final dateStr =
          '${exportDate.year}-${exportDate.month.toString().padLeft(2, '0')}-${exportDate.day.toString().padLeft(2, '0')}';

      final headerStyle = pw.TextStyle(
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.blue800,
      );
      final subHeaderStyle = pw.TextStyle(
        fontSize: 11,
        color: PdfColors.grey700,
      );
      final tableHeaderStyle = pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      );
      final cellStyle = pw.TextStyle(fontSize: 8);

      final pageTheme = pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
      );

      // Split into pages of 30 rows
      const rowsPerPage = 30;
      final pages = <List<Transaction>>[];
      for (var i = 0; i < transactions.length; i += rowsPerPage) {
        pages.add(transactions.sublist(
          i,
          i + rowsPerPage > transactions.length
              ? transactions.length
              : i + rowsPerPage,
        ));
      }
      if (pages.isEmpty) pages.add([]);

      for (var p = 0; p < pages.length; p++) {
        final pageTransactions = pages[p];
        doc.addPage(
          pw.Page(
            pageTheme: pageTheme,
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('TOTALS', style: headerStyle),
                          pw.Text('Transaction Statement', style: subHeaderStyle),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Generated: $dateStr', style: subHeaderStyle),
                          pw.Text(
                              'Page ${p + 1} of ${pages.length}',
                              style: subHeaderStyle),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Divider(color: PdfColors.blue800, thickness: 1.5),
                  pw.SizedBox(height: 8),

                  // Summary (first page only)
                  if (p == 0) ...[
                    pw.Row(
                      children: [
                        _pdfSummaryCard('Total Transactions',
                            '${transactions.length}', PdfColors.blue50),
                        pw.SizedBox(width: 8),
                        _pdfSummaryCard('Total Credit',
                            'ETB ${totalCredit.toStringAsFixed(2)}',
                            PdfColors.green50),
                        pw.SizedBox(width: 8),
                        _pdfSummaryCard('Total Debit',
                            'ETB ${totalDebit.toStringAsFixed(2)}',
                            PdfColors.red50),
                        pw.SizedBox(width: 8),
                        _pdfSummaryCard('Net',
                            'ETB ${(totalCredit - totalDebit).toStringAsFixed(2)}',
                            PdfColors.orange50),
                      ],
                    ),
                    pw.SizedBox(height: 12),
                  ],

                  // Table
                  pw.Table(
                    border: pw.TableBorder.all(
                        color: PdfColors.grey300, width: 0.5),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(60),  // Date
                      1: const pw.FixedColumnWidth(38),  // Type
                      2: const pw.FixedColumnWidth(52),  // Amount
                      3: const pw.FlexColumnWidth(1.2),  // Creditor/Receiver
                      4: const pw.FlexColumnWidth(1),    // Category
                      5: const pw.FixedColumnWidth(52),  // Balance
                    },
                    children: [
                      // Header row
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                            color: PdfColors.blue800),
                        children: [
                          'Date', 'Type', 'Amount (ETB)',
                          'Description', 'Category', 'Balance'
                        ]
                            .map((h) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(h,
                                      style: tableHeaderStyle),
                                ))
                            .toList(),
                      ),
                      // Data rows
                      ...pageTransactions.asMap().entries.map((entry) {
                        final i = entry.key;
                        final t = entry.value;
                        final isCredit = t.type == 'CREDIT';
                        final description = isCredit
                            ? (t.creditor ?? '')
                            : (t.receiver ?? '');
                        final categoryName = t.categoryId != null
                            ? (categoryNames[t.categoryId] ?? '')
                            : '';
                        final bg = i % 2 == 0
                            ? PdfColors.white
                            : PdfColors.grey100;
                        return pw.TableRow(
                          decoration: pw.BoxDecoration(color: bg),
                          children: [
                            _pdfCell(t.time?.substring(0, 10) ?? '',
                                cellStyle),
                            _pdfCell(t.type ?? '', cellStyle,
                                color: isCredit
                                    ? PdfColors.green700
                                    : PdfColors.red700),
                            _pdfCell(
                                t.amount.toStringAsFixed(2), cellStyle,
                                align: pw.TextAlign.right),
                            _pdfCell(description, cellStyle),
                            _pdfCell(categoryName, cellStyle),
                            _pdfCell(t.currentBalance ?? '', cellStyle,
                                align: pw.TextAlign.right),
                          ],
                        );
                      }),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      }

      return doc.save();
    } catch (e) {
      throw Exception('Failed to export transactions as PDF: $e');
    }
  }

  pw.Widget _pdfSummaryCard(String label, String value, PdfColor bg) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 7, color: PdfColors.grey600)),
            pw.SizedBox(height: 2),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfCell(String text, pw.TextStyle style,
      {PdfColor? color, pw.TextAlign? align}) {
    final s = color != null ? style.copyWith(color: color) : style;
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(text, style: s,
          textAlign: align ?? pw.TextAlign.left),
    );
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

  static Map<String, dynamic> normalizeImportPayload(String jsonData) {
    final decoded = jsonDecode(jsonData);
    if (decoded is! Map) {
      throw const FormatException('Backup data must be a JSON object.');
    }
    final raw = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
    final schemaVersion = _resolveSchemaVersion(raw);

    if (schemaVersion < minimumSchemaVersion) {
      throw FormatException(
          'Unsupported backup schema version: $schemaVersion');
    }
    if (schemaVersion > currentSchemaVersion) {
      throw FormatException(
        'Backup schema v$schemaVersion is newer than supported '
        'v$currentSchemaVersion. Update the app and try again.',
      );
    }

    return {
      'schemaVersion': schemaVersion,
      'version': raw['version'],
      'exportDate': raw['exportDate'],
      'accounts': _readList(raw, 'accounts'),
      'banks': _readList(raw, 'banks'),
      'budgets': _readList(raw, 'budgets'),
      'categories': _readList(raw, 'categories'),
      'userAccounts': _readList(
        raw,
        'userAccounts',
        aliases: const ['user_accounts'],
      ),
      'transactions': _readList(raw, 'transactions'),
      'failedParses': _readList(
        raw,
        'failedParses',
        aliases: const ['failed_parses'],
      ),
      'receiverCategoryMappings': _readList(
        raw,
        'receiverCategoryMappings',
        aliases: const ['receiver_category_mappings'],
      ),
      'autoCategoryRules': _readList(
        raw,
        'autoCategoryRules',
        aliases: const ['auto_category_rules'],
      ),
      'autoCategoryPromptDismissals': _readList(
        raw,
        'autoCategoryPromptDismissals',
        aliases: const ['auto_category_prompt_dismissals'],
      ),
      'smsPatterns': _readList(
        raw,
        'smsPatterns',
        aliases: const ['sms_patterns'],
      ),
    };
  }

  static int _resolveSchemaVersion(Map<String, dynamic> data) {
    final explicit =
        _asInt(data['schemaVersion']) ?? _asInt(data['schema_version']);
    if (explicit != null) return explicit;

    if (_hasAnySection(data, const [
      'autoCategoryRules',
      'auto_category_rules',
      'autoCategoryPromptDismissals',
      'auto_category_prompt_dismissals',
    ])) {
      return 4;
    }
    if (_hasAnySection(
        data, const ['banks', 'budgets', 'userAccounts', 'user_accounts'])) {
      return 3;
    }
    if (_hasAnySection(data, const ['categories'])) {
      return 2;
    }
    if (_hasAnySection(data, const [
      'accounts',
      'transactions',
      'failedParses',
      'failed_parses',
      'smsPatterns',
      'sms_patterns',
    ])) {
      return 1;
    }
    throw const FormatException(
      'Backup data does not contain any supported sections.',
    );
  }

  static bool _hasAnySection(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (!data.containsKey(key)) continue;
      final value = data[key];
      if (value is List || value is Map) return true;
      if (value != null) return true;
    }
    return false;
  }

  static List<dynamic> _readList(
    Map<String, dynamic> data,
    String key, {
    List<String> aliases = const [],
  }) {
    for (final candidate in [key, ...aliases]) {
      if (!data.containsKey(candidate)) continue;
      final value = data[candidate];
      if (value is List) return value;
      if (value is Map) return [value];
    }
    return const [];
  }

  static List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final entry in value) {
      if (entry is Map) {
        out.add(Map<String, dynamic>.from(entry.cast<String, dynamic>()));
      }
    }
    return out;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String _accountKey(String accountNumber, int bank) {
    return '${bank.toString()}::${accountNumber.trim()}';
  }

  Future<Set<String>> _getExistingAccountKeys(Database db) async {
    final rows = await db.query(
      'accounts',
      columns: ['accountNumber', 'bank'],
    );
    final keys = <String>{};
    for (final row in rows) {
      final accountNumber = row['accountNumber']?.toString().trim();
      final bank = _asInt(row['bank']);
      if (accountNumber == null || accountNumber.isEmpty || bank == null) {
        continue;
      }
      keys.add(_accountKey(accountNumber, bank));
    }
    return keys;
  }

  Future<Set<String>> _getExistingTransactionReferences(Database db) async {
    final rows = await db.query(
      'transactions',
      columns: ['reference'],
    );
    final references = <String>{};
    for (final row in rows) {
      final reference = row['reference']?.toString().trim();
      if (reference == null || reference.isEmpty) {
        continue;
      }
      references.add(reference);
    }
    return references;
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
        'uniformMasking':
            row['uniformMasking'] == null ? null : (row['uniformMasking'] == 1),
        'simBased': row['simBased'] == null ? null : (row['simBased'] == 1),
        'colors': colors,
      });
    }).toList();
  }

  Future<void> _removeImportedDashenDuplicates() async {
    final transactions = await _transactionRepo.getTransactions();
    if (transactions.isEmpty) return;

    final dashenDebitTransactions = transactions
        .where((transaction) =>
            transaction.bankId == _dashenBankId &&
            (transaction.type ?? '').trim().toUpperCase() == 'DEBIT')
        .toList(growable: false);
    if (dashenDebitTransactions.isEmpty) return;

    final dashenAccounts = (await _accountRepo.getAccounts())
        .where((account) => account.bank == _dashenBankId)
        .toList(growable: false);
    final suffixes = buildDashenDeduplicationSuffixes(
      accountNumbers: dashenAccounts.map((account) => account.accountNumber),
      transactionAccountNumbers: dashenDebitTransactions
          .map((transaction) => transaction.accountNumber),
    );
    if (suffixes.isEmpty) return;

    final plans = <TransactionDeduplicationPlan>[];
    final matchMissingAccountNumbers = dashenAccounts.length == 1;
    for (final suffix in suffixes) {
      plans.addAll(
        buildExactAmountAndBalanceDeduplicationPlans(
          bankId: _dashenBankId,
          type: 'DEBIT',
          transactions: transactions,
          accountSuffix: suffix,
          matchTransactionsWithoutAccountNumber: matchMissingAccountNumbers,
        ),
      );
    }
    if (plans.isEmpty) return;

    final dedupedPlans = <String, TransactionDeduplicationPlan>{};
    for (final plan in plans) {
      final duplicateRefs = [...plan.duplicateReferences]..sort();
      final key = '${plan.keeper.reference}|${duplicateRefs.join(",")}';
      dedupedPlans[key] = plan;
    }

    for (final plan in dedupedPlans.values) {
      await _transactionRepo.saveTransaction(
        plan.mergedKeeper,
        skipAutoCategorization: true,
      );
    }
    await _transactionRepo.deleteTransactionsByReferences(
      dedupedPlans.values.expand((plan) => plan.duplicateReferences),
    );
  }

  Bank _normalizeImportedBank(Bank bank) {
    if (bank.id != _dashenBankId ||
        bank.maskPattern == dashenCanonicalMaskPattern) {
      return bank;
    }

    return Bank(
      id: bank.id,
      name: bank.name,
      shortName: bank.shortName,
      codes: bank.codes,
      image: bank.image,
      maskPattern: dashenCanonicalMaskPattern,
      uniformMasking: bank.uniformMasking,
      simBased: bank.simBased,
      colors: bank.colors,
    );
  }
}
