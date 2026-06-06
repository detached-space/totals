import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:totals/repositories/shared_expense_repository.dart';
import 'package:totals/services/notification_intent_bus.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/shared_expense_crypto_service.dart';
import 'package:totals/services/shared_expense_push_preview_service.dart';
import 'package:totals/services/totals_engine_client.dart';

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
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    await FirebaseMessaging.instance.requestPermission();
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
      final token = enabled ? await FirebaseMessaging.instance.getToken() : null;
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
    await _showLocalNotificationForMessage(message);
  }

  void _handleNotificationTap(RemoteMessage message) {
    if (!_isSharedExpenseMessage(message)) return;
    final groupId = _cleanDataValue(message.data['groupId']);
    NotificationIntentBus.instance.emit(
      OpenSharedExpensesIntent(
        groupId: groupId,
        openActivities: groupId != null,
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
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    if (message.notification != null) return;
    await _showLocalNotificationForMessage(message);
  } catch (error) {
    if (kDebugMode) {
      debugPrint('debug: Shared expense background push failed: $error');
    }
  }
}

bool _isSharedExpenseMessage(RemoteMessage message) {
  return message.data['type'] == 'shared_expense_activity';
}

Future<void> _showLocalNotificationForMessage(RemoteMessage message) async {
  final enabled = await NotificationSettingsService.instance
      .isSharedExpenseNotificationsEnabled();
  if (!enabled) return;

  final notification = message.notification;
  final preview = await _decryptPreviewForMessage(message);
  await NotificationService.instance.showSharedExpenseEventNotification(
    eventId: preview?.eventId ??
        _cleanDataValue(message.data['payloadId']) ??
        message.messageId ??
        DateTime.now().millisecondsSinceEpoch.toString(),
    title: preview?.title ??
        notification?.title ??
        'Shared Expenses has a new update',
    body: preview?.body ??
        notification?.body ??
        _fallbackBodyForKind(message.data['kind']),
    groupId: preview?.groupId ?? _cleanDataValue(message.data['groupId']),
  );
}

Future<SharedExpensePushPreview?> _decryptPreviewForMessage(
  RemoteMessage message,
) async {
  final encryptedPreview = _cleanDataValue(
    message.data['encryptedNotificationPreview'],
  );
  final groupId = _cleanDataValue(message.data['groupId']);
  if (encryptedPreview == null || groupId == null) return null;

  try {
    final cryptoService = SharedExpenseCryptoService();
    final groupKeyHex =
        await SharedExpenseRepository().notificationGroupKey(groupId);
    if (groupKeyHex != null && groupKeyHex.isNotEmpty) {
      final preview = await SharedExpensePushPreviewService.decrypt(
        cryptoService: cryptoService,
        groupKeyHex: groupKeyHex,
        encryptedBlob: encryptedPreview,
      );
      if (preview != null) return preview;
    }

    final senderPublicKey = _cleanDataValue(message.data['senderPublicKey']);
    if (senderPublicKey == null) return null;
    final decoded = await cryptoService.decryptGroupKeyPayload(
      senderPublicKeyHex: senderPublicKey,
      encryptedBlob: encryptedPreview,
    );
    if (decoded == null ||
        decoded['type'] != 'shared_expense_push_preview_v1') {
      return null;
    }
    final preview = SharedExpensePushPreview.fromJson(decoded);
    if (preview.title.trim().isEmpty || preview.body.trim().isEmpty) {
      return null;
    }
    return preview;
  } catch (error) {
    if (kDebugMode) {
      debugPrint('debug: Failed to decrypt shared expense push preview: $error');
    }
    return null;
  }
}

String _fallbackBodyForKind(Object? rawKind) {
  final kind = _cleanDataValue(rawKind);
  if (kind == 'nudge') return 'You have a new shared expense reminder.';
  if (kind == 'join_request') {
    return 'A member is waiting for shared expense approval.';
  }
  return 'You have a new shared expense update.';
}

String? _cleanDataValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
