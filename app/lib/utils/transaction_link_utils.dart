import 'package:totals/models/sms_pattern.dart';
import 'package:totals/models/transaction.dart';

class TransactionLinkUtils {
  static final RegExp _urlPattern =
      RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);

  static String? extractTransactionLinkFromMessage({
    required String messageBody,
    required SmsPattern pattern,
    String? reference,
  }) {
    final normalizedReference = _normalizedReference(reference)?.toLowerCase();
    final urls = _urlPattern
        .allMatches(messageBody)
        .map((match) => _normalizeHttpUrl(match.group(0)))
        .whereType<String>()
        .toList(growable: false);

    if (urls.isNotEmpty) {
      if (normalizedReference != null) {
        for (final url in urls) {
          if (url.toLowerCase().contains(normalizedReference)) {
            return url;
          }
        }
      }

      if (urls.length == 1 || _looksLikeReceiptMessage(messageBody, pattern)) {
        return urls.last;
      }
    }

    return inferTransactionLink(
      bankId: pattern.bankId,
      reference: reference,
    );
  }

  static String? resolveReferenceLink(Transaction transaction) {
    final persistedLink = _normalizeHttpUrl(transaction.transactionLink);
    if (persistedLink != null) return persistedLink;

    return inferTransactionLink(
      bankId: transaction.bankId,
      reference: transaction.displayReference,
    );
  }

  /// Extracts a bank reference embedded in a known receipt URL.
  static String? extractReferenceFromLink(String? rawLink) {
    final normalized = _normalizeHttpUrl(rawLink);
    if (normalized == null) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null) return null;

    for (final key in const ['id', 'reference', 'trx']) {
      final value = uri.queryParameters[key]?.trim();
      if (value != null && RegExp(r'^[A-Za-z0-9@.\-]+$').hasMatch(value)) {
        return value;
      }
    }

    final segments = uri.pathSegments;
    for (var index = 0; index + 1 < segments.length; index++) {
      if (segments[index].toLowerCase() != 'receipt') continue;
      final value = segments[index + 1].trim();
      if (RegExp(r'^[A-Za-z0-9@.\-]+$').hasMatch(value)) return value;
    }
    return null;
  }

  static String? inferTransactionLink({
    required int? bankId,
    String? reference,
  }) {
    final normalizedReference = _normalizedReference(reference);
    if (normalizedReference == null) return null;

    switch (bankId) {
      case 1:
        return 'https://apps.cbe.come.et:100/?id='
            '${Uri.encodeQueryComponent(normalizedReference)}';
      case 5:
        return 'https://share.zemenbank.com/rt/'
            '${Uri.encodeComponent(normalizedReference)}/pdf';
      default:
        return null;
    }
  }

  static bool _looksLikeReceiptMessage(String messageBody, SmsPattern pattern) {
    final normalized =
        '${pattern.description} ${pattern.regex} $messageBody'.toLowerCase();
    return normalized.contains('receipt') ||
        normalized.contains('branchreceipt') ||
        normalized.contains('?trx=') ||
        normalized.contains('?id=') ||
        normalized.contains('share.zemenbank.com/rt/');
  }

  static String? _normalizedReference(String? reference) {
    final trimmed = reference?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static String? _normalizeHttpUrl(String? rawUrl) {
    final trimmed = rawUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final cleaned = trimmed.replaceFirst(RegExp(r'[\].,;:)\s]+$'), '');
    final uri = Uri.tryParse(cleaned);
    if (uri == null || !uri.hasScheme) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;

    return uri.toString();
  }
}
