import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:platform/platform.dart';
import 'package:totals/l10n/app_localizations.dart';

enum AppUpdateCheckSource { launch, manual }

class AppUpdateService {
  AppUpdateService._({Platform platform = const LocalPlatform()})
      : _platform = platform;

  static final AppUpdateService instance = AppUpdateService._();

  final Platform _platform;
  bool _hasCheckedOnLaunch = false;
  bool _isChecking = false;
  bool _isUpdateFlowActive = false;

  bool get isSupported => !kIsWeb && _platform.isAndroid;

  Future<void> checkOnLaunch(BuildContext context) async {
    if (_hasCheckedOnLaunch) return;
    _hasCheckedOnLaunch = true;
    await checkForUpdates(context, source: AppUpdateCheckSource.launch);
  }

  Future<void> checkForUpdates(
    BuildContext context, {
    required AppUpdateCheckSource source,
  }) async {
    final isManual = source == AppUpdateCheckSource.manual;
    if (_isChecking || _isUpdateFlowActive) {
      if (isManual && context.mounted) {
        _showSnackBar(
            context, context.l10nTextRead('Already checking for updates'));
      }
      return;
    }

    if (!isSupported) {
      if (isManual && context.mounted) {
        _showSnackBar(
          context,
          context.l10nTextRead(
            'Google Play updates are only available on Android.',
          ),
        );
      }
      return;
    }

    _isChecking = true;
    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (!context.mounted) return;

      if (updateInfo.installStatus == InstallStatus.downloaded) {
        _showCompleteUpdateSnackBar(context);
        return;
      }

      if (!_hasUpdate(updateInfo)) {
        if (isManual) {
          _showSnackBar(context, context.l10nTextRead('Totals is up to date.'));
        }
        return;
      }

      if (!_canStartAnyUpdate(updateInfo)) {
        if (isManual) {
          _showSnackBar(
            context,
            context.l10nTextRead(
              'Google Play cannot start this update right now.',
            ),
          );
        }
        return;
      }

      await _promptForUpdate(context, updateInfo);
    } on PlatformException catch (error) {
      if (isManual && context.mounted) {
        _showSnackBar(context, _friendlyUpdateError(context, error));
      }
      if (kDebugMode) {
        print('debug: In-app update check failed: $error');
      }
    } catch (error) {
      if (isManual && context.mounted) {
        _showSnackBar(
            context, context.l10nTextRead('Could not check for updates.'));
      }
      if (kDebugMode) {
        print('debug: In-app update check failed: $error');
      }
    } finally {
      _isChecking = false;
    }
  }

  bool _hasUpdate(AppUpdateInfo updateInfo) {
    return updateInfo.updateAvailability ==
            UpdateAvailability.updateAvailable ||
        updateInfo.updateAvailability ==
            UpdateAvailability.developerTriggeredUpdateInProgress;
  }

  bool _canStartAnyUpdate(AppUpdateInfo updateInfo) {
    return updateInfo.flexibleUpdateAllowed ||
        updateInfo.immediateUpdateAllowed;
  }

  bool _shouldUseImmediateUpdate(AppUpdateInfo updateInfo) {
    return updateInfo.immediateUpdateAllowed &&
        (updateInfo.updateAvailability ==
                UpdateAvailability.developerTriggeredUpdateInProgress ||
            updateInfo.updatePriority >= 4);
  }

  Future<void> _promptForUpdate(
    BuildContext context,
    AppUpdateInfo updateInfo,
  ) async {
    final shouldUpdate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogContext.l10nText('Update available')),
          content: Text(
            dialogContext.l10nText(
              'A newer version of Totals is available.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.l10nText('Later')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogContext.l10nText('Update now')),
            ),
          ],
        );
      },
    );

    if (shouldUpdate == true && context.mounted) {
      await _startUpdateFlow(context, updateInfo);
    }
  }

  Future<void> _startUpdateFlow(
    BuildContext context,
    AppUpdateInfo updateInfo,
  ) async {
    if (_isUpdateFlowActive) return;
    _isUpdateFlowActive = true;
    try {
      if (_shouldUseImmediateUpdate(updateInfo)) {
        await _performImmediateUpdate(context);
        return;
      }

      if (updateInfo.flexibleUpdateAllowed) {
        await _startFlexibleUpdate(context);
        return;
      }

      if (updateInfo.immediateUpdateAllowed) {
        await _performImmediateUpdate(context);
        return;
      }

      if (context.mounted) {
        _showSnackBar(
          context,
          context
              .l10nTextRead('Google Play cannot start this update right now.'),
        );
      }
    } on PlatformException catch (error) {
      if (context.mounted) {
        _showSnackBar(context, _friendlyUpdateError(context, error));
      }
      if (kDebugMode) {
        print('debug: In-app update flow failed: $error');
      }
    } catch (error) {
      if (context.mounted) {
        _showSnackBar(
            context, context.l10nTextRead('Update could not be started.'));
      }
      if (kDebugMode) {
        print('debug: In-app update flow failed: $error');
      }
    } finally {
      _isUpdateFlowActive = false;
    }
  }

  Future<void> _startFlexibleUpdate(BuildContext context) async {
    final result = await InAppUpdate.startFlexibleUpdate();
    if (!context.mounted) return;

    switch (result) {
      case AppUpdateResult.success:
        _showCompleteUpdateSnackBar(context);
        break;
      case AppUpdateResult.userDeniedUpdate:
        _showSnackBar(context, context.l10nTextRead('Update cancelled.'));
        break;
      case AppUpdateResult.inAppUpdateFailed:
        _showSnackBar(
            context, context.l10nTextRead('Update could not be started.'));
        break;
    }
  }

  Future<void> _performImmediateUpdate(BuildContext context) async {
    final result = await InAppUpdate.performImmediateUpdate();
    if (!context.mounted) return;

    switch (result) {
      case AppUpdateResult.success:
        break;
      case AppUpdateResult.userDeniedUpdate:
        _showSnackBar(context, context.l10nTextRead('Update cancelled.'));
        break;
      case AppUpdateResult.inAppUpdateFailed:
        _showSnackBar(
            context, context.l10nTextRead('Update could not be started.'));
        break;
    }
  }

  void _showCompleteUpdateSnackBar(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          context.l10nTextRead('Update downloaded. Restart to install.'),
        ),
        duration: const Duration(days: 1),
        action: SnackBarAction(
          label: context.l10nTextRead('Restart'),
          onPressed: () {
            unawaited(_completeFlexibleUpdate(context));
          },
        ),
      ),
    );
  }

  Future<void> _completeFlexibleUpdate(BuildContext context) async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } on PlatformException catch (error) {
      if (context.mounted) {
        _showSnackBar(context, _friendlyUpdateError(context, error));
      }
      if (kDebugMode) {
        print('debug: Completing in-app update failed: $error');
      }
    } catch (error) {
      if (context.mounted) {
        _showSnackBar(
            context, context.l10nTextRead('Update could not be installed.'));
      }
      if (kDebugMode) {
        print('debug: Completing in-app update failed: $error');
      }
    }
  }

  String _friendlyUpdateError(BuildContext context, PlatformException error) {
    final text = '${error.code} ${error.message ?? ''}'.toLowerCase();
    if (text.contains('api_not_available') ||
        text.contains('not available') ||
        text.contains('install')) {
      return context.l10nTextRead(
        'Update check is only available for Google Play installs.',
      );
    }
    return context.l10nTextRead('Could not check for updates.');
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
