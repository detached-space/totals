import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

void _vaultLog(String message) {
  if (kDebugMode) {
    debugPrint('debug: SharedExpenseVault: $message');
  }
}

/// Encrypted recovery vault. Stores the device's Ed25519 seed plus per-group
/// keys so a fresh install can restore the entire identity with a recovery
/// code + PIN.
///
/// Wire format (transport / at-rest):
/// ```
///   nonce(12 bytes) | ciphertext | mac(16 bytes)
/// ```
/// where `ciphertext` is AES-GCM-256 of `utf8(jsonEncode(vaultJson))` keyed by
/// a 256-bit Argon2id-derived KEK from the user's PIN + the random salt.
///
/// The cleartext vault (never crosses the wire and never hits the server):
/// ```json
/// {
///   "version": 1,
///   "seedHex": "<64 hex chars>",
///   "groupKeys": { "<groupId>": "<64 hex chars>", ... },
///   "displayName": "Khalid"   // optional
/// }
/// ```
class SharedExpenseVaultContent {
  final int version;
  final String seedHex;
  final Map<String, String> groupKeys;
  final String? displayName;

  const SharedExpenseVaultContent({
    required this.version,
    required this.seedHex,
    required this.groupKeys,
    this.displayName,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'seedHex': seedHex,
      'groupKeys': groupKeys,
      if (displayName != null && displayName!.trim().isNotEmpty)
        'displayName': displayName,
    };
  }

  factory SharedExpenseVaultContent.fromJson(Map<String, dynamic> json) {
    final rawGroupKeys = (json['groupKeys'] as Map?) ?? const {};
    final groupKeys = <String, String>{};
    rawGroupKeys.forEach((key, value) {
      if (key is String && value is String) {
        groupKeys[key] = value;
      }
    });
    return SharedExpenseVaultContent(
      version: (json['version'] as num?)?.toInt() ?? 1,
      seedHex: (json['seedHex'] as String?) ?? '',
      groupKeys: groupKeys,
      displayName: json['displayName'] as String?,
    );
  }
}

/// Argon2id parameters used to derive the KEK. Tuned for ~500ms on a mid-range
/// 2024 Android. Higher numbers = slower brute force but slower legit unlock.
class SharedExpenseVaultKdfParams {
  final int memoryKb;
  final int iterations;
  final int parallelism;

  const SharedExpenseVaultKdfParams({
    required this.memoryKb,
    required this.iterations,
    required this.parallelism,
  });

  static const SharedExpenseVaultKdfParams defaults =
      SharedExpenseVaultKdfParams(
    memoryKb: 65536, // 64 MB
    iterations: 3,
    parallelism: 4,
  );

  Map<String, dynamic> toJson() => {
        'memoryKb': memoryKb,
        'iterations': iterations,
        'parallelism': parallelism,
      };

  factory SharedExpenseVaultKdfParams.fromJson(Map<String, dynamic> json) {
    return SharedExpenseVaultKdfParams(
      memoryKb: (json['memoryKb'] as num?)?.toInt() ??
          defaults.memoryKb,
      iterations: (json['iterations'] as num?)?.toInt() ??
          defaults.iterations,
      parallelism: (json['parallelism'] as num?)?.toInt() ??
          defaults.parallelism,
    );
  }
}

/// What gets sent to the backend. `salt` and `encryptedBlob` are base64
/// strings (backend stores them as opaque text); the field names match the
/// wire format defined in identity-vault endpoints.
class SharedExpenseSealedVault {
  /// Schema version for the seal format (`nonce | cipher | mac`). Bumps if we
  /// ever change the wire format.
  final int version;
  final String saltBase64;
  final SharedExpenseVaultKdfParams kdfParams;
  final String encryptedBlobBase64;

  const SharedExpenseSealedVault({
    required this.version,
    required this.saltBase64,
    required this.kdfParams,
    required this.encryptedBlobBase64,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'salt': saltBase64,
        'kdfParams': kdfParams.toJson(),
        'encryptedBlob': encryptedBlobBase64,
      };

  factory SharedExpenseSealedVault.fromJson(Map<String, dynamic> json) {
    return SharedExpenseSealedVault(
      version: (json['version'] as num?)?.toInt() ?? 1,
      saltBase64: (json['salt'] as String?) ?? '',
      kdfParams: SharedExpenseVaultKdfParams.fromJson(
        Map<String, dynamic>.from(json['kdfParams'] as Map? ?? {}),
      ),
      encryptedBlobBase64: (json['encryptedBlob'] as String?) ?? '',
    );
  }
}

/// Thrown by [SharedExpenseVaultCrypto.unseal] when the supplied PIN is wrong
/// (MAC failure). The caller is responsible for reporting the failure to the
/// backend so the per-vault attempt counter advances toward the lockout.
class SharedExpenseVaultWrongPinException implements Exception {
  const SharedExpenseVaultWrongPinException();
  @override
  String toString() => 'SharedExpenseVaultWrongPinException';
}

/// Thrown when the sealed vault is malformed or its inner JSON is the wrong
/// shape — only raised AFTER a successful MAC check, so the PIN was correct
/// but the data is corrupt.
class SharedExpenseVaultMalformedException implements Exception {
  final String reason;
  const SharedExpenseVaultMalformedException(this.reason);
  @override
  String toString() => 'SharedExpenseVaultMalformedException($reason)';
}

class SharedExpenseVaultCrypto {
  static const int saltLength = 16;
  static const int nonceLength = 12;
  static const int macLength = 16;
  static const int kekLength = 32;
  static const int currentVersion = 1;

