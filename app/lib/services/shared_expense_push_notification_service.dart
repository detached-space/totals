import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:totals/repositories/shared_expense_repository.dart';
import 'package:totals/services/notification_intent_bus.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/shared_expense_notification_coordinator.dart';
import 'package:totals/services/shared_expense_realtime_bus.dart';
import 'package:totals/services/totals_engine_client.dart';

/// Doorbell-model push handler.
///
/// FCM messages from the engine carry only `{type, groupId, payloadId}` — no
/// content, encrypted or otherwise. On receipt we pull the now-pending payload
/// from the engine over HTTPS, decrypt it locally, and compose the
/// notification from the resulting activity entry using
/// [SharedExpensePushPreviewService.buildForActivity] via
/// [SharedExpenseNotificationCoordinator.notifyForUnseenActivities].
///
/// The backend may still send the legacy `encryptedNotificationPreview` field
/// during the transition; we deliberately ignore it. Do NOT re-enable
/// client-side decryption of that field without revisiting the doorbell
/// design — putting `senderPublicKey` back on the FCM wire breaks the
/// zero-knowledge invariant called out in CLAUDE.md.
class SharedExpensePushNotificationService {
  SharedExpensePushNotificationService._();

  static final SharedExpensePushNotificationService instance =
      SharedExpensePushNotificationService._();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  bool _started = false;
  bool _firebaseReady = false;

  static bool get _supportsFcm =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void registerBackgroundHandler() {
    if (!_supportsFcm) return;
    FirebaseMessaging.onBackgroundMessage(
      sharedExpenseFirebaseMessagingBackgroundHandler,
    );
  }

  Future<void> start() async {
    if (_started || !_supportsFcm) return;
    _started = true;

    if (!await _ensureFirebaseReady()) return;

    await NotificationService.instance.ensureInitialized();
    await NotificationService.instance.dismissLegacySharedExpenseFallbacks();
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    await syncRegistration();

    _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => unawaited(syncRegistration()),
      onError: (Object error) {
        if (kDebugMode) {
          debugPrint('debug: FCM token refresh failed: $error');
        }
      },
    );
    _foregroundSub ??= FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
      onError: (Object error) {
        if (kDebugMode) {
          debugPrint('debug: FCM foreground message failed: $error');
        }
      },
    );
    _openedSub ??= FirebaseMessaging.onMessageOpenedApp.listen(
      _handleNotificationTap,
      onError: (Object error) {
        if (kDebugMode) {
          debugPrint('debug: FCM notification open failed: $error');
        }
      },
    );

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _handleNotificationTap(initialMessage);
  }

  Future<void> syncRegistration() async {
    if (!_supportsFcm) return;
    if (!await _ensureFirebaseReady()) return;

    try {
      final enabled = await NotificationSettingsService.instance
          .isSharedExpenseNotificationsEnabled();
      final token =
          enabled ? await FirebaseMessaging.instance.getToken() : null;
      await TotalsEngineClient().updatePushRegistration(
        pushToken: token,
        pushPlatform: token == null ? null : 'fcm',
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('debug: Shared expense push registration failed: $error');
      }
    }
  }

  Future<bool> _ensureFirebaseReady() async {
    if (_firebaseReady) return true;
    if (!_supportsFcm) return false;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseReady = true;
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'debug: Firebase is not configured yet; shared expense push disabled: $error',
        );
      }
      return false;
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (!_isSharedExpenseMessage(message)) return;
    // FCM does NOT auto-display the `notification` block in foreground on
    // Android. We're free to compose ours unconditionally.
    await _pullAndNotify(message, runningInBackground: false);
  }

  void _handleNotificationTap(RemoteMessage message) {
    if (!_isSharedExpenseMessage(message)) return;
    final groupId = _cleanDataValue(message.data['groupId']);
    NotificationIntentBus.instance.emit(
      OpenSharedExpensesIntent(
        groupId: groupId,
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> sharedExpenseFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  if (!SharedExpensePushNotificationService._supportsFcm) return;
  if (!_isSharedExpenseMessage(message)) return;

  DartPluginRegistrant.ensureInitialized();
  try {
    await TotalsEngineClient.ensureEnvironmentInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    // The push is only a doorbell. A notification is rendered after the
    // encrypted activity has been pulled and decrypted successfully.
    await _pullAndNotify(message, runningInBackground: true);
  } catch (error) {
    if (kDebugMode) {
      debugPrint('debug: Shared expense background push failed: $error');
    }
  }
}

Future<void> _pullAndNotify(
  RemoteMessage message, {
  required bool runningInBackground,
}) async {
  final enabled = await NotificationSettingsService.instance
      .isSharedExpenseNotificationsEnabled();
  if (!enabled) return;

  final stopwatch = Stopwatch()..start();
  final groupId = _cleanDataValue(message.data['groupId']);
  final repository = SharedExpenseRepository();

  try {
    if (groupId == null) {
      // No hint — pull every group we know about. Slower but rare.
      final groups = await repository.refreshGroups();
      // Only render explicitly in background. In foreground the coordinator
      // is already subscribed to SharedExpenseRealtimeBus, and syncGroup /
      // refreshGroups publish on every change — calling this here too would
      // race against that path and produce duplicate notifications.
      if (runningInBackground) {
        for (final group in groups) {
          await SharedExpenseNotificationCoordinator.instance
              .notifyForUnseenActivities(group);
        }
      } else {
        // Foreground catch-up: republish every group so the page picks up
        // anything refreshGroups updated.
        for (final group in groups) {
          SharedExpenseRealtimeBus.instance.publish(group);
        }
      }
      _logDoorbell('no-group-hint', stopwatch);
      return;
    }

    bool syncThrew = false;
    try {
      await repository.syncGroup(groupId);
    } catch (error) {
      syncThrew = true;
      if (kDebugMode) {
        debugPrint('debug: Shared expense syncGroup threw: $error');
      }
    }
    final group = await repository.getGroupById(groupId);
    if (group == null) {
      _logDoorbell('group-not-found', stopwatch);
      return;
    }

    if (runningInBackground) {
      await SharedExpenseNotificationCoordinator.instance
          .notifyForUnseenActivities(group);
    }
    // Foreground: syncGroup's own bus.publish already fires the page + the
    // coordinator. Republishing here added a second bus event for the same
    // payload, and the async-yield race between the two `_handleGroupUpdated`
    // runs duplicated notifications. The defensive republish is now only used
    // when syncGroup actually threw — see the syncThrew branch below.

    // Catch-up bus publish only when syncGroup threw — that's the case where
    // the apply may have committed without the bus publish firing. Otherwise
    // syncGroup already published.
    if (syncThrew) {
      SharedExpenseRealtimeBus.instance.publish(group);
    }

    // Keep the payload pending when synchronization fails. The SSE stream or
    // periodic catch-up will retry it and render the detailed notification;
    // a vague fallback would otherwise remain beside that eventual detail.
    _logDoorbell(syncThrew ? 'sync-threw' : 'ok', stopwatch);
  } catch (error) {
    if (kDebugMode) {
      debugPrint('debug: Shared expense doorbell pull failed: $error');
    }
    _logDoorbell('pull-failed', stopwatch);
  }
}

void _logDoorbell(String outcome, Stopwatch stopwatch) {
  if (kDebugMode) {
    debugPrint(
      'debug: SharedExpenseDoorbell outcome=$outcome elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
  }
}

bool _isSharedExpenseMessage(RemoteMessage message) {
  return message.data['type'] == 'shared_expense_activity';
}

String? _cleanDataValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
