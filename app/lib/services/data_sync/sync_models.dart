import 'dart:convert';

/// Pure data models + transform logic for the Data Sync feature.
///
/// Everything in this file is dependency-free (only `dart:convert`) so it can
/// be unit-tested without a database, HTTP client, or Flutter bindings. The
/// engine, repository, and UI build on top of these primitives.

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// The local entity types that can be exported.
enum SyncEntity { transactions, accounts, budgets }

extension SyncEntityX on SyncEntity {
  String get storage {
    switch (this) {
      case SyncEntity.transactions:
        return 'transactions';
      case SyncEntity.accounts:
        return 'accounts';
      case SyncEntity.budgets:
        return 'budgets';
    }
  }

  String get label {
    switch (this) {
      case SyncEntity.transactions:
        return 'Transactions';
      case SyncEntity.accounts:
        return 'Accounts';
      case SyncEntity.budgets:
        return 'Budgets';
    }
  }

  /// Field names available for mapping. Mirrors each model's `toJson()` keys so
  /// the rule editor can offer a dropdown without importing the model classes.
  List<String> get fieldKeys {
    switch (this) {
      case SyncEntity.transactions:
        return const [
          'amount',
          'reference',
          'creditor',
          'receiver',
          'note',
          'time',
          'status',
          'currentBalance',
          'bankId',
          'type',
          'transactionLink',
          'accountNumber',
          'categoryId',
          'categoryIds',
          'categoryNames',
          'profileId',
          'serviceCharge',
          'vat',
          'sourceType',
          'sourceMessageId',
          'sourceFingerprint',
        ];
      case SyncEntity.accounts:
        return const [
          'accountNumber',
          'bank',
          'bankName',
          'bankShortName',
          'balance',
          'accountHolderName',
          'settledBalance',
          'pendingCredit',
          'profileId',
        ];
      case SyncEntity.budgets:
        return const [
          'id',
          'name',
          'type',
          'amount',
          'categoryId',
          'categoryIds',
          'categoryNames',
          'startDate',
          'endDate',
          'rollover',
          'alertThreshold',
          'isActive',
          'createdAt',
          'updatedAt',
          'timeFrame',
          'calendar',
          'appliesToAllExpenses',
          'usedAmount',
          'availableAmount',
          'percentageUsed',
          'isExceeded',
          'isApproachingLimit',
          'periodStart',
          'periodEnd',
          'isRecurring',
          'recurrence',
        ];
    }
  }

  static SyncEntity fromStorage(String? value) {
    switch (value) {
      case 'accounts':
        return SyncEntity.accounts;
      case 'budgets':
        return SyncEntity.budgets;
      case 'transactions':
      default:
        return SyncEntity.transactions;
    }
  }
}

/// The operation an outbox row represents.
enum SyncOp { upsert, delete }

extension SyncOpX on SyncOp {
  String get storage => this == SyncOp.delete ? 'delete' : 'upsert';
  static SyncOp fromStorage(String? value) =>
      value == 'delete' ? SyncOp.delete : SyncOp.upsert;
}

/// Authentication scheme for a destination.
enum SyncAuthType { none, apiKey, bearer, basic }

extension SyncAuthTypeX on SyncAuthType {
  String get storage {
    switch (this) {
      case SyncAuthType.none:
        return 'none';
      case SyncAuthType.apiKey:
        return 'api_key';
      case SyncAuthType.bearer:
        return 'bearer';
      case SyncAuthType.basic:
        return 'basic';
    }
  }

  String get label {
    switch (this) {
      case SyncAuthType.none:
        return 'None';
      case SyncAuthType.apiKey:
        return 'API key header';
      case SyncAuthType.bearer:
        return 'Bearer token';
      case SyncAuthType.basic:
        return 'Basic auth';
    }
  }

  /// Whether this scheme requires a stored secret value.
  bool get needsSecret => this != SyncAuthType.none;

  static SyncAuthType fromStorage(String? value) {
    switch (value) {
      case 'api_key':
        return SyncAuthType.apiKey;
      case 'bearer':
        return SyncAuthType.bearer;
      case 'basic':
        return SyncAuthType.basic;
      case 'none':
      default:
        return SyncAuthType.none;
    }
  }
}

/// How records are batched into HTTP requests.
enum SyncBatchMode { perRecord, bulkArray }

