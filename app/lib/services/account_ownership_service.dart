import 'dart:async';

import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/background_refresh_signal_service.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/utils/account_identity.dart';
import 'package:totals/utils/account_balance_refresh.dart';
import 'package:totals/utils/bank_sender_matcher.dart';
import 'package:totals/utils/sms_message_classifier.dart';
import 'package:totals/utils/sms_transaction_source.dart';
import 'package:totals/utils/transaction_duplicate_detector.dart';

class AccountOwnershipReconciliationResult {
  final int assignedTransactions;
  final int learnedSubscriptions;
  final int unresolvedTransactions;

  const AccountOwnershipReconciliationResult({
    this.assignedTransactions = 0,
    this.learnedSubscriptions = 0,
    this.unresolvedTransactions = 0,
  });
}

/// Reconciles SMS-backed transactions with the account name and number entered
/// by the user. The raw parsed account number remains untouched; ownership is
/// stored separately in `ownerAccountNumber`.
class AccountOwnershipService {
  AccountOwnershipService._();

  static final AccountOwnershipService instance = AccountOwnershipService._();
  static const String _completedMigrationVersionKeyPrefix =
      'account_ownership_reconciliation_version_profile_';

  // Increment only when an app update requires existing ownership data to be
  // repaired again. Routine launches must not repeat the full inbox scan.
  static const int _requiredMigrationVersion = 1;

  final AccountRepository _accountRepository = AccountRepository();
  final ProfileRepository _profileRepository = ProfileRepository();
  final TransactionRepository _transactionRepository = TransactionRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  Future<AccountOwnershipReconciliationResult>? _activeReconciliation;
  Future<bool>? _activeMigration;
  int? _activeMigrationProfileId;
  Future<void>? _activeProfileSwitch;

  Future<AccountOwnershipReconciliationResult> reconcile({int? bankId}) async {
    while (true) {
      final active = _activeReconciliation;
      if (active != null) return active;

      // Wait outside the active-reconciliation slot. Registering a waiting
      // reconciliation there would let an older migration join it and create
      // a switch -> migration -> reconciliation -> switch cycle.
      final activeProfileSwitch = _activeProfileSwitch;
      if (activeProfileSwitch != null) {
        await activeProfileSwitch;
        continue;
      }
      return _startReconciliation(bankId: bankId);
    }
  }

  Future<AccountOwnershipReconciliationResult> _startReconciliation({
    int? bankId,
  }) {
    final active = _activeReconciliation;
    if (active != null) return active;
    final future = _reconcile(bankId: bankId);
    _activeReconciliation = future;
    return future.whenComplete(() {
      if (identical(_activeReconciliation, future)) {
        _activeReconciliation = null;
      }
    });
  }

  Future<void> switchActiveProfile(int profileId) async {
    final existingSwitch = _activeProfileSwitch;
    if (existingSwitch != null) {
      await existingSwitch;
      return switchActiveProfile(profileId);
    }

    // Capture existing work before publishing the switch gate. New ownership
    // repairs will wait on the gate and therefore run against the new profile.
    final migrationToWaitFor = _activeMigration;
    final reconciliationToWaitFor = _activeReconciliation;
    final switchCompleter = Completer<void>();
    final switchFuture = switchCompleter.future;
    _activeProfileSwitch = switchFuture;

    try {
      try {
        if (migrationToWaitFor != null) await migrationToWaitFor;
        if (reconciliationToWaitFor != null) {
          await reconciliationToWaitFor;
        }
      } catch (error) {
        debugPrint(
          'debug: Ownership repair failed before profile switch: $error',
        );
      }
      await _profileRepository.setActiveProfile(profileId);
    } finally {
      switchCompleter.complete();
      if (identical(_activeProfileSwitch, switchFuture)) {
        _activeProfileSwitch = null;
      }
    }

    unawaited(() async {
      try {
        await runPendingMigration();
      } catch (error) {
        debugPrint(
          'debug: Pending ownership migration after profile switch failed: '
          '$error',
        );
      }
    }());
  }

