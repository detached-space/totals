import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the Data Sync master toggle + consent state, backed by
/// [SharedPreferences]. Mirrors the singleton + [ValueNotifier] pattern of
/// `AdvancedSettingsService`.
///
/// [cachedEnabled] is a process-wide synchronous hint used by the enqueuer on
/// the hot write path so that, when the feature is off (the default), a write
/// costs a single bool check instead of any database work. It is populated on
/// load and on every toggle; the background isolate populates it lazily.
class DataSyncSettingsService {
  DataSyncSettingsService._();
  static final DataSyncSettingsService instance = DataSyncSettingsService._();

  static const String _masterEnabledKey = 'data_sync_master_enabled';
  static const String _consentVersionKey = 'data_sync_consent_version';

  /// Bump when the consent copy materially changes to force re-consent.
  static const int currentConsentVersion = 1;

  /// Synchronous, process-wide hint. Null = not yet known in this isolate.
  static bool? cachedEnabled;

  final ValueNotifier<bool> masterEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<int> consentVersion = ValueNotifier<int>(0);

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_masterEnabledKey) ?? false;
    masterEnabled.value = enabled;
    cachedEnabled = enabled;
    consentVersion.value = prefs.getInt(_consentVersionKey) ?? 0;
    _loaded = true;
  }

  bool get hasConsent => consentVersion.value >= currentConsentVersion;

  Future<void> recordConsent() async {
    await ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_consentVersionKey, currentConsentVersion);
    consentVersion.value = currentConsentVersion;
  }

  Future<void> setMasterEnabled(bool value) async {
    await ensureLoaded();
    masterEnabled.value = value;
    cachedEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_masterEnabledKey, value);
  }

  /// Read the master flag without the in-memory notifier (used by isolates that
  /// don't run [ensureLoaded]). Caches the result into [cachedEnabled].
  static Future<bool> readEnabledFromPrefs() async {
    final cached = cachedEnabled;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_masterEnabledKey) ?? false;
    cachedEnabled = value;
    return value;
  }
}
