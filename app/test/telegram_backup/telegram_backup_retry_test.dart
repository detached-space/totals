import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/repositories/runtime_lock_repository.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/services/telegram_backup/telegram_backup_crypto.dart';
import 'package:totals/services/telegram_backup/telegram_backup_models.dart';
import 'package:totals/services/telegram_backup/telegram_backup_service.dart';
import 'package:totals/services/telegram_backup/telegram_backup_settings_service.dart';
import 'package:totals/services/telegram_backup/telegram_bot_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog retry reuses the uploaded backup instead of uploading again',
      () async {
    final harness = await _createHarness();

    await expectLater(
      harness.service.backupNow(),
      throwsA(isA<TelegramBackupException>()),
    );
    await harness.settings.reload();
    final pending = harness.settings.config.value?.pendingBackup;
    expect(pending, isNotNull);
    expect(harness.api.backupUploadCount, 1);
    expect(harness.api.placeholderCount, 1);

    harness.api.failCatalogWrites = false;
    final completed = await harness.service.backupNow();
    await harness.settings.reload();

    expect(completed.id, pending!.id);
    expect(harness.api.backupUploadCount, 1);
    expect(harness.api.placeholderCount, 1);
    expect(harness.settings.config.value?.pendingBackup, isNull);
    expect(harness.settings.config.value?.pendingUploadMessageId, isNull);
    expect(harness.settings.config.value?.lastBackupAt, pending.createdAt);

    final decryptedCatalog = await harness.crypto.decrypt(
      harness.api.catalogBytes,
      recoveryKey: _recoveryKey,
      expectedContentType: TelegramBackupCrypto.catalogContentType,
    );
    final catalog = TelegramBackupCatalog.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(utf8.decode(decryptedCatalog)) as Map,
      ),
    );
    expect(catalog.entries, hasLength(1));
    expect(catalog.entries.single.id, pending.id);
  });

  test('lost upload response retries through the same Telegram message',
      () async {
    final harness = await _createHarness();
    harness.api
      ..failCatalogWrites = false
      ..failNextBackupUploadAfterApplying = true;

    await expectLater(
      harness.service.backupNow(),
      throwsA(isA<TelegramBackupException>()),
    );
    await harness.settings.reload();
    final uploadMessageId =
        harness.settings.config.value?.pendingUploadMessageId;
    expect(uploadMessageId, isNotNull);
    expect(harness.settings.config.value?.pendingBackup, isNull);
    expect(harness.api.backupMessageIds, <int>{uploadMessageId!});

    final completed = await harness.service.backupNow();
    await harness.settings.reload();

    expect(completed.messageId, uploadMessageId);
    expect(harness.api.backupUploadCount, 2);
    expect(harness.api.backupMessageIds, hasLength(1));
    expect(harness.api.placeholderCount, 1);
    expect(harness.settings.config.value?.pendingUploadMessageId, isNull);
    expect(harness.settings.config.value?.pendingBackup, isNull);
  });
}

const _recoveryKey =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

Future<_RetryHarness> _createHarness() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  FlutterSecureStorage.setMockInitialValues(<String, String>{});

  final settings = TelegramBackupSettingsService.instance;
  await settings.disconnect();
  const chatId = '456';
  const config = TelegramBackupConfig(
    botId: '123',
    botUsername: 'totals_backup_bot',
    botDisplayName: 'Totals Backup',
    chatId: chatId,
    chatDisplayName: 'Owner',
    catalogMessageId: 7,
    schedule: TelegramBackupSchedule.manual,
  );
  await settings.saveConnection(
    config: config,
    token: '123:secret',
    recoveryKey: _recoveryKey,
  );

  final crypto = TelegramBackupCrypto(random: Random(7));
  final emptyCatalogBytes = await crypto.encrypt(
    utf8.encode(jsonEncode(TelegramBackupCatalog.empty(chatId).toJson())),
    recoveryKey: _recoveryKey,
    contentType: TelegramBackupCrypto.catalogContentType,
  );
  final api = _RetryingCatalogApi(emptyCatalogBytes);
  final service = TelegramBackupService(
    settings: settings,
    crypto: crypto,
    exportImportService: _FakeExportService(),
    apiFactory: (_) => api,
    runtimeLocks: _AlwaysAvailableRuntimeLockRepository(),
  );
  return _RetryHarness(
    settings: settings,
    crypto: crypto,
    api: api,
    service: service,
  );
}

