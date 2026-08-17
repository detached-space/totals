import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/transaction_location_repository.dart';
import 'package:totals/services/advanced_settings_service.dart';

enum LocationCapturePermission {
  always,
  whileInUse,
  serviceDisabled,
  denied,
  permanentlyDenied,
  unavailable,
}

extension LocationCapturePermissionState on LocationCapturePermission {
  bool get canCapture =>
      this == LocationCapturePermission.always ||
      this == LocationCapturePermission.whileInUse;

  bool get canCaptureInBackground => this == LocationCapturePermission.always;
}

class TransactionLocationCaptureService {
  TransactionLocationCaptureService._();

  static final TransactionLocationCaptureService instance =
      TransactionLocationCaptureService._();

  final TransactionLocationRepository _repository =
      TransactionLocationRepository();

  Future<LocationCapturePermission> requestPermissionForCapture() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationCapturePermission.serviceDisabled;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationCapturePermission.permanentlyDenied;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        return LocationCapturePermission.denied;
      }
      if (permission == LocationPermission.always) {
        return LocationCapturePermission.always;
      }

      if (Platform.isAndroid) {
        final backgroundStatus =
            await permissions.Permission.locationAlways.request();
        if (backgroundStatus.isGranted) {
          return LocationCapturePermission.always;
        }
      }
      return LocationCapturePermission.whileInUse;
    } catch (error) {
      debugPrint('debug: Could not request location permission: $error');
      return LocationCapturePermission.unavailable;
    }
  }

  Future<void> openSettingsFor(LocationCapturePermission state) async {
    if (state == LocationCapturePermission.serviceDisabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    await Geolocator.openAppSettings();
  }

  Future<bool> captureForTransaction(Transaction transaction) async {
    try {
      final transactionType = transaction.type?.trim().toUpperCase();
      if (transactionType != 'DEBIT' && transactionType != 'CREDIT') {
        return false;
      }
      await AdvancedSettingsService.instance.ensureLoaded();
      if (!AdvancedSettingsService.instance.spendingMapEnabled.value) {
        return false;
      }
      if (await _repository.hasLocation(transaction.reference)) return true;
      if (!await Geolocator.isLocationServiceEnabled()) return false;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return false;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 8),
        );
      } on TimeoutException {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null &&
            DateTime.now().difference(lastKnown.timestamp).abs() <=
                const Duration(minutes: 5)) {
          position = lastKnown;
        }
      }

      if (position == null) return false;
      await _repository.saveLocation(
        transaction: transaction,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        capturedAt: position.timestamp,
      );
      return true;
    } catch (error) {
      debugPrint(
        'debug: Location capture skipped for ${transaction.reference}: $error',
      );
      return false;
    }
  }
}
