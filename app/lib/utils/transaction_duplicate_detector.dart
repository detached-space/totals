import 'package:totals/models/transaction.dart';

const int dashenCanonicalMaskPattern = 3;
const int dashenLegacyMaskPattern = 4;
const Duration dashenDeduplicationWindow = Duration(hours: 10);

class TransactionDeduplicationPlan {
  final Transaction keeper;
  final Transaction mergedKeeper;
  final List<Transaction> duplicates;

  const TransactionDeduplicationPlan({
    required this.keeper,
    required this.mergedKeeper,
    required this.duplicates,
  });

  List<String> get duplicateReferences =>
      duplicates.map((transaction) => transaction.reference).toList();
}

bool hasExactAmountAndBalanceDuplicate({
  required int bankId,
  required String type,
  required double amount,
  required String? currentBalance,
  required String? accountNumber,
  required Iterable<Transaction> existingTransactions,
}) {
  final normalizedType = type.trim().toUpperCase();
  final normalizedAccount = _normalizeAccount(accountNumber);
  final normalizedBalance = _parseBalance(currentBalance);
  if (normalizedBalance == null) return false;

  for (final transaction in existingTransactions) {
    if (transaction.bankId != bankId) continue;
    if ((transaction.type ?? '').trim().toUpperCase() != normalizedType) {
      continue;
    }
    if ((transaction.amount - amount).abs() > 0.0001) continue;

    final existingBalance = _parseBalance(transaction.currentBalance);
    if (existingBalance == null ||
        (existingBalance - normalizedBalance).abs() > 0.0001) {
      continue;
    }

    if (normalizedAccount == null) {
      return true;
    }

    if (_normalizeAccount(transaction.accountNumber) == normalizedAccount) {
      return true;
    }
  }

  return false;
}

