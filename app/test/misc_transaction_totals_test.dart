import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/local_server/handlers/summary_handler.dart';
import 'package:totals/local_server/handlers/transactions_handler.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/transaction_category_split.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/budget_service.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';
import 'package:totals/services/financial_insights.dart';
import 'package:totals/services/widget_data_provider.dart';
import 'package:totals/utils/map_keys.dart';
import 'package:totals/utils/transaction_summary_filter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDirectory;
  late String previousDatabasePath;
  late TransactionRepository repository;
  late Map<String, Category> categories;
  late DateTime today;

  setUpAll(() async {
    dotenv.loadFromString(
      envString: 'SHARED_EXPENSES_URL=https://example.invalid',
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previousDatabasePath = await databaseFactoryFfi.getDatabasesPath();
    testDirectory = await Directory.systemTemp.createTemp('totals-misc-test-');
    await databaseFactoryFfi.setDatabasesPath(testDirectory.path);
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    await databaseFactoryFfi.setDatabasesPath(previousDatabasePath);
    await testDirectory.delete(recursive: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DataSyncSettingsService.cachedEnabled = false;
    await DatabaseHelper.instance.close();
    await databaseFactoryFfi.deleteDatabase('${testDirectory.path}/totals.db');
    final db = await DatabaseHelper.instance.database;
    // Keep bank configuration on its local path.
    await db.insert('banks', <String, Object?>{
      'id': 1,
      'name': 'Test bank',
      'shortName': 'Test',
      'codes': '[]',
      'image': '',
      'colors': '[]',
    });
    categories = {
      for (final category in await CategoryRepository().getCategories())
        if (category.builtInKey != null) category.builtInKey!: category,
    };
    repository = TransactionRepository();
    today = DateTime.now();
  });

  Future<Transaction> save({
    required String reference,
    required double amount,
    String type = 'DEBIT',
    String? categoryKey,
    DateTime? date,
    double? serviceCharge,
    double? vat,
  }) async {
    final transaction = Transaction(
      amount: amount,
      reference: reference,
      type: type,
      time: (date ?? today).toIso8601String(),
      bankId: CashConstants.bankId,
      accountNumber: CashConstants.defaultAccountNumber,
      categoryId: categories[categoryKey]?.id,
      serviceCharge: serviceCharge,
      vat: vat,
    );
    await repository.saveTransaction(transaction, skipAutoCategorization: true);
    return transaction;
  }

  Future<void> saveMixedTransactions() async {
    await save(
      reference: 'groceries',
      amount: 100,
      categoryKey: 'expense_groceries',
      serviceCharge: 10,
      vat: 1.5,
    );
    await save(reference: 'uncategorized', amount: 25);
    await save(
      reference: 'misc-expense',
      amount: 900,
      categoryKey: 'expense_misc',
      serviceCharge: 40,
      vat: 6,
    );
    await save(
      reference: 'salary',
      amount: 500,
      type: 'CREDIT',
      categoryKey: 'income_salary',
    );
    await save(
      reference: 'misc-income',
      amount: 2000,
      type: 'CREDIT',
      categoryKey: 'income_misc',
    );
  }

  test('all provider reporting totals exclude Misc and its fees', () async {
    await saveMixedTransactions();
    final provider = TransactionProvider();
    addTearDown(provider.dispose);
    await provider.loadData();

    for (final totals in [
      provider.todayTotals,
      provider.weekTotals,
      provider.monthTotals,
      provider.thirtyDayTotals,
      provider.todayCashFlowTotals,
      provider.weekCashFlowTotals,
    ]) {
      expect(totals.income, 500);
      expect(totals.expense, 136.5);
    }
    for (final trend in [provider.weekTrendSeries, provider.monthTrendSeries]) {
      expect(trend.totalIncome, 500);
      expect(trend.totalExpense, 136.5);
    }
    expect(provider.financialHealth.trailingIncome, 500);
    expect(provider.financialHealth.trailingExpense, 136.5);
    expect(provider.summary?.totalCredit, 500);
    expect(provider.summary?.totalDebit, 136.5);
    expect(provider.summary?.feesAndVat, 11.5);
    final cashSummary = provider.accountSummaries.single;
    expect(cashSummary.totalTransactions, 3);
    expect(cashSummary.balance, 1417.5);

    expect(provider.allTransactions, hasLength(5));
    expect(provider.todayTransactions, hasLength(5));
    expect(provider.summaryTransactions, hasLength(3));
    final misc = provider.transactionByReference('misc-expense')!;
    expect(provider.netExpenseAmountForTransaction(misc), 0);
    expect(provider.budgetExpenseAmountForTransaction(misc), 0);
    expect(provider.categoryAmountsForTransaction(misc), isEmpty);
    expect(
      provider
          .amountForCategorySelection(misc, {categories['expense_misc']!.id}),
      0,
    );
  });

  test('recategorizing to and from Misc refreshes persisted totals', () async {
    final transaction = await save(reference: 'recategorize', amount: 150);
    final provider = TransactionProvider();
    addTearDown(provider.dispose);
    await provider.loadData();
    expect(provider.todayTotals.expense, 150);

    for (final categoryKey in ['expense_misc', 'expense_groceries']) {
      await repository.saveTransaction(
        transaction.copyWith(categoryId: categories[categoryKey]!.id),
        skipAutoCategorization: true,
      );
      await provider.loadData();
      final expected = categoryKey == 'expense_misc' ? 0.0 : 150.0;
      expect(provider.todayTotals.expense, expected);
      expect(provider.monthTotals.expense, expected);
      expect(await WidgetDataProvider().getTodaySpending(), expected);
      expect(provider.allTransactions, hasLength(1));
    }
  });

  test('a period containing only Misc has no reporting activity', () async {
    await save(
        reference: 'misc-only', amount: 900, categoryKey: 'expense_misc');
    final provider = TransactionProvider();
    addTearDown(provider.dispose);
    await provider.loadData();

    expect(provider.todayTotals.expense, 0);
    expect(provider.weekTrendSeries.maxValue, 0);
    expect(provider.monthTrendSeries.maxValue, 0);
    expect(provider.summaryTransactions, isEmpty);
    expect(provider.accountSummaries.single.totalTransactions, 0);
    expect(await WidgetDataProvider().getTodayCategoryBreakdown(), isEmpty);
    expect(provider.monthlyInsight, contains('No monthly activity'));
  });

  test('widgets and daily, weekly, monthly notification totals exclude Misc',
      () async {
    await saveMixedTransactions();
    final widgetData = WidgetDataProvider();
    expect(await widgetData.getTodaySpending(), 136.5);
    expect(await widgetData.getCurrentWeekSpending(now: today), 136.5);
    expect(await widgetData.getCurrentMonthSpending(now: today), 136.5);
    expect(await widgetData.getTodayIncome(), 500);
    final expenses = await widgetData.getTodayCategoryBreakdown();
    expect(expenses.map((entry) => entry.name), isNot(contains('Misc')));
    expect(expenses.fold<double>(0, (sum, entry) => sum + entry.amount), 136.5);
    final income = await widgetData.getTodayIncomeCategoryBreakdown();
    expect(income.single.name, 'Salary');
    expect(income.single.amount, 500);

    // Exercise completed-period summaries independently of today's date.
    final historicalDate = DateTime(2025, 5, 15, 12);
    await save(reference: 'past-normal', amount: 40, date: historicalDate);
    await save(
      reference: 'past-misc',
      amount: 1000,
      categoryKey: 'expense_misc',
      date: historicalDate,
    );
    expect(
      await widgetData.getLastCompletedWeekSpending(now: DateTime(2025, 5, 19)),
      40,
    );
    expect(
      await widgetData.getLastCompletedMonthSpending(now: DateTime(2025, 6, 1)),
      40,
    );
  });

  test('overall and category budgets ignore Misc spending', () async {
    await saveMixedTransactions();
    final service = BudgetService();
    final start = DateTime(today.year, today.month, 1);
    final end = DateTime(today.year, today.month + 1, 1);
    expect(
        await service.calculateSpending(startDate: start, endDate: end), 136.5);
    expect(
      await service.calculateSpending(
        startDate: start,
        endDate: end,
        categoryId: categories['expense_misc']!.id,
      ),
      0,
    );
    final status = await service.getBudgetStatus(Budget(
      name: 'Monthly budget',
      type: 'monthly',
      amount: 200,
      startDate: start,
      createdAt: today,
    ));
    expect(status.spent, 136.5);
    expect(status.isExceeded, isFalse);
    expect(status.isApproachingLimit, isFalse);
  });

  test('insights exclude Misc even without provider amount callbacks',
      () async {
    await saveMixedTransactions();
    final transactions = await repository.getTransactions();
    final byId = {
      for (final category in categories.values) category.id: category
    };
    final insight = InsightsService(
      () => transactions,
      getCategoryById: (id) => byId[id],
    ).summarize();
    expect(insight[MapKeys.totalIncome], 500);
    expect(insight[MapKeys.totalExpense], 125);
  });

  test('API summaries and statistics exclude Misc while history retains it',
      () async {
    await saveMixedTransactions();
    final router = SummaryHandler().router;
    for (final route in ['/', '/by-bank', '/by-account']) {
      final response =
          await router(Request('GET', Uri.parse('http://localhost$route')));
      expect(response.statusCode, 200);
      final payload = jsonDecode(await response.readAsString());
      final summary =
          route == '/' ? payload as Map : (payload as List).single as Map;
      expect(summary['totalCredit'], 500);
      expect(summary['totalDebit'], 125);
      expect(summary['transactionCount'], 3);
      if (route == '/by-account') expect(summary['balance'], 1417.5);
    }

    final transactionsRouter = TransactionsHandler().router;
    final statsResponse = await transactionsRouter(
      Request('GET', Uri.parse('http://localhost/stats')),
    );
    final stats = jsonDecode(await statsResponse.readAsString()) as Map;
    expect(stats['totals']['totalVolume'], 625);
    expect(stats['totals']['totalCount'], 3);
    final historyResponse = await transactionsRouter(
      Request('GET', Uri.parse('http://localhost/')),
    );
    final history = jsonDecode(await historyResponse.readAsString()) as Map;
    expect(history['total'], 5);
  });

  test(
      'Misc tags and splits exclude the transaction, missing categories do not',
      () {
    final groceriesId = categories['expense_groceries']!.id!;
    final miscId = categories['expense_misc']!.id!;
    final byId = {
      for (final category in categories.values) category.id: category
    };
    for (final transaction in [
      Transaction(
        amount: 100,
        reference: 'tagged',
        categoryIds: [groceriesId, miscId],
      ),
      Transaction(
        amount: 100,
        reference: 'split',
        categorySplits: [
          TransactionCategorySplit(categoryId: groceriesId, amountMinor: 7500),
          TransactionCategorySplit(categoryId: miscId, amountMinor: 2500),
        ],
      ),
    ]) {
      expect(isMiscTransaction(transaction, getCategoryById: (id) => byId[id]),
          isTrue);
    }
    expect(
      isMiscTransaction(
        Transaction(amount: 100, reference: 'unassigned'),
        getCategoryById: (id) => byId[id],
      ),
      isFalse,
    );
    expect(
      isMiscTransaction(
        Transaction(
            amount: 100, reference: 'unknown-category', categoryId: 99999),
        getCategoryById: (id) => byId[id],
      ),
      isFalse,
    );
  });
}
