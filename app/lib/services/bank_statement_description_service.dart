import 'package:totals/models/sms_pattern.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/transaction_source_sms_repository.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/services/transaction_sms_source_service.dart';

enum BankStatementDescriptionProgressStage {
  capturingSources,
  loadingReferences,
  loadingPatterns,
  matchingPatterns,
  complete,
}

class BankStatementDescriptionProgress {
  final double value;
  final BankStatementDescriptionProgressStage stage;
  final int? processed;
  final int? total;

  const BankStatementDescriptionProgress({
    required this.value,
    required this.stage,
    this.processed,
    this.total,
  });
}

typedef BankStatementDescriptionProgressCallback = void Function(
  BankStatementDescriptionProgress progress,
);

/// Resolves human-readable statement descriptions from the SMS pattern that
/// originally parsed each transaction.
class BankStatementDescriptionService {
  final SmsConfigService _smsConfigService;
  final TransactionSourceSmsRepository _sourceSmsRepository;
  final TransactionSmsSourceService _transactionSmsSourceService;

  BankStatementDescriptionService({
    SmsConfigService? smsConfigService,
    TransactionSourceSmsRepository? sourceSmsRepository,
    TransactionSmsSourceService? transactionSmsSourceService,
  })  : _smsConfigService = smsConfigService ?? SmsConfigService(),
        _sourceSmsRepository =
            sourceSmsRepository ?? TransactionSourceSmsRepository(),
        _transactionSmsSourceService =
            transactionSmsSourceService ?? TransactionSmsSourceService();

  Future<Map<String, String>> resolveDescriptions(
    Iterable<Transaction> transactions, {
    BankStatementDescriptionProgressCallback? onProgress,
  }) async {
    var lastProgress = 0.0;

    void report(
      BankStatementDescriptionProgressStage stage,
      double value, {
      int? processed,
      int? total,
    }) {
      final monotonicValue = value.clamp(lastProgress, 1.0).toDouble();
      lastProgress = monotonicValue;
      onProgress?.call(
        BankStatementDescriptionProgress(
          value: monotonicValue,
          stage: stage,
          processed: processed,
          total: total,
        ),
      );
    }

    final candidates = transactions
        .where((transaction) => transaction.reference.trim().isNotEmpty)
        .toList(growable: false);
    if (candidates.isEmpty) {
      report(BankStatementDescriptionProgressStage.complete, 1);
      return const <String, String>{};
    }

    // Older transactions may not have their source SMS captured yet. This is
    // a no-op when SMS access is unavailable and must never block a statement.
    report(BankStatementDescriptionProgressStage.capturingSources, 0);
    try {
      await _transactionSmsSourceService.captureAvailableSources(candidates);
    } catch (_) {
      // Pattern names are optional metadata; type labels remain available.
    }

    report(BankStatementDescriptionProgressStage.loadingReferences, 0.25);
    var sourceMessages = const <TransactionSourceSms>[];
    try {
      sourceMessages = await _sourceSmsRepository.getForTransactionReferences(
        candidates.map((transaction) => transaction.reference),
      );
    } catch (_) {
      report(BankStatementDescriptionProgressStage.complete, 1);
      return const <String, String>{};
    }
    if (sourceMessages.isEmpty) {
      report(BankStatementDescriptionProgressStage.complete, 1);
      return const <String, String>{};
    }

    report(BankStatementDescriptionProgressStage.loadingPatterns, 0.45);
    var patterns = const <SmsPattern>[];
    try {
      patterns = await _smsConfigService.getPatterns(allowRemoteFetch: false);
    } catch (_) {
      report(BankStatementDescriptionProgressStage.complete, 1);
      return const <String, String>{};
    }
    final compiledPatterns = _compileStatementPatterns(patterns);

    final sourceByReference = {
      for (final source in sourceMessages)
        source.transactionReference: source.body,
    };
    final descriptions = <String, String>{};
    final total = candidates.length;
    final progressInterval = total <= 80 ? 1 : (total / 80).ceil();
    report(
      BankStatementDescriptionProgressStage.matchingPatterns,
      0.55,
      processed: 0,
      total: total,
    );
    for (var index = 0; index < total; index++) {
      final transaction = candidates[index];
      final patternName = _findCompiledPatternName(
        bankId: transaction.bankId,
        messageBody: sourceByReference[transaction.reference],
        patterns: compiledPatterns,
      );
      if (patternName != null) {
        descriptions[transaction.reference] = patternName;
      }
      final processed = index + 1;
      if (processed == total || processed % progressInterval == 0) {
        report(
          BankStatementDescriptionProgressStage.matchingPatterns,
          0.55 + ((processed / total) * 0.44),
          processed: processed,
          total: total,
        );
      }
    }
    report(BankStatementDescriptionProgressStage.complete, 1);
    return Map<String, String>.unmodifiable(descriptions);
  }
}

String? findBankStatementPatternName({
  required int? bankId,
  required String? messageBody,
  required Iterable<SmsPattern> patterns,
}) {
  return _findCompiledPatternName(
    bankId: bankId,
    messageBody: messageBody,
    patterns: _compileStatementPatterns(patterns),
  );
}

List<_CompiledStatementPattern> _compileStatementPatterns(
  Iterable<SmsPattern> patterns,
) {
  final compiled = <_CompiledStatementPattern>[];
  for (final pattern in patterns) {
    try {
      final name = cleanBankStatementPatternName(pattern.description);
      compiled.add(
        _CompiledStatementPattern(
          bankId: pattern.bankId,
          regex: RegExp(
            pattern.regex,
            caseSensitive: false,
            multiLine: true,
            dotAll: true,
          ),
          name: name.isEmpty ? null : name,
        ),
      );
    } on FormatException {
      // Ignore malformed remote patterns and continue checking the rest.
    }
  }
  return compiled;
}

String? _findCompiledPatternName({
  required int? bankId,
  required String? messageBody,
  required Iterable<_CompiledStatementPattern> patterns,
}) {
  final body = messageBody?.trim();
  if (bankId == null || body == null || body.isEmpty) return null;

  for (final pattern in patterns) {
    if (pattern.bankId == bankId && pattern.regex.firstMatch(body) != null) {
      return pattern.name;
    }
  }
  return null;
}

String cleanBankStatementPatternName(String value) {
  return value
      .trim()
      .replaceFirst(
        RegExp(
          r'^fallback\b[\s:–—-]*',
          caseSensitive: false,
        ),
        '',
      )
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

class _CompiledStatementPattern {
  final int bankId;
  final RegExp regex;
  final String? name;

  const _CompiledStatementPattern({
    required this.bankId,
    required this.regex,
    required this.name,
  });
}
