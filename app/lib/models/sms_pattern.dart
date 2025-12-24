class SmsPattern {
  final int bankId;
  final String senderId; // e.g., "CBE", "telebirr"
  final String regex;
  final String type; // CREDIT or DEBIT
  final String
      description; // For debugging, e.g., "CBE Debit with Service Charge"
  final bool? refRequired;
  final bool? hasAccount;

  SmsPattern({
    required this.bankId,
    required this.senderId,
    required this.regex,
    required this.type,
    this.description = "",
    this.refRequired,
    this.hasAccount,
  });

  factory SmsPattern.fromJson(Map<String, dynamic> json) {
    return SmsPattern(
      bankId: json['bankId'],
      senderId: json['senderId'],
      regex: json['regex'],
      type: json['type'],
      description: json['description'] ?? "",
      refRequired: json['refRequired'],
      hasAccount: json['hasAccount'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bankId': bankId,
      'senderId': senderId,
      'regex': regex,
      'type': type,
      'description': description,
      'refRequired': refRequired,
      'hasAccount': hasAccount,
    };
  }
}
