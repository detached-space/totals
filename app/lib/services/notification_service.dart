import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/category.dart' as models;
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/receiver_category_service.dart';
import 'package:totals/services/notification_intent_bus.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/constants/cash_constants.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _transactionChannelId = 'transactions';
  static const String _dailySpendingChannelId = 'daily_spending';
  static const String _accountSyncChannelId = 'account_sync';
  static const String _budgetChannelId = 'budgets';
  static const String _duplicateChannelId = 'duplicate_warnings';
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
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
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
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _budgetChannelId,
        'Budget Alerts',
        description: 'Notifications for budget warnings and alerts',
        importance: Importance.defaultImportance,
      ),
    );

    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    _handleNotificationResponse(response);
  }

  Future<void> _handleNotificationResponse(NotificationResponse response) async {
    try {
      if (response.notificationResponseType ==
          NotificationResponseType.selectedNotificationAction) {
        // Action button was tapped - handle quick categorization directly
        final actionId = response.actionId;
        if (actionId != null && actionId.contains('|cat:')) {
          await _handleQuickCategorizeAction(actionId, response.id);
          return;
        }
      }

      // For regular taps, use the intent bus
      final payload = response.notificationResponseType ==
              NotificationResponseType.selectedNotificationAction
          ? response.actionId
          : response.payload;

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

  Future<void> _handleQuickCategorizeAction(String actionId, int? notificationId) async {
    try {
      await ensureInitialized();
      // Parse: tx:<reference>|cat:<categoryId>
      final parts = actionId.split('|cat:');
      if (parts.length != 2) return;

      final reference = Uri.decodeComponent(parts[0].substring(3)); // Remove 'tx:'
      final categoryId = int.tryParse(parts[1]);
      if (categoryId == null) return;

      if (kDebugMode) {
        print('debug: Quick categorize: $reference -> category $categoryId');
      }

      // Find and update the transaction
      final txRepo = TransactionRepository();
      final transaction = await txRepo.getTransactionByReference(reference);

      if (transaction == null) {
        if (kDebugMode) {
          print('debug: Quick categorize: transaction not found');
        }
        return;
      }

      // Save with new category
      await txRepo.saveTransaction(
        transaction.copyWith(categoryId: categoryId),
      );

      if (kDebugMode) {
        print('debug: Quick categorize: saved successfully');
      }

      final isAutoCategorizeEnabled = await NotificationSettingsService.instance
          .isAutoCategorizeByReceiverEnabled();
      if (isAutoCategorizeEnabled) {
        final receiver = transaction.receiver;
        if (receiver != null && receiver.isNotEmpty) {
          await ReceiverCategoryService.instance.saveMapping(
            receiver,
            categoryId,
            'receiver',
          );
        }
        final creditor = transaction.creditor;
        if (creditor != null && creditor.isNotEmpty) {
          await ReceiverCategoryService.instance.saveMapping(
            creditor,
            categoryId,
            'creditor',
          );
        }
      }

      // Cancel the notification
      if (notificationId != null) {
        await _plugin.cancel(notificationId);
        if (kDebugMode) {
          print('debug: Quick categorize: notification cancelled');
        }
      }

      // Refresh widget
      await WidgetService.refreshWidget();
    } catch (e) {
      if (kDebugMode) {
        print('debug: Quick categorize failed: $e');
      }
    }
  }

  NotificationIntent? _intentFromPayload(String? payload) {
    final raw = payload?.trim();
    if (raw == null || raw.isEmpty) return null;

    if (raw.startsWith('tx:')) {
      final rest = raw.substring(3);
      final parts = rest.split('|cat:');
      final reference = Uri.decodeComponent(parts[0]);
      if (reference.trim().isEmpty) return null;

      if (parts.length > 1) {
        final categoryId = int.tryParse(parts[1]);
        if (categoryId != null) {
          return QuickCategorizeTransactionIntent(reference, categoryId);
        }
      }
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

      final actions = await _buildQuickCategoryActions(transaction);
      if (kDebugMode) {
        print('debug: Transaction notification actions: ${actions.length}');
        for (final a in actions) {
          print('debug:   - ${a.title} (${a.id})');
        }
      }

      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _transactionChannelId,
            'Transactions',
            channelDescription:
                'Notifications when a new transaction is detected',
            importance: Importance.high,
            priority: Priority.high,
            actions: actions,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show transaction notification: $e');
      }
    }
  }

  Future<void> showDuplicateWarningNotification({
    required Transaction transaction,
    required Duration timeDelta,
  }) async {
    try {
      await ensureInitialized();
      final seconds = timeDelta.inSeconds;
      final deltaLabel = seconds < 60 ? '${seconds}s' : '${timeDelta.inMinutes}m';
      final amountStr =
          'ETB ${transaction.amount.toStringAsFixed(2)}';
      await _plugin.show(
        transaction.reference.hashCode ^ 0xD0B1,
        '⚠️ Possible duplicate transaction',
        '$amountStr appeared twice within $deltaLabel — verify in the app.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _duplicateChannelId,
            'Duplicate Warnings',
            channelDescription:
                'Alerts when a transaction looks like a duplicate',
            importance: Importance.high,
            priority: Priority.high,
            color: const Color(0xFFE53935),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show duplicate warning notification: $e');
      }
    }
  }

  Future<List<AndroidNotificationAction>> _buildQuickCategoryActions(
    Transaction transaction,
  ) async {
    try {
      final settings = NotificationSettingsService.instance;
      final isIncome = transaction.type == 'CREDIT';
      final categoryIds = isIncome
          ? await settings.getQuickCategorizeIncomeIds()
          : await settings.getQuickCategorizeExpenseIds();

      if (categoryIds.isEmpty) return [];

      final allCategories = await CategoryRepository().getCategories();
      final List<models.Category> categories = [];
      for (final id in categoryIds) {
        final cat = allCategories.where((c) => c.id == id).firstOrNull;
        if (cat != null) categories.add(cat);
        if (categories.length >= 3) break;
      }

      if (categories.isEmpty) return [];

      final List<AndroidNotificationAction> actions = [];
      for (final cat in categories) {
        final actionPayload =
            'tx:${Uri.encodeComponent(transaction.reference)}|cat:${cat.id}';
        actions.add(AndroidNotificationAction(
          actionPayload,
          cat.name,
          showsUserInterface: false,
        ));
      }
      return actions;
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to build quick category actions: $e');
      }
      return [];
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

  Future<void> showBudgetAlertNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await ensureInitialized();

      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _budgetChannelId,
            'Budget Alerts',
            channelDescription: 'Notifications for budget warnings and alerts',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show budget alert notification: $e');
      }
    }
  }

  static Bank? _findBank(int? bankId) {
    if (bankId == null) return null;
    if (bankId == CashConstants.bankId) {
      return const Bank(
        id: CashConstants.bankId,
        name: CashConstants.bankName,
        shortName: CashConstants.bankShortName,
        codes: [],
        image: CashConstants.bankImage,
      );
    }
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

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (kDebugMode) {
    print('debug: Background notification action: ${response.actionId}');
  }

  if (response.notificationResponseType !=
      NotificationResponseType.selectedNotificationAction) {
    return;
  }

  final actionId = response.actionId;
  if (actionId == null || !actionId.contains('|cat:')) return;

  unawaited(_handleQuickCategorizeFromBackground(actionId, response.id));
}

Future<void> _handleQuickCategorizeFromBackground(
  String actionId,
  int? notificationId,
) async {
  await WidgetService.initialize();
  await NotificationService.instance._handleQuickCategorizeAction(
    actionId,
    notificationId,
  );
}
