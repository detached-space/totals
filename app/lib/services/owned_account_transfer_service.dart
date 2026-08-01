import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/account_identity.dart';

class OwnedAccountTransferMatch {
  final Transaction debitTransaction;
  final Transaction creditTransaction;
  final Account debitAccount;
  final Account creditAccount;
  final Duration timeDelta;

  const OwnedAccountTransferMatch({
    required this.debitTransaction,
    required this.creditTransaction,
    required this.debitAccount,
    required this.creditAccount,
    required this.timeDelta,
  });
}

class OwnedAccountTransferService {
  static const Duration identityMatchWindow = Duration(minutes: 10);
  static const Duration timestampOnlyMatchWindow = Duration(seconds: 15);
  static const double amountTolerance = 0.01;

  List<OwnedAccountTransferMatch> findMatches({
    required Iterable<Transaction> transactions,
    required Iterable<Bank> banks,
    required Iterable<Account> accounts,
  }) {
    final bankList = banks.toList(growable: false);
    final accountList = accounts.toList(growable: false);
    final banksById = {for (final bank in bankList) bank.id: bank};
    final bankTokens = {
      for (final bank in bankList) bank.id: _tokensForBank(bank),
    };

    final ownedTransactions = <_OwnedTransaction>[];
    for (final transaction in transactions) {
      final bankId = transaction.bankId;
      final time = _parseTime(transaction.time);
      if (bankId == null || time == null) continue;
      if (transaction.type != 'CREDIT' && transaction.type != 'DEBIT') {
        continue;
      }
      final bank = banksById[bankId];
      if (bank == null) continue;
      final owner = resolveTransactionOwnership(
        transaction: transaction,
        bank: bank,
        accounts: accountList,
      );
      if (owner == null) continue;
      ownedTransactions.add(
        _OwnedTransaction(
          transaction: transaction,
          owner: owner,
          bank: bank,
          time: time,
        ),
      );
    }

    final creditsByCents = <int, List<_OwnedTransaction>>{};
    for (final owned in ownedTransactions) {
      if (owned.transaction.type != 'CREDIT') continue;
      creditsByCents
          .putIfAbsent(_amountCents(owned.transaction.amount), () => [])
          .add(owned);
    }

    final candidates = <_TransferCandidate>[];
    for (final debit in ownedTransactions) {
      if (debit.transaction.type != 'DEBIT') continue;
      final cents = _amountCents(debit.transaction.amount);
      for (final candidateCents in <int>[cents - 1, cents, cents + 1]) {
        for (final credit
            in creditsByCents[candidateCents] ?? const <_OwnedTransaction>[]) {
          if (!_profilesCanMatch(debit, credit) ||
              _isSameAccount(debit, credit) ||
              !_amountsMatch(
                debit.transaction.amount,
                credit.transaction.amount,
              )) {
            continue;
          }
          final delta = debit.time.difference(credit.time).abs();
          if (delta > identityMatchWindow) continue;

          final hasBankEvidence = _mentionsBank(
                debit.transaction,
                bankTokens[credit.bank.id] ?? const <String>{},
              ) ||
              _mentionsBank(
                credit.transaction,
                bankTokens[debit.bank.id] ?? const <String>{},
              );
          final hasHolderEvidence = _mentionsHolder(
                debit.transaction,
                credit.owner.accountHolderName,
              ) ||
              _mentionsHolder(
                credit.transaction,
                debit.owner.accountHolderName,
              );
          final hasTightUnlabeledPair = delta <= timestampOnlyMatchWindow &&
              _normalizedTransactionText(debit.transaction).isEmpty &&
              _normalizedTransactionText(credit.transaction).isEmpty;
          if (!hasBankEvidence &&
              !hasHolderEvidence &&
              !hasTightUnlabeledPair) {
            continue;
          }

          candidates.add(
            _TransferCandidate(
              debit: debit,
              credit: credit,
              timeDelta: delta,
              evidenceScore: (hasBankEvidence ? 100 : 0) +
                  (hasHolderEvidence ? 50 : 0) +
                  (hasTightUnlabeledPair ? 20 : 0),
            ),
          );
        }
      }
    }

    candidates.sort((left, right) {
      final evidenceComparison =
          right.evidenceScore.compareTo(left.evidenceScore);
      if (evidenceComparison != 0) return evidenceComparison;
      final timeComparison = left.timeDelta.compareTo(right.timeDelta);
      if (timeComparison != 0) return timeComparison;
      final debitComparison = left.debit.transaction.reference
          .compareTo(right.debit.transaction.reference);
      if (debitComparison != 0) return debitComparison;
      return left.credit.transaction.reference
          .compareTo(right.credit.transaction.reference);
    });

    final usedReferences = <String>{};
    final matches = <OwnedAccountTransferMatch>[];
    for (final candidate in candidates) {
      final debitReference = candidate.debit.transaction.reference;
      final creditReference = candidate.credit.transaction.reference;
      if (usedReferences.contains(debitReference) ||
          usedReferences.contains(creditReference)) {
        continue;
      }
      usedReferences
        ..add(debitReference)
        ..add(creditReference);
      matches.add(
        OwnedAccountTransferMatch(
          debitTransaction: candidate.debit.transaction,
          creditTransaction: candidate.credit.transaction,
          debitAccount: candidate.debit.owner,
          creditAccount: candidate.credit.owner,
          timeDelta: candidate.timeDelta,
        ),
      );
    }
    return matches;
  }

