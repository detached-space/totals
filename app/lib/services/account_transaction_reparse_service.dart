import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/sms_pattern.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/account_reparse_result_service.dart';
import 'package:totals/services/account_sync_status_service.dart';
import 'package:totals/services/auto_categorization_service.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/background_refresh_signal_service.dart';
import 'package:totals/services/fallback_sms_parser.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/sms_handler/telephony.dart';
import 'package:totals/utils/bank_sender_matcher.dart';
import 'package:totals/utils/pattern_parser.dart';
import 'package:totals/utils/sms_transaction_source.dart';

typedef _ReparseProgressCallback = Future<void> Function(
  String stage,
  double progress,
);

const Duration _sourceAnchoredDuplicateWindow = Duration(minutes: 2);

class AccountTransactionReparseResult {
  final bool unsupported;
  final bool permissionDenied;
  final String? errorMessage;
  final int scannedMessages;
  final int parsedMessages;
  final int matchedTransactions;
  final int updatedTransactions;
  final int importedTransactions;
  final int categorizedTransactions;
  final int addedReceiptLinks;
  final int removedDuplicateTransactions;
  final List<Transaction> importedTransactionDetails;
  final List<Transaction> removedDuplicateTransactionDetails;

  const AccountTransactionReparseResult({
    this.unsupported = false,
    this.permissionDenied = false,
    this.errorMessage,
    this.scannedMessages = 0,
    this.parsedMessages = 0,
    this.matchedTransactions = 0,
    this.updatedTransactions = 0,
    this.importedTransactions = 0,
    this.categorizedTransactions = 0,
    this.addedReceiptLinks = 0,
    this.removedDuplicateTransactions = 0,
    this.importedTransactionDetails = const <Transaction>[],
    this.removedDuplicateTransactionDetails = const <Transaction>[],
  });
}

class AccountTransactionReparseStartResult {
  final bool started;
  final String? errorMessage;

  const AccountTransactionReparseStartResult({
    required this.started,
    this.errorMessage,
  });
}

class _PreparedAccountTransactionReparse {
  final Bank bank;
  final List<SmsPattern> relevantPatterns;
  final List<Account> bankAccounts;
  final AccountTransactionReparseResult? failure;

  _PreparedAccountTransactionReparse({
    required this.bank,
    required this.relevantPatterns,
    required this.bankAccounts,
  }) : failure = null;

  _PreparedAccountTransactionReparse.failure(
    AccountTransactionReparseResult this.failure,
  )   : bank = Bank(
          id: -1,
          name: '',
          shortName: '',
          codes: [],
          image: '',
        ),
        relevantPatterns = const [],
        bankAccounts = const [];
}

class _ParsedSourceSmsTransaction {
  final Transaction transaction;
  final String sourceKey;
  final String? referenceKey;
  final DateTime? messageDate;

  const _ParsedSourceSmsTransaction({
    required this.transaction,
    required this.sourceKey,
    required this.referenceKey,
    required this.messageDate,
  });
}

class _SourceDuplicateCleanupResult {
  final Set<String> updatedReferences;
  final Set<String> linkAddedReferences;
  final int removedDuplicateTransactions;
  final List<Transaction> removedDuplicateTransactionDetails;

  const _SourceDuplicateCleanupResult({
    this.updatedReferences = const <String>{},
    this.linkAddedReferences = const <String>{},
    this.removedDuplicateTransactions = 0,
    this.removedDuplicateTransactionDetails = const <Transaction>[],
  });
}

class AccountTransactionReparseService {
  final Telephony _telephony = Telephony.instance;
  final BankConfigService _bankConfigService = BankConfigService();
  final SmsConfigService _smsConfigService = SmsConfigService();
  final AccountRepository _accountRepo = AccountRepository();
  final TransactionRepository _transactionRepo = TransactionRepository();
  final AccountSyncStatusService _syncStatusService =
      AccountSyncStatusService.instance;
  final NotificationService _notificationService = NotificationService.instance;
  final AutoCategorizationService _autoCategorizationService =
      AutoCategorizationService.instance;
  List<Bank>? _cachedBanks;

  Future<AccountTransactionReparseResult> reparseAccountTransactions({
    required int bankId,
    required String accountNumber,
    required List<Transaction> transactions,
    DateTime? startDate,
    bool refreshExistingTransactions = true,
    bool importMissedTransactions = true,
    bool applyAutoCategorization = true,
  }) async {
    final preparation = await _prepareReparse(
      bankId: bankId,
      refreshExistingTransactions: refreshExistingTransactions,
      importMissedTransactions: importMissedTransactions,
      applyAutoCategorization: applyAutoCategorization,
    );
    if (preparation.failure != null) {
      return preparation.failure!;
    }

    return _executeReparse(
      bank: preparation.bank,
      relevantPatterns: preparation.relevantPatterns,
      bankAccounts: preparation.bankAccounts,
      accountNumber: accountNumber,
      transactions: transactions,
      startDate: startDate,
      refreshExistingTransactions: refreshExistingTransactions,
      importMissedTransactions: importMissedTransactions,
      applyAutoCategorization: applyAutoCategorization,
    );
  }

