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

  /// True where the "Verify Payments" tool is offered — Android only for now.
  ///
  /// The verifier forwards transaction references / receipt images through a
  /// third-party service, so it stays off on iOS v1 to keep the App Store
  /// privacy label at "Data Not Collected". See
  /// `app/docs/ios-port/APP_STORE_PREFLIGHT.md`.
  static bool get canVerifyPayments =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
