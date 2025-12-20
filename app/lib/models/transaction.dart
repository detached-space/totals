class Transaction {
  final double amount; // required
  final String reference; // required
  final String? creditor;
  final String? receiver;
  final String? time; // ISO string
  final String? status; // PENDING, CLEARED, SYNCED
  final String? currentBalance;
  final int? bankId;
  final String? type; // CREDIT or DEBIT
  final String? transactionLink;
  final String? accountNumber; // Last 4 digits
  final int? categoryId;

  Transaction({
    required this.amount,
    required this.reference,
    this.creditor,
    this.receiver,
    this.time,
    this.status,
    this.currentBalance,
    this.bankId,
    this.type,
    this.transactionLink,
    this.accountNumber,
    this.categoryId,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    return Transaction(
      amount: toDouble(json['amount']),
      reference: json['reference'] ?? '',
      creditor: json['creditor'],
      receiver: json['receiver'],
      time: json['time'],
      status: json['status'],
      currentBalance: json['currentBalance']?.toString(),
      bankId: json['bankId'],
      type: json['type'],
      transactionLink: json['transactionLink'],
      accountNumber: json['accountNumber'],
      categoryId: json['categoryId'],
    );
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'reference': reference,
        'creditor': creditor,
        'receiver': receiver,
        'time': time,
        'status': status,
        'currentBalance': currentBalance,
        'bankId': bankId,
        'type': type,
        'transactionLink': transactionLink,
        'accountNumber': accountNumber,
        'categoryId': categoryId,
      };

  Transaction copyWith({
    double? amount,
    String? reference,
    String? creditor,
    String? receiver,
    String? time,
    String? status,
    String? currentBalance,
    int? bankId,
    String? type,
    String? transactionLink,
    String? accountNumber,
    int? categoryId,
  }) {
    return Transaction(
      amount: amount ?? this.amount,
      reference: reference ?? this.reference,
      creditor: creditor ?? this.creditor,
      receiver: receiver ?? this.receiver,
      time: time ?? this.time,
      status: status ?? this.status,
      currentBalance: currentBalance ?? this.currentBalance,
      bankId: bankId ?? this.bankId,
      type: type ?? this.type,
      transactionLink: transactionLink ?? this.transactionLink,
      accountNumber: accountNumber ?? this.accountNumber,
      categoryId: categoryId ?? this.categoryId,
    );
  }
}
