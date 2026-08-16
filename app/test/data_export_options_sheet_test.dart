import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/widgets/data_export_options_sheet.dart';

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
      id: 4,
      name: 'Dashen Bank',
      shortName: 'Dashen',
      accountCount: 1,
      transactionCount: 40,
    ),
  ];

  Widget buildHarness(ValueChanged<DataExportOptions?> onResult) {
    return ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                onResult(
                  await showDataExportOptionsSheet(
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

  testWidgets('defaults to a backward-compatible full backup', (tester) async {
    DataExportOptions? result;
    await tester.pumpWidget(buildHarness((value) => result = value));

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('CBE'), findsOneWidget);
    expect(find.text('Dashen Bank'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Auto-categorization rules'),
      300,
    );
    expect(find.text('Quick Access accounts'), findsOneWidget);
    expect(find.text('Auto-categorization rules'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Failed message diagnostics'),
      300,
    );
    expect(find.text('SMS parsing configuration'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.isFullBackup, isTrue);
    expect(result!.bankIds, isNull);
  });

  testWidgets('returns selected banks and optional sections', (tester) async {
    DataExportOptions? result;
    await tester.pumpWidget(buildHarness((value) => result = value));

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dashen Bank'));
    await tester.scrollUntilVisible(
      find.text('Quick Access accounts'),
      300,
    );
    await tester.tap(find.text('Quick Access accounts'));
    await tester.scrollUntilVisible(
      find.text('Auto-categorization rules'),
      300,
    );
    await tester.tap(find.text('Auto-categorization rules'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.bankIds, {1});
    expect(result!.includeQuickAccessAccounts, isFalse);
    expect(result!.includeAutoCategorization, isFalse);
    expect(result!.isFullBackup, isFalse);
  });
}
