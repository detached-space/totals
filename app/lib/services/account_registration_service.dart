import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/account_sync_status_service.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/sms_handler/telephony.dart';
import 'package:totals/utils/pattern_parser.dart';

class AccountRegistrationService {
  final AccountRepository _accountRepo = AccountRepository();
  final AccountSyncStatusService _syncStatusService =
      AccountSyncStatusService.instance;
  final BankConfigService _bankConfigService = BankConfigService();
  final NotificationService _notificationService =
      NotificationService.instance;
  List<Bank>? _cachedBanks;

  /// Registers a new account and optionally syncs previous SMS messages
  /// Returns the account if created successfully
  Future<Account?> registerAccount({
    required String accountNumber,
    required String accountHolderName,
    required int bankId,
    bool syncPreviousSms = true,
    Function(String stage, double progress)? onProgress,
    Function()? onSyncComplete,
  }) async {
    // Check if account already exists
    final exists = await _accountRepo.accountExists(accountNumber, bankId);
    if (exists) {
      print("debug: Account $accountNumber for bank $bankId already exists");
      return null;
    }

    // Create and save the account immediately
    final account = Account(
      accountNumber: accountNumber,
      bank: bankId,
      balance: 0.0,
      accountHolderName: accountHolderName,
    );
    await _accountRepo.saveAccount(account);
    print("debug: Account registered: $accountNumber");

    // Sync previous SMS in background if requested
    if (syncPreviousSms) {
      // Start sync in background (don't await)
      _syncPreviousSms(bankId, accountNumber, onProgress).then((_) {
        onSyncComplete?.call();
      }).catchError((e) {
        print("debug: Error syncing SMS in background: $e");
        onProgress?.call("Sync failed: $e", 1.0);
        onSyncComplete?.call();
      });
    }

    return account;
  }

  /// Syncs and parses previous SMS messages from the bank
  Future<void> _syncPreviousSms(
    int bankId,
    String accountNumber,
    Function(String stage, double progress)? onProgress,
  ) async {
    // Fetch banks from database (with caching)
    if (_cachedBanks == null) {
      _cachedBanks = await _bankConfigService.getBanks();
    }

    final bank = _cachedBanks!.firstWhere(
      (element) => element.id == bankId,
      orElse: () => throw Exception("Bank with id $bankId not found"),
    );

    Future<void> reportProgress(String stage, double progress) async {
      _syncStatusService.setSyncStatus(accountNumber, bankId, stage);
      onProgress?.call(stage, progress);
      await _notificationService.showAccountSyncProgress(
        accountNumber: accountNumber,
        bankId: bankId,
        bankLabel: bank.shortName,
        stage: stage,
        progress: progress,
      );
    }

    await reportProgress("Starting sync...", 0.05);
    await reportProgress("Finding bank messages...", 0.3);

    final bankCodes = bank.codes;
    print("debug: Syncing SMS for bank ${bank.name} with codes: $bankCodes");

    await reportProgress("Fetching SMS messages...", 0.4);

    // Get all messages from the bank
    final Telephony telephony = Telephony.instance;
    List<SmsMessage> allMessages = [];

    // Query messages for each bank code
    // Fetch all messages and filter by bank codes (since exact match may miss variations)
    try {
      print("debug: bankId: $bankId");
      final allSms = await telephony.getInboxSms(
        columns: const [
          SmsColumn.ADDRESS,
          SmsColumn.BODY,
          SmsColumn.DATE,
        ],
        sortOrder: [
          OrderBy(SmsColumn.DATE, sort: Sort.DESC),
        ],
        filter: SmsFilter.where(SmsColumn.ADDRESS).like('%${bankCodes[0]}%'),
      );

      // Filter messages that match any bank code
      final filtered = allSms.where((message) {
        if (message.address == null) return false;
        final address = message.address!.toLowerCase();
        return bankCodes.any((code) => address.contains(code.toLowerCase()));
      }).toList();

      allMessages.addAll(filtered);
    } catch (e) {
      print("debug: Error fetching SMS: $e");
    }

    // Remove duplicates based on body and address
    final uniqueMessages = <String, SmsMessage>{};
    for (var msg in allMessages) {
      final key = '${msg.address}_${msg.body}';
      if (!uniqueMessages.containsKey(key)) {
        uniqueMessages[key] = msg;
      }
    }

    final messages = uniqueMessages.values.toList();
    print("debug: Found ${messages.length} unique messages from ${bank.name}");

    if (messages.isEmpty) {
      _syncStatusService.clearSyncStatus(accountNumber, bankId);
      onProgress?.call("No messages found", 1.0);
      await _notificationService.showAccountSyncComplete(
        accountNumber: accountNumber,
        bankId: bankId,
        bankLabel: bank.shortName,
        message: "No messages found to import.",
      );
      return;
    }

    await reportProgress("Loading parsing patterns...", 0.5);

    // Load patterns for this bank
    final configService = SmsConfigService();
    final patterns = await configService.getPatterns();
    final relevantPatterns = patterns.where((p) => p.bankId == bankId).toList();

    if (relevantPatterns.isEmpty) {
      print("debug: No patterns found for bank $bankId, skipping parsing");
      _syncStatusService.clearSyncStatus(accountNumber, bankId);
      onProgress?.call("No patterns found", 1.0);
      await _notificationService.showAccountSyncComplete(
        accountNumber: accountNumber,
        bankId: bankId,
        bankLabel: bank.shortName,
        message: "No patterns found for this bank.",
      );
      return;
    }

    await reportProgress("Parsing messages...", 0.6);

    // Process messages in batches for better performance
    int processedCount = 0;
    int skippedCount = 0;
    final totalMessages = messages.length;
    const int batchSize = 10; // Process 10 messages concurrently

    // Track the latest message with balance for account update
    Map<String, dynamic>? latestBalanceDetails;
    String? latestAccountNumber;

    // Process messages in batches
    for (int batchStart = 0;
        batchStart < messages.length;
        batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize < messages.length)
          ? batchStart + batchSize
          : messages.length;
      final batch = messages.sublist(batchStart, batchEnd);

      // Update progress
      final baseProgress = 0.6;
      final batchProgress = batchEnd / totalMessages;
      final currentProgress = baseProgress + (batchProgress * 0.35);
      final status = "Processing ${batchEnd}/$totalMessages messages...";
      await reportProgress(status, currentProgress);

      // Process batch concurrently
      final results = await Future.wait(
        batch.map((message) async {
          if (message.body == null || message.address == null) {
            return {'status': 'skipped', 'details': null};
          }

          try {
            // Check if message matches any pattern
            final cleanedBody = configService.cleanSmsText(message.body!);
            final details = await PatternParser.extractTransactionDetails(
              cleanedBody,
              message.address!,
              DateTime.fromMillisecondsSinceEpoch(message.date!),
              relevantPatterns,
            );

            if (details != null) {
              // Convert message date from milliseconds to DateTime
              DateTime? messageDate;
              if (message.date != null) {
                messageDate =
                    DateTime.fromMillisecondsSinceEpoch(message.date!);
              }

              // Process the message using the existing SmsService logic with message date
              await SmsService.processMessage(
                message.body!,
                message.address!,
                messageDate: messageDate,
              );

              return {'status': 'processed', 'details': details};
            } else {
              return {'status': 'skipped', 'details': null};
            }
          } catch (e) {
            print("debug: Error processing message: $e");
            return {'status': 'skipped', 'details': null};
          }
        }),
      );

      // Count results and track latest balance
      for (var result in results) {
        if (result['status'] == 'processed') {
          processedCount++;
          final details = result['details'] as Map<String, dynamic>?;

          // Track the latest message with balance (messages are sorted DESC, so first match is latest)
          if (details != null &&
              details['currentBalance'] != null &&
              latestBalanceDetails == null) {
            latestBalanceDetails = details;
            latestAccountNumber = details['accountNumber'];
          }
        } else {
          skippedCount++;
        }
      }
    }

