import 'dart:async';
import 'dart:ui';

import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/pattern_parser.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/failed_parse.dart';
import 'package:totals/repositories/failed_parse_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:totals/services/failed_parse_review_service.dart';
import 'package:totals/services/fallback_sms_parser.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/budget_alert_service.dart';
import 'package:totals/services/background_refresh_signal_service.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/utils/bank_sender_matcher.dart';
import 'package:totals/utils/sms_transaction_source.dart';
import 'package:totals/utils/transaction_duplicate_detector.dart';

enum ParseStatus {
  success,
  noBank,
  noPattern,
  duplicate,
  unregisteredBank,
}

class ParseResult {
  final ParseStatus status;
  final Transaction? transaction;
  final String? reason;

  const ParseResult({
    required this.status,
    this.transaction,
    this.reason,
  });

  bool get isResolved => status == ParseStatus.success;
}

class TodaySmsSyncResult {
  final int processed;
  final int added;
  final int duplicates;
  final int noPattern;
  final int skipped;
  final int errors;
  final bool permissionDenied;

  const TodaySmsSyncResult({
    this.processed = 0,
    this.added = 0,
    this.duplicates = 0,
    this.noPattern = 0,
    this.skipped = 0,
    this.errors = 0,
    this.permissionDenied = false,
  });

  bool get hasBankMessages => processed > 0;
}

// Top-level function for background execution
@pragma('vm:entry-point')
onBackgroundMessage(SmsMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    print("debug: BG: Handler started.");

    final String? address = message.address;
    print("debug: BG: Address: '$address'");

    final String? body = message.body;
    if (body == null) {
      print("debug: BG: Body is null. Exiting.");
      return;
    }

    print("debug: BG: Checking if relevant...");
    if (await SmsService.isRelevantMessage(
      address,
      allowRemoteBankFetch: false,
    )) {
      print("debug: BG: Message IS relevant. Processing...");
      final receivedAt = message.date == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(message.date!);
      final transaction = await SmsService.processMessage(body, address!,
          notifyUser: true,
          messageDate: receivedAt,
          allowRemoteBankFetch: false,
          allowRemotePatternFetch: false);
      if (transaction != null) {
        BackgroundRefreshSignalService.notifyDataChanged();
      }
      print("debug: BG: Processing finished.");
    } else {
      print("debug: BG: Message NOT relevant.");
    }
  } catch (e, stack) {
    print("debug: BG: CRITICAL ERROR: $e");
    print(stack);
  }
}

class SmsService {
  final Telephony _telephony = Telephony.instance;
  static final BankConfigService _bankConfigService = BankConfigService();
  static List<Bank>? _cachedBanks;
  static bool _cachedBanksLoadedWithRemoteFetch = false;
  static const String _atmCashCutoffPrefPrefix =
      'atm_cash_transfer_cutoff_iso_profile_';
  static const String _lastSmsCatchupPrefPrefix =
      'sms_last_catchup_epoch_ms_profile_';
  static const int _dashenBankId = 4;
  static const int _canonicalInboxLookupAttempts = 3;
  static const Duration _canonicalInboxLookupDelay =
      Duration(milliseconds: 750);
  static const Duration _canonicalInboxLookupWindow = Duration(minutes: 2);
  static const Duration _canonicalInboxLookupFutureSlack =
      Duration(seconds: 15);

  // Callback for foreground-only UI updates.
  ValueChanged<Transaction>? onTransactionSaved;

  void _registerIncomingSmsListener() {
    _telephony.listenIncomingSms(
      onNewMessage: _handleForegroundMessage,
      onBackgroundMessage: onBackgroundMessage,
    );
  }

  Future<void> init() async {
    final bool? result = await _telephony.requestSmsPermissions;
    if (result != null && result) {
      _registerIncomingSmsListener();
    } else {
      print("debug: SMS Permission denied");
    }
  }

  void _handleForegroundMessage(SmsMessage message) async {
    print("debug: Foreground message from ${message.address}: ${message.body}");
    if (message.body == null) return;

    try {
      if (await SmsService.isRelevantMessage(message.address)) {
        final receivedAt = message.date == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(message.date!);
        final tx = await SmsService.processMessage(
            message.body!, message.address!,
            notifyUser: true, messageDate: receivedAt);
        if (tx != null && onTransactionSaved != null) {
          onTransactionSaved!(tx);
        }
      }
    } catch (e) {
      print("debug: Error processing foreground message: $e");
    }
  }

  Future<TodaySmsSyncResult> syncTodayBankSms() async {
    final bool? permissionGranted = await _telephony.requestSmsPermissions;
    if (permissionGranted != true) {
      return const TodaySmsSyncResult(permissionDenied: true);
    }

    _registerIncomingSmsListener();
    await _getAtmCashTransferCutoff();

    final scanEndedAt = DateTime.now();
    final result = await _syncBankSmsRange(
      start: _startOfDay(scanEndedAt),
      includeStart: true,
      end: scanEndedAt,
      includeEnd: true,
    );
    if (!result.permissionDenied && result.errors == 0) {
      await _setLastSmsCatchupAt(scanEndedAt);
    }
    return result;
  }