  Future<AccountTransactionReparseStartResult>
      startReparseAccountTransactionsInBackground({
    required int bankId,
    required String accountNumber,
    required List<Transaction> transactions,
    DateTime? startDate,
    bool refreshExistingTransactions = true,
    bool importMissedTransactions = true,
    bool applyAutoCategorization = true,
  }) async {
    if (_syncStatusService.getSyncStatus(accountNumber, bankId) != null) {
      return const AccountTransactionReparseStartResult(
        started: false,
        errorMessage: 'This account is already syncing.',
      );
    }

    final preparation = await _prepareReparse(
      bankId: bankId,
      refreshExistingTransactions: refreshExistingTransactions,
      importMissedTransactions: importMissedTransactions,
      applyAutoCategorization: applyAutoCategorization,
    );
    if (preparation.failure != null) {
      return AccountTransactionReparseStartResult(
        started: false,
        errorMessage: preparation.failure!.errorMessage ??
            (preparation.failure!.unsupported
                ? 'Reparse is available only for SMS-backed bank accounts.'
                : preparation.failure!.permissionDenied
                    ? 'SMS permission is required to reparse transactions.'
                    : 'Could not start reparse.'),
      );
    }

    await _reportBackgroundProgress(
      accountNumber: accountNumber,
      bankId: bankId,
      bankLabel: preparation.bank.shortName,
      stage: 'Starting reparse...',
      progress: 0.0,
    );

    unawaited(
      _runReparseInBackground(
        bank: preparation.bank,
        relevantPatterns: preparation.relevantPatterns,
        bankAccounts: preparation.bankAccounts,
        accountNumber: accountNumber,
        transactions: transactions,
        startDate: startDate,
        refreshExistingTransactions: refreshExistingTransactions,
        importMissedTransactions: importMissedTransactions,
        applyAutoCategorization: applyAutoCategorization,
      ),
    );

    return const AccountTransactionReparseStartResult(started: true);
  }

  Future<_PreparedAccountTransactionReparse> _prepareReparse({
    required int bankId,
    required bool refreshExistingTransactions,
    required bool importMissedTransactions,
    required bool applyAutoCategorization,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return _PreparedAccountTransactionReparse.failure(
        const AccountTransactionReparseResult(unsupported: true),
      );
    }
    if (bankId == CashConstants.bankId) {
      return _PreparedAccountTransactionReparse.failure(
        const AccountTransactionReparseResult(
          unsupported: true,
          errorMessage: 'Cash transactions do not have source SMS receipts.',
        ),
      );
    }
    if (!refreshExistingTransactions &&
        !importMissedTransactions &&
        !applyAutoCategorization) {
      return _PreparedAccountTransactionReparse.failure(
        const AccountTransactionReparseResult(
          errorMessage: 'Choose at least one reparse action.',
        ),
      );
    }

    var permissionStatus = await Permission.sms.status;
    if (!permissionStatus.isGranted) {
      permissionStatus = await Permission.sms.request();
    }
    if (!permissionStatus.isGranted) {
      return _PreparedAccountTransactionReparse.failure(
        const AccountTransactionReparseResult(permissionDenied: true),
      );
    }

    _cachedBanks ??= await _bankConfigService.getBanks();
    final bank = _cachedBanks!.firstWhere(
      (item) => item.id == bankId,
      orElse: () => throw StateError('Bank $bankId not found'),
    );

    final patterns =
        await _smsConfigService.getPatterns(allowRemoteFetch: false);
    final relevantPatterns = patterns
        .where((pattern) => pattern.bankId == bankId)
        .toList(growable: false);
    final hasFallbackParser =
        await FallbackSmsParser.supportsBankId(bankId, requirePatterns: true);
    if (relevantPatterns.isEmpty && !hasFallbackParser) {
      return _PreparedAccountTransactionReparse.failure(
        const AccountTransactionReparseResult(
          errorMessage: 'No parsing patterns are configured for this bank.',
        ),
      );
    }

    final bankAccounts = (await _accountRepo.getAccounts())
        .where((account) => account.bank == bankId)
        .toList(growable: false);

    return _PreparedAccountTransactionReparse(
      bank: bank,
      relevantPatterns: relevantPatterns,
      bankAccounts: bankAccounts,
    );
  }

  Future<void> _runReparseInBackground({
    required Bank bank,
    required List<SmsPattern> relevantPatterns,
    required List<Account> bankAccounts,
    required String accountNumber,
    required List<Transaction> transactions,
    DateTime? startDate,
    required bool refreshExistingTransactions,
    required bool importMissedTransactions,
    required bool applyAutoCategorization,
  }) async {
    try {
      final result = await _executeReparse(
        bank: bank,
        relevantPatterns: relevantPatterns,
        bankAccounts: bankAccounts,
        accountNumber: accountNumber,
        transactions: transactions,
        startDate: startDate,
        refreshExistingTransactions: refreshExistingTransactions,
        importMissedTransactions: importMissedTransactions,
        applyAutoCategorization: applyAutoCategorization,
        onProgress: (stage, progress) => _reportBackgroundProgress(
          accountNumber: accountNumber,
          bankId: bank.id,
          bankLabel: bank.shortName,
          stage: stage,
          progress: progress,
        ),
      );

      _syncStatusService.clearSyncStatus(accountNumber, bank.id);
      final completionMessage = _buildCompletionMessage(
        result,
        startDate: startDate,
      );
      String? completionPayload;
      try {
        final debugResult =
            await AccountReparseResultService.instance.recordCompletedReparse(
          bankId: bank.id,
          bankLabel: bank.shortName,
          accountNumber: accountNumber,
          completionMessage: completionMessage,
          importedTransactions: result.importedTransactionDetails,
          removedDuplicateTransactions:
              result.removedDuplicateTransactionDetails,
        );
        completionPayload = NotificationService.accountReparseResultPayload(
          debugResult.id,
        );
      } catch (e) {
        if (kDebugMode) {
          print('debug: Failed to store reparse debug result: $e');
        }
      }
      await _notificationService.showAccountSyncComplete(
        accountNumber: accountNumber,
        bankId: bank.id,
        bankLabel: bank.shortName,
        message: completionMessage,
        payload: completionPayload,
      );
      BackgroundRefreshSignalService.notifyDataChanged();
    } catch (e) {
      _syncStatusService.clearSyncStatus(accountNumber, bank.id);
      await _notificationService.showAccountSyncComplete(
        accountNumber: accountNumber,
        bankId: bank.id,
        bankLabel: bank.shortName,
        message: 'Reparse failed: $e',
      );
    }
  }

  Future<void> _reportBackgroundProgress({
    required String accountNumber,
    required int bankId,
    required String bankLabel,
    required String stage,
    required double progress,
  }) async {
    final clampedProgress = progress.clamp(0.0, 1.0).toDouble();
    _syncStatusService.setSyncStatus(
      accountNumber,
      bankId,
      stage,
      progress: clampedProgress,
    );
    await _notificationService.showAccountSyncProgress(
      accountNumber: accountNumber,
      bankId: bankId,
      bankLabel: bankLabel,
      stage: 'Reparsing',
      progress: clampedProgress,
      includePercentInBody: false,
    );
  }

