import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:totals/repositories/runtime_lock_repository.dart';
import 'package:totals/services/advanced_settings_service.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/telegram_backup/telegram_backup_crypto.dart';
import 'package:totals/services/telegram_backup/telegram_backup_models.dart';
import 'package:totals/services/telegram_backup/telegram_backup_schedule.dart';
import 'package:totals/services/telegram_backup/telegram_backup_settings_service.dart';
import 'package:totals/services/telegram_backup/telegram_bot_api.dart';
import 'package:uuid/uuid.dart';

typedef TelegramBotApiFactory = TelegramBotApi Function(String token);

enum TelegramBackupAttemptResult {
  skipped,
  succeeded,
  retry,
}

class TelegramBackupException implements Exception {
  final String message;

  const TelegramBackupException(this.message);

  @override
  String toString() => message;
}

class TelegramRecoveryKeyRequiredException extends TelegramBackupException {
  const TelegramRecoveryKeyRequiredException()
      : super(
          'This chat already has Totals backups. Enter the recovery key to '
          'connect without replacing them.',
        );
}

class TelegramRecoveryKeyInvalidException extends TelegramBackupException {
  const TelegramRecoveryKeyInvalidException(String message) : super(message);
}

class TelegramBackupService {
  TelegramBackupService({
    TelegramBackupSettingsService? settings,
    TelegramBackupCrypto? crypto,
    DataExportImportService? exportImportService,
    TelegramBotApiFactory? apiFactory,
    RuntimeLockRepository? runtimeLocks,
  })  : _settings = settings ?? TelegramBackupSettingsService.instance,
        _crypto = crypto ?? TelegramBackupCrypto(),
        _exportImportService = exportImportService ?? DataExportImportService(),
        _apiFactory = apiFactory ?? ((token) => TelegramBotApi(token: token)),
        _runtimeLocks = runtimeLocks ?? RuntimeLockRepository();

  static final TelegramBackupService instance = TelegramBackupService();

  static const String catalogFileName = 'totals_backup_index.totals';
  static const int maximumInAppBackupBytes = TelegramBotApi.maxDownloadBytes;

  final TelegramBackupSettingsService _settings;
  final TelegramBackupCrypto _crypto;
  final DataExportImportService _exportImportService;
  final TelegramBotApiFactory _apiFactory;
  final RuntimeLockRepository _runtimeLocks;
  final Random _random = Random.secure();
  final Uuid _uuid = const Uuid();

  static const String _runtimeLockName = 'telegram_backup';
  static const Duration _runtimeLockTtl = Duration(minutes: 15);

  static const String _pairingConfirmationMessage = '✅ Telegram is ready\n\n'
      "You're all set here. Return to Totals to finish setting up your "
      'encrypted backups.';
  static const String _pendingBackupMessage =
      'Preparing encrypted Totals backup…';

  Future<void> _operationQueue = Future<void>.value();