extension SyncBatchModeX on SyncBatchMode {
  String get storage =>
      this == SyncBatchMode.bulkArray ? 'bulk_array' : 'per_record';
  String get label =>
      this == SyncBatchMode.bulkArray ? 'Bulk array' : 'One request per record';
  static SyncBatchMode fromStorage(String? value) =>
      value == 'bulk_array' ? SyncBatchMode.bulkArray : SyncBatchMode.perRecord;
}

/// Per-rule time-based schedule. Event triggers (on-new-txn, on-connectivity,
/// manual) are orthogonal and live on the rule as separate flags.
enum SyncScheduleMode { off, interval, daily }

extension SyncScheduleModeX on SyncScheduleMode {
  String get storage {
    switch (this) {
      case SyncScheduleMode.off:
        return 'off';
      case SyncScheduleMode.interval:
        return 'interval';
      case SyncScheduleMode.daily:
        return 'daily';
    }
  }

  static SyncScheduleMode fromStorage(String? value) {
    switch (value) {
      case 'interval':
        return SyncScheduleMode.interval;
      case 'daily':
        return SyncScheduleMode.daily;
      default:
        return SyncScheduleMode.off;
    }
  }
}

/// Background-reliable interval presets (minutes). Android won't run periodic
/// background work more often than ~15 min, so we don't offer anything below it.
const List<int> syncIntervalPresets = [15, 30, 60, 180, 360, 720];

/// Outbox row lifecycle states (stored as TEXT).
class SyncOutboxStatus {
  static const String pending = 'pending';
  static const String sending = 'sending';
  static const String sent = 'sent';
  static const String failed = 'failed';
  static const String dead = 'dead';
}

/// Allowed HTTP methods for a rule. Stored verbatim.
class SyncHttpMethod {
  static const List<String> all = ['POST', 'PUT', 'PATCH'];
  static String normalize(String? value) {
    final upper = (value ?? 'POST').trim().toUpperCase();
    return all.contains(upper) ? upper : 'POST';
  }
}

// ---------------------------------------------------------------------------
// Coercion helpers (DB rows store bools as int, numbers sometimes as String)
// ---------------------------------------------------------------------------

num? _asNum(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim());
  return null;
}

bool? _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.trim().toLowerCase();
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
  }
  return null;
}

DateTime? _asDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}

int _intCol(Object? value, [int fallback = 0]) =>
    _asNum(value)?.toInt() ?? fallback;

List<String> _decodeStringList(Object? raw) {
  if (raw is List) {
    return raw
        .map((e) => e?.toString())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return _decodeStringList(decoded);
    } catch (_) {}
  }
  return const [];
}

// ---------------------------------------------------------------------------
// SyncFilter — decides whether a record matches a rule.
// ---------------------------------------------------------------------------

/// A declarative, entity-aware filter. All set fields must match (logical AND).
/// `matches` operates on a raw DB row map, so it tolerates int/String/bool
/// representations. Amount comparisons use the absolute value, so "min 500"
/// matches a -500 debit.
class SyncFilter {
  /// Transactions only: 'CREDIT' | 'DEBIT'.
  final String? type;
  final double? minAmount;
  final double? maxAmount;

  /// Banks to include (by bank id). Empty/null = all banks.
  final List<int>? bankIds;

  /// Accounts to include, each as "<accountNumber>|<bank>". Empty/null = all.
  /// Transactions store only the account's last 4 digits, so transaction
  /// matching is by suffix; accounts match exactly.
  final List<String>? accountKeys;

  final DateTime? startDate;
  final DateTime? endDate;

  /// Budgets only: active-only.
  final bool? isActive;

  /// Scope to a single profile (transactions/accounts carry `profileId`).
  final int? profileId;

  const SyncFilter({
    this.type,
    this.minAmount,
    this.maxAmount,
    this.bankIds,
    this.accountKeys,
    this.startDate,
    this.endDate,
    this.isActive,
    this.profileId,
  });

  bool get isEmpty =>
      type == null &&
      minAmount == null &&
      maxAmount == null &&
      (bankIds == null || bankIds!.isEmpty) &&
      (accountKeys == null || accountKeys!.isEmpty) &&
      startDate == null &&
      endDate == null &&
      isActive == null &&
      profileId == null;