  Future<AccountTransactionReparseResult> _executeReparse({
    required Bank bank,
    required List<SmsPattern> relevantPatterns,
    required List<Account> bankAccounts,
    required String accountNumber,
    required List<Transaction> transactions,
    DateTime? startDate,
    required bool refreshExistingTransactions,
    required bool importMissedTransactions,
    required bool applyAutoCategorization,
    _ReparseProgressCallback? onProgress,
  }) async {
    await onProgress?.call('Loading transactions...', 0.08);

    final existingByReference = await _buildExistingTransactionsByReference(
      bank: bank,
      accountNumber: accountNumber,
      hintedTransactions: transactions,
      bankAccounts: bankAccounts,
    );
    final existingSourceMessageIds =
        _sourceMessageIds(existingByReference.values);
    final existingSourceFingerprints =
        _sourceFingerprints(existingByReference.values);

    await onProgress?.call('Fetching bank messages...', 0.2);
    final normalizedStartDate = _normalizeStartDate(startDate);
    final messages = await _loadBankMessages(
      bank,
      startDate: normalizedStartDate,
    );
    final totalMessages = messages.length;
    if (totalMessages == 0) {
      await onProgress?.call('No bank messages found.', 1.0);
      return const AccountTransactionReparseResult();
    }

    await onProgress?.call('Reparsing 0/$totalMessages messages...', 0.24);
    int parsedMessages = 0;
    final matchedReferences = <String>{};
    final updatedReferences = <String>{};
    final importedReferences = <String>{};
    final importedTransactionDetails = <Transaction>[];
    final categorizedReferences = <String>{};
    final linkAddedReferences = <String>{};
    final parsedSourceSmsTransactions = <_ParsedSourceSmsTransaction>[];

    for (var index = 0; index < messages.length; index++) {
      try {
        final message = messages[index];
        final body = message.body;
        final address = message.address;
        if (body == null || address == null) continue;

        final messageDate = message.date == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(message.date!);
        final cleanedBody = _smsConfigService.cleanSmsText(body);
        var details = relevantPatterns.isEmpty
            ? null
            : await PatternParser.extractTransactionDetails(
                cleanedBody,
                address,
                messageDate,
                relevantPatterns,
                banks: _cachedBanks,
              );
        details ??= await FallbackSmsParser.extractTransactionDetails(
          messageBody: cleanedBody,
          senderAddress: address,
          messageDate: messageDate,
          bank: bank,
        );
        if (details == null) continue;
        final parsedBankId = (details['bankId'] as num?)?.toInt() ?? bank.id;
        final source = SmsTransactionSource.fromMessage(
          message: message,
          bankId: parsedBankId,
        );
        details.addAll(source.toJson());
        parsedMessages++;

        if (!_parsedMessageBelongsToTargetAccount(
          bank,
          accountNumber,
          details,
          bankAccounts,
        )) {
          continue;
        }

        final referenceKey = _referenceKey(details['reference']?.toString());
        final reparsed = Transaction.fromJson(details);
        final sourceKey = _sourceKeyFromDetails(details);
        if (sourceKey != null) {
          parsedSourceSmsTransactions.add(
            _ParsedSourceSmsTransaction(
              transaction: reparsed,
              sourceKey: sourceKey,
              referenceKey: referenceKey,
              messageDate: messageDate,
            ),
          );
        }

        final existing =
            referenceKey == null ? null : existingByReference[referenceKey];
        if (existing != null) {
          if (!_matchesAccount(
            bank,
            accountNumber,
            existing,
            details,
            bankAccounts,
          )) {
            continue;
          }

          matchedReferences.add(referenceKey!);
          var transactionToSave = existing;
          var didUpdate = false;

          if (refreshExistingTransactions) {
            final updated = _mergeParsedFields(existing, reparsed);
            if (updated != null) {
              transactionToSave = updated;
              didUpdate = true;
            }
          }

          var didCategorize = false;
          if (applyAutoCategorization) {
            final categorized =
                await _applyAutoCategorizationIfPossible(transactionToSave);
            if (categorized != null) {
              transactionToSave = categorized;
              didCategorize = true;
            }
          }

          if (!didUpdate && !didCategorize) {
            continue;
          }

          await _transactionRepo.saveTransaction(
            transactionToSave,
            skipAutoCategorization: true,
          );
          existingByReference[referenceKey] = transactionToSave;
          _trackSource(
            transactionToSave,
            sourceMessageIds: existingSourceMessageIds,
            sourceFingerprints: existingSourceFingerprints,
          );
          if (didUpdate && !importedReferences.contains(referenceKey)) {
            updatedReferences.add(referenceKey);
          }
          if (didCategorize) {
            categorizedReferences.add(referenceKey);
          }
          if (!_hasText(existing.transactionLink) &&
              _hasText(transactionToSave.transactionLink)) {
            linkAddedReferences.add(referenceKey);
          }
          continue;
        }

        if (!importMissedTransactions) {
          continue;
        }

        if (_sourceAlreadyImported(
          details,
          sourceMessageIds: existingSourceMessageIds,
          sourceFingerprints: existingSourceFingerprints,
        )) {
          continue;
        }

        final importResult = await SmsService.retryFailedParse(
          body,
          address,
          messageDate: messageDate,
          sourceMessageId: message.id,
          skipDashenExpenseDuplicates: true,
          skipAutoCategorization: !applyAutoCategorization,
        );
        if (importResult.status != ParseStatus.success ||
            importResult.transaction == null) {
          continue;
        }

        final imported = importResult.transaction!;
        final importedReferenceKey = _referenceKey(imported.reference);
        if (importedReferenceKey != null) {
          existingByReference[importedReferenceKey] = imported;
          importedReferences.add(importedReferenceKey);
          importedTransactionDetails.add(imported);
          _trackSource(
            imported,
            sourceMessageIds: existingSourceMessageIds,
            sourceFingerprints: existingSourceFingerprints,
          );
          if (imported.categoryId != null) {
            categorizedReferences.add(importedReferenceKey);
          }
        }
      } finally {
        final processedCount = index + 1;
        if (_shouldReportProgress(processedCount, totalMessages)) {
          final progress = 0.24 + (processedCount / totalMessages) * 0.66;
          await onProgress?.call(
            'Reparsing $processedCount/$totalMessages messages...',
            progress,
          );
        }
      }
    }

    await onProgress?.call('Checking SMS sources...', 0.94);
    final sourceCleanupResult = await _resolveSourceBackedDuplicatesForAccount(
      bank: bank,
      accountNumber: accountNumber,
      bankAccounts: bankAccounts,
      parsedSmsTransactions: parsedSourceSmsTransactions,
      startDate: normalizedStartDate,
    );
    updatedReferences.addAll(sourceCleanupResult.updatedReferences);
    linkAddedReferences.addAll(sourceCleanupResult.linkAddedReferences);

    await onProgress?.call('Finishing reparse...', 1.0);
    return AccountTransactionReparseResult(
      scannedMessages: messages.length,
      parsedMessages: parsedMessages,
      matchedTransactions: matchedReferences.length,
      updatedTransactions: updatedReferences.length,
      importedTransactions: importedReferences.length,
      categorizedTransactions: categorizedReferences.length,
      addedReceiptLinks: linkAddedReferences.length,
      removedDuplicateTransactions:
          sourceCleanupResult.removedDuplicateTransactions,
      importedTransactionDetails: importedTransactionDetails,
      removedDuplicateTransactionDetails:
          sourceCleanupResult.removedDuplicateTransactionDetails,
    );
  }

