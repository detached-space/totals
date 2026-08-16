import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/transaction.dart' as models;
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late String databasePath;

  setUpAll(() {
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
  });

  tearDown(() async {
    if (db.isOpen) await DatabaseHelper.instance.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test('batch category update changes only category fields', () async {
    final repository = TransactionRepository();
    final first = _transaction(
      reference: 'batch-category-first',
      sourceMessageId: '101',
      categoryId: 2,
      categoryIds: const <int>[2, 3],
    );
    final second = _transaction(
      reference: 'batch-category-second',
      sourceMessageId: '102',
    );
    final untouched = _transaction(
      reference: 'batch-category-untouched',
      sourceMessageId: '103',
      categoryId: 4,
      categoryIds: const <int>[4],
    );
    for (final transaction in <models.Transaction>[
      first,
      second,
      untouched,
    ]) {
      await repository.saveTransaction(
        transaction,
        skipAutoCategorization: true,
      );
    }

    final changed = await repository.updateTransactionCategories(
      <models.Transaction>[
        first.copyWith(
          categoryId: 2,
          categoryIds: const <int>[2, 3, 7],
        ),
        second.copyWith(categoryId: 7, categoryIds: const <int>[7]),
      ],
    );

    expect(changed, 2);
    final rows = await db.query(
      'transactions',
      orderBy: 'reference',
    );
    final byReference = <String, Map<String, Object?>>{
      for (final row in rows)
        row['reference']! as String: Map<String, Object?>.from(row),
    };
    expect(byReference[first.reference]!['categoryId'], 2);
    expect(byReference[first.reference]!['categoryIds'], '[2,3,7]');
    expect(byReference[first.reference]!['sourceMessageId'], '101');
    expect(byReference[first.reference]!['ownerAccountNumber'], '0911223344');
    expect(byReference[first.reference]!['note'], 'Preserve this note');
    expect(byReference[second.reference]!['categoryId'], 7);
    expect(byReference[second.reference]!['categoryIds'], '[7]');
    expect(byReference[untouched.reference]!['categoryId'], 4);
    expect(byReference[untouched.reference]!['categoryIds'], '[4]');
  });

  test('provider adds flow-correct categories in one batch', () async {
    final repository = TransactionRepository();
    await repository.saveTransaction(
      _transaction(
        reference: 'batch-provider-debit',
        sourceMessageId: '201',
      ),
      skipAutoCategorization: true,
    );
    await repository.saveTransaction(
      _transaction(
        reference: 'batch-provider-credit',
        sourceMessageId: '202',
        type: 'CREDIT',
      ),
      skipAutoCategorization: true,
    );

    final provider = TransactionProvider();
    addTearDown(provider.dispose);
    await provider.loadData();
    final expenseCategories = provider.categories
        .where((category) => category.flow == 'expense' && category.id != null)
        .take(2)
        .toList(growable: false);
    final incomeCategories = provider.categories
        .where((category) => category.flow == 'income' && category.id != null)
        .take(2)
        .toList(growable: false);
    expect(expenseCategories, hasLength(2));
    expect(incomeCategories, hasLength(2));
    final existingExpenseCategory = expenseCategories.first;
    final expenseCategory = expenseCategories.last;
    final existingIncomeCategory = incomeCategories.first;
    final incomeCategory = incomeCategories.last;

    final transactionsByReference = <String, models.Transaction>{
      for (final transaction in provider.allTransactions)
        transaction.reference: transaction,
    };
    await repository.updateTransactionCategories(<models.Transaction>[
      transactionsByReference['batch-provider-debit']!.copyWith(
        categoryId: existingExpenseCategory.id,
        categoryIds: <int>[existingExpenseCategory.id!],
      ),
      transactionsByReference['batch-provider-credit']!.copyWith(
        categoryId: existingIncomeCategory.id,
        categoryIds: <int>[existingIncomeCategory.id!],
      ),
    ]);
    await provider.loadData();

    final changed = await provider.setCategoriesForTransactionsByType(
      provider.allTransactions,
      debitCategory: expenseCategory,
      creditCategory: incomeCategory,
    );

    expect(changed, 2);
    final categorized = <String, models.Transaction>{
      for (final transaction in provider.allTransactions)
        transaction.reference: transaction,
    };
    expect(
      categorized['batch-provider-debit']!.selectedCategoryIds,
      <int>[existingExpenseCategory.id!, expenseCategory.id!],
    );
    expect(
      categorized['batch-provider-debit']!.categoryId,
      existingExpenseCategory.id,
    );
    expect(
      categorized['batch-provider-credit']!.selectedCategoryIds,
      <int>[existingIncomeCategory.id!, incomeCategory.id!],
    );
    expect(
      categorized['batch-provider-credit']!.categoryId,
      existingIncomeCategory.id,
    );
    final unchanged = await provider.setCategoriesForTransactionsByType(
      provider.allTransactions,
      debitCategory: expenseCategory,
      creditCategory: incomeCategory,
    );
    expect(unchanged, 0);
    expect(
      categorized['batch-provider-debit']!.selectedCategoryIds,
      <int>[existingExpenseCategory.id!, expenseCategory.id!],
    );
    expect(
      categorized['batch-provider-credit']!.selectedCategoryIds,
      <int>[existingIncomeCategory.id!, incomeCategory.id!],
    );
    // The provider intentionally finalizes summaries and budget checks after
    // the optimistic category save. Let that work finish before closing the
    // shared test database.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  });
}

models.Transaction _transaction({
  required String reference,
  required String sourceMessageId,
  String type = 'DEBIT',
  int? categoryId,
  List<int>? categoryIds,
}) {
  return models.Transaction(
    amount: 125,
    reference: reference,
    creditor: 'Sender',
    receiver: 'Receiver',
    note: 'Preserve this note',
    time: '2026-07-14T10:30:00.000',
    currentBalance: '900.00',
    bankId: 6,
    type: type,
    accountNumber: '251911223344',
    ownerAccountNumber: '0911223344',
    ownerAssignmentSource: models.Transaction.automaticOwnerAssignment,
    categoryId: categoryId,
    categoryIds: categoryIds,
    sourceType: 'sms',
    sourceMessageId: sourceMessageId,
    sourceFingerprint: 'fingerprint-$sourceMessageId',
    sourceSubscriptionId: 1,
  );
}