  bool matches(Map<String, dynamic> row) {
    if (type != null) {
      final rowType = (row['type'] as String?)?.trim().toUpperCase();
      if (rowType != type!.trim().toUpperCase()) return false;
    }

    if (minAmount != null || maxAmount != null) {
      final amount = _asNum(row['amount'])?.toDouble();
      if (amount == null) return false;
      final magnitude = amount.abs();
      if (minAmount != null && magnitude < minAmount!) return false;
      if (maxAmount != null && magnitude > maxAmount!) return false;
    }

    // Accounts use the `bank` column; transactions use `bankId`.
    final rowBank = _asNum(row['bankId'] ?? row['bank'])?.toInt();
    final hasBankSel = bankIds != null && bankIds!.isNotEmpty;
    final hasAcctSel = accountKeys != null && accountKeys!.isNotEmpty;
    if (hasBankSel || hasAcctSel) {
      // A record passes if it belongs to a selected bank OR a selected account.
      final bankMatch =
          hasBankSel && rowBank != null && bankIds!.contains(rowBank);
      final acctMatch = hasAcctSel && _matchesAnyAccount(row, rowBank);
      if (!bankMatch && !acctMatch) return false;
    }

    if (startDate != null || endDate != null) {
      final date = _asDate(row['time'] ?? row['createdAt'] ?? row['startDate']);
      if (date == null) return false;
      if (startDate != null && date.isBefore(startDate!)) return false;
      if (endDate != null && date.isAfter(endDate!)) return false;
    }

    if (isActive != null) {
      final rowActive = _asBool(row['isActive']);
      if (rowActive != isActive) return false;
    }

    if (profileId != null) {
      final rowProfile = _asNum(row['profileId'])?.toInt();
      if (rowProfile != profileId) return false;
    }

    return true;
  }

  bool _matchesAnyAccount(Map<String, dynamic> row, int? rowBank) {
    final rowAcct = (row['accountNumber'] as String?)?.trim();
    if (rowAcct == null || rowAcct.isEmpty) return false;
    for (final key in accountKeys!) {
      final sep = key.lastIndexOf('|');
      if (sep <= 0) continue;
      final keyNum = key.substring(0, sep);
      final keyBank = int.tryParse(key.substring(sep + 1));
      if (keyBank != null && rowBank != null && keyBank != rowBank) continue;
      // An accounts row holds the full number (exact match); a transaction row
      // holds only the last 4 digits, so fall back to a suffix match.
      if (keyNum == rowAcct) return true;
      if (rowAcct.length >= 3 && keyNum.endsWith(rowAcct)) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        if (type != null) 'type': type,
        if (minAmount != null) 'minAmount': minAmount,
        if (maxAmount != null) 'maxAmount': maxAmount,
        if (bankIds != null && bankIds!.isNotEmpty) 'bankIds': bankIds,
        if (accountKeys != null && accountKeys!.isNotEmpty)
          'accountKeys': accountKeys,
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (endDate != null) 'endDate': endDate!.toIso8601String(),
        if (isActive != null) 'isActive': isActive,
        if (profileId != null) 'profileId': profileId,
      };

  factory SyncFilter.fromJson(Map<String, dynamic> json) {
    List<int>? bankIds;
    final rawBankIds = json['bankIds'];
    if (rawBankIds is List) {
      bankIds =
          rawBankIds.map((e) => _asNum(e)?.toInt()).whereType<int>().toList();
    } else if (json['bankId'] != null) {
      // Back-compat: legacy single bankId.
      final single = _asNum(json['bankId'])?.toInt();
      if (single != null) bankIds = [single];
    }
    List<String>? accountKeys;
    final rawKeys = json['accountKeys'];
    if (rawKeys is List) {
      accountKeys = rawKeys
          .map((e) => e?.toString())
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return SyncFilter(
      type: json['type'] as String?,
      minAmount: _asNum(json['minAmount'])?.toDouble(),
      maxAmount: _asNum(json['maxAmount'])?.toDouble(),
      bankIds: (bankIds == null || bankIds.isEmpty) ? null : bankIds,
      accountKeys:
          (accountKeys == null || accountKeys.isEmpty) ? null : accountKeys,
      startDate: _asDate(json['startDate']),
      endDate: _asDate(json['endDate']),
      isActive: _asBool(json['isActive']),
      profileId: _asNum(json['profileId'])?.toInt(),
    );
  }

  /// Parse from a stored JSON string. Returns null for null/empty/invalid.
  static SyncFilter? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final filter = SyncFilter.fromJson(Map<String, dynamic>.from(decoded));
      return filter.isEmpty ? null : filter;
    } catch (_) {
      return null;
    }
  }

