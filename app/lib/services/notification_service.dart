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
import 'package:totals/models/loan_debt_entry.dart';
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
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _transactionChannelId = 'transactions';
  static const String _failedParseReviewChannelId = 'failed_parse_review';
  static const String _spendingSummaryChannelId = 'spending_summaries';
  static const String _accountSyncChannelId = 'account_sync';
  static const String _accountSyncCompleteChannelId = 'account_sync_complete';
  static const String _budgetChannelId = 'budgets';
  static const String _sharedExpensesChannelId = 'shared_expenses';
  static const String _loanDebtRemindersChannelId = 'loan_debt_reminders';
  static const String _dataSyncChannelId = 'data_sync';
  static const String _historyPrefsKey = 'notification_history_v1';
  static const String _counterpartyActionPrefix = 'txname:';
  static const String _sharedExpensesPayload = 'shared_expenses';
  static const String _sharedExpensesPayloadPrefix = 'shared_expenses:';
  static const String _accountReparseResultPayloadPrefix =
      'account_reparse_result:';
  static const int _maxHistoryEntries = 200;
  static const int dailySpendingNotificationId = 9001;
  static const int dailySpendingTestNotificationId = 9002;
  static const int weeklySpendingNotificationId = 9003;
  static const int weeklySpendingTestNotificationId = 9004;
  static const int monthlySpendingNotificationId = 9005;
  static const int monthlySpendingTestNotificationId = 9006;
  static const int dataSyncResultNotificationId = 9008;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final Set<String> _knownBankTokens = _buildKnownBankTokens();

  bool _initialized = false;
  bool _permissionRequestInProgress = false;

  static String accountReparseResultPayload(String resultId) {
    return '$_accountReparseResultPayloadPrefix${Uri.encodeComponent(resultId)}';
  }

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
        _accountSyncCompleteChannelId,
        'Account sync results',
        description: 'Completion summaries for account transaction syncs',
        importance: Importance.defaultImportance,
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
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _loanDebtRemindersChannelId,
        'Loan and debt reminders',
        description: 'Return date reminders for loans and debts',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _dataSyncChannelId,
        'Data Sync',
        description: 'Results of syncing your data to your backend',
        importance: Importance.defaultImportance,
      ),
    );

    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    _handleNotificationResponse(response);
  }

  Future<void> _handleNotificationResponse(
    NotificationResponse response,
  ) async {
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
    String actionId,
    int? notificationId,
  ) async {
    try {
      await ensureInitialized();
      // Parse: tx:<reference>|cat:<categoryId>
      final parts = actionId.split('|cat:');
      if (parts.length != 2) return;

      final reference = Uri.decodeComponent(
        parts[0].substring(3),
      ); // Remove 'tx:'
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

      await txRepo.saveTransaction(updated, skipAutoCategorization: true);

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

    if (raw.startsWith(_sharedExpensesPayloadPrefix)) {
      final groupId = Uri.decodeComponent(
        raw.substring(_sharedExpensesPayloadPrefix.length),
      ).trim();
      return OpenSharedExpensesIntent(
        groupId: groupId.isEmpty ? null : groupId,
      );
    }

    if (raw.startsWith(_accountReparseResultPayloadPrefix)) {
      final resultId = Uri.decodeComponent(
        raw.substring(_accountReparseResultPayloadPrefix.length),
      ).trim();
      if (resultId.isEmpty) return null;
      return OpenAccountReparseResultIntent(resultId);
    }

    return null;
  }

  String _sharedExpensesNotificationPayload(String? groupId) {
    final trimmed = groupId?.trim();
    if (trimmed == null || trimmed.isEmpty) return _sharedExpensesPayload;
    return '$_sharedExpensesPayloadPrefix${Uri.encodeComponent(trimmed)}';
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

  Future<bool> requestPermissionsIfNeeded() async {
    if (_permissionRequestInProgress) {
      return arePermissionsGranted();
    }

    try {
      _permissionRequestInProgress = true;
      await ensureInitialized();

      if (kIsWeb) return true;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await androidPlugin?.requestNotificationsPermission();
        if (granted != null) return granted;
        final status = await Permission.notification.request();
        return status.isGranted;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final granted = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted == true;
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('debug: Notification permission request failed: $e');
      }
      return false;
    } finally {
      _permissionRequestInProgress = false;
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
              'debug: Transaction notification skipped — disabled in settings',
            );
          }
          return;
        }
      }

      final bank = _findBank(bankId);
      final title = _buildTitle(bank, transaction);
      final categoryLabel = await _categoryLabelForTransaction(transaction);
      final body = _buildBody(transaction, categoryLabel: categoryLabel);

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

  Future<void> dismissTransactionNotification(Transaction transaction) async {
    try {
      await ensureInitialized();
      await _plugin.cancel(_notificationId(transaction));
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to dismiss transaction notification: $e');
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
        ownerAccountNumber: CashConstants.defaultAccountNumber,
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
        actions.add(
          AndroidNotificationAction(
            actionPayload,
            cat.name,
            showsUserInterface: false,
          ),
        );
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
        AndroidNotificationActionInput(label: 'Enter $role name'),
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

  /// Posts a single, self-replacing notification summarizing a Data Sync run.
  /// A failure raises importance; a clean success updates quietly.
  Future<void> showDataSyncResult({
    required int sent,
    required int failed,
    int retried = 0,
    String? destination,
  }) async {
    if (sent <= 0 && failed <= 0 && retried <= 0) return;
    try {
      await ensureInitialized();
      final dest = (destination ?? '').trim();
      final suffix = dest.isEmpty ? '' : ' → $dest';
      final String title;
      final String body;
      if (failed > 0) {
        title = 'Data Sync: $failed failed';
        body = sent > 0
            ? '$sent sent, $failed failed$suffix'
            : "$failed record(s) couldn't be sent$suffix";
      } else if (retried > 0) {
        title = 'Data Sync will retry';
        body = sent > 0
            ? '$sent sent, $retried queued for retry$suffix'
            : '$retried record(s) queued for retry$suffix';
      } else {
        title = 'Data Sync complete';
        body = '$sent record(s) synced$suffix';
      }
      await _plugin.show(
        dataSyncResultNotificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _dataSyncChannelId,
            'Data Sync',
            channelDescription: 'Results of syncing your data to your backend',
            importance:
                failed > 0 ? Importance.high : Importance.defaultImportance,
            priority: failed > 0 ? Priority.high : Priority.defaultPriority,
            showProgress: false,
            ongoing: false,
            onlyAlertOnce: failed == 0,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  Future<void> showDataSyncProgress({
    required int processed,
    required int total,
    required int sent,
    required int failed,
    String? reason,
  }) async {
    if (total <= 0) return;
    try {
      await ensureInitialized();
      final safeTotal = total < 1 ? 1 : total;
      final safeProcessed = processed.clamp(0, safeTotal).toInt();
      final percent = ((safeProcessed / safeTotal) * 100).round();
      final retrying = safeProcessed - sent - failed;
      final detail = <String>[
        '$safeProcessed/$safeTotal processed',
        if (sent > 0) '$sent sent',
        if (failed > 0) '$failed failed',
        if (retrying > 0) '$retrying retrying',
      ].join(' · ');

      await _plugin.show(
        dataSyncResultNotificationId,
        'Data Sync $percent%',
        detail,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _dataSyncChannelId,
            'Data Sync',
            channelDescription: 'Progress and results for Data Sync',
            importance: Importance.low,
            priority: Priority.low,
            showProgress: true,
            maxProgress: 100,
            progress: percent,
            ongoing: safeProcessed < safeTotal,
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
    } catch (_) {}
  }

  Future<void> dismissDataSyncNotification() async {
    try {
      await ensureInitialized();
      await _plugin.cancel(dataSyncResultNotificationId);
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to dismiss data sync notification: $e');
      }
    }
  }

  Future<void> showAccountSyncProgress({
    required String accountNumber,
    String? accountLabel,
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
      final maskedAccount = accountLabel?.trim().isNotEmpty == true
          ? accountLabel!.trim()
          : _maskAccountNumber(accountNumber);
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
    String? payload,
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
            _accountSyncCompleteChannelId,
            'Account sync results',
            channelDescription:
                'Completion summaries for account transaction syncs',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            autoCancel: true,
            showProgress: false,
            ongoing: false,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );
      await _recordHistory(
        channel: _accountSyncCompleteChannelId,
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
      await _recordHistory(channel: _budgetChannelId, title: title, body: body);
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show budget alert notification: $e');
      }
    }
  }

  Future<void> scheduleLoanDebtReturnReminder({
    required String transactionReference,
    required String personName,
    required LoanDebtDirection direction,
    required DateTime returnDate,
    double? amount,
  }) async {
    try {
      final reference = transactionReference.trim();
      if (reference.isEmpty) return;

      final scheduledDate = _loanDebtReminderScheduledDate(returnDate);
      final id = _loanDebtReturnReminderNotificationId(reference);
      if (scheduledDate == null) {
        await cancelLoanDebtReturnReminder(reference);
        return;
      }

      final enabled = await NotificationSettingsService.instance
          .isLoanDebtReturnRemindersEnabled();
      if (!enabled) {
        await cancelLoanDebtReturnReminder(reference);
        return;
      }

      await ensureInitialized();

      final content = _buildLoanDebtReminderContent(
        personName: personName,
        direction: direction,
        amount: amount,
      );

      await _plugin.zonedSchedule(
        id,
        content.title,
        content.body,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _loanDebtRemindersChannelId,
            'Loan and debt reminders',
            channelDescription: 'Return date reminders for loans and debts',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'loan_debt:${Uri.encodeComponent(reference)}',
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to schedule loan/debt reminder: $e');
      }
    }
  }

  Future<bool> showLoanDebtReturnReminderNow({
    required String transactionReference,
    required String personName,
    required LoanDebtDirection direction,
    double? amount,
    bool useTestId = false,
    bool ignoreEnabledCheck = false,
  }) async {
    try {
      final reference = transactionReference.trim();
      if (reference.isEmpty) return false;

      if (!ignoreEnabledCheck) {
        final enabled = await NotificationSettingsService.instance
            .isLoanDebtReturnRemindersEnabled();
        if (!enabled) return false;
      }

      await ensureInitialized();

      final content = _buildLoanDebtReminderContent(
        personName: personName,
        direction: direction,
        amount: amount,
      );
      final id = useTestId
          ? _loanDebtReturnReminderTestNotificationId(reference)
          : _loanDebtReturnReminderNotificationId(reference);

      await _plugin.show(
        id,
        content.title,
        content.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _loanDebtRemindersChannelId,
            'Loan and debt reminders',
            channelDescription: 'Return date reminders for loans and debts',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: 'loan_debt:${Uri.encodeComponent(reference)}',
      );
      await _recordHistory(
        channel: _loanDebtRemindersChannelId,
        title: content.title,
        body: content.body,
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show loan/debt reminder: $e');
      }
      return false;
    }
  }

  Future<void> cancelLoanDebtReturnReminder(String transactionReference) async {
    try {
      final reference = transactionReference.trim();
      if (reference.isEmpty) return;
      await ensureInitialized();
      await _plugin.cancel(_loanDebtReturnReminderNotificationId(reference));
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to cancel loan/debt reminder: $e');
      }
    }
  }

  Future<void> showSharedExpenseNudgeNotification({
    required String nudgeId,
    required String groupName,
    required String payeeName,
    required double amount,
    String? groupId,
  }) async {
    try {
      if (amount <= 0) return;
      final enabled = await NotificationSettingsService.instance
          .isSharedExpenseNotificationsEnabled();
      if (!enabled) return;
      await ensureInitialized();

      final cleanPayee = payeeName.trim();
      final cleanGroup = groupName.trim();
      final amountText = 'ETB ${formatNumberWithComma(amount)}';
      final title = cleanPayee.isEmpty
          ? 'Settle up reminder'
          : 'Settle up with $cleanPayee';
      final body = cleanPayee.isEmpty
          ? 'Pay $amountText${cleanGroup.isEmpty ? '' : ' on $cleanGroup'}.'
          : 'Pay $amountText to $cleanPayee'
              '${cleanGroup.isEmpty ? '' : ' on $cleanGroup'}.';

      await _plugin.show(
        _sharedExpenseNotificationId(nudgeId),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _sharedExpensesChannelId,
            'Shared expenses',
            channelDescription: 'Nudges and reminders from shared expenses',
            importance: Importance.high,
            priority: Priority.high,
            onlyAlertOnce: true,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: _sharedExpensesNotificationPayload(groupId),
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

  Future<void> showSharedExpenseEventNotification({
    required String eventId,
    required String title,
    required String body,
    String? groupId,
  }) async {
    try {
      final enabled = await NotificationSettingsService.instance
          .isSharedExpenseNotificationsEnabled();
      if (!enabled) return;
      await ensureInitialized();

      await _plugin.show(
        _sharedExpenseNotificationId(eventId),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _sharedExpensesChannelId,
            'Shared expenses',
            channelDescription: 'Notifications from shared expenses',
            importance: Importance.high,
            priority: Priority.high,
            onlyAlertOnce: true,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: _sharedExpensesNotificationPayload(groupId),
      );
      await _recordHistory(
        channel: _sharedExpensesChannelId,
        title: title,
        body: body,
      );
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to show shared expense event notification: $e');
      }
    }
  }

  /// Removes generic shared-expense fallbacks left by older app versions.
  Future<void> dismissLegacySharedExpenseFallbacks() async {
    try {
      await ensureInitialized();
      final activeNotifications = await _plugin.getActiveNotifications();
      for (final notification in activeNotifications) {
        final id = notification.id;
        if (id == null) continue;
        if (notification.title?.trim() != 'Shared Expenses has a new update') {
          continue;
        }
        await _plugin.cancel(id, tag: notification.tag);
      }
    } catch (e) {
      if (kDebugMode) {
        print('debug: Failed to dismiss legacy shared expense fallback: $e');
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

  static int _sharedExpenseNotificationId(String eventId) {
    return 300000 + _stableNotificationHash(eventId);
  }

  @visibleForTesting
  static int sharedExpenseNotificationIdForTesting(String eventId) {
    return _sharedExpenseNotificationId(eventId);
  }

  static int _loanDebtReturnReminderNotificationId(String reference) {
    return 700000 + _stableNotificationHash(reference);
  }

  static int _loanDebtReturnReminderTestNotificationId(String reference) {
    return 1000000000 + _stableNotificationHash(reference);
  }

  static int _stableNotificationHash(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = ((hash * 31) + unit) & 0x0fffffff;
    }
    return hash;
  }

  static tz.TZDateTime? _loanDebtReminderScheduledDate(DateTime returnDate) {
    _configureLocalTimeZone();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final localReturnDate = returnDate.toLocal();
    final dueDay = DateTime(
      localReturnDate.year,
      localReturnDate.month,
      localReturnDate.day,
    );
    if (dueDay.isBefore(today)) return null;

    var scheduled = DateTime(dueDay.year, dueDay.month, dueDay.day, 9);
    if (!scheduled.isAfter(now)) {
      scheduled = now.add(const Duration(minutes: 1));
    }

    return tz.TZDateTime(
      tz.local,
      scheduled.year,
      scheduled.month,
      scheduled.day,
      scheduled.hour,
      scheduled.minute,
      scheduled.second,
    );
  }

  static void _configureLocalTimeZone() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset.inMilliseconds;
    final abbreviation =
        now.timeZoneName.trim().isEmpty ? 'LOCAL' : now.timeZoneName.trim();
    tz.setLocalLocation(
      tz.Location('device_local_$offset', [
        tz.minTime
      ], [
        0
      ], [
        tz.TimeZone(offset, isDst: false, abbreviation: abbreviation),
      ]),
    );
  }

  static String? _formatLoanDebtReminderAmount(double? amount) {
    if (amount == null || !amount.isFinite || amount <= 0) return null;
    return 'ETB ${formatNumberWithComma(amount.abs())}';
  }

  static ({String title, String body}) _buildLoanDebtReminderContent({
    required String personName,
    required LoanDebtDirection direction,
    required double? amount,
  }) {
    final cleanName =
        personName.trim().isEmpty ? 'this person' : personName.trim();
    final amountText = _formatLoanDebtReminderAmount(amount);
    final borrowed = direction == LoanDebtDirection.borrowed;
    final amountPhrase = amountText == null ? '' : ' $amountText';
    return (
      title: borrowed ? 'Debt due today' : 'Loan due today',
      body: borrowed
          ? "You're due to pay $cleanName$amountPhrase today."
          : '$cleanName is due to pay you$amountPhrase today.',
    );
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

  String _buildBody(Transaction transaction, {String? categoryLabel}) {
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
      RegExp(
        r'^Parsing\s+\d+\s*/\s*\d+\s+messages\.\.\.$',
        caseSensitive: false,
      ),
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
