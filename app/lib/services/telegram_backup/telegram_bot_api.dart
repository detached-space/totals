import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:totals/services/telegram_backup/telegram_backup_models.dart';
import 'package:totals/services/telegram_backup/telegram_restore_diagnostics.dart';

class TelegramBotApiException implements Exception {
  final String message;
  final int? errorCode;

  const TelegramBotApiException(this.message, {this.errorCode});

  @override
  String toString() => message;
}

class TelegramBotApi {
  TelegramBotApi({
    required String token,
    http.Client? client,
  })  : _token = token.trim(),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const int maxDownloadBytes = 20 * 1024 * 1024;

  final String _token;
  final http.Client _client;
  final bool _ownsClient;

  Uri _methodUri(String method) {
    return Uri.https('api.telegram.org', '/bot$_token/$method');
  }

  Uri _fileUri(String path) {
    return Uri.https('api.telegram.org', '/file/bot$_token/$path');
  }

  Future<TelegramBotIdentity> getMe() async {
    final result = await _postMap('getMe');
    if (result['is_bot'] != true) {
      throw const TelegramBotApiException(
        'This token does not belong to a Telegram bot.',
      );
    }
    final username = (result['username'] as String?)?.trim() ?? '';
    if (username.isEmpty) {
      throw const TelegramBotApiException(
        'Telegram did not return a username for this bot.',
      );
    }
    return TelegramBotIdentity(
      id: '${result['id']}',
      username: username,
      displayName: (result['first_name'] as String?)?.trim() ?? username,
    );
  }

  Future<String> getWebhookUrl() async {
    final result = await _postMap('getWebhookInfo');
    return (result['url'] as String?)?.trim() ?? '';
  }

