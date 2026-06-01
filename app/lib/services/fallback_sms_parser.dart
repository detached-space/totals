import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:totals/models/bank.dart';

class FallbackSmsParser {
  static bool get isEnabled => false;

  static const String _assetPath = 'assets/fallback_sms_patterns.json';
  static const String _schema = 'totals.fallbackSmsPatterns.v1';

  static List<_FallbackBankConfig>? _cachedConfigs;

  static Future<Set<int>> supportedBankIds({
    bool requirePatterns = false,
  }) async {
    if (!isEnabled) return const <int>{};

    final configs = await _loadConfigs();
    final supported = <int>{};

    for (final config in configs) {
      if (!requirePatterns || config.patterns.isNotEmpty) {
        supported.add(config.bankId);
      }
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
    if (!isEnabled) return null;

    final configs = await _configsForTotalsBank(bank.id);
    if (configs.isEmpty) return null;

    _FallbackMatch? bestMatch;
    for (final config in configs) {
      for (final pattern in config.patterns) {
        if (!pattern.enabled) continue;

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
    final configs = await _loadConfigs();
    return configs
        .where((config) => config.bankId == totalsBankId)
        .toList(growable: false);
  }

  static Future<List<_FallbackBankConfig>> _loadConfigs() async {
    if (_cachedConfigs != null) return _cachedConfigs!;

    try {
      final body = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['schema'] != _schema) {
        _cachedConfigs = const [];
        return _cachedConfigs!;
      }

      final rawBanks = decoded['banks'];
      _cachedConfigs = rawBanks is List
          ? rawBanks
              .whereType<Map<String, dynamic>>()
              .map(_FallbackBankConfig.fromJson)
              .toList(growable: false)
          : const [];
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

    final type = _resolveTransactionType(pattern, messageBody);
    if (type == null) return null;

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
      phoneIsAccount: _phoneIsAccount(bank),
    );

    if (hasAccountRegex &&
        accountNumber == null &&
        bank.uniformMasking != false &&
        !_phoneIsAccount(bank)) {
      return null;
    }

    final balanceMatch = _firstMatch(pattern.balanceRegex, messageBody);
    final balance = balanceMatch == null
        ? null
        : _cleanNumber(_firstCapturedValue(balanceMatch));

    final linkMatch = _firstMatch(pattern.linkRegex, messageBody);
    final linkOrReference =
        linkMatch == null ? null : _firstCapturedValue(linkMatch);
    final transactionLink = _resolveTransactionLink(
      linkOrReference: linkOrReference,
      messageBody: messageBody,
    );

    final reference = _buildReference(
      messageBody: messageBody,
      bankId: bank.id,
      pattern: pattern,
      linkOrReference: linkOrReference,
      messageDate: messageDate,
    );
    final counterparty = _extractCounterparty(
      type: type,
      config: config,
      pattern: pattern,
      messageBody: messageBody,
    );

    var score = 0;
    score += 10;
    score += 6;
    score += accountNumber != null ? 4 : 0;
    score += counterparty != null ? 4 : 0;
    score += balance != null ? 3 : 0;
    score += currencyMatched ? 2 : 0;
    score += linkOrReference != null ? 1 : 0;

    final details = <String, dynamic>{
      'type': type,
      'bankId': bank.id,
      'patternDescription':
          'Fallback parser ${config.displayName} ${pattern.id} $type',
      'amount': amount,
      'reference': reference,
      'time': (messageDate ?? DateTime.now()).toIso8601String(),
    };

    if (balance != null) details['currentBalance'] = balance;
    if (accountNumber != null) details['accountNumber'] = accountNumber;
    if (transactionLink != null) details['transactionLink'] = transactionLink;
    if (counterparty != null && type == 'CREDIT') {
      details['creditor'] = counterparty;
    } else if (counterparty != null) {
      details['receiver'] = counterparty;
    }

    return _FallbackMatch(score: score, details: details);
  }

  static String? _resolveTransactionType(
    _FallbackPattern pattern,
    String messageBody,
  ) {
    final creditHasMatcher = _isUsableRegex(pattern.creditRegex);
    final debitHasMatcher = _isUsableRegex(pattern.debitRegex);
    final creditMatched = creditHasMatcher
        ? _matches(pattern.creditRegex, messageBody)
        : pattern.declaredType == 'CREDIT';
    final debitMatched = debitHasMatcher
        ? _matches(pattern.debitRegex, messageBody)
        : pattern.declaredType == 'DEBIT';

    if (pattern.declaredType == 'CREDIT') {
      return creditMatched ? 'CREDIT' : null;
    }
    if (pattern.declaredType == 'DEBIT') {
      return debitMatched ? 'DEBIT' : null;
    }
    if (!creditMatched && !debitMatched) return null;
    if (creditMatched && debitMatched) {
      if (_isCatchAllRegex(pattern.creditRegex) &&
          !_isCatchAllRegex(pattern.debitRegex)) {
        return 'DEBIT';
      }
      if (_isCatchAllRegex(pattern.debitRegex) &&
          !_isCatchAllRegex(pattern.creditRegex)) {
        return 'CREDIT';
      }
    }
    return creditMatched ? 'CREDIT' : 'DEBIT';
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

  static bool _isCatchAllRegex(String? value) {
    final normalized = value?.replaceAll(RegExp(r'\s+'), '').trim();
    return normalized == '.*' || normalized == '^.*\$';
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

  static bool _phoneIsAccount(Bank bank) {
    return bank.simBased == true && bank.uniformMasking == false;
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
    required _FallbackPattern pattern,
    required String? linkOrReference,
    required DateTime? messageDate,
  }) {
    final explicitReference = _extractPatternReference(pattern, messageBody) ??
        _cleanReference(
          linkOrReference,
          rejectStatic: pattern.rejectStaticReference,
        ) ??
        _extractReferenceFromBody(messageBody);
    if (explicitReference != null) return explicitReference;

    final timestamp = messageDate?.millisecondsSinceEpoch ?? 0;
    final strategy = pattern.referenceFallback;
    if (strategy == 'timestamp_message_hash') {
      return 'fallback_${bankId}_${pattern.id}_${timestamp}_${_stableHash(messageBody)}';
    }
    return 'fallback_${bankId}_${pattern.id}_${_stableHash(messageBody)}';
  }

  static String? _extractPatternReference(
    _FallbackPattern pattern,
    String messageBody,
  ) {
    final match = _firstMatch(pattern.referenceRegex, messageBody);
    final value = match == null ? null : _firstCapturedValue(match);
    return _cleanReference(
      value,
      rejectStatic: pattern.rejectStaticReference,
    );
  }

  static String? _cleanReference(
    String? value, {
    bool rejectStatic = false,
  }) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (rejectStatic && _looksStaticReference(trimmed)) return null;
    return trimmed.length > 160 ? trimmed.substring(0, 160) : trimmed;
  }

  static bool _looksStaticReference(String value) {
    final lower = value.toLowerCase();
    if (lower == 'n/a') return true;
    if (lower.contains('ethiotelecom.et/telebirr')) return true;
    if (lower.contains('t.me/')) return true;
    if (lower.contains('forms.gle/')) return true;
    return false;
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

  static String? _extractCounterparty({
    required String type,
    required _FallbackBankConfig config,
    required _FallbackPattern pattern,
    required String messageBody,
  }) {
    final candidates = type == 'CREDIT'
        ? [
            ...pattern.counterpartyExtractors.creditor,
            ...config.counterpartyExtractors.creditor,
          ]
        : [
            ...pattern.counterpartyExtractors.receiver,
            ...config.counterpartyExtractors.receiver,
          ];

    for (final rawRegex in candidates) {
      final match = _firstMatch(rawRegex, messageBody);
      final value = match == null ? null : _firstCapturedValue(match);
      final counterparty = _cleanCounterparty(value);
      if (counterparty != null) return counterparty;
    }

    return null;
  }

  static String? _cleanCounterparty(String? value) {
    var cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s+and\s+(?:credited|debited|transferred|posted)\b.*$',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\s+on\s*:?\s*\d.*$', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r',?\s*remarks?\b.*$', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\s+with\s+payment\b.*$', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\s+through\s+cash deposit\b.*$', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*(?:your transaction|your current|thank you|txn id|transaction number|to download).*$',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s*[.,;:]+$'), '').trim();

    if (cleaned.length < 2) return null;
    if (_looksLikeUrl(cleaned)) return null;
    if (RegExp(
      r'^[\d*Xx\s()\-+./]{4,}$',
    ).hasMatch(cleaned)) {
      return null;
    }
    if (RegExp(r'^\d{1,2}:\d{2}').hasMatch(cleaned)) return null;
    if (RegExp(
      r'(?:receive transaction notification|latest updates|for any support|\bdownload\b|transaction reference|transaction id|\bref(?:erence)?\b|new balance|avail(?:able)? balance|current balance|remaining balance|\bcharge\b|\bvat\b|\bdate\b|account transfer|using branch|bank ref|receipt|\bto download\b|\bwith etb\b|\bbank to\b|is made (?:from|to))',
      caseSensitive: false,
    ).hasMatch(cleaned)) {
      return null;
    }
    if (RegExp(
      r'^(?:etb|birr|br|transaction|txn|ref|reference|balance|receive|get|keep|pos|pos transaction|mobile banking|ethswitch|acount|acount transaction|tele-birr via mobile|withdraw.*|the m-pesa.*|using.*|additional information.*|on.*)$',
      caseSensitive: false,
    ).hasMatch(cleaned)) {
      return null;
    }
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  static bool _looksLikeUrl(String? value) {
    final lower = value?.trim().toLowerCase();
    return lower != null &&
        (lower.startsWith('http://') || lower.startsWith('https://'));
  }

  static String? _resolveTransactionLink({
    required String? linkOrReference,
    required String messageBody,
  }) {
    final fullUrl = _extractUrl(messageBody);
    if (!_looksLikeUrl(linkOrReference)) return fullUrl;

    final capturedUrl = _cleanUrl(linkOrReference);
    if (capturedUrl == null) return fullUrl;

    if (fullUrl != null &&
        fullUrl.length > capturedUrl.length &&
        fullUrl.toLowerCase().startsWith(capturedUrl.toLowerCase())) {
      return fullUrl;
    }

    return capturedUrl;
  }

  static String? _extractUrl(String body) {
    final match = RegExp(
      r'''https?://[^\s<>"']+''',
      caseSensitive: false,
    ).firstMatch(body);
    return _cleanUrl(match?.group(0));
  }

  static String? _cleanUrl(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.replaceFirst(RegExp(r'[\].,;:)\s]+$'), '');
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
  final int bankId;
  final String bankKey;
  final String displayName;
  final _CounterpartyExtractors counterpartyExtractors;
  final List<_FallbackPattern> patterns;

  const _FallbackBankConfig({
    required this.bankId,
    required this.bankKey,
    required this.displayName,
    required this.counterpartyExtractors,
    required this.patterns,
  });

  factory _FallbackBankConfig.fromJson(Map<String, dynamic> json) {
    final rawRules = json['rules'];
    return _FallbackBankConfig(
      bankId: (json['bankId'] as num?)?.toInt() ?? -1,
      bankKey: (json['bankKey'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      counterpartyExtractors: _CounterpartyExtractors.fromJson(
        json['counterparty'],
      ),
      patterns: rawRules is List
          ? rawRules
              .whereType<Map<String, dynamic>>()
              .map(_FallbackPattern.fromJson)
              .toList(growable: false)
          : const [],
    );
  }
}

class _FallbackPattern {
  final String id;
  final bool enabled;
  final String declaredType;
  final String? amountRegex;
  final String? balanceRegex;
  final String? accountRegex;
  final String? linkRegex;
  final String? referenceRegex;
  final String referenceFallback;
  final bool rejectStaticReference;
  final String? currencyRegex;
  final String? debitRegex;
  final String? creditRegex;
  final _CounterpartyExtractors counterpartyExtractors;

  const _FallbackPattern({
    required this.id,
    required this.enabled,
    required this.declaredType,
    required this.amountRegex,
    required this.balanceRegex,
    required this.accountRegex,
    required this.linkRegex,
    required this.referenceRegex,
    required this.referenceFallback,
    required this.rejectStaticReference,
    required this.currencyRegex,
    required this.debitRegex,
    required this.creditRegex,
    required this.counterpartyExtractors,
  });

  factory _FallbackPattern.fromJson(Map<String, dynamic> json) {
    final matchers = _mapOrNull(json['matchers']);
    final extractors = _mapOrNull(json['extractors']);
    final currency = _mapOrNull(json['currency']);
    final reference = _mapOrNull(json['reference']);

    return _FallbackPattern(
      id: (json['id'] ?? 'unknown').toString(),
      enabled: json['enabled'] != false,
      declaredType: (json['type'] ?? 'AUTO').toString().toUpperCase(),
      amountRegex: _stringOrNull(extractors?['amount']),
      balanceRegex: _stringOrNull(extractors?['balance']),
      accountRegex: _stringOrNull(extractors?['account']),
      linkRegex: _stringOrNull(extractors?['link']),
      referenceRegex: _stringOrNull(reference?['extractor']),
      referenceFallback:
          (reference?['fallback'] ?? 'timestamp_message_hash').toString(),
      rejectStaticReference: reference?['rejectStatic'] != false,
      currencyRegex: _stringOrNull(currency?['matcher']),
      debitRegex: _stringOrNull(matchers?['debit']),
      creditRegex: _stringOrNull(matchers?['credit']),
      counterpartyExtractors: _CounterpartyExtractors.fromJson(
        json['counterparty'],
      ),
    );
  }

  static Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return null;
  }

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }
}

class _CounterpartyExtractors {
  final List<String> creditor;
  final List<String> receiver;

  const _CounterpartyExtractors({
    required this.creditor,
    required this.receiver,
  });

  factory _CounterpartyExtractors.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return const _CounterpartyExtractors(
        creditor: [],
        receiver: [],
      );
    }
    return _CounterpartyExtractors(
      creditor: _stringList(json['creditor']),
      receiver: _stringList(json['receiver']),
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item?.toString().trim())
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
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
