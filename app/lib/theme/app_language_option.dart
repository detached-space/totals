import 'package:flutter/widgets.dart';
import 'package:totals/theme/app_calendar_option.dart';

enum AppLanguageOption {
  english(
    storageValue: 'en',
    label: 'English',
    nativeLabel: 'English',
    locale: Locale('en'),
  ),
  amharic(
    storageValue: 'am',
    label: 'Amharic',
    nativeLabel: 'አማርኛ',
    locale: Locale('am'),
  );

  const AppLanguageOption({
    required this.storageValue,
    required this.label,
    required this.nativeLabel,
    required this.locale,
  });

  final String storageValue;
  final String label;
  final String nativeLabel;
  final Locale locale;

  AppCalendarOption get defaultCalendar => this == AppLanguageOption.amharic
      ? AppCalendarOption.ethiopian
      : AppCalendarOption.gregorian;

  static AppLanguageOption fromStorage(String? value) {
    for (final option in AppLanguageOption.values) {
      if (option.storageValue == value) {
        return option;
      }
    }
    return AppLanguageOption.english;
  }
}
