import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:totals/models/bank.dart';

class FallbackSmsParser {
  static const String _assetPath = 'assets/fallback_sms_patterns.json';

  static const Map<int, List<String>> _fallbackProviderIdsByTotalsBankId = {
    1: ['cbe_0'],
    2: ['awash_0'],
    3: ['boa_0'],
    4: ['dashen_0'],
    5: ['zemen_0'],
    6: ['telebirr_0'],
    8: ['mpesa_0'],
    9: ['amhara_0'],
    10: ['ahadu_0'],
    12: ['berhan_0'],
    13: ['bunna_0'],
    14: ['coop_0'],
    19: ['hibret_0'],
    24: ['Oromia_0'],
    30: ['tsedey_0'],
    33: ['wegagen_0'],
    36: ['apollo_0'],
    37: ['cbe_birr_0'],
  };

  static List<_FallbackBankConfig>? _cachedConfigs;

  static Future<Set<int>> supportedBankIds({
    bool requirePatterns = false,
  }) async {
    final configs = await _loadConfigs();
    final configsById = {for (final config in configs) config.bankId: config};
    final supported = <int>{};

    for (final entry in _fallbackProviderIdsByTotalsBankId.entries) {
      final hasSupportedConfig = entry.value.any((fallbackProviderId) {
        final config = configsById[fallbackProviderId];
        if (config == null) return false;
        return !requirePatterns || config.patterns.isNotEmpty;
      });
      if (hasSupportedConfig) supported.add(entry.key);
    }

    return supported;
  }

  static Future<bool> supportsBankId(
    int bankId, {
    bool requirePatterns = false,
  }) async {
    final supported = await supportedBankIds(requirePatterns: requirePatterns);
    return supported.contains(bankId);
  }

  static Future<Map<String, dynamic>?> extractTransactionDetails({
    required String messageBody,
    required String senderAddress,
    required DateTime? messageDate,
    required Bank bank,
  }) async {
    final configs = await _configsForTotalsBank(bank.id);
    if (configs.isEmpty) return null;

    _FallbackMatch? bestMatch;
    for (final config in configs) {
      for (final pattern in config.patterns) {
        final match = _matchPattern(
          config: config,
          pattern: pattern,
          bank: bank,
          messageBody: messageBody,
          messageDate: messageDate,
        );
        if (match == null) continue;

        if (bestMatch == null || match.score >= bestMatch.score) {
          bestMatch = match;
        }
      }
    }

    return bestMatch?.details;
  }

  static Future<List<_FallbackBankConfig>> _configsForTotalsBank(
    int totalsBankId,
  ) async {
    final fallbackProviderIds =
        _fallbackProviderIdsByTotalsBankId[totalsBankId];
    if (fallbackProviderIds == null || fallbackProviderIds.isEmpty) {
      return const [];
    }

    final configs = await _loadConfigs();
    return configs
        .where((config) => fallbackProviderIds.contains(config.bankId))
        .toList(growable: false);
  }