  String? encode() => isEmpty ? null : jsonEncode(toJson());
}

class SyncTransactionCategoryPayload {
  static const categoryNamesKey = 'categoryNames';

  /// Add human-readable category names to a transaction payload while preserving
  /// the existing categoryId/categoryIds fields for compatibility.
  static Map<String, dynamic> enrich(
    Map<String, dynamic> transaction,
    Iterable<Map<String, dynamic>> categoryPayloads,
  ) {
    final payload = Map<String, dynamic>.from(transaction);
    final selectedIds = categoryIdsFor(payload);
    final categoriesById = <int, Map<String, dynamic>>{};

    for (final category in categoryPayloads) {
      final id = _asInt(category['id']);
      if (id == null || !selectedIds.contains(id)) continue;
      categoriesById[id] = Map<String, dynamic>.from(category);
    }

    final categories = <Map<String, dynamic>>[
      for (final id in selectedIds)
        if (categoriesById[id] != null) categoriesById[id]!,
    ];

    payload[categoryNamesKey] = [
      for (final category in categories)
        if (_nameOf(category) != null) _nameOf(category)!,
    ];
    return payload;
  }

  static List<int> categoryIdsFor(Map<String, dynamic> transaction) {
    final ids = <int>[];

    void add(dynamic value) {
      final id = _asInt(value);
      if (id == null || id <= 0 || ids.contains(id)) return;
      ids.add(id);
    }

    add(transaction['categoryId']);
    final rawCategoryIds = transaction['categoryIds'];
    if (rawCategoryIds is Iterable) {
      for (final id in rawCategoryIds) {
        add(id);
      }
    } else if (rawCategoryIds is String) {
      final trimmed = rawCategoryIds.trim();
      if (trimmed.isNotEmpty) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Iterable) {
            for (final id in decoded) {
              add(id);
            }
          }
        } catch (_) {
          for (final id in trimmed.split(',')) {
            add(id);
          }
        }
      }
    }

    return List<int>.unmodifiable(ids);
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static String? _nameOf(Map<String, dynamic>? category) {
    final name = category?['name']?.toString().trim();
    return name == null || name.isEmpty ? null : name;
  }
}

// ---------------------------------------------------------------------------
// SyncFieldMapper — renames/filters payload keys for the destination's schema.
// ---------------------------------------------------------------------------

class SyncFieldMapper {
  /// Produce the outbound payload from a source map (a model's `toJson()`).
  ///
  /// - `map` is `{ totalsField: backendField }`. A null/empty map is the
  ///   identity transform (send `src` unchanged).
  /// - With a non-empty map, only mapped fields are emitted (renamed), which
  ///   minimizes PII — unless [includeUnmapped] is true, in which case fields
  ///   with no mapping are also emitted under their original names.
  /// - Source keys missing from `src` are skipped (not emitted as null).
  static Map<String, dynamic> apply(
    Map<String, dynamic> src,
    Map<String, String>? map, {
    bool includeUnmapped = false,
  }) {
    if (map == null || map.isEmpty) {
      return Map<String, dynamic>.from(src);
    }

    final result = <String, dynamic>{};
    map.forEach((totalsField, backendField) {
      final target = backendField.trim();
      if (target.isEmpty) return;
      if (src.containsKey(totalsField)) {
        result[target] = src[totalsField];
      }
    });

    if (includeUnmapped) {
      src.forEach((key, value) {
        if (!map.containsKey(key)) {
          result.putIfAbsent(key, () => value);
        }
      });
    }

    return result;
  }