  final Random _random;
  final AesGcm _aes;

  SharedExpenseVaultCrypto({Random? random, AesGcm? aes})
      : _random = random ?? Random.secure(),
        _aes = aes ?? AesGcm.with256bits();

  /// Build + seal a vault. Generates a fresh random salt and derives the
  /// KEK from the PIN. Use [sealWithKek] when you already have a cached KEK
  /// (e.g., re-uploading after a local change without re-deriving from PIN).
  Future<SharedExpenseSealedVault> seal({
    required String pin,
    required SharedExpenseVaultContent content,
    SharedExpenseVaultKdfParams kdfParams =
        SharedExpenseVaultKdfParams.defaults,
  }) async {
    if (pin.trim().isEmpty) {
      throw ArgumentError('PIN must not be empty.');
    }
    final salt = _randomBytes(saltLength);
    final kek = await _deriveKek(pin: pin, salt: salt, params: kdfParams);
    return sealWithKek(
      kek: kek,
      saltBase64: base64Encode(salt),
      kdfParams: kdfParams,
      content: content,
    );
  }

  /// Seal using an already-derived KEK. Salt and KDF params are persisted in
  /// the returned record so subsequent unseal calls can re-derive the same
  /// KEK from the same PIN.
  Future<SharedExpenseSealedVault> sealWithKek({
    required List<int> kek,
    required String saltBase64,
    required SharedExpenseVaultKdfParams kdfParams,
    required SharedExpenseVaultContent content,
  }) async {
    final plain = utf8.encode(jsonEncode(content.toJson()));
    final nonce = _randomBytes(nonceLength);
    final box = await _aes.encrypt(
      plain,
      secretKey: SecretKey(kek),
      nonce: nonce,
    );
    final blob = <int>[
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ];
    _vaultLog('sealWithKek version=$currentVersion bytes=${blob.length}');
    return SharedExpenseSealedVault(
      version: currentVersion,
      saltBase64: saltBase64,
      kdfParams: kdfParams,
      encryptedBlobBase64: base64Encode(blob),
    );
  }

  /// Derive the KEK from a PIN and the base64-encoded salt that was stored
  /// alongside the sealed vault. Caller can cache the returned bytes for the
  /// session so subsequent re-seals via [sealWithKek] don't re-pay the
  /// Argon2id cost.
  Future<List<int>> deriveKek({
    required String pin,
    required String saltBase64,
    required SharedExpenseVaultKdfParams params,
  }) {
    final salt = base64Decode(saltBase64);
    return _deriveKek(pin: pin, salt: salt, params: params);
  }

  /// Decrypt a sealed vault with the user's PIN. Throws
  /// [SharedExpenseVaultWrongPinException] on MAC failure (wrong PIN).
  Future<SharedExpenseVaultContent> unseal({
    required String pin,
    required SharedExpenseSealedVault sealed,
  }) async {
    if (sealed.version != currentVersion) {
      throw SharedExpenseVaultMalformedException(
        'unsupported vault version ${sealed.version}',
      );
    }
    final salt = base64Decode(sealed.saltBase64);
    final kek = await _deriveKek(
      pin: pin,
      salt: salt,
      params: sealed.kdfParams,
    );
    final blob = base64Decode(sealed.encryptedBlobBase64);
    if (blob.length <= nonceLength + macLength) {
      throw const SharedExpenseVaultMalformedException(
        'blob too short for nonce + mac',
      );
    }
    final box = SecretBox.fromConcatenation(
      blob,
      nonceLength: nonceLength,
      macLength: macLength,
    );
    List<int> plain;
    try {
      plain = await _aes.decrypt(box, secretKey: SecretKey(kek));
    } on SecretBoxAuthenticationError {
      throw const SharedExpenseVaultWrongPinException();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(plain));
    } catch (error) {
      throw SharedExpenseVaultMalformedException(
        'inner json decode failed: $error',
      );
    }
    if (decoded is! Map) {
      throw const SharedExpenseVaultMalformedException(
        'inner json was not a map',
      );
    }
    final content = SharedExpenseVaultContent.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    if (content.seedHex.length != 64) {
      throw SharedExpenseVaultMalformedException(
        'seedHex wrong length=${content.seedHex.length}',
      );
    }
    _vaultLog('unseal ok groupKeys=${content.groupKeys.length}');
    return content;
  }

  Future<List<int>> _deriveKek({
    required String pin,
    required List<int> salt,
    required SharedExpenseVaultKdfParams params,
  }) async {
    final argon = Argon2id(
      memory: params.memoryKb,
      iterations: params.iterations,
      parallelism: params.parallelism,
      hashLength: kekLength,
    );
    final secret = await argon.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return secret.extractBytes();
  }

  List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }
}
