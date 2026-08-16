import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/widgets/transaction_tile.dart';
import 'package:totals/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('reimbursed expenses show a category-style status chip',
      (tester) async {
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(themeProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: const MaterialApp(
          home: Scaffold(
            body: TransactionTile(
              bank: 'CBE',
              category: 'Shopping',
              isCategorized: true,
              isDebit: true,
              isReimbursed: true,
              amount: '- ETB 3,000',
              amountColor: Colors.red,
              name: 'Store',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Reimbursed'), findsOneWidget);
  });
}