  /// Decode a stored `{totalsField: backendField}` JSON string. Returns an
  /// empty map for null/empty/invalid (= identity transform).
  static Map<String, String> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, String>{};
      decoded.forEach((key, value) {
        if (key is String && value is String && value.trim().isNotEmpty) {
          out[key] = value.trim();
        }
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  static String? encode(Map<String, String> map) =>
      map.isEmpty ? null : jsonEncode(map);
}

// ---------------------------------------------------------------------------
// SyncPathTemplate — resolves `{placeholder}` paths against a payload.
// ---------------------------------------------------------------------------

class SyncTemplateException implements Exception {
  final String message;
  const SyncTemplateException(this.message);
  @override
  String toString() => 'SyncTemplateException: $message';
}

class SyncPathTemplate {
  static final RegExp _placeholder = RegExp(r'\{([a-zA-Z0-9_]+)\}');

  /// Build the request URI from `baseUrl` + `template`, substituting
  /// `{key}` placeholders with percent-encoded values from `src`.
  ///
  /// Throws [SyncTemplateException] if a placeholder has no value in `src`
  /// (so the engine can mark the row dead with a clear error instead of
  /// sending to a malformed URL).
  static Uri resolve(
    String baseUrl,
    String template,
    Map<String, dynamic> src,
  ) {
    final resolvedPath = template.replaceAllMapped(_placeholder, (match) {
      final key = match.group(1)!;
      final value = src[key];
      if (value == null) {
        throw SyncTemplateException(
          'Path placeholder "{$key}" has no value on this record.',
        );
      }
      return Uri.encodeComponent(value.toString());
    });

    final base = baseUrl.trim().endsWith('/')
        ? baseUrl.trim().substring(0, baseUrl.trim().length - 1)
        : baseUrl.trim();

    String path = resolvedPath.trim();
    if (path.isEmpty) {
      return Uri.parse(base);
    }
    if (!path.startsWith('/') &&
        !path.startsWith('http://') &&
        !path.startsWith('https://')) {
      path = '/$path';
    }

    // A template may itself be an absolute URL (rare) — honor it.
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    return Uri.parse('$base$path');
  }
}

// ---------------------------------------------------------------------------
// Retry / state-machine logic (pure, testable).
// ---------------------------------------------------------------------------

enum SyncSendOutcome { success, retry, dead }

/// Classify an HTTP send result into the outbox state machine's outcome.
/// - 2xx → success
/// - 408 / 429 / 5xx / network error / no-status → retry
/// - other 4xx (and unexpected 3xx) → dead (no retry)
SyncSendOutcome classifySyncResponse({
  int? statusCode,
  bool networkError = false,
}) {
  if (networkError) return SyncSendOutcome.retry;
  if (statusCode == null) return SyncSendOutcome.retry;
  if (statusCode >= 200 && statusCode < 300) return SyncSendOutcome.success;
  if (statusCode == 408 || statusCode == 429) return SyncSendOutcome.retry;
  if (statusCode >= 500) return SyncSendOutcome.retry;
  if (statusCode >= 400) return SyncSendOutcome.dead;
  return SyncSendOutcome.dead;
}

/// Exponential backoff: `base * 2^(attempt-1)`, capped. `attempt` is the new
/// (post-increment) attempt count, 1-based for the first retry.
Duration computeSyncBackoff(
  int attempt, {
  Duration base = const Duration(seconds: 30),
  Duration cap = const Duration(hours: 6),
}) {
  final n = attempt < 1 ? 1 : attempt;
  final shift = (n - 1).clamp(0, 30);
  final factor = 1 << shift;
  final ms = base.inMilliseconds * factor;
  final capMs = cap.inMilliseconds;
  return Duration(milliseconds: ms > capMs ? capMs : ms);
}

/// Apply ±20% jitter. `random01` in [0,1): 0.5 → no change, 0 → -20%, ~1 → +20%.
Duration applySyncJitter(Duration delay, double random01) {
  final factor = 1.0 + (random01 * 2 - 1) * 0.2;
  return Duration(milliseconds: (delay.inMilliseconds * factor).round());
}

class SyncOutboxTransition {
  final String status;
  final int attempts;
  const SyncOutboxTransition(this.status, this.attempts);

  @override
  bool operator ==(Object other) =>
      other is SyncOutboxTransition &&
      other.status == status &&
      other.attempts == attempts;

  @override
  int get hashCode => Object.hash(status, attempts);

  @override
  String toString() => 'SyncOutboxTransition($status, attempts=$attempts)';
}

/// Compute the next outbox row state after a send attempt.
SyncOutboxTransition nextOutboxTransition({
  required int currentAttempts,
  required SyncSendOutcome outcome,
  required int maxAttempts,
}) {
  switch (outcome) {
    case SyncSendOutcome.success:
      return SyncOutboxTransition(SyncOutboxStatus.sent, currentAttempts);
    case SyncSendOutcome.dead:
      return SyncOutboxTransition(SyncOutboxStatus.dead, currentAttempts);
    case SyncSendOutcome.retry:
      final next = currentAttempts + 1;
      if (next >= maxAttempts) {
        return SyncOutboxTransition(SyncOutboxStatus.dead, next);
      }
      return SyncOutboxTransition(SyncOutboxStatus.pending, next);
  }
}

/// Whether a rule's time-based schedule is due to fire at [now], given the last
/// time it fired ([SyncRule.lastScheduledAt]).
bool syncScheduleDue(SyncRule rule, DateTime now) {
  switch (rule.scheduleMode) {
    case SyncScheduleMode.off:
      return false;
    case SyncScheduleMode.interval:
      final mins = rule.scheduleIntervalMinutes ?? 15;
      final last = rule.lastScheduledAt;
      return last == null || now.difference(last).inMinutes >= mins;
    case SyncScheduleMode.daily:
      final last = rule.lastScheduledAt;
      for (final hhmm in rule.scheduleTimes) {
        final parts = hhmm.split(':');
        if (parts.length != 2) continue;
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h == null || m == null) continue;
        final slot = DateTime(now.year, now.month, now.day, h, m);
        // Past today's slot and we haven't fired since it.
        if (!now.isBefore(slot) && (last == null || last.isBefore(slot))) {
          return true;
        }
      }
      return false;
  }
}

/// Whether a rule's pending rows should be flushed now, given the drain
/// [reason]. Explicit user actions flush immediately; event-triggered drains
/// only flush rules opted into that event; otherwise the rule's time schedule
/// decides.
bool syncRuleShouldSend(SyncRule rule, String reason, DateTime now) {
  const flushReasons = {'manual', 'backfill', 'rule-on', 'enabled'};
  if (flushReasons.contains(reason)) return true;

  const realtimeReasons = {
    'write',
    'signal',
    'resume',
    'startup',
    'foreground'
  };
  if (rule.triggerOnNewTxn && realtimeReasons.contains(reason)) return true;
  if (rule.triggerOnConnectivity && reason == 'connectivity') return true;

  return syncScheduleDue(rule, now);
}

// ---------------------------------------------------------------------------
// Persistable models
// ---------------------------------------------------------------------------

class SyncDestination {
  final int? id;
  final String name;
  final String baseUrl;
  final SyncAuthType authType;
  final String? authHeaderName;
  final String? authUsername;
  final String? secretRef;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SyncDestination({
    this.id,
    required this.name,
    required this.baseUrl,
    this.authType = SyncAuthType.none,
    this.authHeaderName,
    this.authUsername,
    this.secretRef,
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Secure-storage key holding this destination's secret value.
  static String secretRefFor(int id) => 'data_sync_secret_$id';

  factory SyncDestination.fromDb(Map<String, dynamic> row) {
    final now = DateTime.now();
    return SyncDestination(
      id: row['id'] as int?,
      name: (row['name'] as String?) ?? '',
      baseUrl: (row['baseUrl'] as String?) ?? '',
      authType: SyncAuthTypeX.fromStorage(row['authType'] as String?),
      authHeaderName: row['authHeaderName'] as String?,
      authUsername: row['authUsername'] as String?,
      secretRef: row['secretRef'] as String?,
      enabled: _asBool(row['enabled']) ?? true,
      createdAt: _asDate(row['createdAt']) ?? now,
      updatedAt: _asDate(row['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toDb() => {
        if (id != null) 'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'authType': authType.storage,
        'authHeaderName': authHeaderName,
        'authUsername': authUsername,
        'secretRef': secretRef,
        'enabled': enabled ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  SyncDestination copyWith({
    int? id,
    String? name,
    String? baseUrl,
    SyncAuthType? authType,
    String? authHeaderName,
    String? authUsername,
    String? secretRef,
    bool? enabled,
    DateTime? updatedAt,
  }) {
    return SyncDestination(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      authType: authType ?? this.authType,
      authHeaderName: authHeaderName ?? this.authHeaderName,
      authUsername: authUsername ?? this.authUsername,
      secretRef: secretRef ?? this.secretRef,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class SyncRule {
  final int? id;
  final int destinationId;
  final String name;
  final SyncEntity entity;
  final SyncFilter? filter;
  final String method;
  final String pathTemplate;
  final Map<String, String> fieldMap;
  final bool sendUnmapped;
  final SyncBatchMode batchMode;
  final bool triggerManual;
  final bool triggerPeriodic;
  final bool triggerOnNewTxn;
  final bool triggerOnConnectivity;

  /// Time-based schedule (orthogonal to the event triggers above).
  final SyncScheduleMode scheduleMode;
  final int? scheduleIntervalMinutes;
  final List<String> scheduleTimes; // 'HH:mm' entries for daily mode
  final DateTime? lastScheduledAt;

  final bool enabled;
  final bool backfillDone;
  final String? lastStatus;
  final DateTime? lastRunAt;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SyncRule({
    this.id,
    required this.destinationId,
    required this.name,
    required this.entity,
    this.filter,
    this.method = 'POST',
    required this.pathTemplate,
    this.fieldMap = const {},
    this.sendUnmapped = false,
    this.batchMode = SyncBatchMode.perRecord,
    this.triggerManual = true,
    this.triggerPeriodic = false,
    this.triggerOnNewTxn = false,
    this.triggerOnConnectivity = false,
    this.scheduleMode = SyncScheduleMode.off,
    this.scheduleIntervalMinutes,
    this.scheduleTimes = const [],
    this.lastScheduledAt,
    this.enabled = false,
    this.backfillDone = false,
    this.lastStatus,
    this.lastRunAt,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SyncRule.fromDb(Map<String, dynamic> row) {
    final now = DateTime.now();
    return SyncRule(
      id: row['id'] as int?,
      destinationId: _intCol(row['destinationId']),
      name: (row['name'] as String?) ?? '',
      entity: SyncEntityX.fromStorage(row['entity'] as String?),
      filter: SyncFilter.decode(row['filterJson'] as String?),
      method: SyncHttpMethod.normalize(row['method'] as String?),
      pathTemplate: (row['pathTemplate'] as String?) ?? '/',
      fieldMap: SyncFieldMapper.decode(row['fieldMapJson'] as String?),
      sendUnmapped: _asBool(row['sendUnmapped']) ?? false,
      batchMode: SyncBatchModeX.fromStorage(row['batchMode'] as String?),
      triggerManual: _asBool(row['triggerManual']) ?? true,
      triggerPeriodic: _asBool(row['triggerPeriodic']) ?? false,
      triggerOnNewTxn: _asBool(row['triggerOnNewTxn']) ?? false,
      triggerOnConnectivity: _asBool(row['triggerOnConnectivity']) ?? false,
      scheduleMode:
          SyncScheduleModeX.fromStorage(row['scheduleMode'] as String?),
      scheduleIntervalMinutes: _asNum(row['scheduleIntervalMinutes'])?.toInt(),
      scheduleTimes: _decodeStringList(row['scheduleTimes']),
      lastScheduledAt: _asDate(row['lastScheduledAt']),
      enabled: _asBool(row['enabled']) ?? false,
      backfillDone: _asBool(row['backfillDone']) ?? false,
      lastStatus: row['lastStatus'] as String?,
      lastRunAt: _asDate(row['lastRunAt']),
      lastError: row['lastError'] as String?,
      createdAt: _asDate(row['createdAt']) ?? now,
      updatedAt: _asDate(row['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toDb() => {
        if (id != null) 'id': id,
        'destinationId': destinationId,
        'name': name,
        'entity': entity.storage,
        'filterJson': filter?.encode(),
        'method': SyncHttpMethod.normalize(method),
        'pathTemplate': pathTemplate,
        'fieldMapJson': SyncFieldMapper.encode(fieldMap),
        'sendUnmapped': sendUnmapped ? 1 : 0,
        'batchMode': batchMode.storage,
        'triggerManual': triggerManual ? 1 : 0,
        'triggerPeriodic': triggerPeriodic ? 1 : 0,
        'triggerOnNewTxn': triggerOnNewTxn ? 1 : 0,
        'triggerOnConnectivity': triggerOnConnectivity ? 1 : 0,
        'scheduleMode': scheduleMode.storage,
        'scheduleIntervalMinutes': scheduleIntervalMinutes,
        'scheduleTimes':
            scheduleTimes.isEmpty ? null : jsonEncode(scheduleTimes),
        'lastScheduledAt': lastScheduledAt?.toIso8601String(),
        'enabled': enabled ? 1 : 0,
        'backfillDone': backfillDone ? 1 : 0,
        'lastStatus': lastStatus,
        'lastRunAt': lastRunAt?.toIso8601String(),
        'lastError': lastError,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  SyncRule copyWith({
    int? id,
    int? destinationId,
    String? name,
    SyncEntity? entity,
    SyncFilter? filter,
    bool clearFilter = false,
    String? method,
    String? pathTemplate,
    Map<String, String>? fieldMap,
    bool? sendUnmapped,
    SyncBatchMode? batchMode,
    bool? triggerManual,
    bool? triggerPeriodic,
    bool? triggerOnNewTxn,
    bool? triggerOnConnectivity,
    SyncScheduleMode? scheduleMode,
    int? scheduleIntervalMinutes,
    List<String>? scheduleTimes,
    DateTime? lastScheduledAt,
    bool? enabled,
    bool? backfillDone,
    String? lastStatus,
    DateTime? lastRunAt,
    String? lastError,
    DateTime? updatedAt,
  }) {
    return SyncRule(
      id: id ?? this.id,
      destinationId: destinationId ?? this.destinationId,
      name: name ?? this.name,
      entity: entity ?? this.entity,
      filter: clearFilter ? null : (filter ?? this.filter),
      method: method ?? this.method,
      pathTemplate: pathTemplate ?? this.pathTemplate,
      fieldMap: fieldMap ?? this.fieldMap,
      sendUnmapped: sendUnmapped ?? this.sendUnmapped,
      batchMode: batchMode ?? this.batchMode,
      triggerManual: triggerManual ?? this.triggerManual,
      triggerPeriodic: triggerPeriodic ?? this.triggerPeriodic,
      triggerOnNewTxn: triggerOnNewTxn ?? this.triggerOnNewTxn,
      triggerOnConnectivity:
          triggerOnConnectivity ?? this.triggerOnConnectivity,
      scheduleMode: scheduleMode ?? this.scheduleMode,
      scheduleIntervalMinutes:
          scheduleIntervalMinutes ?? this.scheduleIntervalMinutes,
      scheduleTimes: scheduleTimes ?? this.scheduleTimes,
      lastScheduledAt: lastScheduledAt ?? this.lastScheduledAt,
      enabled: enabled ?? this.enabled,
      backfillDone: backfillDone ?? this.backfillDone,
      lastStatus: lastStatus ?? this.lastStatus,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class SyncOutboxItem {
  final int id;
  final int ruleId;
  final SyncEntity entity;
  final String entityRef;
  final SyncOp op;
  final String? payloadJson;
  final String status;
  final int attempts;
  final DateTime nextAttemptAt;
  final String? lastError;
  final int? lastStatusCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SyncOutboxItem({
    required this.id,
    required this.ruleId,
    required this.entity,
    required this.entityRef,
    required this.op,
    this.payloadJson,
    required this.status,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastError,
    this.lastStatusCode,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SyncOutboxItem.fromDb(Map<String, dynamic> row) {
    final now = DateTime.now();
    return SyncOutboxItem(
      id: _intCol(row['id']),
      ruleId: _intCol(row['ruleId']),
      entity: SyncEntityX.fromStorage(row['entity'] as String?),
      entityRef: (row['entityRef'] as String?) ?? '',
      op: SyncOpX.fromStorage(row['op'] as String?),
      payloadJson: row['payloadJson'] as String?,
      status: (row['status'] as String?) ?? SyncOutboxStatus.pending,
      attempts: _intCol(row['attempts']),
      nextAttemptAt: _asDate(row['nextAttemptAt']) ?? now,
      lastError: row['lastError'] as String?,
      lastStatusCode: _asNum(row['lastStatusCode'])?.toInt(),
      createdAt: _asDate(row['createdAt']) ?? now,
      updatedAt: _asDate(row['updatedAt']) ?? now,
    );
  }
}

/// Build the stable, idempotent `entityRef` for a record of [entity].
/// Returns null if the row lacks the identity columns.
String? syncEntityRef(SyncEntity entity, Map<String, dynamic> row) {
  switch (entity) {
    case SyncEntity.transactions:
      final ref = (row['reference'] as String?)?.trim();
      return (ref == null || ref.isEmpty) ? null : ref;
    case SyncEntity.accounts:
      final account = (row['accountNumber'] as String?)?.trim();
      final bank = _asNum(row['bank'] ?? row['bankId'])?.toInt();
      if (account == null || account.isEmpty || bank == null) return null;
      return '$account|$bank';
    case SyncEntity.budgets:
      final id = _asNum(row['id'])?.toInt();
      return id == null ? null : 'budget:$id';
  }
}
