import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/l10n/app_localizations.dart';

class SmsPermissionPrompt {
  static const String _automaticPromptDismissedKey =
      'sms_permission_privacy_prompt_dismissed';
  static const String _batteryOptimizationPromptHandledKey =
      'battery_optimization_prompt_handled';
  static Future<bool>? _activeRequest;

  static Future<bool> ensureGranted(
    BuildContext context, {
    bool userInitiated = false,
  }) {
    final activeRequest = _activeRequest;
    if (activeRequest != null) return activeRequest;

    final request = _ensureGranted(
      context,
      userInitiated: userInitiated,
    );
    _activeRequest = request;
    request.whenComplete(() {
      if (identical(_activeRequest, request)) {
        _activeRequest = null;
      }
    });
    return request;
  }

  static Future<bool> _ensureGranted(
    BuildContext context, {
    required bool userInitiated,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final currentStatus = await Permission.sms.status;
      if (currentStatus.isGranted) {
        final prefs = await SharedPreferences.getInstance();
        if (!context.mounted) return true;
        await _requestBatteryOptimizationAfterSmsGranted(
          context,
          prefs,
          showDisclosure: true,
        );
        return true;
      }
      if (!context.mounted) return false;

      final prefs = await SharedPreferences.getInstance();
      if (!userInitiated &&
          prefs.getBool(_automaticPromptDismissedKey) == true) {
        return false;
      }
      if (!context.mounted) return false;

      final requiresSettings =
          currentStatus.isPermanentlyDenied || currentStatus.isRestricted;
      final shouldContinue = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => SmsPermissionPrivacyDialog(
              requiresSettings: requiresSettings,
            ),
          ) ??
          false;
      if (!shouldContinue) {
        if (!userInitiated) {
          await prefs.setBool(_automaticPromptDismissedKey, true);
        }
        return false;
      }

      if (requiresSettings) {
        await openAppSettings();
        return false;
      }

      final requestedStatus = await Permission.sms.request();
      if (requestedStatus.isGranted) {
        await prefs.remove(_automaticPromptDismissedKey);
        if (context.mounted) {
          await _requestBatteryOptimizationAfterSmsGranted(
            context,
            prefs,
            showDisclosure: false,
          );
        }
        return true;
      }
      if (!userInitiated) {
        await prefs.setBool(_automaticPromptDismissedKey, true);
      }
      return false;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('debug: SMS permission request failed: $error');
      }
      return false;
    }
  }

  static Future<void> _requestBatteryOptimizationAfterSmsGranted(
    BuildContext context,
    SharedPreferences prefs, {
    required bool showDisclosure,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return;
      if (prefs.getBool(_batteryOptimizationPromptHandledKey) == true) {
        return;
      }

      if (showDisclosure) {
        if (!context.mounted) return;
        final shouldContinue = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const SmsPermissionPrivacyDialog(
                smsAlreadyGranted: true,
              ),
            ) ??
            false;
        if (!shouldContinue) {
          await prefs.setBool(_batteryOptimizationPromptHandledKey, true);
          return;
        }
      }

      await Permission.ignoreBatteryOptimizations.request();
      await prefs.setBool(_batteryOptimizationPromptHandledKey, true);
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'debug: Battery optimization permission request failed: $error',
        );
      }
    }
  }
}

class SmsPermissionPrivacyDialog extends StatelessWidget {
  final bool requiresSettings;
  final bool smsAlreadyGranted;

  const SmsPermissionPrivacyDialog({
    super.key,
    this.requiresSettings = false,
    this.smsAlreadyGranted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(context.l10nText('Data Stays On Device')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10nText(
                'For core transaction tracking, Totals reads and parses supported bank SMS messages locally on your device. Those SMS contents are not sent to our servers.',
              ),
            ),
            const SizedBox(height: 16),
            _PrivacyDetail(
              text: context.l10nText(
                'Your full transaction history stays on this device and is not uploaded unless you explicitly enable Data Sync. Even then, you choose which records to send and which server receives them.',
              ),
            ),
            const SizedBox(height: 10),
            _PrivacyDetail(
              text: context.l10nText(
                'Totals does not include advertising SDKs or analytics telemetry to profile you or sell your data.',
              ),
            ),
            const SizedBox(height: 10),
            _PrivacyDetail(
              text: context.l10nText(
                'Your data stays on this device by default. Optional online features, including Shared Expenses and payment verification, send only the specific information you choose to use with that feature.',
              ),
            ),
            const SizedBox(height: 10),
            _PrivacyDetail(
              text: context.l10nText(
                'If you allow SMS access, Totals will also ask Android to exclude it from battery optimization. This helps Totals process new bank messages and deliver transaction alerts reliably while the app is not open.',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10nText(
                smsAlreadyGranted
                    ? 'SMS access is already enabled. You can continue without changing the battery setting.'
                    : 'You can continue without SMS access and add transactions manually.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10nText('Not now')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            context.l10nText(
              requiresSettings
                  ? 'Open settings'
                  : smsAlreadyGranted
                      ? 'Continue'
                      : 'Allow',
            ),
          ),
        ),
      ],
    );
  }
}

class _PrivacyDetail extends StatelessWidget {
  final String text;

  const _PrivacyDetail({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium,
    );
  }
}