Set<String> buildDashenDeduplicationSuffixes({
  required Iterable<String> accountNumbers,
  Iterable<String?> transactionAccountNumbers = const [],
}) {
  final normalizedAccounts = accountNumbers
      .map(_normalizeAccount)
      .whereType<String>()
      .toList(growable: false);
  final suffixes = <String>{};

  if (normalizedAccounts.isNotEmpty) {
    final canonicalCounts = <String, int>{};
    for (final account in normalizedAccounts) {
      final canonicalSuffix =
          _accountSuffix(account, dashenCanonicalMaskPattern);
      if (canonicalSuffix == null) continue;
      canonicalCounts.update(
        canonicalSuffix,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final allowCanonicalFallback = normalizedAccounts.length == 1;
    for (final account in normalizedAccounts) {
      final legacySuffix = _accountSuffix(account, dashenLegacyMaskPattern);
      if (legacySuffix != null) {
        suffixes.add(legacySuffix);
      }

      final canonicalSuffix =
          _accountSuffix(account, dashenCanonicalMaskPattern);
      if (canonicalSuffix == null) continue;
      if (allowCanonicalFallback || canonicalCounts[canonicalSuffix] == 1) {
        suffixes.add(canonicalSuffix);
      }
    }
  }

  if (suffixes.isNotEmpty) {
    return suffixes;
  }

  for (final accountNumber in transactionAccountNumbers) {
    final canonicalSuffix =
        _accountSuffix(accountNumber, dashenCanonicalMaskPattern);
    if (canonicalSuffix != null) {
      suffixes.add(canonicalSuffix);
    }

    final legacySuffix = _accountSuffix(accountNumber, dashenLegacyMaskPattern);
    if (legacySuffix != null) {
      suffixes.add(legacySuffix);
    }
  }

  return suffixes;
}

List<TransactionDeduplicationPlan>
    buildExactAmountAndBalanceDeduplicationPlans({
  required int bankId,
  required String type,
  required Iterable<Transaction> transactions,
  String? accountSuffix,
  bool matchTransactionsWithoutAccountNumber = false,
}) {
  final normalizedType = type.trim().toUpperCase();
  final normalizedSuffix = _normalizeAccount(accountSuffix);
  final groupedTransactions = <String, List<Transaction>>{};

  for (final transaction in transactions) {
    if (transaction.bankId != bankId) continue;
    if ((transaction.type ?? '').trim().toUpperCase() != normalizedType) {
      continue;
    }

    final normalizedBalance = _parseBalance(transaction.currentBalance);
    if (normalizedBalance == null) {
      continue;
    }

    final normalizedAccount = _normalizeAccount(transaction.accountNumber);
    if (normalizedSuffix != null) {
      if (normalizedAccount == null) {
        if (!matchTransactionsWithoutAccountNumber) {
          continue;
        }
      } else if (!normalizedAccount.endsWith(normalizedSuffix)) {
        continue;
      }
    }

    final accountKey = normalizedSuffix ?? normalizedAccount ?? '';
    final groupKey = [
      accountKey,
      transaction.amount.toStringAsFixed(4),
      normalizedBalance.toStringAsFixed(4),
    ].join('|');
    groupedTransactions.putIfAbsent(groupKey, () => []).add(transaction);
  }

  final plans = <TransactionDeduplicationPlan>[];
  for (final group in groupedTransactions.values) {
    final duplicateClusters = _clusterDuplicateCandidates(group);
    for (final cluster in duplicateClusters) {
      if (cluster.length < 2) continue;
      final keeper = _selectKeeper(cluster);
      final mergedKeeper = _mergeTransactions(keeper, cluster);
      final duplicates = cluster
          .where((transaction) => transaction.reference != keeper.reference)
          .toList(growable: false);
      if (duplicates.isEmpty) continue;
      plans.add(TransactionDeduplicationPlan(
        keeper: keeper,
        mergedKeeper: mergedKeeper,
        duplicates: duplicates,
      ));
    }
  }

  return plans;
}

List<List<Transaction>> _clusterDuplicateCandidates(
  List<Transaction> transactions,
) {
  if (transactions.length < 2) return const [];

  final sorted = [...transactions]
    ..sort((a, b) => _sortTime(a).compareTo(_sortTime(b)));

  final clusters = <List<Transaction>>[];
  var currentCluster = <Transaction>[];
  DateTime? clusterStartTime;

  for (final transaction in sorted) {
    final transactionTime = _parseTime(transaction.time);
    if (currentCluster.isEmpty) {
      currentCluster = [transaction];
      clusterStartTime = transactionTime;
      continue;
    }

    final isSameCluster = clusterStartTime == null ||
        transactionTime == null ||
        transactionTime.difference(clusterStartTime).abs() <=
            dashenDeduplicationWindow;

    if (isSameCluster) {
      currentCluster.add(transaction);
      clusterStartTime ??= transactionTime;
    } else {
      clusters.add(currentCluster);
      currentCluster = [transaction];
      clusterStartTime = transactionTime;
    }
  }

  if (currentCluster.isNotEmpty) {
    clusters.add(currentCluster);
  }

  return clusters;
}

Transaction _selectKeeper(List<Transaction> transactions) {
  var keeper = transactions.first;
  for (final candidate in transactions.skip(1)) {
    if (_compareTransactionRichness(candidate, keeper) > 0) {
      keeper = candidate;
    }
  }
  return keeper;
}

int _compareTransactionRichness(Transaction left, Transaction right) {
  final scoreDiff = _detailScore(left) - _detailScore(right);
  if (scoreDiff != 0) return scoreDiff;

  final populatedFieldsDiff =
      _populatedFieldCount(left) - _populatedFieldCount(right);
  if (populatedFieldsDiff != 0) return populatedFieldsDiff;

  final textLengthDiff = _textDataLength(left) - _textDataLength(right);
  if (textLengthDiff != 0) return textLengthDiff;

  final leftTime = _parseTime(left.time);
  final rightTime = _parseTime(right.time);
  if (leftTime != null && rightTime != null) {
    return leftTime.compareTo(rightTime);
  }
  if (leftTime != null) return 1;
  if (rightTime != null) return -1;

  return right.reference.compareTo(left.reference);
}

int _detailScore(Transaction transaction) {
  var score = 0;
  if (_hasText(transaction.receiver)) score += 5;
  if (_hasText(transaction.creditor)) score += 5;
  if (_hasValue(transaction.vat)) score += 4;
  if (_hasValue(transaction.serviceCharge)) score += 4;
  if (_hasText(transaction.transactionLink)) score += 2;
  if (_hasText(transaction.accountNumber)) score += 2;
  if (_hasText(transaction.currentBalance)) score += 2;
  if (_hasText(transaction.status)) score += 1;
  if (_hasText(transaction.time)) score += 1;
  if (transaction.categoryId != null) score += 2;
  return score;
}

int _populatedFieldCount(Transaction transaction) {
  var count = 0;
  if (_hasText(transaction.receiver)) count++;
  if (_hasText(transaction.creditor)) count++;
  if (_hasText(transaction.transactionLink)) count++;
  if (_hasText(transaction.accountNumber)) count++;
  if (_hasText(transaction.currentBalance)) count++;
  if (_hasText(transaction.status)) count++;
  if (_hasText(transaction.time)) count++;
  if (_hasValue(transaction.vat)) count++;
  if (_hasValue(transaction.serviceCharge)) count++;
  if (transaction.categoryId != null) count++;
  return count;
}

int _textDataLength(Transaction transaction) {
  return [
    transaction.receiver,
    transaction.creditor,
    transaction.transactionLink,
    transaction.accountNumber,
    transaction.currentBalance,
    transaction.status,
    transaction.time,
  ].fold<int>(0, (sum, value) => sum + (value?.trim().length ?? 0));
}

Transaction _mergeTransactions(
  Transaction keeper,
  List<Transaction> transactions,
) {
  var merged = keeper;
  for (final transaction in transactions) {
    if (transaction.reference == keeper.reference) continue;
    final mergedCategoryIds = <int>[
      ...merged.selectedCategoryIds,
      ...transaction.selectedCategoryIds.where(
        (id) => !merged.selectedCategoryIds.contains(id),
      ),
    ];
    merged = merged.copyWith(
      creditor: _pickBetterText(merged.creditor, transaction.creditor),
      receiver: _pickBetterText(merged.receiver, transaction.receiver),
      time: _pickBetterText(merged.time, transaction.time),
      status: _pickBetterText(merged.status, transaction.status),
      currentBalance:
          _pickBetterText(merged.currentBalance, transaction.currentBalance),
      transactionLink:
          _pickBetterText(merged.transactionLink, transaction.transactionLink),
      accountNumber:
          _pickBetterText(merged.accountNumber, transaction.accountNumber),
      categoryId: merged.categoryId ?? transaction.categoryId,
      categoryIds: mergedCategoryIds,
      profileId: merged.profileId ?? transaction.profileId,
      serviceCharge:
          _pickBetterNumber(merged.serviceCharge, transaction.serviceCharge),
      vat: _pickBetterNumber(merged.vat, transaction.vat),
      sourceType: _pickBetterText(merged.sourceType, transaction.sourceType),
      sourceMessageId:
          _pickBetterText(merged.sourceMessageId, transaction.sourceMessageId),
      sourceFingerprint: _pickBetterText(
          merged.sourceFingerprint, transaction.sourceFingerprint),
    );
  }
  return merged;
}

double? _parseBalance(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.trim().replaceAll(',', '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

DateTime? _parseTime(String? raw) {
  if (!_hasText(raw)) return null;
  return DateTime.tryParse(raw!.trim());
}

DateTime _sortTime(Transaction transaction) {
  return _parseTime(transaction.time) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

String? _normalizeAccount(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;
  return cleaned;
}

String? _accountSuffix(String? raw, int maskPattern) {
  final normalized = _normalizeAccount(raw);
  if (normalized == null) return null;
  if (maskPattern > 0 && normalized.length > maskPattern) {
    return normalized.substring(normalized.length - maskPattern);
  }
  return normalized;
}

String? _pickBetterText(String? current, String? candidate) {
  if (!_hasText(current)) return candidate;
  if (!_hasText(candidate)) return current;
  if (candidate!.trim().length > current!.trim().length) {
    return candidate;
  }
  return current;
}

double? _pickBetterNumber(double? current, double? candidate) {
  if (!_hasValue(current)) return candidate;
  if (!_hasValue(candidate)) return current;
  if ((candidate!.abs() - current!.abs()) > 0.0001) {
    return candidate;
  }
  return current;
}

bool _hasText(String? value) {
  return value != null && value.trim().isNotEmpty;
}

bool _hasValue(double? value) {
  return value != null && value.abs() > 0.0001;
}
