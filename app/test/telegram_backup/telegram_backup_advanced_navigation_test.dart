import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/screens/advanced_settings_page.dart';
import 'package:totals/_redesign/screens/telegram_backup_consent_page.dart';
import 'package:totals/_redesign/screens/telegram_backup_page.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/services/advanced_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildHarness() {
    return ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: const MaterialApp(
        home: RedesignAdvancedSettingsPage(),
      ),
    );
  }

  testWidgets('Telegram Backup stays disabled when consent is cancelled',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AdvancedSettingsService.instance.reload();

    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Telegram Backup'));
    await tester.pumpAndSettle();

    expect(find.byType(TelegramBackupConsentPage), findsOneWidget);
    expect(
      AdvancedSettingsService.instance.telegramBackupEnabled.value,
      isFalse,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(TelegramBackupConsentPage), findsNothing);
    expect(
      AdvancedSettingsService.instance.telegramBackupEnabled.value,
      isFalse,
    );
  });

  testWidgets('previous consent does not skip the tutorial when re-enabling',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'advanced_telegram_backup_enabled': false,
      'advanced_telegram_backup_consent_version':
          AdvancedSettingsService.currentTelegramBackupConsentVersion,
    });
    await AdvancedSettingsService.instance.reload();

    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(
      AdvancedSettingsService.instance.hasTelegramBackupConsent,
      isTrue,
    );
    await tester.tap(find.text('Telegram Backup'));
    await tester.pumpAndSettle();

    expect(find.byType(TelegramBackupConsentPage), findsOneWidget);
    expect(
      AdvancedSettingsService.instance.telegramBackupEnabled.value,
      isFalse,
    );
  });

  testWidgets('accepting consent enables Telegram Backup and opens setup',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AdvancedSettingsService.instance.reload();

    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Telegram Backup'));
    await tester.pumpAndSettle();

    expect(find.text('Enable Telegram Backup'), findsOneWidget);
    expect(find.text('Your full backup is included'), findsOneWidget);
    expect(find.textContaining('original source SMS'), findsOneWidget);
    final enableButton = find.widgetWithText(
      ElevatedButton,
      'I understand — enable',
    );
    expect(
      tester.widget<ElevatedButton>(enableButton).onPressed,
      isNull,
    );

    await tester.scrollUntilVisible(find.byType(Checkbox), 250);
    expect(
      find.text(
        'I understand that my encrypted Totals backup will be sent to Telegram.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('retained SMS content'), findsNothing);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(enableButton).onPressed,
      isNotNull,
    );

    await tester.tap(enableButton);
    await tester.pumpAndSettle();

    expect(find.byType(TelegramBackupConsentPage), findsNothing);
    expect(find.byType(TelegramBackupPage), findsOneWidget);
    expect(
      AdvancedSettingsService.instance.telegramBackupEnabled.value,
      isTrue,
    );
    expect(
      AdvancedSettingsService.instance.hasTelegramBackupConsent,
      isTrue,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt('advanced_telegram_backup_consent_version'),
      AdvancedSettingsService.currentTelegramBackupConsentVersion,
    );
  });

  testWidgets('enabled Telegram Backup card opens its backup page',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'advanced_telegram_backup_enabled': true,
    });
    await AdvancedSettingsService.instance.reload();

    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(
      AdvancedSettingsService.instance.telegramBackupEnabled.value,
      isTrue,
    );

    await tester.tap(find.text('Telegram Backup'));
    await tester.pumpAndSettle();

    expect(find.byType(TelegramBackupPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Telegram Backup setup presents BotFather as a link',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'advanced_telegram_backup_enabled': true,
    });
    await AdvancedSettingsService.instance.reload();

    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Telegram Backup'));
    await tester.pumpAndSettle();

    final botFatherLink = find.byKey(
      const Key('telegram-backup-botfather-link'),
    );
    expect(botFatherLink, findsOneWidget);
    expect(tester.widget<InkWell>(botFatherLink).onTap, isNotNull);
  });
}