class _RetryHarness {
  const _RetryHarness({
    required this.settings,
    required this.crypto,
    required this.api,
    required this.service,
  });

  final TelegramBackupSettingsService settings;
  final TelegramBackupCrypto crypto;
  final _RetryingCatalogApi api;
  final TelegramBackupService service;
}

class _FakeExportService extends DataExportImportService {
  @override
  Future<String> exportAllData({
    DataExportOptions options = const DataExportOptions(),
  }) async {
    return '{"schemaVersion":11}';
  }
}

class _AlwaysAvailableRuntimeLockRepository extends RuntimeLockRepository {
  @override
  Future<RuntimeLockLease?> tryAcquire(
    String name, {
    Duration ttl = const Duration(minutes: 15),
  }) async {
    return RuntimeLockLease(name: name, owner: 'test');
  }

  @override
  Future<void> release(RuntimeLockLease lease) async {}
}

class _RetryingCatalogApi extends TelegramBotApi {
  _RetryingCatalogApi(this.catalogBytes)
      : super(
          token: '123:secret',
          client: MockClient(
            (_) async => throw StateError('Unexpected real HTTP request.'),
          ),
        );

  List<int> catalogBytes;
  bool failCatalogWrites = true;
  bool failNextBackupUploadAfterApplying = false;
  int placeholderCount = 0;
  int backupUploadCount = 0;
  final Set<int> backupMessageIds = <int>{};

  @override
  Future<int> sendMessage({
    required String chatId,
    required String text,
  }) async {
    placeholderCount += 1;
    return 50 + placeholderCount;
  }

  @override
  Future<Map<String, dynamic>> getChat(String chatId) async {
    return <String, dynamic>{
      'pinned_message': <String, dynamic>{
        'message_id': 7,
        'document': <String, dynamic>{
          'file_id': 'catalog-file-id',
          'file_name': TelegramBackupService.catalogFileName,
          'file_size': catalogBytes.length,
        },
      },
    };
  }

  @override
  Future<List<int>> downloadFile(
    String fileId, {
    int maximumBytes = TelegramBotApi.maxDownloadBytes,
  }) async {
    return catalogBytes;
  }

  @override
  Future<TelegramRemoteDocument> sendDocument({
    required String chatId,
    required List<int> bytes,
    required String fileName,
    required String caption,
  }) async {
    if (fileName == TelegramBackupService.catalogFileName) {
      if (failCatalogWrites) {
        throw const TelegramBotApiException('Catalog upload failed.');
      }
      catalogBytes = bytes;
      return TelegramRemoteDocument(
        fileId: 'catalog-file-id',
        fileName: fileName,
        fileSize: bytes.length,
        messageId: 7,
      );
    }
    throw StateError('Backup documents must edit their placeholder message.');
  }

  @override
  Future<TelegramRemoteDocument> replaceDocument({
    required String chatId,
    required int messageId,
    required List<int> bytes,
    required String fileName,
    required String caption,
  }) async {
    if (fileName == TelegramBackupService.catalogFileName) {
      if (failCatalogWrites) {
        throw const TelegramBotApiException('Catalog edit failed.');
      }
      catalogBytes = bytes;
      return TelegramRemoteDocument(
        fileId: 'catalog-file-id',
        fileName: fileName,
        fileSize: bytes.length,
        messageId: messageId,
      );
    }
    backupUploadCount += 1;
    backupMessageIds.add(messageId);
    if (failNextBackupUploadAfterApplying) {
      failNextBackupUploadAfterApplying = false;
      throw const TelegramBotApiException('Upload response was lost.');
    }
    return TelegramRemoteDocument(
      fileId: 'backup-file-$backupUploadCount',
      fileName: fileName,
      fileSize: bytes.length,
      messageId: messageId,
    );
  }

  @override
  void close() {}
}
