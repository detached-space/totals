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

  /// Whether this account contributes to aggregate balance cards.
  final bool includeInTotals;

  /// User-managed lifecycle marker. Dormant accounts remain accessible and do
  /// not lose transaction history.
  final bool isDormant;

  /// Preferred destination for bank messages that are genuinely ambiguous.
  final bool isDefault;

  Account({
    required this.accountNumber,
    required this.bank,
    required this.balance,
    required this.accountHolderName,
    this.settledBalance,
    this.pendingCredit,
    this.profileId,
    this.smsSubscriptionId,
    this.includeInTotals = true,
    this.isDormant = false,
    this.isDefault = false,
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
      includeInTotals: _toBool(json['includeInTotals'], fallback: true),
      isDormant: _toBool(json['isDormant']),
      isDefault: _toBool(json['isDefault']),
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
      'includeInTotals': includeInTotals,
      'isDormant': isDormant,
      'isDefault': isDefault,
      if (profileId != null) 'profileId': profileId,
    };
  }

  static int? _toNullableInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static bool _toBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return fallback;
  }

  static String encode(List<Account> accounts) => json.encode(
        accounts.map<Map<String, dynamic>>((a) => a.toJson()).toList(),
      );

  static List<Account> decode(String accounts) =>
      (json.decode(accounts) as List<dynamic>)
          .map<Account>((item) => Account.fromJson(item))
          .toList();
}
