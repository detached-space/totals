import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thrown for transport-level failures (timeout, socket errors). These are
/// retryable; HTTP error statuses are returned as an [OutboundResponse].
class OutboundNetworkException implements Exception {
  final String message;
  const OutboundNetworkException(this.message);
  @override
  String toString() => 'OutboundNetworkException: $message';
}

class OutboundResponse {
  final int statusCode;
  final String body;
  final Duration? retryAfter;

  /// True when the request was refused locally (e.g. payload too large) and
  /// never sent. Treated as a terminal (dead) outcome by the engine.
  final bool refusedLocally;

  const OutboundResponse({
    required this.statusCode,
    this.body = '',
    this.retryAfter,
    this.refusedLocally = false,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// A short, non-sensitive snippet of the response body for the log UI.
  String? bodySnippet({int max = 200}) {
    final trimmed = body.replaceAll('\n', ' ').trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= max ? trimmed : '${trimmed.substring(0, max)}…';
  }
}

/// A generic, user-configurable outbound HTTP client. Mirrors the resilience of
/// `TotalsEngineClient` (timeouts, Retry-After parsing, network-error
/// classification) but carries no built-in auth — headers are supplied per
/// request by the caller. Retry/backoff scheduling lives in the engine; this
/// client performs a single attempt and reports the outcome.
class OutboundHttpClient {
  OutboundHttpClient({http.Client? client}) : _client = client ?? http.Client();

  http.Client _client;

  static const Duration _timeout = Duration(seconds: 15);
  static const int maxBodyBytes = 1 * 1024 * 1024; // 1 MB

  Future<OutboundResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Object jsonBody,
  }) async {
    final body = jsonEncode(jsonBody);
    if (body.length > maxBodyBytes) {
      return OutboundResponse(
        statusCode: 413,
        body: 'Payload too large (${body.length} bytes > $maxBodyBytes).',
        refusedLocally: true,
      );
    }

    try {
      final request = http.Request(method, uri)
        ..headers.addAll({'Content-Type': 'application/json', ...headers})
        ..body = body;
      final streamed = await _client.send(request).timeout(_timeout);
      final text = await streamed.stream.bytesToString();
      return OutboundResponse(
        statusCode: streamed.statusCode,
        body: text,
        retryAfter: _retryAfter(streamed.headers),
      );
    } on TimeoutException catch (error) {
      throw OutboundNetworkException('Request timed out: $error');
    } on http.ClientException catch (error) {
      throw OutboundNetworkException(error.message);
    } catch (error) {
      if (_isRetryableNetworkError(error)) {
        throw OutboundNetworkException(error.toString());
      }
      rethrow;
    }
  }

  /// Lightweight reachability probe for the "Test connection" affordance.
  /// Returns the status code, or null if the host is unreachable.
  Future<int?> probe(Uri uri, Map<String, String> headers) async {
    try {
      final response =
          await _client.head(uri, headers: headers).timeout(_timeout);
      return response.statusCode;
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } catch (error) {
      if (kDebugMode) debugPrint('OutboundHttpClient.probe failed: $error');
      return null;
    }
  }

  void cancelInFlight() {
    _client.close();
    _client = http.Client();
  }

  void close() => _client.close();

  // Lifted from TotalsEngineClient._retryAfter.
  static Duration? _retryAfter(Map<String, String> headers) {
    final raw = headers['retry-after'];
    if (raw == null || raw.trim().isEmpty) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds != null && seconds > 0) return Duration(seconds: seconds);
    final date = DateTime.tryParse(raw.trim());
    if (date == null) return null;
    final delay = date.difference(DateTime.now());
    return delay.isNegative ? null : delay;
  }

  // Lifted from TotalsEngineClient._isRetryableNetworkError.
  static bool _isRetryableNetworkError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('connection closed') ||
        message.contains('connection reset') ||
        message.contains('connection refused') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('software caused connection abort') ||
        message.contains('handshake');
  }
}
