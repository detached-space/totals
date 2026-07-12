import 'dart:convert';

class Account {
  final String accountNumber;
  final int bank; // Mapped to 'bank' in JSON
  final double balance;
  final String accountHolderName;
  final double? settledBalance;
  final double? pendingCredit;
  final int? profileId;

  /// Android SMS subscription used to route messages for SIM-backed accounts.
  /// This is device-local metadata; the user-entered number remains the
  /// durable account identity.
  final int? smsSubscriptionId;

  Account({
    required this.accountNumber,
    required this.bank,
    required this.balance,
    required this.accountHolderName,
    this.settledBalance,
    this.pendingCredit,
    this.profileId,
    this.smsSubscriptionId,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      accountNumber: json['accountNumber'],
      bank: json['bank'],
      balance: double.tryParse(json['balance'].toString()) ?? 0.0,
      accountHolderName: json['accountHolderName'],
      settledBalance: json['settledBalance']?.toDouble(),
      pendingCredit: json['pendingCredit']?.toDouble(),
      profileId: json['profileId'] as int?,
      smsSubscriptionId: _toNullableInt(json['smsSubscriptionId']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accountNumber': accountNumber,
      'bank': bank,
      'balance': balance,
      'accountHolderName': accountHolderName,
      'settledBalance': settledBalance,
      'pendingCredit': pendingCredit,
      if (profileId != null) 'profileId': profileId,
    };
  }

  static int? _toNullableInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static String encode(List<Account> accounts) => json.encode(
        accounts.map<Map<String, dynamic>>((a) => a.toJson()).toList(),
      );

  static List<Account> decode(String accounts) =>
      (json.decode(accounts) as List<dynamic>)
          .map<Account>((item) => Account.fromJson(item))
          .toList();
}
