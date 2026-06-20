import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:totals/services/data_sync/sync_service.dart';

/// The app's first long-lived connectivity listener. When the device
/// transitions from offline to online it kicks a Data Sync drain so queued
/// rows go out promptly. No-ops when Data Sync is disabled (the drain
/// self-gates).
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = true;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      _online = _isOnline(await _connectivity.checkConnectivity());
    } catch (_) {
      _online = true;
    }

    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final online = _isOnline(results);
      final wasOffline = !_online;
      _online = online;
      if (online && wasOffline) {
        if (kDebugMode) debugPrint('debug: ConnectivityService: back online → drain');
        unawaited(SyncService.instance.requestDrain(reason: 'connectivity'));
      }
    });
  }

  bool _isOnline(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
