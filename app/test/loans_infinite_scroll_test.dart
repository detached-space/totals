import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/screens/loans_page.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/loan_debt_entry.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/repositories/loan_debt_repository.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(
      envString: 'SHARED_EXPENSES_URL=https://example.invalid',
    );
  });

  testWidgets('loads additional linked loans while scrolling', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final transactions = List<Transaction>.generate(
      45,
      (index) => Transaction(
        amount: 100 + index.toDouble(),
        reference: 'loan-$index',
        receiver: 'Person ${index.toString().padLeft(2, '0')}',
        time: DateTime(2026, 1, 1).add(Duration(days: index)).toIso8601String(),
        bankId: 1,
        type: 'DEBIT',
        categoryId: 1,
      ),
      growable: false,
    );
    final entries = List<LoanDebtEntry>.generate(
      transactions.length,
      (index) {
        final timestamp = DateTime(2026, 1, 1).add(Duration(days: index));
        return LoanDebtEntry(
          transactionReference: transactions[index].reference,
          personName: 'Person ${index.toString().padLeft(2, '0')}',
          direction: LoanDebtDirection.lent,
          createdAt: timestamp,
          updatedAt: timestamp,
        );
      },
      growable: false,
    );
    final provider = _LoansTestProvider(transactions);
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TransactionProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
          ),
        ],
        child: MaterialApp(
          home: LoansPage(
            repository: _LoansTestRepository(entries),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Linked'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Page '), findsNothing);
    expect(find.text('Person 24'), findsNothing);

    final loansScrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    expect(loansScrollable, findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Person 00'),
      500,
      scrollable: loansScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Person 00'), findsOneWidget);
    expect(find.textContaining('Page '), findsNothing);
  });
}

class _LoansTestRepository extends LoanDebtRepository {
  final List<LoanDebtEntry> entries;

  _LoansTestRepository(this.entries);

  @override
  Future<List<LoanDebtEntry>> getEntries() async => entries;

  @override
  Future<List<LoanDebtRepayment>> getRepayments() async =>
      const <LoanDebtRepayment>[];
}

class _LoansTestProvider extends TransactionProvider {
  final List<Transaction> testTransactions;

  _LoansTestProvider(this.testTransactions);

  @override
  List<Transaction> get allTransactions => testTransactions;

  @override
  List<Category> get categories => const <Category>[
        Category(
          id: 1,
          name: 'Loan',
          essential: true,
          flow: 'expense',
          builtIn: true,
          builtInKey: 'expense_loan',
        ),
      ];

  @override
  String getBankName(int? bankId) => 'Test Bank';

  @override
  String getBankShortName(int? bankId) => 'Test';
}
