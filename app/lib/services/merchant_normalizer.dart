import 'package:totals/models/transaction.dart';
import 'package:totals/services/enrichment_pipeline.dart';

/// Normalises creditor/receiver names extracted from SMS messages.
///
/// Strips common bank/processor prefixes (e.g. "SML*", "POS "), maps
/// known merchant substrings to canonical names, and capitalises the
/// result. Runs as an [TransactionEnricher] in the enrichment pipeline.
class MerchantNormalizer extends TransactionEnricher {
  // Prefix/pattern rules applied in order. Each strips or replaces a
  // known pattern before the merchant lookup runs.
  static final List<_NormalizationRule> _rules = [
    _NormalizationRule(RegExp(r'^SML\*', caseSensitive: false), ''),
    _NormalizationRule(RegExp(r'^POS\s+', caseSensitive: false), ''),
    _NormalizationRule(RegExp(r'^ONLINE\s+', caseSensitive: false), ''),
    _NormalizationRule(RegExp(r'^WEB\s+', caseSensitive: false), ''),
    _NormalizationRule(RegExp(r'^MOBILE\s+', caseSensitive: false), ''),
    _NormalizationRule(RegExp(r'\s*\(.*?\)\s*\$'), ''),
    _NormalizationRule(RegExp(r'\s{2,}'), ' '),
  ];

  // Known merchants: the key is a lower-case substring to match against
  // the cleaned counterparty; the value is the canonical display name.
  static final Map<String, String> _knownMerchants = {
    'ethiotelecom': 'Ethio Telecom',
    'safaricom': 'Safaricom',
    'mpesa': 'M-PESA',
  };

  @override
  Future<Transaction> enrich(Transaction transaction, String rawMessage) async {
    var updated = transaction;

    if (updated.creditor != null && updated.creditor!.trim().isNotEmpty) {
      final normalized = _normalize(updated.creditor!);
      if (normalized != updated.creditor) {
        updated = updated.copyWith(creditor: normalized);
      }
    }

    if (updated.receiver != null && updated.receiver!.trim().isNotEmpty) {
      final normalized = _normalize(updated.receiver!);
      if (normalized != updated.receiver) {
        updated = updated.copyWith(receiver: normalized);
      }
    }

    return updated;
  }

  String _normalize(String raw) {
    var value = raw.trim();

    // Apply prefix/pattern rules
    for (final rule in _rules) {
      value = value.replaceAll(rule.pattern, rule.replacement);
    }
    value = value.trim();

    // Check against known merchants
    for (final entry in _knownMerchants.entries) {
      if (value.toLowerCase().contains(entry.key)) {
        return entry.value;
      }
    }

    // Fallback: capitalise first letter
    if (value.isNotEmpty) {
      value = '${value[0].toUpperCase()}${value.substring(1)}';
    }

    return value;
  }
}

class _NormalizationRule {
  final RegExp pattern;
  final String replacement;

  const _NormalizationRule(this.pattern, this.replacement);
}
