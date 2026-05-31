import 'package:flutter/foundation.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/repositories/budget_repository.dart';
import 'package:totals/services/budget_service.dart';
import 'package:totals/services/budget_alert_service.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/theme/app_calendar_option.dart';

export 'package:totals/services/budget_service.dart' show BudgetStatus;

class BudgetProvider with ChangeNotifier {
  final BudgetRepository _budgetRepository = BudgetRepository();
  final BudgetService _budgetService = BudgetService();
  final BudgetAlertService _budgetAlertService = BudgetAlertService();
  TransactionProvider? _transactionProvider;

  List<Budget> _budgets = [];
  List<BudgetStatus> _budgetStatuses = [];
  bool _isLoading = false;
  String _calendar = AppCalendarOption.gregorian.storageValue;

  // Getters
  List<Budget> get budgets => _budgets;
  List<BudgetStatus> get budgetStatuses => _budgetStatuses;
  bool get isLoading => _isLoading;
  String get calendar => _calendar;

  // Set transaction provider for integration
  void setTransactionProvider(TransactionProvider provider) {
    _transactionProvider = provider;
  }

  String _normalizeCalendar(String? calendar) {
    return AppCalendarOption.fromStorage(calendar).storageValue;
  }

  Future<void> loadBudgets({String? calendar}) async {
    if (calendar != null) {
      _calendar = _normalizeCalendar(calendar);
    }
    _isLoading = true;
    notifyListeners();

    try {
      _budgets = await _budgetRepository.getActiveBudgets(calendar: _calendar);
      await _refreshBudgetStatuses();
      await _refreshBudgetWidgetSafe();
    } catch (e) {
      print("debug: Error loading budgets: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshBudgetStatuses() async {
    _budgetStatuses = await _budgetService.getAllBudgetStatuses(
      calendar: _calendar,
    );
  }

  Future<Budget> createBudget(Budget budget) async {
    try {
      final scopedBudget = budget.copyWith(calendar: _calendar);
      final id = await _budgetRepository.insertBudget(scopedBudget);
      // Get the created budget with its ID
      final createdBudget = scopedBudget.copyWith(id: id);
      await loadBudgets();
      notifyListeners();
      // Check and send notifications for the specific budget that was created
      try {
        await _budgetAlertService.checkAndNotifyBudgetAlert(createdBudget);
      } catch (e) {
        print("debug: Error checking budget alerts after creating budget: $e");
      }
      return createdBudget;
    } catch (e) {
      print("debug: Error creating budget: $e");
      rethrow;
    }
  }

  Future<Budget> updateBudget(Budget budget) async {
    try {
      final scopedBudget = budget.copyWith(calendar: _calendar);
      await _budgetRepository.updateBudget(scopedBudget);
      await loadBudgets();
      notifyListeners();
      // Check and send notifications for the specific budget that was updated
      try {
        await _budgetAlertService.checkAndNotifyBudgetAlert(scopedBudget);
      } catch (e) {
        print("debug: Error checking budget alerts after updating budget: $e");
      }
      return scopedBudget;
    } catch (e) {
      print("debug: Error updating budget: $e");
      rethrow;
    }
  }

  Future<Budget> updateBudgetForMonthOnly({
    required Budget originalBudget,
    required Budget editedBudget,
    required DateTime month,
    bool keepFutureSegment = true,
  }) async {
    try {
      final scopedEditedBudget = editedBudget.copyWith(calendar: _calendar);
      final editedBudgetId = await _budgetRepository.updateBudgetForMonthOnly(
        originalBudget: originalBudget,
        editedBudget: scopedEditedBudget,
        month: month,
        keepFutureSegment: keepFutureSegment,
      );
      await loadBudgets();
      notifyListeners();
      return scopedEditedBudget.copyWith(id: editedBudgetId);
    } catch (e) {
      print("debug: Error updating budget for month only: $e");
      rethrow;
    }
  }

  Future<void> deleteBudget(int id) async {
    try {
      await _budgetRepository.deleteBudget(id);
      await loadBudgets();
      notifyListeners();
    } catch (e) {
      print("debug: Error deleting budget: $e");
      rethrow;
    }
  }

  Future<void> deleteBudgetForMonth({
    required Budget originalBudget,
    required DateTime month,
    bool deleteFutureBudgets = false,
  }) async {
    try {
      await _budgetRepository.deleteBudgetForMonth(
        originalBudget: originalBudget,
        month: month,
        deleteFutureBudgets: deleteFutureBudgets,
      );
      await loadBudgets();
      notifyListeners();
    } catch (e) {
      print("debug: Error deleting budget for month: $e");
      rethrow;
    }
  }

  Future<void> deactivateBudget(int id) async {
    try {
      await _budgetRepository.deactivateBudget(id);
      await loadBudgets();
      notifyListeners();
    } catch (e) {
      print("debug: Error deactivating budget: $e");
      rethrow;
    }
  }

  Future<void> activateBudget(int id) async {
    try {
      await _budgetRepository.activateBudget(id);
      await loadBudgets();
      notifyListeners();
    } catch (e) {
      print("debug: Error activating budget: $e");
      rethrow;
    }
  }

  Future<List<BudgetStatus>> getBudgetsByType(String type) async {
    return await _budgetService.getBudgetStatusesByType(
      type,
      calendar: _calendar,
    );
  }

  Future<List<BudgetStatus>> getCategoryBudgets() async {
    return await _budgetService.getCategoryBudgetStatuses(calendar: _calendar);
  }

  Future<BudgetStatus?> getBudgetStatus(int budgetId) async {
    final budget = await _budgetRepository.getBudgetById(budgetId);
    if (budget == null) return null;
    return await _budgetService.getBudgetStatus(budget);
  }

  Future<void> refreshBudgetStatuses() async {
    await _refreshBudgetStatuses();
    await _refreshBudgetWidgetSafe();
    notifyListeners();
  }

  // Check for budget alerts
  Future<List<BudgetStatus>> getBudgetsNeedingAlert() async {
    await _refreshBudgetStatuses();
    return _budgetStatuses
        .where((status) => status.isApproachingLimit || status.isExceeded)
        .toList();
  }

  // Get overall budget status for a type
  Future<BudgetStatus?> getOverallBudgetStatus(String type) async {
    final budgets = await _budgetRepository.getBudgetsByType(
      type,
      calendar: _calendar,
    );
    if (budgets.isEmpty) return null;

    // For overall budgets, we might have only one active budget per type
    // If multiple exist, use the most recent one
    final budget = budgets.first;
    return await _budgetService.getBudgetStatus(budget);
  }

  Future<void> _refreshBudgetWidgetSafe() async {
    try {
      await WidgetService.refreshBudgetWidget(calendar: _calendar);
    } catch (e) {
      print("debug: Error refreshing budget widget: $e");
    }
  }
}
