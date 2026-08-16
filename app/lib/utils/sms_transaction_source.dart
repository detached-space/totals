import 'dart:convert';

import 'package:totals/sms_handler/telephony.dart';

class SmsTransactionSource {
  static const String smsType = 'sms';
  static const int _telebirrBankId = 6;
  static const String _telebirrLegMarker = '__totals_tb_leg_';

  final String sourceType;
  final String? sourceMessageId;
  final String? sourceFingerprint;

  const SmsTransactionSource({
    this.sourceType = smsType,
    this.sourceMessageId,
    this.sourceFingerprint,
  });

  factory SmsTransactionSource.fromMessage({
    required SmsMessage message,
    required int bankId,
  }) {
    return SmsTransactionSource.fromParts(
      bankId: bankId,
      messageId: message.id,
      senderAddress: message.address,
      body: message.body,
      dateMillis: message.date,
    );
  }

  factory SmsTransactionSource.fromParts({
    required int bankId,
    int? messageId,
    String? senderAddress,
    String? body,
    int? dateMillis,
  }) {
    // Android's broadcast timestamp and inbox provider timestamp can differ
    // for the same SMS, so dateMillis is kept for API compatibility but is not
    // part of the dedupe fingerprint.
    return SmsTransactionSource(
      sourceMessageId: messageId?.toString(),
      sourceFingerprint: _buildFingerprint(
        bankId: bankId,
        senderAddress: senderAddress,
        body: body,
      ),
    );
  }

  bool get hasIdentity =>
      _hasText(sourceMessageId) || _hasText(sourceFingerprint);

  /// Gives each side of a Telebirr transfer a stable row identity.
  ///
  /// Wallet-to-wallet transfers can produce a debit and a credit receipt with
  /// the same bank transaction number. The database still requires a unique
  /// `reference`, so debit/credit direction is kept in a private suffix while
  /// the original bank reference remains available through [displayReference].
  String? scopeReference({
    required int bankId,
    required String? reference,
    required String? transactionType,
  }) {
    final bankReference = displayReference(
      bankId: bankId,
      storedReference: reference,
    );
    if (!_hasText(bankReference)) return null;
    if (bankId != _telebirrBankId || !hasIdentity) return bankReference;

    final direction = transactionType?.trim().toLowerCase();
    if (direction != 'debit' && direction != 'credit') return bankReference;
    return '$bankReference$_telebirrLegMarker$direction';
  }

  /// Removes Totals' private SMS identity suffix for display/copy/receipt use.
  static String displayReference({
    required int? bankId,
    required String? storedReference,
  }) {
    final value = storedReference?.trim() ?? '';
    if (bankId != _telebirrBankId) return value;
    return value.replaceFirst(
      RegExp(
        '${RegExp.escape(_telebirrLegMarker)}(?:debit|credit)\$',
        caseSensitive: false,
      ),
      '',
    );
  }

  /// Normalized bank reference for identity comparisons.
  ///
  /// Older parsers sometimes captured the sentence-ending period after a
  /// transaction number. That punctuation is presentation, not part of the
  /// bank's reference, and must not prevent a legacy row from matching its
  /// current SMS-backed counterpart.
  static String canonicalReference({
    required int? bankId,
    required String? storedReference,
  }) {
    return displayReference(
      bankId: bankId,
      storedReference: storedReference,
    )
        .trim()
        .replaceAll(RegExp(r'[\s.,;:]+$'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
  }

  /// Canonical key used when comparing a legacy unsuffixed row with a scoped
  /// debit/credit row for the same wallet ledger leg.
  static String logicalLegKey({
    required int? bankId,
    required String? reference,
    required String? transactionType,
  }) {
    final external = canonicalReference(
      bankId: bankId,
      storedReference: reference,
    );
    final direction = transactionType?.trim().toUpperCase() ?? '';
    return '${bankId ?? ''}|$external|$direction';
  }

  Map<String, dynamic> toJson() {
    return {
      if (hasIdentity) 'sourceType': sourceType,
      if (_hasText(sourceMessageId)) 'sourceMessageId': sourceMessageId,
      if (_hasText(sourceFingerprint)) 'sourceFingerprint': sourceFingerprint,
    };
  }

  static String? _buildFingerprint({
    required int bankId,
    required String? senderAddress,
    required String? body,
  }) {
    final sender = senderAddress?.trim().toLowerCase();
    final normalizedBody = body?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!_hasText(sender) || !_hasText(normalizedBody)) {
      return null;
    }

    return _fnv1a64('sms|v2|$bankId|$sender|$normalizedBody');
  }

  static String _fnv1a64(String value) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xffffffffffffffff;

    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * prime) & mask;
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }

  static bool _hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}
