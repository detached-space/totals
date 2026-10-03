import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/screens/money/money_page.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/account_sync_status_service.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(
      envString: 'SHARED_EXPENSES_URL=https://example.invalid',
    );
  });

  testWidgets('cash wallet menu can opt into the total balance',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final transactionProvider = _CashWalletMenuTestProvider();
    addTearDown(transactionProvider.dispose);
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(themeProvider.dispose);
    final syncStatusService = AccountSyncStatusService.instance;
    syncStatusService.clearAll();
    addTearDown(syncStatusService.clearAll);
    final pageKey = GlobalKey<RedesignMoneyPageState>();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TransactionProvider>.value(
            value: transactionProvider,
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<AccountSyncStatusService>.value(
            value: syncStatusService,
          ),
        ],
        child: MaterialApp(
          home: RedesignMoneyPage(key: pageKey),
        ),
      ),
    );

    pageKey.currentState!.openAccountsTab();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Cash Wallet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byTooltip('Account options'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('View transactions'), findsOneWidget);
    expect(find.text('Show in total balance'), findsOneWidget);
    final switchFinder = find.byKey(
      const ValueKey<String>('cash-total-balance-switch'),
    );
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    await tester.tap(
      find.byKey(const ValueKey<String>('cash-total-balance-action')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(transactionProvider.includeCashInTotals, isTrue);
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
  });
}

class _CashWalletMenuTestProvider extends TransactionProvider {
  bool includeCashInTotals = false;
  int _version = 1;

  AccountSummary get _cashAccount => AccountSummary(
        bankId: CashConstants.bankId,
        accountNumber: CashConstants.defaultAccountNumber,
        accountHolderName: CashConstants.defaultAccountHolderName,
        totalTransactions: 2,
        totalCredit: 100,
        totalDebit: 25,
        settledBalance: 0,
        balance: 75,
        pendingCredit: 0,
        includeInTotals: includeCashInTotals,
        isDefault: true,
      );

  @override
  bool get isLoading => false;

  @override
  int get dataVersion => _version;

  @override
  AllSummary get summary => AllSummary(
        totalCredit: 100,
        totalDebit: 25,
        banks: 1,
        totalBalance: includeCashInTotals ? 75 : 0,
        accounts: 1,
      );

  @override
  List<BankSummary> get bankSummaries => <BankSummary>[
        BankSummary(
          accountCount: 1,
          bankId: CashConstants.bankId,
          totalCredit: 100,
          totalDebit: 25,
          settledBalance: 0,
          totalBalance: includeCashInTotals ? 75 : 0,
          pendingCredit: 0,
          hasAccountsIncludedInTotalBalance: includeCashInTotals,
        ),
      ];

  @override
  List<AccountSummary> get accountSummaries => <AccountSummary>[_cashAccount];

  @override
  Future<bool> updateAccountPreferences({
    required int bankId,
    required String accountNumber,
    bool? includeInTotals,
    bool? isDormant,
  }) async {
    if (bankId != CashConstants.bankId || includeInTotals == null) return false;
    includeCashInTotals = includeInTotals;
    _version += 1;
    notifyListeners();
    return true;
  }
}
