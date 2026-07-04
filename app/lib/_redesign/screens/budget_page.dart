import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/screens/loans_page.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/widgets/transaction_category_sheet.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/_redesign/widgets/transaction_tile.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/bank.dart' as bank_model;
import 'package:totals/models/budget.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/budget_provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/theme/app_calendar_option.dart';
import 'package:totals/utils/app_calendar_date_utils.dart';
import 'package:totals/utils/app_date_format.dart';
import 'package:totals/utils/category_icons.dart';
import 'package:totals/utils/category_sort.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

class _BudgetCategoryColorOption {
  final String key;
  final Color color;

  const _BudgetCategoryColorOption({
    required this.key,
    required this.color,
  });
}

const List<_BudgetCategoryColorOption> _kBudgetCategoryColorOptions = [
  _BudgetCategoryColorOption(key: 'blue', color: AppColors.blue),
  _BudgetCategoryColorOption(key: 'emerald', color: AppColors.incomeSuccess),
  _BudgetCategoryColorOption(key: 'amber', color: AppColors.amber),
  _BudgetCategoryColorOption(key: 'red', color: AppColors.red),
  _BudgetCategoryColorOption(key: 'rose', color: Color(0xFFFB7185)),
  _BudgetCategoryColorOption(key: 'magenta', color: Color(0xFFD946EF)),
  _BudgetCategoryColorOption(key: 'violet', color: Color(0xFF8B5CF6)),
  _BudgetCategoryColorOption(key: 'indigo', color: Color(0xFF6366F1)),
  _BudgetCategoryColorOption(key: 'teal', color: Color(0xFF14B8A6)),
  _BudgetCategoryColorOption(key: 'mint', color: Color(0xFF34D399)),
  _BudgetCategoryColorOption(key: 'orange', color: Color(0xFFF97316)),
  _BudgetCategoryColorOption(key: 'tangerine', color: Color(0xFFFF8C42)),
  _BudgetCategoryColorOption(key: 'yellow', color: Color(0xFFEAB308)),
  _BudgetCategoryColorOption(key: 'cyan', color: Color(0xFF06B6D4)),
  _BudgetCategoryColorOption(key: 'sky', color: Color(0xFF0EA5E9)),
  _BudgetCategoryColorOption(key: 'lime', color: Color(0xFF84CC16)),
  _BudgetCategoryColorOption(key: 'pink', color: Color(0xFFEC4899)),
  _BudgetCategoryColorOption(key: 'brown', color: Color(0xFFA16207)),
  _BudgetCategoryColorOption(key: 'gray', color: Color(0xFF6B7280)),
];

const List<_BudgetCategoryColorOption> _kBudgetWidgetColorOptions = [
  _BudgetCategoryColorOption(key: 'mint', color: Color(0xFF34D399)),
  _BudgetCategoryColorOption(key: 'blue', color: Color(0xFF60A5FA)),
  _BudgetCategoryColorOption(key: 'pink', color: Color(0xFFEC4899)),
  _BudgetCategoryColorOption(key: 'violet', color: Color(0xFF8B7CF6)),
  _BudgetCategoryColorOption(key: 'amber', color: Color(0xFFF1B556)),
  _BudgetCategoryColorOption(key: 'teal', color: Color(0xFF2FB5A8)),
  _BudgetCategoryColorOption(key: 'orange', color: Color(0xFFF28C5B)),
  _BudgetCategoryColorOption(key: 'cyan', color: Color(0xFF46B8D9)),
];

const List<CategoryIconOption> _kBudgetWidgetIconOptions = categoryIconOptions;

final Set<String> _kBudgetWidgetSupportedIconKeys = categoryIconKeys;

const List<String> _kBudgetWidgetFallbackColorKeys = [
  'mint',
  'blue',
  'pink',
  'violet',
  'amber',
  'teal',
  'orange',
  'cyan',
];

// ── Compact amount formatter ────────────────────────────────────────────────

String _compactAmount(double value) {
  final abs = value.abs();
  final sign = value < 0 ? '-' : '';

  String formatUnit(double scaled, String suffix) {
    final rounded = (scaled * 10).round() / 10.0;
    final formatted = rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toStringAsFixed(1);
    return '$sign$formatted$suffix';
  }

  if (abs >= 999950) {
    return formatUnit(abs / 1000000, 'M');
  }

  if (abs >= 1000) {
    return formatUnit(abs / 1000, 'K');
  }
  return value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
}

Color _progressColorForUsage({
  required double usagePercent,
}) {
  final normalized = usagePercent.clamp(0.0, 999.0).toDouble();
  if (normalized >= 80) return AppColors.red;
  if (normalized >= 60) return AppColors.amber;
  return AppColors.incomeSuccess;
}

String? _extractLegacyBudgetColorKey(String? iconKey) {
  if (iconKey == null || iconKey.isEmpty) return null;
  const prefix = 'color:';
  if (!iconKey.startsWith(prefix)) return null;
  final value = iconKey.substring(prefix.length).trim();
  if (value.isEmpty) return null;
  return value;
}

String? _normalizeBudgetWidgetColorKey(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  for (final option in _kBudgetWidgetColorOptions) {
    if (option.key == trimmed) return trimmed;
  }
  return null;
}

Color _budgetWidgetColorFromKey(String colorKey) {
  for (final option in _kBudgetWidgetColorOptions) {
    if (option.key == colorKey) return option.color;
  }
  return _kBudgetWidgetColorOptions.first.color;
}

String? _normalizeBudgetWidgetIconKey(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.startsWith('color:')) return null;
  if (!_kBudgetWidgetSupportedIconKeys.contains(trimmed)) return null;
  return trimmed;
}

int _hashBudgetColorSeed(String value) {
  var hash = 0;
  for (final codeUnit in value.trim().toLowerCase().codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x7fffffff;
  }
  return hash;
}

// ── Bank label helper ───────────────────────────────────────────────────────

final List<bank_model.Bank> _assetBanks = _buildAssetBanks();

bank_model.Bank _canonicalMpesaBank({int id = 8}) {
  return bank_model.Bank(
    id: id,
    name: 'M Pesa',
    shortName: 'MPESA',
    codes: ['MPESA', 'M-Pesa', 'Mpesa'],
    image: 'assets/images/mpesa.png',
    uniformMasking: false,
    simBased: true,
  );
}

List<bank_model.Bank> _buildAssetBanks() {
  final banks = List<bank_model.Bank>.from(AllBanksFromAssets.getAllBanks());
  final mpesaIndex = banks.indexWhere((bank) => bank.id == 8);
  if (mpesaIndex >= 0) {
    banks[mpesaIndex] = _canonicalMpesaBank();
  } else {
    banks.insert(0, _canonicalMpesaBank());
  }
  return banks;
}

String _bankLabel(int? bankId) {
  if (bankId == null) return 'Bank';
  if (bankId == CashConstants.bankId) return CashConstants.bankShortName;
  try {
    return _assetBanks.firstWhere((b) => b.id == bankId).shortName;
  } catch (_) {
    try {
      return AppConstants.banks.firstWhere((b) => b.id == bankId).shortName;
    } catch (_) {
      return 'Bank $bankId';
    }
  }
}

String _budgetMonthLabel(BuildContext context, DateTime month) {
  return AppDateFormat.monthYear(month, context: context);
}

String _budgetDateLabel(BuildContext context, DateTime date) {
  return AppDateFormat.monthDayYear(date, context: context);
}

String _formatBudgetEtb(BuildContext context, double value) {
  return '${context.l10nText('ETB')} ${_compactAmount(value)}';
}

String _formatBudgetEtbFull(BuildContext context, double value) {
  return '${context.l10nText('ETB')} ${formatNumberWithComma(value)}';
}

