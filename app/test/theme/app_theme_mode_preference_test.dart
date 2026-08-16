import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/theme/app_theme_mode_preference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads each persisted theme mode', () async {
    for (final themeMode in ThemeMode.values) {
      SharedPreferences.setMockInitialValues({
        AppThemeModePreference.preferenceKey: themeMode.toString(),
      });

      expect(await AppThemeModePreference.load(), themeMode);
    }
  });

  test('falls back to the system theme for missing or invalid values', () {
    expect(
      AppThemeModePreference.fromStorageValue(null),
      ThemeMode.system,
    );
    expect(
      AppThemeModePreference.fromStorageValue('not-a-theme'),
      ThemeMode.system,
    );
  });

  test('ThemeProvider keeps the theme resolved during bootstrap', () async {
    SharedPreferences.setMockInitialValues({
      AppThemeModePreference.preferenceKey: ThemeMode.light.toString(),
    });

    final provider = ThemeProvider(initialThemeMode: ThemeMode.dark);
    addTearDown(provider.dispose);

    await Future<void>.delayed(Duration.zero);

    expect(provider.themeMode, ThemeMode.dark);
  });
}
