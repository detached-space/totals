import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:totals/_redesign/widgets/reimbursement_link_sheet.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/models/reimbursement_allocation.dart';
import 'package:totals/models/transaction.dart' as models;
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/repositories/budget_repository.dart';
import 'package:totals/repositories/reimbursement_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/screens/stats_recap_page.dart';
import 'package:totals/services/budget_service.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';
import 'package:totals/services/financial_insights.dart';
import 'package:totals/services/widget_data_provider.dart';
import 'package:totals/utils/map_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late String databasePath;
  late ReimbursementRepository reimbursementRepository;
  late TransactionRepository transactionRepository;
  late int lunchCategoryId;
  late int reimbursementCategoryId;

  setUpAll(() {
    dotenv.loadFromString(
      envString: 'SHARED_EXPENSES_URL=https://example.invalid',
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DataSyncSettingsService.cachedEnabled = false;
    await DatabaseHelper.instance.close();
    databasePath = '${await databaseFactoryFfi.getDatabasesPath()}/totals.db';
    await databaseFactoryFfi.deleteDatabase(databasePath);
    db = await DatabaseHelper.instance.database;

    final lunch = await CategoryRepository().createCategory(
      name: 'Lunch test',
      essential: false,
      flow: 'expense',
    );
    lunchCategoryId = lunch.id!;
    final reimbursementRows = await db.query(
      'categories',
      columns: const ['id'],
      where: 'builtInKey = ?',
      whereArgs: const ['income_reimbursement'],
      limit: 1,
    );
    reimbursementCategoryId = reimbursementRows.single['id']! as int;

    reimbursementRepository = ReimbursementRepository();
    transactionRepository = TransactionRepository();
    for (final transaction in <models.Transaction>[
      _transaction(
        reference: 'lunch-one',
        amount: 1000,
        type: 'DEBIT',
        time: '2026-07-22T12:00:00.000',
        categoryId: lunchCategoryId,
      ),
      _transaction(
        reference: 'lunch-two',
        amount: 300,
        type: 'DEBIT',
        time: '2026-07-23T12:00:00.000',
        categoryId: lunchCategoryId,
      ),
      _transaction(
        reference: 'friend-one',
        amount: 700,
        type: 'CREDIT',
        time: '2026-08-02T12:00:00.000',
        categoryId: reimbursementCategoryId,
      ),
      _transaction(
        reference: 'friend-two',
        amount: 200,
        type: 'CREDIT',
        time: '2026-08-03T12:00:00.000',
        categoryId: reimbursementCategoryId,
      ),
    ]) {
      await transactionRepository.saveTransaction(
        transaction,
        skipAutoCategorization: true,
      );
    }
  });

  tearDown(() async {
    if (db.isOpen) await DatabaseHelper.instance.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test(
      'many-to-many allocations reduce the original expense period and not income',
      () async {
    await reimbursementRepository.replaceForReimbursement(
      reimbursementTransactionReference: 'friend-one',
      allocations: const [
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'lunch-one',
          appliedAmount: 400,
        ),
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'lunch-two',
          appliedAmount: 300,
        ),
      ],
    );
    await reimbursementRepository.replaceForReimbursement(
      reimbursementTransactionReference: 'friend-two',
      allocations: const [
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'lunch-one',
          appliedAmount: 200,
        ),
      ],
    );

    final provider = TransactionProvider();
    addTearDown(provider.dispose);
    await provider.loadData();
    final byReference = <String, models.Transaction>{
      for (final transaction in provider.allTransactions)
        transaction.reference: transaction,
    };

    expect(
      provider.incomeAmountForTransaction(byReference['friend-one']!),
      0,
    );
    expect(
      provider.incomeAmountForTransaction(byReference['friend-two']!),
      0,
    );
    expect(provider.isReimbursedExpense(byReference['lunch-one']!), isTrue);
    expect(provider.isReimbursedExpense(byReference['lunch-two']!), isTrue);
    expect(provider.isReimbursedExpense(byReference['friend-one']!), isFalse);
    final insights = InsightsService(
      () => provider.allTransactions,
      getCategoryById: provider.getCategoryById,
      isExcludedFromIncome: provider.isReimbursementTransaction,
      expenseAmountForTransaction: provider.netExpenseAmountForTransaction,
    ).summarize();
    expect(insights[MapKeys.totalIncome], 0);
    expect(insights[MapKeys.totalExpense], 400);
    final recap = StatsRecapData.from(
      transactions: provider.allTransactions,
      banks: const [],
      year: 2026,
      expenseAmountForTransaction: provider.netExpenseAmountForTransaction,
      incomeAmountForTransaction: provider.incomeAmountForTransaction,
    );
    expect(recap.topSentTo.single.amount, 400);
    expect(recap.topReceivedFrom, isEmpty);
    expect(
      provider.budgetExpenseAmountForTransaction(byReference['lunch-one']!),
      400,
    );
    expect(
      provider.budgetExpenseAmountForTransaction(byReference['lunch-two']!),
      0,
    );

    // Although the money arrived in August, it reduces July's Lunch spend.
    expect(
      await BudgetService().calculateSpending(
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 31, 23, 59, 59, 999),
        categoryId: lunchCategoryId,
      ),
      400,
    );
    expect(
      await WidgetDataProvider().getSpendingForRange(
        DateTime(2026, 7, 1),
        DateTime(2026, 7, 31, 23, 59, 59, 999),
      ),
      400,
    );
  });

  test('home cash flow keeps reimbursement inflow and gross expense', () async {
    final now = DateTime.now().toIso8601String();
    await transactionRepository.saveTransaction(
      _transaction(
        reference: 'today-expense',
        amount: 300,
        type: 'DEBIT',
        time: now,
        categoryId: lunchCategoryId,
      ),
      skipAutoCategorization: true,
    );
    await transactionRepository.saveTransaction(
      _transaction(
        reference: 'today-reimbursement',
        amount: 150,
        type: 'CREDIT',
        time: now,
        categoryId: reimbursementCategoryId,
      ),
      skipAutoCategorization: true,
    );
    await reimbursementRepository.replaceForReimbursement(
      reimbursementTransactionReference: 'today-reimbursement',
      allocations: const [
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'today-expense',
          appliedAmount: 150,
        ),
      ],
    );

    final provider = TransactionProvider();
    addTearDown(provider.dispose);
    await provider.loadData();

    expect(provider.todayCashFlowTotals.income, 150);
    expect(provider.todayCashFlowTotals.expense, 300);
    expect(provider.weekCashFlowTotals.income, 150);
    expect(provider.weekCashFlowTotals.expense, 300);

    // Spending surfaces still use net expense and exclude reimbursements from
    // earned income.
    expect(provider.todayTotals.income, 0);
    expect(provider.todayTotals.expense, 150);
  });

  testWidgets('custom amount remains editable while temporarily empty',
      (tester) async {
    final provider = _ReimbursementPickerTestProvider(
      <models.Transaction>[
        _transaction(
          reference: 'lunch-two',
          amount: 300,
          type: 'DEBIT',
          time: '2026-07-23T12:00:00.000',
          categoryId: lunchCategoryId,
          includeCounterparty: false,
        ),
      ],
    );
    addTearDown(provider.dispose);
    final reimbursement = _transaction(
      reference: 'friend-one',
      amount: 700,
      type: 'CREDIT',
      time: '2026-08-02T12:00:00.000',
      categoryId: reimbursementCategoryId,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showReimbursementLinkSheet(
                  context: context,
                  transaction: reimbursement,
                  provider: provider,
                ),
                child: const Text('Open reimbursement'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reimbursement'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey('apply-reimbursement-lunch-two')),
    );
    await tester.pump();

    final amountField =
        find.byKey(const ValueKey('reimbursement-amount-lunch-two'));
    expect(amountField, findsOneWidget);

    await tester.enterText(amountField, '');
    await tester.pump();
    expect(amountField, findsOneWidget);

    await tester.enterText(amountField, '125.50');
    await tester.pump();
    expect(find.text('125.50'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('save-reimbursement-links'));
    final saveButtonContext = tester.element(saveButton);
    final mediaQuery = MediaQuery.of(saveButtonContext);
    final viewportBottom =
        tester.getBottomRight(find.byType(Scaffold).first).dy;
    final keyboardTop = viewportBottom - mediaQuery.viewInsets.bottom;
    final sheetInset = find.ancestor(
      of: saveButton,
      matching: find.byType(AnimatedPadding),
    );
    expect(sheetInset, findsOneWidget);
    final appliedInset = tester
        .widget<AnimatedPadding>(sheetInset)
        .padding
        .resolve(TextDirection.ltr)
        .bottom;
    expect(appliedInset, greaterThan(mediaQuery.viewInsets.bottom));
    expect(
      tester.getBottomRight(saveButton).dy,
      lessThanOrEqualTo(keyboardTop - 24),
    );

    expect(
      find.byKey(const ValueKey('leave-reimbursement-unlinked')),
      findsNothing,
    );
  });

  test('invalid replacement is atomic and unlinking reverses budget spend',
      () async {
    await reimbursementRepository.replaceForReimbursement(
      reimbursementTransactionReference: 'friend-one',
      allocations: const [
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'lunch-one',
          appliedAmount: 500,
        ),
      ],
    );

    await expectLater(
      reimbursementRepository.replaceForReimbursement(
        reimbursementTransactionReference: 'friend-one',
        allocations: const [
          ReimbursementAllocationDraft(
            expenseTransactionReference: 'lunch-one',
            appliedAmount: 800,
          ),
        ],
      ),
      throwsStateError,
    );
    expect(
      (await reimbursementRepository.getForReimbursement('friend-one'))
          .single
          .appliedAmount,
      500,
    );

    final provider = TransactionProvider();
    addTearDown(provider.dispose);
    await provider.loadData();
    final reimbursement = provider.allTransactions.singleWhere(
      (transaction) => transaction.reference == 'friend-one',
    );
    await provider.updateCategoriesForTransaction(
      reimbursement,
      categoryIds: const [],
    );

    expect(
      await reimbursementRepository.getForReimbursement('friend-one'),
      isEmpty,
    );
    expect(
      await BudgetService().calculateSpending(
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 31, 23, 59, 59, 999),
        categoryId: lunchCategoryId,
      ),
      1300,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
  });

  test('unlinking the final expense removes the reimbursement category',
      () async {
    await reimbursementRepository.replaceForReimbursement(
      reimbursementTransactionReference: 'friend-one',
      allocations: const [
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'lunch-one',
          appliedAmount: 400,
        ),
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'lunch-two',
          appliedAmount: 200,
        ),
      ],
    );
    final allocations =
        await reimbursementRepository.getForReimbursement('friend-one');

    final firstUpdate = await transactionRepository
        .unlinkReimbursementAllocation(allocations.first.id!);
    expect(firstUpdate, isNull);
    expect(
      await reimbursementRepository.getForReimbursement('friend-one'),
      hasLength(1),
    );

    final finalAllocation =
        (await reimbursementRepository.getForReimbursement('friend-one'))
            .single;
    final finalUpdate = await transactionRepository
        .unlinkReimbursementAllocation(finalAllocation.id!);
    expect(finalUpdate, isNotNull);
    expect(
      finalUpdate!.selectedCategoryIds,
      isNot(contains(reimbursementCategoryId)),
    );
    expect(
      await reimbursementRepository.getForReimbursement('friend-one'),
      isEmpty,
    );
  });

  test('batched budget statuses preserve reimbursement-adjusted spending',
      () async {
    final budgetRepository = BudgetRepository();
    final periodStart = DateTime(2026, 7, 1);
    final periodEnd = DateTime(2026, 7, 31, 23, 59, 59);
    for (final budget in <Budget>[
      Budget(
        name: 'All expenses',
        type: 'category',
        amount: 2000,
        startDate: periodStart,
        endDate: periodEnd,
        timeFrame: 'never',
        createdAt: DateTime(2026, 7, 1),
      ),
      Budget(
        name: 'Lunch only',
        type: 'category',
        amount: 1500,
        categoryId: lunchCategoryId,
        startDate: periodStart,
        endDate: periodEnd,
        timeFrame: 'never',
        createdAt: DateTime(2026, 7, 2),
      ),
    ]) {
      await budgetRepository.insertBudget(budget);
    }
    await reimbursementRepository.replaceForReimbursement(
      reimbursementTransactionReference: 'friend-one',
      allocations: const [
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'lunch-one',
          appliedAmount: 500,
        ),
      ],
    );

    final statuses = await BudgetService().getAllBudgetStatuses();
    expect(statuses, hasLength(2));
    expect(
      <String, double>{
        for (final status in statuses) status.budget.name: status.spent,
      },
      <String, double>{
        'All expenses': 800,
        'Lunch only': 800,
      },
    );
  });

  test(
      'deleting expenses removes orphaned reimbursement categories only after the final link',
      () async {
    await reimbursementRepository.replaceForReimbursement(
      reimbursementTransactionReference: 'friend-one',
      allocations: const [
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'lunch-one',
          appliedAmount: 500,
        ),
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'lunch-two',
          appliedAmount: 200,
        ),
      ],
    );

    await transactionRepository.deleteTransactionsByReferences(
      const ['lunch-two'],
    );

    final remaining =
        await reimbursementRepository.getForReimbursement('friend-one');
    expect(remaining, hasLength(1));
    expect(remaining.single.expenseTransactionReference, 'lunch-one');
    expect(
      (await transactionRepository.getTransactionByReference('friend-one'))!
          .selectedCategoryIds,
      contains(reimbursementCategoryId),
    );

    await transactionRepository.deleteTransactionsByReferences(
      const ['lunch-one'],
    );
    expect(
      await reimbursementRepository.getForReimbursement('friend-one'),
      isEmpty,
    );
    final orphanedReimbursement =
        await transactionRepository.getTransactionByReference('friend-one');
    expect(orphanedReimbursement, isNotNull);
    expect(orphanedReimbursement!.categoryId, isNull);
    expect(orphanedReimbursement.selectedCategoryIds, isEmpty);

    // An intentionally unlinked reimbursement is not changed by deleting
    // another reimbursement's expense.
    expect(
      (await transactionRepository.getTransactionByReference('friend-two'))!
          .selectedCategoryIds,
      contains(reimbursementCategoryId),
    );

    await transactionRepository.deleteTransactionsByReferences(
      const ['friend-one'],
    );
    expect(await reimbursementRepository.getAllocations(), isEmpty);
  });

  test('orphan cleanup preserves any other income category', () async {
    final otherIncomeCategory = await CategoryRepository().createCategory(
      name: 'Other income test',
      essential: false,
      flow: 'income',
    );
    await db.update(
      'transactions',
      {
        'categoryId': reimbursementCategoryId,
        'categoryIds': jsonEncode(
          [reimbursementCategoryId, otherIncomeCategory.id!],
        ),
      },
      where: 'reference = ?',
      whereArgs: const ['friend-one'],
    );
    await reimbursementRepository.replaceForReimbursement(
      reimbursementTransactionReference: 'friend-one',
      allocations: const [
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'lunch-one',
          appliedAmount: 500,
        ),
      ],
    );

    await transactionRepository.deleteTransactionsByReferences(
      const ['lunch-one'],
    );

    final reimbursement =
        await transactionRepository.getTransactionByReference('friend-one');
    expect(reimbursement, isNotNull);
    expect(reimbursement!.categoryId, otherIncomeCategory.id);
    expect(reimbursement.selectedCategoryIds, [otherIncomeCategory.id]);
  });

  test('clearing an expense bank also repairs surviving reimbursements',
      () async {
    await reimbursementRepository.replaceForReimbursement(
      reimbursementTransactionReference: 'friend-one',
      allocations: const [
        ReimbursementAllocationDraft(
          expenseTransactionReference: 'lunch-one',
          appliedAmount: 500,
        ),
      ],
    );

    await transactionRepository.clearBanks({1});

    expect(
      await reimbursementRepository.getForReimbursement('friend-one'),
      isEmpty,
    );
    final reimbursement =
        await transactionRepository.getTransactionByReference('friend-one');
    expect(reimbursement, isNotNull);
    expect(reimbursement!.selectedCategoryIds, isEmpty);
  });

  test('renaming is preserved and deletion is safely reseeded around a custom',
      () async {
    await db.update(
      'categories',
      {'name': 'Paid back by friends'},
      where: 'builtInKey = ?',
      whereArgs: const ['income_reimbursement'],
    );
    final categories = CategoryRepository();
    await categories.ensureSeeded();
    var stableRows = await db.query(
      'categories',
      where: 'builtInKey = ?',
      whereArgs: const ['income_reimbursement'],
    );
    expect(stableRows.single['name'], 'Paid back by friends');

    await db.delete(
      'categories',
      where: 'builtInKey = ?',
      whereArgs: const ['income_reimbursement'],
    );
    await db.insert('categories', {
      'name': 'Reimbursement',
      'essential': 0,
      'uncategorized': 0,
      'iconKey': 'wallet',
      'description': 'Custom category',
      'flow': 'income',
      'recurring': 0,
      'builtIn': 0,
      'builtInKey': null,
    });

    await categories.ensureSeeded();
    stableRows = await db.query(
      'categories',
      where: 'builtInKey = ?',
      whereArgs: const ['income_reimbursement'],
    );
    expect(stableRows, hasLength(1));
    expect(stableRows.single['name'], 'Reimbursement (Totals)');

    final customRows = await db.query(
      'categories',
      where: 'name = ? AND flow = ?',
      whereArgs: const ['Reimbursement', 'income'],
    );
    expect(customRows, hasLength(1));
    expect(customRows.single['builtIn'], 0);
    expect(customRows.single['builtInKey'], isNull);
  });
}

models.Transaction _transaction({
  required String reference,
  required double amount,
  required String type,
  required String time,
  required int categoryId,
  bool includeCounterparty = true,
}) {
  return models.Transaction(
    amount: amount,
    reference: reference,
    creditor: includeCounterparty && type == 'CREDIT' ? 'Friend' : null,
    receiver: includeCounterparty && type == 'DEBIT' ? 'Cafe' : null,
    time: time,
    bankId: type == 'CREDIT' ? 100 : 1,
    type: type,
    categoryId: categoryId,
    categoryIds: [categoryId],
  );
}

class _ReimbursementPickerTestProvider extends TransactionProvider {
  final List<models.Transaction> _testTransactions;

  _ReimbursementPickerTestProvider(this._testTransactions);

  @override
  List<models.Transaction> get allTransactions => _testTransactions;

  @override
  bool isSelfTransfer(models.Transaction transaction) => false;

  @override
  String categoryLabelForTransaction(
    models.Transaction transaction, {
    String uncategorizedLabel = 'Uncategorized',
  }) {
    return 'Lunch test';
  }

  @override
  String getBankShortName(int? bankId) => 'Cash';

  @override
  String getBankImage(int? bankId) => '';
}