  Future<_SourceDuplicateCleanupResult>
      _resolveSourceBackedDuplicatesForAccount({
    required Bank bank,
    required String accountNumber,
    required List<Account> bankAccounts,
    required List<_ParsedSourceSmsTransaction> parsedSmsTransactions,
    DateTime? startDate,
  }) async {
    if (parsedSmsTransactions.isEmpty) {
      return const _SourceDuplicateCleanupResult();
    }

    final parsedBySourceKey = <String, _ParsedSourceSmsTransaction>{};
    for (final parsed in parsedSmsTransactions) {
      parsedBySourceKey.putIfAbsent(parsed.sourceKey, () => parsed);
    }
    if (parsedBySourceKey.isEmpty) {
      return const _SourceDuplicateCleanupResult();
    }

    final transactions = (await _transactionRepo.getTransactions())
        .where(
          (transaction) => _transactionBelongsToTargetAccount(
            transaction,
            bank: bank,
            accountNumber: accountNumber,
            bankAccounts: bankAccounts,
          ),
        )
        .where((transaction) => _transactionFallsInReparseRange(
              transaction,
              startDate,
            ))
        .toList(growable: false);
    if (transactions.isEmpty) {
      return const _SourceDuplicateCleanupResult();
    }

    final matchesBySourceKey = <String, List<Transaction>>{};
    for (final transaction in transactions) {
      final matches = <_ParsedSourceSmsTransaction>[];
      for (final parsed in parsedBySourceKey.values) {
        if (_transactionMatchesParsedSmsSource(
          transaction,
          parsed,
          bank: bank,
          accountNumber: accountNumber,
          bankAccounts: bankAccounts,
        )) {
          matches.add(parsed);
        }
      }
      if (matches.length != 1) {
        continue;
      }
      matchesBySourceKey
          .putIfAbsent(matches.single.sourceKey, () => <Transaction>[])
          .add(transaction);
    }

    if (matchesBySourceKey.isEmpty) {
      return const _SourceDuplicateCleanupResult();
    }

    final updatedReferences = <String>{};
    final linkAddedReferences = <String>{};
    final removedDuplicateTransactionDetails = <Transaction>[];
    var removedDuplicateTransactions = 0;

    for (final entry in matchesBySourceKey.entries) {
      final parsed = parsedBySourceKey[entry.key];
      if (parsed == null) continue;

      final matches = _dedupeTransactionsByReference(entry.value);
      if (matches.isEmpty) continue;

      final keeper = _selectSourceBackedKeeper(matches, parsed);
      final mergedKeeper = _mergeSourceBackedTransactions(
        keeper: keeper,
        matches: matches,
        parsed: parsed.transaction,
      );
      final duplicateReferences = matches
          .where((transaction) => transaction.reference != keeper.reference)
          .map((transaction) => transaction.reference)
          .toSet();
      final duplicateTransactions = matches
          .where((transaction) =>
              duplicateReferences.contains(transaction.reference))
          .toList(growable: false);

      if (!_isSameTransaction(keeper, mergedKeeper)) {
        await _transactionRepo.saveTransaction(
          mergedKeeper,
          skipAutoCategorization: true,
        );
        updatedReferences.add(mergedKeeper.reference);
        if (!_hasText(keeper.transactionLink) &&
            _hasText(mergedKeeper.transactionLink)) {
          linkAddedReferences.add(mergedKeeper.reference);
        }
      }

      if (duplicateReferences.isNotEmpty) {
        await _transactionRepo.deleteTransactionsByReferences(
          duplicateReferences,
        );
        removedDuplicateTransactions += duplicateReferences.length;
        removedDuplicateTransactionDetails.addAll(duplicateTransactions);
      }
    }

    return _SourceDuplicateCleanupResult(
      updatedReferences: updatedReferences,
      linkAddedReferences: linkAddedReferences,
      removedDuplicateTransactions: removedDuplicateTransactions,
      removedDuplicateTransactionDetails: removedDuplicateTransactionDetails,
    );
  }

