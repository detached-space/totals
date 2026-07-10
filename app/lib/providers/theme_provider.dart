import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/theme/app_font_option.dart';
import 'package:totals/theme/app_calendar_option.dart';
import 'package:totals/theme/app_language_option.dart';
import 'package:totals/theme/app_theme_mode_preference.dart';
import 'package:totals/services/widget_service.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _uiScaleKey = 'ui_scale';
  static const String _appTopPaddingKey = 'app_top_padding';
  static const String _appFontKey = 'app_font';
  static const String _appCalendarKey = 'app_calendar';
  static const String _appLanguageKey = 'app_language';
  static const double _defaultUiScale = 0.9;
  static const double _defaultAppTopPadding = 20.0;
  static const List<ThemeMode> _themeCycleOrder = <ThemeMode>[
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];
  static const List<double> _uiScaleOptions = <double>[
    0.5,
    0.6,
    0.7,
    0.75,
    0.8,
    0.85,
    0.9,
    0.95,
    1.0,
    1.1,
    1.25,
    1.5,
  ];
  static const List<double> _appTopPaddingOptions = <double>[
    0,
    8,
    12,
    16,
    20,
    24,
    32,
  ];
  ThemeMode _themeMode = ThemeMode.system;
  double _uiScale = _defaultUiScale;
  double _appTopPadding = _defaultAppTopPadding;
  AppFontOption _appFont = AppFontOption.appDefault;
  AppLanguageOption _appLanguage = AppLanguageOption.english;
  AppCalendarOption _appCalendar = AppCalendarOption.gregorian;

  ThemeMode get themeMode => _themeMode;
  double get uiScale => _uiScale;
  double get appTopPadding => _appTopPadding;
  AppFontOption get appFont => _appFont;
  AppLanguageOption get appLanguage => _appLanguage;
  Locale get appLocale => _appLanguage.locale;
  AppCalendarOption get appCalendar => _appCalendar;
  List<double> get availableUiScales =>
      List<double>.unmodifiable(_uiScaleOptions);
  List<double> get availableAppTopPaddings =>
      List<double>.unmodifiable(_appTopPaddingOptions);
  List<AppFontOption> get availableAppFonts =>
      List<AppFontOption>.unmodifiable(AppFontOption.values);
  List<AppLanguageOption> get availableAppLanguages =>
      List<AppLanguageOption>.unmodifiable(AppLanguageOption.values);
  List<AppCalendarOption> get availableAppCalendars =>
      List<AppCalendarOption>.unmodifiable(AppCalendarOption.values);
  String get uiScaleLabel => _formatUiScale(_uiScale);
  String get appTopPaddingLabel => _formatPixels(_appTopPadding);
  String get appFontLabel => _appFont.label;
  String get appLanguageLabel => _appLanguage.nativeLabel;
  String get appCalendarLabel => appCalendar.label;
  bool get isZoomedOut => (_uiScale - 0.75).abs() < 0.001;
  String get themeModeLabel {
    switch (_themeMode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  ThemeProvider() {
    _loadThemeMode();
    _loadUiScale();
    _loadAppTopPadding();
    _loadAppFont();
    _loadAppCalendar();
    _loadAppLanguage();
  }

  Future<void> _loadThemeMode() async {
    final savedTheme = await AppThemeModePreference.load();
    if (_themeMode != savedTheme) {
      _themeMode = savedTheme;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    // Defer notification to the next frame so any in-progress build/animation
    // (e.g. overlay entries from bottom sheets) finishes first. This prevents
    // InheritedElement ancestor-chain assertions during heavy tree rebuilds.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
    await AppThemeModePreference.save(mode);
  }

  Future<void> _loadUiScale() async {
    final prefs = await SharedPreferences.getInstance();
    final savedScale = prefs.getDouble(_uiScaleKey);
    if (savedScale != null) {
      _uiScale = _normalizeUiScale(savedScale);
      notifyListeners();
    }
  }

  Future<void> setUiScale(double scale) async {
    final normalized = _normalizeUiScale(scale);
    _uiScale = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_uiScaleKey, normalized);
  }

  Future<void> _loadAppTopPadding() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPadding = prefs.getDouble(_appTopPaddingKey);
    if (savedPadding != null) {
      _appTopPadding = _normalizeAppTopPadding(savedPadding);
      notifyListeners();
    }
  }

  Future<void> setAppTopPadding(double padding) async {
    final normalized = _normalizeAppTopPadding(padding);
    _appTopPadding = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_appTopPaddingKey, normalized);
  }

  Future<void> _loadAppFont() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFont = prefs.getString(_appFontKey);
    final resolvedFont = AppFontOption.fromStorage(savedFont);
    if (_appFont == resolvedFont) return;
    _appFont = resolvedFont;
    notifyListeners();
  }

  Future<void> setAppFont(AppFontOption font) async {
    if (_appFont == font) return;
    _appFont = font;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appFontKey, font.storageValue);
  }

  Future<void> _loadAppLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(_appLanguageKey);
    final savedCalendar = prefs.getString(_appCalendarKey);
    final resolvedLanguage = AppLanguageOption.fromStorage(savedLanguage);
    if (_appLanguage == resolvedLanguage) return;
    _appLanguage = resolvedLanguage;
    if (savedCalendar == null) {
      _appCalendar = resolvedLanguage.defaultCalendar;
    }
    notifyListeners();
  }

  Future<void> setAppLanguage(AppLanguageOption language) async {
    if (_appLanguage == language) return;
    _appLanguage = language;
    _appCalendar = language.defaultCalendar;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appLanguageKey, language.storageValue);
    await prefs.setString(_appCalendarKey, _appCalendar.storageValue);
    await _refreshBudgetWidgetForCalendar();
  }

  Future<void> _loadAppCalendar() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCalendar = prefs.getString(_appCalendarKey);
    final resolvedCalendar = AppCalendarOption.fromStorage(savedCalendar);
    if (_appCalendar == resolvedCalendar) return;
    _appCalendar = resolvedCalendar;
    notifyListeners();
  }

  Future<void> setAppCalendar(AppCalendarOption calendar) async {
    if (_appCalendar == calendar) return;
    _appCalendar = calendar;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appCalendarKey, calendar.storageValue);
    await _refreshBudgetWidgetForCalendar();
  }

  Future<void> setZoomedOut(bool value) async {
    await setUiScale(value ? 0.75 : _defaultUiScale);
  }

  double _normalizeUiScale(double value) {
    return _normalizeNearestValue(
      value: value,
      options: _uiScaleOptions,
      fallback: _defaultUiScale,
    );
  }

  double _normalizeAppTopPadding(double value) {
    return _normalizeNearestValue(
      value: value,
      options: _appTopPaddingOptions,
      fallback: _defaultAppTopPadding,
    );
  }

  double _normalizeNearestValue({
    required double value,
    required List<double> options,
    required double fallback,
  }) {
    if (value < 0) return fallback;
    double nearest = options.first;
    double nearestDelta = (value - nearest).abs();
    for (final option in options.skip(1)) {
      final delta = (value - option).abs();
      if (delta < nearestDelta) {
        nearest = option;
        nearestDelta = delta;
      }
    }
    return nearest;
  }

  String _formatUiScale(double value) {
    final formatted = value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '${formatted}x';
  }

  String _formatPixels(double value) {
    final formatted = value
        .toStringAsFixed(1)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '${formatted}px';
  }

  void toggleTheme() {
    if (_themeMode == ThemeMode.light) {
      setThemeMode(ThemeMode.dark);
      return;
    }
    if (_themeMode == ThemeMode.dark) {
      setThemeMode(ThemeMode.light);
      return;
    }
    setThemeMode(ThemeMode.dark);
  }

  void cycleThemeMode() {
    final currentIndex = _themeCycleOrder.indexOf(_themeMode);
    final safeIndex = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (safeIndex + 1) % _themeCycleOrder.length;
    setThemeMode(_themeCycleOrder[nextIndex]);
  }

  Future<void> _refreshBudgetWidgetForCalendar() async {
    try {
      await WidgetService.refreshBudgetWidget(
        calendar: _appCalendar.storageValue,
      );
    } catch (_) {}
  }
}
