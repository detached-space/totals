import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/widgets/clear_database_dialog.dart';

void main() {
  Widget buildHarness() {
    return ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showClearDatabaseDialog(context),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows independently selectable local data groups',
      (tester) async {
    await tester.pumpWidget(buildHarness());

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Transactions & Accounts'), findsOneWidget);
    expect(find.text('Quick Access accounts'), findsOneWidget);
    expect(find.text('Budgets'), findsOneWidget);
    expect(find.text('Auto-categorization rules'), findsOneWidget);
    expect(find.text('Loans and debts'), findsOneWidget);
    expect(find.text('Failed Parses'), findsOneWidget);
    expect(find.text('SMS patterns'), findsNothing);
    expect(find.byIcon(Icons.receipt_long), findsNothing);
    expect(find.byIcon(Icons.people_outline), findsNothing);
    expect(find.byIcon(Icons.pie_chart_outline), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
    expect(find.byIcon(Icons.handshake_outlined), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enables Clear after selecting Quick Access accounts',
      (tester) async {
    await tester.pumpWidget(buildHarness());

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    ElevatedButton clearButton() => tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Clear'),
        );

    expect(clearButton().onPressed, isNull);
    await tester.tap(find.text('Quick Access accounts'));
    await tester.pump();
    expect(clearButton().onPressed, isNotNull);
  });
}
