import 'package:meta/meta.dart';
import 'package:totals/models/transaction.dart';

/// Transforms a parsed [Transaction] after extraction.
///
/// Enrichers run in registration order. Each receives the raw SMS body
/// alongside the transaction so it can re-scan the original text if needed.
/// New enrichers are added by calling [EnrichmentPipeline.add] — no changes
/// to the extractor or orchestrator are required.
abstract class TransactionEnricher {
  Future<Transaction> enrich(Transaction transaction, String rawMessage);
}

/// Chains multiple [TransactionEnricher]s into a single pass.
///
/// Usage:
///   final pipeline = EnrichmentPipeline()
///     ..add(MerchantNormalizer())
///     ..add(CategorizerEnricher());
///   final enriched = await pipeline.enrich(tx, rawSms);
class EnrichmentPipeline {
  final List<TransactionEnricher> _enrichers = [];

  void add(TransactionEnricher enricher) {
    _enrichers.add(enricher);
  }

  void remove(TransactionEnricher enricher) {
    _enrichers.remove(enricher);
  }

  @visibleForTesting
  void clear() {
    _enrichers.clear();
  }

  @visibleForTesting
  int get enricherCount => _enrichers.length;

  Future<Transaction> enrich(Transaction transaction, String rawMessage) async {
    var tx = transaction;
    for (final enricher in _enrichers) {
      tx = await enricher.enrich(tx, rawMessage);
    }
    return tx;
  }
}