    // Update account balance from the latest message
    if (latestBalanceDetails != null) {
      await reportProgress("Updating account balance...", 0.95);
      await _updateAccountBalanceFromLatestMessage(
        bankId,
        latestBalanceDetails,
        latestAccountNumber,
      );
    }

    // Clear sync status when complete
    _syncStatusService.clearSyncStatus(accountNumber, bankId);
    onProgress?.call(
      "Complete! Processed $processedCount transactions",
      1.0,
    );
    await _notificationService.showAccountSyncComplete(
      accountNumber: accountNumber,
      bankId: bankId,
      bankLabel: bank.shortName,
      message: "Imported $processedCount transactions.",
    );

    print(
        "debug: SMS sync complete - Processed: $processedCount, Skipped: $skippedCount");
  }

  AccountSyncStatusService get syncStatusService => _syncStatusService;

  /// Updates account balance from the latest message
  Future<void> _updateAccountBalanceFromLatestMessage(
    int bankId,
    Map<String, dynamic> details,
    String? extractedAccountNumber,
  ) async {
    try {
      final accounts = await _accountRepo.getAccounts();
      int bankIdFromDetails = details['bankId'] ?? bankId;
      final banks = await _bankConfigService.getBanks();
      final bank = banks.firstWhere((b) => b.id == bankIdFromDetails);

      int index = -1;

      // Use uniformMasking logic to match accounts
      if (bank.uniformMasking == false) {
        // Match by bankId only (e.g., Awash/Telebirr)
        index = accounts.indexWhere((a) => a.bank == bankIdFromDetails);
      } else if (extractedAccountNumber != null &&
          extractedAccountNumber.isNotEmpty) {
        if (bank.uniformMasking == true && bank.maskPattern != null) {
          // Match last N digits based on mask pattern
          final extractedSuffix = extractedAccountNumber.length >=
                  bank.maskPattern!
              ? extractedAccountNumber
                  .substring(extractedAccountNumber.length - bank.maskPattern!)
              : extractedAccountNumber;

          index = accounts.indexWhere((a) {
            if (a.bank != bankIdFromDetails) return false;
            if (a.accountNumber.length < bank.maskPattern!) return false;
            final accountSuffix = a.accountNumber
                .substring(a.accountNumber.length - bank.maskPattern!);
            return accountSuffix == extractedSuffix;
          });
        } else {
          // Exact match (uniformMasking is null)
          index = accounts.indexWhere((a) =>
              a.bank == bankIdFromDetails &&
              a.accountNumber == extractedAccountNumber);
        }
      } else {
        // No account number extracted, match by bankId only
        index = accounts.indexWhere((a) => a.bank == bankIdFromDetails);
      }

      if (index != -1) {
        final account = accounts[index];
        final newBalance = details['currentBalance'] != null
            ? SmsService.sanitizeAmount(details['currentBalance'])
            : account.balance;

        final updated = Account(
          accountNumber: account.accountNumber,
          bank: account.bank,
          balance: newBalance,
          accountHolderName: account.accountHolderName,
          settledBalance: account.settledBalance,
          pendingCredit: account.pendingCredit,
        );
        await _accountRepo.saveAccount(updated);
        print(
            "debug: Account balance updated from latest message for ${account.accountHolderName}: $newBalance");
      }
    } catch (e) {
      print("debug: Error updating account balance from latest message: $e");
    }
  }
}
