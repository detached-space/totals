import 'package:flutter/foundation.dart';
import 'package:totals/models/transaction.dart';

/// Field-level enrichment of a stored transaction from a re-parsed copy of its
/// source message — the ingest-side counterpart of the Android reparse
/// service's `_mergeParsedFields`: the stored row's identity and the user's
/// organization (note, categories, profile) always win; the parsed copy only
/// fills fields the stored row is missing (receiver, balance, receipt link,
/// service charge, SMS source ids…).
class TransactionMergeUtils {
  /// Returns the enriched transaction, or null when the parsed copy adds
  /// nothing — so callers can skip the write entirely.
  static Transaction? mergeParsedFields(
      Transaction existing, Transaction reparsed) {
    final updated = Transaction(
      amount: existing.amount,
      reference: existing.reference,
      creditor: _pickText(existing.creditor, reparsed.creditor),
      receiver: _pickText(existing.receiver, reparsed.receiver),
      note: existing.note,
      time: _pickText(existing.time, reparsed.time),
      status: _pickText(existing.status, reparsed.status),
      currentBalance:
          _pickText(existing.currentBalance, reparsed.currentBalance),
      bankId: existing.bankId ?? reparsed.bankId,
      type: _pickText(existing.type, reparsed.type),
      transactionLink: _pickText(
          existing.transactionLink, reparsed.transactionLink),
      accountNumber: _pickText(existing.accountNumber, reparsed.accountNumber),
      categoryId: existing.categoryId,
      categoryIds: existing.categoryIds,
      profileId: existing.profileId,
      serviceCharge:
          _pickAmount(existing.serviceCharge, reparsed.serviceCharge),
      vat: _pickAmount(existing.vat, reparsed.vat),
      sourceType: _pickText(existing.sourceType, reparsed.sourceType),
      sourceMessageId:
          _pickText(existing.sourceMessageId, reparsed.sourceMessageId),
      sourceFingerprint:
          _pickText(existing.sourceFingerprint, reparsed.sourceFingerprint),
    );

    if (_isSameTransaction(existing, updated)) {
      return null;
    }
    return updated;
  }

  static String? _pickText(String? existing, String? reparsed) {
    final trimmedExisting = existing?.trim();
    if (trimmedExisting != null && trimmedExisting.isNotEmpty) return existing;
    final trimmedReparsed = reparsed?.trim();
    if (trimmedReparsed == null || trimmedReparsed.isEmpty) return null;
    return trimmedReparsed;
  }

  static double? _pickAmount(double? existing, double? reparsed) {
    if (existing != null && existing != 0) return existing;
    if (reparsed != null && reparsed != 0) return reparsed;
    return existing;
  }

  static bool _isSameTransaction(Transaction a, Transaction b) {
    return a.amount == b.amount &&
        a.reference == b.reference &&
        a.creditor == b.creditor &&
        a.receiver == b.receiver &&
        a.note == b.note &&
        a.time == b.time &&
        a.status == b.status &&
        a.currentBalance == b.currentBalance &&
        a.bankId == b.bankId &&
        a.type == b.type &&
        a.transactionLink == b.transactionLink &&
        a.accountNumber == b.accountNumber &&
        a.categoryId == b.categoryId &&
        listEquals(a.selectedCategoryIds, b.selectedCategoryIds) &&
        a.profileId == b.profileId &&
        a.serviceCharge == b.serviceCharge &&
        a.vat == b.vat &&
        a.sourceType == b.sourceType &&
        a.sourceMessageId == b.sourceMessageId &&
        a.sourceFingerprint == b.sourceFingerprint;
  }
}
