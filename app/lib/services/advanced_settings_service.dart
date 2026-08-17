import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ProfileDoubleTapAction {
  lock,
  doNothing,
}

enum ToolsFabItem {
  quickAccounts,
  verifyPayments,
  loans,
  spendingMap,
  failedParsings,
  dataSync,
  webDashboard,
}

class AdvancedSettingsService {
  AdvancedSettingsService._();

  static final AdvancedSettingsService instance = AdvancedSettingsService._();

  static const String _profileDoubleTapActionKey =
      'redesign_profile_double_tap_action';
  static const String _toolsFabItemsKey = 'redesign_tools_fab_items';
  static const String _telegramBackupEnabledKey =
      'advanced_telegram_backup_enabled';
  static const String _telegramBackupConsentVersionKey =
      'advanced_telegram_backup_consent_version';
  static const String _spendingMapEnabledKey = 'advanced_spending_map_enabled';
  static const int currentTelegramBackupConsentVersion = 1;
  static const Set<ToolsFabItem> defaultToolsFabItems = {
    ToolsFabItem.quickAccounts,
    ToolsFabItem.verifyPayments,
    ToolsFabItem.loans,
    ToolsFabItem.failedParsings,
    ToolsFabItem.webDashboard,
  };

  final ValueNotifier<ProfileDoubleTapAction> profileDoubleTapAction =
      ValueNotifier<ProfileDoubleTapAction>(ProfileDoubleTapAction.lock);
  final ValueNotifier<Set<ToolsFabItem>> toolsFabItems =
      ValueNotifier<Set<ToolsFabItem>>(defaultToolsFabItems);
  final ValueNotifier<bool> telegramBackupEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<int> telegramBackupConsentVersion = ValueNotifier<int>(0);
  final ValueNotifier<bool> spendingMapEnabled = ValueNotifier<bool>(false);

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await reload();
  }

  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_profileDoubleTapActionKey);
    profileDoubleTapAction.value = _fromStorage(raw);
    spendingMapEnabled.value = prefs.getBool(_spendingMapEnabledKey) ?? false;
    toolsFabItems.value = _toolsFabItemsFromStorage(
      prefs.getStringList(_toolsFabItemsKey),
      spendingMapEnabled: spendingMapEnabled.value,
    );
    telegramBackupEnabled.value =
        prefs.getBool(_telegramBackupEnabledKey) ?? false;
    telegramBackupConsentVersion.value =
        prefs.getInt(_telegramBackupConsentVersionKey) ?? 0;
    _loaded = true;
  }

  Future<void> setProfileDoubleTapAction(ProfileDoubleTapAction action) async {
    await ensureLoaded();
    if (profileDoubleTapAction.value == action) return;
    profileDoubleTapAction.value = action;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileDoubleTapActionKey, _toStorage(action));
  }

  Future<void> setToolsFabItems(Set<ToolsFabItem> items) async {
    await ensureLoaded();
    final normalized = _normalizeToolsFabItems(
      items,
      spendingMapEnabled: spendingMapEnabled.value,
    );
    if (setEquals(toolsFabItems.value, normalized)) return;
    toolsFabItems.value = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _toolsFabItemsKey,
      normalized.map(_toolsFabItemToStorage).toList(growable: false),
    );
  }

  Future<void> setSpendingMapEnabled(bool enabled) async {
    await ensureLoaded();
    if (spendingMapEnabled.value == enabled) return;

    spendingMapEnabled.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_spendingMapEnabledKey, enabled);

    final updatedTools = Set<ToolsFabItem>.of(toolsFabItems.value);
    if (enabled) {
      updatedTools.add(ToolsFabItem.spendingMap);
    } else {
      updatedTools.remove(ToolsFabItem.spendingMap);
    }
    final normalized = _normalizeToolsFabItems(
      updatedTools,
      spendingMapEnabled: enabled,
    );
    toolsFabItems.value = normalized;
    await prefs.setStringList(
      _toolsFabItemsKey,
      normalized.map(_toolsFabItemToStorage).toList(growable: false),
    );
  }

  List<ToolsFabItem> get availableToolsFabItems => ToolsFabItem.values
      .where(
        (item) => item != ToolsFabItem.spendingMap || spendingMapEnabled.value,
      )
      .toList(growable: false);

  Future<void> setTelegramBackupEnabled(bool enabled) async {
    await ensureLoaded();
    if (telegramBackupEnabled.value == enabled) return;
    if (enabled && !hasTelegramBackupConsent) {
      throw StateError(
        'Telegram Backup cannot be enabled before consent is recorded.',
      );
    }
    telegramBackupEnabled.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_telegramBackupEnabledKey, enabled);
  }

  bool get hasTelegramBackupConsent =>
      telegramBackupConsentVersion.value >= currentTelegramBackupConsentVersion;

  Future<void> recordTelegramBackupConsent() async {
    await ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _telegramBackupConsentVersionKey,
      currentTelegramBackupConsentVersion,
    );
    telegramBackupConsentVersion.value = currentTelegramBackupConsentVersion;
  }

  static ProfileDoubleTapAction _fromStorage(String? raw) {
    switch (raw) {
      case 'do_nothing':
        return ProfileDoubleTapAction.doNothing;
      case 'lock':
      default:
        return ProfileDoubleTapAction.lock;
    }
  }

  static String _toStorage(ProfileDoubleTapAction action) {
    switch (action) {
      case ProfileDoubleTapAction.lock:
        return 'lock';
      case ProfileDoubleTapAction.doNothing:
        return 'do_nothing';
    }
  }

  static Set<ToolsFabItem> _toolsFabItemsFromStorage(
    List<String>? raw, {
    required bool spendingMapEnabled,
  }) {
    if (raw == null || raw.isEmpty) {
      return _normalizeToolsFabItems(
        defaultToolsFabItems,
        spendingMapEnabled: spendingMapEnabled,
      );
    }
    return _normalizeToolsFabItems(
      raw.map(_toolsFabItemFromStorage).whereType<ToolsFabItem>().toSet(),
      spendingMapEnabled: spendingMapEnabled,
    );
  }

  static Set<ToolsFabItem> _normalizeToolsFabItems(
    Set<ToolsFabItem> items, {
    required bool spendingMapEnabled,
  }) {
    final requested = Set<ToolsFabItem>.of(
      items.isEmpty ? defaultToolsFabItems : items,
    );
    if (spendingMapEnabled) {
      requested.add(ToolsFabItem.spendingMap);
    } else {
      requested.remove(ToolsFabItem.spendingMap);
    }
    final ordered = <ToolsFabItem>{};
    for (final item in ToolsFabItem.values) {
      if (requested.contains(item)) ordered.add(item);
    }
    return Set.unmodifiable(ordered.isEmpty ? defaultToolsFabItems : ordered);
  }

  static ToolsFabItem? _toolsFabItemFromStorage(String raw) {
    switch (raw) {
      case 'quick_accounts':
        return ToolsFabItem.quickAccounts;
      case 'verify_payments':
        return ToolsFabItem.verifyPayments;
      case 'loans':
        return ToolsFabItem.loans;
      case 'spending_map':
        return ToolsFabItem.spendingMap;
      case 'failed_parsings':
        return ToolsFabItem.failedParsings;
      case 'data_sync':
        return ToolsFabItem.dataSync;
      case 'web_dashboard':
        return ToolsFabItem.webDashboard;
    }
    return null;
  }

  static String _toolsFabItemToStorage(ToolsFabItem item) {
    switch (item) {
      case ToolsFabItem.quickAccounts:
        return 'quick_accounts';
      case ToolsFabItem.verifyPayments:
        return 'verify_payments';
      case ToolsFabItem.loans:
        return 'loans';
      case ToolsFabItem.spendingMap:
        return 'spending_map';
      case ToolsFabItem.failedParsings:
        return 'failed_parsings';
      case ToolsFabItem.dataSync:
        return 'data_sync';
      case ToolsFabItem.webDashboard:
        return 'web_dashboard';
    }
  }
}
