import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/category.dart' as models;
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/failed_parse_review_service.dart';
import 'package:totals/services/background_refresh_signal_service.dart';
import 'package:totals/services/notification_intent_bus.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/constants/cash_constants.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _transactionChannelId = 'transactions';
  static const String _failedParseReviewChannelId = 'failed_parse_review';
  static const String _spendingSummaryChannelId = 'spending_summaries';
  static const String _accountSyncChannelId = 'account_sync';
  static const String _budgetChannelId = 'budgets';
  static const String _sharedExpensesChannelId = 'shared_expenses';
  static const String _historyPrefsKey = 'notification_history_v1';
  static const String _counterpartyActionPrefix = 'txname:';
  static const String _sharedExpensesPayload = 'shared_expenses';
  static const int _maxHistoryEntries = 200;
  static const int dailySpendingNotificationId = 9001;
  static const int dailySpendingTestNotificationId = 9002;
  static const int weeklySpendingNotificationId = 9003;
  static const int weeklySpendingTestNotificationId = 9004;
  static const int monthlySpendingNotificationId = 9005;
  static const int monthlySpendingTestNotificationId = 9006;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final Set<String> _knownBankTokens = _buildKnownBankTokens();

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

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
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
        _failedParseReviewChannelId,
        'Failed parse review',
        description: 'Prompts to confirm unparsed bank transactions',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _spendingSummaryChannelId,
        'Spending summaries',
        description: 'Daily, weekly, and monthly spending summaries',
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
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _sharedExpensesChannelId,
        'Shared expenses',
        description: 'Nudges and reminders from shared expenses',
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    _handleNotificationResponse(response);
  }

  Future<void> _handleNotificationResponse(
      NotificationResponse response) async {
    try {
      if (response.notificationResponseType ==
          NotificationResponseType.selectedNotificationAction) {
        // Action button was tapped - handle quick actions directly
        final actionId = response.actionId;
        if (actionId != null &&
            actionId.startsWith(_counterpartyActionPrefix)) {
          await _handleCounterpartyInputAction(
            actionId,
            response.input,
            response.id,
          );
          return;
        }
        if (actionId != null && actionId.contains('|cat:')) {
          await _handleQuickCategorizeAction(actionId, response.id);
          return;
        }
        if (actionId != null && actionId.startsWith('fp|')) {
          await _handleFailedParseReviewAction(actionId, response.id);
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

  Future<void> _handleQuickCategorizeAction(
      String actionId, int? notificationId) async {
    try {
      await ensureInitialized();
      // Parse: tx:<reference>|cat:<categoryId>
      final parts = actionId.split('|cat:');
      if (parts.length != 2) return;

      final reference =
          Uri.decodeComponent(parts[0].substring(3)); // Remove 'tx:'
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
        transaction.copyWith(
          categoryId: categoryId,
          categoryIds: <int>[categoryId],
        ),
        skipAutoCategorization: true,
      );

      if (kDebugMode) {
        print('debug: Quick categorize: saved successfully');
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
      BackgroundRefreshSignalService.notifyDataChanged();
    } catch (e) {
      if (kDebugMode) {
        print('debug: Quick categorize failed: $e');
      }
    }
  }

  Future<void> _handleCounterpartyInputAction(
    String actionId,
    String? input,
    int? notificationId,
  ) async {
    try {
      await ensureInitialized();

      if (!actionId.startsWith(_counterpartyActionPrefix)) return;

      final submittedName = input?.trim();
      if (submittedName == null || submittedName.isEmpty) {
        if (kDebugMode) {
          print('debug: Counterparty input skipped: empty input');
        }
        return;
      }

      final reference = Uri.decodeComponent(
        actionId.substring(_counterpartyActionPrefix.length),
      );
      if (reference.trim().isEmpty) return;

      final txRepo = TransactionRepository();
      final transaction = await txRepo.getTransactionByReference(reference);

      if (transaction == null) {
        if (kDebugMode) {
          print('debug: Counterparty input: transaction not found');
        }
        return;
      }

      final updated = transaction.type == 'CREDIT'
          ? transaction.copyWith(creditor: submittedName)
          : transaction.copyWith(receiver: submittedName);

      await txRepo.saveTransaction(
        updated,
        skipAutoCategorization: true,
      );

      await WidgetService.refreshWidget();
      BackgroundRefreshSignalService.notifyDataChanged();
      await showTransactionNotification(
        transaction: updated,
        bankId: updated.bankId,
        ignoreEnabledCheck: true,
        recordHistory: false,
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Counterparty input failed: $e');
      }
    }
  }

  Future<void> _handleFailedParseReviewAction(
    String actionId,
    int? notificationId,
  ) async {
    try {
      await ensureInitialized();
      final parts = actionId.split('|');
      if (parts.length != 3 || parts[0] != 'fp') return;

      final decision = parts[1];
      final candidateId = parts[2];
      if (candidateId.trim().isEmpty) return;

      if (decision == 'yes') {
        await FailedParseReviewService.instance.confirmCandidate(candidateId);
        BackgroundRefreshSignalService.notifyDataChanged();
      } else {
        await FailedParseReviewService.instance.discardCandidate(candidateId);
      }

      if (notificationId != null) {
        await _plugin.cancel(notificationId);
      }
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed parse review action failed: $e');
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

    if (raw == _sharedExpensesPayload) {
      return const OpenSharedExpensesIntent();
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
        final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
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
    bool ignoreEnabledCheck = false,
    bool recordHistory = true,
  }) async {
    try {
      await ensureInitialized();

      if (!ignoreEnabledCheck) {
        final enabled = await NotificationSettingsService.instance
            .isTransactionNotificationsEnabled();
        if (!enabled) {
          if (kDebugMode) {
            print(
                'debug: Transaction notification skipped — disabled in settings');
          }
          return;
        }
      }

      final bank = _findBank(bankId);
      final title = _buildTitle(bank, transaction);
      final categoryLabel = await _categoryLabelForTransaction(transaction);
      final body = _buildBody(
        transaction,
        categoryLabel: categoryLabel,
      );

      final id = _notificationId(transaction);
      final payload = 'tx:${Uri.encodeComponent(transaction.reference)}';

      final actions = await _buildTransactionActions(transaction);
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
      if (recordHistory) {
        await _recordHistory(
          channel: _transactionChannelId,
          title: title,
          body: body,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show transaction notification: $e');
      }
    }
  }

  Future<bool> showTestTransactionNotification() async {
    try {
      final transaction = Transaction(
        amount: 123.0,
        reference: 'test_transaction_notification_cash',
        note: 'Test transaction notification',
        time: DateTime.now().toIso8601String(),
        status: 'TEST',
        bankId: CashConstants.bankId,
        type: 'DEBIT',
        accountNumber: CashConstants.defaultAccountNumber,
      );

      await TransactionRepository().saveTransaction(
        transaction,
        skipAutoCategorization: true,
      );
      await WidgetService.refreshWidget();
      BackgroundRefreshSignalService.notifyDataChanged();

      await showTransactionNotification(
        transaction: transaction,
        bankId: transaction.bankId,
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show test transaction notification: $e');
      }
      return false;
    }
  }

  Future<bool> showFailedParseReviewNotification({
    required String reviewId,
    required String bankName,
    required String messageBody,
  }) async {
    try {
      await ensureInitialized();

      final preview = _previewMessage(messageBody);
      await _plugin.show(
        _failedParseReviewNotificationId(reviewId),
        '$bankName transaction review',
        'Was this a transaction?\n$preview',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _failedParseReviewChannelId,
            'Failed parse review',
            channelDescription: 'Prompts to confirm unparsed bank transactions',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(
              'Was this a transaction?\n$preview',
            ),
            actions: [
              AndroidNotificationAction(
                'fp|yes|$reviewId',
                'Yes',
                showsUserInterface: false,
              ),
              AndroidNotificationAction(
                'fp|no|$reviewId',
                'No',
                showsUserInterface: false,
              ),
            ],
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show failed parse review notification: $e');
      }
      return false;
    }
  }

  Future<List<AndroidNotificationAction>> _buildQuickCategoryActions(
    Transaction transaction, {
    int maxCount = 3,
  }) async {
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
        if (actions.length >= maxCount) break;
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

  Future<String?> _categoryLabelForTransaction(Transaction transaction) async {
    final categoryIds = transaction.selectedCategoryIds;
    if (categoryIds.isEmpty) return null;

    try {
      final allCategories = await CategoryRepository().getCategories();
      final labels = <String>[];

      for (final categoryId in categoryIds) {
        models.Category? category;
        for (final candidate in allCategories) {
          if (candidate.id == categoryId) {
            category = candidate;
            break;
          }
        }

        final name = category?.name.trim();
        if (name == null || name.isEmpty || labels.contains(name)) continue;
        labels.add(name);
      }

      if (labels.isEmpty) return null;
      if (labels.length == 1) return labels.first;
      return '${labels.first} +${labels.length - 1}';
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to resolve notification category label: $e');
      }
      return null;
    }
  }

  Future<List<AndroidNotificationAction>> _buildTransactionActions(
    Transaction transaction,
  ) async {
    if (!_needsCounterpartyInput(transaction)) {
      return _buildQuickCategoryActions(transaction);
    }

    final quickActions = await _buildQuickCategoryActions(
      transaction,
      maxCount: 2,
    );

    return <AndroidNotificationAction>[
      _buildCounterpartyInputAction(transaction),
      ...quickActions,
    ];
  }

  AndroidNotificationAction _buildCounterpartyInputAction(
    Transaction transaction,
  ) {
    final role = transaction.type == 'CREDIT' ? 'sender' : 'receiver';
    return AndroidNotificationAction(
      '$_counterpartyActionPrefix${Uri.encodeComponent(transaction.reference)}',
      'add $role',
      allowGeneratedReplies: true,
      showsUserInterface: false,
      cancelNotification: false,
      inputs: <AndroidNotificationActionInput>[
        AndroidNotificationActionInput(
          label: 'Enter $role name',
        ),
      ],
    );
  }

  bool _needsCounterpartyInput(Transaction transaction) {
    return _isMissingOrBankPlaceholder(
      _notificationCounterpartyValue(transaction),
    );
  }

  String? _notificationCounterpartyValue(Transaction transaction) {
    final primary = transaction.type == 'CREDIT'
        ? transaction.creditor?.trim()
        : transaction.receiver?.trim();
    if (primary != null && primary.isNotEmpty) return primary;

    final fallback = transaction.type == 'CREDIT'
        ? transaction.receiver?.trim()
        : transaction.creditor?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;

    return null;
  }

  static bool _isMissingOrBankPlaceholder(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return true;

    final normalized = _normalizeBankToken(trimmed);
    if (normalized.isEmpty) return true;
    return _knownBankTokens.contains(normalized);
  }

  static Set<String> _buildKnownBankTokens() {
    final tokens = <String>{};

    void addToken(String? raw) {
      final normalized = _normalizeBankToken(raw ?? '');
      if (normalized.isNotEmpty) {
        tokens.add(normalized);
      }
    }

    for (final bank in AppConstants.banks) {
      addToken(bank.name);
      addToken(bank.shortName);
      for (final code in bank.codes) {
        addToken(code);
      }
    }

    for (final bank in AllBanksFromAssets.getAllBanks()) {
      addToken(bank.name);
      addToken(bank.shortName);
      for (final code in bank.codes) {
        addToken(code);
      }
    }

    addToken(CashConstants.bankName);
    addToken(CashConstants.bankShortName);

    return tokens;
  }

  static String _normalizeBankToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Future<bool> _showSpendingSummaryNotification({
    required String title,
    required String body,
    required int id,
    required Future<bool> Function() isEnabled,
    bool ignoreEnabledCheck = false,
  }) async {
    try {
      await ensureInitialized();

      if (!ignoreEnabledCheck) {
        final enabled = await isEnabled();
        if (!enabled) return false;
      }

      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _spendingSummaryChannelId,
            'Spending summaries',
            channelDescription: 'Daily, weekly, and monthly spending summaries',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      await _recordHistory(
        channel: _spendingSummaryChannelId,
        title: title,
        body: body,
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show spending summary notification: $e');
      }
      return false;
    }
  }

  Future<bool> showDailySpendingNotification({
    required double amount,
    int id = dailySpendingNotificationId,
    bool ignoreEnabledCheck = false,
  }) async {
    return _showSpendingSummaryNotification(
      title: "Today's spending",
      body: "You've spent ${formatNumberWithComma(amount)} ETB today.",
      id: id,
      ignoreEnabledCheck: ignoreEnabledCheck,
      isEnabled: NotificationSettingsService.instance.isDailySummaryEnabled,
    );
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

  Future<bool> showWeeklySpendingNotification({
    required double amount,
    int id = weeklySpendingNotificationId,
    bool ignoreEnabledCheck = false,
  }) async {
    return _showSpendingSummaryNotification(
      title: "This week's spending",
      body: "You've spent ${formatNumberWithComma(amount)} ETB this week.",
      id: id,
      ignoreEnabledCheck: ignoreEnabledCheck,
      isEnabled: NotificationSettingsService.instance.isWeeklySummaryEnabled,
    );
  }

  Future<bool> showWeeklySpendingTestNotification({
    required double amount,
  }) async {
    return showWeeklySpendingNotification(
      amount: amount,
      id: weeklySpendingTestNotificationId,
      ignoreEnabledCheck: true,
    );
  }

  Future<bool> showMonthlySpendingNotification({
    required double amount,
    int id = monthlySpendingNotificationId,
    bool ignoreEnabledCheck = false,
  }) async {
    return _showSpendingSummaryNotification(
      title: "This month's spending",
      body: "You've spent ${formatNumberWithComma(amount)} ETB this month.",
      id: id,
      ignoreEnabledCheck: ignoreEnabledCheck,
      isEnabled: NotificationSettingsService.instance.isMonthlySummaryEnabled,
    );
  }

  Future<bool> showMonthlySpendingTestNotification({
    required double amount,
  }) async {
    return showMonthlySpendingNotification(
      amount: amount,
      id: monthlySpendingTestNotificationId,
      ignoreEnabledCheck: true,
    );
  }

  Future<void> showAccountSyncProgress({
    required String accountNumber,
    required int bankId,
    required String stage,
    required double progress,
    String? bankLabel,
    bool includePercentInBody = true,
  }) async {
    try {
      await ensureInitialized();

      final clamped = progress.clamp(0.0, 1.0);
      final percent = (clamped * 100).round();
      final title = bankLabel == null ? 'Syncing account' : '$bankLabel sync';
      final maskedAccount = _maskAccountNumber(accountNumber);
      final progressStage = includePercentInBody
          ? _formatSyncProgressStage(stage, percent)
          : stage.trim();
      final body = maskedAccount == null
          ? progressStage
          : '$progressStage - $maskedAccount';

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
            timeoutAfter: 900000,
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

      final title = bankLabel == null
          ? 'Account sync complete'
          : '$bankLabel sync complete';
      final body = message ?? 'Your transactions are up to date.';
      final id = _accountSyncNotificationId(accountNumber, bankId);

      await _plugin.cancel(id);
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _accountSyncChannelId,
            'Account sync',
            channelDescription: 'Background sync of account transactions',
            importance: Importance.low,
            priority: Priority.low,
            autoCancel: true,
            showProgress: false,
            ongoing: false,
            onlyAlertOnce: true,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      await _recordHistory(
        channel: _accountSyncChannelId,
        title: title,
        body: body,
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show account sync completion: $e');
      }
      await dismissAccountSyncNotification(
        accountNumber: accountNumber,
        bankId: bankId,
      );
    }
  }

  Future<void> dismissAccountSyncNotification({
    required String accountNumber,
    required int bankId,
  }) async {
    try {
      await ensureInitialized();
      await _plugin.cancel(_accountSyncNotificationId(accountNumber, bankId));
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to dismiss account sync notification: $e');
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
      await _recordHistory(
        channel: _budgetChannelId,
        title: title,
        body: body,
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show budget alert notification: $e');
      }
    }
  }

  Future<void> showSharedExpenseNudgeNotification({
    required String nudgeId,
    required String groupName,
    required String payeeName,
    required double amount,
  }) async {
    try {
      if (amount <= 0) return;
      await ensureInitialized();

      final cleanPayee = payeeName.trim();
      final cleanGroup = groupName.trim();
      final amountText = 'ETB ${formatNumberWithComma(amount)}';
      final title = cleanPayee.isEmpty
          ? 'Settle up reminder'
          : 'Settle up with $cleanPayee';
      final body = cleanPayee.isEmpty
          ? 'Pay $amountText${cleanGroup.isEmpty ? '' : ' for $cleanGroup'}.'
          : 'Pay $amountText to $cleanPayee'
              '${cleanGroup.isEmpty ? '' : ' for $cleanGroup'}.';

      await _plugin.show(
        _sharedExpenseNudgeNotificationId(nudgeId),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _sharedExpensesChannelId,
            'Shared expenses',
            channelDescription: 'Nudges and reminders from shared expenses',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: _sharedExpensesPayload,
      );
      await _recordHistory(
        channel: _sharedExpensesChannelId,
        title: title,
        body: body,
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show shared expense nudge notification: $e');
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
    for (final bank in AllBanksFromAssets.getAllBanks()) {
      if (bank.id == bankId) {
        return Bank(
          id: bank.id,
          name: bank.name,
          shortName: bank.shortName,
          codes: bank.codes,
          image: bank.image,
        );
      }
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

  static int _failedParseReviewNotificationId(String reviewId) {
    return 200000 + (reviewId.hashCode & 0x7fffffff);
  }

  static int _sharedExpenseNudgeNotificationId(String nudgeId) {
    return 300000 + (nudgeId.hashCode & 0x0fffffff);
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

  String _buildBody(
    Transaction transaction, {
    String? categoryLabel,
  }) {
    final sign = switch (transaction.type) {
      'CREDIT' => '+',
      'DEBIT' => '-',
      _ => '',
    };

    final amount = '${sign}ETB ${formatNumberWithComma(transaction.amount)}';
    if (_needsCounterpartyInput(transaction)) {
      final role = transaction.type == 'CREDIT' ? 'sender' : 'receiver';
      return '$amount • Expand notification to add $role';
    }

    final counterparty = _notificationCounterpartyValue(transaction);
    if (categoryLabel != null) {
      final categoryText = 'Categorized as $categoryLabel';
      if (counterparty == null) {
        return '$amount \u2022 $categoryText';
      }
      return '$amount \u2022 $counterparty \u2022 $categoryText';
    }

    if (counterparty == null) return '$amount • Tap to categorize';
    return '$amount • $counterparty • Tap to categorize';
  }

  String _previewMessage(String messageBody) {
    final collapsed = messageBody.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 180) return collapsed;
    return '${collapsed.substring(0, 177)}...';
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

  static String _formatSyncProgressStage(String stage, int percent) {
    final trimmed = stage.trim();
    final normalizedStage = trimmed.replaceFirst(
      RegExp(r'^Parsing\s+\d+\s*/\s*\d+\s+messages\.\.\.$',
          caseSensitive: false),
      'Parsing messages...',
    );
    if (normalizedStage.isEmpty) {
      return '$percent%';
    }
    return '$normalizedStage ($percent%)';
  }

  Future<List<NotificationHistoryEntry>> getNotificationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawEntries = prefs.getStringList(_historyPrefsKey) ?? <String>[];
      final entries = <NotificationHistoryEntry>[];
      for (final raw in rawEntries) {
        try {
          final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
          entries.add(NotificationHistoryEntry.fromJson(jsonMap));
        } catch (_) {
          // Ignore malformed entries
        }
      }
      return entries;
    } catch (_) {
      return <NotificationHistoryEntry>[];
    }
  }

  Future<void> clearNotificationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyPrefsKey);
  }

  Future<void> _recordHistory({
    required String channel,
    required String title,
    required String body,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawEntries = prefs.getStringList(_historyPrefsKey) ?? <String>[];
      final entry = NotificationHistoryEntry(
        channel: channel,
        title: title,
        body: body,
        sentAt: DateTime.now(),
      );
      rawEntries.insert(0, jsonEncode(entry.toJson()));
      if (rawEntries.length > _maxHistoryEntries) {
        rawEntries.removeRange(_maxHistoryEntries, rawEntries.length);
      }
      await prefs.setStringList(_historyPrefsKey, rawEntries);
    } catch (_) {
      // Ignore persistence failures for notification history.
    }
  }
}

class NotificationHistoryEntry {
  final String channel;
  final String title;
  final String body;
  final DateTime sentAt;

  const NotificationHistoryEntry({
    required this.channel,
    required this.title,
    required this.body,
    required this.sentAt,
  });

  factory NotificationHistoryEntry.fromJson(Map<String, dynamic> json) {
    final channel = (json['channel'] as String?)?.trim();
    final title = (json['title'] as String?)?.trim();
    final body = (json['body'] as String?)?.trim();
    final sentAtRaw = json['sentAt'] as String?;
    return NotificationHistoryEntry(
      channel: (channel == null || channel.isEmpty) ? 'unknown' : channel,
      title: (title == null || title.isEmpty) ? 'Notification' : title,
      body: body ?? '',
      sentAt: DateTime.tryParse(sentAtRaw ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'channel': channel,
      'title': title,
      'body': body,
      'sentAt': sentAt.toIso8601String(),
    };
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
  if (actionId == null) return;

  if (actionId.startsWith(NotificationService._counterpartyActionPrefix)) {
    unawaited(
      _handleCounterpartyInputFromBackground(
        actionId,
        response.input,
        response.id,
      ),
    );
    return;
  }

  if (actionId.contains('|cat:')) {
    unawaited(_handleQuickCategorizeFromBackground(actionId, response.id));
    return;
  }

  if (actionId.startsWith('fp|')) {
    unawaited(_handleFailedParseReviewFromBackground(actionId, response.id));
  }
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

Future<void> _handleCounterpartyInputFromBackground(
  String actionId,
  String? input,
  int? notificationId,
) async {
  await WidgetService.initialize();
  await NotificationService.instance._handleCounterpartyInputAction(
    actionId,
    input,
    notificationId,
  );
}

Future<void> _handleFailedParseReviewFromBackground(
  String actionId,
  int? notificationId,
) async {
  await NotificationService.instance._handleFailedParseReviewAction(
    actionId,
    notificationId,
  );
}
