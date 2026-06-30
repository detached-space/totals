import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/models/transaction.dart';

class AccountReparseDebugResult {
  final String id;
  final int bankId;
  final String bankLabel;
  final String accountNumber;
  final String completionMessage;
  final DateTime completedAt;
  final List<Transaction> importedTransactions;
  final List<Transaction> removedDuplicateTransactions;

  const AccountReparseDebugResult({
    required this.id,
    required this.bankId,
    required this.bankLabel,
    required this.accountNumber,
    required this.completionMessage,
    required this.completedAt,
    this.importedTransactions = const <Transaction>[],
    this.removedDuplicateTransactions = const <Transaction>[],
  });

  int get importedCount => importedTransactions.length;

  int get removedDuplicateCount => removedDuplicateTransactions.length;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bankId': bankId,
      'bankLabel': bankLabel,
      'accountNumber': accountNumber,
      'completionMessage': completionMessage,
      'completedAt': completedAt.toIso8601String(),
      'importedTransactions': importedTransactions
          .map((transaction) => transaction.toJson())
          .toList(),
      'removedDuplicateTransactions': removedDuplicateTransactions
          .map((transaction) => transaction.toJson())
          .toList(),
    };
  }

  factory AccountReparseDebugResult.fromJson(Map<String, dynamic> json) {
    return AccountReparseDebugResult(
      id: (json['id'] as String?)?.trim() ?? '',
      bankId: (json['bankId'] as num?)?.toInt() ?? -1,
      bankLabel: (json['bankLabel'] as String?)?.trim() ?? 'Account',
      accountNumber: (json['accountNumber'] as String?)?.trim() ?? '',
      completionMessage:
          (json['completionMessage'] as String?)?.trim() ?? 'Reparse complete.',
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? '') ??
          DateTime.now(),
      importedTransactions: _transactionsFromJson(json['importedTransactions']),
      removedDuplicateTransactions:
          _transactionsFromJson(json['removedDuplicateTransactions']),
    );
  }

  static List<Transaction> _transactionsFromJson(dynamic raw) {
    if (raw is! List) return const <Transaction>[];
    return raw
        .whereType<Map>()
        .map(
          (item) => Transaction.fromJson(
            item.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .toList(growable: false);
  }
}

class AccountReparseResultService {
  AccountReparseResultService._();

  static final AccountReparseResultService instance =
      AccountReparseResultService._();

  static const String _prefsKey = 'account_reparse_debug_results_v1';
  static const int _maxStoredResults = 20;

  final StreamController<AccountReparseDebugResult> _controller =
      StreamController<AccountReparseDebugResult>.broadcast();

  Stream<AccountReparseDebugResult> get stream => _controller.stream;

  Future<AccountReparseDebugResult> recordCompletedReparse({
    required int bankId,
    required String bankLabel,
    required String accountNumber,
    required String completionMessage,
    required List<Transaction> importedTransactions,
    required List<Transaction> removedDuplicateTransactions,
  }) async {
    final completedAt = DateTime.now();
    final result = AccountReparseDebugResult(
      id: _buildResultId(
        bankId: bankId,
        accountNumber: accountNumber,
        completedAt: completedAt,
      ),
      bankId: bankId,
      bankLabel: bankLabel,
      accountNumber: accountNumber,
      completionMessage: completionMessage,
      completedAt: completedAt,
      importedTransactions:
          List<Transaction>.unmodifiable(importedTransactions),
      removedDuplicateTransactions:
          List<Transaction>.unmodifiable(removedDuplicateTransactions),
    );

    await _saveResult(result);
    if (!_controller.isClosed) {
      _controller.add(result);
    }
    return result;
  }

  Future<AccountReparseDebugResult?> getResult(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return null;

    final results = await _loadResults();
    for (final result in results) {
      if (result.id == normalizedId) return result;
    }
    return null;
  }

  Future<void> _saveResult(AccountReparseDebugResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final results = await _loadResultsFromPrefs(prefs);
    final nextResults = <AccountReparseDebugResult>[
      result,
      ...results.where((stored) => stored.id != result.id),
    ];
    final limitedResults = nextResults.take(_maxStoredResults).toList();
    await prefs.setString(
      _prefsKey,
      jsonEncode(
        limitedResults.map((stored) => stored.toJson()).toList(),
      ),
    );
  }

  Future<List<AccountReparseDebugResult>> _loadResults() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadResultsFromPrefs(prefs);
  }

  Future<List<AccountReparseDebugResult>> _loadResultsFromPrefs(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <AccountReparseDebugResult>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <AccountReparseDebugResult>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => AccountReparseDebugResult.fromJson(
              item.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .where((result) => result.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <AccountReparseDebugResult>[];
    }
  }

  String _buildResultId({
    required int bankId,
    required String accountNumber,
    required DateTime completedAt,
  }) {
    final normalizedAccount = accountNumber.trim();
    final timestamp = completedAt.microsecondsSinceEpoch;
    return '$bankId-$normalizedAccount-$timestamp';
  }
}
