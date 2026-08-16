import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class TelegramBackupCryptoException implements Exception {
  final String message;

  const TelegramBackupCryptoException(this.message);

  @override
  String toString() => message;
}

class TelegramBackupCrypto {
  TelegramBackupCrypto({
    Random? random,
    AesGcm? aesGcm,
    HashAlgorithm? hashAlgorithm,
  })  : _random = random ?? Random.secure(),
        _aesGcm = aesGcm ?? AesGcm.with256bits(),
        _hashAlgorithm = hashAlgorithm ?? Sha256();

  static const int _version = 1;
  static const int _nonceLength = 12;
  static const int _keyLength = 32;
  static const String backupContentType = 'backup';
  static const String catalogContentType = 'catalog';

  final Random _random;
  final AesGcm _aesGcm;
  final HashAlgorithm _hashAlgorithm;

  String generateRecoveryKey() {
    return _toHex(_randomBytes(_keyLength)).toUpperCase();
  }

  String formatRecoveryKey(String recoveryKey) {
    final normalized = normalizeRecoveryKey(recoveryKey);
    return List.generate(
      normalized.length ~/ 4,
      (index) => normalized.substring(index * 4, (index + 1) * 4),
    ).join('-');
  }

  static bool isRecoveryKeyFormatValid(String recoveryKey) {
    final normalized = _canonicalizeRecoveryKey(recoveryKey);
    return normalized.length == _keyLength * 2 &&
        normalized.codeUnits.every(
          (code) => (code >= 48 && code <= 57) || (code >= 65 && code <= 70),
        );
  }

  String normalizeRecoveryKey(String recoveryKey) {
    final normalized = _canonicalizeRecoveryKey(recoveryKey);
    if (!isRecoveryKeyFormatValid(normalized)) {
      throw const TelegramBackupCryptoException(
        'Enter the 64-character Totals recovery key.',
      );
    }
    return normalized;
  }

  static String _canonicalizeRecoveryKey(String recoveryKey) {
    return recoveryKey
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll('\t', '')
        .toUpperCase();
  }

  Future<List<int>> encrypt(
    List<int> plaintext, {
    required String recoveryKey,
    required String contentType,
  }) async {
    _validateContentType(contentType);
    final keyBytes = _fromHex(normalizeRecoveryKey(recoveryKey));
    final nonce = _randomBytes(_nonceLength);
    final compressed = gzip.encode(plaintext);
    final box = await _aesGcm.encrypt(
      compressed,
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
      aad: _aad(contentType),
    );
    final envelope = <String, dynamic>{
      'format': 'totals.telegram.encrypted',
      'version': _version,
      'contentType': contentType,
      'compression': 'gzip',
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
    return utf8.encode(jsonEncode(envelope));
  }

  Future<List<int>> decrypt(
    List<int> encrypted, {
    required String recoveryKey,
    required String expectedContentType,
  }) async {
    _validateContentType(expectedContentType);
    late final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(utf8.decode(encrypted));
      if (decoded is! Map) throw const FormatException();
      envelope = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const TelegramBackupCryptoException(
        'The encrypted Telegram file is damaged or unsupported.',
      );
    }

    if (envelope['format'] != 'totals.telegram.encrypted' ||
        envelope['version'] != _version ||
        envelope['contentType'] != expectedContentType ||
        envelope['compression'] != 'gzip') {
      throw const TelegramBackupCryptoException(
        'The encrypted Telegram file has an unsupported format.',
      );
    }

    try {
      final keyBytes = _fromHex(normalizeRecoveryKey(recoveryKey));
      final nonce = base64Decode(envelope['nonce'] as String);
      final cipherText = base64Decode(envelope['ciphertext'] as String);
      final mac = Mac(base64Decode(envelope['mac'] as String));
      final compressed = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: SecretKey(keyBytes),
        aad: _aad(expectedContentType),
      );
      return gzip.decode(compressed);
    } on TelegramBackupCryptoException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const TelegramBackupCryptoException(
        'The recovery key is incorrect, or this backup was changed.',
      );
    } catch (_) {
      throw const TelegramBackupCryptoException(
        'The encrypted Telegram file is damaged or unsupported.',
      );
    }
  }

  Future<String> sha256Hex(List<int> bytes) async {
    final hash = await _hashAlgorithm.hash(bytes);
    return _toHex(hash.bytes);
  }

  List<int> _aad(String contentType) {
    return utf8.encode('totals.telegram.$contentType.v$_version');
  }

  void _validateContentType(String contentType) {
    if (contentType != backupContentType && contentType != catalogContentType) {
      throw ArgumentError.value(contentType, 'contentType');
    }
  }

  List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }

  static String _toHex(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> _fromHex(String hex) {
    return List<int>.generate(
      hex.length ~/ 2,
      (index) => int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16),
    );
  }
}
