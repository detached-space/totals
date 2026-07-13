import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/sms_transaction_source.dart';

const Duration legacySmsDirectionRepairWindow = Duration(minutes: 2);

Transaction? findLegacySmsDirectionMismatch({
  required Bank bank,
  required Transaction parsed,
  required DateTime? messageDate,
  required Iterable<Transaction> candidates,
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
  if (parsedType == null || parsedAccount == null || parsedBalance == null) {
    return null;
  }

  final matches = candidates.where((candidate) {
    if (candidate.bankId != bank.id ||
        !_isSourceless(candidate) ||
        !_hasLegacyTimestampReference(candidate, bank.id)) {
      return false;
    }
    final candidateType = _ledgerType(candidate.type);
    if (candidateType == null || candidateType == parsedType) return false;
    if ((candidate.amount.abs() - parsed.amount.abs()).abs() > 0.0001) {
      return false;
    }
    if (_accountEvidence(candidate.accountNumber) != parsedAccount) {
      return false;
    }
    final candidateBalance = _parseBalance(candidate.currentBalance);
    if (candidateBalance == null ||
        (candidateBalance - parsedBalance).abs() > 0.0001) {
      return false;
    }
    final candidateTime = DateTime.tryParse(candidate.time ?? '');
    if (candidateTime == null ||
        candidateTime.difference(messageDate).abs() >
            legacySmsDirectionRepairWindow) {
      return false;
    }
    return true;
  }).toList(growable: false);

  return matches.length == 1 ? matches.single : null;
}

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
  return double.tryParse(normalized);
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
