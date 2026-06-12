import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:totals/repositories/shared_expense_repository.dart';
import 'package:totals/services/shared_expense_crypto_service.dart';
import 'package:totals/services/shared_expense_realtime_bus.dart';
import 'package:totals/services/shared_expense_recovery_code.dart';
import 'package:totals/services/shared_expense_vault.dart';
import 'package:totals/services/totals_engine_client.dart';

void _vaultLog(String message) {
  if (kDebugMode) {
    debugPrint('debug: SharedExpenseVaultService: $message');
  }
}

/// Thrown by [SharedExpenseVaultService.restore] when the supplied recovery
/// code doesn't match any vault on the server (404 from the fetch endpoint).
class SharedExpenseNoVaultException implements Exception {
  const SharedExpenseNoVaultException();
  @override
  String toString() => 'SharedExpenseNoVaultException';
}

/// Thrown when the backend's per-vault lockout is active (429 from fetch).
/// Carries the timestamp the lockout lifts so the UI can show a countdown.
class SharedExpenseVaultLockedException implements Exception {
  final DateTime? lockedUntil;
  const SharedExpenseVaultLockedException({this.lockedUntil});
  @override
  String toString() =>
      'SharedExpenseVaultLockedException(lockedUntil=$lockedUntil)';
}

/// Orchestrates the identity-recovery vault.
///
/// Lifecycle:
/// - [setupNew] — first time, generate recovery code, seal local state with
///   PIN, upload, persist recovery code in secure storage, cache KEK for the
///   session.
/// - [unlock] — subsequent sessions, re-derive KEK from the PIN using the
///   server-stored salt for the persisted recovery code.
/// - [restore] — fresh install with no local identity, fetch the sealed
///   vault by recovery code, unseal with PIN, write seed + group keys into
///   local secure storage.
/// - [syncIfUnlocked] — on every relevant local change (join, leave, key
///   receipt, etc.), rebuild + re-seal + upload. No-op when locked.
/// - [lock] — wipe in-memory KEK; persisted recovery code stays.
class SharedExpenseVaultService extends ChangeNotifier {
  SharedExpenseVaultService._({
    SharedExpenseRepository? repository,
    SharedExpenseCryptoService? cryptoService,
    TotalsEngineClient? engineClient,
    SharedExpenseVaultCrypto? vaultCrypto,
    FlutterSecureStorage? secureStorage,
  })  : _repository = repository ?? SharedExpenseRepository(),
        _cryptoService = cryptoService ?? SharedExpenseCryptoService(),
        _engineClient = engineClient ?? TotalsEngineClient(),
        _vaultCrypto = vaultCrypto ?? SharedExpenseVaultCrypto(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static final SharedExpenseVaultService instance =
      SharedExpenseVaultService._();

  static const String _recoveryCodeKey = 'shared_expense_vault_recovery_code';

  final SharedExpenseRepository _repository;
  final SharedExpenseCryptoService _cryptoService;
  final TotalsEngineClient _engineClient;
  final SharedExpenseVaultCrypto _vaultCrypto;
  final FlutterSecureStorage _secureStorage;

  String? _recoveryCode;
  List<int>? _cachedKek;
  String? _cachedSaltBase64;
  SharedExpenseVaultKdfParams? _cachedKdfParams;
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _recoveryCode = await _secureStorage.read(key: _recoveryCodeKey);
      _vaultLog('initialized hasVault=$hasVault');
    } catch (error) {
      _vaultLog('initialize read failed: $error');
      _recoveryCode = null;
    }
    notifyListeners();
  }

  /// True once a vault has been set up on this device. Persists across
  /// app restarts.
  bool get hasVault =>
      _recoveryCode != null && _recoveryCode!.isNotEmpty;

  /// True while a derived KEK is cached in memory for the current session.
  bool get isUnlocked => _cachedKek != null;

  /// The recovery code the user is supposed to keep somewhere safe. Returns
  /// null when no vault has been set up yet.
  String? get recoveryCode => _recoveryCode;

  /// First-time vault setup. Generates a recovery code, seals the current
  /// device state with the PIN, uploads. Caches the recovery code in secure
  /// storage and the derived KEK in memory for the session.
  ///
  /// Returns the recovery code so the UI can present it to the user — they
  /// must save it somewhere safe.
  Future<String> setupNew({required String pin}) async {
    await ensureInitialized();
    if (hasVault) {
      throw StateError(
        'Vault already exists; call unlock() or rotate via change-pin.',
      );
    }
    if (pin.trim().isEmpty) {
      throw ArgumentError('PIN must not be empty.');
    }
    final recoveryCode = SharedExpenseRecoveryCode.generate();
    final content = await _buildVaultContent();
    final sealed = await _vaultCrypto.seal(pin: pin, content: content);
    await _engineClient.putIdentityVault(
      recoveryCode: recoveryCode,
      sealedVault: sealed.toJson(),
    );
    await _secureStorage.write(key: _recoveryCodeKey, value: recoveryCode);
    _recoveryCode = recoveryCode;
    _cacheKekFromSealed(
      kek: await _vaultCrypto.deriveKek(
        pin: pin,
        saltBase64: sealed.saltBase64,
        params: sealed.kdfParams,
      ),
      sealed: sealed,
    );
    _vaultLog('setupNew ok groupKeys=${content.groupKeys.length}');
    notifyListeners();
    return recoveryCode;
  }

  /// Unlock an existing vault for the current session by entering the PIN.
  /// Fetches the sealed vault to read the salt + KDF params, derives the
  /// KEK, validates via unseal. Throws [SharedExpenseVaultWrongPinException]
  /// on bad PIN.
  Future<void> unlock({required String pin}) async {
    await ensureInitialized();
    if (!hasVault) {
      throw StateError('No vault on this device; call setupNew() first.');
    }
    final sealed = await _fetchSealed(_recoveryCode!);
    if (sealed == null) {
      throw const SharedExpenseNoVaultException();
    }
    try {
      await _vaultCrypto.unseal(pin: pin, sealed: sealed);
      final kek = await _vaultCrypto.deriveKek(
        pin: pin,
        saltBase64: sealed.saltBase64,
        params: sealed.kdfParams,
      );
      _cacheKekFromSealed(kek: kek, sealed: sealed);
      _vaultLog('unlock ok');
      notifyListeners();
    } on SharedExpenseVaultWrongPinException {
      unawaited(_engineClient.reportIdentityVaultFailure(_recoveryCode!));
      rethrow;
    }
  }

  /// Restore identity from backend vault. Writes the seed + group keys
  /// into local secure storage. Caller is responsible for the follow-up
  /// `refreshGroups()` so the local DB rows for each group get populated.
  Future<SharedExpenseVaultContent> restore({
    required String recoveryCode,
    required String pin,
  }) async {
    await ensureInitialized();
    final normalized =
        SharedExpenseRecoveryCode.normalizeForWire(recoveryCode);
    if (normalized == null) {
      throw ArgumentError('Recovery code is not well-formed.');
    }
    final sealed = await _fetchSealed(normalized);
    if (sealed == null) {
      throw const SharedExpenseNoVaultException();
    }
    SharedExpenseVaultContent content;
    try {
      content = await _vaultCrypto.unseal(pin: pin, sealed: sealed);
    } on SharedExpenseVaultWrongPinException {
      unawaited(_engineClient.reportIdentityVaultFailure(normalized));
      rethrow;
    }
    await _cryptoService.restoreFromSeedHex(content.seedHex);
    for (final entry in content.groupKeys.entries) {
      await _repository.restoreGroupKey(
        groupId: entry.key,
        groupKeyHex: entry.value,
      );
    }
    await _secureStorage.write(key: _recoveryCodeKey, value: normalized);
    _recoveryCode = normalized;
    final kek = await _vaultCrypto.deriveKek(
      pin: pin,
      saltBase64: sealed.saltBase64,
      params: sealed.kdfParams,
    );
    _cacheKekFromSealed(kek: kek, sealed: sealed);
    _vaultLog(
      'restore ok seed-set groupKeys=${content.groupKeys.length}',
    );
    notifyListeners();
    // Rehydrate group rows from server-side membership and ask peers to
    // re-share history. Fire-and-forget — restore returns as soon as the
    // identity is in place; the history streams in as other members
    // respond. We pass the vault's group-ID list so the bootstrap step can
    // create local rows that refreshGroups would otherwise skip as
    // "unknown server group".
    unawaited(_rehydrateAfterRestore(content.groupKeys.keys.toList()));
    return content;
  }

  Future<void> _rehydrateAfterRestore(List<String> vaultGroupIds) async {
    try {
      // 1. Create bare local rows for the groups in the vault. Without this
      //    refreshGroups would skip them as "unknown server group".
      await _repository.bootstrapGroupsForRestore(vaultGroupIds);
      // 2. Merge server-side membership into those rows (display names,
      //    member list, etc. coming from server's listGroups).
      await _repository.refreshGroups();
      // 3. Push each restored group through the realtime bus so the shared
      //    expenses page rebuilds without a manual refresh. refreshGroups
      //    writes to the DB but doesn't publish on its own, so a page that
      //    was sitting on the empty state never sees the new rows otherwise.
      final groups = await _repository.getGroups();
      for (final group in groups) {
        SharedExpenseRealtimeBus.instance.publish(group);
      }
      // 4. Ask peers for the full encrypted snapshot so the activity log,
      //    expenses, and member meta materialise. Those snapshots will
      //    publish to the bus on arrival via the existing SSE consumer.
      await _repository.requestSnapshotsForAllGroups();
      _vaultLog(
        'rehydrateAfterRestore done published=${groups.length}',
      );
    } catch (error, stackTrace) {
      _vaultLog('rehydrateAfterRestore failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Change the PIN. Verifies the old PIN by attempting an unlock, then
  /// re-seals the current vault content with a fresh KEK derived from the
  /// new PIN and uploads. The recovery code stays the same. Throws
  /// [SharedExpenseVaultWrongPinException] if the old PIN is wrong.
  Future<void> changePin({
    required String oldPin,
    required String newPin,
  }) async {
    await ensureInitialized();
    if (!hasVault) {
      throw StateError('No vault on this device.');
    }
    if (newPin.trim().isEmpty) {
      throw ArgumentError('New PIN must not be empty.');
    }
    // Verify the old PIN. unlock() throws SharedExpenseVaultWrongPinException
    // (and reports the failure to the backend) if it's wrong.
    await unlock(pin: oldPin);

    final content = await _buildVaultContent();
    final sealed = await _vaultCrypto.seal(pin: newPin, content: content);
    await _engineClient.putIdentityVault(
      recoveryCode: _recoveryCode!,
      sealedVault: sealed.toJson(),
    );
    final newKek = await _vaultCrypto.deriveKek(
      pin: newPin,
      saltBase64: sealed.saltBase64,
      params: sealed.kdfParams,
    );
    _cacheKekFromSealed(kek: newKek, sealed: sealed);
    _vaultLog('changePin ok');
    notifyListeners();
  }

  /// Wipe the in-memory KEK so subsequent syncs are silent no-ops until the
  /// next [unlock] call. Persisted recovery code is untouched.
  void lock() {
    _cachedKek = null;
    _cachedSaltBase64 = null;
    _cachedKdfParams = null;
    _vaultLog('lock');
    notifyListeners();
  }

  /// DEBUG ONLY: wipe the persisted recovery code so the next launch behaves
  /// like a fresh install (vault setup banner reappears, can run setup
  /// again). Does NOT delete the server-side vault row — that would require
  /// an authenticated DELETE we don't have endpoints for yet. The orphaned
  /// row is harmless: it's keyed by a recovery code we no longer remember,
  /// so nobody can fetch it.
  Future<void> debugReset() async {
    assert(() {
      // Refuse to compile this method into release builds — the assert
      // body runs only in debug.
      return true;
    }());
    if (!kDebugMode) {
      _vaultLog('debugReset refused in release build');
      return;
    }
    try {
      await _secureStorage.delete(key: _recoveryCodeKey);
    } catch (error) {
      _vaultLog('debugReset secure-storage delete failed: $error');
    }
    _recoveryCode = null;
    _cachedKek = null;
    _cachedSaltBase64 = null;
    _cachedKdfParams = null;
    _vaultLog('debugReset done');
    notifyListeners();
  }

  /// Re-build the vault from the device's current state and upload. No-op
  /// when locked. Reuses the cached salt + KEK so the same PIN keeps
  /// unlocking the vault after the sync.
  ///
  /// Returns true if the upload happened, false if locked or no vault.
  Future<bool> syncIfUnlocked() async {
    await ensureInitialized();
    if (!hasVault) return false;
    if (_cachedKek == null ||
        _cachedSaltBase64 == null ||
        _cachedKdfParams == null) {
      _vaultLog('syncIfUnlocked skipped (locked)');
      return false;
    }
    try {
      final content = await _buildVaultContent();
      final sealed = await _vaultCrypto.sealWithKek(
        kek: _cachedKek!,
        saltBase64: _cachedSaltBase64!,
        kdfParams: _cachedKdfParams!,
        content: content,
      );
      await _engineClient.putIdentityVault(
        recoveryCode: _recoveryCode!,
        sealedVault: sealed.toJson(),
      );
      _vaultLog('syncIfUnlocked ok groupKeys=${content.groupKeys.length}');
      return true;
    } catch (error, stackTrace) {
      _vaultLog('syncIfUnlocked failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Internals

  Future<SharedExpenseVaultContent> _buildVaultContent() async {
    final seedHex = await _cryptoService.exportSeedHex();
    if (seedHex == null || seedHex.isEmpty) {
      throw StateError('No device identity to back up.');
    }
    final groups = await _repository.getGroups();
    final groupKeys = <String, String>{};
    for (final group in groups) {
      final keyHex = await _repository.exportGroupKey(group.id);
      if (keyHex != null && keyHex.isNotEmpty) {
        groupKeys[group.id] = keyHex;
      }
    }
    return SharedExpenseVaultContent(
      version: SharedExpenseVaultCrypto.currentVersion,
      seedHex: seedHex,
      groupKeys: groupKeys,
    );
  }

  Future<SharedExpenseSealedVault?> _fetchSealed(String recoveryCode) async {
    try {
      final raw = await _engineClient.fetchIdentityVault(recoveryCode);
      if (raw == null) return null;
      return SharedExpenseSealedVault.fromJson(raw);
    } on TotalsEngineException catch (error) {
      if (error.statusCode == 429) {
        final until = error.body?['lockedUntil'];
        throw SharedExpenseVaultLockedException(
          lockedUntil: until is String ? DateTime.tryParse(until) : null,
        );
      }
      rethrow;
    }
  }

  void _cacheKekFromSealed({
    required List<int> kek,
    required SharedExpenseSealedVault sealed,
  }) {
    _cachedKek = kek;
    _cachedSaltBase64 = sealed.saltBase64;
    _cachedKdfParams = sealed.kdfParams;
  }
}