  Future<List<Map<String, dynamic>>> getUpdates({
    int? offset,
    int timeoutSeconds = 10,
  }) async {
    final result = await _post(
      'getUpdates',
      fields: {
        if (offset != null) 'offset': '$offset',
        'timeout': '$timeoutSeconds',
        'allowed_updates': jsonEncode(['message']),
      },
      timeout: Duration(seconds: timeoutSeconds + 15),
    );
    if (result is! List) {
      throw const TelegramBotApiException(
        'Telegram returned an invalid updates response.',
      );
    }
    return result
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> getChat(String chatId) {
    return _postMap('getChat', fields: {'chat_id': chatId});
  }

  Future<void> sendMessage({
    required String chatId,
    required String text,
  }) async {
    await _post(
      'sendMessage',
      fields: {
        'chat_id': chatId,
        'text': text,
        'disable_notification': 'true',
      },
      timeout: const Duration(seconds: 10),
    );
  }

  Future<TelegramRemoteDocument> sendDocument({
    required String chatId,
    required List<int> bytes,
    required String fileName,
    required String caption,
  }) async {
    final result = await _multipartMap(
      'sendDocument',
      fields: {
        'chat_id': chatId,
        'caption': caption,
        'disable_notification': 'true',
      },
      fileField: 'document',
      bytes: bytes,
      fileName: fileName,
    );
    return _documentFromMessage(result);
  }

  Future<TelegramRemoteDocument> replaceDocument({
    required String chatId,
    required int messageId,
    required List<int> bytes,
    required String fileName,
    required String caption,
  }) async {
    final result = await _multipartMap(
      'editMessageMedia',
      fields: {
        'chat_id': chatId,
        'message_id': '$messageId',
        'media': jsonEncode({
          'type': 'document',
          'media': 'attach://catalog',
          'caption': caption,
        }),
      },
      fileField: 'catalog',
      bytes: bytes,
      fileName: fileName,
    );
    return _documentFromMessage(result);
  }

  Future<void> pinMessage({
    required String chatId,
    required int messageId,
  }) async {
    await _post(
      'pinChatMessage',
      fields: {
        'chat_id': chatId,
        'message_id': '$messageId',
        'disable_notification': 'true',
      },
    );
  }

  Future<List<int>> downloadFile(
    String fileId, {
    int maximumBytes = maxDownloadBytes,
  }) async {
    final diag = TelegramRestoreDiagnostics.instance;
    final file = await _postMap('getFile', fields: {'file_id': fileId});
    final filePath = (file['file_path'] as String?)?.trim();
    final declaredSize = (file['file_size'] as num?)?.toInt();
    diag.log('getFile',
        'declaredSize=$declaredSize hasPath=${filePath != null && filePath.isNotEmpty} limit=$maximumBytes');
    if (filePath == null || filePath.isEmpty) {
      throw const TelegramBotApiException(
        'Telegram did not return a download path for this backup.',
      );
    }
    if (declaredSize != null && declaredSize > maximumBytes) {
      diag.log('getFile ABORT',
          'declaredSize $declaredSize > $maximumBytes — over Bot API getFile 20MB cap');
      throw const TelegramBotApiException(
        'This backup is too large for an in-app Telegram restore.',
      );
    }

    try {
      final request = http.Request('GET', _fileUri(filePath));
      final response =
          await _client.send(request).timeout(const Duration(seconds: 45));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        diag.log('download HTTP', response.statusCode);
        throw TelegramBotApiException(
          'Telegram could not download this backup '
          '(HTTP ${response.statusCode}).',
        );
      }
      final builder = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 30))) {
        length += chunk.length;
        if (length > maximumBytes) {
          diag.log('download ABORT', 'stream exceeded $maximumBytes bytes');
          throw const TelegramBotApiException(
            'This backup is too large for an in-app Telegram restore.',
          );
        }
        builder.add(chunk);
      }
      diag.log('download', 'streamed $length bytes');
      return builder.takeBytes();
    } on TelegramBotApiException {
      rethrow;
    } on TimeoutException {
      diag.log('download timeout');
      throw const TelegramBotApiException(
        'Telegram took too long to download the backup.',
      );
    } catch (error, stackTrace) {
      // The generic message below hides the real cause (TLS/socket/etc). Keep
      // the user-facing wrapper but surface the true error into the trace.
      diag.log('download error (unwrapped)', '${error.runtimeType}: $error');
      if (kDebugMode) {
        debugPrint('debug: TGRESTORE download stack\n$stackTrace');
      }
      throw const TelegramBotApiException(
        'Could not download the backup from Telegram.',
      );
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<Map<String, dynamic>> _postMap(
    String method, {
    Map<String, String> fields = const {},
  }) async {
    final result = await _post(method, fields: fields);
    if (result is! Map) {
      throw const TelegramBotApiException(
        'Telegram returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(result);
  }

  Future<dynamic> _post(
    String method, {
    Map<String, String> fields = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final response =
          await _client.post(_methodUri(method), body: fields).timeout(timeout);
      return _decode(response);
    } on TelegramBotApiException {
      rethrow;
    } on TimeoutException {
      throw const TelegramBotApiException(
        'Telegram did not respond in time. Check your connection and retry.',
      );
    } catch (_) {
      throw const TelegramBotApiException(
        'Could not reach Telegram. Check your connection and retry.',
      );
    }
  }

  Future<Map<String, dynamic>> _multipartMap(
    String method, {
    required Map<String, String> fields,
    required String fileField,
    required List<int> bytes,
    required String fileName,
  }) async {
    try {
      final request = http.MultipartRequest('POST', _methodUri(method))
        ..fields.addAll(fields)
        ..files.add(
          http.MultipartFile.fromBytes(
            fileField,
            bytes,
            filename: fileName,
          ),
        );
      final streamed =
          await _client.send(request).timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 30));
      final result = _decode(response);
      if (result is! Map) {
        throw const TelegramBotApiException(
          'Telegram returned an invalid upload response.',
        );
      }
      return Map<String, dynamic>.from(result);
    } on TelegramBotApiException {
      rethrow;
    } on TimeoutException {
      throw const TelegramBotApiException(
        'Telegram took too long to upload the backup.',
      );
    } catch (_) {
      throw const TelegramBotApiException(
        'Could not upload the encrypted file to Telegram.',
      );
    }
  }

  dynamic _decode(http.Response response) {
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload?['ok'] != true) {
      final description = (payload?['description'] as String?)?.trim();
      throw TelegramBotApiException(
        description?.isNotEmpty == true
            ? description!
            : 'Telegram rejected the request (HTTP ${response.statusCode}).',
        errorCode: (payload?['error_code'] as num?)?.toInt(),
      );
    }
    return payload!['result'];
  }

  TelegramRemoteDocument _documentFromMessage(Map<String, dynamic> message) {
    final documentRaw = message['document'];
    if (documentRaw is! Map) {
      throw const TelegramBotApiException(
        'Telegram uploaded the message without a document.',
      );
    }
    final document = Map<String, dynamic>.from(documentRaw);
    final fileId = (document['file_id'] as String?)?.trim() ?? '';
    final messageId = (message['message_id'] as num?)?.toInt() ?? 0;
    if (fileId.isEmpty || messageId <= 0) {
      throw const TelegramBotApiException(
        'Telegram did not return the uploaded document identifier.',
      );
    }
    return TelegramRemoteDocument(
      fileId: fileId,
      fileName: (document['file_name'] as String?) ?? '',
      fileSize: (document['file_size'] as num?)?.toInt() ?? 0,
      messageId: messageId,
    );
  }
}
