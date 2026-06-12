import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void _cryptoLog(String message) {
  if (kDebugMode) {
    debugPrint('debug: SharedExpenseCrypto: $message');
  }
}

String _logKey(String value) {
  if (value.length <= 12) return value;
  return '${value.substring(0, 8)}...${value.substring(value.length - 4)}';
}

class SharedExpenseIdentity {
  final String publicKeyHex;

  const SharedExpenseIdentity({required this.publicKeyHex});
}

class SharedExpenseCryptoService {
  static const _privateKeyKey = 'shared_expense_device_private_key';
  static const _publicKeyKey = 'shared_expense_device_public_key';
  static const _nonceLength = 12;
  static const _macLength = 16;

  final FlutterSecureStorage _storage;
  final Ed25519 _ed25519;
  final X25519 _x25519;
  final AesGcm _aesGcm;
  final Sha512 _sha512;
  final Random _random;

  // In-memory cache for the seed + public key so repeated decryption calls
  // within a wake don't re-hit Keystore. Keystore reads dominate cold-start
  // latency in the background push handler (200–400ms). Cleared on identity
  // rotation only.
  static String? _cachedPrivateKeyHex;
  static String? _cachedPublicKeyHex;

  SharedExpenseCryptoService({
    FlutterSecureStorage? storage,
    Ed25519? ed25519,
    X25519? x25519,
    AesGcm? aesGcm,
    Sha512? sha512,
    Random? random,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _ed25519 = ed25519 ?? Ed25519(),
        _x25519 = x25519 ?? X25519(),
        _aesGcm = aesGcm ?? AesGcm.with256bits(),
        _sha512 = sha512 ?? Sha512(),
        _random = random ?? Random.secure();

  Future<SharedExpenseIdentity> getOrCreateIdentity() async {
    final cachedPublic = _cachedPublicKeyHex;
    if (cachedPublic != null && cachedPublic.isNotEmpty) {
      return SharedExpenseIdentity(publicKeyHex: cachedPublic);
    }

    final existingPrivateHex = await _safeRead(_privateKeyKey);
    final existingPublicHex = await _safeRead(_publicKeyKey);
    if (existingPrivateHex != null &&
        existingPrivateHex.isNotEmpty &&
        existingPublicHex != null &&
        existingPublicHex.isNotEmpty) {
      _cryptoLog('using existing identity key=${_logKey(existingPublicHex)}');
      _cachedPrivateKeyHex = existingPrivateHex;
      _cachedPublicKeyHex = existingPublicHex;
      return SharedExpenseIdentity(publicKeyHex: existingPublicHex);
    }

    if (existingPrivateHex != null && existingPrivateHex.isNotEmpty) {
      _cryptoLog('repairing missing identity public key');
      final keyPair = await _ed25519.newKeyPairFromSeed(
        fromHex(existingPrivateHex),
      );
      final publicKey = await keyPair.extractPublicKey();
      final publicKeyHex = toHex(publicKey.bytes);
      await _storage.write(key: _publicKeyKey, value: publicKeyHex);
      _cachedPrivateKeyHex = existingPrivateHex;
      _cachedPublicKeyHex = publicKeyHex;
      return SharedExpenseIdentity(publicKeyHex: publicKeyHex);
    }

    if (existingPublicHex != null && existingPublicHex.isNotEmpty) {
      throw StateError('Shared expense identity is incomplete.');
    }

    _cryptoLog('creating new identity');
    final seed = randomBytes(32);
    final keyPair = await _ed25519.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyHex = toHex(publicKey.bytes);
    final seedHex = toHex(seed);

    await _storage.write(key: _privateKeyKey, value: seedHex);
    await _storage.write(key: _publicKeyKey, value: publicKeyHex);
    _cachedPrivateKeyHex = seedHex;
    _cachedPublicKeyHex = publicKeyHex;

    _cryptoLog('created identity key=${_logKey(publicKeyHex)}');
    return SharedExpenseIdentity(publicKeyHex: publicKeyHex);
  }

  /// Read a value from secure storage. Read failures are not treated as a
  /// missing identity because rotating this key changes group membership.
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (error) {
      _cryptoLog('safeRead failed key=$key error=$error');
      throw StateError('Shared expense identity storage is unavailable.');
    }
  }

  /// Read the current device seed for vault backup. Returns null if no
  /// identity has been created yet. Caller is responsible for keeping the
  /// returned hex string in scope only as long as needed.
  Future<String?> exportSeedHex() async {
    final cached = _cachedPrivateKeyHex;
    if (cached != null && cached.isNotEmpty) return cached;
    return _safeRead(_privateKeyKey);
  }

  /// Replace the device identity with the supplied seed (e.g. from a
  /// successful vault unseal during restore). The corresponding public key
  /// is recomputed and persisted. The in-memory cache is updated so the
  /// next operation uses the restored identity immediately.
  Future<SharedExpenseIdentity> restoreFromSeedHex(String seedHex) async {
    final normalized = seedHex.trim().toLowerCase();
    if (normalized.length != 64) {
      throw ArgumentError(
        'restoreFromSeedHex expects a 64-char hex seed, got ${normalized.length}',
      );
    }
    final seedBytes = fromHex(normalized);
    final keyPair = await _ed25519.newKeyPairFromSeed(seedBytes);
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyHex = toHex(publicKey.bytes);

    await _storage.write(key: _privateKeyKey, value: normalized);
    await _storage.write(key: _publicKeyKey, value: publicKeyHex);
    _cachedPrivateKeyHex = normalized;
    _cachedPublicKeyHex = publicKeyHex;

    _cryptoLog('restored identity key=${_logKey(publicKeyHex)}');
    return SharedExpenseIdentity(publicKeyHex: publicKeyHex);
  }

  Future<String> signHexChallenge(String challengeHex) async {
    final seedHex = await _readPrivateKey();
    final keyPair = await _ed25519.newKeyPairFromSeed(fromHex(seedHex));
    _cryptoLog('signing challenge bytes=${challengeHex.length ~/ 2}');
    final signature = await _ed25519.sign(
      fromHex(challengeHex),
      keyPair: keyPair,
    );
    return toHex(signature.bytes);
  }

  Future<String> _readPrivateKey() async {
    final cached = _cachedPrivateKeyHex;
    if (cached != null && cached.isNotEmpty) return cached;
    final seedHex = await _safeRead(_privateKeyKey);
    if (seedHex == null || seedHex.isEmpty) {
      await getOrCreateIdentity();
      final fresh = _cachedPrivateKeyHex;
      if (fresh != null && fresh.isNotEmpty) return fresh;
      throw StateError('Shared expense identity is not available.');
    }
    _cachedPrivateKeyHex = seedHex;
    return seedHex;
  }

  Future<String> encryptGroupKeyPayload({
    required String recipientPublicKeyHex,
    required Map<String, dynamic> payload,
  }) async {
    _cryptoLog(
      'encryptGroupKeyPayload recipient=${_logKey(recipientPublicKeyHex)}',
    );
    final sharedSecret = await _sharedSecretFor(recipientPublicKeyHex);
    return encryptPayloadWithKey(
      keyBytes: await sharedSecret.extractBytes(),
      payload: payload,
    );
  }

  Future<Map<String, dynamic>?> decryptGroupKeyPayload({
    required String senderPublicKeyHex,
    required String encryptedBlob,
  }) async {
    _cryptoLog('decryptGroupKeyPayload sender=${_logKey(senderPublicKeyHex)}');
    final sharedSecret = await _sharedSecretFor(senderPublicKeyHex);
    return decryptPayloadWithKey(
      keyBytes: await sharedSecret.extractBytes(),
      encryptedBlob: encryptedBlob,
    );
  }

  Future<String> encryptPayloadWithKey({
    required List<int> keyBytes,
    required Map<String, dynamic> payload,
  }) async {
    final nonce = randomBytes(_nonceLength);
    final plainText = utf8.encode(jsonEncode(payload));
    _cryptoLog(
      'encryptPayloadWithKey keys=${payload.keys.join(',')} '
      'plainBytes=${plainText.length}',
    );
    final secretBox = await _aesGcm.encrypt(
      plainText,
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
    );
    return toHex([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  Future<Map<String, dynamic>?> decryptPayloadWithKey({
    required List<int> keyBytes,
    required String encryptedBlob,
  }) async {
    try {
      final bytes = fromHex(encryptedBlob);
      if (bytes.length <= _nonceLength + _macLength) {
        _cryptoLog(
          'decryptPayloadWithKey blob too short bytes=${bytes.length}',
        );
        return null;
      }
      final secretBox = SecretBox.fromConcatenation(
        bytes,
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final plainText = await _aesGcm.decrypt(
        secretBox,
        secretKey: SecretKey(keyBytes),
      );
      _cryptoLog('decryptPayloadWithKey decrypted bytes=${plainText.length}');
      final decoded = jsonDecode(utf8.decode(plainText));
      if (decoded is! Map) {
        _cryptoLog('decryptPayloadWithKey ignored non-map payload');
        return null;
      }
      return Map<String, dynamic>.from(decoded);
    } catch (error) {
      _cryptoLog('decryptPayloadWithKey failed: $error');
      return null;
    }
  }

  List<int> randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }

  Future<SecretKey> _sharedSecretFor(String otherEd25519PublicKeyHex) async {
    final privateKeyHex = await _readPrivateKey();

    _cryptoLog(
        'deriving shared secret remote=${_logKey(otherEd25519PublicKeyHex)}');
    final edSeed = fromHex(privateKeyHex);
    final x25519Seed = await _ed25519SeedToX25519Seed(edSeed);
    final ownKeyPair = await _x25519.newKeyPairFromSeed(x25519Seed);
    final remotePublicKey = SimplePublicKey(
      _ed25519PublicKeyToX25519(fromHex(otherEd25519PublicKeyHex)),
      type: KeyPairType.x25519,
    );

    return _x25519.sharedSecretKey(
      keyPair: ownKeyPair,
      remotePublicKey: remotePublicKey,
    );
  }

  Future<List<int>> _ed25519SeedToX25519Seed(List<int> seed) async {
    final hash = await _sha512.hash(seed);
    return hash.bytes.sublist(0, 32);
  }

  List<int> _ed25519PublicKeyToX25519(List<int> publicKeyBytes) {
    if (publicKeyBytes.length != 32) {
      throw ArgumentError('Ed25519 public key must have 32 bytes.');
    }

    final yBytes = Uint8List.fromList(publicKeyBytes);
    yBytes[31] &= 0x7f;
    final y = _bigIntFromLittleEndian(yBytes);
    final p = (BigInt.one << 255) - BigInt.from(19);
    final numerator = (BigInt.one + y) % p;
    final denominator = (BigInt.one - y) % p;
    final u = (numerator * denominator.modInverse(p)) % p;
    return _littleEndianFromBigInt(u, 32);
  }

  BigInt _bigIntFromLittleEndian(List<int> bytes) {
    var result = BigInt.zero;
    for (var i = bytes.length - 1; i >= 0; i--) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  List<int> _littleEndianFromBigInt(BigInt value, int length) {
    final result = List<int>.filled(length, 0);
    var remaining = value;
    for (var i = 0; i < length; i++) {
      result[i] = (remaining & BigInt.from(0xff)).toInt();
      remaining = remaining >> 8;
    }
    return result;
  }

  static String toHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static List<int> fromHex(String hex) {
    final normalized = hex.trim().toLowerCase();
    if (normalized.length.isOdd) {
      throw FormatException('Hex string must have an even length.', hex);
    }

    final bytes = <int>[];
    for (var i = 0; i < normalized.length; i += 2) {
      bytes.add(int.parse(normalized.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}