  Future<bool> runPendingMigration() async {
    while (true) {
      final activeProfileSwitch = _activeProfileSwitch;
      if (activeProfileSwitch != null) {
        await activeProfileSwitch;
        continue;
      }

      final requestedProfileId = await _profileRepository.getActiveProfileId();
      if (_activeProfileSwitch != null) {
        continue;
      }

      final activeMigration = _activeMigration;
      if (activeMigration != null) {
        if (_activeMigrationProfileId == requestedProfileId) {
          return activeMigration;
        }
        await activeMigration;
        if (identical(_activeMigration, activeMigration)) {
          _activeMigration = null;
          _activeMigrationProfileId = null;
        }
        continue;
      }

      final migration = _runPendingMigration(requestedProfileId);
      _activeMigration = migration;
      _activeMigrationProfileId = requestedProfileId;
      try {
        return await migration;
      } finally {
        if (identical(_activeMigration, migration)) {
          _activeMigration = null;
          _activeMigrationProfileId = null;
        }
      }
    }
  }

  Future<bool> _runPendingMigration(int? activeProfileId) async {
    final prefs = await SharedPreferences.getInstance();
    final migrationVersionKey = migrationVersionPreferenceKey(activeProfileId);
    var completedVersion = prefs.getInt(migrationVersionKey) ?? 0;
    if (completedVersion >= _requiredMigrationVersion) {
      return false;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final smsPermission = await Permission.sms.status;
    if (!smsPermission.isGranted) {
      return false;
    }

    // A bank-scoped repair may already be running after account registration.
    // Let it finish, then still perform the full versioned migration.
    final activeReconciliation = _activeReconciliation;
    if (activeReconciliation != null) {
      await activeReconciliation;
      if (identical(_activeReconciliation, activeReconciliation)) {
        _activeReconciliation = null;
      }
      completedVersion = prefs.getInt(migrationVersionKey) ?? 0;
      if (completedVersion >= _requiredMigrationVersion) {
        return false;
      }
    }

    if (await _profileRepository.getActiveProfileId() != activeProfileId) {
      return false;
    }
    await _startReconciliation();
    if (await _profileRepository.getActiveProfileId() != activeProfileId) {
      return false;
    }
    final permissionAfterRepair = await Permission.sms.status;
    if (!permissionAfterRepair.isGranted) {
      return false;
    }
    await prefs.setInt(
      migrationVersionKey,
      _requiredMigrationVersion,
    );
    return true;
  }

  @visibleForTesting
  static String migrationVersionPreferenceKey(int? profileId) {
    return '$_completedMigrationVersionKeyPrefix${profileId ?? 'default'}';
  }

  Future<AccountOwnershipReconciliationResult> _reconcile({int? bankId}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const AccountOwnershipReconciliationResult();
    }
    final smsPermission = await Permission.sms.status;
    if (!smsPermission.isGranted) {
      return const AccountOwnershipReconciliationResult();
    }

    final banks = await _bankConfigService.getBanks(allowRemoteFetch: false);
    var accounts = await _accountRepository.getAccounts();
    final transactions = await _transactionRepository.getTransactions();
    final updates = <TransactionOwnershipUpdate>[];
    final obsoleteReferences = <String>{};
    var learnedSubscriptions = 0;
    var unresolvedTransactions = 0;

    for (final bank in banks) {
      if (bankId != null && bank.id != bankId) continue;
      var bankAccounts =
          accounts.where((account) => account.bank == bank.id).toList();
      if (bankAccounts.isEmpty) continue;

      final messages = await _loadBankMessages(bank, banks);
      if (messages.isEmpty) continue;
      final messagesById = <String, SmsMessage>{};
      final messagesByFingerprint = <String, List<SmsMessage>>{};
      final messagesByReference = <String, List<SmsMessage>>{};
      final obsoleteTelebirrCreditReferences = <String>{};
      final obsoleteTelebirrDebitReferences = <String>{};
      for (final message in messages) {
        if (message.id != null) {
          messagesById[message.id.toString()] = message;
        }
        final fingerprint = SmsTransactionSource.fromParts(
          bankId: bank.id,
          messageId: message.id,
          senderAddress: message.address,
          body: message.body,
          dateMillis: message.date,
        ).sourceFingerprint;
        if (fingerprint != null) {
          messagesByFingerprint
              .putIfAbsent(fingerprint, () => <SmsMessage>[])
              .add(message);
        }
        for (final messageReference in _messageReferences(message.body)) {
          final reference = SmsTransactionSource.canonicalReference(
            bankId: bank.id,
            storedReference: messageReference,
          );
          if (reference.isEmpty) continue;
          final matches = messagesByReference.putIfAbsent(
            reference,
            () => <SmsMessage>[],
          );
          if (!matches.contains(message)) matches.add(message);
        }
        final messageDateMillis = message.date;
        if (messageDateMillis != null) {
          // Native patterns without a bank reference historically used this
          // exact bank-and-SMS-timestamp value. Index it so old backups that
          // predate sourceMessageId/sourceFingerprint can reconnect to the
          // original inbox row during import reconciliation.
          final timestampReference = SmsTransactionSource.canonicalReference(
            bankId: bank.id,
            storedReference:
                '${bank.id}_${DateTime.fromMillisecondsSinceEpoch(messageDateMillis).toIso8601String()}',
          );
          final matches = messagesByReference.putIfAbsent(
            timestampReference,
            () => <SmsMessage>[],
          );
          if (!matches.contains(message)) matches.add(message);
        }
        if (bank.id == 6 && message.body != null) {
          final authorizationCode =
              SmsMessageClassifier.telebirrAtmAuthorizationCode(
            message.body!,
          );
          if (authorizationCode != null) {
            obsoleteTelebirrDebitReferences.add(
              SmsTransactionSource.canonicalReference(
                bankId: bank.id,
                storedReference: authorizationCode,
              ),
            );
          }
          final reference =
              SmsMessageClassifier.telebirrAirtimeReceiptReference(
            message.body!,
          );
          if (reference != null) {
            obsoleteTelebirrCreditReferences.add(
              SmsTransactionSource.canonicalReference(
                bankId: bank.id,
                storedReference: reference,
              ),
            );
          }
        }
      }

      final allBankTransactions = transactions
          .where((transaction) => transaction.bankId == bank.id)
          .toList(growable: false);
      final bankTransactions = <Transaction>[];
      for (final transaction in allBankTransactions) {
        final transactionType = (transaction.type ?? '').trim().toUpperCase();
        if (bank.id == 6 &&
            transactionType == 'CREDIT' &&
            obsoleteTelebirrCreditReferences.contains(
              SmsTransactionSource.canonicalReference(
                bankId: bank.id,
                storedReference: transaction.reference,
              ),
            )) {
          obsoleteReferences.add(transaction.reference);
          continue;
        }
        if (bank.id == 6 &&
            transactionType == 'DEBIT' &&
            obsoleteTelebirrDebitReferences.contains(
              SmsTransactionSource.canonicalReference(
                bankId: bank.id,
                storedReference: transaction.reference,
              ),
            )) {
          obsoleteReferences
            ..add(transaction.reference)
            ..add(CashConstants.buildAtmReference(transaction.reference));
          continue;
        }
        final message = _sourceMessage(
          transaction,
          messagesById: messagesById,
          messagesByFingerprint: messagesByFingerprint,
          messagesByReference: messagesByReference,
        );
        final messageBody = message?.body;
        if (bank.id == 6 &&
            messageBody != null &&
            SmsMessageClassifier.isTelebirrAtmAuthorization(messageBody)) {
          obsoleteReferences
            ..add(transaction.reference)
            ..add(CashConstants.buildAtmReference(transaction.reference));
          continue;
        }
        if (bank.id == 6 &&
            messageBody != null &&
            SmsMessageClassifier.isTelebirrCreditLineNotice(messageBody)) {
          obsoleteReferences.add(transaction.reference);
          continue;
        }
        bankTransactions.add(transaction);
      }
      final strongOwners = <String, Account>{};
      final subscriptionVotes = <String, Map<int, int>>{};

      // Pass one: number and anchored greeting evidence learn ownership and
      // conflict-free device subscription mappings.
      for (final transaction in bankTransactions) {
        // A user-selected owner is authoritative and must not be used as
        // evidence for a different automatic owner or SIM binding.
        if (transaction.hasManualOwnerAssignment) continue;
        final message = _sourceMessage(
          transaction,
          messagesById: messagesById,
          messagesByFingerprint: messagesByFingerprint,
          messagesByReference: messagesByReference,
        );
        final body = message?.body;
        if (body == null) continue;
        final owner = resolveSmsOwnership(
          bank: bank,
          accounts: bankAccounts,
          messageBody: body,
          parsedAccountNumber: transaction.accountNumber,
        );
        if (owner == null) continue;
        strongOwners[transaction.reference] = owner;
        final subscriptionId = message?.subscriptionId;
        if (subscriptionId != null && subscriptionId >= 0) {
          final votes = subscriptionVotes.putIfAbsent(
            owner.accountNumber,
            () => <int, int>{},
          );
          votes[subscriptionId] = (votes[subscriptionId] ?? 0) + 1;
        }
      }

      if (bank.simBased == true) {
        final proposedBindings = <String, int>{};
        for (final account in bankAccounts) {
          final votes = subscriptionVotes[account.accountNumber];
          if (votes == null || votes.isEmpty) continue;
          final ranked = votes.entries.toList()
            ..sort((left, right) => right.value.compareTo(left.value));
          if (ranked.length > 1 && ranked[0].value == ranked[1].value) continue;
          proposedBindings[account.accountNumber] = ranked.first.key;
        }
        final claims = <int, int>{};
        for (final subscriptionId in proposedBindings.values) {
          claims[subscriptionId] = (claims[subscriptionId] ?? 0) + 1;
        }
        for (final entry in proposedBindings.entries) {
          if (claims[entry.value] != 1) continue;
          final didBind = await _accountRepository.bindSmsSubscription(
            accountNumber: entry.key,
            bank: bank.id,
            subscriptionId: entry.value,
          );
          if (didBind) learnedSubscriptions++;
        }
      }

      accounts = await _accountRepository.getAccounts();
      bankAccounts =
          accounts.where((account) => account.bank == bank.id).toList();

      // Pass two: use the learned subscription mapping for messages that do
      // not carry a usable owner number or greeting.
      for (final transaction in bankTransactions) {
        if (transaction.hasManualOwnerAssignment) continue;
        final message = _sourceMessage(
          transaction,
          messagesById: messagesById,
          messagesByFingerprint: messagesByFingerprint,
          messagesByReference: messagesByReference,
        );
        final strongOwner = strongOwners[transaction.reference];
        final body = message?.body;
        final owner = strongOwner ??
            (body == null
                ? null
                : resolveSmsOwnership(
                    bank: bank,
                    accounts: bankAccounts,
                    messageBody: body,
                    parsedAccountNumber: transaction.accountNumber,
                    sourceSubscriptionId: message?.subscriptionId,
                  ));
        if (owner == null) {
          unresolvedTransactions++;

          // Repair rows previously poisoned by a transfer counterparty. An
          // explicit greeting for someone who is not registered proves that
          // any assignment to a currently registered account is incorrect.
          final assignedAccount = resolveTransactionOwnership(
            transaction: transaction,
            bank: bank,
            accounts: bankAccounts,
          );
          final hasConflictingGreeting = body != null &&
              hasUnmatchedSpecificAccountGreeting(body, bankAccounts);
          if (hasConflictingGreeting &&
              (assignedAccount != null ||
                  transaction.ownerAssignmentSource !=
                      Transaction.conflictingOwnerAssignment)) {
            updates.add(TransactionOwnershipUpdate(
              reference: transaction.reference,
              ownerAccountNumber: null,
              ownerAssignmentSource: Transaction.conflictingOwnerAssignment,
              sourceMessageId: message?.id?.toString(),
            ));
          }
          continue;
        }
        final alreadyOwned = registeredAccountNumbersMatch(
          bank,
          transaction.ownerAccountNumber,
          owner.accountNumber,
        );
        final subscriptionId = message?.subscriptionId;
        final hasSameSubscription = subscriptionId == null ||
            subscriptionId < 0 ||
            transaction.sourceSubscriptionId == subscriptionId;
        final hasMessageId =
            transaction.sourceMessageId?.trim().isNotEmpty == true;
        if (alreadyOwned && hasSameSubscription && hasMessageId) continue;
        updates.add(TransactionOwnershipUpdate(
          reference: transaction.reference,
          ownerAccountNumber: owner.accountNumber,
          ownerAssignmentSource: Transaction.automaticOwnerAssignment,
          sourceSubscriptionId: subscriptionId != null && subscriptionId >= 0
              ? subscriptionId
              : null,
          sourceMessageId: message?.id?.toString(),
        ));
      }
    }

    if (obsoleteReferences.isNotEmpty) {
      await _transactionRepository.deleteTransactionsByReferences(
        obsoleteReferences,
      );
    }
    final duplicatePlans = buildLegacySmsReferenceDeduplicationPlans(
      transactions: transactions.where(
        (transaction) => !obsoleteReferences.contains(transaction.reference),
      ),
    );
    for (final plan in duplicatePlans) {
      await _transactionRepository.saveTransaction(
        plan.mergedKeeper,
        skipAutoCategorization: true,
      );
    }
    final duplicateReferences =
        duplicatePlans.expand((plan) => plan.duplicateReferences).toSet();
    if (duplicateReferences.isNotEmpty) {
      await _transactionRepository.deleteTransactionsByReferences(
        duplicateReferences,
      );
    }
    final assigned =
        await _transactionRepository.updateTransactionOwnerships(updates);
    final balancesChanged = await _refreshAccountBalances();
    if (assigned > 0 ||
        balancesChanged ||
        obsoleteReferences.isNotEmpty ||
        duplicateReferences.isNotEmpty) {
      BackgroundRefreshSignalService.notifyDataChanged();
    }
    return AccountOwnershipReconciliationResult(
      assignedTransactions: assigned,
      learnedSubscriptions: learnedSubscriptions,
      unresolvedTransactions: unresolvedTransactions,
    );
  }

