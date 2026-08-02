enum TelegramBackupSchedule {
  manual,
  daily,
  weekly;

  String get storageValue {
    switch (this) {
      case TelegramBackupSchedule.manual:
        return 'manual';
      case TelegramBackupSchedule.daily:
        return 'daily';
      case TelegramBackupSchedule.weekly:
        return 'weekly';
    }
  }

  static TelegramBackupSchedule fromStorage(String? value) {
    switch (value) {
      case 'daily':
        return TelegramBackupSchedule.daily;
      case 'weekly':
        return TelegramBackupSchedule.weekly;
      case 'manual':
      default:
        return TelegramBackupSchedule.manual;
    }
  }
}

class TelegramBackupConfig {
  final String botId;
  final String botUsername;
  final String botDisplayName;
  final String chatId;
  final String chatDisplayName;
  final String? chatUsername;
  final int catalogMessageId;
  final TelegramBackupSchedule schedule;
  final DateTime? scheduleAnchorAt;
  final DateTime? lastBackupAt;
  final String? lastBackupError;

  const TelegramBackupConfig({
    required this.botId,
    required this.botUsername,
    required this.botDisplayName,
    required this.chatId,
    required this.chatDisplayName,
    required this.catalogMessageId,
    this.chatUsername,
    this.schedule = TelegramBackupSchedule.daily,
    this.scheduleAnchorAt,
    this.lastBackupAt,
    this.lastBackupError,
  });

  bool get isConfigured =>
      botId.isNotEmpty &&
      botUsername.isNotEmpty &&
      chatId.isNotEmpty &&
      catalogMessageId > 0;

  TelegramBackupConfig copyWith({
    int? catalogMessageId,
    TelegramBackupSchedule? schedule,
    DateTime? scheduleAnchorAt,
    DateTime? lastBackupAt,
    String? lastBackupError,
    bool clearLastBackupError = false,
  }) {
    return TelegramBackupConfig(
      botId: botId,
      botUsername: botUsername,
      botDisplayName: botDisplayName,
      chatId: chatId,
      chatDisplayName: chatDisplayName,
      chatUsername: chatUsername,
      catalogMessageId: catalogMessageId ?? this.catalogMessageId,
      schedule: schedule ?? this.schedule,
      scheduleAnchorAt: scheduleAnchorAt ?? this.scheduleAnchorAt,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      lastBackupError:
          clearLastBackupError ? null : lastBackupError ?? this.lastBackupError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'botId': botId,
      'botUsername': botUsername,
      'botDisplayName': botDisplayName,
      'chatId': chatId,
      'chatDisplayName': chatDisplayName,
      if (chatUsername != null) 'chatUsername': chatUsername,
      'catalogMessageId': catalogMessageId,
      'schedule': schedule.storageValue,
      // Retain the v1 field so older app versions also use mobile data when
      // they read a config written by this version.
      'wifiOnly': false,
      if (scheduleAnchorAt != null)
        'scheduleAnchorAt': scheduleAnchorAt!.toUtc().toIso8601String(),
      if (lastBackupAt != null)
        'lastBackupAt': lastBackupAt!.toUtc().toIso8601String(),
      if (lastBackupError != null) 'lastBackupError': lastBackupError,
    };
  }

  factory TelegramBackupConfig.fromJson(Map<String, dynamic> json) {
    return TelegramBackupConfig(
      botId: (json['botId'] as String?)?.trim() ?? '',
      botUsername: (json['botUsername'] as String?)?.trim() ?? '',
      botDisplayName: (json['botDisplayName'] as String?)?.trim() ?? '',
      chatId: (json['chatId'] as String?)?.trim() ?? '',
      chatDisplayName: (json['chatDisplayName'] as String?)?.trim() ?? '',
      chatUsername: (json['chatUsername'] as String?)?.trim(),
      catalogMessageId: (json['catalogMessageId'] as num?)?.toInt() ?? 0,
      schedule: TelegramBackupSchedule.fromStorage(
        json['schedule'] as String?,
      ),
      scheduleAnchorAt: DateTime.tryParse(
        (json['scheduleAnchorAt'] as String?) ?? '',
      )?.toUtc(),
      lastBackupAt: DateTime.tryParse(
        (json['lastBackupAt'] as String?) ?? '',
      )?.toUtc(),
      lastBackupError: json['lastBackupError'] as String?,
    );
  }
}

class TelegramBotIdentity {
  final String id;
  final String username;
  final String displayName;

