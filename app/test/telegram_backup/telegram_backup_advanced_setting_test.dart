import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/services/advanced_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Telegram Backup advanced gate is off by default and persists',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = AdvancedSettingsService.instance;

    await service.ensureLoaded();
    expect(service.telegramBackupEnabled.value, isFalse);
    expect(service.hasTelegramBackupConsent, isFalse);

    await expectLater(
      service.setTelegramBackupEnabled(true),
      throwsA(isA<StateError>()),
    );
    await service.recordTelegramBackupConsent();
    await service.setTelegramBackupEnabled(true);

    final prefs = await SharedPreferences.getInstance();
    expect(service.hasTelegramBackupConsent, isTrue);
    expect(
      prefs.getInt('advanced_telegram_backup_consent_version'),
      AdvancedSettingsService.currentTelegramBackupConsentVersion,
    );
    expect(service.telegramBackupEnabled.value, isTrue);
    expect(prefs.getBool('advanced_telegram_backup_enabled'), isTrue);
  });
}
