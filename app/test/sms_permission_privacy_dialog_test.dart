import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/widgets/sms_permission_privacy_dialog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('explains local SMS processing before permission',
      (tester) async {
    bool? result;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (_) => const SmsPermissionPrivacyDialog(),
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

    expect(find.text('Data Stays On Device'), findsOneWidget);
    expect(find.byKey(const Key('totals-privacy-logo')), findsNothing);
    expect(find.text('•'), findsNothing);
    expect(
      find.textContaining('Those SMS contents are not sent to our servers.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('unless you explicitly enable Data Sync'),
      findsOneWidget,
    );
    expect(
      find.textContaining('which server receives them'),
      findsOneWidget,
    );
    expect(find.textContaining('Shared Expenses'), findsOneWidget);
    expect(
      find.textContaining('Your data stays on this device by default'),
      findsOneWidget,
    );
    expect(
      find.textContaining('exclude it from battery optimization'),
      findsOneWidget,
    );
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('uses settings action after permanent denial', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: const MaterialApp(
          home: Scaffold(
            body: SmsPermissionPrivacyDialog(requiresSettings: true),
          ),
        ),
      ),
    );

    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('Allow'), findsNothing);
  });

  testWidgets('uses a battery-specific modal when SMS is already enabled',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: const MaterialApp(
          home: Scaffold(
            body: ExistingSmsBatteryOptimizationDialog(),
          ),
        ),
      ),
    );

    expect(find.text('Keep Totals Running Reliably'), findsOneWidget);
    expect(
        find.textContaining('SMS access is already enabled'), findsOneWidget);
    expect(
      find.textContaining('does not change how your data is handled'),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Allow'), findsNothing);
  });
}