  bool _profilesCanMatch(_OwnedTransaction left, _OwnedTransaction right) {
    final leftProfile = left.transaction.profileId ?? left.owner.profileId;
    final rightProfile = right.transaction.profileId ?? right.owner.profileId;
    return leftProfile == null ||
        rightProfile == null ||
        leftProfile == rightProfile;
  }

  bool _isSameAccount(_OwnedTransaction left, _OwnedTransaction right) {
    if (left.bank.id != right.bank.id) return false;
    return registeredAccountNumbersMatch(
      left.bank,
      left.owner.accountNumber,
      right.owner.accountNumber,
    );
  }

  bool _mentionsBank(
    Transaction transaction,
    Set<String> tokens,
  ) {
    final rawText = _transactionText(transaction).toLowerCase();
    if (rawText.isEmpty) return false;
    final normalizedText = _normalizeToken(rawText);
    return tokens.any((token) {
      if (token.isEmpty) return false;
      if (token.length > 3) return normalizedText.contains(token);

      // Short bank codes such as CBE and BOA must be complete words. Without
      // this guard, a counterparty such as "CBEBirr" incorrectly counts as
      // evidence that the matching transaction belongs to CBE.
      return RegExp(
        '(^|[^a-z0-9])${RegExp.escape(token)}([^a-z0-9]|\$)',
      ).hasMatch(rawText);
    });
  }

  bool _mentionsHolder(Transaction transaction, String holderName) {
    final holder = _normalizeToken(holderName);
    if (holder.length < 4) return false;
    return _normalizedTransactionText(transaction).contains(holder);
  }

  Set<String> _tokensForBank(Bank bank) {
    final tokens = <String>{
      _normalizeToken(bank.name),
      _normalizeToken(bank.shortName),
      for (final code in bank.codes) _normalizeToken(code),
    };
    tokens.removeWhere((token) => token.length < 3);
    return tokens;
  }

  String _normalizedTransactionText(Transaction transaction) {
    return _normalizeToken(_transactionText(transaction));
  }

  String _transactionText(Transaction transaction) {
    return <String?>[
      transaction.creditor,
      transaction.receiver,
      transaction.note,
    ].whereType<String>().join(' ').trim();
  }

  String _normalizeToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  int _amountCents(double amount) => (amount.abs() * 100).round();

  bool _amountsMatch(double left, double right) {
    return (left.abs() - right.abs()).abs() <= amountTolerance;
  }

  DateTime? _parseTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }
}

class _OwnedTransaction {
  final Transaction transaction;
  final Account owner;
  final Bank bank;
  final DateTime time;

  const _OwnedTransaction({
    required this.transaction,
    required this.owner,
    required this.bank,
    required this.time,
  });
}

class _TransferCandidate {
  final _OwnedTransaction debit;
  final _OwnedTransaction credit;
  final Duration timeDelta;
  final int evidenceScore;

  const _TransferCandidate({
    required this.debit,
    required this.credit,
    required this.timeDelta,
    required this.evidenceScore,
  });
}
