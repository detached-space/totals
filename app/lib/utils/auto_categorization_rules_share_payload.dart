import 'dart:convert';
import 'dart:io';

import 'package:totals/models/auto_categorization.dart';
import 'package:totals/models/category.dart';

String? _asText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '');
}

bool _asBool(dynamic value, {bool defaultValue = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == '1') return true;
  if (normalized == 'false' || normalized == '0') return false;
  return defaultValue;
}

String _normalizeFlow(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == 'income' || normalized == 'i' ? 'income' : 'expense';
}

String _normalizeCounterparty(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

String _flowCode(String flow) => _normalizeFlow(flow) == 'income' ? 'i' : 'e';

String? _listText(List<dynamic> values, int index) {
  if (index < 0 || index >= values.length) return null;
  return _asText(values[index]);
}

int? _listInt(List<dynamic> values, int index) {
  if (index < 0 || index >= values.length) return null;
  return _asInt(values[index]);
}

List<dynamic> _withoutTrailingNulls(List<dynamic> values) {
  var end = values.length;
  while (end > 0 && values[end - 1] == null) {
    end--;
  }
  return values.take(end).toList(growable: false);
}

class AutoCategorizationRulesShareCategory {
  final int sourceId;
  final String name;
  final bool essential;
  final bool uncategorized;
  final String? iconKey;
  final String? colorKey;
  final String? description;
  final String flow;
  final bool recurring;
  final String? builtInKey;

  const AutoCategorizationRulesShareCategory({
    required this.sourceId,
    required this.name,
    required this.essential,
    required this.uncategorized,
    required this.iconKey,
    required this.colorKey,
    required this.description,
    required this.flow,
    required this.recurring,
    required this.builtInKey,
  });

  factory AutoCategorizationRulesShareCategory.fromCategory(Category category) {
    return AutoCategorizationRulesShareCategory(
      sourceId: category.id!,
      name: category.name,
      essential: category.essential,
      uncategorized: category.uncategorized,
      iconKey: category.iconKey,
      colorKey: category.colorKey,
      description: category.description,
      flow: _normalizeFlow(category.flow),
      recurring: category.recurring,
      builtInKey: category.builtInKey,
    );
  }

  static AutoCategorizationRulesShareCategory? tryFromJson(
    Map<String, dynamic> json,
  ) {
    final sourceId = _asInt(json['s'] ?? json['sourceId'] ?? json['id']);
    final name = _asText(json['n'] ?? json['name']);
    if (sourceId == null || sourceId <= 0 || name == null) return null;

    return AutoCategorizationRulesShareCategory(
      sourceId: sourceId,
      name: name,
      essential: _asBool(json['e'] ?? json['essential']),
      uncategorized: _asBool(json['u'] ?? json['uncategorized']),
      iconKey: _asText(json['i'] ?? json['iconKey']),
      colorKey: _asText(json['k'] ?? json['colorKey']),
      description: _asText(json['d'] ?? json['description']),
      flow: _normalizeFlow(_asText(json['f'] ?? json['flow'])),
      recurring: _asBool(json['r'] ?? json['recurring']),
      builtInKey: _asText(json['b'] ?? json['builtInKey']),
    );
  }

  static AutoCategorizationRulesShareCategory? tryFromCompactJson(
    List<dynamic> values, {
    required String defaultFlow,
  }) {
    final sourceId = _listInt(values, 0);
    final name = _listText(values, 1);
    if (sourceId == null || sourceId <= 0 || name == null) return null;

    final flags = _listInt(values, 2) ?? 0;
    return AutoCategorizationRulesShareCategory(
      sourceId: sourceId,
      name: name,
      essential: flags & 1 != 0,
      uncategorized: flags & 2 != 0,
      recurring: flags & 4 != 0,
      flow: _normalizeFlow(_listText(values, 3) ?? defaultFlow),
      iconKey: _listText(values, 4),
      colorKey: _listText(values, 5),
      description: _listText(values, 6),
      builtInKey: _listText(values, 7),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      's': sourceId,
      'n': name,
      'f': flow,
      if (essential) 'e': true,
      if (uncategorized) 'u': true,
      if (iconKey != null) 'i': iconKey,
      if (colorKey != null) 'k': colorKey,
      if (description != null) 'd': description,
      if (recurring) 'r': true,
      if (builtInKey != null) 'b': builtInKey,
    };
  }

  List<dynamic> toCompactJson({required String defaultFlow}) {
    final flags =
        (essential ? 1 : 0) | (uncategorized ? 2 : 0) | (recurring ? 4 : 0);
    return _withoutTrailingNulls([
      sourceId,
      name,
      flags,
      _flowCode(flow.isEmpty ? defaultFlow : flow),
      iconKey,
      colorKey,
      description,
      builtInKey,
    ]);
  }
}

class AutoCategorizationRulesShareRule {
  final String counterparty;
  final String normalizedCounterparty;
  final String flow;
  final int sourceCategoryId;
  final bool isPrimary;

  const AutoCategorizationRulesShareRule({
    required this.counterparty,
    required this.normalizedCounterparty,
    required this.flow,
    required this.sourceCategoryId,
    required this.isPrimary,
  });

  factory AutoCategorizationRulesShareRule.fromRule(
    AutoCategorizationRule rule,
  ) {
    return AutoCategorizationRulesShareRule(
      counterparty: rule.counterparty,
      normalizedCounterparty: rule.normalizedCounterparty.isNotEmpty
          ? rule.normalizedCounterparty
          : _normalizeCounterparty(rule.counterparty),
      flow: _normalizeFlow(rule.flow),
      sourceCategoryId: rule.categoryId,
      isPrimary: rule.isPrimary,
    );
  }

  static AutoCategorizationRulesShareRule? tryFromJson(
    Map<String, dynamic> json,
  ) {
    final counterparty = _asText(json['p'] ?? json['counterparty']);
    final sourceCategoryId = _asInt(
      json['c'] ?? json['categoryId'] ?? json['sourceCategoryId'],
    );
    if (counterparty == null ||
        sourceCategoryId == null ||
        sourceCategoryId <= 0) {
      return null;
    }

    final normalizedCounterparty = _asText(
          json['n'] ?? json['normalizedCounterparty'],
        ) ??
        _normalizeCounterparty(counterparty);

    return AutoCategorizationRulesShareRule(
      counterparty: counterparty,
      normalizedCounterparty: normalizedCounterparty,
      flow: _normalizeFlow(_asText(json['f'] ?? json['flow'])),
      sourceCategoryId: sourceCategoryId,
      isPrimary: _asBool(json['m'] ?? json['isPrimary'], defaultValue: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'p': counterparty,
      'n': normalizedCounterparty,
      'f': flow,
      'c': sourceCategoryId,
      if (isPrimary) 'm': true,
    };
  }

  static List<AutoCategorizationRulesShareRule> compactRulesFromJson(
    List<dynamic> values, {
    required String defaultFlow,
  }) {
    final counterparty = _listText(values, 0);
    if (counterparty == null) return const <AutoCategorizationRulesShareRule>[];

    var cursor = 1;
    var flow = defaultFlow;
    final possibleFlow = _listText(values, cursor);
    if (possibleFlow == 'e' ||
        possibleFlow == 'i' ||
        possibleFlow == 'expense' ||
        possibleFlow == 'income') {
      flow = _normalizeFlow(possibleFlow);
      cursor++;
    }

    final primaryCategoryId = _listInt(values, cursor);
    if (primaryCategoryId == null || primaryCategoryId <= 0) {
      return const <AutoCategorizationRulesShareRule>[];
    }
    cursor++;

    final rules = <AutoCategorizationRulesShareRule>[
      AutoCategorizationRulesShareRule(
        counterparty: counterparty,
        normalizedCounterparty: _normalizeCounterparty(counterparty),
        flow: flow,
        sourceCategoryId: primaryCategoryId,
        isPrimary: true,
      ),
    ];

    if (cursor < values.length) {
      final rawSecondaryIds = values[cursor];
      if (rawSecondaryIds is List) {
        for (final value in rawSecondaryIds) {
          final categoryId = _asInt(value);
          if (categoryId == null || categoryId <= 0) continue;
          if (categoryId == primaryCategoryId) continue;
          rules.add(
            AutoCategorizationRulesShareRule(
              counterparty: counterparty,
              normalizedCounterparty: _normalizeCounterparty(counterparty),
              flow: flow,
              sourceCategoryId: categoryId,
              isPrimary: false,
            ),
          );
        }
      }
    }

    return rules;
  }
}

class AutoCategorizationRulesImportResult {
  final int createdCategories;
  final int matchedCategories;
  final int importedRuleGroups;
  final int importedRules;

  const AutoCategorizationRulesImportResult({
    required this.createdCategories,
    required this.matchedCategories,
    required this.importedRuleGroups,
    required this.importedRules,
  });

  bool get importedAnything => importedRules > 0;
}

class AutoCategorizationRulesSharePayload {
  static const int currentVersion = 2;
  static const String prefix = 'totals:autocat:';
  static const String type = 'totals.autoCategoryRules';
  static const String _gzipMarker = 'gz:';

  final int version;
  final String flow;
  final String generatedAt;
  final List<AutoCategorizationRulesShareCategory> categories;
  final List<AutoCategorizationRulesShareRule> rules;

  const AutoCategorizationRulesSharePayload({
    this.version = currentVersion,
    required this.flow,
    required this.generatedAt,
    required this.categories,
    required this.rules,
  });

  factory AutoCategorizationRulesSharePayload.fromRules({
    required Iterable<AutoCategorizationRule> rules,
    required Category? Function(int?) resolveCategory,
    required String flow,
  }) {
    final categoryBySourceId = <int, AutoCategorizationRulesShareCategory>{};
    final exportedRules = <AutoCategorizationRulesShareRule>[];

    for (final rule in rules) {
      final category = resolveCategory(rule.categoryId);
      final categoryId = category?.id;
      if (category == null || categoryId == null || categoryId <= 0) {
        continue;
      }

      categoryBySourceId.putIfAbsent(
        categoryId,
        () => AutoCategorizationRulesShareCategory.fromCategory(category),
      );
      exportedRules.add(AutoCategorizationRulesShareRule.fromRule(rule));
    }

    return AutoCategorizationRulesSharePayload(
      flow: _normalizeFlow(flow),
      generatedAt: DateTime.now().toIso8601String(),
      categories: categoryBySourceId.values.toList(growable: false),
      rules: exportedRules,
    );
  }

  static String encode(AutoCategorizationRulesSharePayload payload) {
    final jsonText = jsonEncode(payload.toCompactJson());
    final compressed = gzip.encode(utf8.encode(jsonText));
    final encoded = base64Url.encode(compressed).replaceAll('=', '');
    return '$prefix$_gzipMarker$encoded';
  }

  static AutoCategorizationRulesSharePayload? decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith(prefix)) {
      final encoded = trimmed.substring(prefix.length);
      if (encoded.startsWith(_gzipMarker)) {
        return _parseCompressedEncoded(encoded.substring(_gzipMarker.length));
      }
      final parsedFromCompressed = _parseCompressedEncoded(encoded);
      if (parsedFromCompressed != null) return parsedFromCompressed;
      final parsedFromEncoded = _parseEncoded(encoded);
      if (parsedFromEncoded != null) return parsedFromEncoded;
      return _parseJsonPayload(encoded);
    }

    return _parseJsonPayload(trimmed) ??
        _parseCompressedEncoded(trimmed) ??
        _parseEncoded(trimmed);
  }

  static AutoCategorizationRulesSharePayload? _parseCompressedEncoded(
    String encoded,
  ) {
    final normalized = _normalizeBase64(encoded);
    if (normalized == null) return null;
    try {
      final bytes = base64Url.decode(normalized);
      final decoded = utf8.decode(gzip.decode(bytes));
      return _parseJsonPayload(decoded);
    } catch (_) {
      return null;
    }
  }

  static AutoCategorizationRulesSharePayload? _parseEncoded(String encoded) {
    final normalized = _normalizeBase64(encoded);
    if (normalized == null) return null;
    try {
      return _parseJsonPayload(utf8.decode(base64Url.decode(normalized)));
    } catch (_) {
      return null;
    }
  }

  static String? _normalizeBase64(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;
    final remainder = cleaned.length % 4;
    final padding = remainder == 0 ? '' : '=' * (4 - remainder);
    return cleaned + padding;
  }

  static AutoCategorizationRulesSharePayload? _parseJsonPayload(
    String rawJson,
  ) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(rawJson);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    return tryFromJson(Map<String, dynamic>.from(decoded));
  }

  static AutoCategorizationRulesSharePayload? tryFromJson(
    Map<String, dynamic> json,
  ) {
    final rawType = _asText(json['t'] ?? json['type']);
    if (rawType != null && rawType != type && rawType != 'a') return null;
    final payloadFlow = _normalizeFlow(_asText(json['f'] ?? json['flow']));

    final categories = <AutoCategorizationRulesShareCategory>[];
    final rawCategories = json['c'] ?? json['categories'];
    if (rawCategories is List) {
      for (final entry in rawCategories) {
        final category = entry is Map
            ? AutoCategorizationRulesShareCategory.tryFromJson(
                Map<String, dynamic>.from(entry),
              )
            : entry is List
                ? AutoCategorizationRulesShareCategory.tryFromCompactJson(
                    entry,
                    defaultFlow: payloadFlow,
                  )
                : null;
        if (category != null) categories.add(category);
      }
    }

    final rules = <AutoCategorizationRulesShareRule>[];
    final rawRules = json['r'] ?? json['rules'];
    if (rawRules is List) {
      for (final entry in rawRules) {
        if (entry is Map) {
          final rule = AutoCategorizationRulesShareRule.tryFromJson(
            Map<String, dynamic>.from(entry),
          );
          if (rule != null) rules.add(rule);
        } else if (entry is List) {
          rules.addAll(
            AutoCategorizationRulesShareRule.compactRulesFromJson(
              entry,
              defaultFlow: payloadFlow,
            ),
          );
        }
      }
    }

    if (categories.isEmpty || rules.isEmpty) return null;

    return AutoCategorizationRulesSharePayload(
      version: _asInt(json['v'] ?? json['version']) ?? currentVersion,
      flow: payloadFlow,
      generatedAt: _asText(json['g'] ?? json['generatedAt']) ??
          DateTime.now().toIso8601String(),
      categories: categories,
      rules: rules,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      't': type,
      'v': version,
      'f': flow,
      'g': generatedAt,
      'c': categories.map((category) => category.toJson()).toList(),
      'r': rules.map((rule) => rule.toJson()).toList(),
    };
  }

  Map<String, dynamic> toCompactJson() {
    final groupedRules = <String, _CompactRuleGroup>{};
    for (final rule in rules) {
      final normalizedCounterparty = rule.normalizedCounterparty.isNotEmpty
          ? rule.normalizedCounterparty
          : _normalizeCounterparty(rule.counterparty);
      final ruleFlow = _normalizeFlow(rule.flow);
      final key = '$normalizedCounterparty::$ruleFlow';
      final group = groupedRules.putIfAbsent(
        key,
        () => _CompactRuleGroup(
          counterparty: rule.counterparty,
          flow: ruleFlow,
        ),
      );
      group.add(rule.sourceCategoryId, isPrimary: rule.isPrimary);
    }

    return {
      't': 'a',
      'v': currentVersion,
      'f': _flowCode(flow),
      'c': categories
          .map((category) => category.toCompactJson(defaultFlow: flow))
          .toList(),
      'r': groupedRules.values
          .map((rule) => rule.toJson(defaultFlow: flow))
          .toList(),
    };
  }
}

class _CompactRuleGroup {
  final String counterparty;
  final String flow;
  final List<int> categoryIds = [];
  int? primaryCategoryId;

  _CompactRuleGroup({
    required this.counterparty,
    required this.flow,
  });

  void add(int categoryId, {required bool isPrimary}) {
    if (categoryId <= 0) return;
    if (!categoryIds.contains(categoryId)) {
      categoryIds.add(categoryId);
    }
    if (isPrimary || primaryCategoryId == null) {
      primaryCategoryId = categoryId;
    }
  }

  List<dynamic> toJson({required String defaultFlow}) {
    final primaryId = primaryCategoryId ?? categoryIds.first;
    final secondaryIds = categoryIds
        .where((categoryId) => categoryId != primaryId)
        .toList(growable: false);
    if (_normalizeFlow(flow) == _normalizeFlow(defaultFlow)) {
      return _withoutTrailingNulls([
        counterparty,
        primaryId,
        secondaryIds.isEmpty ? null : secondaryIds,
      ]);
    }

    return _withoutTrailingNulls([
      counterparty,
      _flowCode(flow),
      primaryId,
      secondaryIds.isEmpty ? null : secondaryIds,
    ]);
  }
}
