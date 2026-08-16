import 'package:flutter/foundation.dart';
import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/repositories/shared_expense_repository.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/shared_expense_notification_coordinator.dart';
import 'package:totals/services/totals_engine_client.dart';

void _sharedExpenseBackgroundNotificationLog(String message) {
  if (kDebugMode) {
    debugPrint('debug: SharedExpenseBackgroundNotifications: $message');
  }
}

class SharedExpenseBackgroundNotificationService {
  SharedExpenseBackgroundNotificationService._();

  static final SharedExpenseBackgroundNotificationService instance =
      SharedExpenseBackgroundNotificationService._();

  Future<void> sendMissedActivityNotificationsIfNeeded() async {
    final enabled = await NotificationSettingsService.instance
        .isSharedExpenseNotificationsEnabled();
    if (!enabled) return;

    try {
      // WorkManager runs in its own isolate, so it must load the same engine
      // configuration as the foreground app before constructing a repository.
      await TotalsEngineClient.ensureEnvironmentInitialized();
      final repository = SharedExpenseRepository();
      final beforeGroups = await repository.getGroups();
      final beforeActivityIdsByGroup = {
        for (final group in beforeGroups)
          group.id: group.activity
              .map((entry) => entry.id)
              .where((id) => id.isNotEmpty)
              .toSet(),
      };

      for (final group in beforeGroups) {
        if (group.id.isEmpty) continue;
        if (group.status == SharedExpenseGroupStatus.localOnly) continue;
        try {
          await repository.syncGroup(group.id);
        } catch (error) {
          // A payload may have been applied before an acknowledgement or later
          // request failed. Continue to the render pass so any applied activity
          // still gets its detailed notification.
          _sharedExpenseBackgroundNotificationLog(
            'sync failed for group=${group.id}: $error',
          );
        }
      }

      final refreshedGroups = await repository.getGroups();
      var detailedNotificationCandidates = 0;
      for (final group in refreshedGroups) {
        if (group.id.isEmpty) continue;
        if (group.status == SharedExpenseGroupStatus.localOnly) continue;

        final beforeIds =
            beforeActivityIdsByGroup[group.id] ?? const <String>{};
        final newEntryIds = group.activity
            .map((entry) => entry.id)
            .where((id) => id.isNotEmpty && !beforeIds.contains(id))
            .toSet();
        if (newEntryIds.isEmpty) continue;

        detailedNotificationCandidates += newEntryIds.length;
        await SharedExpenseNotificationCoordinator.instance
            .notifyForActivityIds(group, newEntryIds);
      }

      _sharedExpenseBackgroundNotificationLog(
        'rendered detailed catch-up candidates='
        '$detailedNotificationCandidates',
      );
    } catch (error, stackTrace) {
      _sharedExpenseBackgroundNotificationLog('catch-up failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
    }
  }
}
