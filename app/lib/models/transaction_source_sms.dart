class TransactionSourceSms {
  final String transactionReference;
  final String body;
  final String? senderAddress;
  final DateTime? receivedAt;
  final String? messageId;

  const TransactionSourceSms({
    required this.transactionReference,
    required this.body,
    this.senderAddress,
    this.receivedAt,
    this.messageId,
  });

  factory TransactionSourceSms.fromJson(Map<String, dynamic> json) {
    final receivedAt = json['receivedAt']?.toString().trim();
    return TransactionSourceSms(
      transactionReference:
          json['transactionReference']?.toString().trim() ?? '',
      body: json['body']?.toString() ?? '',
      senderAddress: _normalizedText(json['senderAddress']),
      receivedAt: receivedAt == null || receivedAt.isEmpty
          ? null
          : DateTime.tryParse(receivedAt),
      messageId: _normalizedText(json['messageId']),
    );
  }

  Map<String, dynamic> toJson() => {
        'transactionReference': transactionReference,
        'body': body,
        if (senderAddress != null) 'senderAddress': senderAddress,
        if (receivedAt != null) 'receivedAt': receivedAt!.toIso8601String(),
        if (messageId != null) 'messageId': messageId,
      };

  Map<String, dynamic> toDb() => toJson();

  static String? _normalizedText(dynamic value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
