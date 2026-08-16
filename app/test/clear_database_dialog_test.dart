import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/services/data_clear_service.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/widgets/clear_database_dialog.dart';

void main() {
  const banks = [
    ExportBankSummary(
      id: 1,
      name: 'CBE',
      shortName: 'CBE',
      accountCount: 2,
      transactionCount: 120,
    ),
    ExportBankSummary(
      id: 100,
      name: 'Cash Wallet',
      shortName: 'Cash Wallet',
      accountCount: 1,
      transactionCount: 8,
    ),
  ];

  Widget buildHarness(ValueChanged<ClearDataSelection?> onResult) {
    return ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                onResult(
                  await showClearDataOptionsSheet(
                    context: context,
                    banks: banks,
                  ),
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
  }

  FilledButton clearButton(WidgetTester tester) =>
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Clear selected'),
      );

  CheckboxListTile bankTile(WidgetTester tester, String name) =>
      tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text(name),
          matching: find.byType(CheckboxListTile),
        ),
      );

  testWidgets('matches export layout with banks and additional data switches',
      (tester) async {
    await tester.pumpWidget(buildHarness((_) {}));

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Banks and wallets'), findsOneWidget);
    expect(find.text('CBE'), findsOneWidget);
    expect(find.text('Cash Wallet'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    expect(bankTile(tester, 'CBE').value, isFalse);
    expect(bankTile(tester, 'Cash Wallet').value, isFalse);
    expect(clearButton(tester).onPressed, isNull);

    await tester.scrollUntilVisible(
      find.text('Quick Access accounts'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Additional data'), findsOneWidget);
    for (final title in const [
      'Quick Access accounts',
      'Budgets',
      'Auto-categorization rules',
      'Loans and debts',
      'Failed message diagnostics',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('SMS patterns'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('select all and clear all toggle every bank', (tester) async {
    await tester.pumpWidget(buildHarness((_) {}));

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select all'));
    await tester.pump();

    expect(find.text('Clear all'), findsOneWidget);
    expect(bankTile(tester, 'CBE').value, isTrue);
    expect(bankTile(tester, 'Cash Wallet').value, isTrue);
    expect(clearButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Clear all'));
    await tester.pump();

    expect(find.text('Select all'), findsOneWidget);
    expect(bankTile(tester, 'CBE').value, isFalse);
    expect(bankTile(tester, 'Cash Wallet').value, isFalse);
    expect(clearButton(tester).onPressed, isNull);
  });

  testWidgets('returns an individual bank selection', (tester) async {
    ClearDataSelection? result;
    await tester.pumpWidget(buildHarness((value) => result = value));

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CBE'));
    await tester.pump();
    await tester.tap(find.text('Clear selected'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.financialData, isTrue);
    expect(result!.bankIds, {1});
    expect(result!.quickAccessAccounts, isFalse);
  });

  testWidgets('allows clearing an additional group without a bank',
      (tester) async {
    ClearDataSelection? result;
    await tester.pumpWidget(buildHarness((value) => result = value));

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Quick Access accounts'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Quick Access accounts'));
    await tester.pump();
    await tester.tap(find.text('Clear selected'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.financialData, isFalse);
    expect(result!.bankIds, isEmpty);
    expect(result!.quickAccessAccounts, isTrue);
  });
}
