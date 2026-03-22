import 'dart:ui';

import 'package:another_telephony/telephony.dart';
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
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/budget_alert_service.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/services/duplicate_transaction_service.dart';

enum ParseStatus {
  success,
  noBank,
  noPattern,
  duplicate,
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
Future<void> onBackgroundMessage(SmsMessage message) async {
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
    if (await SmsService.isRelevantMessage(address)) {
      print("debug: BG: Message IS relevant. Processing...");
      await SmsService.processMessage(body, address!,
          notifyUser: true,
          messageDate: DateTime.fromMillisecondsSinceEpoch(message.date!));
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

  // Callback for foreground-only UI updates.
  ValueChanged<Transaction>? onTransactionSaved;

  Future<void> init() async {
    final bool? result = await _telephony.requestSmsPermissions;
    if (result != null && result) {
      _telephony.listenIncomingSms(
        onNewMessage: _handleForegroundMessage,
        onBackgroundMessage: onBackgroundMessage,
      );
    } else {
      print("debug: SMS Permission denied");
    }
  }

  void _handleForegroundMessage(SmsMessage message) async {
    print("debug: Foreground message from ${message.address}: ${message.body}");
    if (message.body == null) return;

    try {
      if (await SmsService.isRelevantMessage(message.address)) {
        final tx = await SmsService.processMessage(
            message.body!, message.address!,
            notifyUser: true,
            messageDate: DateTime.fromMillisecondsSinceEpoch(message.date!));
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

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final filter = SmsFilter.where(SmsColumn.DATE)
        .greaterThanOrEqualTo(startOfDay.millisecondsSinceEpoch.toString())
        .and(SmsColumn.DATE)
        .lessThan(endOfDay.millisecondsSinceEpoch.toString());

    final messages = await _telephony.getInboxSms(
      filter: filter,
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

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
  static Future<bool> isRelevantMessage(String? address) async {
    if (address == null) return false;
    final bank = await getRelevantBank(address);
    return bank != null;
  }

  /// Identifies the bank associated with the sender address.
  static Future<Bank?> getRelevantBank(String? address) async {
    if (address == null) return null;

    // Fetch banks from database (with static caching)
    _cachedBanks ??= await _bankConfigService.getBanks();

    for (var bank in _cachedBanks!) {
      for (var code in bank.codes) {
        if (address.contains(code)) {
          return bank;
        }
      }
    }
    return null;
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
      cleaned = '${cleaned}0';
    }

    // If empty after cleaning, return 0
    if (cleaned.isEmpty) return 0.0;

    // Safe parse
    return double.tryParse(cleaned) ?? 0.0;
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

    final cashReference = CashConstants.buildAtmReference(withdrawal.reference);
    if (existingTransactions.any((t) => t.reference == cashReference)) {
      return;
    }

    await _ensureCashAccount();

    final cashTransaction = Transaction(
      amount: withdrawal.amount,
      reference: cashReference,
      creditor: 'ATM withdrawal',
      time: withdrawal.time ?? DateTime.now().toIso8601String(),
      bankId: CashConstants.bankId,
      type: 'CREDIT',
      transactionLink: withdrawal.reference,
      accountNumber: CashConstants.defaultAccountNumber,
    );

    await TransactionRepository().saveTransaction(cashTransaction);
  }

  // Static processing logic so it can be used by background handler too.
  static Future<Transaction?> processMessage(
    String messageBody,
    String senderAddress, {
    DateTime? messageDate,
    bool notifyUser = false,
  }) async {
    final result = await _processMessageInternal(
      messageBody,
      senderAddress,
      messageDate: messageDate,
      notifyUser: notifyUser,
      recordFailure: true,
    );
    return result.transaction;
  }

  static Future<ParseResult> retryFailedParse(
    String messageBody,
    String senderAddress, {
    DateTime? messageDate,
  }) async {
    return _processMessageInternal(
      messageBody,
      senderAddress,
      messageDate: messageDate,
      notifyUser: false,
      recordFailure: false,
    );
  }

  static Future<ParseResult> _processMessageInternal(
    String messageBody,
    String senderAddress, {
    DateTime? messageDate,
    bool notifyUser = false,
    bool recordFailure = true,
  }) async {
    print("debug: Processing message: $messageBody");

    Bank? bank = await getRelevantBank(senderAddress);
    if (bank == null) {
      print(
          "dubg: No bank found for address $senderAddress - skipping processing.");
      return const ParseResult(
        status: ParseStatus.noBank,
        reason: "No matching bank",
      );
    }

    // 1. Load Patterns
    final SmsConfigService configService = SmsConfigService();
    final patterns = await configService.getPatterns();
    final relevantPatterns =
        patterns.where((p) => p.bankId == bank.id).toList();
    // 2. Parse
    configService.debugSms(messageBody);
    var details = await PatternParser.extractTransactionDetails(
        configService.cleanSmsText(messageBody),
        senderAddress,
        messageDate,
        relevantPatterns);

    if (details == null) {
      print("debug: No matching pattern found for message from $senderAddress");
      if (recordFailure) {
        await FailedParseRepository().add(FailedParse(
            address: senderAddress,
            body: messageBody,
            reason: "No matching pattern",
            timestamp: DateTime.now().toIso8601String()));
      }
      return const ParseResult(
        status: ParseStatus.noPattern,
        reason: "No matching pattern",
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

    // 3. Check duplicate transaction
    TransactionRepository txRepo = TransactionRepository();
    List<Transaction> existingTx = await txRepo.getTransactions();

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
        await FailedParseRepository().add(FailedParse(
            address: senderAddress,
            body: messageBody,
            reason: "Duplicate transaction $newRef",
            timestamp: DateTime.now().toIso8601String()));
      }
      return ParseResult(
        status: ParseStatus.duplicate,
        reason: "Duplicate transaction $newRef",
      );
    }

    // 4. Update Account Balance
    // We need to match the Bank ID from the pattern, not just assume 1 (CBE)
    int bankId = details['bankId'] ?? bank.id;
    final banks = await _bankConfigService.getBanks();
    final currentBank = banks.firstWhere((b) => b.id == bankId);
    if (currentBank.uniformMasking == false) {
      AccountRepository accRepo = AccountRepository();
      List<Account> accounts = await accRepo.getAccounts();
      int index = accounts.indexWhere((a) {
        return a.bank == bankId;
      });
      Account old = accounts[index];
      double newBalance = details['currentBalance'] != null
          ? sanitizeAmount(details['currentBalance'])
          : old.balance;

      Account updated = Account(
          accountNumber: old.accountNumber,
          bank: old.bank,
          balance: newBalance,
          accountHolderName: old.accountHolderName,
          settledBalance: old.settledBalance,
          pendingCredit: old.pendingCredit);
      await accRepo.saveAccount(updated);
      print("debug: Account balance updated for ${old.accountHolderName}");
    } else if (details['accountNumber'] != null) {
      AccountRepository accRepo = AccountRepository();
      List<Account> accounts = await accRepo.getAccounts();

      String extractedAccount = details['accountNumber'];

      int index = -1;
      final banks = await _bankConfigService.getBanks();
      final bank = banks.firstWhere((b) => b.id == bankId);
      if (bank.uniformMasking == true) {
        index = accounts.indexWhere((a) {
          if (a.bank != bankId) return false;
          return a.accountNumber.endsWith(extractedAccount
              .substring(extractedAccount.length - bank.maskPattern!));
        });
      }

      if (index != -1) {
        Account old = accounts[index];
        double newBalance = details['currentBalance'] != null
            ? sanitizeAmount(details['currentBalance'])
            : old.balance;

        // Update balance
        Account updated = Account(
            accountNumber: old.accountNumber,
            bank: old.bank,
            balance: newBalance,
            accountHolderName: old.accountHolderName,
            settledBalance: old.settledBalance,
            pendingCredit: old.pendingCredit);
        await accRepo.saveAccount(updated);
        print("debug: Account balance updated for ${old.accountHolderName}");
      } else {
        print(
            "No matching account found for bank $bankId and account $extractedAccount");
      }
    }

    // 5. Save Transaction
    // Need to ensure details has all fields or handle parsing
    // Transaction.fromJson expects Strings mostly?
    Transaction newTx = Transaction.fromJson(details);
    await txRepo.saveTransaction(newTx);

    print("debug: New transaction saved: ${newTx.reference}");

    // Check if this looks like a duplicate of a recent transaction
    final suspectedDuplicate = DuplicateTransactionService()
        .checkIncoming(newTx, existingTx);
    if (suspectedDuplicate != null) {
      print("debug: Suspected duplicate detected for ${newTx.reference}");
      await NotificationService.instance.showDuplicateWarningNotification(
        transaction: newTx,
        timeDelta: suspectedDuplicate.timeDelta,
      );
    }

    if (_isAtmWithdrawal(details, messageBody)) {
      try {
        await _createCashTransactionForAtmWithdrawal(newTx, existingTx);
      } catch (e) {
        print("debug: Error creating cash transfer: $e");
      }
    }

    if (notifyUser) {
      await NotificationService.instance.showTransactionNotification(
        transaction: newTx,
        bankId: bankId,
      );
    }

    if (newTx.type == 'DEBIT') {
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
      transaction: newTx,
    );
  }
}