  const TelegramBotIdentity({
    required this.id,
    required this.username,
    required this.displayName,
  });
}

class TelegramChatIdentity {
  final String id;
  final String displayName;
  final String? username;

  const TelegramChatIdentity({
    required this.id,
    required this.displayName,
    this.username,
  });
}

/// Kept in memory only while setup is in progress. Deliberately has no
/// `toString` implementation so the bot token cannot accidentally be logged.
class TelegramPairingSession {
  final String token;
  final String nonce;
  final TelegramBotIdentity bot;

  const TelegramPairingSession({
    required this.token,
    required this.nonce,
    required this.bot,
  });

  Uri get deepLink => Uri.https(
        't.me',
        '/${bot.username}',
        {'start': 'totals_$nonce'},
      );
}

class TelegramConnectionResult {
  final TelegramBackupConfig config;
  final String recoveryKey;
  final bool createdNewCatalog;
  final bool shouldShowRecoveryKey;

  const TelegramConnectionResult({
    required this.config,
    required this.recoveryKey,
    required this.createdNewCatalog,
    required this.shouldShowRecoveryKey,
  });
}

class TelegramBackupEntry {
  final String id;
  final DateTime createdAt;
  final String fileName;
  final int fileSize;
  final String sha256;
  final int exportSchemaVersion;
  final String fileId;
  final int messageId;

  const TelegramBackupEntry({
    required this.id,
    required this.createdAt,
    required this.fileName,
    required this.fileSize,
    required this.sha256,
    required this.exportSchemaVersion,
    required this.fileId,
    required this.messageId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'fileName': fileName,
      'fileSize': fileSize,
      'sha256': sha256,
      'exportSchemaVersion': exportSchemaVersion,
      'fileId': fileId,
      'messageId': messageId,
    };
  }

  factory TelegramBackupEntry.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(
      (json['createdAt'] as String?) ?? '',
    );
    if (createdAt == null) {
      throw const FormatException('Backup entry has an invalid date.');
    }
    return TelegramBackupEntry(
      id: (json['id'] as String?) ?? '',
      createdAt: createdAt.toUtc(),
      fileName: (json['fileName'] as String?) ?? '',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      sha256: (json['sha256'] as String?) ?? '',
      exportSchemaVersion: (json['exportSchemaVersion'] as num?)?.toInt() ?? 1,
      fileId: (json['fileId'] as String?) ?? '',
      messageId: (json['messageId'] as num?)?.toInt() ?? 0,
    );
  }
}

class TelegramBackupCatalog {
  static const int currentVersion = 1;

  final int version;
  final String chatId;
  final DateTime updatedAt;
  final List<TelegramBackupEntry> entries;

  const TelegramBackupCatalog({
    required this.version,
    required this.chatId,
    required this.updatedAt,
    required this.entries,
  });

  factory TelegramBackupCatalog.empty(String chatId) {
    return TelegramBackupCatalog(
      version: currentVersion,
      chatId: chatId,
      updatedAt: DateTime.now().toUtc(),
      entries: const [],
    );
  }

  TelegramBackupCatalog add(TelegramBackupEntry entry) {
    return TelegramBackupCatalog(
      version: version,
      chatId: chatId,
      updatedAt: DateTime.now().toUtc(),
      entries: [entry, ...entries],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'format': 'totals.telegram.catalog',
      'version': version,
      'chatId': chatId,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }

  factory TelegramBackupCatalog.fromJson(Map<String, dynamic> json) {
    if (json['format'] != 'totals.telegram.catalog') {
      throw const FormatException('This is not a Totals backup catalog.');
    }
    final version = (json['version'] as num?)?.toInt() ?? 0;
    if (version != currentVersion) {
      throw FormatException('Unsupported backup catalog version $version.');
    }
    final rawEntries = json['entries'];
    if (rawEntries is! List) {
      throw const FormatException('Backup catalog entries are missing.');
    }
    final entries = rawEntries
        .whereType<Map>()
        .map(
          (entry) => TelegramBackupEntry.fromJson(
            Map<String, dynamic>.from(entry),
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return TelegramBackupCatalog(
      version: version,
      chatId: (json['chatId'] as String?) ?? '',
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      entries: entries,
    );
  }
}

class TelegramRemoteDocument {
  final String fileId;
  final String fileName;
  final int fileSize;
  final int messageId;

  const TelegramRemoteDocument({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.messageId,
  });
}
