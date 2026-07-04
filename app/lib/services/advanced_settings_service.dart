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

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileDoubleTapActionKey);
    profileDoubleTapAction.value = _fromStorage(raw);
    toolsFabItems.value =
        _toolsFabItemsFromStorage(prefs.getStringList(_toolsFabItemsKey));
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
    final normalized = _normalizeToolsFabItems(items);
    if (setEquals(toolsFabItems.value, normalized)) return;
    toolsFabItems.value = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _toolsFabItemsKey,
      normalized.map(_toolsFabItemToStorage).toList(growable: false),
    );
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

  static Set<ToolsFabItem> _toolsFabItemsFromStorage(List<String>? raw) {
    if (raw == null || raw.isEmpty) return defaultToolsFabItems;
    return _normalizeToolsFabItems(
      raw.map(_toolsFabItemFromStorage).whereType<ToolsFabItem>().toSet(),
    );
  }

  static Set<ToolsFabItem> _normalizeToolsFabItems(Set<ToolsFabItem> items) {
    if (items.isEmpty) return defaultToolsFabItems;
    final ordered = <ToolsFabItem>{};
    for (final item in ToolsFabItem.values) {
      if (items.contains(item)) ordered.add(item);
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
      case ToolsFabItem.failedParsings:
        return 'failed_parsings';
      case ToolsFabItem.dataSync:
        return 'data_sync';
      case ToolsFabItem.webDashboard:
        return 'web_dashboard';
    }
  }
}
