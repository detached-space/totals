import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:totals/models/transaction_source_sms.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/transaction_source_sms_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/sms_transaction_source.dart';

export 'package:totals/models/transaction_source_sms.dart';

/// Resolves a transaction's durable SMS source identity back to the Android
/// inbox and persists a portable copy for export and restore.
class TransactionSmsSourceService {
  final Telephony? _telephonyOverride;
  final BankConfigService _bankConfigService;
  final TransactionSourceSmsRepository _sourceSmsRepository;

  TransactionSmsSourceService({
    Telephony? telephony,
    BankConfigService? bankConfigService,
    TransactionSourceSmsRepository? sourceSmsRepository,
  })  : _telephonyOverride = telephony,
        _bankConfigService = bankConfigService ?? BankConfigService(),
        _sourceSmsRepository =
            sourceSmsRepository ?? TransactionSourceSmsRepository();

  Telephony get _telephony => _telephonyOverride ?? Telephony.instance;

  static bool hasSmsSource(Transaction transaction) {
    final sourceType = transaction.sourceType?.trim().toLowerCase();
    return sourceType == SmsTransactionSource.smsType ||
        _hasText(transaction.sourceMessageId) ||
        _hasText(transaction.sourceFingerprint);
  }

  Future<TransactionSourceSms?> resolve(Transaction transaction) async {
    final stored =
        await _sourceSmsRepository.getForTransaction(transaction.reference);
    if (stored != null) return stored;

    if (!hasSmsSource(transaction) ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        transaction.bankId == null) {
      return null;
    }

    final permission = await Permission.sms.status;
    if (!permission.isGranted) return null;

    final messageId = int.tryParse(transaction.sourceMessageId?.trim() ?? '');
    if (messageId != null) {
      final rows = await _query(
        SmsFilter.where(SmsColumn.ID).equals(messageId.toString()),
      );
      final exact = _findMatch(
        transaction,
        rows,
        allowMessageIdOnly: true,
      );
      if (exact != null) return _storeMatch(transaction, exact);
    }

    if (!_hasText(transaction.sourceFingerprint)) return null;
    final banks = await _bankConfigService.getBanks(allowRemoteFetch: false);
    final bankCodes = banks
        .where((bank) => bank.id == transaction.bankId)
        .expand((bank) => bank.codes)
        .map((code) => code.trim())
        .where((code) => code.isNotEmpty)
        .toSet();
    if (bankCodes.isEmpty) return null;

    final candidates = <String, SmsMessage>{};
    for (final code in bankCodes) {
      final rows = await _query(
        SmsFilter.where(SmsColumn.ADDRESS).like('%$code%'),
      );
      for (final message in rows) {
        final key = message.id?.toString() ??
            '${message.date}|${message.address}|${message.body}';
        candidates[key] = message;
      }
    }
    final match = _findMatch(transaction, candidates.values);
    return match == null ? null : _storeMatch(transaction, match);
  }