  bool _transactionMatchesParsedSmsSource(
    Transaction transaction,
    _ParsedSourceSmsTransaction parsed, {
    required Bank bank,
    required String accountNumber,
    required List<Account> bankAccounts,
  }) {
    final transactionSourceKey = _sourceKeyFromTransaction(transaction);
    if (transactionSourceKey == parsed.sourceKey) {
      return true;
    }
    if (_sameSourceMessageId(transaction, parsed.transaction)) {
      return true;
    }
    // Legacy SMS fingerprints included provider timestamps. If a stored
    // fingerprint does not match the newly parsed source, keep checking the
    // stricter transaction fields below before deciding it is unrelated.

    final transactionReferenceKey = _referenceKey(transaction.reference);
    if (parsed.referenceKey != null &&
        transactionReferenceKey == parsed.referenceKey) {
      return true;
    }

    if (transaction.bankId != parsed.transaction.bankId) return false;
    if (!_sameTransactionType(transaction.type, parsed.transaction.type)) {
      return false;
    }
    if ((transaction.amount - parsed.transaction.amount).abs() > 0.0001) {
      return false;
    }
    if (!_sameParsedBalance(
      transaction.currentBalance,
      parsed.transaction.currentBalance,
    )) {
      return false;
    }
    if (!_transactionAccountMatchesParsedSms(
      bank,
      accountNumber,
      transaction,
      parsed.transaction,
      bankAccounts,
    )) {
      return false;
    }

    return _transactionIsNearParsedSmsDate(transaction, parsed.messageDate);
  }

  bool _sameSourceMessageId(Transaction transaction, Transaction parsed) {
    if (transaction.sourceType != SmsTransactionSource.smsType ||
        parsed.sourceType != SmsTransactionSource.smsType) {
      return false;
    }
    final transactionMessageId = transaction.sourceMessageId?.trim();
    final parsedMessageId = parsed.sourceMessageId?.trim();
    return transactionMessageId != null &&
        transactionMessageId.isNotEmpty &&
        transactionMessageId == parsedMessageId;
  }

  List<Transaction> _dedupeTransactionsByReference(
    Iterable<Transaction> transactions,
  ) {
    final byReference = <String, Transaction>{};
    for (final transaction in transactions) {
      final existing = byReference[transaction.reference];
      if (existing == null ||
          _transactionDetailScore(transaction) >
              _transactionDetailScore(existing)) {
        byReference[transaction.reference] = transaction;
      }
    }
    return byReference.values.toList(growable: false);
  }

  Transaction _selectSourceBackedKeeper(
    List<Transaction> transactions,
    _ParsedSourceSmsTransaction parsed,
  ) {
    var keeper = transactions.first;
    for (final candidate in transactions.skip(1)) {
      if (_sourceKeeperScore(candidate, parsed) >
          _sourceKeeperScore(keeper, parsed)) {
        keeper = candidate;
      }
    }
    return keeper;
  }

  int _sourceKeeperScore(
    Transaction transaction,
    _ParsedSourceSmsTransaction parsed,
  ) {
    var score = _transactionDetailScore(transaction);
    if (_referenceKey(transaction.reference) == parsed.referenceKey) {
      score += 1000;
    }
    if (_sourceKeyFromTransaction(transaction) == parsed.sourceKey) {
      score += 500;
    }
    return score;
  }

  Transaction _mergeSourceBackedTransactions({
    required Transaction keeper,
    required List<Transaction> matches,
    required Transaction parsed,
  }) {
    var merged = _mergeParsedFields(keeper, parsed) ??
        keeper.copyWith(
          sourceType: parsed.sourceType,
          sourceMessageId: parsed.sourceMessageId,
          sourceFingerprint: parsed.sourceFingerprint,
        );

    for (final transaction in matches) {
      if (transaction.reference == keeper.reference) continue;
      merged = _mergeExistingTransactionFields(merged, transaction);
    }

    return merged.copyWith(
      sourceType: parsed.sourceType,
      sourceMessageId: parsed.sourceMessageId,
      sourceFingerprint: parsed.sourceFingerprint,
    );
  }

  Transaction _mergeExistingTransactionFields(
    Transaction current,
    Transaction candidate,
  ) {
    final categoryIds = _mergedCategoryIds(current, candidate);
    return Transaction(
      amount: current.amount,
      reference: current.reference,
      creditor: _pickText(current.creditor, candidate.creditor),
      receiver: _pickText(current.receiver, candidate.receiver),
      note: _pickText(current.note, candidate.note),
      time: _pickText(current.time, candidate.time),
      status: _pickText(current.status, candidate.status),
      currentBalance:
          _pickText(current.currentBalance, candidate.currentBalance),
      bankId: current.bankId ?? candidate.bankId,
      type: _pickText(current.type, candidate.type),
      transactionLink: _pickTransactionLink(
          current.transactionLink, candidate.transactionLink),
      accountNumber: _pickText(current.accountNumber, candidate.accountNumber),
      categoryId: current.categoryId ?? candidate.categoryId,
      categoryIds: categoryIds,
      profileId: current.profileId ?? candidate.profileId,
      serviceCharge:
          _pickAmount(current.serviceCharge, candidate.serviceCharge),
      vat: _pickAmount(current.vat, candidate.vat),
      sourceType: _pickText(current.sourceType, candidate.sourceType),
      sourceMessageId:
          _pickText(current.sourceMessageId, candidate.sourceMessageId),
      sourceFingerprint:
          _pickText(current.sourceFingerprint, candidate.sourceFingerprint),
    );
  }

  List<int>? _mergedCategoryIds(Transaction left, Transaction right) {
    final ids = <int>[];
    void add(int id) {
      if (id > 0 && !ids.contains(id)) ids.add(id);
    }

    for (final id in left.selectedCategoryIds) {
      add(id);
    }
    for (final id in right.selectedCategoryIds) {
      add(id);
    }
    return ids.isEmpty ? null : ids;
  }

  bool _sameTransactionType(String? left, String? right) {
    return (left ?? '').trim().toUpperCase() ==
        (right ?? '').trim().toUpperCase();
  }

  bool _sameParsedBalance(String? left, String? right) {
    final leftValue = _parseBalance(left);
    final rightValue = _parseBalance(right);
    if (leftValue == null || rightValue == null) return false;
    return (leftValue - rightValue).abs() <= 0.0001;
  }

