import 'package:totals/models/transaction.dart';

class SuspectedDuplicate {
  final Transaction first;
  final Transaction second;
  final Duration timeDelta;

  const SuspectedDuplicate({
    required this.first,
    required this.second,
    required this.timeDelta,
  });
}

class DuplicateTransactionService {
  static const Duration timeWindow = Duration(seconds: 60);
  static const double amountTolerance = 0.01;

  /// Scans [transactions] and returns pairs that look like duplicates:
  /// same amount (within [amountTolerance]), same accountNumber, same type,
  /// and timestamps within [timeWindow] of each other.
  List<SuspectedDuplicate> findDuplicates(List<Transaction> transactions) {
    final withTime = transactions
        .where((t) => t.time != null)
        .toList()
      ..sort((a, b) {
          final ta = DateTime.tryParse(a.time!);
          final tb = DateTime.tryParse(b.time!);
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return ta.compareTo(tb);
        });

    final usedReferences = <String>{};
    final duplicates = <SuspectedDuplicate>[];

    for (var i = 0; i < withTime.length; i++) {
      final a = withTime[i];
      if (usedReferences.contains(a.reference)) continue;

      final timeA = DateTime.tryParse(a.time!);
      if (timeA == null) continue;

      for (var j = i + 1; j < withTime.length; j++) {
        final b = withTime[j];
        if (usedReferences.contains(b.reference)) continue;

        final timeB = DateTime.tryParse(b.time!);
        if (timeB == null) continue;

        final delta = timeB.difference(timeA);
        if (delta > timeWindow) { break; } // list is sorted, no point going further

        if (_isSuspectedDuplicate(a, b)) {
          usedReferences.add(a.reference);
          usedReferences.add(b.reference);
          duplicates.add(SuspectedDuplicate(
            first: a,
            second: b,
            timeDelta: delta,
          ));
          break;
        }
      }
    }

    return duplicates;
  }

  /// Returns true if [incoming] looks like a duplicate of any transaction
  /// in [existing] — used for real-time SMS detection.
  SuspectedDuplicate? checkIncoming(
    Transaction incoming,
    List<Transaction> existing,
  ) {
    final incomingTime = incoming.time != null
        ? DateTime.tryParse(incoming.time!)
        : null;
    if (incomingTime == null) return null;

    for (final t in existing) {
      if (t.reference == incoming.reference) continue;
      if (t.time == null) continue;
      final tTime = DateTime.tryParse(t.time!);
      if (tTime == null) continue;
      final delta = incomingTime.difference(tTime).abs();
      if (delta > timeWindow) continue;
      if (_isSuspectedDuplicate(incoming, t)) {
        return SuspectedDuplicate(
          first: t,
          second: incoming,
          timeDelta: delta,
        );
      }
    }
    return null;
  }

  static bool _isSuspectedDuplicate(Transaction a, Transaction b) {
    if (a.type != b.type) { return false; }
    if ((a.amount - b.amount).abs() > amountTolerance) { return false; }
    if (a.accountNumber != null &&
        b.accountNumber != null &&
        a.accountNumber != b.accountNumber) { return false; }
    if (a.bankId != null && b.bankId != null && a.bankId != b.bankId) {
      return false;
    }
    return true;
  }
}
