import 'package:totals/models/budget.dart';
import 'package:totals/services/budget_service.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BudgetAlertService {
  final BudgetService _budgetService = BudgetService();

  static const int _budgetNotificationIdBase = 10000;
  static const String _alertSentPrefix = 'budget_alert_sent';

  // Check budgets against current spending and generate alerts
  Future<List<BudgetAlert>> checkBudgetAlerts() async {
    final statuses = await _budgetService.getAllBudgetStatuses();
    final alerts = <BudgetAlert>[];

    for (final status in statuses) {
      if (status.isExceeded) {
        alerts.add(BudgetAlert(
          budget: status.budget,
          status: status,
          alertType: BudgetAlertType.exceeded,
          message: _getExceededMessage(status),
        ));
      } else if (status.isApproachingLimit) {
        alerts.add(BudgetAlert(
          budget: status.budget,
          status: status,
          alertType: BudgetAlertType.approaching,
          message: _getApproachingMessage(status),
        ));
      }
    }

    return alerts;
  }

  String _getExceededMessage(BudgetStatus status) {
    final overAmount = status.spent - status.budget.amount;
    return '${status.budget.name} budget exceeded by ${_formatCurrency(overAmount)}';
  }

  String _getApproachingMessage(BudgetStatus status) {
    final percentage = status.percentageUsed.toStringAsFixed(1);
    return '${status.budget.name} budget is ${percentage}% used';
  }

  String _formatCurrency(double amount) {
    return 'ETB ${amount.toStringAsFixed(2)}';
  }

  // Send notification for budget alerts
  Future<void> sendBudgetAlertNotification(BudgetAlert alert) async {
    final enabled =
        await NotificationSettingsService.instance.isBudgetAlertsEnabled();
    if (!enabled) return;

    final alreadySent = await _hasSentAlert(alert);
    if (alreadySent) return;

    final title = alert.alertType == BudgetAlertType.exceeded
        ? 'Budget Exceeded'
        : 'Budget Warning';

    final id = _budgetNotificationIdBase + (alert.budget.id ?? 0);

    await NotificationService.instance.showBudgetAlertNotification(
      id: id,
      title: title,
      body: alert.message,
    );

    await _markAlertSent(alert);
  }

  Future<bool> _hasSentAlert(BudgetAlert alert) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_alertKey(alert)) ?? false;
  }

  Future<void> _markAlertSent(BudgetAlert alert) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alertKey(alert), true);
  }

  String _alertKey(BudgetAlert alert) {
    final budgetId = alert.budget.id ?? 0;
    final periodStart = alert.status.periodStart.millisecondsSinceEpoch;
    final type = _alertTypeKey(alert.alertType);
    return '$_alertSentPrefix:$budgetId:$type:$periodStart';
  }

  String _alertTypeKey(BudgetAlertType type) {
    switch (type) {
      case BudgetAlertType.approaching:
        return 'approaching';
      case BudgetAlertType.exceeded:
        return 'exceeded';
    }
  }

  // Check and send notifications for all budget alerts
  Future<void> checkAndNotifyBudgetAlerts() async {
    final alerts = await checkBudgetAlerts();
    for (final alert in alerts) {
      await sendBudgetAlertNotification(alert);
    }
  }

  // Check and send notification for a specific budget
  Future<void> checkAndNotifyBudgetAlert(Budget budget) async {
    try {
      final status = await _budgetService.getCurrentBudgetStatus(budget);
      if (status == null) return;

      if (status.isExceeded) {
        final alert = BudgetAlert(
          budget: budget,
          status: status,
          alertType: BudgetAlertType.exceeded,
          message: _getExceededMessage(status),
        );
        await sendBudgetAlertNotification(alert);
      } else if (status.isApproachingLimit) {
        final alert = BudgetAlert(
          budget: budget,
          status: status,
          alertType: BudgetAlertType.approaching,
          message: _getApproachingMessage(status),
        );
        await sendBudgetAlertNotification(alert);
      }
    } catch (e) {
      print('debug: Failed to check budget alert for budget ${budget.id}: $e');
    }
  }

  // Check and send notifications for budgets of a specific category
  Future<void> checkAndNotifyBudgetAlertsForCategory(int categoryId) async {
    try {
      final budgets = await _budgetService.getBudgetsByCategory(categoryId);
      for (final budget in budgets) {
        await checkAndNotifyBudgetAlert(budget);
      }
    } catch (e) {
      print('debug: Failed to check budget alerts for category $categoryId: $e');
    }
  }
}

class BudgetAlert {
  final Budget budget;
  final BudgetStatus status;
  final BudgetAlertType alertType;
  final String message;

  BudgetAlert({
    required this.budget,
    required this.status,
    required this.alertType,
    required this.message,
  });
}

enum BudgetAlertType {
  approaching,
  exceeded,
}
