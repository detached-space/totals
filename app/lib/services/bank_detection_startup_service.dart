import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/bank_detection_service.dart';
import 'package:totals/services/sms_config_service.dart';

/// Runs bank detection once at app startup so detected banks are available
/// even before the user unlocks the app UI.
class BankDetectionStartupService {
  static bool _hasRunThisLaunch = false;
  static bool _isRunning = false;

  static Future<void> runOnAppOpen() async {
    if (_hasRunThisLaunch || _isRunning) return;

    try {
      final permissionStatus = await Permission.sms.status;
      if (!permissionStatus.isGranted) {
        if (kDebugMode) {
          print(
              "debug: SMS permission not granted, skipping startup detection");
        }
        return;
      }

      _hasRunThisLaunch = true;
      _isRunning = true;

      await SmsConfigService().syncRemoteConfig();

      // Ensure bank configuration exists before trying to match sender IDs.
      await BankConfigService().initializeBanks();

      await BankDetectionService().detectUnregisteredBanks(
        forceRefresh: true,
      );

      if (kDebugMode) {
        print("debug: Startup bank detection completed");
      }
    } catch (e) {
      if (kDebugMode) {
        print("debug: Startup bank detection failed: $e");
      }
    } finally {
      _isRunning = false;
    }
  }
}
