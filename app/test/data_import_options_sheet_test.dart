import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/widgets/data_import_options_sheet.dart';

void main() {
  final summary = BackupImportSummary(
    schemaVersion: 9,
    exportDate: DateTime.utc(2026, 7, 24),
    isFilteredExport: true,
    banks: const [
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
    ],
    budgetCount: 2,
    autoCategorizationRuleCount: 8,
    failedParseCount: 3,
    smsPatternCount: 20,
    loanDebtEntryCount: 1,
  );

  testWidgets('previews a backup and returns selective import options',
      (tester) async {
    DataImportOptions? result;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDataImportOptionsSheet(
                    context: context,
                    summary: summary,
                  );
                },
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Import backup'), findsOneWidget);
    expect(find.text('Filtered backup'), findsOneWidget);
    expect(find.text('CBE'), findsOneWidget);
    expect(find.text('Dashen Bank'), findsOneWidget);

    await tester.tap(find.text('Dashen Bank'));
    await tester.scrollUntilVisible(
      find.text('Auto-categorization rules'),
      300,
    );
    await tester.tap(find.text('Auto-categorization rules'));
    await tester.tap(find.text('Import selected'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.bankIds, {1});
    expect(result!.includeAutoCategorization, isFalse);
    expect(result!.isFullImport, isFalse);
  });
}