  Future<TodaySmsSyncResult> syncMissedBankSmsSinceLastCatchup() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const TodaySmsSyncResult();
    }

    final permissionStatus = await Permission.sms.status;
    if (!permissionStatus.isGranted) {
      return const TodaySmsSyncResult(permissionDenied: true);
    }

    await _getAtmCashTransferCutoff();

    final scanEndedAt = DateTime.now();
    final startOfDay = _startOfDay(scanEndedAt);
    final lastCatchupAt = await _getLastSmsCatchupAt();
    final hasCursor = lastCatchupAt != null &&
        lastCatchupAt.isAfter(startOfDay) &&
        !lastCatchupAt.isAfter(scanEndedAt);

    final result = await _syncBankSmsRange(
      start: hasCursor ? lastCatchupAt : startOfDay,
      includeStart: !hasCursor,
      end: scanEndedAt,
      includeEnd: true,
    );

    if (!result.permissionDenied && result.errors == 0) {
      await _setLastSmsCatchupAt(scanEndedAt);
    }

    return result;
  }

  Future<TodaySmsSyncResult> _syncBankSmsRange({
    required DateTime start,
    required bool includeStart,
    required DateTime end,
    required bool includeEnd,
  }) async {
    final lowerBound = start.millisecondsSinceEpoch.toString();
    final upperBound = end.millisecondsSinceEpoch.toString();

    final startFilter = includeStart
        ? SmsFilter.where(SmsColumn.DATE).greaterThanOrEqualTo(lowerBound)
        : SmsFilter.where(SmsColumn.DATE).greaterThan(lowerBound);
    final filter = includeEnd
        ? startFilter.and(SmsColumn.DATE).lessThanOrEqualTo(upperBound)
        : startFilter.and(SmsColumn.DATE).lessThan(upperBound);

    final messages = await _telephony.getInboxSms(
      filter: filter,
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    return _processInboxMessages(messages);
  }

  Future<TodaySmsSyncResult> _processInboxMessages(
    List<SmsMessage> messages,
  ) async {
    int processed = 0;
    int added = 0;
    int duplicates = 0;
    int noPattern = 0;
    int skipped = 0;
    int errors = 0;

    for (final message in messages) {
      final body = message.body;
      final address = message.address;
      if (body == null || address == null) {
        skipped++;
        continue;
      }

      final bank = await getRelevantBank(address);
      if (bank == null) {
        skipped++;
        continue;
      }

      processed++;
      final messageDate = message.date != null
          ? DateTime.fromMillisecondsSinceEpoch(message.date!)
          : null;

      try {
        final result = await _processMessageInternal(
          body,
          address,
          messageDate: messageDate,
          sourceMessageId: message.id,
          notifyUser: false,
          recordFailure: false,
        );
        switch (result.status) {
          case ParseStatus.success:
            added++;
            break;
          case ParseStatus.duplicate:
            duplicates++;
            break;
          case ParseStatus.noPattern:
            noPattern++;
            break;
          case ParseStatus.noBank:
          case ParseStatus.unregisteredBank:
            skipped++;
            break;
        }
      } catch (e) {
        errors++;
        print("debug: Error processing SMS: $e");
      }
    }

    return TodaySmsSyncResult(
      processed: processed,
      added: added,
      duplicates: duplicates,
      noPattern: noPattern,
      skipped: skipped,
      errors: errors,
    );
  }

  /// Checks if the message address matches any of our known bank codes.
  static Future<bool> isRelevantMessage(
    String? address, {
    bool allowRemoteBankFetch = true,
  }) async {
    if (address == null) return false;
    final bank = await getRelevantBank(
      address,
      allowRemoteFetch: allowRemoteBankFetch,
    );
    return bank != null;
  }

  /// Identifies the bank associated with the sender address.
  static Future<Bank?> getRelevantBank(
    String? address, {
    bool allowRemoteFetch = true,
  }) async {
    if (address == null) return null;

    // Fetch banks from database (with static caching)
    if (_cachedBanks == null ||
        (allowRemoteFetch && !_cachedBanksLoadedWithRemoteFetch)) {
      _cachedBanks =
          await _bankConfigService.getBanks(allowRemoteFetch: allowRemoteFetch);
      _cachedBanksLoadedWithRemoteFetch = allowRemoteFetch;
    }

    return findBestBankForSenderAddress(address, _cachedBanks!);
  }

  static double sanitizeAmount(String? raw) {
    if (raw == null) return 0.0;

    String cleaned = raw.trim();

    // Remove all characters except digits and decimal points
    cleaned = cleaned.replaceAll(RegExp(r'[^0-9.]'), '');

    // If multiple dots exist, keep only the first valid decimal
    int firstDot = cleaned.indexOf('.');
    if (firstDot != -1) {
      // Remove all dots after the first one
      cleaned = cleaned.substring(0, firstDot + 1) +
          cleaned.substring(firstDot + 1).replaceAll('.', '');
    }

    // If the string ends with a dot, add a zero → "12." → "12.0"
    if (cleaned.endsWith('.')) {
      cleaned = cleaned + '0';
    }

    // If empty after cleaning, return 0
    if (cleaned.isEmpty) return 0.0;

    // Safe parse
    return double.tryParse(cleaned) ?? 0.0;
  }

  static Future<void> _recordFailedParse({
    required String address,
    required String body,
    required String reason,
    DateTime? timestamp,
    int? bankId,
  }) async {
    if (bankId != null && !(await _hasRegisteredAccountForBank(bankId))) return;

    await FailedParseRepository().add(
      FailedParse(
        address: address,
        body: body,
        reason: reason,
        timestamp: (timestamp ?? DateTime.now()).toIso8601String(),
      ),
    );
  }

  static bool _looksLikeTransactionMessage(String messageBody) {
    final normalized =
        messageBody.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return false;

    const transactionKeywords = <String>[
      'debited',
      'credited',
      'deposit',
      'withdraw',
      'withdrawal',
      'transfer',
      'transferred',
      'payment',
      'paid',
      'purchase',
      'received',
      'sent',
      'spent',
      'cash out',
      'cashout',
      'atm',
      'trx',
      'txn',
      'transaction',
    ];
    const supportingKeywords = <String>[
      'balance',
      'amount',
      'amt',
      'available balance',
      'ref',
      'reference',
      'account',
      'ac',
      'a/c',
      'card',
      'merchant',
      'pos',
      'wallet',
      'etb',
      'birr',
      'br',
    ];

    final hasTransactionKeyword = _containsAny(normalized, transactionKeywords);
    final hasSupportingKeyword = _containsAny(normalized, supportingKeywords);
    final hasMonetaryAmount = RegExp(
      r'(?:etb|birr|br)\s*\d|\d[\d,]*(?:\.\d{1,2})?\s*(?:etb|birr|br)',
      caseSensitive: false,
    ).hasMatch(messageBody);

    return hasTransactionKeyword && (hasSupportingKeyword || hasMonetaryAmount);
  }

  static Future<bool> _hasRegisteredAccountForBank(int bankId) async {
    final accounts = await AccountRepository().getAccounts();
    return accounts.any((account) => account.bank == bankId);
  }

  static bool _containsAny(String text, List<String> values) {
    for (final value in values) {
      if (text.contains(value)) return true;
    }
    return false;
  }

  static String _normalizeSmsComparisonText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static Set<String> _smsComparisonTokens(String value) {
    return _normalizeSmsComparisonText(value)
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 2)
        .toSet();
  }

  static bool _bodiesLookRelated(String originalBody, String inboxBody) {
    final original = _normalizeSmsComparisonText(originalBody);
    final inbox = _normalizeSmsComparisonText(inboxBody);
    if (original.isEmpty || inbox.isEmpty) return false;
    if (original == inbox) return originalBody.trim() != inboxBody.trim();
    if (inbox.contains(original) || original.contains(inbox)) return true;

    final originalTokens = _smsComparisonTokens(originalBody);
    final inboxTokens = _smsComparisonTokens(inboxBody);
    if (originalTokens.isEmpty || inboxTokens.isEmpty) return false;

    var overlap = 0;
    for (final token in originalTokens) {
      if (inboxTokens.contains(token)) overlap++;
    }

    final smallerSetSize = originalTokens.length < inboxTokens.length
        ? originalTokens.length
        : inboxTokens.length;
    return overlap / smallerSetSize >= 0.7;
  }

  static int _canonicalInboxCandidateScore({
    required SmsMessage message,
    required String originalSenderAddress,
    required String originalBody,
    required DateTime anchor,
    required Bank bank,
    required List<Bank> banks,
  }) {
    final body = message.body;
    final address = message.address;
    if (body == null || address == null) return -1;
    if (!_bodiesLookRelated(originalBody, body)) return -1;

    final normalizedOriginalSender =
        normalizeBankSenderToken(originalSenderAddress);
    final normalizedCandidateSender = normalizeBankSenderToken(address);
    final sameSender = normalizedCandidateSender == normalizedOriginalSender;
    final sameBank = sameSender ||
        senderAddressMatchesBank(
          bank,
          address,
          allBanks: banks,
        );
    if (!sameBank) return -1;

    final messageTime = message.date == null
        ? anchor
        : DateTime.fromMillisecondsSinceEpoch(message.date!);
    final distanceMs = messageTime.difference(anchor).inMilliseconds.abs();
    if (distanceMs > _canonicalInboxLookupWindow.inMilliseconds) return -1;

    var score = 0;
    if (sameSender) score += 40;
    if (_looksLikeTransactionMessage(body)) score += 20;
    if (body.length > originalBody.length) score += 10;
    score += 20 -
        ((distanceMs / _canonicalInboxLookupWindow.inMilliseconds) * 20)
            .round();
    return score;
  }

  static Future<SmsMessage?> _findCanonicalInboxCopy({
    required String originalBody,
    required String senderAddress,
    required DateTime? messageDate,
    required Bank bank,
    required List<Bank> banks,
  }) async {
    final anchor = messageDate ?? DateTime.now();
    final lowerBound = anchor
        .subtract(_canonicalInboxLookupWindow)
        .millisecondsSinceEpoch
        .toString();
    final upperBound = DateTime.now()
        .add(_canonicalInboxLookupFutureSlack)
        .millisecondsSinceEpoch
        .toString();
    final filter = SmsFilter.where(SmsColumn.DATE)
        .greaterThanOrEqualTo(lowerBound)
        .and(SmsColumn.DATE)
        .lessThanOrEqualTo(upperBound);

    final messages = await Telephony.instance.getInboxSms(
      columns: const [
        SmsColumn.ID,
        SmsColumn.ADDRESS,
        SmsColumn.BODY,
        SmsColumn.DATE,
      ],
      filter: filter,
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    SmsMessage? best;
    var bestScore = -1;
    for (final message in messages) {
      final score = _canonicalInboxCandidateScore(
        message: message,
        originalSenderAddress: senderAddress,
        originalBody: originalBody,
        anchor: anchor,
        bank: bank,
        banks: banks,
      );
      if (score > bestScore) {
        best = message;
        bestScore = score;
      }
    }

    return best;
  }

  static Future<ParseResult?> _retryCanonicalInboxCopy({
    required String originalBody,
    required String senderAddress,
    required DateTime? messageDate,
    required Bank bank,
    required bool skipDashenExpenseDuplicates,
    required bool skipAutoCategorization,
    required bool allowRemoteBankFetch,
    required bool allowRemotePatternFetch,
  }) async {
    debugPrint(
      "debug: Looking for canonical inbox copy before failed parse review",
    );
    final banks = await _bankConfigService.getBanks(
      allowRemoteFetch: allowRemoteBankFetch,
    );

    for (var attempt = 0; attempt < _canonicalInboxLookupAttempts; attempt++) {
      await Future<void>.delayed(_canonicalInboxLookupDelay);
      final inboxMessage = await _findCanonicalInboxCopy(
        originalBody: originalBody,
        senderAddress: senderAddress,
        messageDate: messageDate,
        bank: bank,
        banks: banks,
      );
      if (inboxMessage?.body == null || inboxMessage?.address == null) {
        continue;
      }

      debugPrint("debug: Retrying parse with canonical inbox SMS copy");
      final inboxDate = inboxMessage!.date == null
          ? messageDate
          : DateTime.fromMillisecondsSinceEpoch(inboxMessage.date!);
      final result = await _processMessageInternal(
        inboxMessage.body!,
        inboxMessage.address!,
        messageDate: inboxDate,
        sourceMessageId: inboxMessage.id,
        notifyUser: false,
        skipDashenExpenseDuplicates: skipDashenExpenseDuplicates,
        skipAutoCategorization: skipAutoCategorization,
        allowRemoteBankFetch: allowRemoteBankFetch,
        allowRemotePatternFetch: allowRemotePatternFetch,
        recordFailure: false,
      );
      if (result.status == ParseStatus.success ||
          result.status == ParseStatus.duplicate) {
        return result;
      }
    }

    return null;
  }

  static Bank? _bankById(List<Bank> banks, int bankId) {
    for (final bank in banks) {
      if (bank.id == bankId) return bank;
    }
    return null;
  }

  static Account? _accountForBank(List<Account> accounts, int bankId) {
    for (final account in accounts) {
      if (account.bank == bankId) return account;
    }
    return null;
  }

  static Account? _maskedAccountMatch(
    List<Account> accounts, {
    required int bankId,
    required String extractedAccount,
    required int? maskPattern,
  }) {
    final trimmedAccount = extractedAccount.trim();
    if (trimmedAccount.isEmpty) return null;

    final suffix = maskPattern != null &&
            maskPattern > 0 &&
            trimmedAccount.length > maskPattern
        ? trimmedAccount.substring(trimmedAccount.length - maskPattern)
        : trimmedAccount;

    for (final account in accounts) {
      if (account.bank != bankId) continue;
      if (account.accountNumber.endsWith(suffix)) return account;
    }
    return null;
  }

  static Future<void> _saveUpdatedAccountBalance(
    AccountRepository accRepo,
    Account account,
    double newBalance,
  ) async {
    final updated = Account(
      accountNumber: account.accountNumber,
      bank: account.bank,
      balance: newBalance,
      accountHolderName: account.accountHolderName,
      settledBalance: account.settledBalance,
      pendingCredit: account.pendingCredit,
      profileId: account.profileId,
    );
    await accRepo.saveAccount(updated);
    print("debug: Account balance updated for ${account.accountHolderName}");
  }

  static bool _isAtmWithdrawal(
    Map<String, dynamic> details,
    String messageBody,
  ) {
    final type = (details['type'] ?? '').toString().toUpperCase();
    if (type != 'DEBIT') return false;

    final description =
        (details['patternDescription'] as String?)?.toLowerCase();
    if (description != null && description.contains('atm')) {
      return true;
    }

    final normalizedBody = messageBody.toLowerCase();
    return normalizedBody.contains('atm') &&
        normalizedBody.contains('withdraw');
  }

  static Future<void> _ensureCashAccount() async {
    final accountRepo = AccountRepository();
    final accounts = await accountRepo.getAccounts();
    final hasCash = accounts.any((a) => a.bank == CashConstants.bankId);
    if (hasCash) return;

    final cashAccount = Account(
      accountNumber: CashConstants.defaultAccountNumber,
      bank: CashConstants.bankId,
      balance: 0.0,
      accountHolderName: CashConstants.defaultAccountHolderName,
    );
    await accountRepo.saveAccount(cashAccount);
  }

  static Future<void> _createCashTransactionForAtmWithdrawal(
    Transaction withdrawal,
    List<Transaction> existingTransactions,
  ) async {
    final bankId = withdrawal.bankId;
    if (bankId == null || bankId == CashConstants.bankId) return;

    if (await _isWithdrawalBeforeCashCutoff(withdrawal)) {
      print(
          "debug: Skipping historical ATM cash transfer for ${withdrawal.reference}");
      return;
    }

    final cashReference = CashConstants.buildAtmReference(withdrawal.reference);
    if (existingTransactions.any((t) => t.reference == cashReference)) {
      return;
    }

    await _ensureCashAccount();
    final currentCashBalance =
        await _currentCashWalletBalance(existingTransactions);

    final cashTransaction = Transaction(
      amount: withdrawal.amount,
      reference: cashReference,
      creditor: 'ATM withdrawal',
      time: withdrawal.time ?? DateTime.now().toIso8601String(),
      bankId: CashConstants.bankId,
      type: 'CREDIT',
      currentBalance:
          (currentCashBalance + withdrawal.amount).toStringAsFixed(2),
      transactionLink: withdrawal.reference,
      accountNumber: CashConstants.defaultAccountNumber,
    );

    await TransactionRepository().saveTransaction(cashTransaction);
  }

  static Future<double> _currentCashWalletBalance(
    List<Transaction> existingTransactions,
  ) async {
    final accountRepo = AccountRepository();
    final accounts = await accountRepo.getAccounts();
    final accountBase = accounts
        .where((a) => a.bank == CashConstants.bankId)
        .fold<double>(0.0, (sum, account) => sum + account.balance);

    final txDelta = existingTransactions
        .where((t) => t.bankId == CashConstants.bankId)
        .fold<double>(0.0, (sum, transaction) {
      if (transaction.type == 'DEBIT') return sum - transaction.amount;
      if (transaction.type == 'CREDIT') return sum + transaction.amount;
      return sum;
    });

    return accountBase + txDelta;
  }

  static Future<bool> _isWithdrawalBeforeCashCutoff(
      Transaction withdrawal) async {
    final withdrawalTime = DateTime.tryParse(withdrawal.time ?? '');
    if (withdrawalTime == null) return false;
    final cutoff = await _getAtmCashTransferCutoff();
    return withdrawalTime.isBefore(cutoff);
  }

  static Future<DateTime> _getAtmCashTransferCutoff() async {
    final profileRepo = ProfileRepository();
    final activeProfileId = await profileRepo.getActiveProfileId();
    final key = activeProfileId != null
        ? '$_atmCashCutoffPrefPrefix$activeProfileId'
        : '${_atmCashCutoffPrefPrefix}default';

    final prefs = await SharedPreferences.getInstance();
    final existingIso = prefs.getString(key);
    if (existingIso != null) {
      final parsed = DateTime.tryParse(existingIso);
      if (parsed != null) return parsed;
    }

    final cutoff = (await profileRepo.getActiveProfile())?.createdAt ??
        (await profileRepo.getDefaultProfile())?.createdAt ??
        DateTime.now();

    await prefs.setString(key, cutoff.toIso8601String());
    await _cleanupHistoricalAtmCashTransactions(cutoff);
    return cutoff;
  }

  static DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static Future<DateTime?> _getLastSmsCatchupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(await _lastSmsCatchupPrefKey());
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  static Future<void> _setLastSmsCatchupAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      await _lastSmsCatchupPrefKey(),
      time.millisecondsSinceEpoch,
    );
  }

  static Future<String> _lastSmsCatchupPrefKey() async {
    final profileRepo = ProfileRepository();
    final activeProfileId = await profileRepo.getActiveProfileId();
    return activeProfileId != null
        ? '$_lastSmsCatchupPrefPrefix$activeProfileId'
        : '${_lastSmsCatchupPrefPrefix}default';
  }

  static Future<void> _cleanupHistoricalAtmCashTransactions(
      DateTime cutoff) async {
    final txRepo = TransactionRepository();
    final transactions = await txRepo.getTransactions();
    final staleReferences = transactions
        .where((transaction) {
          if (transaction.bankId != CashConstants.bankId) return false;
          if (!transaction.reference
              .startsWith(CashConstants.atmReferencePrefix)) {
            return false;
          }
          final txTime = DateTime.tryParse(transaction.time ?? '');
          if (txTime == null) return false;
          return txTime.isBefore(cutoff);
        })
        .map((transaction) => transaction.reference)
        .toList(growable: false);

    if (staleReferences.isEmpty) return;

    await txRepo.deleteTransactionsByReferences(staleReferences);
    print(
        "debug: Removed ${staleReferences.length} historical ATM cash transfer(s) before cutoff");
  }

  static bool _isDashenExactDuplicate(
    Map<String, dynamic> details,
    List<Transaction> existingTransactions,
  ) {
    final bankId = details['bankId'];
    final type = (details['type'] ?? '').toString().toUpperCase();
    final amount = details['amount'];
    if (bankId != _dashenBankId || amount is! num) {
      return false;
    }

    return hasExactAmountAndBalanceDuplicate(
      bankId: bankId,
      type: type,
      amount: amount.toDouble(),
      currentBalance: details['currentBalance']?.toString(),
      accountNumber: details['accountNumber']?.toString(),
      existingTransactions: existingTransactions,
    );
  }

  static bool _hasSmsSourceDuplicate(
    Map<String, dynamic> details,
    List<Transaction> existingTransactions,
  ) {
    final sourceType = details['sourceType']?.toString().trim();
    if (sourceType != SmsTransactionSource.smsType) return false;

    final sourceMessageId = details['sourceMessageId']?.toString().trim();
    final sourceFingerprint = details['sourceFingerprint']?.toString().trim();
    final hasMessageId = sourceMessageId != null && sourceMessageId.isNotEmpty;
    final hasFingerprint =
        sourceFingerprint != null && sourceFingerprint.isNotEmpty;
    if (!hasMessageId && !hasFingerprint) return false;

    for (final transaction in existingTransactions) {
      if (transaction.sourceType != SmsTransactionSource.smsType) continue;

      if (hasFingerprint &&
          transaction.sourceFingerprint == sourceFingerprint) {
        return true;
      }

      if (!hasMessageId || transaction.sourceMessageId != sourceMessageId) {
        continue;
      }

      final existingFingerprint = transaction.sourceFingerprint?.trim();
      if (!hasFingerprint ||
          existingFingerprint == null ||
          existingFingerprint.isEmpty ||
          existingFingerprint == sourceFingerprint) {
        return true;
      }
    }

    return false;
  }

  // Static processing logic so it can be used by background handler too.
  static Future<Transaction?> processMessage(
    String messageBody,
    String senderAddress, {
    DateTime? messageDate,
    bool notifyUser = false,
    bool skipDashenExpenseDuplicates = true,
    bool skipAutoCategorization = false,
    bool allowRemoteBankFetch = true,
    bool allowRemotePatternFetch = false,
    int? sourceMessageId,
  }) async {
    final result = await _processMessageInternal(
      messageBody,
      senderAddress,
      messageDate: messageDate,
      sourceMessageId: sourceMessageId,
      notifyUser: notifyUser,
      skipDashenExpenseDuplicates: skipDashenExpenseDuplicates,
      skipAutoCategorization: skipAutoCategorization,
      allowRemoteBankFetch: allowRemoteBankFetch,
      allowRemotePatternFetch: allowRemotePatternFetch,
      recordFailure: true,
    );
    return result.transaction;
  }

  static Future<ParseResult> retryFailedParse(
    String messageBody,
    String senderAddress, {
    DateTime? messageDate,
    bool skipDashenExpenseDuplicates = true,
    bool skipAutoCategorization = false,
    int? sourceMessageId,
  }) async {
    return _processMessageInternal(
      messageBody,
      senderAddress,
      messageDate: messageDate,
      sourceMessageId: sourceMessageId,
      notifyUser: false,
      skipDashenExpenseDuplicates: skipDashenExpenseDuplicates,
      skipAutoCategorization: skipAutoCategorization,
      recordFailure: false,
    );
  }

  static Future<ParseResult> _processMessageInternal(
    String messageBody,
    String senderAddress, {
    DateTime? messageDate,
    bool notifyUser = false,
    bool skipDashenExpenseDuplicates = true,
    bool skipAutoCategorization = false,
    bool allowRemoteBankFetch = true,
    bool allowRemotePatternFetch = false,
    bool recordFailure = true,
    int? sourceMessageId,
  }) async {
    print("debug: Processing message: $messageBody");

    Bank? bank = await getRelevantBank(
      senderAddress,
      allowRemoteFetch: allowRemoteBankFetch,
    );
    if (bank == null) {
      print(
          "dubg: No bank found for address $senderAddress - skipping processing.");
      return const ParseResult(
        status: ParseStatus.noBank,
        reason: "No matching bank",
      );
    }

    // Check if the user has a registered account for this bank
    final registeredAccounts = await AccountRepository().getAccounts();
    final hasRegisteredAccount =
        registeredAccounts.any((a) => a.bank == bank.id);
    if (!hasRegisteredAccount) {
      print(
          "debug: No registered account for bank ${bank.name} (${bank.id}) - skipping.");
      return const ParseResult(
        status: ParseStatus.unregisteredBank,
        reason: "No registered account for this bank",
      );
    }

    // 1. Load Patterns
    final SmsConfigService configService = SmsConfigService();
    final patterns = await configService.getPatterns(
        allowRemoteFetch: allowRemotePatternFetch);
    final relevantPatterns =
        patterns.where((p) => p.bankId == bank.id).toList();
    print(
        "debug: Loaded ${relevantPatterns.length} native SMS patterns for ${bank.name}");
    // 2. Parse
    configService.debugSms(messageBody);
    final cleanedMessageBody = configService.cleanSmsText(messageBody);
    var details = await PatternParser.extractTransactionDetails(
      cleanedMessageBody,
      senderAddress,
      messageDate,
      relevantPatterns,
      banks: _cachedBanks,
    );

    if (details == null && FallbackSmsParser.isEnabled) {
      print("debug: Trying fallback SMS parser for ${bank.name}");
      details = await FallbackSmsParser.extractTransactionDetails(
        messageBody: cleanedMessageBody,
        senderAddress: senderAddress,
        messageDate: messageDate,
        bank: bank,
      );
    }

    if (details == null) {
      print("debug: No matching pattern found for message from $senderAddress");
      if (notifyUser && recordFailure) {
        try {
          final canonicalResult = await _retryCanonicalInboxCopy(
            originalBody: messageBody,
            senderAddress: senderAddress,
            messageDate: messageDate,
            bank: bank,
            skipDashenExpenseDuplicates: skipDashenExpenseDuplicates,
            skipAutoCategorization: skipAutoCategorization,
            allowRemoteBankFetch: allowRemoteBankFetch,
            allowRemotePatternFetch: allowRemotePatternFetch,
          );
          if (canonicalResult != null) {
            if (canonicalResult.status == ParseStatus.success &&
                canonicalResult.transaction != null) {
              await NotificationService.instance.showTransactionNotification(
                transaction: canonicalResult.transaction!,
                bankId: canonicalResult.transaction!.bankId,
              );
            }
            return canonicalResult;
          }
        } catch (e) {
          debugPrint("debug: Canonical inbox retry failed: $e");
        }
      }
      if (recordFailure && _looksLikeTransactionMessage(messageBody)) {
        if (notifyUser) {
          final reviewEnabled = await NotificationSettingsService.instance
              .isFailedParseReviewNotificationsEnabled();
          if (reviewEnabled) {
            final reviewId =
                await FailedParseReviewService.instance.storeCandidate(
              bank: bank,
              address: senderAddress,
              body: messageBody,
              messageDate: messageDate,
            );
            final shown = await NotificationService.instance
                .showFailedParseReviewNotification(
              reviewId: reviewId,
              bankName: bank.shortName,
              messageBody: messageBody,
            );
            if (!shown) {
              await FailedParseReviewService.instance
                  .discardCandidate(reviewId);
              await _recordFailedParse(
                address: senderAddress,
                body: messageBody,
                reason: FailedParse.noMatchingPatternReason,
                timestamp: messageDate,
                bankId: bank.id,
              );
            }
          }
        } else {
          await _recordFailedParse(
            address: senderAddress,
            body: messageBody,
            reason: FailedParse.noMatchingPatternReason,
            timestamp: messageDate,
            bankId: bank.id,
          );
        }
      }
      return const ParseResult(
        status: ParseStatus.noPattern,
        reason: FailedParse.noMatchingPatternReason,
      );
    }

    print("debug: Extracted details: $details");

    // Use message date if provided, otherwise use extracted time or current time
    if (messageDate != null && details['time'] == null) {
      details['time'] = messageDate.toIso8601String();
    } else if (messageDate != null && details['time'] != null) {
      // If pattern extracted a time but we have message date, prefer message date for historical accuracy
      details['time'] = messageDate.toIso8601String();
    }

    final parsedBankId = (details['bankId'] as num?)?.toInt() ?? bank.id;
    final smsSource = SmsTransactionSource.fromParts(
      bankId: parsedBankId,
      messageId: sourceMessageId,
      senderAddress: senderAddress,
      body: messageBody,
      dateMillis: messageDate?.millisecondsSinceEpoch,
    );
    details.addAll(smsSource.toJson());

    // 3. Check duplicate transaction
    TransactionRepository txRepo = TransactionRepository();
    List<Transaction> existingTx = await txRepo.getTransactions();

    if (_hasSmsSourceDuplicate(details, existingTx)) {
      print("debug: Duplicate SMS source skipped");
      return const ParseResult(
        status: ParseStatus.duplicate,
        reason: "Duplicate SMS source",
      );
    }

    String? newRef = details['reference'];
    if (newRef != null && existingTx.any((t) => t.reference == newRef)) {
      print("debug: Duplicate transaction skipped");
      if (_isAtmWithdrawal(details, messageBody)) {
        try {
          final existing = existingTx
              .firstWhere((transaction) => transaction.reference == newRef);
          await _createCashTransactionForAtmWithdrawal(existing, existingTx);
        } catch (e) {
          print("debug: Error reconciling cash transfer: $e");
        }
      }
      if (recordFailure) {
        await _recordFailedParse(
          address: senderAddress,
          body: messageBody,
          reason: "Duplicate transaction $newRef",
          timestamp: messageDate,
          bankId: parsedBankId,
        );
      }
      return ParseResult(
        status: ParseStatus.duplicate,
        reason: "Duplicate transaction $newRef",
      );
    }

    if (skipDashenExpenseDuplicates &&
        _isDashenExactDuplicate(details, existingTx)) {
      print(
          "debug: Duplicate Dashen transaction skipped by amount and balance");
      if (recordFailure) {
        await _recordFailedParse(
          address: senderAddress,
          body: messageBody,
          reason: "Duplicate Dashen transaction by amount and balance",
          timestamp: messageDate,
          bankId: parsedBankId,
        );
      }
      return const ParseResult(
        status: ParseStatus.duplicate,
        reason: "Duplicate Dashen transaction by amount and balance",
      );
    }

    // 4. Update Account Balance
    // We need to match the Bank ID from the pattern, not just assume 1 (CBE)
    int bankId = parsedBankId;
    final banks = await _bankConfigService.getBanks(
        allowRemoteFetch: allowRemoteBankFetch);
    final currentBank = _bankById(banks, bankId);
    if (currentBank == null) {
      print("debug: No bank config found for bank $bankId");
    } else if (currentBank.uniformMasking == false) {
      AccountRepository accRepo = AccountRepository();
      List<Account> accounts = await accRepo.getAccounts();
      final account = _accountForBank(accounts, bankId);
      if (account == null) {
        print("debug: No matching account found for bank $bankId");
      } else {
        final newBalance = details['currentBalance'] != null
            ? sanitizeAmount(details['currentBalance'])
            : account.balance;
        await _saveUpdatedAccountBalance(accRepo, account, newBalance);
      }
    } else if (details['accountNumber'] != null) {
      AccountRepository accRepo = AccountRepository();
      List<Account> accounts = await accRepo.getAccounts();

      final extractedAccount = details['accountNumber'].toString();
      final account = currentBank.uniformMasking == true
          ? _maskedAccountMatch(
              accounts,
              bankId: bankId,
              extractedAccount: extractedAccount,
              maskPattern: currentBank.maskPattern,
            )
          : null;

      if (account != null) {
        final newBalance = details['currentBalance'] != null
            ? sanitizeAmount(details['currentBalance'])
            : account.balance;
        await _saveUpdatedAccountBalance(accRepo, account, newBalance);
      } else {
        print(
            "No matching account found for bank $bankId and account $extractedAccount");
      }
    }

    // 5. Save Transaction
    // Need to ensure details has all fields or handle parsing
    // Transaction.fromJson expects Strings mostly?
    Transaction newTx = Transaction.fromJson(details);
    await txRepo.saveTransaction(
      newTx,
      skipAutoCategorization: skipAutoCategorization,
    );
    final savedTx =
        await txRepo.getTransactionByReference(newTx.reference) ?? newTx;

    print("debug: New transaction saved: ${savedTx.reference}");

    if (_isAtmWithdrawal(details, messageBody)) {
      try {
        await _createCashTransactionForAtmWithdrawal(savedTx, existingTx);
      } catch (e) {
        print("debug: Error creating cash transfer: $e");
      }
    }

    if (notifyUser) {
      await NotificationService.instance.showTransactionNotification(
        transaction: savedTx,
        bankId: bankId,
      );
    }

    if (savedTx.type == 'DEBIT') {
      try {
        await BudgetAlertService().checkAndNotifyBudgetAlerts();
      } catch (e) {
        print("debug: Error checking budget alerts after SMS transaction: $e");
      }
    }

    try {
      await WidgetService.refreshWidget();
    } catch (e) {
      print("debug: Error refreshing widget after SMS transaction: $e");
    }

    return ParseResult(
      status: ParseStatus.success,
      transaction: savedTx,
    );
  }
}
