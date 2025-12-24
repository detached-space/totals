import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/notification_intent_bus.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/utils/text_utils.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _transactionChannelId = 'transactions';
  static const String _dailySpendingChannelId = 'daily_spending';
  static const String _accountSyncChannelId = 'account_sync';
  static const int dailySpendingNotificationId = 9001;
  static const int dailySpendingTestNotificationId = 9002;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _transactionChannelId,
        'Transactions',
        description: 'Notifications when a new transaction is detected',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _dailySpendingChannelId,
        "Today's spending",
        description: "Daily summary of today's spending",
        importance: Importance.defaultImportance,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _accountSyncChannelId,
        'Account sync',
        description: 'Background sync of account transactions',
        importance: Importance.low,
      ),
    );

    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    try {
      final payload = response.payload;
      final intent = _intentFromPayload(payload);
      if (intent != null) {
        NotificationIntentBus.instance.emit(intent);
      }
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed handling notification tap: $e');
      }
    }
  }

  NotificationIntent? _intentFromPayload(String? payload) {
    final raw = payload?.trim();
    if (raw == null || raw.isEmpty) return null;

    if (raw.startsWith('tx:')) {
      final encoded = raw.substring(3);
      final reference = Uri.decodeComponent(encoded);
      if (reference.trim().isEmpty) return null;
      return CategorizeTransactionIntent(reference);
    }

    return null;
  }

  Future<void> emitLaunchIntentIfAny() async {
    try {
      await ensureInitialized();
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null) return;
      if (details.didNotificationLaunchApp != true) return;

      final payload = details.notificationResponse?.payload;
      final intent = _intentFromPayload(payload);
      if (intent != null) {
        NotificationIntentBus.instance.emit(intent);
      }
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed reading launch notification details: $e');
      }
    }
  }

  Future<bool> arePermissionsGranted() async {
    if (kIsWeb) return true;

    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to check notification permission status: $e');
      }
      return false;
    }
  }

  Future<void> requestPermissionsIfNeeded() async {
    try {
      await ensureInitialized();

      if (kIsWeb) return;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin =
            _plugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosPlugin =
            _plugin.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('debug: Notification permission request failed: $e');
      }
    }
  }

  Future<void> showTransactionNotification({
    required Transaction transaction,
    required int? bankId,
  }) async {
    try {
      await ensureInitialized();

      final enabled = await NotificationSettingsService.instance
          .isTransactionNotificationsEnabled();
      if (!enabled) return;

      final bank = _findBank(bankId);
      final title = _buildTitle(bank, transaction);
      final body = _buildBody(transaction);

      final id = _notificationId(transaction);
      final payload = 'tx:${Uri.encodeComponent(transaction.reference)}';

      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _transactionChannelId,
            'Transactions',
            channelDescription:
                'Notifications when a new transaction is detected',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show transaction notification: $e');
      }
    }
  }

  Future<bool> showDailySpendingNotification({
    required double amount,
    int id = dailySpendingNotificationId,
    bool ignoreEnabledCheck = false,
  }) async {
    try {
      await ensureInitialized();

      if (!ignoreEnabledCheck) {
        final enabled =
            await NotificationSettingsService.instance.isDailySummaryEnabled();
        if (!enabled) return false;
      }

      final title = "Today's spending";
      final body = "You've spent ${formatNumberWithComma(amount)} ETB today.";

      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _dailySpendingChannelId,
            "Today's spending",
            channelDescription: "Daily summary of today's spending",
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show daily spending notification: $e');
      }
      return false;
    }
  }

  Future<bool> showDailySpendingTestNotification({
    required double amount,
  }) async {
    return showDailySpendingNotification(
      amount: amount,
      id: dailySpendingTestNotificationId,
      ignoreEnabledCheck: true,
    );
  }

  Future<void> showAccountSyncProgress({
    required String accountNumber,
    required int bankId,
    required String stage,
    required double progress,
    String? bankLabel,
  }) async {
    try {
      await ensureInitialized();

      final clamped = progress.clamp(0.0, 1.0);
      final percent = (clamped * 100).round();
      final title = bankLabel == null ? 'Syncing account' : '$bankLabel sync';
      final maskedAccount = _maskAccountNumber(accountNumber);
      final body =
          maskedAccount == null ? stage : '$stage - $maskedAccount';

      await _plugin.show(
        _accountSyncNotificationId(accountNumber, bankId),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _accountSyncChannelId,
            'Account sync',
            channelDescription: 'Background sync of account transactions',
            importance: Importance.low,
            priority: Priority.low,
            showProgress: true,
            maxProgress: 100,
            progress: percent,
            ongoing: clamped < 1.0,
            onlyAlertOnce: true,
            enableVibration: false,
            playSound: false,
          ),
          iOS: const DarwinNotificationDetails(
            presentSound: false,
            presentBadge: false,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show account sync progress: $e');
      }
    }
  }

  Future<void> showAccountSyncComplete({
    required String accountNumber,
    required int bankId,
    String? bankLabel,
    String? message,
  }) async {
    try {
      await ensureInitialized();

      final title =
          bankLabel == null ? 'Account sync complete' : '$bankLabel sync complete';
      final body = message ?? 'Your transactions are up to date.';

      await _plugin.show(
        _accountSyncNotificationId(accountNumber, bankId),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _accountSyncChannelId,
            'Account sync',
            channelDescription: 'Background sync of account transactions',
            importance: Importance.low,
            priority: Priority.low,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show account sync completion: $e');
      }
    }
  }

  static Bank? _findBank(int? bankId) {
    if (bankId == null) return null;
    for (final bank in AppConstants.banks) {
      if (bank.id == bankId) return bank;
    }
    return null;
  }

  static int _notificationId(Transaction transaction) {
    // Stable ID so "same reference" updates instead of spamming.
    final raw = transaction.reference.isEmpty
        ? '${transaction.time ?? ''}|${transaction.amount}'
        : transaction.reference;
    return raw.hashCode & 0x7fffffff;
  }

  static String _buildTitle(Bank? bank, Transaction transaction) {
    final bankLabel = bank?.shortName ?? 'Totals';
    final kind = switch (transaction.type) {
      'CREDIT' => 'Money In',
      'DEBIT' => 'Money Out',
      _ => 'Transaction',
    };
    return '$bankLabel • $kind';
  }

  static String _buildBody(Transaction transaction) {
    final sign = switch (transaction.type) {
      'CREDIT' => '+',
      'DEBIT' => '-',
      _ => '',
    };

    final counterparty = _firstNonEmpty([
      transaction.creditor,
      transaction.receiver,
    ]);

    final amount = '${sign}ETB ${formatNumberWithComma(transaction.amount)}';
    if (counterparty == null) return '$amount • Tap to categorize';
    return '$amount • $counterparty • Tap to categorize';
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      final trimmed = v?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static int _accountSyncNotificationId(String accountNumber, int bankId) {
    final raw = '$bankId|$accountNumber';
    return 8000 + (raw.hashCode & 0x7fffffff);
  }

  static String? _maskAccountNumber(String accountNumber) {
    final trimmed = accountNumber.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length <= 4) return trimmed;
    return '****${trimmed.substring(trimmed.length - 4)}';
  }
}