  /// Captures source messages for older transactions in a bank-batched inbox
  /// scan. Failures and missing SMS permission leave the existing export
  /// untouched instead of preventing a backup.
  Future<int> captureAvailableSources(
    Iterable<Transaction> transactions,
  ) async {
    final candidatesByReference = <String, Transaction>{};
    for (final transaction in transactions) {
      final reference = transaction.reference.trim();
      if (reference.isEmpty ||
          transaction.bankId == null ||
          !hasSmsSource(transaction)) {
        continue;
      }
      candidatesByReference[reference] = transaction;
    }
    if (candidatesByReference.isEmpty ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return 0;
    }

    try {
      final existing = await _sourceSmsRepository
          .getForTransactionReferences(candidatesByReference.keys);
      for (final sourceSms in existing) {
        candidatesByReference.remove(sourceSms.transactionReference);
      }
      if (candidatesByReference.isEmpty) return 0;

      final permission = await Permission.sms.status;
      if (!permission.isGranted) return 0;

      final banks = await _bankConfigService.getBanks(allowRemoteFetch: false);
      final banksById = {for (final bank in banks) bank.id: bank};
      final transactionsByBank = <int, List<Transaction>>{};
      for (final transaction in candidatesByReference.values) {
        transactionsByBank
            .putIfAbsent(transaction.bankId!, () => <Transaction>[])
            .add(transaction);
      }

      final captured = <TransactionSourceSms>[];
      for (final entry in transactionsByBank.entries) {
        final bank = banksById[entry.key];
        if (bank == null) continue;

        final messages = <String, SmsMessage>{};
        for (final code in bank.codes) {
          final normalizedCode = code.trim();
          if (normalizedCode.isEmpty) continue;
          for (final message in await _query(
            SmsFilter.where(SmsColumn.ADDRESS).like('%$normalizedCode%'),
          )) {
            final key = message.id?.toString() ??
                '${message.date}|${message.address}|${message.body}';
            messages[key] = message;
          }
        }

        final byMessageId = <String, SmsMessage>{};
        final byFingerprint = <String, SmsMessage>{};
        for (final message in messages.values) {
          final body = message.body;
          if (body == null || body.trim().isEmpty) continue;
          final messageId = message.id?.toString();
          if (messageId != null) byMessageId[messageId] = message;
          final fingerprint = _fingerprintForMessage(entry.key, message);
          if (_hasText(fingerprint)) {
            byFingerprint.putIfAbsent(fingerprint!, () => message);
          }
        }

        for (final transaction in entry.value) {
          SmsMessage? match;
          final expectedFingerprint = transaction.sourceFingerprint?.trim();
          final messageId = transaction.sourceMessageId?.trim();
          if (_hasText(messageId)) {
            final byId = byMessageId[messageId!];
            if (byId != null &&
                (!_hasText(expectedFingerprint) ||
                    _fingerprintForMessage(entry.key, byId) ==
                        expectedFingerprint)) {
              match = byId;
            }
          }
          if (match == null && _hasText(expectedFingerprint)) {
            match = byFingerprint[expectedFingerprint!];
          }
          if (match != null) {
            captured.add(_toSourceSms(transaction, match));
          }
        }
      }

      await _sourceSmsRepository.upsertAll(captured);
      return captured.length;
    } catch (_) {
      return 0;
    }
  }

  Future<List<SmsMessage>> _query(SmsFilter filter) async {
    try {
      return await _telephony.getInboxSms(
        columns: const <SmsColumn>[
          SmsColumn.ID,
          SmsColumn.ADDRESS,
          SmsColumn.BODY,
          SmsColumn.DATE,
        ],
        filter: filter,
        sortOrder: <OrderBy>[
          OrderBy(SmsColumn.DATE, sort: Sort.DESC),
        ],
      );
    } catch (_) {
      return const <SmsMessage>[];
    }
  }

  SmsMessage? _findMatch(
    Transaction transaction,
    Iterable<SmsMessage> messages, {
    bool allowMessageIdOnly = false,
  }) {
    final expectedFingerprint = transaction.sourceFingerprint?.trim();
    for (final message in messages) {
      final body = message.body?.trim();
      if (body == null || body.isEmpty) continue;
      final fingerprint = SmsTransactionSource.fromParts(
        bankId: transaction.bankId!,
        messageId: message.id,
        senderAddress: message.address,
        body: message.body,
        dateMillis: message.date,
      ).sourceFingerprint;
      if (_hasText(expectedFingerprint)) {
        if (fingerprint == expectedFingerprint) return message;
        continue;
      }
      if (allowMessageIdOnly &&
          message.id?.toString() == transaction.sourceMessageId?.trim()) {
        return message;
      }
    }
    return null;
  }

  Future<TransactionSourceSms> _storeMatch(
    Transaction transaction,
    SmsMessage message,
  ) async {
    final sourceSms = _toSourceSms(transaction, message);
    try {
      await _sourceSmsRepository.upsert(sourceSms);
    } catch (_) {
      // The inbox source can still be shown even if durable capture fails.
    }
    return sourceSms;
  }

  TransactionSourceSms _toSourceSms(
    Transaction transaction,
    SmsMessage message,
  ) {
    return TransactionSourceSms(
      transactionReference: transaction.reference.trim(),
      body: message.body!,
      senderAddress: message.address?.trim(),
      receivedAt: message.date == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(message.date!).toLocal(),
      messageId: message.id?.toString(),
    );
  }

  String? _fingerprintForMessage(int bankId, SmsMessage message) {
    return SmsTransactionSource.fromParts(
      bankId: bankId,
      messageId: message.id,
      senderAddress: message.address,
      body: message.body,
      dateMillis: message.date,
    ).sourceFingerprint;
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}
