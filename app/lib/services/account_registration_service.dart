import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/account_sync_status_service.dart';
import 'package:totals/services/fallback_sms_parser.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/sms_handler/telephony.dart';
import 'package:totals/utils/bank_sender_matcher.dart';
import 'package:totals/utils/pattern_parser.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/utils/sms_transaction_source.dart';
import 'package:totals/utils/transaction_duplicate_detector.dart';

const int _dashenBankId = 4;

class _ParsedSmsImportResult {
  final Map<String, dynamic>? details;

  const _ParsedSmsImportResult({this.details});

  bool get isParsed => details != null;
}

class AccountRegistrationService {
  final AccountRepository _accountRepo = AccountRepository();
  final TransactionRepository _transactionRepo = TransactionRepository();
  final AccountSyncStatusService _syncStatusService =
      AccountSyncStatusService.instance;
  final BankConfigService _bankConfigService = BankConfigService();
  final NotificationService _notificationService = NotificationService.instance;
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
      }).catchError((e) async {
        print("debug: Error syncing SMS in background: $e");
        _syncStatusService.clearSyncStatus(accountNumber, bankId);
        onProgress?.call("Sync failed: $e", 1.0);
        await _notificationService.dismissAccountSyncNotification(
          accountNumber: accountNumber,
          bankId: bankId,
        );
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

    Future<void> reportProgress(String stage, {double? progress}) async {
      final safeProgress = progress?.clamp(0.0, 1.0).toDouble();
      final notificationProgress = safeProgress ?? 0.0;
      _syncStatusService.setSyncStatus(
        accountNumber,
        bankId,
        stage,
        progress: safeProgress,
      );
      onProgress?.call(stage, notificationProgress);
      await _notificationService.showAccountSyncProgress(
        accountNumber: accountNumber,
        bankId: bankId,
        bankLabel: bank.shortName,
        stage: stage,
        progress: notificationProgress,
      );
    }

    await reportProgress("Starting sync...");
    await reportProgress("Finding bank messages...");

    final bankCodes = bank.codes;
    print("debug: Syncing SMS for bank ${bank.name} with codes: $bankCodes");

    await reportProgress("Fetching SMS messages...");

    // Get all messages from the bank
    final Telephony telephony = Telephony.instance;
    List<SmsMessage> allMessages = [];

    // Fetch all messages for every bank code and keep only the best sender match.
    try {
      print("debug: bankId: $bankId");
      final allSms = <SmsMessage>[];
      for (final code in bankCodes.toSet()) {
        final trimmedCode = code.trim();
        if (trimmedCode.isEmpty) continue;
        final batch = await telephony.getInboxSms(
          columns: const [
            SmsColumn.ID,
            SmsColumn.ADDRESS,
            SmsColumn.BODY,
            SmsColumn.DATE,
          ],
          sortOrder: [
            OrderBy(SmsColumn.DATE, sort: Sort.DESC),
          ],
          filter: SmsFilter.where(SmsColumn.ADDRESS).like('%$trimmedCode%'),
        );
        allSms.addAll(batch);
      }

      // Filter messages that match any bank code
      final filtered = allSms.where((message) {
        return senderAddressMatchesBank(
          bank,
          message.address,
          allBanks: _cachedBanks,
        );
      }).toList();

      allMessages.addAll(filtered);
    } catch (e) {
      print("debug: Error fetching SMS: $e");
    }

    // Remove duplicates based on body and address
    final uniqueMessages = <String, SmsMessage>{};
    for (var msg in allMessages) {
      final key = msg.id == null
          ? '${msg.date}_${msg.address}_${msg.body}'
          : 'id:${msg.id}';
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

    await reportProgress("Loading parsing patterns...");

    // Load patterns for this bank
    final configService = SmsConfigService();
    final patterns = await configService.getPatterns(allowRemoteFetch: false);
    final relevantPatterns = patterns.where((p) => p.bankId == bankId).toList();
    final hasFallbackParser =
        await FallbackSmsParser.supportsBankId(bankId, requirePatterns: true);

    if (relevantPatterns.isEmpty && !hasFallbackParser) {
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

    await reportProgress("Parsing messages...", progress: 0.0);

    // Process messages in batches for better performance
    int importedCount = 0;
    int skippedCount = 0;
    int duplicatesRemovedCount = 0;
    final totalMessages = messages.length;
    const int batchSize = 10; // Process 10 messages concurrently
    final existingTransactions = await _transactionRepo.getTransactions();
    final importedReferences = existingTransactions
        .map((transaction) => transaction.reference)
        .toSet();
    final importedSourceMessageIds = existingTransactions
        .map((transaction) => transaction.sourceMessageId)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet();
    final importedSourceFingerprints = existingTransactions
        .map((transaction) => transaction.sourceFingerprint)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet();
    final transactionsToImport = <Transaction>[];

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

      // Parse batch concurrently. Saving happens after parsing so duplicate
      // checks use one in-memory reference set instead of reloading the DB.
      final results = await Future.wait(
        batch.map((message) async {
          if (message.body == null || message.address == null) {
            return const _ParsedSmsImportResult();
          }

          try {
            // Check if message matches any pattern
            final cleanedBody = configService.cleanSmsText(message.body!);
            final messageDate = message.date == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(message.date!);
            var details = relevantPatterns.isEmpty
                ? null
                : await PatternParser.extractTransactionDetails(
                    cleanedBody,
                    message.address!,
                    messageDate,
                    relevantPatterns,
                    banks: _cachedBanks,
                  );
            details ??= await FallbackSmsParser.extractTransactionDetails(
              messageBody: cleanedBody,
              senderAddress: message.address!,
              messageDate: messageDate,
              bank: bank,
            );

            if (details != null) {
              final parsedBankId =
                  (details['bankId'] as num?)?.toInt() ?? bank.id;
              final source = SmsTransactionSource.fromMessage(
                message: message,
                bankId: parsedBankId,
              );
              details.addAll(source.toJson());
              _applyMessageDate(details, messageDate);
              return _ParsedSmsImportResult(details: details);
            }
            return const _ParsedSmsImportResult();
          } catch (e) {
            print("debug: Error processing message: $e");
            return const _ParsedSmsImportResult();
          }
        }),
      );

      // Count results and track latest balance
      for (var result in results) {
        final details = result.details;
        if (details != null &&
            details['currentBalance'] != null &&
            latestBalanceDetails == null) {
          latestBalanceDetails = details;
          latestAccountNumber = details['accountNumber'];
        }

        if (!result.isParsed) {
          skippedCount++;
          continue;
        }

        final transaction = _transactionFromDetails(details!);
        if (transaction == null ||
            importedReferences.contains(transaction.reference) ||
            _sourceAlreadyImported(
              transaction,
              sourceMessageIds: importedSourceMessageIds,
              sourceFingerprints: importedSourceFingerprints,
            )) {
          skippedCount++;
          continue;
        }

        importedReferences.add(transaction.reference);
        _trackImportedSource(
          transaction,
          sourceMessageIds: importedSourceMessageIds,
          sourceFingerprints: importedSourceFingerprints,
        );
        transactionsToImport.add(transaction);
        importedCount++;
      }

      // Report parsing progress after this batch finishes.
      final parsingProgress = batchEnd / totalMessages;
      final status = "Parsing $batchEnd/$totalMessages messages...";
      await reportProgress(status, progress: parsingProgress);
    }

    if (transactionsToImport.isNotEmpty) {
      await reportProgress("Saving imported transactions...", progress: 1.0);
      await _transactionRepo.saveAllTransactions(
        transactionsToImport,
        skipAutoCategorization: false,
      );
    }

    // Update account balance from the latest message
    if (latestBalanceDetails != null) {
      await reportProgress("Updating account balance...", progress: 1.0);
      await _updateAccountBalanceFromLatestMessage(
        bankId,
        latestBalanceDetails,
        latestAccountNumber,
      );
    }

    duplicatesRemovedCount = await _removeImportedDuplicates(
      bank: bank,
      accountNumber: accountNumber,
    );
    final finalImportedCount = importedCount > duplicatesRemovedCount
        ? importedCount - duplicatesRemovedCount
        : 0;
    final completionMessage = "Imported $finalImportedCount transactions.";

    // Clear sync status when complete
    _syncStatusService.clearSyncStatus(accountNumber, bankId);
    onProgress?.call(
      "Complete! Imported $finalImportedCount transactions",
      1.0,
    );
    await _notificationService.showAccountSyncComplete(
      accountNumber: accountNumber,
      bankId: bankId,
      bankLabel: bank.shortName,
      message: completionMessage,
    );

    print(
        "debug: SMS sync complete - Imported: $finalImportedCount, Removed duplicates: $duplicatesRemovedCount, Skipped: $skippedCount");
  }

  AccountSyncStatusService get syncStatusService => _syncStatusService;

  void _applyMessageDate(
    Map<String, dynamic> details,
    DateTime? messageDate,
  ) {
    if (messageDate == null) return;
    details['time'] = messageDate.toIso8601String();
  }

  Transaction? _transactionFromDetails(Map<String, dynamic> details) {
    final reference = details['reference']?.toString();
    if (reference == null || reference.trim().isEmpty) return null;

    return Transaction.fromJson(details);
  }

  bool _sourceAlreadyImported(
    Transaction transaction, {
    required Set<String> sourceMessageIds,
    required Set<String> sourceFingerprints,
  }) {
    final sourceFingerprint = transaction.sourceFingerprint?.trim();
    if (sourceFingerprint != null &&
        sourceFingerprint.isNotEmpty &&
        sourceFingerprints.contains(sourceFingerprint)) {
      return true;
    }

    final sourceMessageId = transaction.sourceMessageId?.trim();
    if (sourceMessageId == null ||
        sourceMessageId.isEmpty ||
        !sourceMessageIds.contains(sourceMessageId)) {
      return false;
    }

    return sourceFingerprint == null ||
        sourceFingerprint.isEmpty ||
        sourceFingerprints.contains(sourceFingerprint);
  }

  void _trackImportedSource(
    Transaction transaction, {
    required Set<String> sourceMessageIds,
    required Set<String> sourceFingerprints,
  }) {
    final sourceMessageId = transaction.sourceMessageId?.trim();
    if (sourceMessageId != null && sourceMessageId.isNotEmpty) {
      sourceMessageIds.add(sourceMessageId);
    }

    final sourceFingerprint = transaction.sourceFingerprint?.trim();
    if (sourceFingerprint != null && sourceFingerprint.isNotEmpty) {
      sourceFingerprints.add(sourceFingerprint);
    }
  }

  Future<int> _removeImportedDuplicates({
    required Bank bank,
    required String accountNumber,
  }) async {
    if (bank.id != _dashenBankId) return 0;

    final accountSuffix = _accountSuffixForBank(
      bank: bank,
      accountNumber: accountNumber,
    );
    if (accountSuffix == null) return 0;

    final plans = buildExactAmountAndBalanceDeduplicationPlans(
      bankId: bank.id,
      type: 'DEBIT',
      transactions: await _transactionRepo.getTransactions(),
      accountSuffix: accountSuffix,
    );
    if (plans.isEmpty) return 0;

    for (final plan in plans) {
      await _transactionRepo.saveTransaction(
        plan.mergedKeeper,
        skipAutoCategorization: true,
      );
    }
    await _transactionRepo.deleteTransactionsByReferences(
      plans.expand((plan) => plan.duplicateReferences),
    );

    final removedCount = plans.fold<int>(
      0,
      (sum, plan) => sum + plan.duplicates.length,
    );
    print(
      "debug: Removed $removedCount duplicate ${bank.shortName} transaction(s) "
      "after account sync",
    );
    return removedCount;
  }

  String? _accountSuffixForBank({
    required Bank bank,
    required String accountNumber,
  }) {
    final trimmedAccount = accountNumber.trim();
    if (trimmedAccount.isEmpty) return null;
    final maskPattern = bank.maskPattern;
    if (bank.uniformMasking == true &&
        maskPattern != null &&
        maskPattern > 0 &&
        trimmedAccount.length > maskPattern) {
      return trimmedAccount.substring(trimmedAccount.length - maskPattern);
    }
    return trimmedAccount;
  }

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
