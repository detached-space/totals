import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/screens/account_share_qr_page.dart';
import 'package:totals/utils/account_share_payload.dart';
import 'package:totals/widgets/account_share_qr_code.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'account_share_display_name': 'Device Owner',
    });
  });

  testWidgets(
    'quick-access rows show holders and produce a compatible QR payload',
    (tester) async {
      final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
      addTearDown(themeProvider.dispose);

      const accounts = <AccountShareEntry>[
        AccountShareEntry(
          bankId: 1,
          accountNumber: '1000123456789',
          name: 'Almaz',
        ),
        AccountShareEntry(
          bankId: 3,
          accountNumber: '2000987654321',
          name: 'Bekele',
        ),
      ];

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: const MaterialApp(
            home: AccountShareQrPage(
              initialAccounts: accounts,
              initialDisplayName: 'Your contacts',
              showAccountNames: true,
              title: 'Share Quick Access Accounts',
              shareMessage: 'Scan this QR code to add these account details',
              qrDescription: 'Let someone scan this QR to add these accounts.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Share Quick Access Accounts'), findsOneWidget);
      expect(find.text('Your contacts'), findsOneWidget);

      final accountTiles = tester
          .widgetList<CheckboxListTile>(
            find.byType(CheckboxListTile, skipOffstage: false),
          )
          .toList(growable: false);

      expect(accountTiles, hasLength(2));
      final accountNumbersByHolder = <String?, String?>{
        for (final tile in accountTiles)
          (tile.title! as Text).data: (tile.subtitle! as Text).data,
      };
      expect(accountNumbersByHolder['Almaz'], '1000123456789');
      expect(accountNumbersByHolder['Bekele'], '2000987654321');

      final qrCode = tester.widget<AccountShareQrCode>(
        find.byType(AccountShareQrCode),
      );
      final payload = AccountSharePayload.decode(qrCode.data);

      expect(payload, isNotNull);
      expect(payload!.name, 'Your contacts');
      expect(payload.accounts, hasLength(2));
      expect(
        payload.accounts.map((account) => account.name),
        containsAll(<String?>['Almaz', 'Bekele']),
      );
      expect(payload.name, isNot('Device Owner'));
    },
  );

  testWidgets(
    'your-accounts rows show the holder before the account number',
    (tester) async {
      final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
      addTearDown(themeProvider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: const MaterialApp(
            home: AccountShareQrPage(
              initialAccounts: <AccountShareEntry>[
                AccountShareEntry(
                  bankId: 1,
                  accountNumber: '1000123456789',
                  name: 'Marta',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final accountTile = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile, skipOffstage: false),
      );

      expect((accountTile.title! as Text).data, 'Marta');
      expect((accountTile.subtitle! as Text).data, '1000123456789');
    },
  );
}