  SmsMessage? _sourceMessage(
    Transaction transaction, {
    required Map<String, SmsMessage> messagesById,
    required Map<String, List<SmsMessage>> messagesByFingerprint,
    required Map<String, List<SmsMessage>> messagesByReference,
  }) {
    final fingerprint = transaction.sourceFingerprint?.trim();
    if (fingerprint != null && fingerprint.isNotEmpty) {
      final matches = messagesByFingerprint[fingerprint];
      if (matches?.length == 1) return matches!.single;
    }

    final messageId = transaction.sourceMessageId?.trim();
    if (messageId != null && messageId.isNotEmpty) {
      final message = messagesById[messageId];
      if (message != null) return message;
    }

    // Very old exports may have neither the modern source fingerprint nor a
    // stable inbox row id. A unique bank reference still reconnects the row
    // without guessing by amount or date.
    final reference = SmsTransactionSource.canonicalReference(
      bankId: transaction.bankId,
      storedReference: transaction.reference,
    );
    final referenceMatches = messagesByReference[reference];
    if (referenceMatches?.length == 1) return referenceMatches!.single;
    return null;
  }

  Iterable<String> _messageReferences(String? body) sync* {
    if (body == null || body.trim().isEmpty) return;
    final pattern = RegExp(
      r'''(?:transaction\s+(?:number|no\.?|id)|txn\s*(?:id|no\.?)|ref(?:erence)?\s*(?:number|no\.?)?)\s*(?:is|:)?\s*([A-Z0-9][A-Z0-9@.\-]{4,})''',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(body)) {
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) yield value;
    }
  }

  Future<List<SmsMessage>> _loadBankMessages(
    Bank bank,
    List<Bank> allBanks,
  ) async {
    final messages = <String, SmsMessage>{};
    for (final code in bank.codes.toSet()) {
      final sender = code.trim();
      if (sender.isEmpty) continue;
      List<SmsMessage> rows;
      try {
        rows = await Telephony.instance.getInboxSms(
          columns: const [
            SmsColumn.ID,
            SmsColumn.ADDRESS,
            SmsColumn.BODY,
            SmsColumn.DATE,
            SmsColumn.SUBSCRIPTION_ID,
          ],
          filter: SmsFilter.where(SmsColumn.ADDRESS).like('%$sender%'),
          sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
        );
      } catch (_) {
        rows = await Telephony.instance.getInboxSms(
          columns: const [
            SmsColumn.ID,
            SmsColumn.ADDRESS,
            SmsColumn.BODY,
            SmsColumn.DATE,
          ],
          filter: SmsFilter.where(SmsColumn.ADDRESS).like('%$sender%'),
          sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
        );
      }
      for (final message in rows) {
        if (!senderAddressMatchesBank(
          bank,
          message.address,
          allBanks: allBanks,
        )) {
          continue;
        }
        final key = message.id?.toString() ??
            '${message.date}|${message.address}|${message.body}';
        messages[key] = message;
      }
    }
    return messages.values.toList(growable: false);
  }

  Future<bool> _refreshAccountBalances() async {
    final accounts = await _accountRepository.getAccounts();
    final banks = await _bankConfigService.getBanks(allowRemoteFetch: false);
    final bankById = {for (final bank in banks) bank.id: bank};
    final transactions = await _transactionRepository.getTransactions();
    var didChange = false;
    for (final account in accounts) {
      final bank = bankById[account.bank];
      if (bank == null || bank.simBased != true) continue;
      final balance = resolveRefreshedAccountBalance(
        account: account,
        bank: bank,
        accounts: accounts,
        banksById: bankById,
        transactions: transactions,
      );
      if (balance == null || (balance - account.balance).abs() < 0.0001) {
        continue;
      }
      await _accountRepository.saveAccount(Account(
        accountNumber: account.accountNumber,
        bank: account.bank,
        balance: balance,
        accountHolderName: account.accountHolderName,
        settledBalance: account.settledBalance,
        pendingCredit: account.pendingCredit,
        profileId: account.profileId,
        smsSubscriptionId: account.smsSubscriptionId,
      ));
      didChange = true;
    }
    return didChange;
  }
}
