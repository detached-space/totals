import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/screens/todays_transactions_page.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.loadFromString(
      envString: 'SHARED_EXPENSES_URL=https://example.invalid',
    );
  });

  testWidgets('map app-bar title creates and removes a custom place name',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    String? savedName;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => ThemeProvider(initialThemeMode: ThemeMode.light),
          ),
          ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ],
        child: MaterialApp(
          home: TodaysTransactionsPage(
            transactionReferences: const <String>{},
            title: 'CMC area',
            subtitle: '1 transaction',
            onTitleChanged: (name) async {
              savedName = name;
              return name ?? 'CMC area';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('CMC area'));
    await tester.pumpAndSettle();
    expect(find.text('Name this place'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Home');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedName, 'Home');
    expect(find.text('Home'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Edit place name'), findsOneWidget);
    await tester.tap(find.text('Remove name'));
    await tester.pumpAndSettle();

    expect(savedName, isNull);
    expect(find.text('CMC area'), findsOneWidget);
  });
}