  double? _parseBalance(String? value) {
    final cleaned = value?.trim().replaceAll(',', '');
    if (cleaned == null || cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  bool _transactionAccountMatchesParsedSms(
    Bank bank,
    String accountNumber,
    Transaction transaction,
    Transaction parsed,
    List<Account> bankAccounts,
  ) {
    if (bank.uniformMasking == false) return true;

    final parsedAccount = _normalizeText(parsed.accountNumber);
    final transactionAccount = _normalizeText(transaction.accountNumber);
    if (parsedAccount != null && transactionAccount != null) {
      return _accountsMatch(bank, parsedAccount, transactionAccount);
    }
    if (parsedAccount != null) {
      return _accountsMatch(bank, parsedAccount, accountNumber);
    }
    if (transactionAccount != null) {
      return _accountsMatch(bank, transactionAccount, accountNumber);
    }

    return _isOnlyRegisteredAccountForBank(
      bank: bank,
      accountNumber: accountNumber,
      bankAccounts: bankAccounts,
    );
  }

  bool _transactionIsNearParsedSmsDate(
    Transaction transaction,
    DateTime? messageDate,
  ) {
    if (messageDate == null) return false;
    final transactionTime = DateTime.tryParse(transaction.time ?? '');
    if (transactionTime == null) return false;
    return transactionTime.difference(messageDate).abs() <=
        _sourceAnchoredDuplicateWindow;
  }

  bool _transactionFallsInReparseRange(
    Transaction transaction,
    DateTime? startDate,
  ) {
    if (startDate == null) return true;
    final transactionTime = DateTime.tryParse(transaction.time ?? '');
    if (transactionTime == null) return false;
    return !transactionTime.isBefore(startDate);
  }

  String _buildCompletionMessage(
    AccountTransactionReparseResult result, {
    DateTime? startDate,
  }) {
    final startLabel =
        startDate == null ? '' : ' since ${_formatCompletionDate(startDate)}';
    final actionParts = <String>[
      if (result.updatedTransactions > 0)
        'updated ${result.updatedTransactions}',
      if (result.importedTransactions > 0)
        'imported ${result.importedTransactions}',
      if (result.categorizedTransactions > 0)
        'auto-categorized ${result.categorizedTransactions}',
      if (result.removedDuplicateTransactions > 0)
        'removed ${result.removedDuplicateTransactions} duplicate'
            '${result.removedDuplicateTransactions == 1 ? '' : 's'}',
    ];

    if (actionParts.isEmpty) {
      return 'No matching transactions changed. '
          'Scanned ${result.scannedMessages} bank messages$startLabel.';
    }

    final actionSummary = _formatActionSummary(actionParts);
    final suffix = result.addedReceiptLinks > 0
        ? ' Added ${result.addedReceiptLinks} receipt '
            'link${result.addedReceiptLinks == 1 ? '' : 's'}.'
        : '';
    return '${actionSummary[0].toUpperCase()}${actionSummary.substring(1)} '
        'transactions$startLabel.$suffix';
  }

  String _formatActionSummary(List<String> actionParts) {
    if (actionParts.length == 1) return actionParts.first;
    if (actionParts.length == 2) {
      return '${actionParts[0]} and ${actionParts[1]}';
    }
    return '${actionParts.take(actionParts.length - 1).join(", ")}, '
        'and ${actionParts.last}';
  }

  String _formatCompletionDate(DateTime date) {
    final normalized = _normalizeStartDate(date) ?? date;
    final month = _monthAbbreviation(normalized.month);
    return '$month ${normalized.day}, ${normalized.year}';
  }

  String _monthAbbreviation(int month) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (month < 1 || month >= months.length) return '';
    return months[month];
  }

  bool _shouldReportProgress(int processedCount, int totalMessages) {
    if (processedCount <= 0 || totalMessages <= 0) return false;
    if (processedCount == totalMessages) return true;
    if (totalMessages <= 20) return true;
    return processedCount % 10 == 0;
  }

  Future<List<SmsMessage>> _loadBankMessages(
    Bank bank, {
    DateTime? startDate,
  }) async {
    final bankCodes =
        bank.codes.where((code) => code.trim().isNotEmpty).toList();
    final allMessages = <SmsMessage>[];
    final startMillis = startDate?.millisecondsSinceEpoch;

    if (bankCodes.isEmpty) {
      allMessages.addAll(
        await _telephony.getInboxSms(
          columns: const [
            SmsColumn.ADDRESS,
            SmsColumn.ID,
            SmsColumn.BODY,
            SmsColumn.DATE,
          ],
          sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
          filter: startMillis == null
              ? null
              : SmsFilter.where(
                  SmsColumn.DATE,
                ).greaterThanOrEqualTo(startMillis.toString()),
        ),
      );
    } else {
      for (final code in bankCodes.toSet()) {
        var filter = SmsFilter.where(SmsColumn.ADDRESS).like('%$code%');
        if (startMillis != null) {
          filter = filter
              .and(
                SmsColumn.DATE,
              )
              .greaterThanOrEqualTo(startMillis.toString());
        }
        final batch = await _telephony.getInboxSms(
          columns: const [
            SmsColumn.ADDRESS,
            SmsColumn.ID,
            SmsColumn.BODY,
            SmsColumn.DATE,
          ],
          sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
          filter: filter,
        );
        allMessages.addAll(batch);
      }
    }

    final byKey = <String, SmsMessage>{};
    for (final message in allMessages) {
      if (startMillis != null &&
          (message.date == null || message.date! < startMillis)) {
        continue;
      }
      final address = message.address;
      final body = message.body;
      if (address == null || body == null) continue;
      if (!_matchesBankAddress(bank, address)) continue;
      final key = message.id == null
          ? '${message.date}_${address.trim()}_${body.trim()}'
          : 'id:${message.id}';
      byKey.putIfAbsent(key, () => message);
    }

    final unique = byKey.values.toList(growable: false);
    unique.sort((a, b) => (b.date ?? 0).compareTo(a.date ?? 0));
    return unique;
  }

  DateTime? _normalizeStartDate(DateTime? startDate) {
    if (startDate == null) return null;
    final local = startDate.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  Future<Map<String, Transaction>> _buildExistingTransactionsByReference({
    required Bank bank,
    required String accountNumber,
    required List<Transaction> hintedTransactions,
    required List<Account> bankAccounts,
  }) async {
    final allTransactions = await _transactionRepo.getTransactions();
    final matchingTransactions = <String, Transaction>{};

    void collect(Transaction transaction) {
      if (!_transactionBelongsToTargetAccount(
        transaction,
        bank: bank,
        accountNumber: accountNumber,
        bankAccounts: bankAccounts,
      )) {
        return;
      }

      final identityKey = _transactionIdentityKey(transaction);
      final existing = matchingTransactions[identityKey];
      if (existing == null ||
          _transactionDetailScore(transaction) >
              _transactionDetailScore(existing)) {
        matchingTransactions[identityKey] = transaction;
      }
    }

    for (final transaction in hintedTransactions) {
      collect(transaction);
    }
    for (final transaction in allTransactions) {
      collect(transaction);
    }

    final byReference = <String, Transaction>{};
    for (final transaction in matchingTransactions.values) {
      final referenceKey = _referenceKey(transaction.reference);
      if (referenceKey == null) continue;
      final existing = byReference[referenceKey];
      if (existing == null ||
          _transactionDetailScore(transaction) >
              _transactionDetailScore(existing)) {
        byReference[referenceKey] = transaction;
      }
    }
    return byReference;
  }

  bool _matchesBankAddress(Bank bank, String address) {
    return senderAddressMatchesBank(
      bank,
      address,
      allBanks: _cachedBanks,
    );
  }

  Set<String> _sourceMessageIds(Iterable<Transaction> transactions) {
    return transactions
        .map((transaction) => transaction.sourceMessageId)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Set<String> _sourceFingerprints(Iterable<Transaction> transactions) {
    return transactions
        .map((transaction) => transaction.sourceFingerprint)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  String? _sourceKeyFromDetails(Map<String, dynamic> details) {
    if (details['sourceType'] != SmsTransactionSource.smsType) return null;
    final sourceFingerprint = details['sourceFingerprint']?.toString().trim();
    if (sourceFingerprint != null && sourceFingerprint.isNotEmpty) {
      return 'fingerprint:$sourceFingerprint';
    }

    final sourceMessageId = details['sourceMessageId']?.toString().trim();
    if (sourceMessageId != null && sourceMessageId.isNotEmpty) {
      return 'message:$sourceMessageId';
    }
    return null;
  }

  String? _sourceKeyFromTransaction(Transaction transaction) {
    if (transaction.sourceType != SmsTransactionSource.smsType) return null;
    final sourceFingerprint = transaction.sourceFingerprint?.trim();
    if (sourceFingerprint != null && sourceFingerprint.isNotEmpty) {
      return 'fingerprint:$sourceFingerprint';
    }

    final sourceMessageId = transaction.sourceMessageId?.trim();
    if (sourceMessageId != null && sourceMessageId.isNotEmpty) {
      return 'message:$sourceMessageId';
    }
    return null;
  }

  bool _sourceAlreadyImported(
    Map<String, dynamic> details, {
    required Set<String> sourceMessageIds,
    required Set<String> sourceFingerprints,
  }) {
    if (details['sourceType'] != SmsTransactionSource.smsType) return false;

    final sourceFingerprint = details['sourceFingerprint']?.toString().trim();
    if (sourceFingerprint != null &&
        sourceFingerprint.isNotEmpty &&
        sourceFingerprints.contains(sourceFingerprint)) {
      return true;
    }

    final sourceMessageId = details['sourceMessageId']?.toString().trim();
    if (sourceMessageId == null ||
        sourceMessageId.isEmpty ||
        !sourceMessageIds.contains(sourceMessageId)) {
      return false;
    }

    return sourceFingerprint == null ||
        sourceFingerprint.isEmpty ||
        sourceFingerprints.contains(sourceFingerprint);
  }

  void _trackSource(
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

  bool _matchesAccount(
    Bank bank,
    String accountNumber,
    Transaction existing,
    Map<String, dynamic> details,
    List<Account> bankAccounts,
  ) {
    if (bank.uniformMasking == false) {
      return true;
    }

    final parsedAccount = _normalizeText(details['accountNumber']?.toString());
    if (parsedAccount != null) {
      return _accountsMatch(bank, parsedAccount, accountNumber);
    }

    final existingAccount = _normalizeText(existing.accountNumber);
    if (existingAccount != null) {
      return _accountsMatch(bank, existingAccount, accountNumber);
    }

    return _isOnlyRegisteredAccountForBank(
      bank: bank,
      accountNumber: accountNumber,
      bankAccounts: bankAccounts,
    );
  }

  bool _parsedMessageBelongsToTargetAccount(
    Bank bank,
    String accountNumber,
    Map<String, dynamic> details,
    List<Account> bankAccounts,
  ) {
    if (bank.uniformMasking == false) {
      return true;
    }

    final parsedAccount = _normalizeText(details['accountNumber']?.toString());
    if (parsedAccount != null) {
      return _accountsMatch(bank, parsedAccount, accountNumber);
    }

    return _isOnlyRegisteredAccountForBank(
      bank: bank,
      accountNumber: accountNumber,
      bankAccounts: bankAccounts,
    );
  }

  bool _transactionBelongsToTargetAccount(
    Transaction transaction, {
    required Bank bank,
    required String accountNumber,
    required List<Account> bankAccounts,
  }) {
    if (transaction.bankId != bank.id) return false;
    if (bank.uniformMasking == false) return true;

    final transactionAccount = _normalizeText(transaction.accountNumber);
    if (transactionAccount == null) {
      return _isOnlyRegisteredAccountForBank(
        bank: bank,
        accountNumber: accountNumber,
        bankAccounts: bankAccounts,
      );
    }

    return _accountsMatch(bank, transactionAccount, accountNumber);
  }

  bool _isOnlyRegisteredAccountForBank({
    required Bank bank,
    required String accountNumber,
    required List<Account> bankAccounts,
  }) {
    if (bankAccounts.length != 1) return false;
    return _accountsMatch(
        bank, bankAccounts.first.accountNumber, accountNumber);
  }

  bool _accountsMatch(Bank bank, String leftAccount, String rightAccount) {
    if (bank.uniformMasking == false) {
      return true;
    }
    if (bank.uniformMasking == true) {
      return _accountSuffix(leftAccount, bank) ==
          _accountSuffix(rightAccount, bank);
    }
    return leftAccount.trim() == rightAccount.trim();
  }

  String _accountSuffix(String accountNumber, Bank bank) {
    final trimmed = accountNumber.trim();
    final maskLength = bank.maskPattern;
    if (maskLength == null || maskLength <= 0 || trimmed.length <= maskLength) {
      return trimmed;
    }
    return trimmed.substring(trimmed.length - maskLength);
  }

  Transaction? _mergeParsedFields(Transaction existing, Transaction reparsed) {
    final updated = Transaction(
      amount: existing.amount,
      reference: existing.reference,
      creditor: _pickText(existing.creditor, reparsed.creditor),
      receiver: _pickText(existing.receiver, reparsed.receiver),
      note: existing.note,
      time: _pickText(existing.time, reparsed.time),
      status: _pickText(existing.status, reparsed.status),
      currentBalance:
          _pickText(existing.currentBalance, reparsed.currentBalance),
      bankId: existing.bankId ?? reparsed.bankId,
      type: _pickText(existing.type, reparsed.type),
      transactionLink: _pickTransactionLink(
          existing.transactionLink, reparsed.transactionLink),
      accountNumber: _pickText(existing.accountNumber, reparsed.accountNumber),
      categoryId: existing.categoryId,
      categoryIds: existing.categoryIds,
      profileId: existing.profileId,
      serviceCharge:
          _pickAmount(existing.serviceCharge, reparsed.serviceCharge),
      vat: _pickAmount(existing.vat, reparsed.vat),
      sourceType: _pickText(existing.sourceType, reparsed.sourceType),
      sourceMessageId:
          _pickText(existing.sourceMessageId, reparsed.sourceMessageId),
      sourceFingerprint:
          _pickText(existing.sourceFingerprint, reparsed.sourceFingerprint),
    );

    if (_isSameTransaction(existing, updated)) {
      return null;
    }
    return updated;
  }

  Future<Transaction?> _applyAutoCategorizationIfPossible(
    Transaction transaction,
  ) async {
    if (transaction.categoryId != null) return null;

    final selection =
        await _autoCategorizationService.getCategorySelectionForTransaction(
      type: transaction.type,
      receiver: transaction.receiver,
      creditor: transaction.creditor,
    );
    if (selection == null || selection.isEmpty) return null;

    return transaction.copyWith(
      categoryId: selection.primaryCategoryId,
      categoryIds: selection.categoryIds,
    );
  }

  bool _isSameTransaction(Transaction a, Transaction b) {
    return a.amount == b.amount &&
        a.reference == b.reference &&
        a.creditor == b.creditor &&
        a.receiver == b.receiver &&
        a.note == b.note &&
        a.time == b.time &&
        a.status == b.status &&
        a.currentBalance == b.currentBalance &&
        a.bankId == b.bankId &&
        a.type == b.type &&
        a.transactionLink == b.transactionLink &&
        a.accountNumber == b.accountNumber &&
        a.categoryId == b.categoryId &&
        listEquals(a.selectedCategoryIds, b.selectedCategoryIds) &&
        a.profileId == b.profileId &&
        a.serviceCharge == b.serviceCharge &&
        a.vat == b.vat &&
        a.sourceType == b.sourceType &&
        a.sourceMessageId == b.sourceMessageId &&
        a.sourceFingerprint == b.sourceFingerprint;
  }

  String? _pickText(String? existing, String? reparsed) {
    final normalizedExisting = _normalizeText(existing);
    if (normalizedExisting != null) return existing;
    return _normalizeText(reparsed);
  }

  String? _pickTransactionLink(String? existing, String? reparsed) {
    final normalizedExisting = _normalizeText(existing);
    if (normalizedExisting != null) return normalizedExisting;
    return _normalizeText(reparsed);
  }

  double? _pickAmount(double? existing, double? reparsed) {
    if (_hasMeaningfulAmount(existing)) return existing;
    if (_hasMeaningfulAmount(reparsed)) return reparsed;
    return existing;
  }

  bool _hasMeaningfulAmount(double? value) {
    return value != null && value != 0;
  }

  String? _referenceKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  String _transactionIdentityKey(Transaction transaction) {
    final referenceKey = _referenceKey(transaction.reference);
    if (referenceKey != null) {
      return 'ref:$referenceKey';
    }
    return [
      transaction.bankId ?? '',
      (transaction.type ?? '').trim().toUpperCase(),
      transaction.amount.toStringAsFixed(4),
      _normalizeText(transaction.time) ?? '',
      _normalizeText(transaction.accountNumber) ?? '',
      _normalizeText(transaction.currentBalance) ?? '',
    ].join('|');
  }

  int _transactionDetailScore(Transaction transaction) {
    var score = 0;
    if (_hasText(transaction.receiver)) score += 4;
    if (_hasText(transaction.creditor)) score += 4;
    if (_hasText(transaction.transactionLink)) score += 3;
    if (_hasText(transaction.accountNumber)) score += 2;
    if (_hasText(transaction.currentBalance)) score += 2;
    if (_hasText(transaction.status)) score += 1;
    if (_hasText(transaction.time)) score += 1;
    if (_hasMeaningfulAmount(transaction.serviceCharge)) score += 1;
    if (_hasMeaningfulAmount(transaction.vat)) score += 1;
    return score;
  }

  String? _normalizeText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  bool _hasText(String? value) => _normalizeText(value) != null;
}
