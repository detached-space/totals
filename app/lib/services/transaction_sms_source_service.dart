import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/sms_transaction_source.dart';

class TransactionSourceSms {
  final String body;
  final String? senderAddress;
  final DateTime? receivedAt;
  final String? messageId;

  const TransactionSourceSms({
    required this.body,
    this.senderAddress,
    this.receivedAt,
    this.messageId,
  });
}

/// Resolves a transaction's durable SMS source identity back to the Android
/// inbox. Raw SMS text stays in the system inbox instead of being copied into
/// Totals backups or sync payloads.
class TransactionSmsSourceService {
  final Telephony _telephony;
  final BankConfigService _bankConfigService;

  TransactionSmsSourceService({
    Telephony? telephony,
    BankConfigService? bankConfigService,
  })  : _telephony = telephony ?? Telephony.instance,
        _bankConfigService = bankConfigService ?? BankConfigService();

  static bool hasSmsSource(Transaction transaction) {
    final sourceType = transaction.sourceType?.trim().toLowerCase();
    return sourceType == SmsTransactionSource.smsType ||
        _hasText(transaction.sourceMessageId) ||
        _hasText(transaction.sourceFingerprint);
  }

  Future<TransactionSourceSms?> resolve(Transaction transaction) async {
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
      if (exact != null) return _toSourceSms(exact);
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
    return match == null ? null : _toSourceSms(match);
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

  TransactionSourceSms _toSourceSms(SmsMessage message) {
    return TransactionSourceSms(
      body: message.body!.trim(),
      senderAddress: message.address?.trim(),
      receivedAt: message.date == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(message.date!).toLocal(),
      messageId: message.id?.toString(),
    );
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}
