import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/widgets/credit_debit_breakdown_sheet.dart';
import 'package:totals/providers/theme_provider.dart';

void main() {
  testWidgets('shows merged credit and fee-inclusive debit breakdown',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    var didOpenUnreconciledTransactions = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCreditDebitBreakdownSheet(
                  context,
                  totalCredit: 1000,
                  totalDebit: 115,
                  transferIn: 200,
                  transferOut: 300,
                  feesAndVat: 15,
                  unreconciledAdjustment: -42.50,
                  reconciliationMismatchCount: 3,
                  onUnreconciledTap: () {
                    didOpenUnreconciledTransactions = true;
                  },
                  showAmounts: true,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Received from others'), findsOneWidget);
    expect(find.text('Moved in from your accounts'), findsOneWidget);
    expect(find.text('Paid or sent to others'), findsOneWidget);
    expect(find.text('Moved out to your accounts'), findsOneWidget);
    expect(find.text('Bank fees & VAT'), findsOneWidget);
    expect(find.text('ETB 1,200.00'), findsOneWidget);
    expect(find.text('ETB 415.00'), findsOneWidget);
    expect(find.text('ETB 15.00'), findsOneWidget);
    expect(find.text('By your bank'), findsNothing);
    expect(find.text('Unreconciled activity'), findsOneWidget);
    expect(find.text('-ETB 42.50'), findsOneWidget);
    expect(
      find.text('Balance checkpoints that did not match: 3'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Unreconciled activity'));
    await tester.tap(find.text('Unreconciled activity'));
    await tester.pumpAndSettle();

    expect(didOpenUnreconciledTransactions, isTrue);
    expect(find.text('Credit & debit breakdown'), findsNothing);
  });
}
