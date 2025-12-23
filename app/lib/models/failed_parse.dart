class FailedParse {
  final int? id;
  final String address;
  final String body;
  final String reason;
  final String timestamp; // ISO string

  FailedParse({
    this.id,
    required this.address,
    required this.body,
    required this.reason,
    required this.timestamp,
  });

  factory FailedParse.fromJson(Map<String, dynamic> json) => FailedParse(
        id: json['id'],
        address: json['address'] ?? '',
        body: json['body'] ?? '',
        reason: json['reason'] ?? '',
        timestamp: json['timestamp'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'address': address,
        'body': body,
        'reason': reason,
        'timestamp': timestamp,
      };
}
