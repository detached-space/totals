import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/services/shared_expense_crypto_service.dart';

void _engineLog(String message) {
  if (kDebugMode) {
    debugPrint('debug: TotalsEngineClient: $message');
  }
}

String _logId(String value) {
  if (value.length <= 12) return value;
  return '${value.substring(0, 8)}...${value.substring(value.length - 4)}';
}

String _logBody(String body) {
  final sanitized = body.replaceAll('\n', ' ').trim();
  if (sanitized.length <= 240) return sanitized;
  return '${sanitized.substring(0, 240)}...';
}

class TotalsEngineException implements Exception {
  final String message;
  final int? statusCode;
  final Duration? retryAfter;
  /// Decoded body for non-2xx responses where the caller needs structured
  /// fields (e.g. a 429 with a `lockedUntil` timestamp).
  final Map<String, dynamic>? body;

  const TotalsEngineException(
    this.message, {
    this.statusCode,
    this.retryAfter,
    this.body,
  });

  @override
  String toString() {
    if (statusCode == null) return message;
    return '$message ($statusCode)';
  }
}

class EngineGroup {
  final String id;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final List<SharedExpenseMember> members;

  const EngineGroup({
    required this.id,
    required this.createdAt,
    required this.expiresAt,
    required this.members,
  });

  factory EngineGroup.fromJson(Map<String, dynamic> json) {
    return EngineGroup(
      id: json['id'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      members: ((json['members'] as List?) ?? const [])
          .whereType<Map>()
          .map((member) => SharedExpenseMember.fromJson(
                Map<String, dynamic>.from(member),
              ))
          .where((member) => member.devicePublicKey.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class EngineCreateGroupResponse {
  final String id;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const EngineCreateGroupResponse({
    required this.id,
    required this.createdAt,
    required this.expiresAt,
  });

  factory EngineCreateGroupResponse.fromJson(Map<String, dynamic> json) {
    return EngineCreateGroupResponse(
      id: json['id'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    );
  }
}

class EnginePendingPayload {
  final String id;
  final String groupId;
  final String senderPublicKey;
  final String encryptedBlob;
  final String kind;
  final DateTime createdAt;

  const EnginePendingPayload({
    required this.id,
    required this.groupId,
    required this.senderPublicKey,
    required this.encryptedBlob,
    this.kind = 'group',
    required this.createdAt,
  });

  factory EnginePendingPayload.fromJson(Map<String, dynamic> json) {
    return EnginePendingPayload(
      id: json['id'] as String? ?? '',
      groupId: json['groupId'] as String? ?? '',
      senderPublicKey: json['senderPublicKey'] as String? ?? '',
      encryptedBlob: json['encryptedBlob'] as String? ?? '',
      kind: json['kind'] as String? ?? 'group',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class _EngineResponse {
  final int statusCode;
  final String bodyText;
  final Map<String, dynamic> decoded;
  final Map<String, String> headers;

  const _EngineResponse({
    required this.statusCode,
    required this.bodyText,
    required this.decoded,
    required this.headers,
  });
}

class _AuthHeaderSet {
  final Map<String, String> headers;
  final bool usedSession;

  const _AuthHeaderSet({
    required this.headers,
    required this.usedSession,
  });
}

class _SseEvent {
  final String event;
  final String data;

  const _SseEvent({
    required this.event,
    required this.data,
  });
}

class TotalsEngineClient {
  static const _defaultBaseUrl = 'https://engine-staging.totals.detached.space';
  static const _requestTimeout = Duration(seconds: 12);
  // SSE connect headroom — much longer than a regular request because some
  // proxies/engines flush response headers lazily. Once headers arrive, the
  // body stream is unconstrained.
  static const _streamConnectTimeout = Duration(minutes: 5);
  static const _retryDelays = [
    Duration(milliseconds: 450),
    Duration(milliseconds: 1200),
  ];

  final SharedExpenseCryptoService _cryptoService;
  final http.Client _client;
  final String baseUrl;
  String? _sessionToken;
  DateTime? _sessionExpiresAt;
  Future<void>? _sessionRefreshFuture;

  TotalsEngineClient({
    SharedExpenseCryptoService? cryptoService,
    http.Client? client,
    String? baseUrl,
  })  : _cryptoService = cryptoService ?? SharedExpenseCryptoService(),
        _client = client ?? http.Client(),
        baseUrl = _normalizeBaseUrl(baseUrl ?? _configuredBaseUrl()) {
    _engineLog('initialized baseUrl=${this.baseUrl}');
  }

  Future<List<EngineGroup>> listGroups() async {
    final response = await _authenticatedRequest('GET', '/groups');
    final groups = (response['groups'] as List?) ?? const [];
    final parsed = groups
        .whereType<Map>()
        .map((group) => EngineGroup.fromJson(Map<String, dynamic>.from(group)))
        .where((group) => group.id.isNotEmpty)
        .toList(growable: false);
    _engineLog('listGroups parsed ${parsed.length} groups');
    return parsed;
  }

  Future<EngineCreateGroupResponse> createGroup() async {
    _engineLog('createGroup request');
    final response = await _authenticatedRequest('POST', '/groups', body: {});
    final result = EngineCreateGroupResponse.fromJson(response);
    if (result.id.isEmpty) {
      throw const TotalsEngineException('Engine returned an empty group ID.');
    }
    _engineLog('createGroup response group=${_logId(result.id)}');
    return result;
  }

  Future<void> joinGroup(String groupId) async {
    _engineLog('joinGroup group=${_logId(groupId)}');
    await _authenticatedRequest('POST', '/groups/$groupId/join', body: {});
  }

  Future<void> updatePushRegistration({
    required String? pushToken,
    required String? pushPlatform,
  }) async {
    _engineLog(
      'updatePushRegistration platform=${pushPlatform ?? '-'} token=${pushToken == null ? 'clear' : 'set'}',
    );
    await _authenticatedRequest(
      'PUT',
      '/groups/push-registration',
      body: {
        'pushToken': pushToken,
        'pushPlatform': pushPlatform,
      },
    );
  }

  Future<void> leaveGroup(String groupId) async {
    _engineLog('leaveGroup group=${_logId(groupId)}');
    await _authenticatedRequest('DELETE', '/groups/$groupId/members/me');
  }

  // ---------------------------------------------------------------------------
  // Identity vault — encrypted recovery blob keyed by a recovery code. PUT is
  // authenticated (the current device is who decides to back itself up). Fetch
  // and failure reporting are unauthenticated by design: at restore time the
  // user has no device keypair to sign with — that's the whole reason they're
  // restoring.

  Future<void> putIdentityVault({
    required String recoveryCode,
    required Map<String, dynamic> sealedVault,
  }) async {
    _engineLog('putIdentityVault code=${_logId(recoveryCode)}');
    await _authenticatedRequest(
      'PUT',
      '/identity/vault',
      body: {
        'recoveryCode': recoveryCode,
        ...sealedVault,
      },
    );
  }

  /// Returns the sealed vault map on success, null when no vault exists for
  /// the supplied recovery code (404). Throws [TotalsEngineException] with
  /// `statusCode == 429` when the vault is currently locked — caller should
  /// extract `lockedUntil` from the body.
  ///
  /// Body fields on a 200: `{ salt, kdfParams, encryptedBlob, version }`.
  /// Body fields on a 429: `{ error: "locked", lockedUntil: <ISO8601> }`.
  Future<Map<String, dynamic>?> fetchIdentityVault(String recoveryCode) async {
    _engineLog('fetchIdentityVault code=${_logId(recoveryCode)}');
    final response = await _sendAuthenticatedRequest(
      'POST',
      _uri('/identity/vault/fetch'),
      const {'Content-Type': 'application/json'},
      {'recoveryCode': recoveryCode},
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode == 429) {
      throw TotalsEngineException(
        'Vault temporarily locked.',
        statusCode: 429,
        retryAfter: _retryAfter(response.headers),
        body: response.decoded,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TotalsEngineException(
        _errorMessage(response.decoded) ?? 'Vault fetch failed.',
        statusCode: response.statusCode,
        retryAfter: _retryAfter(response.headers),
      );
    }
    return response.decoded;
  }

  /// Tell the backend the user just attempted a PIN unlock and the MAC
  /// failed (wrong PIN). Backend advances the per-vault failure counter and
  /// locks the row after N consecutive failures. Best-effort: a failure here
  /// is logged but not surfaced.
  Future<void> reportIdentityVaultFailure(String recoveryCode) async {
    _engineLog('reportIdentityVaultFailure code=${_logId(recoveryCode)}');
    try {
      await _sendAuthenticatedRequest(
        'POST',
        _uri('/identity/vault/report-failure'),
        const {'Content-Type': 'application/json'},
        {'recoveryCode': recoveryCode},
      );
    } catch (error) {
      _engineLog('reportIdentityVaultFailure swallowed error=$error');
    }
  }

  Future<List<SharedExpenseMember>> listMembers(String groupId) async {
    final response =
        await _authenticatedRequest('GET', '/groups/$groupId/members');
    final members = (response['members'] as List?) ?? const [];
    final parsed = members
        .whereType<Map>()
        .map((member) => SharedExpenseMember.fromJson(
              Map<String, dynamic>.from(member),
            ))
        .where((member) => member.devicePublicKey.isNotEmpty)
        .toList(growable: false);
    _engineLog(
      'listMembers group=${_logId(groupId)} members=${parsed.length}',
    );
    return parsed;
  }

  // The client no longer sends `encryptedNotificationPreview` — notification
  // text is composed locally by the recipient after pulling and decrypting the
  // payload (doorbell model). Do NOT reintroduce the field without revisiting
  // shared_expense_push_notification_service.dart.

  Future<void> submitPayload({
    required String groupId,
    required String encryptedBlob,
    String kind = 'group',
  }) async {
    _engineLog(
      'submitPayload group=${_logId(groupId)} kind=$kind encryptedBytes=${encryptedBlob.length ~/ 2}',
    );
    await _authenticatedRequest(
      'POST',
      '/groups/$groupId/payloads',
      body: {
        'encryptedBlob': encryptedBlob,
        'kind': kind,
      },
    );
  }

  Future<void> submitTargetedPayload({
    required String groupId,
    required String encryptedBlob,
    required List<String> recipientPublicKeys,
    String kind = 'group',
  }) async {
    _engineLog(
      'submitTargetedPayload group=${_logId(groupId)} kind=$kind recipients=${recipientPublicKeys.length} encryptedBytes=${encryptedBlob.length ~/ 2}',
    );
    await _authenticatedRequest(
      'POST',
      '/groups/$groupId/payloads/targeted',
      body: {
        'encryptedBlob': encryptedBlob,
        'recipientPublicKeys': recipientPublicKeys,
        'kind': kind,
      },
    );
  }

  Future<void> submitNudge({
    required String groupId,
    required String encryptedBlob,
    required List<String> recipientPublicKeys,
  }) async {
    _engineLog(
      'submitNudge group=${_logId(groupId)} recipients=${recipientPublicKeys.length} encryptedBytes=${encryptedBlob.length ~/ 2}',
    );
    await _authenticatedRequest(
      'POST',
      '/groups/$groupId/nudges',
      body: {
        'encryptedBlob': encryptedBlob,
        'recipientPublicKeys': recipientPublicKeys,
        'kind': 'nudge',
      },
    );
  }

  Future<List<EnginePendingPayload>> pullPending(String groupId) async {
    final response =
        await _authenticatedRequest('GET', '/groups/$groupId/pending');
    final payloads = (response['payloads'] as List?) ?? const [];
    final parsed = payloads
        .whereType<Map>()
        .map((payload) => EnginePendingPayload.fromJson(
              Map<String, dynamic>.from(payload),
            ))
        .where((payload) => payload.id.isNotEmpty)
        .toList(growable: false);
    _engineLog(
      'pullPending group=${_logId(groupId)} payloads=${parsed.length}',
    );
    return parsed;
  }

  Stream<EnginePendingPayload> streamPending(String groupId) async* {
    final uri = _uri('/groups/$groupId/pending/stream');
    _engineLog('streamPending group=${_logId(groupId)} -> $uri');

    final response = await _sendAuthenticatedStream(
      '/groups/$groupId/pending/stream',
      label: 'streamPending',
    );
    _engineLog(
      'streamPending group=${_logId(groupId)} <- ${response.statusCode}',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bodyText = await response.stream.bytesToString();
      final decoded = _decodeBody(bodyText);
      _engineLog('streamPending errorBody=${_logBody(bodyText)}');
      throw TotalsEngineException(
        _errorMessage(decoded) ?? 'Totals Engine stream failed.',
        statusCode: response.statusCode,
        retryAfter: _retryAfter(response.headers),
      );
    }

    await for (final event in _decodeSseEvents(response.stream)) {
      if (event.event == 'payload') {
        final decoded = jsonDecode(event.data);
        if (decoded is! Map) continue;
        final payload = EnginePendingPayload.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (payload.id.isNotEmpty) yield payload;
      } else if (event.event == 'error') {
        throw TotalsEngineException(
          event.data.isEmpty ? 'Totals Engine stream failed.' : event.data,
        );
      }
    }
  }

  Stream<EnginePendingPayload> streamAllPending() async* {
    final uri = _uri('/groups/pending/stream');
    _engineLog('streamAllPending -> $uri');

    final response = await _sendAuthenticatedStream(
      '/groups/pending/stream',
      label: 'streamAllPending',
    );
    _engineLog('streamAllPending <- ${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bodyText = await response.stream.bytesToString();
      final decoded = _decodeBody(bodyText);
      _engineLog('streamAllPending errorBody=${_logBody(bodyText)}');
      throw TotalsEngineException(
        _errorMessage(decoded) ?? 'Totals Engine stream failed.',
        statusCode: response.statusCode,
        retryAfter: _retryAfter(response.headers),
      );
    }

    await for (final event in _decodeSseEvents(response.stream)) {
      if (event.event == 'payload') {
        final decoded = jsonDecode(event.data);
        if (decoded is! Map) continue;
        final payload = EnginePendingPayload.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (payload.id.isNotEmpty) yield payload;
      } else if (event.event == 'error') {
        throw TotalsEngineException(
          event.data.isEmpty ? 'Totals Engine stream failed.' : event.data,
        );
      }
    }
  }

  Stream<void> streamGroupListChanges() async* {
    final uri = _uri('/groups/stream');
    _engineLog('streamGroupListChanges -> $uri');

    final response = await _sendAuthenticatedStream(
      '/groups/stream',
      label: 'streamGroupListChanges',
    );
    _engineLog('streamGroupListChanges <- ${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bodyText = await response.stream.bytesToString();
      final decoded = _decodeBody(bodyText);
      _engineLog('streamGroupListChanges errorBody=${_logBody(bodyText)}');
      throw TotalsEngineException(
        _errorMessage(decoded) ?? 'Totals Engine group stream failed.',
        statusCode: response.statusCode,
        retryAfter: _retryAfter(response.headers),
      );
    }

    await for (final event in _decodeSseEvents(response.stream)) {
      if (event.event == 'groups_changed') {
        yield null;
      } else if (event.event == 'error') {
        throw TotalsEngineException(
          event.data.isEmpty
              ? 'Totals Engine group stream failed.'
              : event.data,
        );
      }
    }
  }

  Future<void> acknowledgePayload(String payloadId) async {
    _engineLog('acknowledgePayload payload=${_logId(payloadId)}');
    await _authenticatedRequest('POST', '/payloads/$payloadId/ack');
  }

  Future<void> acknowledgePayloads(List<String> payloadIds) async {
    final ids = payloadIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;
    if (ids.length == 1) {
      await acknowledgePayload(ids.single);
      return;
    }
    _engineLog('acknowledgePayloads count=${ids.length}');
    await _authenticatedRequest(
      'POST',
      '/payloads/ack',
      body: {'payloadIds': ids},
    );
  }

  Future<bool> isReachable() async {
    try {
      final response = await _retryTransient(
        label: 'health',
        request: () => _client.get(_uri('/health')).timeout(_requestTimeout),
        shouldRetryResult: (response) {
          final shouldRetry = _isRetryableStatus(response.statusCode);
          if (shouldRetry) {
            _engineLog(
              'health retryable status=${response.statusCode} '
              'body=${_logBody(response.body)}',
            );
          }
          return shouldRetry;
        },
      );
      final reachable = response.statusCode >= 200 && response.statusCode < 300;
      _engineLog(
          'isReachable status=${response.statusCode} reachable=$reachable');
      return reachable;
    } catch (error, stackTrace) {
      _engineLog('isReachable failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<Map<String, dynamic>> _authenticatedRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = _uri(path);
    for (var authAttempt = 0; authAttempt < 2; authAttempt++) {
      final _AuthHeaderSet auth;
      final _EngineResponse response;
      try {
        auth = await _authHeaders(forceChallenge: authAttempt > 0);
        _engineLog(
          '$method $path -> $uri bodyKeys=${body?.keys.join(',') ?? '-'}',
        );
        response = method == 'GET'
            ? await _retryTransient(
                label: '$method $path',
                request: () =>
                    _sendAuthenticatedRequest(method, uri, auth.headers, body),
                shouldRetryResult: (response) {
                  final shouldRetry = _isRetryableStatus(response.statusCode);
                  if (shouldRetry) {
                    _engineLog(
                      '$method $path retryable status=${response.statusCode} '
                      'body=${_logBody(response.bodyText)}',
                    );
                  }
                  return shouldRetry;
                },
              )
            : await _sendAuthenticatedRequest(method, uri, auth.headers, body);
      } on TimeoutException catch (error) {
        throw TotalsEngineException(
          'Totals Engine took too long to respond. Check your connection and try again.',
          body: {'cause': error.toString()},
        );
      } on http.ClientException catch (error) {
        throw TotalsEngineException(
          'Can\'t reach Totals Engine. Check your internet and try again.',
          body: {'cause': error.message},
        );
      }

      _captureSessionHeaders(response.headers);
      if (response.statusCode == 401 && auth.usedSession && authAttempt == 0) {
        _clearSession();
        continue;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _engineLog('$method $path errorBody=${_logBody(response.bodyText)}');
        throw TotalsEngineException(
          _errorMessage(response.decoded) ?? 'Totals Engine request failed.',
          statusCode: response.statusCode,
          retryAfter: _retryAfter(response.headers),
          body: response.decoded,
        );
      }
      return response.decoded;
    }

    throw const TotalsEngineException('Totals Engine authentication failed.');
  }

  Future<_AuthHeaderSet> _authHeaders({bool forceChallenge = false}) async {
    final identity = await _cryptoService.getOrCreateIdentity();
    final token = _sessionToken;
    final expiresAt = _sessionExpiresAt;
    final now = DateTime.now();
    if (!forceChallenge &&
        token != null &&
        expiresAt != null &&
        expiresAt.isAfter(now.add(const Duration(seconds: 15)))) {
      return _AuthHeaderSet(
        usedSession: true,
        headers: {
          'X-Device-Public-Key': identity.publicKeyHex,
          'X-Device-Session': token,
          'Content-Type': 'application/json',
        },
      );
    }
    if (!forceChallenge) {
      try {
        await _ensureSession(identity.publicKeyHex);
        final refreshedToken = _sessionToken;
        final refreshedExpiresAt = _sessionExpiresAt;
        if (refreshedToken != null &&
            refreshedExpiresAt != null &&
            refreshedExpiresAt
                .isAfter(DateTime.now().add(const Duration(seconds: 15)))) {
          return _AuthHeaderSet(
            usedSession: true,
            headers: {
              'X-Device-Public-Key': identity.publicKeyHex,
              'X-Device-Session': refreshedToken,
              'Content-Type': 'application/json',
            },
          );
        }
      } on TotalsEngineException catch (error) {
        if (error.statusCode != 404) rethrow;
        _engineLog('session endpoint unavailable; falling back to challenge');
      }
    }

    _engineLog('requesting challenge key=${_logId(identity.publicKeyHex)}');
    final challengeResponse = await _retryTransient(
      label: 'challenge',
      request: () => _client.post(
        _uri('/auth/challenge'),
        headers: {'X-Device-Public-Key': identity.publicKeyHex},
      ).timeout(
        _requestTimeout,
      ),
      shouldRetryResult: (response) {
        final shouldRetry = _isRetryableStatus(response.statusCode);
        if (shouldRetry) {
          _engineLog(
            'challenge retryable status=${response.statusCode} '
            'body=${_logBody(response.body)}',
          );
        }
        return shouldRetry;
      },
    );
    final decoded = _decodeBody(challengeResponse.body);
    _engineLog(
      'challenge <- ${challengeResponse.statusCode} bytes=${challengeResponse.body.length}',
    );
    if (challengeResponse.statusCode < 200 ||
        challengeResponse.statusCode >= 300) {
      _engineLog('challenge errorBody=${_logBody(challengeResponse.body)}');
      throw TotalsEngineException(
        _errorMessage(decoded) ?? 'Could not request engine challenge.',
        statusCode: challengeResponse.statusCode,
      );
    }

    final challenge = decoded['challenge'] as String?;
    if (challenge == null || challenge.isEmpty) {
      throw const TotalsEngineException('Engine returned an empty challenge.');
    }

    final signature = await _cryptoService.signHexChallenge(challenge);
    _engineLog(
      'challenge signed key=${_logId(identity.publicKeyHex)} '
      'challengeBytes=${challenge.length ~/ 2}',
    );
    return _AuthHeaderSet(
      usedSession: false,
      headers: {
        'X-Device-Public-Key': identity.publicKeyHex,
        'X-Challenge': challenge,
        'X-Signature': signature,
        'Content-Type': 'application/json',
      },
    );
  }

  Future<_EngineResponse> _sendAuthenticatedRequest(
    String method,
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic>? body,
  ) async {
    try {
      final response = await _client
          .send(
            http.Request(method, uri)
              ..headers.addAll(headers)
              ..body = body == null ? '' : jsonEncode(body),
          )
          .timeout(_requestTimeout);
      final bodyText = await response.stream.bytesToString();
      final decoded = _decodeBody(bodyText);
      _engineLog(
        '$method ${uri.path} <- ${response.statusCode} bytes=${bodyText.length}',
      );
      return _EngineResponse(
        statusCode: response.statusCode,
        bodyText: bodyText,
        decoded: decoded,
        headers: response.headers,
      );
    } catch (error, stackTrace) {
      _engineLog('$method ${uri.path} network failed: $error');
      if (kDebugMode && !_isRetryableNetworkError(error)) {
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  Future<http.StreamedResponse> _sendAuthenticatedStream(
    String path, {
    required String label,
  }) async {
    final uri = _uri(path);
    for (var authAttempt = 0; authAttempt < 2; authAttempt++) {
      final auth = await _authHeaders(forceChallenge: authAttempt > 0);
      final request = http.Request('GET', uri)..headers.addAll(auth.headers);
      // Only time-out the initial response headers. The body stream is
      // long-lived SSE — applying _requestTimeout to the whole
      // `_client.send(request)` future kills every stream at exactly 12s,
      // because that future doesn't complete until the response is fully
      // received in older http client builds (or because some engines flush
      // headers lazily). Use a generous header-only deadline instead.
      final response =
          await _client.send(request).timeout(_streamConnectTimeout);
      _captureSessionHeaders(response.headers);
      if (response.statusCode == 401 && auth.usedSession && authAttempt == 0) {
        _clearSession();
        await response.stream.drain<void>();
        continue;
      }
      return response;
    }
    throw TotalsEngineException('$label authentication failed.');
  }

  void _captureSessionHeaders(Map<String, String> headers) {
    final token = headers['x-device-session'];
    final expiresAtRaw = headers['x-device-session-expires-at'];
    if (token == null || token.isEmpty || expiresAtRaw == null) return;
    final expiresAt = DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null) return;
    _sessionToken = token;
    _sessionExpiresAt = expiresAt;
  }

  void _clearSession() {
    _sessionToken = null;
    _sessionExpiresAt = null;
  }

  Future<void> _ensureSession(String publicKeyHex) async {
    final existing = _sessionRefreshFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final refresh = _refreshSession(publicKeyHex);
    _sessionRefreshFuture = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_sessionRefreshFuture, refresh)) {
        _sessionRefreshFuture = null;
      }
    }
  }

  Future<void> _refreshSession(String publicKeyHex) async {
    _clearSession();
    _engineLog('requesting session key=${_logId(publicKeyHex)}');
    final challengeResponse = await _retryTransient(
      label: 'session challenge',
      request: () => _client.post(
        _uri('/auth/challenge'),
        headers: {'X-Device-Public-Key': publicKeyHex},
      ).timeout(_requestTimeout),
      shouldRetryResult: (response) {
        final shouldRetry = _isRetryableStatus(response.statusCode);
        if (shouldRetry) {
          _engineLog(
            'session challenge retryable status=${response.statusCode} '
            'body=${_logBody(response.body)}',
          );
        }
        return shouldRetry;
      },
    );
    final challengeDecoded = _decodeBody(challengeResponse.body);
    if (challengeResponse.statusCode < 200 ||
        challengeResponse.statusCode >= 300) {
      throw TotalsEngineException(
        _errorMessage(challengeDecoded) ??
            'Could not request engine challenge.',
        statusCode: challengeResponse.statusCode,
        retryAfter: _retryAfter(challengeResponse.headers),
      );
    }

    final challenge = challengeDecoded['challenge'] as String?;
    if (challenge == null || challenge.isEmpty) {
      throw const TotalsEngineException('Engine returned an empty challenge.');
    }
    final signature = await _cryptoService.signHexChallenge(challenge);
    final sessionResponse = await _client
        .post(
          _uri('/auth/session'),
          headers: {
            'X-Device-Public-Key': publicKeyHex,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'challenge': challenge,
            'signature': signature,
          }),
        )
        .timeout(_requestTimeout);
    final sessionDecoded = _decodeBody(sessionResponse.body);
    if (sessionResponse.statusCode < 200 || sessionResponse.statusCode >= 300) {
      throw TotalsEngineException(
        _errorMessage(sessionDecoded) ?? 'Could not create engine session.',
        statusCode: sessionResponse.statusCode,
        retryAfter: _retryAfter(sessionResponse.headers),
      );
    }

    final token = sessionDecoded['token'] as String?;
    final expiresAt = DateTime.tryParse(
      sessionDecoded['expiresAt'] as String? ?? '',
    );
    if (token == null || token.isEmpty || expiresAt == null) {
      throw const TotalsEngineException('Engine returned an invalid session.');
    }
    _sessionToken = token;
    _sessionExpiresAt = expiresAt;
  }

  Future<T> _retryTransient<T>({
    required String label,
    required Future<T> Function() request,
    bool Function(T result)? shouldRetryResult,
  }) async {
    for (var attempt = 0; attempt <= _retryDelays.length; attempt++) {
      try {
        final result = await request();
        final shouldRetry = shouldRetryResult?.call(result) ?? false;
        if (!shouldRetry || attempt == _retryDelays.length) return result;

        await _waitBeforeRetry(label, attempt);
      } catch (error) {
        if (attempt == _retryDelays.length ||
            !_isRetryableNetworkError(error)) {
          rethrow;
        }
        _engineLog('$label transient network failure: $error');
        await _waitBeforeRetry(label, attempt);
      }
    }

    throw StateError('Retry loop exited unexpectedly.');
  }

  Future<void> _waitBeforeRetry(String label, int attempt) async {
    final delay = _retryDelays[attempt];
    _engineLog(
      '$label retrying in ${delay.inMilliseconds}ms '
      '(attempt ${attempt + 2}/${_retryDelays.length + 1})',
    );
    await Future.delayed(delay);
  }

  bool _isRetryableNetworkError(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }

    final message = error.toString().toLowerCase();
    return message.contains('connection closed') ||
        message.contains('connection reset') ||
        message.contains('connection refused') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('software caused connection abort') ||
        message.contains('handshake');
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;
  }

  Duration? _retryAfter(Map<String, String> headers) {
    final raw = headers['retry-after'];
    if (raw == null || raw.trim().isEmpty) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds != null && seconds > 0) return Duration(seconds: seconds);
    final date = DateTime.tryParse(raw.trim());
    if (date == null) return null;
    final delay = date.difference(DateTime.now());
    return delay.isNegative ? null : delay;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, dynamic> _decodeBody(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      _engineLog('ignored non-map response body=${_logBody(body)}');
      return <String, dynamic>{};
    } catch (error) {
      _engineLog(
          'failed to decode response body: $error body=${_logBody(body)}');
      return <String, dynamic>{};
    }
  }

  Stream<_SseEvent> _decodeSseEvents(Stream<List<int>> byteStream) async* {
    var eventName = 'message';
    final dataLines = <String>[];

    _SseEvent? flush() {
      if (dataLines.isEmpty) {
        eventName = 'message';
        return null;
      }
      final event = _SseEvent(
        event: eventName,
        data: dataLines.join('\n'),
      );
      eventName = 'message';
      dataLines.clear();
      return event;
    }

    await for (final line
        in byteStream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        final event = flush();
        if (event != null) yield event;
        continue;
      }
      if (line.startsWith(':')) continue;

      final separator = line.indexOf(':');
      final field = separator == -1 ? line : line.substring(0, separator);
      var value = separator == -1 ? '' : line.substring(separator + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      switch (field) {
        case 'event':
          eventName = value.isEmpty ? 'message' : value;
          break;
        case 'data':
          dataLines.add(value);
          break;
      }
    }

    final event = flush();
    if (event != null) yield event;
  }

  String? _errorMessage(Map<String, dynamic> body) {
    final message = body['message'] ?? body['error'];
    return message is String && message.isNotEmpty ? message : null;
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String _configuredBaseUrl() {
    const fromDefine = String.fromEnvironment('SHARED_EXPENSES_URL');
    if (fromDefine.isNotEmpty) {
      _engineLog('baseUrl from dart-define');
      return fromDefine;
    }
    if (dotenv.isInitialized) {
      final fromEnv = dotenv.maybeGet('SHARED_EXPENSES_URL');
      if (fromEnv != null && fromEnv.isNotEmpty) {
        _engineLog('baseUrl from .env');
        return fromEnv;
      }
    }
    _engineLog('baseUrl using default staging URL');
    return _defaultBaseUrl;
  }
}