  static Future<List<_FallbackBankConfig>> _loadConfigs() async {
    if (_cachedConfigs != null) return _cachedConfigs!;

    try {
      final body = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        _cachedConfigs = const [];
        return _cachedConfigs!;
      }

      _cachedConfigs = decoded
          .whereType<Map<String, dynamic>>()
          .map(_FallbackBankConfig.fromJson)
          .toList(growable: false);
      return _cachedConfigs!;
    } catch (_) {
      _cachedConfigs = const [];
      return _cachedConfigs!;
    }
  }

  static _FallbackMatch? _matchPattern({
    required _FallbackBankConfig config,
    required _FallbackPattern pattern,
    required Bank bank,
    required String messageBody,
    required DateTime? messageDate,
  }) {
    final amountMatch = _firstMatch(pattern.amountRegex, messageBody);
    if (amountMatch == null) return null;

    final amountText = _firstCapturedValue(amountMatch);
    final amount = _parseAmount(amountText);
    if (amount == null) return null;

    final creditMatched = _matches(pattern.creditRegex, messageBody);
    final debitMatched = _matches(pattern.debitRegex, messageBody);
    if (!creditMatched && !debitMatched) return null;

    final currencyRegex = pattern.currencyRegex;
    final currencyMatched =
        !_isUsableRegex(currencyRegex) || _matches(currencyRegex, messageBody);
    if (!currencyMatched) return null;

    final accountMatch = _firstMatch(pattern.accountRegex, messageBody);
    final hasAccountRegex = _isUsableRegex(pattern.accountRegex);
    final rawAccount = accountMatch == null
        ? null
        : _firstCapturedValue(accountMatch) ?? accountMatch.group(0);
    final accountNumber = _normalizeAccountNumber(
      rawAccount,
      bank: bank,
      phoneIsAccount: config.phoneIsAccount,
    );

    if (hasAccountRegex &&
        accountNumber == null &&
        bank.uniformMasking != false &&
        !config.phoneIsAccount) {
      return null;
    }

    final balanceMatch = _firstMatch(pattern.balanceRegex, messageBody);
    final balance = balanceMatch == null
        ? null
        : _cleanNumber(_firstCapturedValue(balanceMatch));

    final linkMatch = _firstMatch(pattern.linkRegex, messageBody);
    final linkOrReference =
        linkMatch == null ? null : _firstCapturedValue(linkMatch);
    final transactionLink = _looksLikeUrl(linkOrReference)
        ? linkOrReference
        : _extractUrl(messageBody);

    final type = creditMatched ? 'CREDIT' : 'DEBIT';
    final reference = _buildReference(
      messageBody: messageBody,
      bankId: bank.id,
      patternId: pattern.id,
      linkOrReference: linkOrReference,
      messageDate: messageDate,
    );

    var score = 0;
    score += 10;
    score += creditMatched || debitMatched ? 6 : 0;
    score += accountNumber != null ? 4 : 0;
    score += balance != null ? 3 : 0;
    score += currencyMatched ? 2 : 0;
    score += linkOrReference != null ? 1 : 0;

    final details = <String, dynamic>{
      'type': type,
      'bankId': bank.id,
      'patternDescription':
          'Fallback parser ${config.name} ${pattern.id} $type',
      'amount': amount,
      'reference': reference,
      'time': (messageDate ?? DateTime.now()).toIso8601String(),
    };

    if (balance != null) details['currentBalance'] = balance;
    if (accountNumber != null) details['accountNumber'] = accountNumber;
    if (transactionLink != null) details['transactionLink'] = transactionLink;

    return _FallbackMatch(score: score, details: details);
  }

  static RegExpMatch? _firstMatch(String? rawRegex, String body) {
    if (!_isUsableRegex(rawRegex)) return null;
    try {
      final regex = RegExp(
        _normalizeRegex(rawRegex!.trim()),
        caseSensitive: false,
        multiLine: true,
        dotAll: true,
      );
      return regex.firstMatch(body);
    } catch (_) {
      return null;
    }
  }

  static bool _matches(String? rawRegex, String body) {
    return _firstMatch(rawRegex, body) != null;
  }

  static bool _isUsableRegex(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return false;
    return trimmed.toUpperCase() != 'N/A';
  }

  static String _normalizeRegex(String regex) {
    return regex.replaceAll(r'\X', 'X');
  }

  static String? _firstCapturedValue(RegExpMatch match) {
    for (var index = 1; index <= match.groupCount; index++) {
      final value = match.group(index)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }

    final fullMatch = match.group(0)?.trim();
    return fullMatch == null || fullMatch.isEmpty ? null : fullMatch;
  }

  static double? _parseAmount(String? value) {
    final cleaned = _cleanNumber(value);
    if (cleaned == null || cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static String? _cleanNumber(String? value) {
    if (value == null) return null;
    var cleaned = value.replaceAll(',', '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'[^0-9.]'), '');
    final firstDot = cleaned.indexOf('.');
    if (firstDot >= 0) {
      cleaned = cleaned.substring(0, firstDot + 1) +
          cleaned.substring(firstDot + 1).replaceAll('.', '');
    }
    cleaned = cleaned.replaceAll(RegExp(r'\.+$'), '');
    return cleaned.isEmpty ? null : cleaned;
  }

  static String? _normalizeAccountNumber(
    String? rawAccount, {
    required Bank bank,
    required bool phoneIsAccount,
  }) {
    if (phoneIsAccount) return null;
    final account = rawAccount?.trim();
    if (account == null || account.isEmpty) return null;

    final maskPattern = bank.maskPattern;
    if (bank.uniformMasking == true &&
        maskPattern != null &&
        maskPattern > 0 &&
        account.length >= maskPattern) {
      return account.substring(account.length - maskPattern);
    }

    return account;
  }

  static String _buildReference({
    required String messageBody,
    required int bankId,
    required String patternId,
    required String? linkOrReference,
    required DateTime? messageDate,
  }) {
    final explicitReference = _cleanReference(linkOrReference) ??
        _extractReferenceFromBody(messageBody);
    if (explicitReference != null) return explicitReference;

    final timestamp = messageDate?.millisecondsSinceEpoch ?? 0;
    return 'fallback_${bankId}_${patternId}_${timestamp}_${_stableHash(messageBody)}';
  }

  static String? _cleanReference(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.length > 160 ? trimmed.substring(0, 160) : trimmed;
  }

  static String? _extractReferenceFromBody(String body) {
    final patterns = [
      RegExp(
        r'(?:transaction|txn|trx|reference|ref)(?:\s+number|\s+no\.?)?\s*(?:is|:)?\s*([A-Z0-9][A-Z0-9._/-]{3,})',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(FT[A-Z0-9]{6,})\b',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      final value = match == null ? null : _firstCapturedValue(match);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static bool _looksLikeUrl(String? value) {
    final lower = value?.trim().toLowerCase();
    return lower != null &&
        (lower.startsWith('http://') || lower.startsWith('https://'));
  }

  static String? _extractUrl(String body) {
    final match =
        RegExp(r'https?://\S+', caseSensitive: false).firstMatch(body);
    return match?.group(0);
  }

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _FallbackBankConfig {
  final String bankId;
  final String name;
  final bool phoneIsAccount;
  final List<_FallbackPattern> patterns;

  const _FallbackBankConfig({
    required this.bankId,
    required this.name,
    required this.phoneIsAccount,
    required this.patterns,
  });

  factory _FallbackBankConfig.fromJson(Map<String, dynamic> json) {
    final rawPatterns = json['regexPatterns'];
    return _FallbackBankConfig(
      bankId: (json['bankId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phoneIsAccount: json['phoneIsAccount'] == true,
      patterns: rawPatterns is List
          ? rawPatterns
              .whereType<Map<String, dynamic>>()
              .map(_FallbackPattern.fromJson)
              .toList(growable: false)
          : const [],
    );
  }
}

class _FallbackPattern {
  final String id;
  final String? amountRegex;
  final String? balanceRegex;
  final String? accountRegex;
  final String? linkRegex;
  final String? currencyRegex;
  final String? debitRegex;
  final String? creditRegex;

  const _FallbackPattern({
    required this.id,
    required this.amountRegex,
    required this.balanceRegex,
    required this.accountRegex,
    required this.linkRegex,
    required this.currencyRegex,
    required this.debitRegex,
    required this.creditRegex,
  });

  factory _FallbackPattern.fromJson(Map<String, dynamic> json) {
    return _FallbackPattern(
      id: (json['id'] ?? 'unknown').toString(),
      amountRegex: _stringOrNull(json['amount']),
      balanceRegex: _stringOrNull(json['balance']),
      accountRegex: _stringOrNull(json['account']),
      linkRegex: _stringOrNull(json['link']),
      currencyRegex: _stringOrNull(json['currencyRegex']),
      debitRegex: _stringOrNull(json['debit']),
      creditRegex: _stringOrNull(json['credit']),
    );
  }

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }
}

class _FallbackMatch {
  final int score;
  final Map<String, dynamic> details;

  const _FallbackMatch({
    required this.score,
    required this.details,
  });
}
