import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/sms_transaction_source.dart';

const Duration legacySmsDirectionRepairWindow = Duration(minutes: 2);

/// Indexes strict legacy direction-repair candidates once per account.
///
/// Older imports can contain thousands of sourceless timestamp-reference
/// rows. Looking through that entire collection for every parsed SMS makes a
/// reparse quadratic. This index narrows each lookup by the evidence that must
/// already agree, then applies the original exact checks to the small result.
class LegacySmsDirectionRepairIndex {
  final Bank bank;
  final Map<String, List<Transaction>> _candidatesByEvidence;

  LegacySmsDirectionRepairIndex({
    required this.bank,
    required Iterable<Transaction> candidates,
  }) : _candidatesByEvidence = _buildIndex(bank, candidates);

  Transaction? findMismatch({
    required Transaction parsed,
    required DateTime? messageDate,
  }) {
    if (messageDate == null ||
        parsed.bankId != bank.id ||
        parsed.sourceType != SmsTransactionSource.smsType ||
        !_hasSourceIdentity(parsed)) {
      return null;
    }

    final parsedType = _ledgerType(parsed.type);
    final parsedAccount = _accountEvidence(parsed.accountNumber);
    final parsedBalance = _parseBalance(parsed.currentBalance);
    if (parsedType == null ||
        parsedAccount == null ||
        parsedBalance == null ||
        !parsed.amount.isFinite) {
      return null;
    }

    final oppositeType = parsedType == 'CREDIT' ? 'DEBIT' : 'CREDIT';
    final parsedAmountUnits = _evidenceUnits(parsed.amount.abs());
    final parsedBalanceUnits = _evidenceUnits(parsedBalance);
    final candidates = <Transaction>[];
    for (var amountOffset = -1; amountOffset <= 1; amountOffset++) {
      for (var balanceOffset = -1; balanceOffset <= 1; balanceOffset++) {
        final key = _evidenceKey(
          account: parsedAccount,
          type: oppositeType,
          amountUnits: parsedAmountUnits + amountOffset,
          balanceUnits: parsedBalanceUnits + balanceOffset,
        );
        candidates.addAll(
          _candidatesByEvidence[key] ?? const <Transaction>[],
        );
      }
    }

    final matches = candidates.where((candidate) {
      if ((candidate.amount.abs() - parsed.amount.abs()).abs() > 0.0001) {
        return false;
      }
      final candidateBalance = _parseBalance(candidate.currentBalance);
      if (candidateBalance == null ||
          (candidateBalance - parsedBalance).abs() > 0.0001) {
        return false;
      }
      final candidateTime = DateTime.tryParse(candidate.time ?? '');
      return candidateTime != null &&
          candidateTime.difference(messageDate).abs() <=
              legacySmsDirectionRepairWindow;
    }).toList(growable: false);

    return matches.length == 1 ? matches.single : null;
  }

  /// Keeps the in-memory index consistent after a repaired legacy row is
  /// deleted from the transaction repository during the same reparse.
  void remove(Transaction transaction) {
    final type = _ledgerType(transaction.type);
    final account = _accountEvidence(transaction.accountNumber);
    final balance = _parseBalance(transaction.currentBalance);
    if (type == null ||
        account == null ||
        balance == null ||
        !transaction.amount.isFinite) {
      return;
    }
    final key = _evidenceKey(
      account: account,
      type: type,
      amountUnits: _evidenceUnits(transaction.amount.abs()),
      balanceUnits: _evidenceUnits(balance),
    );
    final candidates = _candidatesByEvidence[key];
    candidates?.removeWhere(
      (candidate) => candidate.reference == transaction.reference,
    );
    if (candidates?.isEmpty == true) {
      _candidatesByEvidence.remove(key);
    }
  }

  static Map<String, List<Transaction>> _buildIndex(
    Bank bank,
    Iterable<Transaction> candidates,
  ) {
    final result = <String, List<Transaction>>{};
    for (final candidate in candidates) {
      if (candidate.bankId != bank.id ||
          !_isSourceless(candidate) ||
          !_hasLegacyTimestampReference(candidate, bank.id)) {
        continue;
      }
      final type = _ledgerType(candidate.type);
      final account = _accountEvidence(candidate.accountNumber);
      final balance = _parseBalance(candidate.currentBalance);
      if (type == null ||
          account == null ||
          balance == null ||
          !candidate.amount.isFinite) {
        continue;
      }
      final key = _evidenceKey(
        account: account,
        type: type,
        amountUnits: _evidenceUnits(candidate.amount.abs()),
        balanceUnits: _evidenceUnits(balance),
      );
      result.putIfAbsent(key, () => <Transaction>[]).add(candidate);
    }
    return result;
  }
}

Transaction? findLegacySmsDirectionMismatch({
  required Bank bank,
  required Transaction parsed,
  required DateTime? messageDate,
  required Iterable<Transaction> candidates,
}) {
  return LegacySmsDirectionRepairIndex(
    bank: bank,
    candidates: candidates,
  ).findMismatch(parsed: parsed, messageDate: messageDate);
}

int _evidenceUnits(double value) => (value * 10000).round();

String _evidenceKey({
  required String account,
  required String type,
  required int amountUnits,
  required int balanceUnits,
}) =>
    '$account|$type|$amountUnits|$balanceUnits';

bool _hasSourceIdentity(Transaction transaction) {
  return _hasText(transaction.sourceMessageId) ||
      _hasText(transaction.sourceFingerprint);
}

bool _isSourceless(Transaction transaction) {
  return !_hasText(transaction.sourceType) &&
      !_hasText(transaction.sourceMessageId) &&
      !_hasText(transaction.sourceFingerprint);
}

bool _hasLegacyTimestampReference(Transaction transaction, int bankId) {
  final reference = transaction.reference.trim();
  final prefix = '${bankId}_';
  if (!reference.startsWith(prefix)) return false;
  final timestamp = reference.substring(prefix.length);
  final parsedReferenceTime = DateTime.tryParse(timestamp);
  final transactionTime = DateTime.tryParse(transaction.time ?? '');
  return parsedReferenceTime != null &&
      transactionTime != null &&
      parsedReferenceTime.difference(transactionTime).abs() <=
          const Duration(seconds: 2);
}

String? _ledgerType(String? value) {
  final normalized = value?.trim().toUpperCase();
  return normalized == 'CREDIT' || normalized == 'DEBIT' ? normalized : null;
}

String? _accountEvidence(String? value) {
  final normalized =
      value?.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9*X]'), '').trim();
  if (normalized == null || normalized.isEmpty) return null;
  final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 3 ? normalized : null;
}

double? _parseBalance(String? value) {
  final normalized = value?.trim().replaceAll(',', '');
  if (normalized == null || normalized.isEmpty) return null;
  final parsed = double.tryParse(normalized);
  return parsed?.isFinite == true ? parsed : null;
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