int _remainingWeeksInRange({
  required DateTime rangeStart,
  required DateTime rangeEnd,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final todayStart = DateTime(current.year, current.month, current.day);
  final start = todayStart.isBefore(rangeStart)
      ? rangeStart
      : todayStart.isBefore(rangeEnd)
          ? todayStart
          : rangeEnd;
  final daysLeft = rangeEnd.difference(start).inDays;
  if (daysLeft <= 0) return 0;
  return (daysLeft / 7).ceil();
}

String _formatBudgetTransactionCount(BuildContext context, int count) {
  final unit = context.l10nText(count == 1 ? 'transaction' : 'transactions');
  return '$count $unit';
}

String _localizedBankLabel(BuildContext context, int? bankId) {
  final label = _bankLabel(bankId);
  if (bankId != null && label == 'Bank $bankId') {
    return '${context.l10nText('Bank')} $bankId';
  }
  return context.l10nText(label);
}

String _localizedBudgetCategoryLabel(BuildContext context, String label) {
  return label
      .split(' • ')
      .map((part) => context.l10nText(part.trim()))
      .join(' • ');
}

String _transactionDisplayName(
  BuildContext context,
  Transaction transaction, {
  bool isSelfTransfer = false,
}) {
  if (isSelfTransfer) return context.l10nText('Self');
  final receiver = transaction.receiver?.trim();
  if (receiver != null && receiver.isNotEmpty) return receiver;
  final creditor = transaction.creditor?.trim();
  if (creditor != null && creditor.isNotEmpty) return creditor;
  return context.l10nText('Unknown');
}

// ═══════════════════════════════════════════════════════════════════════════
// RedesignBudgetPage
// ═══════════════════════════════════════════════════════════════════════════

class RedesignBudgetPage extends StatefulWidget {
  const RedesignBudgetPage({super.key});

  @override
  State<RedesignBudgetPage> createState() => RedesignBudgetPageState();
}

class RedesignBudgetPageState extends State<RedesignBudgetPage> {
  DateTime _selectedMonth = DateTime.now();
  AppCalendarOption? _loadedBudgetCalendar;
  Budget? _detailBudget;
  bool _needsExpanded = true;
  bool _wantsExpanded = true;
  Set<int> _selectedBudgetWidgetIds = <int>{};
  Map<int, BudgetWidgetStylePreference> _budgetWidgetStylesById =
      <int, BudgetWidgetStylePreference>{};

  bool handleSystemBack() {
    if (_detailBudget == null) return false;
    setState(() => _detailBudget = null);
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bp = Provider.of<BudgetProvider>(context, listen: false);
      final tp = Provider.of<TransactionProvider>(context, listen: false);
      bp.setTransactionProvider(tp);
      _loadBudgetWidgetState();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final calendar = Provider.of<ThemeProvider>(context).appCalendar;
    if (_loadedBudgetCalendar == calendar) return;
    _loadedBudgetCalendar = calendar;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bp = Provider.of<BudgetProvider>(context, listen: false);
      bp.loadBudgets(calendar: calendar.storageValue);
      _loadBudgetWidgetState(calendar: calendar);
    });
  }

  Future<void> _loadBudgetWidgetState({AppCalendarOption? calendar}) async {
    final resolvedCalendar = calendar ?? _activeCalendar;
    final selectedIds = await WidgetService.getBudgetWidgetSelectedIds(
      calendar: resolvedCalendar.storageValue,
    );
    final stylesById = await WidgetService.getBudgetWidgetStylePreferences();
    if (!mounted) return;
    setState(() {
      _selectedBudgetWidgetIds = selectedIds.toSet();
      _budgetWidgetStylesById = stylesById;
    });
  }

  bool _isBudgetOnHomescreenWidget(Budget budget) {
    final budgetId = budget.id;
    return budgetId != null && _selectedBudgetWidgetIds.contains(budgetId);
  }

  String _widgetIconKeyForBudget(Budget budget, TransactionProvider tp) {
    final budgetId = budget.id;
    final savedIconKey = budgetId == null
        ? null
        : _normalizeBudgetWidgetIconKey(
            _budgetWidgetStylesById[budgetId]?.iconKey,
          );
    if (savedIconKey != null) {
      return savedIconKey;
    }

    final categories = budget.selectedCategoryIds
        .map(tp.getCategoryById)
        .whereType<Category>()
        .toList(growable: false);
    for (final category in categories) {
      final iconKey = _normalizeBudgetWidgetIconKey(category.iconKey);
      if (iconKey != null) {
        return iconKey;
      }
    }

    return 'more_horiz';
  }

  String _widgetColorKeyForBudget(Budget budget, TransactionProvider tp) {
    final budgetId = budget.id;
    final savedColorKey = budgetId == null
        ? null
        : _normalizeBudgetWidgetColorKey(
            _budgetWidgetStylesById[budgetId]?.colorKey,
          );
    if (savedColorKey != null) {
      return savedColorKey;
    }

    final categories = budget.selectedCategoryIds
        .map(tp.getCategoryById)
        .whereType<Category>()
        .toList(growable: false);
    for (final category in categories) {
      final categoryColorKey =
          _normalizeBudgetWidgetColorKey(category.colorKey) ??
              _normalizeBudgetWidgetColorKey(
                _extractLegacyBudgetColorKey(category.iconKey),
              );
      if (categoryColorKey != null) {
        return categoryColorKey;
      }
    }

    final seed = categories.isNotEmpty
        ? categories.map((category) => category.name).join('|')
        : budget.name;
    return _kBudgetWidgetFallbackColorKeys[
        _hashBudgetColorSeed(seed) % _kBudgetWidgetFallbackColorKeys.length];
  }

  Color _widgetBadgeColorForBudget(Budget budget, TransactionProvider tp) {
    return _budgetWidgetColorFromKey(_widgetColorKeyForBudget(budget, tp));
  }

  Future<void> _openBudgetWidgetStyleSheet(
    Budget budget,
    TransactionProvider tp,
  ) async {
    final budgetId = budget.id;
    if (budgetId == null) return;

    final preference = await showModalBottomSheet<BudgetWidgetStylePreference>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _BudgetWidgetStyleSheet(
        budgetName: budget.name,
        initialIconKey: _widgetIconKeyForBudget(budget, tp),
        initialColorKey: _widgetColorKeyForBudget(budget, tp),
      ),
    );
    if (preference == null) return;

    try {
      await WidgetService.addBudgetToWidget(
        budgetId,
        calendar: _activeCalendar.storageValue,
        stylePreference: preference,
      );
      await _loadBudgetWidgetState();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10nTextRead('Could not update widget style')}: $error',
          ),
        ),
      );
    }
  }

  // ── Month helpers ───────────────────────────────────────────────────────

  AppCalendarOption get _activeCalendar => AppDateFormat.calendarOf(context);

  DateTime get _monthStart => AppCalendarDateUtils.monthStart(
        _selectedMonth,
        calendar: _activeCalendar,
      );
  DateTime get _monthEnd => AppCalendarDateUtils.nextMonthStart(
        _selectedMonth,
        calendar: _activeCalendar,
      );
  DateTime get _monthEndInclusive =>
      _monthEnd.subtract(const Duration(milliseconds: 1));

  bool _isBudgetVisibleInSelectedMonth(Budget budget) {
    return budget.overlapsRange(_monthStart, _monthEndInclusive);
  }

  void _prevMonth() => setState(() {
        _selectedMonth = AppCalendarDateUtils.shiftMonth(
          _selectedMonth,
          -1,
          calendar: _activeCalendar,
        );
      });

  void _nextMonth() => setState(() {
        _selectedMonth = AppCalendarDateUtils.shiftMonth(
          _selectedMonth,
          1,
          calendar: _activeCalendar,
        );
      });

  // ── Spending computation ────────────────────────────────────────────────

  List<Transaction> _monthDebits(TransactionProvider tp) {
    return tp.allTransactions.where((t) {
      if (t.type != 'DEBIT') return false;
      if (t.time == null) return false;
      final dt = DateTime.tryParse(t.time!);
      if (dt == null) return false;
      return !dt.isBefore(_monthStart) && dt.isBefore(_monthEnd);
    }).toList();
  }

  double _spentForBudget(Budget b, List<Transaction> debits) {
    return debits
        .where((t) => _transactionMatchesBudget(t, b))
        .fold(0.0, (s, t) => s + t.amount);
  }

  bool _transactionMatchesBudget(Transaction transaction, Budget budget) {
    if (budget.appliesToAllExpenses) return true;
    return transaction.selectedCategoryIds.any(budget.includesCategory);
  }

  bool _isWantsBudget(Budget budget, TransactionProvider tp) {
    final categories = budget.selectedCategoryIds
        .map(tp.getCategoryById)
        .whereType<Category>()
        .toList(growable: false);
    if (categories.isEmpty) return false;
    return categories.any((c) => !c.essential);
  }

  String? _categorySummaryForBudget(Budget budget, TransactionProvider tp) {
    if (budget.appliesToAllExpenses) return 'All expenses';

    final categories = budget.selectedCategoryIds
        .map(tp.getCategoryById)
        .whereType<Category>()
        .toList(growable: false);
    if (categories.isEmpty) return null;
    return categories.map((c) => c.name).join(' • ');
  }

  bool _isRecurringBudgetInSelectedMonth(Budget budget) {
    final end = budget.endDate;
    if (end == null) return true;
    return end.isAfter(_monthEndInclusive);
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer2<BudgetProvider, TransactionProvider>(
      builder: (context, budgetProvider, transactionProvider, _) {
        final budgets = budgetProvider.budgets
            .where((budget) => budget.calendar == _activeCalendar.storageValue)
            .where(_isBudgetVisibleInSelectedMonth)
            .toList();
        final debits = _monthDebits(transactionProvider);

        if (_detailBudget != null) {
          // Verify detail budget still exists
          final still = budgets.where((b) => b.id == _detailBudget!.id);
          if (still.isEmpty) {
            _detailBudget = null;
          } else {
            _detailBudget = still.first;
          }
        }

        return PopScope<void>(
          canPop: _detailBudget == null,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || _detailBudget == null || !mounted) return;
            setState(() => _detailBudget = null);
          },
          child: Scaffold(
            backgroundColor: AppColors.background(context),
            body: SafeArea(
              child: _detailBudget != null
                  ? _buildDetailView(context, _detailBudget!, debits,
                      budgetProvider, transactionProvider)
                  : _buildListView(context, budgets, debits, budgetProvider,
                      transactionProvider),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LIST VIEW
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildListView(
    BuildContext context,
    List<Budget> budgets,
    List<Transaction> debits,
    BudgetProvider bp,
    TransactionProvider tp,
  ) {
    // Compute totals
    final totalAssigned = budgets.fold(0.0, (s, b) => s + b.amount);
    final totalActivity =
        budgets.fold(0.0, (s, b) => s + _spentForBudget(b, debits));
    final totalAvailable = totalAssigned - totalActivity;

    // Split into NEEDS / WANTS
    final needsBudgets = <Budget>[];
    final wantsBudgets = <Budget>[];
    for (final b in budgets) {
      if (_isWantsBudget(b, tp)) {
        wantsBudgets.add(b);
      } else {
        needsBudgets.add(b);
      }
    }

    final needsAvailable = needsBudgets.fold(
        0.0, (double s, b) => s + (b.amount - _spentForBudget(b, debits)));
    final wantsAvailable = wantsBudgets.fold(
        0.0, (double s, b) => s + (b.amount - _spentForBudget(b, debits)));

    // Unbudgeted spending
    final budgetedCatIds = budgets.expand((b) => b.selectedCategoryIds).toSet();
    final hasCatchAllBudget = budgets.any((b) => b.appliesToAllExpenses);
    final unbudgetedTxns = hasCatchAllBudget
        ? <Transaction>[]
        : debits.where((t) {
            if (tp.isSelfTransfer(t)) return false;
            return !t.selectedCategoryIds.any(budgetedCatIds.contains);
          }).toList();
    final unbudgetedAmount = unbudgetedTxns.fold(0.0, (s, t) => s + t.amount);

    return RefreshIndicator(
      color: AppColors.primaryLight,
      onRefresh: () => bp.loadBudgets(calendar: _activeCalendar.storageValue),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: [
          // Month navigator
          _MonthNavigator(
            month: _selectedMonth,
            onPrev: _prevMonth,
            onNext: _nextMonth,
          ),
          const SizedBox(height: 16),

          // Summary card
          if (budgets.isNotEmpty)
            _SummaryCard(
              assigned: totalAssigned,
              activity: totalActivity,
              available: totalAvailable,
            ),
          if (budgets.isNotEmpty) const SizedBox(height: 20),

          // NEEDS group
          if (needsBudgets.isNotEmpty)
            _BudgetGroupSection(
              title: 'NEEDS',
              totalAvailable: needsAvailable,
              expanded: _needsExpanded,
              onToggle: () => setState(() => _needsExpanded = !_needsExpanded),
              children: needsBudgets
                  .map((b) => _BudgetItemRow(
                        budget: b,
                        spent: _spentForBudget(b, debits),
                        categoryLabel: _categorySummaryForBudget(b, tp),
                        isOnHomescreenWidget: _isBudgetOnHomescreenWidget(b),
                        widgetBadgeColor: _widgetBadgeColorForBudget(b, tp),
                        onWidgetBadgeTap: () =>
                            _openBudgetWidgetStyleSheet(b, tp),
                        isRecurring: _isRecurringBudgetInSelectedMonth(b),
                        periodStart: _monthStart,
                        periodEnd: _monthEnd,
                        onTap: () => setState(() => _detailBudget = b),
                      ))
                  .toList(),
            ),

          // WANTS group
          if (wantsBudgets.isNotEmpty)
            _BudgetGroupSection(
              title: 'WANTS',
              totalAvailable: wantsAvailable,
              expanded: _wantsExpanded,
              onToggle: () => setState(() => _wantsExpanded = !_wantsExpanded),
              children: wantsBudgets
                  .map((b) => _BudgetItemRow(
                        budget: b,
                        spent: _spentForBudget(b, debits),
                        categoryLabel: _categorySummaryForBudget(b, tp),
                        isOnHomescreenWidget: _isBudgetOnHomescreenWidget(b),
                        widgetBadgeColor: _widgetBadgeColorForBudget(b, tp),
                        onWidgetBadgeTap: () =>
                            _openBudgetWidgetStyleSheet(b, tp),
                        isRecurring: _isRecurringBudgetInSelectedMonth(b),
                        periodStart: _monthStart,
                        periodEnd: _monthEnd,
                        onTap: () => setState(() => _detailBudget = b),
                      ))
                  .toList(),
            ),

          // Add Budget button
          const SizedBox(height: 12),
          _AddBudgetButton(
            onTap: () => _openNewBudgetForm(bp, tp),
          ),

          // Unbudgeted spending
          if (unbudgetedAmount > 0) ...[
            const SizedBox(height: 16),
            _UnbudgetedSpendingCard(
              amount: unbudgetedAmount,
              transactionCount: unbudgetedTxns.length,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _UnbudgetedTransactionsPage(
                    selectedMonth: _selectedMonth,
                    calendar: _activeCalendar,
                    budgetedCategoryIds: budgetedCatIds,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DETAIL VIEW
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildDetailView(
    BuildContext context,
    Budget budget,
    List<Transaction> debits,
    BudgetProvider bp,
    TransactionProvider tp,
  ) {
    final spent = _spentForBudget(budget, debits);
    final available = budget.amount - spent;
    final categorySummary = _categorySummaryForBudget(budget, tp);

    // Transactions for this budget
    final txns =
        debits.where((t) => _transactionMatchesBudget(t, budget)).toList();
    // Sort newest first
    txns.sort((a, b) {
      final ta = a.time != null ? DateTime.tryParse(a.time!) : null;
      final tb = b.time != null ? DateTime.tryParse(b.time!) : null;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });

    // Group by date
    final groups = <String, List<Transaction>>{};
    for (final t in txns) {
      final dt = t.time != null ? DateTime.tryParse(t.time!) : null;
      final key = dt != null
          ? _dateGroupLabel(context, dt)
          : context.l10nText('Unknown');
      groups.putIfAbsent(key, () => []).add(t);
    }

    // Days left in month
    final daysLeft = _monthEnd.difference(DateTime.now()).inDays.clamp(1, 31);
    final dailyRate = available > 0 ? available / daysLeft : 0.0;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
      children: [
        // Top bar
        _DetailTopBar(
          onBack: () => setState(() => _detailBudget = null),
          onEdit: () => _openEditBudgetForm(budget, bp, tp),
        ),
        const SizedBox(height: 8),

        // Detail summary card
        _DetailSummaryCard(
          budget: budget,
          spent: spent,
          available: available,
          categoryLabel: categorySummary,
          isRecurring: _isRecurringBudgetInSelectedMonth(budget),
          dailyRate: dailyRate,
          daysLeft: daysLeft,
        ),
        const SizedBox(height: 24),

        // TRANSACTIONS header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '${context.l10nText('TRANSACTIONS')} (${txns.length})',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        const SizedBox(height: 8),

        if (txns.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: Text(
              '${context.l10nText('No spending in')} ${context.l10nText(budget.name)} ${context.l10nText('this month')}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
          )
        else
          ...groups.entries.expand((entry) {
            final label = entry.key;
            final items = entry.value;
            return [
              _DateGroupHeader(label: label, count: items.length),
              ...items.map((t) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Builder(builder: (context) {
                      final transactionCategory =
                          tp.getCategoryById(t.categoryId);
                      return TransactionTile(
                        key: ValueKey(
                            'budget_txn_${t.reference}_${t.categoryId}'),
                        bank: _localizedBankLabel(context, t.bankId),
                        category: context.l10nText(
                          tp.categoryLabelForTransaction(
                            t,
                            uncategorizedLabel: 'Uncategorized',
                          ),
                        ),
                        categoryModel: transactionCategory,
                        personLabel: tp.loanDebtPersonNameForTransaction(t),
                        onPersonTap: (personName) => openLoansPersonPage(
                          context: context,
                          personName: personName,
                        ),
                        isCategorized: t.selectedCategoryIds.isNotEmpty,
                        isDebit: t.type?.toUpperCase() == 'DEBIT',
                        isSharing: tp.isSharingSharedExpenseTransaction(t),
                        isShared: tp.isSharedExpenseTransaction(t),
                        amount: _formatBudgetEtbFull(context, t.amount),
                        amountColor: t.type?.toUpperCase() == 'DEBIT'
                            ? AppColors.red
                            : AppColors.incomeSuccess,
                        name: _transactionDisplayName(context, t),
                        onCategoryTap: () => showTransactionCategorySheet(
                          context: context,
                          transaction: t,
                          provider: tp,
                        ),
                        onTap: () => showTransactionDetailsSheet(
                          context: context,
                          transaction: t,
                          provider: tp,
                        ),
                      );
                    }),
                  )),
            ];
          }),
      ],
    );
  }

  // ── Date grouping helper ────────────────────────────────────────────────

  String _dateGroupLabel(BuildContext context, DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);

    if (date == today) return context.l10nText('Today');
    if (date == today.subtract(const Duration(days: 1))) {
      return context.l10nText('Yesterday');
    }
    return _budgetDateLabel(context, dt);
  }

  // ── Form helpers ────────────────────────────────────────────────────────

  void _openNewBudgetForm(BudgetProvider bp, TransactionProvider tp) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewBudgetFormSheet(
        budgetProvider: bp,
        transactionProvider: tp,
        selectedMonth: _selectedMonth,
        calendar: _activeCalendar,
      ),
    ).whenComplete(() => _loadBudgetWidgetState());
  }

  void _openEditBudgetForm(
      Budget budget, BudgetProvider bp, TransactionProvider tp) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewBudgetFormSheet(
        budgetProvider: bp,
        transactionProvider: tp,
        selectedMonth: _selectedMonth,
        calendar: _activeCalendar,
        existing: budget,
      ),
    ).whenComplete(() => _loadBudgetWidgetState());
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _MonthNavigator
// ═══════════════════════════════════════════════════════════════════════════

class _MonthNavigator extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthNavigator({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final label = _budgetMonthLabel(context, month);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: onPrev,
          icon: Icon(AppIcons.chevron_left,
              color: AppColors.textPrimary(context)),
          splashRadius: 20,
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: Icon(AppIcons.chevron_right,
              color: AppColors.textPrimary(context)),
          splashRadius: 20,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _SummaryCard  (ASSIGNED | ACTIVITY | AVAILABLE + progress bar)
// ═══════════════════════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final double assigned;
  final double activity;
  final double available;

  const _SummaryCard({
    required this.assigned,
    required this.activity,
    required this.available,
  });

  @override
  Widget build(BuildContext context) {
    final progress = assigned > 0 ? (activity / assigned).clamp(0.0, 1.0) : 0.0;
    final usagePercent =
        assigned > 0 ? ((activity / assigned) * 100).toDouble() : 0.0;
    final availableColor =
        available >= 0 ? AppColors.incomeSuccess : AppColors.red;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _SummaryColumn(
                label: 'ASSIGNED',
                value: _formatBudgetEtb(context, assigned),
                color: AppColors.textPrimary(context),
              ),
              _SummaryColumn(
                label: 'ACTIVITY',
                value: _formatBudgetEtb(context, activity),
                color: AppColors.textPrimary(context),
              ),
              _SummaryColumn(
                label: 'AVAILABLE',
                value: _formatBudgetEtb(context, available),
                color: availableColor,
                highlight: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.mutedFill(context),
              valueColor: AlwaysStoppedAnimation(
                _progressColorForUsage(
                  usagePercent: usagePercent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool highlight;

  const _SummaryColumn({
    required this.label,
    required this.value,
    required this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            context.l10nText(label),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.6,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 4),
          highlight
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _BudgetGroupSection  (collapsible NEEDS / WANTS)
// ═══════════════════════════════════════════════════════════════════════════

class _BudgetGroupSection extends StatelessWidget {
  final String title;
  final double totalAvailable;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _BudgetGroupSection({
    required this.title,
    required this.totalAvailable,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final availColor =
        totalAvailable >= 0 ? AppColors.incomeSuccess : AppColors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  expanded ? AppIcons.expand_more : AppIcons.chevron_right,
                  size: 20,
                  color: AppColors.textSecondary(context),
                ),
                const SizedBox(width: 4),
                Text(
                  context.l10nText(title),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatBudgetEtb(context, totalAvailable),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: availColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...children,
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _BudgetItemRow  (dot + name, progress bar, spent, available badge)
// ═══════════════════════════════════════════════════════════════════════════

class _BudgetItemRow extends StatelessWidget {
  final Budget budget;
  final double spent;
  final String? categoryLabel;
  final bool isOnHomescreenWidget;
  final Color widgetBadgeColor;
  final VoidCallback onWidgetBadgeTap;
  final bool isRecurring;
  final DateTime periodStart;
  final DateTime periodEnd;
  final VoidCallback onTap;

  const _BudgetItemRow({
    required this.budget,
    required this.spent,
    required this.categoryLabel,
    required this.isOnHomescreenWidget,
    required this.widgetBadgeColor,
    required this.onWidgetBadgeTap,
    required this.isRecurring,
    required this.periodStart,
    required this.periodEnd,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        budget.amount > 0 ? (spent / budget.amount).clamp(0.0, 1.0) : 0.0;
    final usagePercent =
        budget.amount > 0 ? ((spent / budget.amount) * 100).toDouble() : 0.0;
    final progressColor = _progressColorForUsage(
      usagePercent: usagePercent,
    );
    final available = budget.amount - spent;
    final weeksLeft = _remainingWeeksInRange(
      rangeStart: periodStart,
      rangeEnd: periodEnd,
    );
    final weeklyAmount =
        available > 0 && weeksLeft > 0 ? available / weeksLeft : 0.0;
    final weeklyRateText =
        '${_formatBudgetEtb(context, weeklyAmount)}/${context.l10nText('week')} ${context.l10nText('left')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                context.l10nText(budget.name),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isOnHomescreenWidget) ...[
                              _BudgetWidgetBadge(
                                color: widgetBadgeColor,
                                onTap: onWidgetBadgeTap,
                              ),
                              const SizedBox(width: 6),
                            ],
                            _BudgetRecurrenceBadge(isRecurring: isRecurring),
                          ],
                        ),
                        if (categoryLabel != null &&
                            categoryLabel!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          _AutoMarqueeText(
                            text: _localizedBudgetCategoryLabel(
                              context,
                              categoryLabel!,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: AppColors.mutedFill(context),
                  valueColor: AlwaysStoppedAnimation(progressColor),
                ),
              ),
              const SizedBox(height: 10),
              // Spent + assigned
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _BudgetFooterBadge(
                        label: _formatBudgetEtb(context, spent),
                        backgroundColor: progressColor.withValues(alpha: 0.1),
                        foregroundColor: progressColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(
                      weeklyRateText,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _BudgetFooterBadge(
                        label: _formatBudgetEtb(context, budget.amount),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetFooterBadge extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const _BudgetFooterBadge({
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.mutedFill(context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foregroundColor ?? AppColors.textPrimary(context),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _AddBudgetButton  (dashed border)
// ═══════════════════════════════════════════════════════════════════════════

class _AddBudgetButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddBudgetButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.borderColor(context),
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Text(
            context.l10nText('+ Add Budget'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _UnbudgetedSpendingCard
// ═══════════════════════════════════════════════════════════════════════════

class _UnbudgetedSpendingCard extends StatelessWidget {
  final double amount;
  final int transactionCount;
  final VoidCallback onTap;

  const _UnbudgetedSpendingCard({
    required this.amount,
    required this.transactionCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10nText('SPENDING WITHOUT A BUDGET'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_formatBudgetEtb(context, amount)} ${context.l10nText('from')} ${_formatBudgetTransactionCount(context, transactionCount)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              AppIcons.chevron_right,
              size: 20,
              color: AppColors.textTertiary(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _UnbudgetedTransactionsPage
// ═══════════════════════════════════════════════════════════════════════════

class _UnbudgetedTransactionsPage extends StatelessWidget {
  final DateTime selectedMonth;
  final AppCalendarOption calendar;
  final Set<int> budgetedCategoryIds;

  const _UnbudgetedTransactionsPage({
    required this.selectedMonth,
    required this.calendar,
    required this.budgetedCategoryIds,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(AppIcons.arrow_back_rounded),
        ),
        title: Text(
          context.l10nText('Unbudgeted Spending'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
      ),
      body: Consumer<TransactionProvider>(
        builder: (context, provider, _) {
          final monthStart = AppCalendarDateUtils.monthStart(
            selectedMonth,
            calendar: calendar,
          );
          final monthEnd = AppCalendarDateUtils.nextMonthStart(
            selectedMonth,
            calendar: calendar,
          );
          final transactions = provider.allTransactions.where((t) {
            if (t.type != 'DEBIT') return false;
            if (t.time == null) return false;
            final dt = DateTime.tryParse(t.time!);
            if (dt == null) return false;
            if (dt.isBefore(monthStart) || !dt.isBefore(monthEnd)) return false;
            if (provider.isSelfTransfer(t)) return false;
            return !t.selectedCategoryIds.any(budgetedCategoryIds.contains);
          }).toList()
            ..sort((a, b) {
              final ta = a.time != null ? DateTime.tryParse(a.time!) : null;
              final tb = b.time != null ? DateTime.tryParse(b.time!) : null;
              if (ta == null && tb == null) return 0;
              if (ta == null) return 1;
              if (tb == null) return -1;
              return tb.compareTo(ta);
            });

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              // Hint text
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  context.l10nText(
                    'These transactions aren\'t tracked by any budget. Categorize them to include in your budgets.',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),

              if (transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    context.l10nText(
                      'No unbudgeted transactions for this month.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                )
              else
                ...transactions.map((t) {
                  final cat = provider.getCategoryById(t.categoryId);
                  final isSelfTransfer = provider.isSelfTransfer(t);
                  final isMisc = cat?.uncategorized == true;
                  final categoryLabel = isSelfTransfer
                      ? 'Self'
                      : provider.categoryLabelForTransaction(
                          t,
                          uncategorizedLabel: 'Categorize',
                        );
                  final isCategorized =
                      isSelfTransfer || t.selectedCategoryIds.isNotEmpty;
                  final isCredit = t.type == 'CREDIT';

                  return TransactionTile(
                    bank: _localizedBankLabel(context, t.bankId),
                    category: context.l10nText(categoryLabel),
                    categoryModel: cat,
                    personLabel: provider.loanDebtPersonNameForTransaction(t),
                    onPersonTap: (personName) => openLoansPersonPage(
                      context: context,
                      personName: personName,
                    ),
                    isCategorized: isCategorized,
                    isDebit: !isCredit,
                    isSelfTransfer: isSelfTransfer,
                    isMisc: isMisc,
                    isSharing: provider.isSharingSharedExpenseTransaction(t),
                    isShared: provider.isSharedExpenseTransaction(t),
                    amount: _formatBudgetEtbFull(context, t.amount),
                    amountColor:
                        isCredit ? AppColors.incomeSuccess : AppColors.red,
                    name: _transactionDisplayName(
                      context,
                      t,
                      isSelfTransfer: isSelfTransfer,
                    ),
                    onCategoryTap: () => showTransactionCategorySheet(
                      context: context,
                      transaction: t,
                      provider: provider,
                    ),
                    onTap: () => showTransactionDetailsSheet(
                      context: context,
                      transaction: t,
                      provider: provider,
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DETAIL VIEW WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _DetailTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onEdit;

  const _DetailTopBar({required this.onBack, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(AppIcons.chevron_left, size: 20),
            label: Text(context.l10nText('Back')),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryLight,
              textStyle:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onEdit,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryLight,
              textStyle:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: Text(context.l10nText('Edit')),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _DetailSummaryCard
// ═══════════════════════════════════════════════════════════════════════════

class _DetailSummaryCard extends StatelessWidget {
  final Budget budget;
  final double spent;
  final double available;
  final String? categoryLabel;
  final bool isRecurring;
  final double dailyRate;
  final int daysLeft;

  const _DetailSummaryCard({
    required this.budget,
    required this.spent,
    required this.available,
    required this.categoryLabel,
    required this.isRecurring,
    required this.dailyRate,
    required this.daysLeft,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        budget.amount > 0 ? (spent / budget.amount).clamp(0.0, 1.0) : 0.0;
    final usagePercent =
        budget.amount > 0 ? ((spent / budget.amount) * 100).toDouble() : 0.0;
    final progressColor = _progressColorForUsage(
      usagePercent: usagePercent,
    );
    final availableColor =
        available >= 0 ? AppColors.incomeSuccess : AppColors.red;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        children: [
          // Name + badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  context.l10nText(budget.name),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _BudgetRecurrenceBadge(isRecurring: isRecurring),
            ],
          ),
          if (categoryLabel != null && categoryLabel!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: _AutoMarqueeText(
                text: _localizedBudgetCategoryLabel(context, categoryLabel!),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // ASSIGNED | ACTIVITY | AVAILABLE
          Row(
            children: [
              _SummaryColumn(
                label: 'ASSIGNED',
                value: _formatBudgetEtb(context, budget.amount),
                color: AppColors.textPrimary(context),
              ),
              _SummaryColumn(
                label: 'ACTIVITY',
                value: _formatBudgetEtb(context, spent),
                color: AppColors.textPrimary(context),
              ),
              _SummaryColumn(
                label: 'AVAILABLE',
                value: _formatBudgetEtb(context, available),
                color: availableColor,
                highlight: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.mutedFill(context),
              valueColor: AlwaysStoppedAnimation(
                progressColor,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Daily rate
          Text(
            '${_formatBudgetEtb(context, dailyRate)}/${context.l10nText('day')} ${context.l10nText('for')} $daysLeft ${context.l10nText(daysLeft == 1 ? 'day left' : 'days left')}',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _DateGroupHeader
// ═══════════════════════════════════════════════════════════════════════════

class _DateGroupHeader extends StatelessWidget {
  final String label;
  final int count;

  const _DateGroupHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        '$label ($count)',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary(context),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _NewBudgetFormSheet (previous full-featured form style)
// ═══════════════════════════════════════════════════════════════════════════

class _NewBudgetFormSheet extends StatefulWidget {
  final BudgetProvider budgetProvider;
  final TransactionProvider transactionProvider;
  final DateTime selectedMonth;
  final AppCalendarOption calendar;
  final Budget? existing;

  const _NewBudgetFormSheet({
    required this.budgetProvider,
    required this.transactionProvider,
    required this.selectedMonth,
    required this.calendar,
    this.existing,
  });

  @override
  State<_NewBudgetFormSheet> createState() => _NewBudgetFormSheetState();
}

class _NewBudgetFormSheetState extends State<_NewBudgetFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _alertController;
  late String _selectedPeriod;
  late String _selectedGroup; // 'needs' or 'wants'
  final Set<int> _selectedCategoryIds = <int>{};
  late bool _rollover;
  bool _isSaving = false;
  bool _uniqueToSelectedMonth = false;
  bool _applyToFutureBudgets = true;
  bool _createFutureBudgets = false;
  bool _endRecurringAtSelectedMonth = false;
  bool _showNewCategoryComposer = false;
  bool _showCategoryColorChoices = false;
  String _draftCategoryColorKey = _kBudgetCategoryColorOptions.first.key;
  final TextEditingController _newCategoryController = TextEditingController();
  final FocusNode _newCategoryFocus = FocusNode();
  final ScrollController _formScrollController = ScrollController();
  double _lastKeyboardInset = 0;
  Set<int> _selectedBudgetWidgetIds = <int>{};
  bool _isHomescreenWidgetStateLoading = true;
  bool _showOnHomescreenWidget = false;
  String _selectedWidgetIconKey = 'more_horiz';
  String _selectedWidgetColorKey = 'mint';

  bool get _isEdit => widget.existing != null;
  DateTime get _selectedMonthStart => AppCalendarDateUtils.monthStart(
        widget.selectedMonth,
        calendar: widget.calendar,
      );
  DateTime get _selectedMonthEnd => AppCalendarDateUtils.nextMonthStart(
        widget.selectedMonth,
        calendar: widget.calendar,
      ).subtract(const Duration(seconds: 1));
  bool get _hasFutureBudgetsToUpdate {
    final existing = widget.existing;
    if (existing == null) return false;
    return existing.endDate == null ||
        existing.endDate!.isAfter(_selectedMonthEnd);
  }

  bool get _isSingleMonthBudgetInSelectedMonth {
    final existing = widget.existing;
    if (existing == null || _hasFutureBudgetsToUpdate) return false;
    final endDate = existing.endDate;
    if (endDate == null) return false;
    return !endDate.isBefore(_selectedMonthStart) &&
        !endDate.isAfter(_selectedMonthEnd);
  }

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _nameController = TextEditingController(text: b?.name ?? '');
    _amountController = TextEditingController(
      text: b != null ? b.amount.toStringAsFixed(0) : '',
    );
    _alertController = TextEditingController(
      text: b != null ? b.alertThreshold.toStringAsFixed(0) : '80',
    );
    _selectedCategoryIds.addAll(b?.selectedCategoryIds ?? const <int>[]);
    _rollover = b?.rollover ?? false;

    // Determine group from existing category
    if (b != null && b.selectedCategoryIds.isNotEmpty) {
      final selectedCats = b.selectedCategoryIds
          .map(widget.transactionProvider.getCategoryById)
          .whereType<Category>()
          .toList();
      _selectedGroup =
          selectedCats.any((c) => !c.essential) ? 'wants' : 'needs';
    } else {
      _selectedGroup = 'needs';
    }

    if (b != null) {
      if (b.type == 'category') {
        _selectedPeriod = b.timeFrame ?? 'monthly';
      } else {
        _selectedPeriod = b.type;
      }
    } else {
      _selectedPeriod = 'monthly';
    }

    _selectedWidgetIconKey = _resolveDefaultWidgetIconKey();
    _selectedWidgetColorKey = _resolveDefaultWidgetColorKey();
    _loadHomescreenWidgetState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _alertController.dispose();
    _newCategoryController.dispose();
    _newCategoryFocus.dispose();
    _formScrollController.dispose();
    super.dispose();
  }

  List<Category> get _filteredCategories {
    final isNeeds = _selectedGroup == 'needs';
    return sortCategoriesAlphabetically(widget.transactionProvider.categories
        .where((c) =>
            c.flow == 'expense' && !c.uncategorized && c.essential == isNeeds));
  }

  String? _extractColorKey(String? iconKey) {
    if (iconKey == null || iconKey.isEmpty) return null;
    const prefix = 'color:';
    if (!iconKey.startsWith(prefix)) return null;
    final value = iconKey.substring(prefix.length).trim();
    if (value.isEmpty) return null;
    return value;
  }

  Color _colorFromKey(String colorKey) {
    for (final option in _kBudgetCategoryColorOptions) {
      if (option.key == colorKey) return option.color;
    }
    return _kBudgetCategoryColorOptions.first.color;
  }

  int _fallbackColorIndex(Category category) {
    final seed = '${category.flow}:${category.name.toLowerCase()}';
    int hash = 0;
    for (final code in seed.codeUnits) {
      hash = (hash + code) & 0x7fffffff;
    }
    return hash % _kBudgetCategoryColorOptions.length;
  }

  Color _categoryChipColor(Category category) {
    final explicitColorKey = _normalizeColorKey(category.colorKey) ??
        _extractColorKey(category.iconKey);
    if (explicitColorKey != null) {
      return _colorFromKey(explicitColorKey);
    }
    return _kBudgetCategoryColorOptions[_fallbackColorIndex(category)].color;
  }

  String? _normalizeColorKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String? _normalizeWidgetColorKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    for (final option in _kBudgetWidgetColorOptions) {
      if (option.key == trimmed) return trimmed;
    }
    return null;
  }

  String? _normalizeWidgetIconKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.startsWith('color:')) return null;
    if (!_kBudgetWidgetSupportedIconKeys.contains(trimmed)) return null;
    return trimmed;
  }

  String _resolveDefaultWidgetIconKey() {
    for (final categoryId in _selectedCategoryIds) {
      final category = widget.transactionProvider.getCategoryById(categoryId);
      final iconKey = _normalizeWidgetIconKey(category?.iconKey);
      if (iconKey != null) return iconKey;
    }
    return 'more_horiz';
  }

  String _resolveDefaultWidgetColorKey() {
    for (final categoryId in _selectedCategoryIds) {
      final category = widget.transactionProvider.getCategoryById(categoryId);
      final colorKey = _normalizeWidgetColorKey(category?.colorKey) ??
          _normalizeWidgetColorKey(_extractColorKey(category?.iconKey));
      if (colorKey != null) return colorKey;
    }

    final seed = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'budget';
    var hash = 0;
    for (final codeUnit in seed.toLowerCase().codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return _kBudgetWidgetFallbackColorKeys[
        hash % _kBudgetWidgetFallbackColorKeys.length];
  }

  Color _widgetColorFromKey(String colorKey) {
    for (final option in _kBudgetWidgetColorOptions) {
      if (option.key == colorKey) return option.color;
    }
    return _kBudgetWidgetColorOptions.first.color;
  }

  Category? _findCategoryByName({
    required String name,
    required String flow,
    Set<int>? excludeIds,
  }) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedFlow = flow.toLowerCase();
    return widget.transactionProvider.categories
        .where((c) =>
            c.flow.toLowerCase() == normalizedFlow &&
            c.name.trim().toLowerCase() == normalizedName &&
            (c.id == null || !(excludeIds?.contains(c.id) ?? false)))
        .fold<Category?>(
          null,
          (best, current) => best == null || (current.id ?? 0) > (best.id ?? 0)
              ? current
              : best,
        );
  }

  int? get _existingBudgetId => widget.existing?.id;

  bool get _isExistingBudgetSelectedOnWidget {
    final existingBudgetId = _existingBudgetId;
    return existingBudgetId != null &&
        _selectedBudgetWidgetIds.contains(existingBudgetId);
  }

  int get _draftSelectedWidgetCount {
    var count = _selectedBudgetWidgetIds.length;
    if (_isExistingBudgetSelectedOnWidget && !_showOnHomescreenWidget) {
      count -= 1;
    } else if (!_isExistingBudgetSelectedOnWidget && _showOnHomescreenWidget) {
      count += 1;
    }
    return count.clamp(0, WidgetService.maxBudgetWidgetBudgets);
  }

  int get _draftWidgetSpotsLeft {
    return (WidgetService.maxBudgetWidgetBudgets - _draftSelectedWidgetCount)
        .clamp(0, WidgetService.maxBudgetWidgetBudgets);
  }

  bool get _canEnableHomescreenWidgetToggle {
    return _showOnHomescreenWidget || _draftWidgetSpotsLeft > 0;
  }

  Future<void> _loadHomescreenWidgetState() async {
    final selectedIds = await WidgetService.getBudgetWidgetSelectedIds(
      calendar: widget.calendar.storageValue,
    );
    final existingBudgetId = _existingBudgetId;
    final stylePreference = existingBudgetId == null
        ? null
        : await WidgetService.getBudgetWidgetStylePreference(existingBudgetId);
    if (!mounted) return;

    final selectedSet = selectedIds.toSet();
    setState(() {
      _selectedBudgetWidgetIds = selectedSet;
      _showOnHomescreenWidget =
          existingBudgetId != null && selectedSet.contains(existingBudgetId);
      _selectedWidgetIconKey =
          _normalizeWidgetIconKey(stylePreference?.iconKey) ??
              _resolveDefaultWidgetIconKey();
      _selectedWidgetColorKey =
          _normalizeWidgetColorKey(stylePreference?.colorKey) ??
              _resolveDefaultWidgetColorKey();
      _isHomescreenWidgetStateLoading = false;
    });
  }

  Future<String?> _syncHomescreenWidgetSelection(Budget savedBudget) async {
    if (_isHomescreenWidgetStateLoading) return null;

    final savedBudgetId = savedBudget.id;
    final originalBudgetId = _existingBudgetId;
    final originallySelected = _isExistingBudgetSelectedOnWidget;

    if (!_showOnHomescreenWidget) {
      if (savedBudgetId != null) {
        await WidgetService.removeBudgetFromWidget(
          savedBudgetId,
          calendar: widget.calendar.storageValue,
        );
      }
      if (originallySelected &&
          originalBudgetId != null &&
          originalBudgetId != savedBudgetId) {
        await WidgetService.removeBudgetFromWidget(
          originalBudgetId,
          calendar: widget.calendar.storageValue,
        );
      }
      return null;
    }

    if (savedBudgetId == null) {
      return 'Budget saved, but the homescreen widget selection could not be applied.';
    }

    if (originallySelected &&
        originalBudgetId != null &&
        originalBudgetId != savedBudgetId) {
      await WidgetService.removeBudgetFromWidget(
        originalBudgetId,
        calendar: widget.calendar.storageValue,
      );
    }

    final addResult = await WidgetService.addBudgetToWidget(
      savedBudgetId,
      calendar: widget.calendar.storageValue,
      stylePreference: BudgetWidgetStylePreference(
        iconKey: _selectedWidgetIconKey,
        colorKey: _selectedWidgetColorKey,
      ),
    );
    switch (addResult) {
      case BudgetWidgetSelectionResult.added:
        return null;
      case BudgetWidgetSelectionResult.alreadySelected:
        return null;
      case BudgetWidgetSelectionResult.limitReached:
        return 'Budget saved, but the homescreen widget is already using all 3 spots.';
    }
  }

  bool _categoryExistsForFlow({
    required String name,
    required String flow,
  }) {
    return _findCategoryByName(name: name, flow: flow) != null;
  }

  void _toggleNewCategoryComposer() {
    final shouldShow = !_showNewCategoryComposer;
    setState(() {
      _showNewCategoryComposer = shouldShow;
      _showCategoryColorChoices = false;
      if (!shouldShow) {
        _newCategoryController.clear();
      }
    });
    if (shouldShow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _newCategoryFocus.requestFocus();
        _scrollComposerIntoView();
      });
    } else {
      _newCategoryFocus.unfocus();
    }
  }

  void _toggleColorChoices() {
    setState(() => _showCategoryColorChoices = !_showCategoryColorChoices);
  }

  void _scrollComposerIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_formScrollController.hasClients) return;
      final maxExtent = _formScrollController.position.maxScrollExtent;
      final target = (maxExtent - 36).clamp(0.0, maxExtent).toDouble();
      _formScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _dismissKeyboardOnOutsideTap(PointerDownEvent event) {
    final focusedNode = FocusManager.instance.primaryFocus;
    final focusedContext = focusedNode?.context;
    if (focusedNode == null || focusedContext == null) return;

    final renderObject = focusedContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      focusedNode.unfocus();
      return;
    }

    final focusedBounds =
        renderObject.localToGlobal(Offset.zero) & renderObject.size;
    if (!focusedBounds.contains(event.position)) {
      focusedNode.unfocus();
    }
  }

  Future<void> _createCategoryInline() async {
    final createdName = _newCategoryController.text.trim();
    if (createdName.isEmpty) return;
    const flow = 'expense';
    if (_categoryExistsForFlow(name: createdName, flow: flow)) {
      _newCategoryFocus.requestFocus();
      setState(() {});
      return;
    }

    final knownCategoryIds = widget.transactionProvider.categories
        .map((c) => c.id)
        .whereType<int>()
        .toSet();
    final isEssential = _selectedGroup == 'needs';

    try {
      await widget.transactionProvider.createCategory(
        name: createdName,
        essential: isEssential,
        flow: flow,
        colorKey: _draftCategoryColorKey,
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().toLowerCase();
      if (message.contains('unique') ||
          message.contains('constraint') ||
          message.contains('already exists')) {
        _newCategoryFocus.requestFocus();
        setState(() {});
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.l10nTextRead('Could not create category'))),
      );
      return;
    }

    if (!mounted) return;
    final createdCategory = _findCategoryByName(
      name: createdName,
      flow: flow,
      excludeIds: knownCategoryIds,
    );
    final target =
        createdCategory ?? _findCategoryByName(name: createdName, flow: flow);

    setState(() {
      _showNewCategoryComposer = false;
      _showCategoryColorChoices = false;
      _newCategoryController.clear();
      if (target?.id != null) {
        _selectedCategoryIds.add(target!.id!);
      }
    });
    _newCategoryFocus.unfocus();
  }

  Widget _buildHomescreenWidgetStyleSection(ThemeData theme) {
    final selectedColor = _widgetColorFromKey(_selectedWidgetColorKey);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(
            height: 1,
            color: AppColors.borderColor(context),
          ),
          const SizedBox(height: 14),
          Text(
            context.l10nText('Icon'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _kBudgetWidgetIconOptions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: 42,
              ),
              itemBuilder: (context, index) {
                final option = _kBudgetWidgetIconOptions[index];
                final selected = option.key == _selectedWidgetIconKey;
                return Tooltip(
                  message: context.l10nText(option.label),
                  child: Material(
                    color: selected
                        ? selectedColor.withValues(alpha: 0.15)
                        : AppColors.surfaceColor(context),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() => _selectedWidgetIconKey = option.key);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? selectedColor
                                : AppColors.borderColor(context),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          option.icon,
                          size: 20,
                          color: selected
                              ? selectedColor
                              : AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10nText('Swipe sideways to see more icons.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.l10nText('Color'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kBudgetWidgetColorOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final option = _kBudgetWidgetColorOptions[index];
                final selected = option.key == _selectedWidgetColorKey;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedWidgetColorKey = option.key);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: option.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppColors.textPrimary(context)
                            : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: option.color.withValues(alpha: 0.28),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedMonthLabel = _budgetMonthLabel(context, _selectedMonthStart);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final expenseCategories = _filteredCategories;
    final keyboardScrollBuffer = bottomInset > 0 && _showNewCategoryComposer
        ? (_showCategoryColorChoices ? 60.0 : 40.0)
        : 0.0;
    if (bottomInset > _lastKeyboardInset && _showNewCategoryComposer) {
      _scrollComposerIntoView();
    }
    _lastKeyboardInset = bottomInset;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _dismissKeyboardOnOutsideTap,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: AppColors.background(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Text(
                      _isEdit
                          ? context.l10nText('Edit Budget')
                          : context.l10nText('Create Budget'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(AppIcons.close),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.borderColor(context)),
              Flexible(
                child: SingleChildScrollView(
                  controller: _formScrollController,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    24 + bottomInset + keyboardScrollBuffer,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name
                        Text(
                          context.l10nText('Name'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nameController,
                          decoration: _inputDecoration(
                              context, 'e.g. Monthly groceries'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? context.l10nText('Required')
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Amount
                        Text(
                          context.l10nText('Amount'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration(context, '0').copyWith(
                            prefixText: '${context.l10nText('ETB')}  ',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return context.l10nText('Required');
                            }
                            final n = double.tryParse(v.trim());
                            if (n == null || n <= 0) {
                              return context.l10nText('Enter a valid amount');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Group (Needs / Wants)
                        Text(
                          context.l10nText('Group'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _GroupToggle(
                          selected: _selectedGroup,
                          onChanged: (v) {
                            _newCategoryFocus.unfocus();
                            setState(() {
                              _selectedGroup = v;
                              _showNewCategoryComposer = false;
                              _showCategoryColorChoices = false;
                              _newCategoryController.clear();
                              // Keep only categories valid for the new group.
                              final allowedIds = _filteredCategories
                                  .map((c) => c.id)
                                  .whereType<int>()
                                  .toSet();
                              _selectedCategoryIds.removeWhere(
                                  (id) => !allowedIds.contains(id));
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // // Period
                        // Text(
                        //   'Period',
                        //   style: theme.textTheme.labelMedium?.copyWith(
                        //     color: AppColors.textSecondary(context),
                        //     fontWeight: FontWeight.w600,
                        //   ),
                        // ),
                        // const SizedBox(height: 6),
                        // _PeriodToggle(
                        //   selected: _selectedPeriod,
                        //   onChanged: (v) =>
                        //       setState(() => _selectedPeriod = v),
                        // ),
                        // const SizedBox(height: 16),

                        // Category
                        Text(
                          context.l10nText('Categories (optional)'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _CategoryChipButton(
                              label: 'None',
                              color: AppColors.textTertiary(context),
                              selected: _selectedCategoryIds.isEmpty,
                              showColorDot: false,
                              onTap: () =>
                                  setState(() => _selectedCategoryIds.clear()),
                            ),
                            ...expenseCategories.map((cat) {
                              final catId = cat.id;
                              final isSelected = catId != null &&
                                  _selectedCategoryIds.contains(catId);
                              return _CategoryChipButton(
                                label: cat.name,
                                color: _categoryChipColor(cat),
                                selected: isSelected,
                                onTap: () {
                                  if (catId == null) return;
                                  setState(() {
                                    if (isSelected) {
                                      _selectedCategoryIds.remove(catId);
                                    } else {
                                      _selectedCategoryIds.add(catId);
                                    }
                                  });
                                },
                              );
                            }),
                            _CategoryChipButton(
                              label:
                                  _showNewCategoryComposer ? 'Cancel' : '+ New',
                              color: _showNewCategoryComposer
                                  ? AppColors.red
                                  : AppColors.textSecondary(context),
                              selected: false,
                              showColorDot: false,
                              isAction: true,
                              onTap: _toggleNewCategoryComposer,
                            ),
                          ],
                        ),
                        if (_showNewCategoryComposer)
                          _buildNewCategoryComposer(),
                        const SizedBox(height: 16),

                        if (!_isEdit) ...[
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceColor(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SwitchListTile(
                              title: Text(
                                '${context.l10nText('Only for')} $selectedMonthLabel',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textPrimary(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                context.l10nText(
                                  'Keep this budget unique to this month only',
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              value: _uniqueToSelectedMonth,
                              onChanged: (v) =>
                                  setState(() => _uniqueToSelectedMonth = v),
                              activeColor: AppColors.primaryLight,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (_isEdit && _hasFutureBudgetsToUpdate) ...[
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceColor(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SwitchListTile(
                              title: Text(
                                '${context.l10nText('Make')} $selectedMonthLabel ${context.l10nText('the last month')}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textPrimary(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                context.l10nText(
                                  'Stop this recurring budget after this month',
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              value: _endRecurringAtSelectedMonth,
                              onChanged: (v) => setState(
                                  () => _endRecurringAtSelectedMonth = v),
                              activeColor: AppColors.primaryLight,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (_isEdit && _isSingleMonthBudgetInSelectedMonth) ...[
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceColor(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SwitchListTile(
                              title: Text(
                                context.l10nText(
                                  'Create for future months too',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textPrimary(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                context.l10nText(
                                  'Turn this into a recurring budget',
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              value: _createFutureBudgets,
                              onChanged: (v) =>
                                  setState(() => _createFutureBudgets = v),
                              activeColor: AppColors.primaryLight,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (_isEdit && _hasFutureBudgetsToUpdate) ...[
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceColor(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SwitchListTile(
                              title: Text(
                                context.l10nText(
                                  'Apply to future budgets too',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textPrimary(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                '${context.l10nText('Turn off to change only')} $selectedMonthLabel',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              value: _applyToFutureBudgets,
                              onChanged: _endRecurringAtSelectedMonth
                                  ? null
                                  : (v) =>
                                      setState(() => _applyToFutureBudgets = v),
                              activeColor: AppColors.primaryLight,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Alert threshold
                        Text(
                          context.l10nText('Alert threshold'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _alertController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration(context, '80').copyWith(
                            suffixText: '%',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return context.l10nText('Required');
                            }
                            final n = double.tryParse(v.trim());
                            if (n == null || n < 1 || n > 100) {
                              return '1-100';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Rollover
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceColor(context),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SwitchListTile(
                            title: Text(
                              context.l10nText('Rollover unused budget'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textPrimary(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              context.l10nText(
                                'Carry remaining budget to the next period',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                            value: _rollover,
                            onChanged: (v) => setState(() => _rollover = v),
                            activeColor: AppColors.primaryLight,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceColor(context),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              SwitchListTile(
                                title: Text(
                                  context.l10nText('Show on homescreen widget'),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textPrimary(context),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  _isHomescreenWidgetStateLoading
                                      ? context.l10nText(
                                          'Checking available widget spots...',
                                        )
                                      : '${_draftWidgetSpotsLeft.toInt()} ${context.l10nText(_draftWidgetSpotsLeft == 1 ? 'spot' : 'spots')} ${context.l10nText('left on the homescreen widget')}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary(context),
                                  ),
                                ),
                                value: _showOnHomescreenWidget,
                                onChanged: _isHomescreenWidgetStateLoading ||
                                        _isSaving
                                    ? null
                                    : (value) {
                                        if (value &&
                                            !_canEnableHomescreenWidgetToggle) {
                                          return;
                                        }
                                        setState(
                                          () => _showOnHomescreenWidget = value,
                                        );
                                      },
                                activeColor: AppColors.primaryLight,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                child: _showOnHomescreenWidget
                                    ? _buildHomescreenWidgetStyleSection(theme)
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Save button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryDark,
                              foregroundColor: AppColors.white,
                              disabledBackgroundColor:
                                  AppColors.primaryDark.withValues(alpha: 0.5),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.white,
                                    ),
                                  )
                                : Text(
                                    _isEdit
                                        ? context.l10nText('Save Changes')
                                        : context.l10nText('Create Budget'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),

                        if (_isEdit) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _isSaving ? null : _delete,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.red,
                                side: BorderSide(
                                  color: AppColors.red.withValues(alpha: 0.4),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                context.l10nText('Delete budget'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewCategoryComposer() {
    final selectedColor = _colorFromKey(_draftCategoryColorKey);
    const flow = 'expense';
    final draftName = _newCategoryController.text.trim();
    final isDuplicateName = draftName.isNotEmpty &&
        _categoryExistsForFlow(name: draftName, flow: flow);
    final canSubmit = draftName.isNotEmpty && !isDuplicateName;
    final textFieldBorderColor =
        isDuplicateName ? AppColors.red : AppColors.borderColor(context);
    final focusedBorderColor =
        isDuplicateName ? AppColors.red : AppColors.primaryLight;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newCategoryController,
                  focusNode: _newCategoryFocus,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _createCategoryInline(),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: context.l10nText('Category name'),
                    hintStyle:
                        TextStyle(color: AppColors.textTertiary(context)),
                    filled: true,
                    fillColor: AppColors.surfaceColor(context),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: textFieldBorderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: textFieldBorderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: focusedBorderColor,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleColorChoices,
                child: Container(
                  height: 40,
                  width: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: selectedColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Icon(
                        _showCategoryColorChoices
                            ? AppIcons.keyboard_arrow_up
                            : AppIcons.keyboard_arrow_down,
                        size: 16,
                        color: AppColors.textSecondary(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: canSubmit ? _createCategoryInline : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    context.l10nText('Add'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if (_showCategoryColorChoices) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _kBudgetCategoryColorOptions.map((option) {
                    final selected = option.key == _draftCategoryColorKey;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _draftCategoryColorKey = option.key;
                            _showCategoryColorChoices = false;
                          });
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: option.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? AppColors.textPrimary(context)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: context.l10nText(hint),
      hintStyle: TextStyle(color: AppColors.textTertiary(context)),
      filled: true,
      fillColor: AppColors.surfaceColor(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final selectedIds = _selectedCategoryIds.toList(growable: false);
    final primaryCategoryId = selectedIds.isEmpty ? null : selectedIds.first;
    final isCategory = selectedIds.isNotEmpty;
    final now = DateTime.now();
    final startDate =
        _isEdit ? widget.existing!.startDate : _selectedMonthStart;
    final baseEndDate = _isEdit
        ? widget.existing!.endDate
        : (_uniqueToSelectedMonth ? _selectedMonthEnd : null);
    final shouldCreateFutureBudgets =
        _isEdit && _isSingleMonthBudgetInSelectedMonth && _createFutureBudgets;
    final shouldEndRecurringAfterSelectedMonth =
        _isEdit && _hasFutureBudgetsToUpdate && _endRecurringAtSelectedMonth;
    final effectiveEndDate = shouldCreateFutureBudgets ? null : baseEndDate;
    final budget = Budget(
      id: widget.existing?.id,
      name: _nameController.text.trim(),
      type: isCategory ? 'category' : _selectedPeriod,
      amount: double.parse(_amountController.text.trim()),
      categoryId: primaryCategoryId,
      categoryIds: selectedIds.isEmpty ? null : selectedIds,
      startDate: startDate,
      endDate: effectiveEndDate,
      rollover: _rollover,
      alertThreshold: double.parse(_alertController.text.trim()),
      isActive: true,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      timeFrame: isCategory ? _selectedPeriod : null,
      calendar: widget.calendar.storageValue,
    );

    try {
      late final Budget savedBudget;

      if (_isEdit) {
        if (shouldEndRecurringAfterSelectedMonth) {
          savedBudget = await widget.budgetProvider.updateBudgetForMonthOnly(
            originalBudget: widget.existing!,
            editedBudget: budget.copyWith(endDate: _selectedMonthEnd),
            month: _selectedMonthStart,
            keepFutureSegment: false,
          );
        } else if (_applyToFutureBudgets || !_hasFutureBudgetsToUpdate) {
          savedBudget = await widget.budgetProvider.updateBudget(budget);
        } else {
          savedBudget = await widget.budgetProvider.updateBudgetForMonthOnly(
            originalBudget: widget.existing!,
            editedBudget: budget,
            month: _selectedMonthStart,
            keepFutureSegment: true,
          );
        }
      } else {
        savedBudget = await widget.budgetProvider.createBudget(budget);
      }

      String? widgetFeedback;
      try {
        widgetFeedback = await _syncHomescreenWidgetSelection(savedBudget);
      } catch (error, stackTrace) {
        debugPrint(
          'debug: Error syncing homescreen widget after saving budget: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
        widgetFeedback =
            'Budget saved, but the homescreen widget could not be updated.';
      }

      if (!mounted) return;
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      navigator.pop();
      if (widgetFeedback != null && widgetFeedback.trim().isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10nTextRead(widgetFeedback))),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('debug: Error saving budget: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10nTextRead('Could not save budget'))),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    bool deleteFutureBudgets = false;
    final hasFutureBudgets = _hasFutureBudgetsToUpdate;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(ctx.l10nText('Delete budget?')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ctx.l10nText('This cannot be undone.')),
              if (hasFutureBudgets) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(ctx.l10nText('Delete future budgets too')),
                  value: deleteFutureBudgets,
                  onChanged: (value) {
                    setDialogState(() {
                      deleteFutureBudgets = value ?? false;
                    });
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10nText('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                ctx.l10nText('Delete'),
                style: const TextStyle(color: AppColors.red),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      if (hasFutureBudgets) {
        await widget.budgetProvider.deleteBudgetForMonth(
          originalBudget: widget.existing!,
          month: _selectedMonthStart,
          deleteFutureBudgets: deleteFutureBudgets,
        );
      } else {
        await widget.budgetProvider.deleteBudget(widget.existing!.id!);
      }
      if (mounted) Navigator.of(context).pop();
    }
  }
}

// ── Group toggle (Needs / Wants) ────────────────────────────────────────────

class _GroupToggle extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _GroupToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final toggleBg = AppColors.mutedFill(context).withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: toggleBg,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: ['needs', 'wants'].map((group) {
          final isSelected = selected == group;
          final label = group[0].toUpperCase() + group.substring(1);
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(group),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.cardColor(context)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  context.l10nText(label),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppColors.textPrimary(context)
                        : AppColors.textSecondary(context),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Period toggle ───────────────────────────────────────────────────────────

class _PeriodToggle extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _PeriodToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final toggleBg = AppColors.mutedFill(context).withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: toggleBg,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: ['daily', 'monthly', 'yearly'].map((period) {
          final isSelected = selected == period;
          final label = period[0].toUpperCase() + period.substring(1);
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(period),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.cardColor(context)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  context.l10nText(label),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppColors.textPrimary(context)
                        : AppColors.textSecondary(context),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AutoMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final double gap;
  final double pixelsPerSecond;

  const _AutoMarqueeText({
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
    this.gap = 28,
    this.pixelsPerSecond = 28,
  });

  @override
  State<_AutoMarqueeText> createState() => _AutoMarqueeTextState();
}

class _AutoMarqueeTextState extends State<_AutoMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Duration? _currentDuration;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _stopMarquee() {
    if (_controller.isAnimating) {
      _controller.stop();
    }
    _controller.value = 0;
  }

  void _startMarquee(double scrollDistance) {
    if (scrollDistance <= 0 || !mounted) {
      _stopMarquee();
      return;
    }
    final millis = ((scrollDistance / widget.pixelsPerSecond) * 1000)
        .round()
        .clamp(3500, 24000)
        .toInt();
    final duration = Duration(milliseconds: millis);
    if (_currentDuration != duration) {
      _currentDuration = duration;
      _controller.duration = duration;
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) {
      _stopMarquee();
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxWidth.isFinite || constraints.maxWidth <= 0) {
          _stopMarquee();
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: widget.textAlign,
          );
        }

        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: double.infinity);

        final textWidth = painter.width;
        final shouldMarquee = textWidth > constraints.maxWidth + 0.5;

        if (!shouldMarquee) {
          _stopMarquee();
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: widget.textAlign,
          );
        }

        final scrollDistance = textWidth + widget.gap;
        _startMarquee(scrollDistance);

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final offsetX = -_controller.value * scrollDistance;
              return Transform.translate(
                offset: Offset(offsetX, 0),
                child: child,
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.text,
                  style: widget.style,
                  maxLines: 1,
                  softWrap: false,
                ),
                SizedBox(width: widget.gap),
                Text(
                  widget.text,
                  style: widget.style,
                  maxLines: 1,
                  softWrap: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BudgetRecurrenceBadge extends StatelessWidget {
  final bool isRecurring;

  const _BudgetRecurrenceBadge({
    required this.isRecurring,
  });

  @override
  Widget build(BuildContext context) {
    final label = isRecurring ? 'Recurring' : 'This month';
    final color =
        isRecurring ? AppColors.primaryLight : AppColors.textSecondary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        context.l10nText(label),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _BudgetWidgetBadge extends StatelessWidget {
  final Color color;
  final VoidCallback? onTap;

  const _BudgetWidgetBadge({
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: color.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            context.l10nText('Widget'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _BudgetWidgetStyleSheet extends StatefulWidget {
  final String budgetName;
  final String initialIconKey;
  final String initialColorKey;

  const _BudgetWidgetStyleSheet({
    required this.budgetName,
    required this.initialIconKey,
    required this.initialColorKey,
  });

  @override
  State<_BudgetWidgetStyleSheet> createState() =>
      _BudgetWidgetStyleSheetState();
}

class _BudgetWidgetStyleSheetState extends State<_BudgetWidgetStyleSheet> {
  late String _selectedIconKey;
  late String _selectedColorKey;

  @override
  void initState() {
    super.initState();
    _selectedIconKey = widget.initialIconKey;
    _selectedColorKey = widget.initialColorKey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = _budgetWidgetColorFromKey(_selectedColorKey);
    final selectedIcon = _kBudgetWidgetIconOptions.firstWhere(
      (option) => option.key == _selectedIconKey,
      orElse: () => _kBudgetWidgetIconOptions.first,
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10nText('Widget Style'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(AppIcons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: selectedColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selectedColor.withValues(alpha: 0.25),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      selectedIcon.icon,
                      size: 18,
                      color: selectedColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l10nText(widget.budgetName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BudgetWidgetBadge(color: selectedColor),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                child: _BudgetWidgetStylePicker(
                  selectedIconKey: _selectedIconKey,
                  selectedColorKey: _selectedColorKey,
                  onIconChanged: (value) {
                    setState(() => _selectedIconKey = value);
                  },
                  onColorChanged: (value) {
                    setState(() => _selectedColorKey = value);
                  },
                  showTopDivider: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      BudgetWidgetStylePreference(
                        iconKey: _selectedIconKey,
                        colorKey: _selectedColorKey,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    context.l10nText('Save Style'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetWidgetStylePicker extends StatelessWidget {
  final String selectedIconKey;
  final String selectedColorKey;
  final ValueChanged<String> onIconChanged;
  final ValueChanged<String> onColorChanged;
  final bool showTopDivider;

  const _BudgetWidgetStylePicker({
    required this.selectedIconKey,
    required this.selectedColorKey,
    required this.onIconChanged,
    required this.onColorChanged,
    this.showTopDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = _budgetWidgetColorFromKey(selectedColorKey);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTopDivider)
            Divider(
              height: 1,
              color: AppColors.borderColor(context),
            ),
          const SizedBox(height: 14),
          Text(
            context.l10nText('Icon'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _kBudgetWidgetIconOptions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: 42,
              ),
              itemBuilder: (context, index) {
                final option = _kBudgetWidgetIconOptions[index];
                final selected = option.key == selectedIconKey;
                return Tooltip(
                  message: context.l10nText(option.label),
                  child: Material(
                    color: selected
                        ? selectedColor.withValues(alpha: 0.15)
                        : AppColors.surfaceColor(context),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onIconChanged(option.key),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? selectedColor
                                : AppColors.borderColor(context),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          option.icon,
                          size: 20,
                          color: selected
                              ? selectedColor
                              : AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10nText('Swipe sideways to see more icons.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.l10nText('Color'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kBudgetWidgetColorOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final option = _kBudgetWidgetColorOptions[index];
                final selected = option.key == selectedColorKey;
                return GestureDetector(
                  onTap: () => onColorChanged(option.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: option.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppColors.textPrimary(context)
                            : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: option.color.withValues(alpha: 0.28),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category chip button ────────────────────────────────────────────────────

class _CategoryChipButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final bool showColorDot;
  final bool isAction;
  final VoidCallback onTap;

  const _CategoryChipButton({
    required this.label,
    required this.color,
    required this.selected,
    this.showColorDot = true,
    this.isAction = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color.withValues(alpha: 0.15) : Colors.transparent;
    final border = selected ? color : AppColors.borderColor(context);
    final textColor =
        isAction ? color : (selected ? color : AppColors.textPrimary(context));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showColorDot) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                context.l10nText(label),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
