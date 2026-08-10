import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/services/notification_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('weekly summaries are enabled by default', () async {
    expect(
      await NotificationSettingsService.instance.isWeeklySummaryEnabled(),
      isTrue,
    );
  });

  test('an explicit weekly summary preference is respected', () async {
    await NotificationSettingsService.instance.setWeeklySummaryEnabled(false);

    expect(
      await NotificationSettingsService.instance.isWeeklySummaryEnabled(),
      isFalse,
    );
  });
}
