import 'package:flutter/foundation.dart';

/// Central capability flags for platform features that don't exist everywhere.
///
/// Keeping these in one place avoids scattering `defaultTargetPlatform` checks
/// through the codebase and documents *why* a feature is gated.
class PlatformSupport {
  PlatformSupport._();

  /// True only where the app can read the device SMS inbox and listen for
  /// incoming SMS — i.e. Android.
  ///
  /// iOS and web expose no SMS API, so every telephony call must be skipped
  /// there (they throw `MissingPluginException`/`PlatformException` otherwise).
  /// On iOS, bank messages are ingested via the Shortcuts automation → file
  /// drop path instead, and still parsed by the same engine. See
  /// `app/docs/ios-port/PLAN.md`.
  static bool get canReadDeviceSms =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True where bank messages arrive via the iOS Shortcuts → file-drop inbox
  /// (see `MessageIngestService`) instead of direct SMS reads — i.e. iOS.
  static bool get usesFileInbox =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}
