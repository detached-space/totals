class SmsPattern {
  final int bankId;
  final String senderId; // e.g., "CBE", "telebirr"
  final String regex;
  final String type; // CREDIT or DEBIT
  final String
      description; // For debugging, e.g., "CBE Debit with Service Charge"
  final bool? refRequired;
  final bool? hasAccount;
  final bool? hasFees;
  final Map<String, String>? fieldMapping;

  SmsPattern({
    required this.bankId,
    required this.senderId,
    required this.regex,
    required this.type,
    this.description = "",
    this.refRequired,
    this.hasAccount,
    this.hasFees,
    this.fieldMapping,
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
      hasFees: json['hasFees'],
      fieldMapping: json['fieldMapping'] != null
          ? Map<String, String>.from(json['fieldMapping'])
          : null,
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
      'hasFees': hasFees,
      'fieldMapping': fieldMapping,
    };
  }
}
