import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeModePreference {
  AppThemeModePreference._();

  static const String preferenceKey = 'theme_mode';

  static Future<ThemeMode> load() async {
    final preferences = await SharedPreferences.getInstance();
    return fromStorageValue(preferences.getString(preferenceKey));
  }

  static Future<void> save(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(preferenceKey, mode.toString());
  }

  static ThemeMode fromStorageValue(String? value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.toString() == value,
      orElse: () => ThemeMode.system,
    );
  }
}
