import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TotalsEngineException implements Exception {
  final String message;
  final int? statusCode;

  const TotalsEngineException(this.message, [this.statusCode]);

  @override
  String toString() => statusCode == null ? message : '$message ($statusCode)';
}

class TotalsEnginePendingPayload {
  final String id;
  final String senderPublicKey;
  final Map<String, dynamic> event;

  const TotalsEnginePendingPayload({
    required this.id,
    required this.senderPublicKey,
    required this.event,
  });
}

class TotalsEngineSyncService {
  TotalsEngineSyncService._();

  static final TotalsEngineSyncService instance = TotalsEngineSyncService._();

  // Paste your ngrok HTTPS URL here before running Flutter, without a trailing slash.
  // Example: 'https://abc123.ngrok-free.app'
  static const hardcodedBaseUrl = 'https://5cf1-196-188-227-55.ngrok-free.app';

  static const _privateKeyPrefsKey = 'totals_engine_device_private_key_v1';
  static const _publicKeyPrefsKey = 'totals_engine_device_public_key_v1';
  static const _baseUrlPrefsKey = 'totals_engine_base_url_v1';

  final _ed25519 = Ed25519();
  final _aesGcm = AesGcm.with256bits();
  final _random = Random.secure();

  SimpleKeyPairData? _keyPair;
  String? _publicKeyHex;

  String get defaultBaseUrl {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:4000';
    }
    return 'http://localhost:4000';
  }

  Future<String> baseUrl() async {
    final hardcoded = hardcodedBaseUrl.trim();
    if (hardcoded.isNotEmpty) return hardcoded;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_baseUrlPrefsKey)?.trim();
    return saved == null || saved.isEmpty ? defaultBaseUrl : saved;
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlPrefsKey, url.trim());
  }

  Future<String> devicePublicKeyHex() async {
    await _ensureDeviceIdentity();
    return _publicKeyHex!;
  }

  Future<String> createGroup() async {
    final response = await _authenticatedJson('POST', '/groups', body: {});
    return response['id'] as String;
  }

  Future<void> joinGroup(String groupId) async {
    await _authenticatedJson('POST', '/groups/$groupId/join', body: {});
  }

  Future<void> submitEvent({
    required String groupId,
    required String groupKeyHex,
    required Map<String, dynamic> event,
  }) async {
    final encryptedBlob = await encryptEvent(
      groupKeyHex: groupKeyHex,
      event: event,
    );
    await _authenticatedJson(
      'POST',
      '/groups/$groupId/payloads',
      body: {'encryptedBlob': encryptedBlob},
    );
  }

  Future<List<TotalsEnginePendingPayload>> pullEvents({
    required String groupId,
    required String groupKeyHex,
  }) async {
    final response =
        await _authenticatedJson('GET', '/groups/$groupId/pending');
    final rawPayloads = response['payloads'] as List<dynamic>? ?? const [];
    final payloads = <TotalsEnginePendingPayload>[];

    for (final raw in rawPayloads) {
      final map = raw as Map<String, dynamic>;
      final event = await decryptEvent(
        groupKeyHex: groupKeyHex,
        encryptedBlob: map['encryptedBlob'] as String,
      );
      payloads.add(
        TotalsEnginePendingPayload(
          id: map['id'] as String,
          senderPublicKey: map['senderPublicKey'] as String,
          event: event,
        ),
      );
    }

    return payloads;
  }

  Future<void> acknowledgePayload(String payloadId) async {
    await _authenticatedJson('POST', '/payloads/$payloadId/ack');
  }

  String generateGroupKeyHex() {
    return _toHex(Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    ));
  }

  Future<String> encryptEvent({
    required String groupKeyHex,
    required Map<String, dynamic> event,
  }) async {
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => _random.nextInt(256)),
    );
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(jsonEncode(event)),
      secretKey: SecretKey(_fromHex(groupKeyHex)),
      nonce: nonce,
    );
    return _toHex(
      Uint8List.fromList([
        ...secretBox.nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]),
    );
  }

  Future<Map<String, dynamic>> decryptEvent({
    required String groupKeyHex,
    required String encryptedBlob,
  }) async {
    final bytes = _fromHex(encryptedBlob);
    if (bytes.length < 29) {
      throw const TotalsEngineException('Encrypted payload is too short');
    }

    final nonce = bytes.sublist(0, 12);
    final mac = bytes.sublist(bytes.length - 16);
    final cipherText = bytes.sublist(12, bytes.length - 16);
    final clear = await _aesGcm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(_fromHex(groupKeyHex)),
    );

    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _authenticatedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${await baseUrl()}$path');
    late final http.Response response;

    if (method == 'GET') {
      response = await http.get(uri, headers: headers);
    } else if (method == 'POST') {
      response = await http.post(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      );
    } else {
      throw TotalsEngineException('Unsupported method $method');
    }

    return _decodeResponse(response);
  }

  Future<Map<String, String>> _authHeaders() async {
    await _ensureDeviceIdentity();
    final base = await baseUrl();
    final challengeResponse =
        await http.post(Uri.parse('$base/auth/challenge'));
    final challengeBody = _decodeResponse(challengeResponse);
    final challengeHex = challengeBody['challenge'] as String;
    final signature = await _ed25519.sign(
      _fromHex(challengeHex),
      keyPair: _keyPair!,
    );

    return {
      'x-device-public-key': _publicKeyHex!,
      'x-challenge': challengeHex,
      'x-signature': _toHex(Uint8List.fromList(signature.bytes)),
      'content-type': 'application/json',
    };
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final message = decoded['message'] as String? ??
        decoded['error'] as String? ??
        'Totals Engine request failed';
    throw TotalsEngineException(message, response.statusCode);
  }

  Future<void> _ensureDeviceIdentity() async {
    if (_keyPair != null && _publicKeyHex != null) return;

    final prefs = await SharedPreferences.getInstance();
    final savedPrivateHex = prefs.getString(_privateKeyPrefsKey);
    final savedPublicHex = prefs.getString(_publicKeyPrefsKey);

    if (savedPrivateHex != null && savedPublicHex != null) {
      _publicKeyHex = savedPublicHex;
      _keyPair = SimpleKeyPairData(
        _fromHex(savedPrivateHex),
        publicKey: SimplePublicKey(
          _fromHex(savedPublicHex),
          type: KeyPairType.ed25519,
        ),
        type: KeyPairType.ed25519,
      );
      return;
    }

    final generated = await _ed25519.newKeyPair();
    final privateBytes = await generated.extractPrivateKeyBytes();
    final publicKey = await generated.extractPublicKey();
    _keyPair = SimpleKeyPairData(
      privateBytes,
      publicKey: publicKey,
      type: KeyPairType.ed25519,
    );
    _publicKeyHex = _toHex(Uint8List.fromList(publicKey.bytes));

    await prefs.setString(
      _privateKeyPrefsKey,
      _toHex(Uint8List.fromList(privateBytes)),
    );
    await prefs.setString(_publicKeyPrefsKey, _publicKeyHex!);
  }

  static Uint8List _fromHex(String hex) {
    final clean = hex.trim().toLowerCase();
    if (clean.length.isOdd) {
      throw const TotalsEngineException('Invalid hex string length');
    }

    final bytes = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < clean.length; i += 2) {
      bytes[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }

  static String _toHex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
