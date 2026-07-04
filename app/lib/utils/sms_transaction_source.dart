import 'dart:convert';

import 'package:totals/sms_handler/telephony.dart';

class SmsTransactionSource {
  static const String smsType = 'sms';

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
