import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/services/telegram_backup/telegram_backup_models.dart';

class TelegramBackupSettingsService {
  TelegramBackupSettingsService._();

  static final TelegramBackupSettingsService instance =
      TelegramBackupSettingsService._();

  static const String _configKey = 'telegram_backup_config_v1';
  static const String _tokenKey = 'telegram_backup_bot_token_v1';
  static const String _recoveryKey = 'telegram_backup_recovery_key_v1';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ValueNotifier<TelegramBackupConfig?> config =
      ValueNotifier<TelegramBackupConfig?>(null);

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await reload();
  }

  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    config.value = _decodeConfig(prefs.getString(_configKey));
    _loaded = true;
  }

  Future<void> saveConnection({
    required TelegramBackupConfig config,
    required String token,
    required String recoveryKey,
  }) async {
    await saveCredentials(token: token, recoveryKey: recoveryKey);
    await _writeConfig(config);
  }

  Future<void> saveCredentials({
    required String token,
    required String recoveryKey,
  }) async {
    await _secureStorage.write(key: _tokenKey, value: token.trim());
    await _secureStorage.write(
      key: _recoveryKey,
      value: recoveryKey.trim(),
    );
  }

  Future<String?> readToken() async {
    final value = await _secureStorage.read(key: _tokenKey);
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<String?> readRecoveryKey() async {
    final value = await _secureStorage.read(key: _recoveryKey);
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setSchedule(TelegramBackupSchedule schedule) async {
    await reload();
    final current = config.value;
    if (current == null || current.schedule == schedule) return;
    await _writeConfig(
      current.copyWith(
        schedule: schedule,
        scheduleAnchorAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<TelegramBackupConfig?> ensureScheduleAnchor({DateTime? now}) async {
    await reload();
    final current = config.value;
    if (current == null || current.scheduleAnchorAt != null) return current;
    final anchored = current.copyWith(
      scheduleAnchorAt: current.lastBackupAt ?? (now ?? DateTime.now()).toUtc(),
    );
    await _writeConfig(anchored);
    return anchored;
  }

  Future<void> recordBackupSuccess({
    required DateTime completedAt,
    required int catalogMessageId,
  }) async {
    await reload();
    final current = config.value;
    if (current == null) return;
    await _writeConfig(
      current.copyWith(
        catalogMessageId: catalogMessageId,
        lastBackupAt: completedAt.toUtc(),
        clearLastBackupError: true,
      ),
    );
  }

  Future<void> recordBackupFailure(String message) async {
    await reload();
    final current = config.value;
    if (current == null) return;
    await _writeConfig(
      current.copyWith(lastBackupError: _safeError(message)),
    );
  }

  Future<void> updateCatalogMessageId(int messageId) async {
    await reload();
    final current = config.value;
    if (current == null || current.catalogMessageId == messageId) return;
    await _writeConfig(current.copyWith(catalogMessageId: messageId));
  }

  Future<void> disconnect() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _recoveryKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configKey);
    config.value = null;
    _loaded = true;
  }

  Future<void> _writeConfig(TelegramBackupConfig value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(value.toJson()));
    config.value = value;
    _loaded = true;
  }

  static TelegramBackupConfig? _decodeConfig(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final value = TelegramBackupConfig.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return value.isConfigured ? value : null;
    } catch (_) {
      return null;
    }
  }

  static String _safeError(String message) {
    final output = StringBuffer();
    var lastWasWhitespace = false;
    for (final code in message.trim().codeUnits) {
      final whitespace = code <= 32;
      if (whitespace) {
        if (!lastWasWhitespace) output.write(' ');
      } else {
        output.writeCharCode(code);
      }
      lastWasWhitespace = whitespace;
    }
    final normalized = output.toString();
    if (normalized.length <= 240) return normalized;
    return '${normalized.substring(0, 237)}...';
  }
}
