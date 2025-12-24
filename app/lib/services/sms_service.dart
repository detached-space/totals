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
    if (_cachedBanks == null) {
      _cachedBanks = await _bankConfigService.getBanks();
    }

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
      cleaned = cleaned + '0';
    }

    // If empty after cleaning, return 0
    if (cleaned.isEmpty) return 0.0;

    // Safe parse
    return double.tryParse(cleaned) ?? 0.0;
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

    if (notifyUser) {
      await NotificationService.instance.showTransactionNotification(
        transaction: newTx,
        bankId: bankId,
      );
    }

    return ParseResult(
      status: ParseStatus.success,
      transaction: newTx,
    );
  }
}
