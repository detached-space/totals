import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:totals/services/telegram_backup/telegram_backup_service.dart';
import 'package:totals/services/telegram_backup/telegram_bot_api.dart';

void main() {
  test('getMe returns the verified bot identity', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/bot123:secret/getMe');
      return http.Response(
        jsonEncode({
          'ok': true,
          'result': {
            'id': 42,
            'is_bot': true,
            'first_name': 'Totals',
            'username': 'totals_backup_bot',
          },
        }),
        200,
      );
    });
    final api = TelegramBotApi(token: '123:secret', client: client);

    final bot = await api.getMe();

    expect(bot.id, '42');
    expect(bot.username, 'totals_backup_bot');
    expect(bot.displayName, 'Totals');
  });

  test('Telegram errors are surfaced without exposing the request URL', () {
    final client = MockClient((_) async {
      return http.Response(
        jsonEncode({
          'ok': false,
          'error_code': 401,
          'description': 'Unauthorized',
        }),
        401,
      );
    });
    final api = TelegramBotApi(token: '123:very-secret', client: client);

    expect(
      api.getMe,
      throwsA(
        isA<TelegramBotApiException>()
            .having((error) => error.errorCode, 'errorCode', 401)
            .having((error) => error.message, 'message', 'Unauthorized')
            .having(
              (error) => error.toString(),
              'safe string',
              isNot(contains('very-secret')),
            ),
      ),
    );
  });

  test('deep-link pairing accepts only the matching private Start message',
      () async {
    String? expectedStart;
    Map<String, String>? confirmationFields;
    final service = TelegramBackupService(
      apiFactory: (token) => TelegramBotApi(
        token: token,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/getMe')) {
            return http.Response(
              jsonEncode({
                'ok': true,
                'result': {
                  'id': 42,
                  'is_bot': true,
                  'first_name': 'Totals',
                  'username': 'totals_backup_bot',
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/getWebhookInfo')) {
            return http.Response(
              jsonEncode({
                'ok': true,
                'result': {'url': ''},
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/getUpdates')) {
            return http.Response(
              jsonEncode({
                'ok': true,
                'result': [
                  {
                    'update_id': 5,
                    'message': {
                      'text': '/start wrong_nonce',
                      'chat': {'id': -100, 'type': 'group'},
                    },
                  },
                  {
                    'update_id': 6,
                    'message': {
                      'text': expectedStart,
                      'chat': {
                        'id': 987654321,
                        'type': 'private',
                        'first_name': 'Backup',
                        'last_name': 'Owner',
                        'username': 'backup_owner',
                      },
                    },
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/sendMessage')) {
            confirmationFields = request.bodyFields;
            return http.Response(
              jsonEncode({
                'ok': true,
                'result': {'message_id': 7},
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
    );

    final session = await service.beginPairing('123:secret');
    expectedStart = '/start totals_${session.nonce}';
    final chat = await service.waitForPairing(
      session,
      timeout: const Duration(seconds: 2),
    );

    expect(session.deepLink.host, 't.me');
    expect(
        session.deepLink.queryParameters['start'], 'totals_${session.nonce}');
    expect(chat.id, '987654321');
    expect(chat.displayName, 'Backup Owner');
    expect(chat.username, 'backup_owner');
    expect(confirmationFields?['chat_id'], '987654321');
    expect(
      confirmationFields?['text'],
      contains('Return to Totals to finish setting up'),
    );
    expect(confirmationFields?['disable_notification'], 'true');
  });

  test('backup documents are sent silently', () async {
    Map<String, String>? uploadFields;
    final client = _RecordingClient((request) async {
      final upload = request as http.MultipartRequest;
      uploadFields = Map<String, String>.from(upload.fields);
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode({
              'ok': true,
              'result': {
                'message_id': 8,
                'document': {
                  'file_id': 'backup-file-id',
                  'file_name': 'backup.totals',
                  'file_size': 3,
                },
              },
            }),
          ),
        ),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
    final api = TelegramBotApi(token: '123:secret', client: client);

    await api.sendDocument(
      chatId: '987654321',
      bytes: const [1, 2, 3],
      fileName: 'backup.totals',
      caption: 'Encrypted Totals backup',
    );

    expect(uploadFields?['disable_notification'], 'true');
  });
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}
