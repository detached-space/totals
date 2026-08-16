import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/telegram_backup/telegram_backup_models.dart';

void main() {
  test('new config defaults to the recommended weekly schedule', () {
    const config = TelegramBackupConfig(
      botId: '123',
      botUsername: 'totals_backup_bot',
      botDisplayName: 'Totals Backup',
      chatId: '456',
      chatDisplayName: 'Owner',
      catalogMessageId: 7,
    );

    expect(TelegramBackupSchedule.recommended, TelegramBackupSchedule.weekly);
    expect(config.schedule, TelegramBackupSchedule.weekly);
  });

  test('catalog JSON round trip keeps newest backups first', () {
    final older = TelegramBackupEntry(
      id: 'older',
      createdAt: DateTime.utc(2026, 7, 1),
      fileName: 'older.totals',
      fileSize: 100,
      sha256: 'aa',
      exportSchemaVersion: 8,
      fileId: 'file-old',
      messageId: 10,
    );
    final newer = TelegramBackupEntry(
      id: 'newer',
      createdAt: DateTime.utc(2026, 7, 2),
      fileName: 'newer.totals',
      fileSize: 200,
      sha256: 'bb',
      exportSchemaVersion: 9,
      fileId: 'file-new',
      messageId: 11,
    );
    final catalog = TelegramBackupCatalog(
      version: TelegramBackupCatalog.currentVersion,
      chatId: '12345',
      updatedAt: DateTime.utc(2026, 7, 2),
      entries: [older, newer],
    );

    final decoded = TelegramBackupCatalog.fromJson(catalog.toJson());

    expect(decoded.chatId, '12345');
    expect(decoded.entries.map((entry) => entry.id), ['newer', 'older']);
    expect(decoded.entries.first.exportSchemaVersion, 9);
  });

  test('config persistence preserves schedule and status', () {
    final config = TelegramBackupConfig(
      botId: '123',
      botUsername: 'totals_backup_bot',
      botDisplayName: 'Totals Backup',
      chatId: '456',
      chatDisplayName: 'Owner',
      catalogMessageId: 7,
      schedule: TelegramBackupSchedule.weekly,
      scheduleAnchorAt: DateTime.utc(2026, 7, 20, 8),
      lastBackupAt: DateTime.utc(2026, 7, 24, 8),
      lastBackupError: 'temporary failure',
    );

    final decoded = TelegramBackupConfig.fromJson(config.toJson());
    final successful = decoded.copyWith(clearLastBackupError: true);
    final legacyJson = Map<String, dynamic>.from(config.toJson())
      ..remove('scheduleAnchorAt')
      ..['wifiOnly'] = true;
    final legacy = TelegramBackupConfig.fromJson(legacyJson);

    expect(decoded.isConfigured, isTrue);
    expect(decoded.schedule, TelegramBackupSchedule.weekly);
    expect(decoded.toJson()['wifiOnly'], isFalse);
    expect(decoded.scheduleAnchorAt, DateTime.utc(2026, 7, 20, 8));
    expect(decoded.lastBackupAt, DateTime.utc(2026, 7, 24, 8));
    expect(successful.lastBackupError, isNull);
    expect(legacy.scheduleAnchorAt, isNull);
    expect(legacy.toJson()['wifiOnly'], isFalse);
  });

  test('pending uploaded backup survives persistence and can be cleared', () {
    final pending = TelegramBackupEntry(
      id: 'pending-id',
      createdAt: DateTime.utc(2026, 8, 10, 12),
      fileName: 'totals_backup_20260810_120000.totals',
      fileSize: 321,
      sha256: 'abc123',
      exportSchemaVersion: 11,
      fileId: 'pending-file-id',
      messageId: 42,
    );
    final config = TelegramBackupConfig(
      botId: '123',
      botUsername: 'totals_backup_bot',
      botDisplayName: 'Totals Backup',
      chatId: '456',
      chatDisplayName: 'Owner',
      catalogMessageId: 7,
      pendingUploadMessageId: 41,
      pendingBackup: pending,
    );

    final decoded = TelegramBackupConfig.fromJson(config.toJson());
    final completed = decoded.copyWith(
      clearPendingUploadMessageId: true,
      clearPendingBackup: true,
    );

    expect(decoded.pendingBackup?.id, 'pending-id');
    expect(decoded.pendingBackup?.messageId, 42);
    expect(decoded.pendingUploadMessageId, 41);
    expect(completed.pendingUploadMessageId, isNull);
    expect(completed.pendingBackup, isNull);
  });
}