  Future<TelegramPairingSession> beginPairing(String token) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty || !normalizedToken.contains(':')) {
      throw const TelegramBackupException(
        'Paste the complete bot token from BotFather.',
      );
    }
    final api = _apiFactory(normalizedToken);
    try {
      final bot = await api.getMe();
      final webhookUrl = await api.getWebhookUrl();
      if (webhookUrl.isNotEmpty) {
        throw const TelegramBackupException(
          'This bot is connected to another service through a webhook. '
          'Use a new private bot for Totals.',
        );
      }
      return TelegramPairingSession(
        token: normalizedToken,
        nonce: _randomHex(16),
        bot: bot,
      );
    } on TelegramBackupException {
      rethrow;
    } on TelegramBotApiException catch (error) {
      throw TelegramBackupException(_friendlyApiError(error));
    } finally {
      api.close();
    }
  }

  Future<TelegramChatIdentity> waitForPairing(
    TelegramPairingSession session, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final api = _apiFactory(session.token);
    final deadline = DateTime.now().add(timeout);
    int? offset;
    final expectedParameter = 'totals_${session.nonce}';

    try {
      while (DateTime.now().isBefore(deadline)) {
        final updates = await api.getUpdates(
          offset: offset,
          timeoutSeconds: 8,
        );
        for (final update in updates) {
          final updateId = (update['update_id'] as num?)?.toInt();
          if (updateId != null && (offset == null || updateId >= offset)) {
            offset = updateId + 1;
          }
          final rawMessage = update['message'];
          if (rawMessage is! Map) continue;
          final message = Map<String, dynamic>.from(rawMessage);
          final text = (message['text'] as String?)?.trim() ?? '';
          final commandParts =
              text.split(' ').where((part) => part.isNotEmpty).toList();
          if (commandParts.length != 2 ||
              commandParts.first.split('@').first.toLowerCase() != '/start' ||
              commandParts.last != expectedParameter) {
            continue;
          }

          final rawChat = message['chat'];
          if (rawChat is! Map) continue;
          final chat = Map<String, dynamic>.from(rawChat);
          if (chat['type'] != 'private') continue;
          final id = '${chat['id']}';
          if (id.isEmpty || id == 'null') continue;
          final firstName = (chat['first_name'] as String?)?.trim() ?? '';
          final lastName = (chat['last_name'] as String?)?.trim() ?? '';
          final username = (chat['username'] as String?)?.trim();
          final fullName =
              [firstName, lastName].where((part) => part.isNotEmpty).join(' ');
          try {
            await api.sendMessage(
              chatId: id,
              text: _pairingConfirmationMessage,
            );
          } on TelegramBotApiException {
            // The chat is already verified. A failed UX acknowledgement must
            // not force the user to repeat pairing.
          }
          return TelegramChatIdentity(
            id: id,
            displayName: fullName.isNotEmpty
                ? fullName
                : username?.isNotEmpty == true
                    ? '@$username'
                    : 'Private Telegram chat',
            username: username?.isEmpty == true ? null : username,
          );
        }
      }
      throw const TelegramBackupException(
        'No matching Start message arrived. Open the bot from Totals, tap '
        'Start, then try again.',
      );
    } on TelegramBackupException {
      rethrow;
    } on TelegramBotApiException catch (error) {
      throw TelegramBackupException(_friendlyApiError(error));
    } finally {
      api.close();
    }
  }

  Future<TelegramConnectionResult> finishPairing({
    required TelegramPairingSession session,
    required TelegramChatIdentity chat,
    String? recoveryKey,
  }) async {
    final api = _apiFactory(session.token);
    try {
      final chatInfo = await api.getChat(chat.id);
      final existing = _pinnedCatalogDocument(chatInfo);
      final hasDifferentPinnedMessage =
          existing == null && chatInfo['pinned_message'] is Map;

      late final String normalizedKey;
      late final int catalogMessageId;
      late final bool createdNewCatalog;
      var recoveredDraftKey = false;

      if (existing != null) {
        final suppliedKey =
            recoveryKey?.trim().isNotEmpty == true ? recoveryKey!.trim() : null;
        final candidateKey = suppliedKey ?? await _settings.readRecoveryKey();
        recoveredDraftKey = suppliedKey == null && candidateKey != null;
        if (candidateKey == null || candidateKey.isEmpty) {
          throw const TelegramRecoveryKeyRequiredException();
        }
        normalizedKey = _crypto.normalizeRecoveryKey(candidateKey);
        final catalog = await _downloadCatalog(
          api: api,
          document: existing,
          recoveryKey: normalizedKey,
          expectedChatId: chat.id,
        );
        if (catalog.chatId != chat.id) {
          throw const TelegramBackupException(
            'The pinned Totals catalog belongs to a different Telegram chat.',
          );
        }
        catalogMessageId = existing.messageId;
        createdNewCatalog = false;
      } else {
        if (hasDifferentPinnedMessage) {
          throw const TelegramBackupException(
            'This chat has a different pinned message. Re-pin '
            'totals_backup_index.totals if it belongs to an existing Totals '
            'backup, or use a new private bot.',
          );
        }
        normalizedKey = _crypto.generateRecoveryKey();
        // Persist the only decryption key before creating the remote catalog.
        // If setup is interrupted after the pin succeeds, a retry on this
        // device can recover the draft key and finish safely.
        await _settings.saveCredentials(
          token: session.token,
          recoveryKey: normalizedKey,
        );
        final catalog = TelegramBackupCatalog.empty(chat.id);
        final encryptedCatalog = await _encryptCatalog(
          catalog,
          normalizedKey,
        );
        final document = await api.sendDocument(
          chatId: chat.id,
          bytes: encryptedCatalog,
          fileName: catalogFileName,
          caption: _catalogCaption,
        );
        try {
          await api.pinMessage(
            chatId: chat.id,
            messageId: document.messageId,
          );
        } on TelegramBotApiException {
          throw const TelegramBackupException(
            'The catalog was uploaded, but the bot could not pin it. Make '
            'sure this is a private chat with the bot and retry setup.',
          );
        }
        catalogMessageId = document.messageId;
        createdNewCatalog = true;
      }

      final config = TelegramBackupConfig(
        botId: session.bot.id,
        botUsername: session.bot.username,
        botDisplayName: session.bot.displayName,
        chatId: chat.id,
        chatDisplayName: chat.displayName,
        chatUsername: chat.username,
        catalogMessageId: catalogMessageId,
        // A second device should not immediately race the device already
        // producing this catalog. The user can deliberately move the schedule
        // here after disabling it on the old device.
        schedule: createdNewCatalog
            ? TelegramBackupSchedule.recommended
            : TelegramBackupSchedule.manual,
        scheduleAnchorAt: DateTime.now().toUtc(),
      );
      await _settings.saveConnection(
        config: config,
        token: session.token,
        recoveryKey: normalizedKey,
      );
      return TelegramConnectionResult(
        config: config,
        recoveryKey: _crypto.formatRecoveryKey(normalizedKey),
        createdNewCatalog: createdNewCatalog,
        shouldShowRecoveryKey: createdNewCatalog || recoveredDraftKey,
      );
    } on TelegramRecoveryKeyRequiredException {
      rethrow;
    } on TelegramRecoveryKeyInvalidException {
      rethrow;
    } on TelegramBackupException {
      rethrow;
    } on TelegramBackupCryptoException catch (error) {
      throw TelegramRecoveryKeyInvalidException(error.message);
    } on TelegramBotApiException catch (error) {
      throw TelegramBackupException(_friendlyApiError(error));
    } finally {
      api.close();
    }
  }

  Future<List<TelegramBackupEntry>> listBackups() {
    return _serialized(() => _withDeviceBackupLock(() async {
          final connection = await _connection();
          final api = _apiFactory(connection.token);
          try {
            final loaded = await _loadPinnedCatalog(
              api: api,
              config: connection.config,
              recoveryKey: connection.recoveryKey,
            );
            if (loaded.document.messageId !=
                connection.config.catalogMessageId) {
              await _settings.updateCatalogMessageId(
                loaded.document.messageId,
              );
            }
            return loaded.catalog.entries;
          } finally {
            api.close();
          }
        }));
  }

  Future<TelegramBackupEntry> backupNow() {
    return _serialized(() => _withDeviceBackupLock(_performBackup));
  }

  Future<String> downloadBackup(TelegramBackupEntry entry) {
    return _serialized(() async {
      final connection = await _connection();
      if (entry.fileSize > maximumInAppBackupBytes) {
        throw const TelegramBackupException(
          'This backup is too large for an in-app Telegram restore.',
        );
      }
      final api = _apiFactory(connection.token);
      try {
        final encrypted = await api.downloadFile(
          entry.fileId,
          maximumBytes: maximumInAppBackupBytes,
        );
        final actualHash = await _crypto.sha256Hex(encrypted);
        if (actualHash.toLowerCase() != entry.sha256.toLowerCase()) {
          throw const TelegramBackupException(
            'This Telegram backup no longer matches its encrypted catalog.',
          );
        }
        final plain = await _crypto.decrypt(
          encrypted,
          recoveryKey: connection.recoveryKey,
          expectedContentType: TelegramBackupCrypto.backupContentType,
        );
        return utf8.decode(plain);
      } on TelegramBackupException {
        rethrow;
      } on TelegramBackupCryptoException catch (error) {
        throw TelegramBackupException(error.message);
      } on TelegramBotApiException catch (error) {
        throw TelegramBackupException(_friendlyApiError(error));
      } finally {
        api.close();
      }
    });
  }

  Future<String> formattedRecoveryKey() async {
    final key = await _settings.readRecoveryKey();
    if (key == null) {
      throw const TelegramBackupException(
        'The recovery key is not available on this device.',
      );
    }
    try {
      return _crypto.formatRecoveryKey(key);
    } on TelegramBackupCryptoException catch (error) {
      throw TelegramBackupException(error.message);
    }
  }

  Future<TelegramBackupAttemptResult> backupIfDue({
    DateTime? now,
    TimeOfDay? summaryTime,
  }) async {
    await AdvancedSettingsService.instance.reload();
    if (!AdvancedSettingsService.instance.telegramBackupEnabled.value) {
      return TelegramBackupAttemptResult.skipped;
    }
    await _settings.reload();
    var config = _settings.config.value;
    if (config == null || config.schedule == TelegramBackupSchedule.manual) {
      return TelegramBackupAttemptResult.skipped;
    }
    final current = now ?? DateTime.now();
    config = await _settings.ensureScheduleAnchor(now: current);
    if (config == null) return TelegramBackupAttemptResult.skipped;
    final scheduledTime = summaryTime ??
        await NotificationSettingsService.instance.getDailySummaryTime();
    if (!isTelegramBackupDue(
      config: config,
      now: current,
      summaryTime: scheduledTime,
    )) {
      return TelegramBackupAttemptResult.skipped;
    }

    return _serialized(
      () => _withDeviceBackupLock(
        () async {
          // The winning isolate re-reads persisted state after acquiring the
          // SQLite lease so only one due boundary can be uploaded.
          await AdvancedSettingsService.instance.reload();
          await _settings.reload();
          final lockedConfig = _settings.config.value;
          if (!AdvancedSettingsService.instance.telegramBackupEnabled.value ||
              lockedConfig == null ||
              lockedConfig.schedule == TelegramBackupSchedule.manual ||
              !isTelegramBackupDue(
                config: lockedConfig,
                now: current,
                summaryTime: scheduledTime,
              )) {
            return TelegramBackupAttemptResult.skipped;
          }
          try {
            await _performBackup();
            return TelegramBackupAttemptResult.succeeded;
          } catch (_) {
            return TelegramBackupAttemptResult.retry;
          }
        },
        onBusy: () => TelegramBackupAttemptResult.skipped,
      ),
    );
  }

  Future<void> disconnect() {
    return _serialized(
      () => _withDeviceBackupLock(_settings.disconnect),
    );
  }

  Future<void> setSchedule(TelegramBackupSchedule schedule) {
    return _serialized(
      () => _withDeviceBackupLock(
        () => _settings.setSchedule(schedule),
      ),
    );
  }

  Future<TelegramBackupEntry> _performBackup() async {
    final connection = await _connection();
    final api = _apiFactory(connection.token);
    try {
      final loaded = await _loadPinnedCatalog(
        api: api,
        config: connection.config,
        recoveryKey: connection.recoveryKey,
      );
      final pendingBackup = connection.config.pendingBackup;
      if (pendingBackup != null) {
        return await _commitBackupEntry(
          api: api,
          config: connection.config,
          loaded: loaded,
          entry: pendingBackup,
          recoveryKey: connection.recoveryKey,
        );
      }

      final exported = await _exportImportService.exportAllData();
      final encrypted = await _crypto.encrypt(
        utf8.encode(exported),
        recoveryKey: connection.recoveryKey,
        contentType: TelegramBackupCrypto.backupContentType,
      );
      if (encrypted.length > maximumInAppBackupBytes) {
        throw const TelegramBackupException(
          'This encrypted backup is larger than Telegram’s in-app download '
          'limit. Use Export Data for this backup.',
        );
      }

      final now = DateTime.now().toUtc();
      final fileName = _backupFileName(now);
      var uploadMessageId = connection.config.pendingUploadMessageId;
      if (uploadMessageId == null) {
        uploadMessageId = await api.sendMessage(
          chatId: connection.config.chatId,
          text: _pendingBackupMessage,
        );
        await _settings.recordPendingUploadMessageId(uploadMessageId);
      }
      // Upload by editing one durable placeholder message. If Telegram accepts
      // the document but its response is lost, a retry replaces that same
      // message instead of creating a second visible backup document.
      final uploaded = await api.replaceDocument(
        chatId: connection.config.chatId,
        messageId: uploadMessageId,
        bytes: encrypted,
        fileName: fileName,
        caption: 'Encrypted Totals backup • ${now.toIso8601String()}',
      );
      final entry = TelegramBackupEntry(
        id: _uuid.v4(),
        createdAt: now,
        fileName: fileName,
        fileSize: uploaded.fileSize > 0 ? uploaded.fileSize : encrypted.length,
        sha256: await _crypto.sha256Hex(encrypted),
        exportSchemaVersion: DataExportImportService.currentSchemaVersion,
        fileId: uploaded.fileId,
        messageId: uploaded.messageId,
      );
      // Persist Telegram's document identifiers before touching the catalog.
      // If catalog replacement or the final settings write fails, the retry
      // can commit this exact upload instead of sending the backup again.
      await _settings.recordPendingBackup(entry);
      return await _commitBackupEntry(
        api: api,
        config: connection.config,
        loaded: loaded,
        entry: entry,
        recoveryKey: connection.recoveryKey,
      );
    } on TelegramBackupException catch (error) {
      await _settings.recordBackupFailure(error.message);
      rethrow;
    } on TelegramBackupCryptoException catch (error) {
      await _settings.recordBackupFailure(error.message);
      throw TelegramBackupException(error.message);
    } on TelegramBotApiException catch (error) {
      final message = _friendlyApiError(error);
      await _settings.recordBackupFailure(message);
      throw TelegramBackupException(message);
    } catch (error) {
      const message = 'Could not create the Telegram backup.';
      await _settings.recordBackupFailure(message);
      throw const TelegramBackupException(message);
    } finally {
      api.close();
    }
  }

  Future<TelegramBackupEntry> _commitBackupEntry({
    required TelegramBotApi api,
    required TelegramBackupConfig config,
    required _LoadedCatalog loaded,
    required TelegramBackupEntry entry,
    required String recoveryKey,
  }) async {
    final alreadyCataloged = loaded.catalog.entries.any(
      (existing) =>
          existing.id == entry.id ||
          existing.messageId == entry.messageId ||
          existing.fileId == entry.fileId,
    );
    var catalogDocument = loaded.document;
    if (!alreadyCataloged) {
      catalogDocument = await _replaceCatalog(
        api: api,
        config: config,
        currentDocument: loaded.document,
        catalog: loaded.catalog.add(entry),
        recoveryKey: recoveryKey,
      );
    }
    await _settings.recordBackupSuccess(
      completedAt: entry.createdAt,
      catalogMessageId: catalogDocument.messageId,
    );
    return entry;
  }

  Future<_TelegramConnection> _connection() async {
    await _settings.ensureLoaded();
    final config = _settings.config.value;
    final token = await _settings.readToken();
    final recoveryKey = await _settings.readRecoveryKey();
    if (config == null || token == null || recoveryKey == null) {
      throw const TelegramBackupException(
        'Telegram Backup is not connected on this device.',
      );
    }
    return _TelegramConnection(
      config: config,
      token: token,
      recoveryKey: recoveryKey,
    );
  }

  Future<_LoadedCatalog> _loadPinnedCatalog({
    required TelegramBotApi api,
    required TelegramBackupConfig config,
    required String recoveryKey,
  }) async {
    try {
      var chat = await api.getChat(config.chatId);
      var document = _pinnedCatalogDocument(chat);
      if (document == null && config.catalogMessageId > 0) {
        try {
          await api.pinMessage(
            chatId: config.chatId,
            messageId: config.catalogMessageId,
          );
          chat = await api.getChat(config.chatId);
          document = _pinnedCatalogDocument(chat);
        } on TelegramBotApiException {
          // Fall through to the actionable missing-index error below.
        }
      }
      if (document == null) {
        throw const TelegramBackupException(
          'The pinned Totals backup index is missing. In Telegram, re-pin '
          'totals_backup_index.totals and then retry.',
        );
      }
      final catalog = await _downloadCatalog(
        api: api,
        document: document,
        recoveryKey: recoveryKey,
        expectedChatId: config.chatId,
      );
      return _LoadedCatalog(document: document, catalog: catalog);
    } on TelegramBackupException {
      rethrow;
    } on TelegramBackupCryptoException catch (error) {
      throw TelegramBackupException(error.message);
    } on TelegramBotApiException catch (error) {
      throw TelegramBackupException(_friendlyApiError(error));
    }
  }

  Future<TelegramBackupCatalog> _downloadCatalog({
    required TelegramBotApi api,
    required TelegramRemoteDocument document,
    required String recoveryKey,
    required String expectedChatId,
  }) async {
    final encrypted = await api.downloadFile(document.fileId);
    final plain = await _crypto.decrypt(
      encrypted,
      recoveryKey: recoveryKey,
      expectedContentType: TelegramBackupCrypto.catalogContentType,
    );
    try {
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map) throw const FormatException();
      final catalog = TelegramBackupCatalog.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (catalog.chatId != expectedChatId) {
        throw const TelegramBackupException(
          'The pinned Totals catalog belongs to a different Telegram chat.',
        );
      }
      return catalog;
    } on TelegramBackupException {
      rethrow;
    } on FormatException catch (error) {
      throw TelegramBackupException(error.message);
    } catch (_) {
      throw const TelegramBackupException(
        'The encrypted Telegram backup index is damaged.',
      );
    }
  }

  Future<TelegramRemoteDocument> _replaceCatalog({
    required TelegramBotApi api,
    required TelegramBackupConfig config,
    required TelegramRemoteDocument currentDocument,
    required TelegramBackupCatalog catalog,
    required String recoveryKey,
  }) async {
    final bytes = await _encryptCatalog(catalog, recoveryKey);
    try {
      return await api.replaceDocument(
        chatId: config.chatId,
        messageId: currentDocument.messageId,
        bytes: bytes,
        fileName: catalogFileName,
        caption: _catalogCaption,
      );
    } on TelegramBotApiException {
      final replacement = await api.sendDocument(
        chatId: config.chatId,
        bytes: bytes,
        fileName: catalogFileName,
        caption: _catalogCaption,
      );
      await api.pinMessage(
        chatId: config.chatId,
        messageId: replacement.messageId,
      );
      return replacement;
    }
  }

  Future<List<int>> _encryptCatalog(
    TelegramBackupCatalog catalog,
    String recoveryKey,
  ) {
    return _crypto.encrypt(
      utf8.encode(jsonEncode(catalog.toJson())),
      recoveryKey: recoveryKey,
      contentType: TelegramBackupCrypto.catalogContentType,
    );
  }

  TelegramRemoteDocument? _pinnedCatalogDocument(
    Map<String, dynamic> chat,
  ) {
    final rawPinned = chat['pinned_message'];
    if (rawPinned is! Map) return null;
    final pinned = Map<String, dynamic>.from(rawPinned);
    final rawDocument = pinned['document'];
    if (rawDocument is! Map) return null;
    final document = Map<String, dynamic>.from(rawDocument);
    final fileName = (document['file_name'] as String?) ?? '';
    if (fileName != catalogFileName) return null;
    final fileId = (document['file_id'] as String?)?.trim() ?? '';
    final messageId = (pinned['message_id'] as num?)?.toInt() ?? 0;
    if (fileId.isEmpty || messageId <= 0) return null;
    return TelegramRemoteDocument(
      fileId: fileId,
      fileName: fileName,
      fileSize: (document['file_size'] as num?)?.toInt() ?? 0,
      messageId: messageId,
    );
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<T> _withDeviceBackupLock<T>(
    Future<T> Function() action, {
    T Function()? onBusy,
  }) async {
    final lease = await _runtimeLocks.tryAcquire(
      _runtimeLockName,
      ttl: _runtimeLockTtl,
    );
    if (lease == null) {
      if (onBusy != null) return onBusy();
      throw const TelegramBackupException(
        'Another Telegram backup operation is already running.',
      );
    }
    try {
      return await action();
    } finally {
      try {
        await _runtimeLocks.release(lease);
      } catch (_) {}
    }
  }

  String _randomHex(int byteLength) {
    return List<int>.generate(byteLength, (_) => _random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String _backupFileName(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'totals_backup_${date.year}${two(date.month)}${two(date.day)}_'
        '${two(date.hour)}${two(date.minute)}${two(date.second)}.totals';
  }

  static String _friendlyApiError(TelegramBotApiException error) {
    if (error.errorCode == 401) {
      return 'Telegram rejected this bot token. Copy it again from BotFather.';
    }
    if (error.errorCode == 409) {
      return 'This bot is already connected to another app or webhook. Use a '
          'new private bot for Totals.';
    }
    return error.message;
  }

  static const String _catalogCaption =
      'Totals encrypted backup index. Keep this message pinned so Totals can '
      'show your backups.';
}

class _TelegramConnection {
  final TelegramBackupConfig config;
  final String token;
  final String recoveryKey;

  const _TelegramConnection({
    required this.config,
    required this.token,
    required this.recoveryKey,
  });
}

class _LoadedCatalog {
  final TelegramRemoteDocument document;
  final TelegramBackupCatalog catalog;

  const _LoadedCatalog({
    required this.document,
    required this.catalog,
  });
}
