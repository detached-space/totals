import 'dart:async';
import 'dart:convert';

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

  /// Key under which we persist the PIN-derived KEK + matching salt/KDF so
  /// the vault can auto-unlock on every app launch without the user
  /// re-entering their PIN. flutter_secure_storage encrypts at rest using
  /// the OS keystore/keychain — the value is only readable while the
  /// device is unlocked. PIN is still required for new-device restore
  /// (we don't have access to this secure-storage entry there) and for
  /// change-pin / delete-vault flows.
  static const String _persistedKekKey =
      'shared_expense_vault_persisted_kek_v1';

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
  final StreamController<void> _restoreEventsController =
      StreamController<void>.broadcast();

  /// Fires once per successful [restore] call. The shared-expenses page
  /// listens to this so it can tear down its long-lived SSE subscriptions
  /// (which authenticated against the pre-restore identity) and reconnect
  /// with the restored one. Without this, snapshot replies from peers
  /// sit in the engine's queue for the wrong pubkey and the page looks
  /// empty until the user manually refreshes.
  Stream<void> get onRestore => _restoreEventsController.stream;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _recoveryCode = await _secureStorage.read(key: _recoveryCodeKey);
      _vaultLog('initialized hasVault=$hasVault');
      if (hasVault) {
        // Best-effort auto-unlock from a previously persisted KEK. Silent
        // success path = backup just keeps working across launches with no
        // PIN prompt. Silent failure path = the banner / sheets fall back
        // to the existing PIN flow.
        await _loadKekFromDevice();
      }
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
    await _persistKekToDevice();
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
      await _persistKekToDevice();
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
    await _persistKekToDevice();
    _vaultLog(
      'restore ok seed-set groupKeys=${content.groupKeys.length}',
    );
    notifyListeners();
    // Tell any listening UI (the shared expenses page) that the identity
    // just changed. The page restarts its SSE subscriptions on this event
    // so it picks up snapshot replies addressed to the restored pubkey
    // instead of the pre-restore one.
    if (!_restoreEventsController.isClosed) {
      _restoreEventsController.add(null);
    }
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
    await _persistKekToDevice();
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
    await _clearPersistedKek();
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

  /// Persist the in-memory KEK + matching salt + KDF params to OS secure
  /// storage so the vault auto-unlocks on the next launch without a PIN
  /// prompt. Called from every code path that derives a fresh KEK
  /// (setupNew / unlock / restore / changePin). Best effort: a write
  /// failure isn't fatal — the user will just be prompted for their PIN
  /// next time, same as the pre-auto-unlock behavior.
  Future<void> _persistKekToDevice() async {
    if (_cachedKek == null ||
        _cachedSaltBase64 == null ||
        _cachedKdfParams == null) {
      return;
    }
    try {
      final blob = jsonEncode({
        'kek': SharedExpenseCryptoService.toHex(_cachedKek!),
        'salt': _cachedSaltBase64,
        'kdf': _cachedKdfParams!.toJson(),
      });
      await _secureStorage.write(key: _persistedKekKey, value: blob);
      _vaultLog('persisted KEK to device');
    } catch (error) {
      _vaultLog('persist KEK failed: $error');
    }
  }

  /// Try to restore the cached KEK from secure storage. Returns true if a
  /// stored entry exists and was loaded — in which case [isUnlocked] flips
  /// to true and sync resumes silently. Returns false (and leaves cached
  /// fields null) if there's nothing stored, the entry is malformed, or
  /// the OS refused to release it (e.g. device locked).
  Future<bool> _loadKekFromDevice() async {
    try {
      final raw = await _secureStorage.read(key: _persistedKekKey);
      if (raw == null || raw.isEmpty) return false;
      final blob = jsonDecode(raw);
      if (blob is! Map) return false;
      final kekHex = blob['kek'] as String?;
      final saltBase64 = blob['salt'] as String?;
      final kdfMap = blob['kdf'];
      if (kekHex == null ||
          saltBase64 == null ||
          kdfMap is! Map<String, dynamic>) {
        return false;
      }
      _cachedKek = SharedExpenseCryptoService.fromHex(kekHex);
      _cachedSaltBase64 = saltBase64;
      _cachedKdfParams = SharedExpenseVaultKdfParams.fromJson(kdfMap);
      _vaultLog('loaded KEK from device — auto-unlocked');
      return true;
    } catch (error) {
      _vaultLog('load KEK failed: $error');
      return false;
    }
  }

  /// Wipe the persisted KEK entry. Called from debugReset and from any
  /// future delete-vault / opt-out-of-backup flow. Future app launches
  /// will fall back to the PIN entry path until the user unlocks again.
  Future<void> _clearPersistedKek() async {
    try {
      await _secureStorage.delete(key: _persistedKekKey);
      _vaultLog('cleared persisted KEK');
    } catch (error) {
      _vaultLog('clear persisted KEK failed: $error');
    }
  }
}
