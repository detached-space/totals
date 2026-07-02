import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/bank.dart' as bank_model;
import 'package:totals/models/category.dart' show Category;
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:totals/services/account_registration_service.dart';
import 'package:totals/services/account_transaction_reparse_service.dart';
import 'package:totals/services/account_sync_status_service.dart';
import 'package:totals/services/bank_detection_service.dart';
import 'package:totals/services/fallback_sms_parser.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/utils/app_date_format.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/_redesign/screens/loans_page.dart';
import 'package:totals/widgets/add_cash_transaction_sheet.dart';
import 'package:totals/widgets/inline_bank_selector.dart';
import 'package:totals/_redesign/widgets/transaction_category_sheet.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/_redesign/widgets/transaction_tile.dart';
import 'package:kenat/kenat.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/theme/app_calendar_option.dart';
import 'package:totals/theme/app_language_option.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

class RedesignMoneyPage extends StatefulWidget {
  const RedesignMoneyPage({super.key});

  @override
  State<RedesignMoneyPage> createState() => RedesignMoneyPageState();
}

enum _TopTab { activity, accounts }

enum _SubTab { transactions, analytics, ledger }

enum _AnalyticsHeatmapMode { all, expense, income }

enum _AnalyticsHeatmapView { daily, monthly }

enum _AnalyticsLineChartPeriod { weekly, monthly, yearly }

enum _AnalyticsBarChartPeriod { weekly, monthly, yearly }

enum _AnalyticsChartSection {
  heatmap,
  expenseBubble,
  lineChart,
  barChart,
  pieChart,
}

extension on _AnalyticsChartSection {
  String get title {
    switch (this) {
      case _AnalyticsChartSection.heatmap:
        return 'Heatmap';
      case _AnalyticsChartSection.expenseBubble:
        return 'Bubble Chart';
      case _AnalyticsChartSection.lineChart:
        return 'Line Chart';
      case _AnalyticsChartSection.barChart:
        return 'Bar Chart';
      case _AnalyticsChartSection.pieChart:
        return 'Pie Chart';
    }
  }

  String get filterTitle {
    switch (this) {
      case _AnalyticsChartSection.heatmap:
        return 'Filter Heatmap';
      case _AnalyticsChartSection.expenseBubble:
        return 'Filter Bubble Chart';
      case _AnalyticsChartSection.lineChart:
        return 'Filter Line Chart';
      case _AnalyticsChartSection.barChart:
        return 'Filter Bar Chart';
      case _AnalyticsChartSection.pieChart:
        return 'Filter Pie Chart';
    }
  }

  String get filterSubtitle {
    switch (this) {
      case _AnalyticsChartSection.heatmap:
        return 'Tune flow, bank, and category for the activity grid.';
      case _AnalyticsChartSection.expenseBubble:
        return 'Focus the category bubbles on a specific bank or date range.';
      case _AnalyticsChartSection.lineChart:
        return 'Focus income and expense trends on a specific bank.';
      case _AnalyticsChartSection.barChart:
        return 'Tune flow, period, and bank for the category bar chart.';
      case _AnalyticsChartSection.pieChart:
        return 'Focus category share on a specific bank or date range.';
    }
  }

  _AnalyticsHeatmapMode get defaultFilterMode {
    switch (this) {
      case _AnalyticsChartSection.heatmap:
      case _AnalyticsChartSection.lineChart:
        return _AnalyticsHeatmapMode.all;
      case _AnalyticsChartSection.barChart:
        return _AnalyticsHeatmapMode.expense;
      case _AnalyticsChartSection.expenseBubble:
      case _AnalyticsChartSection.pieChart:
        return _AnalyticsHeatmapMode.expense;
    }
  }

  _AnalyticsBarChartPeriod get defaultBarChartPeriod {
    switch (this) {
      case _AnalyticsChartSection.barChart:
        return _AnalyticsBarChartPeriod.monthly;
      default:
        return _AnalyticsBarChartPeriod.monthly;
    }
  }

  bool get showsModeFilter =>
      this == _AnalyticsChartSection.heatmap ||
      this == _AnalyticsChartSection.barChart;

  bool get showsPeriodFilter => this == _AnalyticsChartSection.barChart;

  bool get showsBankFilter => true;

  bool get showsCategoryFilter => this == _AnalyticsChartSection.heatmap;

  bool get showsDateRangeFilter =>
      this == _AnalyticsChartSection.expenseBubble ||
      this == _AnalyticsChartSection.pieChart;

  int activeFilterCount(_AnalyticsHeatmapFilter filter) {
    var count = 0;
    if (showsModeFilter && filter.mode != defaultFilterMode) count++;
    if (showsPeriodFilter && filter.barPeriod != defaultBarChartPeriod) {
      count++;
    }
    if (showsBankFilter && filter.bankId != null) count++;
    if (showsCategoryFilter && filter.categoryId != null) count++;
    if (showsDateRangeFilter &&
        (filter.startDate != null || filter.endDate != null)) {
      count++;
    }
    return count;
  }
}

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

String _normalizeBankToken(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String _bankDedupeKey(bank_model.Bank bank) {
  final short = _normalizeBankToken(bank.shortName);
  final name = _normalizeBankToken(bank.name);
  if (short.contains('mpesa') || name.contains('mpesa')) {
    return 'mpesa';
  }
  if (short.isNotEmpty) return short;
  if (name.isNotEmpty) return name;
  return bank.image.toLowerCase();
}

List<bank_model.Bank> _dedupeBanksForSelection(List<bank_model.Bank> banks) {
  final dedupedByKey = <String, bank_model.Bank>{};
  for (final bank in banks) {
    final key = _bankDedupeKey(bank);
    final existing = dedupedByKey[key];
    if (existing == null) {
      dedupedByKey[key] = bank;
      continue;
    }

    final shouldReplace = (bank.id == 8 && existing.id != 8) ||
        (existing.id != 8 && bank.id < existing.id);
    if (shouldReplace) dedupedByKey[key] = bank;
  }
  return dedupedByKey.values.toList();
}

/// Filter state passed from the filter bottom sheet.
class _TransactionFilter {
  final String? type; // null = All, 'DEBIT' = Expense, 'CREDIT' = Income
  final int? bankId; // null = All Banks
  final int? categoryId; // null = All Categories
  final double? minAmount;
  final double? maxAmount;
  final DateTime? startDate;
  final DateTime? endDate;

  _TransactionFilter({
    this.type,
    this.bankId,
    this.categoryId,
    this.minAmount,
    this.maxAmount,
    this.startDate,
    this.endDate,
  });

  bool get isActive =>
      type != null ||
      bankId != null ||
      categoryId != null ||
      minAmount != null ||
      maxAmount != null ||
      startDate != null ||
      endDate != null;

  int get activeCount {
    int count = 0;
    if (type != null) count++;
    if (bankId != null) count++;
    if (categoryId != null) count++;
    if (minAmount != null || maxAmount != null) count++;
    if (startDate != null || endDate != null) count++;
    return count;
  }
}

class _LedgerFilter {
  final DateTime? startDate;
  final DateTime? endDate;
  final Set<int> bankIds;

  const _LedgerFilter({
    this.startDate,
    this.endDate,
    this.bankIds = const <int>{},
  });

  bool get isActive =>
      startDate != null || endDate != null || bankIds.isNotEmpty;

  int get activeCount {
    int count = 0;
    if (startDate != null || endDate != null) count++;
    if (bankIds.isNotEmpty) count++;
    return count;
  }
}

class _AnalyticsHeatmapFilter {
  final _AnalyticsHeatmapMode mode;
  final _AnalyticsBarChartPeriod barPeriod;
  final int? bankId;
  final int? categoryId;
  final DateTime? startDate;
  final DateTime? endDate;

  const _AnalyticsHeatmapFilter({
    this.mode = _AnalyticsHeatmapMode.all,
    this.barPeriod = _AnalyticsBarChartPeriod.monthly,
    this.bankId,
    this.categoryId,
    this.startDate,
    this.endDate,
  });

  bool get isActive =>
      mode != _AnalyticsHeatmapMode.all ||
      barPeriod != _AnalyticsBarChartPeriod.monthly ||
      bankId != null ||
      categoryId != null ||
      startDate != null ||
      endDate != null;

  int get activeCount {
    int count = 0;
    if (mode != _AnalyticsHeatmapMode.all) count++;
    if (barPeriod != _AnalyticsBarChartPeriod.monthly) count++;
    if (bankId != null) count++;
    if (categoryId != null) count++;
    if (startDate != null || endDate != null) count++;
    return count;
  }

  _AnalyticsHeatmapFilter copyWith({
    _AnalyticsHeatmapMode? mode,
    _AnalyticsBarChartPeriod? barPeriod,
    int? bankId,
    bool clearBankId = false,
    int? categoryId,
    bool clearCategoryId = false,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? endDate,
    bool clearEndDate = false,
  }) {
    return _AnalyticsHeatmapFilter(
      mode: mode ?? this.mode,
      barPeriod: barPeriod ?? this.barPeriod,
      bankId: clearBankId ? null : (bankId ?? this.bankId),
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
    );
  }
}

class _ProviderContentVersion {
  final int dataVersion;
  final bool isLoading;

  const _ProviderContentVersion({
    required this.dataVersion,
    required this.isLoading,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ProviderContentVersion &&
        other.dataVersion == dataVersion &&
        other.isLoading == isLoading;
  }

  @override
  int get hashCode => Object.hash(dataVersion, isLoading);
}

class _ActivityTransactionsViewCacheKey {
  final int dataVersion;
  final String calendar;
  final String language;
  final String searchQuery;
  final String? type;
  final int? bankId;
  final int? categoryId;
  final double? minAmount;
  final double? maxAmount;
  final int? startDateMillis;
  final int? endDateMillis;
  final int currentPage;

  const _ActivityTransactionsViewCacheKey({
    required this.dataVersion,
    required this.calendar,
    required this.language,
    required this.searchQuery,
    required this.type,
    required this.bankId,
    required this.categoryId,
    required this.minAmount,
    required this.maxAmount,
    required this.startDateMillis,
    required this.endDateMillis,
    required this.currentPage,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ActivityTransactionsViewCacheKey &&
        other.dataVersion == dataVersion &&
        other.calendar == calendar &&
        other.language == language &&
        other.searchQuery == searchQuery &&
        other.type == type &&
        other.bankId == bankId &&
        other.categoryId == categoryId &&
        other.minAmount == minAmount &&
        other.maxAmount == maxAmount &&
        other.startDateMillis == startDateMillis &&
        other.endDateMillis == endDateMillis &&
        other.currentPage == currentPage;
  }

  @override
  int get hashCode => Object.hash(
      dataVersion,
      calendar,
      language,
      searchQuery,
      type,
      bankId,
      categoryId,
      minAmount,
      maxAmount,
      startDateMillis,
      endDateMillis,
      currentPage);
}

class _ActivityTransactionsViewData {
  final int totalPages;
  final int safePage;
  final List<Object> flatItems;
  final _ActivityTransactionsSummary summary;

  const _ActivityTransactionsViewData({
    required this.totalPages,
    required this.safePage,
    required this.flatItems,
    required this.summary,
  });
}

class _ActivityTransactionsSummary {
  final int totalTransactions;
  final double totalIncome;
  final double totalExpense;

  const _ActivityTransactionsSummary({
    required this.totalTransactions,
    required this.totalIncome,
    required this.totalExpense,
  });
}

class _LedgerViewCacheKey {
  final int dataVersion;
  final String calendar;
  final String language;
  final int? startDateMillis;
  final int? endDateMillis;
  final String bankIdsKey;

  const _LedgerViewCacheKey({
    required this.dataVersion,
    required this.calendar,
    required this.language,
    required this.startDateMillis,
    required this.endDateMillis,
    required this.bankIdsKey,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _LedgerViewCacheKey &&
        other.dataVersion == dataVersion &&
        other.calendar == calendar &&
        other.language == language &&
        other.startDateMillis == startDateMillis &&
        other.endDateMillis == endDateMillis &&
        other.bankIdsKey == bankIdsKey;
  }

  @override
  int get hashCode => Object.hash(
        dataVersion,
        calendar,
        language,
        startDateMillis,
        endDateMillis,
        bankIdsKey,
      );
}

class _LedgerViewSummary {
  final List<Object> flatItems;
  final Map<String, double> derivedCashBalancesByReference;
  final DateTime? startingDate;
  final double? startingBalance;

  const _LedgerViewSummary({
    required this.flatItems,
    required this.derivedCashBalancesByReference,
    required this.startingDate,
    required this.startingBalance,
  });
}

class RedesignMoneyPageState extends State<RedesignMoneyPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  _TopTab _topTab = _TopTab.activity;
  _SubTab _subTab = _SubTab.transactions;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _TransactionFilter _filter = _TransactionFilter();
  int? _selectedBankId;
  bool _showAccountBalances = false;
  final Set<String> _selectedRefs = {};
  final Set<String> _reparsingAccountKeys = <String>{};
  _LedgerFilter _ledgerFilter = const _LedgerFilter();
  final ScrollController _activityScrollController = ScrollController();
  int _currentPage = 0;
  static const int _pageSize = 20;
  _AnalyticsHeatmapFilter _analyticsHeatmapFilter =
      const _AnalyticsHeatmapFilter();
  _AnalyticsHeatmapFilter _analyticsBubbleFilter =
      const _AnalyticsHeatmapFilter(
    mode: _AnalyticsHeatmapMode.expense,
  );
  _AnalyticsHeatmapFilter _analyticsLineFilter =
      const _AnalyticsHeatmapFilter();
  _AnalyticsHeatmapFilter _analyticsBarFilter = const _AnalyticsHeatmapFilter(
    mode: _AnalyticsHeatmapMode.expense,
  );
  _AnalyticsHeatmapFilter _analyticsPieFilter = const _AnalyticsHeatmapFilter(
    mode: _AnalyticsHeatmapMode.expense,
  );
  _AnalyticsHeatmapView _analyticsHeatmapView = _AnalyticsHeatmapView.daily;
  _AnalyticsLineChartPeriod _analyticsLineChartPeriod =
      _AnalyticsLineChartPeriod.monthly;
  int _analyticsBubbleChartOffset = 0;
  int _analyticsLineChartOffset = 0;
  int _analyticsBarChartOffset = 0;
  int _analyticsPieChartOffset = 0;
  DateTime? _analyticsHeatmapFocusMonth;
  _AnalyticsChartSection _analyticsSelectedChartSection =
      _AnalyticsChartSection.heatmap;
  final AccountTransactionReparseService _accountTransactionReparseService =
      AccountTransactionReparseService();
  late final AnimationController _subTabFadeController;
  late final Animation<double> _subTabFadeAnimation;
  _ActivityTransactionsViewCacheKey? _activityTransactionsViewCacheKey;
  _ActivityTransactionsViewData? _activityTransactionsViewCache;
  _LedgerViewCacheKey? _ledgerViewCacheKey;
  _LedgerViewSummary? _ledgerViewCache;
  final ValueNotifier<bool> _showActivityPinnedHeaderDivider =
      ValueNotifier<bool>(false);

  bool get _isSelecting => _selectedRefs.isNotEmpty;

  double get _activityPinnedHeaderDividerTriggerOffset {
    switch (_subTab) {
      case _SubTab.transactions:
        return 16;
      case _SubTab.analytics:
        return 12;
      case _SubTab.ledger:
        return 16;
    }
  }

  @override
  void initState() {
    super.initState();
    _subTabFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _subTabFadeAnimation = CurvedAnimation(
      parent: _subTabFadeController,
      curve: Curves.easeOutCubic,
    );
    _subTabFadeController.value = 1;
    _activityScrollController.addListener(_syncActivityPinnedHeaderDivider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncActivityPinnedHeaderDivider();
    });
  }

  void _syncActivityPinnedHeaderDivider([double? offset]) {
    final pixels = offset ??
        (_activityScrollController.hasClients
            ? _activityScrollController.offset
            : 0);
    final shouldShow = pixels > _activityPinnedHeaderDividerTriggerOffset;
    if (_showActivityPinnedHeaderDivider.value == shouldShow) return;
    _showActivityPinnedHeaderDivider.value = shouldShow;
  }

  DateTime _normalizeAnalyticsHeatmapMonth(DateTime date) {
    try {
      final isEC = context.read<ThemeProvider>().appCalendar ==
          AppCalendarOption.ethiopian;
      if (isEC) {
        final ec =
            Kenat.fromGregorian(date.year, date.month, date.day).getEthiopian();
        final gc =
            Kenat.fromEthiopian(ec['year']!, ec['month']!, 1).getGregorian();
        return DateTime(gc['year']!, gc['month']!, gc['day']!);
      }
    } catch (_) {}
    return DateTime(date.year, date.month, 1);
  }

  DateTime _normalizeYearStart(DateTime date) {
    try {
      final isEC = context.read<ThemeProvider>().appCalendar ==
          AppCalendarOption.ethiopian;
      if (isEC) {
        final ec =
            Kenat.fromGregorian(date.year, date.month, date.day).getEthiopian();
        final gc = Kenat.fromEthiopian(ec['year']!, 1, 1).getGregorian();
        return DateTime(gc['year']!, gc['month']!, gc['day']!);
      }
    } catch (_) {}
    return DateTime(date.year, 1, 1);
  }

  DateTime _resolveAnalyticsHeatmapFocusMonth(DateTime fallbackMonth) {
    return _normalizeAnalyticsHeatmapMonth(
      _analyticsHeatmapFocusMonth ?? fallbackMonth,
    );
  }

  void _shiftAnalyticsHeatmapPeriod(DateTime currentFocusMonth, int delta) {
    DateTime nextFocus;
    try {
      final isEC = context.read<ThemeProvider>().appCalendar ==
          AppCalendarOption.ethiopian;
      if (isEC) {
        final ec = Kenat.fromGregorian(
          currentFocusMonth.year,
          currentFocusMonth.month,
          currentFocusMonth.day,
        ).getEthiopian();
        if (_analyticsHeatmapView == _AnalyticsHeatmapView.daily) {
          var y = ec['year']!;
          var m = ec['month']! + delta;
          while (m > 13) {
            m -= 13;
            y++;
          }
          while (m < 1) {
            m += 13;
            y--;
          }
          final gc = Kenat.fromEthiopian(y, m, 1).getGregorian();
          nextFocus = DateTime(gc['year']!, gc['month']!, gc['day']!);
        } else {
          final gc = Kenat.fromEthiopian(ec['year']! + delta, ec['month']!, 1)
              .getGregorian();
          nextFocus = DateTime(gc['year']!, gc['month']!, gc['day']!);
        }
      } else {
        if (_analyticsHeatmapView == _AnalyticsHeatmapView.daily) {
          nextFocus = DateTime(
              currentFocusMonth.year, currentFocusMonth.month + delta, 1);
        } else {
          nextFocus = DateTime(
              currentFocusMonth.year + delta, currentFocusMonth.month, 1);
        }
      }
    } catch (_) {
      if (_analyticsHeatmapView == _AnalyticsHeatmapView.daily) {
        nextFocus = DateTime(
            currentFocusMonth.year, currentFocusMonth.month + delta, 1);
      } else {
        nextFocus = DateTime(
            currentFocusMonth.year + delta, currentFocusMonth.month, 1);
      }
    }
    setState(() {
      _analyticsHeatmapFocusMonth = nextFocus;
    });
  }

  void _toggleAnalyticsHeatmapView(DateTime currentFocusMonth) {
    setState(() {
      _analyticsHeatmapFocusMonth =
          _normalizeAnalyticsHeatmapMonth(currentFocusMonth);
      _analyticsHeatmapView =
          _analyticsHeatmapView == _AnalyticsHeatmapView.daily
              ? _AnalyticsHeatmapView.monthly
              : _AnalyticsHeatmapView.daily;
    });
  }

  void _selectAnalyticsHeatmapMonth(DateTime month) {
    setState(() {
      _analyticsHeatmapFocusMonth = _normalizeAnalyticsHeatmapMonth(month);
      _analyticsHeatmapView = _AnalyticsHeatmapView.daily;
    });
  }

  _AnalyticsHeatmapFilter _analyticsFilterForSection(
    _AnalyticsChartSection section,
  ) {
    switch (section) {
      case _AnalyticsChartSection.heatmap:
        return _analyticsHeatmapFilter;
      case _AnalyticsChartSection.expenseBubble:
        return _analyticsBubbleFilter;
      case _AnalyticsChartSection.lineChart:
        return _analyticsLineFilter;
      case _AnalyticsChartSection.barChart:
        return _analyticsBarFilter;
      case _AnalyticsChartSection.pieChart:
        return _analyticsPieFilter;
    }
  }

  bool _analyticsFilterUsesDateRange(_AnalyticsHeatmapFilter filter) {
    return filter.startDate != null || filter.endDate != null;
  }

  bool get _usesEthiopianCalendar =>
      context.read<ThemeProvider>().appCalendar == AppCalendarOption.ethiopian;

  DateTime _ethiopianDateFromParts(int year, int month, int day) {
    final gc = Kenat.fromEthiopian(year, month, day).getGregorian();
    return DateTime(gc['year']!, gc['month']!, gc['day']!);
  }

  _AnalyticsDateWindow _resolveAnalyticsMonthWindow(DateTime date) {
    if (!_usesEthiopianCalendar) {
      final start = DateTime(date.year, date.month, 1);
      return _AnalyticsDateWindow(
        start: start,
        endExclusive: DateTime(start.year, start.month + 1, 1),
      );
    }

    final ec =
        Kenat.fromGregorian(date.year, date.month, date.day).getEthiopian();
    final start = _ethiopianDateFromParts(ec['year']!, ec['month']!, 1);
    var nextYear = ec['year']!;
    var nextMonth = ec['month']! + 1;
    if (nextMonth > 13) {
      nextMonth = 1;
      nextYear++;
    }

    return _AnalyticsDateWindow(
      start: start,
      endExclusive: _ethiopianDateFromParts(nextYear, nextMonth, 1),
    );
  }

  _AnalyticsDateWindow _resolveAnalyticsYearWindow(DateTime date) {
    if (!_usesEthiopianCalendar) {
      final start = DateTime(date.year, 1, 1);
      return _AnalyticsDateWindow(
        start: start,
        endExclusive: DateTime(start.year + 1, 1, 1),
      );
    }

    final ec =
        Kenat.fromGregorian(date.year, date.month, date.day).getEthiopian();
    return _AnalyticsDateWindow(
      start: _ethiopianDateFromParts(ec['year']!, 1, 1),
      endExclusive: _ethiopianDateFromParts(ec['year']! + 1, 1, 1),
    );
  }

  DateTime _shiftAnalyticsMonth(DateTime month, int offset) {
    if (!_usesEthiopianCalendar) {
      return DateTime(month.year, month.month + offset, 1);
    }

    final ec =
        Kenat.fromGregorian(month.year, month.month, month.day).getEthiopian();
    var year = ec['year']!;
    var targetMonth = ec['month']! + offset;
    while (targetMonth > 13) {
      targetMonth -= 13;
      year++;
    }
    while (targetMonth < 1) {
      targetMonth += 13;
      year--;
    }
    return _ethiopianDateFromParts(year, targetMonth, 1);
  }

  int _analyticsMonthDelta(DateTime targetMonth, DateTime anchorMonth) {
    if (_usesEthiopianCalendar) {
      final targetEc = Kenat.fromGregorian(
        targetMonth.year,
        targetMonth.month,
        targetMonth.day,
      ).getEthiopian();
      final anchorEc = Kenat.fromGregorian(
        anchorMonth.year,
        anchorMonth.month,
        anchorMonth.day,
      ).getEthiopian();
      return (targetEc['year']! - anchorEc['year']!) * 13 +
          targetEc['month']! -
          anchorEc['month']!;
    }

    return (targetMonth.year - anchorMonth.year) * 12 +
        targetMonth.month -
        anchorMonth.month;
  }

  int _analyticsYearDelta(DateTime targetDate, DateTime anchorDate) {
    if (_usesEthiopianCalendar) {
      final targetEc = Kenat.fromGregorian(
        targetDate.year,
        targetDate.month,
        targetDate.day,
      ).getEthiopian();
      final anchorEc = Kenat.fromGregorian(
        anchorDate.year,
        anchorDate.month,
        anchorDate.day,
      ).getEthiopian();
      return targetEc['year']! - anchorEc['year']!;
    }

    return targetDate.year - anchorDate.year;
  }

  DateTime _resolveChartVisibleMonth(
    List<Transaction> transactions, {
    required int periodOffset,
  }) {
    final anchorMonth = _resolveAnalyticsChartAnchorMonth(transactions);
    return _shiftAnalyticsMonth(anchorMonth, periodOffset);
  }

  int _resolveLineChartOffsetForVisibleStart(
    List<Transaction> transactions, {
    required DateTime visibleStart,
    required _AnalyticsLineChartPeriod period,
  }) {
    final anchorDate = _resolveAnalyticsChartAnchorDate(transactions);
    switch (period) {
      case _AnalyticsLineChartPeriod.weekly:
        final anchorWeekStart = anchorDate.subtract(
          Duration(days: anchorDate.weekday - DateTime.monday),
        );
        final targetWeekStart = visibleStart.subtract(
          Duration(days: visibleStart.weekday - DateTime.monday),
        );
        return targetWeekStart.difference(anchorWeekStart).inDays ~/ 7;
      case _AnalyticsLineChartPeriod.monthly:
        final anchorMonth = _resolveAnalyticsMonthWindow(anchorDate).start;
        final targetMonth = _resolveAnalyticsMonthWindow(visibleStart).start;
        return _analyticsMonthDelta(targetMonth, anchorMonth);
      case _AnalyticsLineChartPeriod.yearly:
        return _analyticsYearDelta(visibleStart, anchorDate);
    }
  }

  int _resolveBarChartOffsetForVisibleStart(
    List<Transaction> transactions, {
    required DateTime visibleStart,
    required _AnalyticsBarChartPeriod period,
  }) {
    final anchorDate = _resolveAnalyticsChartAnchorDate(transactions);
    switch (period) {
      case _AnalyticsBarChartPeriod.weekly:
        final anchorWeekStart = anchorDate.subtract(
          Duration(days: anchorDate.weekday - DateTime.monday),
        );
        final targetWeekStart = visibleStart.subtract(
          Duration(days: visibleStart.weekday - DateTime.monday),
        );
        return targetWeekStart.difference(anchorWeekStart).inDays ~/ 7;
      case _AnalyticsBarChartPeriod.monthly:
        final anchorMonth = _resolveAnalyticsMonthWindow(anchorDate).start;
        final targetMonth = _resolveAnalyticsMonthWindow(visibleStart).start;
        return _analyticsMonthDelta(targetMonth, anchorMonth);
      case _AnalyticsBarChartPeriod.yearly:
        return _analyticsYearDelta(visibleStart, anchorDate);
    }
  }

  int _resolveChartOffsetForFilterChange(
    TransactionProvider provider, {
    required _AnalyticsChartSection section,
    required _AnalyticsHeatmapFilter currentFilter,
    required _AnalyticsHeatmapFilter nextFilter,
  }) {
    switch (section) {
      case _AnalyticsChartSection.heatmap:
        return 0;
      case _AnalyticsChartSection.expenseBubble:
        if (_analyticsFilterUsesDateRange(currentFilter) ||
            _analyticsFilterUsesDateRange(nextFilter)) {
          return 0;
        }
        final currentTransactions = _analyticsTransactionsForFilter(
          provider,
          currentFilter,
        );
        final nextTransactions = _analyticsTransactionsForFilter(
          provider,
          nextFilter,
        );
        final currentVisibleMonth = _resolveChartVisibleMonth(
          currentTransactions,
          periodOffset: _analyticsBubbleChartOffset,
        );
        final nextAnchorMonth = _resolveAnalyticsChartAnchorMonth(
          nextTransactions,
        );
        return _analyticsMonthDelta(currentVisibleMonth, nextAnchorMonth);
      case _AnalyticsChartSection.lineChart:
        final currentTransactions = _analyticsTransactionsForFilter(
          provider,
          currentFilter,
        );
        final nextTransactions = _analyticsTransactionsForFilter(
          provider,
          nextFilter,
        );
        final visibleStart = _resolveLineChartWindow(
          currentTransactions,
          period: _analyticsLineChartPeriod,
          periodOffset: _analyticsLineChartOffset,
        ).start;
        return _resolveLineChartOffsetForVisibleStart(
          nextTransactions,
          visibleStart: visibleStart,
          period: _analyticsLineChartPeriod,
        );
      case _AnalyticsChartSection.barChart:
        final currentTransactions = _analyticsTransactionsForFilter(
          provider,
          currentFilter,
        );
        final nextTransactions = _analyticsTransactionsForFilter(
          provider,
          nextFilter,
        );
        final visibleStart = _resolveBarChartWindow(
          currentTransactions,
          period: currentFilter.barPeriod,
          periodOffset: _analyticsBarChartOffset,
        ).start;
        return _resolveBarChartOffsetForVisibleStart(
          nextTransactions,
          visibleStart: visibleStart,
          period: nextFilter.barPeriod,
        );
      case _AnalyticsChartSection.pieChart:
        if (_analyticsFilterUsesDateRange(currentFilter) ||
            _analyticsFilterUsesDateRange(nextFilter)) {
          return 0;
        }
        final currentTransactions = _analyticsTransactionsForFilter(
          provider,
          currentFilter,
        );
        final nextTransactions = _analyticsTransactionsForFilter(
          provider,
          nextFilter,
        );
        final currentVisibleMonth = _resolveChartVisibleMonth(
          currentTransactions,
          periodOffset: _analyticsPieChartOffset,
        );
        final nextAnchorMonth = _resolveAnalyticsChartAnchorMonth(
          nextTransactions,
        );
        return _analyticsMonthDelta(currentVisibleMonth, nextAnchorMonth);
    }
  }

  void _setAnalyticsFilterForSection(
    TransactionProvider provider,
    _AnalyticsChartSection section,
    _AnalyticsHeatmapFilter filter,
  ) {
    final currentFilter = _analyticsFilterForSection(section);
    final nextOffset = _resolveChartOffsetForFilterChange(
      provider,
      section: section,
      currentFilter: currentFilter,
      nextFilter: filter,
    );

    setState(() {
      switch (section) {
        case _AnalyticsChartSection.heatmap:
          _analyticsHeatmapFilter = filter;
          break;
        case _AnalyticsChartSection.expenseBubble:
          _analyticsBubbleFilter = filter;
          _analyticsBubbleChartOffset = nextOffset;
          break;
        case _AnalyticsChartSection.lineChart:
          _analyticsLineFilter = filter;
          _analyticsLineChartOffset = nextOffset;
          break;
        case _AnalyticsChartSection.barChart:
          _analyticsBarFilter = filter;
          _analyticsBarChartOffset = nextOffset;
          break;
        case _AnalyticsChartSection.pieChart:
          _analyticsPieFilter = filter;
          _analyticsPieChartOffset = nextOffset;
          break;
      }
    });
  }

  void _setAnalyticsLineChartPeriod(_AnalyticsLineChartPeriod period) {
    if (_analyticsLineChartPeriod == period && _analyticsLineChartOffset == 0) {
      return;
    }
    setState(() {
      _analyticsLineChartPeriod = period;
      _analyticsLineChartOffset = 0;
    });
  }

  void _navigateAnalyticsLineChartPeriod({required bool newer}) {
    final nextOffset = newer
        ? math.min(0, _analyticsLineChartOffset + 1)
        : _analyticsLineChartOffset - 1;
    if (nextOffset == _analyticsLineChartOffset) return;
    HapticFeedback.selectionClick();
    setState(() => _analyticsLineChartOffset = nextOffset);
  }

  void _navigateAnalyticsBarChartPeriod({required bool newer}) {
    final nextOffset = newer
        ? math.min(0, _analyticsBarChartOffset + 1)
        : _analyticsBarChartOffset - 1;
    if (nextOffset == _analyticsBarChartOffset) return;
    HapticFeedback.selectionClick();
    setState(() => _analyticsBarChartOffset = nextOffset);
  }

  void _navigateAnalyticsBubbleChartPeriod({required bool newer}) {
    final nextOffset = newer
        ? math.min(0, _analyticsBubbleChartOffset + 1)
        : _analyticsBubbleChartOffset - 1;
    if (nextOffset == _analyticsBubbleChartOffset) return;
    HapticFeedback.selectionClick();
    setState(() => _analyticsBubbleChartOffset = nextOffset);
  }

  void _navigateAnalyticsPieChartPeriod({required bool newer}) {
    final nextOffset = newer
        ? math.min(0, _analyticsPieChartOffset + 1)
        : _analyticsPieChartOffset - 1;
    if (nextOffset == _analyticsPieChartOffset) return;
    HapticFeedback.selectionClick();
    setState(() => _analyticsPieChartOffset = nextOffset);
  }

  DateTime _resolveAnalyticsChartAnchorDate(
    Iterable<Transaction> transactions,
  ) {
    DateTime? latestTransactionTime;
    for (final transaction in transactions) {
      final dt = _parseTransactionTime(transaction.time);
      if (dt == null) continue;
      if (latestTransactionTime == null || dt.isAfter(latestTransactionTime)) {
        latestTransactionTime = dt;
      }
    }

    final anchor = latestTransactionTime ?? DateTime.now();
    return DateTime(anchor.year, anchor.month, anchor.day);
  }

  DateTime _resolveAnalyticsChartAnchorMonth(
    Iterable<Transaction> transactions,
  ) {
    final anchorDate = _resolveAnalyticsChartAnchorDate(transactions);
    return _resolveAnalyticsMonthWindow(anchorDate).start;
  }

  _AnalyticsCategoryChartPage _buildAnalyticsCategoryChartPage({
    required TransactionProvider provider,
    required List<Transaction> transactions,
    required _AnalyticsHeatmapFilter filter,
    required bool expandedForDateRange,
    int periodOffset = 0,
  }) {
    final anchorMonth = _resolveAnalyticsChartAnchorMonth(transactions);
    final targetMonth = _shiftAnalyticsMonth(anchorMonth, periodOffset);

    final snapshot = _buildAnalyticsSnapshot(
      provider,
      sourceTransactions: transactions,
      categoryMode: filter.mode,
      constrainSeriesToAnchorMonth: true,
      anchorDate: targetMonth,
    );

    return _AnalyticsCategoryChartPage(
      snapshot: snapshot,
      periodLabel: _formatAnalyticsChartPeriodLabel(
        context: context,
        filter: filter,
        fallbackMonthDate: targetMonth,
        expandedForDateRange: expandedForDateRange,
      ),
    );
  }

  List<Transaction> _transactionsWithinDateWindow(
    List<Transaction> transactions, {
    required DateTime start,
    required DateTime endExclusive,
  }) {
    return transactions.where((transaction) {
      final dt = _parseTransactionTime(transaction.time);
      if (dt == null) return false;
      return !dt.isBefore(start) && dt.isBefore(endExclusive);
    }).toList(growable: false);
  }

  _AnalyticsDateWindow _resolveLineChartWindow(
    List<Transaction> transactions, {
    required _AnalyticsLineChartPeriod period,
    required int periodOffset,
  }) {
    final anchorDate = _resolveAnalyticsChartAnchorDate(transactions);
    final shiftedAnchor = _shiftAnalyticsLineAnchorDate(
      anchorDate,
      period,
      periodOffset,
      context: context,
    );

    switch (period) {
      case _AnalyticsLineChartPeriod.weekly:
        final start = shiftedAnchor.subtract(
          Duration(days: shiftedAnchor.weekday - DateTime.monday),
        );
        return _AnalyticsDateWindow(
          start: start,
          endExclusive: start.add(const Duration(days: 7)),
        );
      case _AnalyticsLineChartPeriod.monthly:
        if (_usesEthiopianCalendar) {
          return _resolveAnalyticsMonthWindow(shiftedAnchor);
        }
        final start = DateTime(shiftedAnchor.year, shiftedAnchor.month, 1);
        return _AnalyticsDateWindow(
          start: start,
          endExclusive: DateTime(start.year, start.month + 1, 1),
        );
      case _AnalyticsLineChartPeriod.yearly:
        if (_usesEthiopianCalendar) {
          return _resolveAnalyticsYearWindow(shiftedAnchor);
        }
        final start = DateTime(shiftedAnchor.year, 1, 1);
        return _AnalyticsDateWindow(
          start: start,
          endExclusive: DateTime(start.year + 1, 1, 1),
        );
    }
  }

  String _formatLineChartWindowLabel(
    _AnalyticsDateWindow window,
    _AnalyticsLineChartPeriod period,
  ) {
    switch (period) {
      case _AnalyticsLineChartPeriod.weekly:
        return _formatAnalyticsDateRange(
          window.start,
          window.endExclusive.subtract(const Duration(days: 1)),
          context: context,
        );
      case _AnalyticsLineChartPeriod.monthly:
        try {
          final isEC =
              Provider.of<ThemeProvider>(context!, listen: false).appCalendar ==
                  AppCalendarOption.ethiopian;
          if (isEC) {
            final ecDate = Kenat.fromGregorian(
                    window.start.year, window.start.month, window.start.day)
                .getEthiopian();
            return '${_formatEthiopianMonthNameForContext(ecDate['month']!, context)} ${ecDate['year']}';
          }
        } catch (_) {}
        return AppDateFormat.monthYear(window.start, context: context);
      case _AnalyticsLineChartPeriod.yearly:
        try {
          final isEC =
              Provider.of<ThemeProvider>(context!, listen: false).appCalendar ==
                  AppCalendarOption.ethiopian;
          if (isEC) {
            final ecDate = Kenat.fromGregorian(
                    window.start.year, window.start.month, window.start.day)
                .getEthiopian();
            return '${_formatEthiopianMonthRangeForContext(context)} ${ecDate['year']}';
          }
        } catch (_) {}
        return AppDateFormat.yearRangeLabel(window.start, context: context);
    }
  }

  _AnalyticsDateWindow _resolveBarChartWindow(
    List<Transaction> transactions, {
    required _AnalyticsBarChartPeriod period,
    required int periodOffset,
  }) {
    final anchorDate = _resolveAnalyticsChartAnchorDate(transactions);
    final shiftedAnchor = _shiftAnalyticsBarAnchorDate(
      anchorDate,
      period,
      periodOffset,
      context: context,
    );

    switch (period) {
      case _AnalyticsBarChartPeriod.weekly:
        final start = shiftedAnchor.subtract(
          Duration(days: shiftedAnchor.weekday - DateTime.monday),
        );
        return _AnalyticsDateWindow(
          start: start,
          endExclusive: start.add(const Duration(days: 7)),
        );
      case _AnalyticsBarChartPeriod.monthly:
        if (_usesEthiopianCalendar) {
          return _resolveAnalyticsMonthWindow(shiftedAnchor);
        }
        final start = DateTime(shiftedAnchor.year, shiftedAnchor.month, 1);
        return _AnalyticsDateWindow(
          start: start,
          endExclusive: DateTime(start.year, start.month + 1, 1),
        );
      case _AnalyticsBarChartPeriod.yearly:
        if (_usesEthiopianCalendar) {
          return _resolveAnalyticsYearWindow(shiftedAnchor);
        }
        final start = DateTime(shiftedAnchor.year, 1, 1);
        return _AnalyticsDateWindow(
          start: start,
          endExclusive: DateTime(start.year + 1, 1, 1),
        );
    }
  }

  String _formatBarChartWindowLabel(
    _AnalyticsDateWindow window,
    _AnalyticsBarChartPeriod period,
  ) {
    switch (period) {
      case _AnalyticsBarChartPeriod.weekly:
        return _formatAnalyticsDateRange(
          window.start,
          window.endExclusive.subtract(const Duration(days: 1)),
          context: context,
        );
      case _AnalyticsBarChartPeriod.monthly:
        try {
          final isEC =
              Provider.of<ThemeProvider>(context!, listen: false).appCalendar ==
                  AppCalendarOption.ethiopian;
          if (isEC) {
            final ecDate = Kenat.fromGregorian(
                    window.start.year, window.start.month, window.start.day)
                .getEthiopian();
            return '${context.l10nText('W1 - W5 in')} ${_formatEthiopianMonthNameForContext(ecDate['month']!, context)} ${ecDate['year']}';
          }
        } catch (_) {}
        return '${context.l10nText('W1 - W5 in')} ${AppDateFormat.monthYear(window.start, context: context)}';
      case _AnalyticsBarChartPeriod.yearly:
        try {
          final isEC =
              Provider.of<ThemeProvider>(context!, listen: false).appCalendar ==
                  AppCalendarOption.ethiopian;
          if (isEC) {
            final ecDate = Kenat.fromGregorian(
                    window.start.year, window.start.month, window.start.day)
                .getEthiopian();
            return '${_formatEthiopianMonthRangeForContext(context)} ${ecDate['year']}';
          }
        } catch (_) {}
        return AppDateFormat.yearRangeLabel(window.start, context: context);
    }
  }

  _AnalyticsSupportContext _buildActiveAnalyticsSupportContext(
    TransactionProvider provider, {
    required List<Transaction> heatmapTransactions,
    required DateTime heatmapFocusMonth,
  }) {
    switch (_analyticsSelectedChartSection) {
      case _AnalyticsChartSection.heatmap:
        final periodStart = _analyticsHeatmapView == _AnalyticsHeatmapView.daily
            ? _normalizeAnalyticsHeatmapMonth(heatmapFocusMonth)
            : _normalizeYearStart(heatmapFocusMonth);

        DateTime periodEnd;
        try {
          final isEC = context.read<ThemeProvider>().appCalendar ==
              AppCalendarOption.ethiopian;
          if (isEC) {
            final ec = Kenat.fromGregorian(
                    periodStart.year, periodStart.month, periodStart.day)
                .getEthiopian();
            if (_analyticsHeatmapView == _AnalyticsHeatmapView.daily) {
              var y = ec['year']!;
              var m = ec['month']! + 1;
              if (m > 13) {
                m = 1;
                y++;
              }
              final gc = Kenat.fromEthiopian(y, m, 1).getGregorian();
              periodEnd = DateTime(gc['year']!, gc['month']!, gc['day']!);
            } else {
              final gc =
                  Kenat.fromEthiopian(ec['year']! + 1, 1, 1).getGregorian();
              periodEnd = DateTime(gc['year']!, gc['month']!, gc['day']!);
            }
          } else {
            periodEnd = _analyticsHeatmapView == _AnalyticsHeatmapView.daily
                ? DateTime(
                    heatmapFocusMonth.year, heatmapFocusMonth.month + 1, 1)
                : DateTime(heatmapFocusMonth.year + 1, 1, 1);
          }
        } catch (_) {
          periodEnd = _analyticsHeatmapView == _AnalyticsHeatmapView.daily
              ? DateTime(heatmapFocusMonth.year, heatmapFocusMonth.month + 1, 1)
              : DateTime(heatmapFocusMonth.year + 1, 1, 1);
        }
        return _AnalyticsSupportContext(
          transactions: _transactionsWithinDateWindow(
            heatmapTransactions,
            start: periodStart,
            endExclusive: periodEnd,
          ),
          periodLabel: _formatAnalyticsSpendingPeriodLabel(
            _analyticsHeatmapView,
            _normalizeAnalyticsHeatmapMonth(heatmapFocusMonth),
            context: context,
          ),
          periodKey:
              'heatmap-${_analyticsHeatmapView.name}-${periodStart.year}-${periodStart.month}',
          showIncome:
              _analyticsHeatmapFilter.mode == _AnalyticsHeatmapMode.income,
        );
      case _AnalyticsChartSection.expenseBubble:
        final filter = _analyticsBubbleFilter;
        final filteredTransactions = _analyticsTransactionsForFilter(
          provider,
          filter,
        );
        final usesDateRange =
            filter.startDate != null || filter.endDate != null;
        if (usesDateRange) {
          return _AnalyticsSupportContext(
            transactions: filteredTransactions,
            periodLabel: _formatAnalyticsChartPeriodLabel(
              context: context,
              filter: filter,
              fallbackMonthDate:
                  _resolveAnalyticsChartAnchorMonth(filteredTransactions),
              expandedForDateRange: true,
            ),
            periodKey:
                'bubble-range-${filter.mode.name}-${filter.bankId ?? 'all'}-${filter.startDate?.millisecondsSinceEpoch ?? 'none'}-${filter.endDate?.millisecondsSinceEpoch ?? 'none'}',
            showIncome: filter.mode == _AnalyticsHeatmapMode.income,
          );
        }
        final anchorMonth = _resolveAnalyticsChartAnchorMonth(
          filteredTransactions,
        );
        DateTime targetMonth;
        try {
          final isEC = context.read<ThemeProvider>().appCalendar ==
              AppCalendarOption.ethiopian;
          if (isEC) {
            final ec = Kenat.fromGregorian(
              anchorMonth.year,
              anchorMonth.month,
              anchorMonth.day,
            ).getEthiopian();
            var y = ec['year']!;
            var m = ec['month']! + _analyticsBubbleChartOffset;
            while (m > 13) {
              m -= 13;
              y++;
            }
            while (m < 1) {
              m += 13;
              y--;
            }
            final gc = Kenat.fromEthiopian(y, m, 1).getGregorian();
            targetMonth = DateTime(gc['year']!, gc['month']!, gc['day']!);
          } else {
            targetMonth = DateTime(
              anchorMonth.year,
              anchorMonth.month + _analyticsBubbleChartOffset,
              1,
            );
          }
        } catch (_) {
          targetMonth = DateTime(
            anchorMonth.year,
            anchorMonth.month + _analyticsBubbleChartOffset,
            1,
          );
        }
        final monthWindow = _resolveAnalyticsMonthWindow(targetMonth);
        return _AnalyticsSupportContext(
          transactions: _transactionsWithinDateWindow(
            filteredTransactions,
            start: monthWindow.start,
            endExclusive: monthWindow.endExclusive,
          ),
          periodLabel: _formatAnalyticsChartPeriodLabel(
            context: context,
            filter: filter,
            fallbackMonthDate: monthWindow.start,
            expandedForDateRange: true,
          ),
          periodKey:
              'bubble-${filter.mode.name}-${monthWindow.start.year}-${monthWindow.start.month}',
          showIncome: filter.mode == _AnalyticsHeatmapMode.income,
        );
      case _AnalyticsChartSection.lineChart:
        final filter = _analyticsLineFilter;
        final filteredTransactions = _analyticsTransactionsForFilter(
          provider,
          filter,
        );
        final window = _resolveLineChartWindow(
          filteredTransactions,
          period: _analyticsLineChartPeriod,
          periodOffset: _analyticsLineChartOffset,
        );
        return _AnalyticsSupportContext(
          transactions: _transactionsWithinDateWindow(
            filteredTransactions,
            start: window.start,
            endExclusive: window.endExclusive,
          ),
          periodLabel: _formatLineChartWindowLabel(
            window,
            _analyticsLineChartPeriod,
          ),
          periodKey:
              'line-${_analyticsLineChartPeriod.name}-${window.start.year}-${window.start.month}-${window.start.day}',
          showIncome: filter.mode == _AnalyticsHeatmapMode.income,
        );
      case _AnalyticsChartSection.barChart:
        final filter = _analyticsBarFilter;
        final filteredTransactions = _analyticsTransactionsForFilter(
          provider,
          filter,
        );
        final window = _resolveBarChartWindow(
          filteredTransactions,
          period: filter.barPeriod,
          periodOffset: _analyticsBarChartOffset,
        );
        return _AnalyticsSupportContext(
          transactions: _transactionsWithinDateWindow(
            filteredTransactions,
            start: window.start,
            endExclusive: window.endExclusive,
          ),
          periodLabel: _formatBarChartWindowLabel(window, filter.barPeriod),
          periodKey:
              'bar-${filter.mode.name}-${filter.barPeriod.name}-${window.start.year}-${window.start.month}-${window.start.day}',
          showIncome: filter.mode == _AnalyticsHeatmapMode.income,
        );
      case _AnalyticsChartSection.pieChart:
        final filter = _analyticsPieFilter;
        final filteredTransactions = _analyticsTransactionsForFilter(
          provider,
          filter,
        );
        final usesDateRange =
            filter.startDate != null || filter.endDate != null;
        if (usesDateRange) {
          return _AnalyticsSupportContext(
            transactions: filteredTransactions,
            periodLabel: _formatAnalyticsChartPeriodLabel(
              context: context,
              filter: filter,
              fallbackMonthDate:
                  _resolveAnalyticsChartAnchorMonth(filteredTransactions),
            ),
            periodKey:
                'pie-range-${filter.mode.name}-${filter.bankId ?? 'all'}-${filter.startDate?.millisecondsSinceEpoch ?? 'none'}-${filter.endDate?.millisecondsSinceEpoch ?? 'none'}',
            showIncome: filter.mode == _AnalyticsHeatmapMode.income,
          );
        }
        final anchorMonth = _resolveAnalyticsChartAnchorMonth(
          filteredTransactions,
        );
        DateTime targetMonth;
        try {
          final isEC = context.read<ThemeProvider>().appCalendar ==
              AppCalendarOption.ethiopian;
          if (isEC) {
            final ec = Kenat.fromGregorian(
              anchorMonth.year,
              anchorMonth.month,
              anchorMonth.day,
            ).getEthiopian();
            var y = ec['year']!;
            var m = ec['month']! + _analyticsPieChartOffset;
            while (m > 13) {
              m -= 13;
              y++;
            }
            while (m < 1) {
              m += 13;
              y--;
            }
            final gc = Kenat.fromEthiopian(y, m, 1).getGregorian();
            targetMonth = DateTime(gc['year']!, gc['month']!, gc['day']!);
          } else {
            targetMonth = DateTime(
              anchorMonth.year,
              anchorMonth.month + _analyticsPieChartOffset,
              1,
            );
          }
        } catch (_) {
          targetMonth = DateTime(
            anchorMonth.year,
            anchorMonth.month + _analyticsPieChartOffset,
            1,
          );
        }
        final monthWindow = _resolveAnalyticsMonthWindow(targetMonth);
        return _AnalyticsSupportContext(
          transactions: _transactionsWithinDateWindow(
            filteredTransactions,
            start: monthWindow.start,
            endExclusive: monthWindow.endExclusive,
          ),
          periodLabel: _formatAnalyticsChartPeriodLabel(
            context: context,
            filter: filter,
            fallbackMonthDate: monthWindow.start,
          ),
          periodKey:
              'pie-${filter.mode.name}-${monthWindow.start.year}-${monthWindow.start.month}',
          showIncome: filter.mode == _AnalyticsHeatmapMode.income,
        );
    }
  }

  void _setAnalyticsChartFlowMode(
    TransactionProvider provider,
    _AnalyticsChartSection section,
    _AnalyticsHeatmapMode mode,
  ) {
    if (mode == _AnalyticsHeatmapMode.all) return;
    final currentFilter = _analyticsFilterForSection(section);
    if (currentFilter.mode == mode) return;
    _setAnalyticsFilterForSection(
      provider,
      section,
      currentFilter.copyWith(mode: mode),
    );
  }

  List<Transaction> _analyticsTransactionsForFilter(
    TransactionProvider provider,
    _AnalyticsHeatmapFilter filter,
  ) {
    return provider.allTransactions
        .where(
          (transaction) =>
              _matchesAnalyticsHeatmapFilterValue(transaction, filter),
        )
        .toList(growable: false);
  }

  Future<void> _openAnalyticsChartSheet() async {
    final selectedSection = await showModalBottomSheet<_AnalyticsChartSection>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomPadding = MediaQuery.of(sheetContext).padding.bottom;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.background(sheetContext),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary(sheetContext)
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    sheetContext.l10nText('Select chart'),
                    style: TextStyle(
                      color: AppColors.textPrimary(sheetContext),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sheetContext.l10nText('Choose a chart.'),
                    style: TextStyle(
                      color: AppColors.textSecondary(sheetContext),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._AnalyticsChartSection.values.map(
                    (section) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _AnalyticsBottomSheetOption(
                        title: section.title,
                        selected: section == _analyticsSelectedChartSection,
                        onTap: () => Navigator.of(sheetContext).pop(section),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted || selectedSection == null) return;
    setState(() => _analyticsSelectedChartSection = selectedSection);
  }

  Future<void> _openAnalyticsFilterSheet(
    TransactionProvider provider,
    _AnalyticsChartSection section,
  ) async {
    final bankIds = <int>{};
    final categoryIds = <int>{};
    for (final transaction in provider.allTransactions) {
      if (transaction.bankId != null) bankIds.add(transaction.bankId!);
      if (transaction.categoryId != null) {
        categoryIds.add(transaction.categoryId!);
      }
    }

    final categories = categoryIds
        .map((id) => provider.getCategoryById(id))
        .whereType<Category>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final selectedFilter = await showModalBottomSheet<_AnalyticsHeatmapFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnalyticsChartFilterSheet(
        chartSection: section,
        currentFilter: _analyticsFilterForSection(section),
        bankIds: section.showsBankFilter
            ? (bankIds.toList()..sort())
            : const <int>[],
        categories:
            section.showsCategoryFilter ? categories : const <Category>[],
      ),
    );
    if (!mounted || selectedFilter == null) {
      return;
    }
    _setAnalyticsFilterForSection(provider, section, selectedFilter);
  }

  void _setSubTab(_SubTab nextTab) {
    if (_subTab == nextTab) return;
    setState(() {
      _subTab = nextTab;
      if (nextTab != _SubTab.transactions) {
        _selectedRefs.clear();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncActivityPinnedHeaderDivider();
    });
    _subTabFadeController.forward(from: 0);
    HapticFeedback.selectionClick();
    if (_activityScrollController.hasClients) {
      _activityScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _setTopTab(_TopTab nextTab) {
    if (_topTab == nextTab) return;
    setState(() => _topTab = nextTab);
    HapticFeedback.selectionClick();
  }

  void _setActivityTransactionsPage(int page) {
    if (_currentPage == page) return;
    setState(() => _currentPage = page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_activityScrollController.hasClients) {
        return;
      }
      _activityScrollController.jumpTo(
        _activityScrollController.position.minScrollExtent,
      );
    });
  }

  void openAccountsTab() {
    _setTopTab(_TopTab.accounts);
  }

  void _toggleSelection(Transaction transaction) {
    setState(() {
      if (_selectedRefs.contains(transaction.reference)) {
        _selectedRefs.remove(transaction.reference);
      } else {
        _selectedRefs.add(transaction.reference);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedRefs.clear());

  Future<void> _deleteSelected(TransactionProvider provider) async {
    if (_selectedRefs.isEmpty) return;
    final count = _selectedRefs.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardColor(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete $count transaction${count > 1 ? 's' : ''}?',
          style: TextStyle(color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          'This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              ctx.l10nText('Cancel'),
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
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
    );
    if (!mounted || confirmed != true) return;
    final refs = _selectedRefs.toList();
    _clearSelection();
    try {
      await provider.deleteTransactionsByReferences(refs);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10nTextRead('Deleted')} $count ${context.l10nTextRead(count > 1 ? 'transactions' : 'transaction')}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10nTextRead('Failed to delete')}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _activityScrollController.removeListener(_syncActivityPinnedHeaderDivider);
    _showActivityPinnedHeaderDivider.dispose();
    _subTabFadeController.dispose();
    _searchController.dispose();
    _activityScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _TopTabBar(
                selectedTab: _topTab,
                onTabChanged: _setTopTab,
              ),
            ),
            Expanded(
              child: _topTab == _TopTab.activity
                  ? Selector<TransactionProvider, _ProviderContentVersion>(
                      selector: (_, provider) => _ProviderContentVersion(
                        dataVersion: provider.dataVersion,
                        isLoading: provider.isLoading,
                      ),
                      builder: (context, _, __) => _buildActivityContent(
                          context.read<TransactionProvider>()),
                    )
                  : Consumer<AccountSyncStatusService>(
                      builder: (context, syncStatusService, _) => Selector<
                          TransactionProvider, _ProviderContentVersion>(
                        selector: (_, provider) => _ProviderContentVersion(
                          dataVersion: provider.dataVersion,
                          isLoading: provider.isLoading,
                        ),
                        builder: (context, _, __) => _buildAccountsContent(
                          context.read<TransactionProvider>(),
                          syncStatusService,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityContent(TransactionProvider provider) {
    final healthSnapshot = provider.financialHealth;
    final transactionsViewData = _subTab == _SubTab.transactions
        ? _resolveActivityTransactionsViewData(provider)
        : null;
    final activityTransactionsSummary = transactionsViewData?.summary;
    final ledgerViewSummary =
        _subTab == _SubTab.ledger ? _resolveLedgerViewSummary(provider) : null;
    final totalPages = transactionsViewData?.totalPages ?? 1;
    final safePage = transactionsViewData?.safePage ?? 0;
    final flatItems = transactionsViewData?.flatItems ?? const <Object>[];
    final showsPagination = _subTab == _SubTab.transactions &&
        flatItems.isNotEmpty &&
        totalPages > 1;
    final transactionsListKey = ValueKey<_ActivityTransactionsViewCacheKey?>(
      transactionsViewData == null ? null : _activityTransactionsViewCacheKey,
    );

    final dynamicSlivers = <Widget>[
      if (_subTab == _SubTab.transactions) ...[
        if (_isSelecting)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _SelectionBar(
                count: _selectedRefs.length,
                onDelete: () => _deleteSelected(provider),
                onClear: _clearSelection,
              ),
            ),
          ),
        // Keep rendering existing rows during provider reloads so
        // category updates do not collapse scroll extent and jump to top.
        if (flatItems.isEmpty && provider.isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _LoadingTransactions(),
            ),
          )
        else if (flatItems.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _EmptyTransactions(),
            ),
          )
        else ...[
          SliverPadding(
            key: transactionsListKey,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            sliver: SliverList.builder(
              itemCount: flatItems.length,
              itemBuilder: (context, index) {
                final item = flatItems[index];
                if (item is String) {
                  return _DateHeader(label: item);
                }
                final transaction = item as Transaction;
                return _buildTransactionTile(provider, transaction);
              },
            ),
          ),
          if (showsPagination)
            SliverToBoxAdapter(
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Align(
                  alignment: Alignment.center,
                  child: _PaginationBar(
                    currentPage: safePage,
                    totalPages: totalPages,
                    onPageChanged: _setActivityTransactionsPage,
                  ),
                ),
              ),
            ),
        ],
      ] else if (_subTab == _SubTab.analytics) ...[
        ..._buildAnalyticsSlivers(provider),
      ] else if (_subTab == _SubTab.ledger) ...[
        ..._buildLedgerSlivers(provider, ledgerViewSummary!),
      ],
    ];

    return Column(
      children: [
        _buildActivityPinnedHeader(
          provider: provider,
          financialHealth: healthSnapshot,
          activityTransactionsSummary: activityTransactionsSummary,
          ledgerViewSummary: ledgerViewSummary,
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primaryLight,
            onRefresh: provider.loadData,
            child: CustomScrollView(
              controller: _activityScrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFadeTransition(
                  opacity: _subTabFadeAnimation,
                  sliver: SliverMainAxisGroup(slivers: dynamicSlivers),
                ),
                const SliverPadding(
                  padding: EdgeInsets.only(bottom: 24),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityPinnedHeader({
    required TransactionProvider provider,
    required FinancialHealthSnapshot financialHealth,
    required _ActivityTransactionsSummary? activityTransactionsSummary,
    required _LedgerViewSummary? ledgerViewSummary,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background(context),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FinancialHealthCard(
                  financialHealth: financialHealth,
                  onTap: () => _showFinancialHealthSheet(financialHealth),
                ),
                const SizedBox(height: 16),
                _SubTabBar(
                  selectedTab: _subTab,
                  onTabChanged: _setSubTab,
                ),
                if (_subTab == _SubTab.transactions) ...[
                  const SizedBox(height: 12),
                  _SearchFilterRow(
                    controller: _searchController,
                    onChanged: (value) => setState(() {
                      _searchQuery = value;
                      _currentPage = 0;
                    }),
                    onFilterTap: () => _openFilterSheet(provider),
                    activeFilterCount: _filter.activeCount,
                  ),
                  if (!(provider.isLoading &&
                          provider.allTransactions.isEmpty) &&
                      activityTransactionsSummary != null) ...[
                    const SizedBox(height: 12),
                    _ActivityTransactionsSummaryRow(
                      summary: activityTransactionsSummary,
                    ),
                  ],
                ] else if (_subTab == _SubTab.ledger) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _LedgerHeaderSummary(
                          startingDate: ledgerViewSummary?.startingDate,
                          startingBalance: ledgerViewSummary?.startingBalance,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FilterActionButton(
                        onTap: () => _openLedgerFilterSheet(provider),
                        activeFilterCount: _ledgerFilter.activeCount,
                        size: 38,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ValueListenableBuilder<bool>(
                valueListenable: _showActivityPinnedHeaderDivider,
                builder: (context, showDivider, child) => AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  opacity: showDivider ? 1 : 0,
                  child: child,
                ),
                child: Container(
                  height: 1,
                  color: AppColors.borderColor(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(
    TransactionProvider provider,
    Transaction transaction,
  ) {
    final bankLabel = _localizedBankLabel(context, transaction.bankId);
    final category = provider.getCategoryById(transaction.categoryId);
    final isSelfTransfer = provider.isSelfTransfer(transaction);
    final isMisc = category?.uncategorized == true;
    final categoryLabel = isSelfTransfer
        ? context.l10nText('Self')
        : provider.categoryLabelForTransaction(
            transaction,
            uncategorizedLabel: 'Categorize',
          );
    final localizedCategoryLabel = context.l10nText(categoryLabel);
    final isCategorized =
        isSelfTransfer || transaction.selectedCategoryIds.isNotEmpty;
    final isCredit = transaction.type == 'CREDIT';

    final selected = _selectedRefs.contains(transaction.reference);
    return TransactionTile(
      bank: bankLabel,
      category: localizedCategoryLabel,
      categoryModel: category,
      personLabel: provider.loanDebtPersonNameForTransaction(transaction),
      onPersonTap: (personName) => openLoansPersonPage(
        context: context,
        personName: personName,
      ),
      isCategorized: isCategorized,
      isDebit: !isCredit,
      isSelfTransfer: isSelfTransfer,
      isMisc: isMisc,
      isSharing: provider.isSharingSharedExpenseTransaction(transaction),
      isShared: provider.isSharedExpenseTransaction(transaction),
      amount: _amountLabel(
        context,
        transaction.amount,
        isCredit: isCredit,
      ),
      amountColor: isCredit ? AppColors.incomeSuccess : AppColors.red,
      name: _localizedTransactionCounterparty(
        context,
        transaction,
        isSelfTransfer: isSelfTransfer,
      ),
      timestamp: _transactionTimeLabel(transaction, context),
      selected: selected,
      onTap: _isSelecting
          ? () => _toggleSelection(transaction)
          : () => _openTransactionDetailsSheet(provider, transaction),
      onCategoryTap: _isSelecting
          ? () => _toggleSelection(transaction)
          : () => _openTransactionCategorySheet(provider, transaction),
      onLongPress: () => _toggleSelection(transaction),
    );
  }

  Future<void> _openTransactionDetailsSheet(
    TransactionProvider provider,
    Transaction transaction,
  ) async {
    await showTransactionDetailsSheet(
      context: context,
      transaction: transaction,
      provider: provider,
    );
  }

  Future<void> _openTransactionCategorySheet(
    TransactionProvider provider,
    Transaction transaction,
  ) async {
    await showTransactionCategorySheet(
      context: context,
      transaction: transaction,
      provider: provider,
    );
  }

  bool _matchesAnalyticsHeatmapFilter(Transaction transaction) {
    return _matchesAnalyticsHeatmapFilterValue(
      transaction,
      _analyticsHeatmapFilter,
    );
  }

  List<Transaction> _transactionsForHeatmapDay(
    DateTime day,
    TransactionProvider provider,
  ) {
    return _transactionsForHeatmapDayWithFilter(
      day: day,
      allTransactions: provider.allTransactions,
      filter: _analyticsHeatmapFilter,
    );
  }

  Future<void> _openHeatmapDayLedger(
    DateTime day,
    TransactionProvider provider,
  ) async {
    final transactions = _transactionsForHeatmapDay(day, provider);
    if (transactions.isEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10nTextRead('No transactions were recorded on')} ${_formatDateHeader(day, context)}.',
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _HeatmapDayLedgerPage(
          date: day,
          filter: _analyticsHeatmapFilter,
        ),
      ),
    );
  }

  List<Widget> _buildAnalyticsSlivers(TransactionProvider provider) {
    final heatmapTransactions = provider.allTransactions
        .where(_matchesAnalyticsHeatmapFilter)
        .toList(growable: false);
    final heatmapSnapshot = _buildAnalyticsSnapshot(
      provider,
      sourceTransactions: heatmapTransactions,
      anchorTransactions: provider.allTransactions,
      categoryMode: _analyticsHeatmapFilter.mode,
    );
    final heatmapFocusMonth =
        _resolveAnalyticsHeatmapFocusMonth(heatmapSnapshot.monthDate);
    final activeSupportContext = _buildActiveAnalyticsSupportContext(
      provider,
      heatmapTransactions: heatmapTransactions,
      heatmapFocusMonth: heatmapFocusMonth,
    );
    final spendingByDaySnapshot = _buildAnalyticsSpendingByDaySnapshot(
      provider,
      transactions: activeSupportContext.transactions,
      periodLabel: activeSupportContext.periodLabel,
      periodKey: activeSupportContext.periodKey,
      showIncome: activeSupportContext.showIncome,
    );
    final topRecipientsSnapshot = _buildAnalyticsTopRecipientsSnapshot(
      provider,
      transactions: activeSupportContext.transactions,
      periodLabel: activeSupportContext.periodLabel,
      periodKey: activeSupportContext.periodKey,
      showIncome: activeSupportContext.showIncome,
    );
    final moneyFlowSnapshot = _buildAnalyticsMoneyFlowSnapshot(
      transactions: activeSupportContext.transactions,
      periodLabel: activeSupportContext.periodLabel,
      periodKey: activeSupportContext.periodKey,
    );
    final overviewSnapshot = _buildAnalyticsSnapshot(
      provider,
      sourceTransactions: activeSupportContext.transactions,
      anchorTransactions: activeSupportContext.transactions,
      categoryMode:
          _analyticsFilterForSection(_analyticsSelectedChartSection).mode,
      constrainSeriesToAnchorMonth: false,
    );
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            children: [
              _buildPrimaryAnalyticsChart(
                provider: provider,
                heatmapTransactions: heatmapTransactions,
                heatmapFocusMonth: heatmapFocusMonth,
              ),
              const SizedBox(height: 14),
              _AnalyticsSpendingByDayCard(snapshot: spendingByDaySnapshot),
              const SizedBox(height: 14),
              _AnalyticsTopRecipientsCard(snapshot: topRecipientsSnapshot),
              const SizedBox(height: 14),
              _AnalyticsMoneyFlowCard(snapshot: moneyFlowSnapshot),
              const SizedBox(height: 14),
              _AnalyticsOverviewGrid(snapshot: overviewSnapshot),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildPrimaryAnalyticsChart({
    required TransactionProvider provider,
    required List<Transaction> heatmapTransactions,
    required DateTime heatmapFocusMonth,
  }) {
    switch (_analyticsSelectedChartSection) {
      case _AnalyticsChartSection.heatmap:
        return _AnalyticsHeatmapCard(
          transactions: heatmapTransactions,
          focusMonth: heatmapFocusMonth,
          view: _analyticsHeatmapView,
          mode: _analyticsHeatmapFilter.mode,
          activeFilterCount: _AnalyticsChartSection.heatmap.activeFilterCount(
            _analyticsHeatmapFilter,
          ),
          onOpenModeSheet: () => _openAnalyticsFilterSheet(
            provider,
            _AnalyticsChartSection.heatmap,
          ),
          onOpenChartSheet: _openAnalyticsChartSheet,
          onPrevious: () => _shiftAnalyticsHeatmapPeriod(heatmapFocusMonth, -1),
          onNext: () => _shiftAnalyticsHeatmapPeriod(heatmapFocusMonth, 1),
          onToggleView: () => _toggleAnalyticsHeatmapView(heatmapFocusMonth),
          onDaySelected: (date) => _openHeatmapDayLedger(date, provider),
          onMonthSelected: _selectAnalyticsHeatmapMonth,
        );
      case _AnalyticsChartSection.expenseBubble:
        final filter = _analyticsBubbleFilter;
        final filteredTransactions = _analyticsTransactionsForFilter(
          provider,
          filter,
        );
        final usesDateRange =
            filter.startDate != null || filter.endDate != null;
        final currentPage = usesDateRange
            ? _AnalyticsCategoryChartPage(
                snapshot: _buildAnalyticsSnapshot(
                  provider,
                  sourceTransactions: filteredTransactions,
                  anchorTransactions: filteredTransactions,
                  categoryMode: filter.mode,
                  constrainSeriesToAnchorMonth: false,
                ),
                periodLabel: _formatAnalyticsChartPeriodLabel(
                  context: context,
                  filter: filter,
                  fallbackMonthDate:
                      _resolveAnalyticsChartAnchorMonth(filteredTransactions),
                  expandedForDateRange: true,
                ),
              )
            : _buildAnalyticsCategoryChartPage(
                provider: provider,
                transactions: filteredTransactions,
                filter: filter,
                expandedForDateRange: true,
                periodOffset: _analyticsBubbleChartOffset,
              );
        final previousPage = usesDateRange
            ? null
            : _buildAnalyticsCategoryChartPage(
                provider: provider,
                transactions: filteredTransactions,
                filter: filter,
                expandedForDateRange: true,
                periodOffset: _analyticsBubbleChartOffset - 1,
              );
        final hasNewerBubblePeriod =
            !usesDateRange && _analyticsBubbleChartOffset < 0;
        final nextPage = usesDateRange
            ? null
            : hasNewerBubblePeriod
                ? _buildAnalyticsCategoryChartPage(
                    provider: provider,
                    transactions: filteredTransactions,
                    filter: filter,
                    expandedForDateRange: true,
                    periodOffset: _analyticsBubbleChartOffset + 1,
                  )
                : currentPage;
        return _AnalyticsExpenseBubbleCard(
          currentPage: currentPage,
          previousPage: previousPage,
          nextPage: nextPage,
          showIncome: filter.mode == _AnalyticsHeatmapMode.income,
          usesCustomDateRange: usesDateRange,
          onNavigateToOlderPeriod: usesDateRange
              ? null
              : () => _navigateAnalyticsBubbleChartPeriod(newer: false),
          onNavigateToNewerPeriod: hasNewerBubblePeriod
              ? () => _navigateAnalyticsBubbleChartPeriod(newer: true)
              : null,
          activeFilterCount:
              _AnalyticsChartSection.expenseBubble.activeFilterCount(filter),
          onOpenFilterSheet: () => _openAnalyticsFilterSheet(
            provider,
            _AnalyticsChartSection.expenseBubble,
          ),
          onChartPickerTap: _openAnalyticsChartSheet,
          onFlowModeChanged: (mode) => _setAnalyticsChartFlowMode(
            provider,
            _AnalyticsChartSection.expenseBubble,
            mode,
          ),
        );
      case _AnalyticsChartSection.lineChart:
        final filter = _analyticsLineFilter;
        final filteredTransactions = _analyticsTransactionsForFilter(
          provider,
          filter,
        );
        return _AnalyticsLineChartCard(
          provider: provider,
          transactions: filteredTransactions,
          period: _analyticsLineChartPeriod,
          periodOffset: _analyticsLineChartOffset,
          onPeriodChanged: _setAnalyticsLineChartPeriod,
          onNavigateToOlderPeriod: () =>
              _navigateAnalyticsLineChartPeriod(newer: false),
          onNavigateToNewerPeriod: () =>
              _navigateAnalyticsLineChartPeriod(newer: true),
          activeFilterCount: _AnalyticsChartSection.lineChart.activeFilterCount(
            filter,
          ),
          onOpenFilterSheet: () => _openAnalyticsFilterSheet(
              provider, _AnalyticsChartSection.lineChart),
          onChartPickerTap: _openAnalyticsChartSheet,
        );
      case _AnalyticsChartSection.barChart:
        final filter = _analyticsBarFilter;
        final filteredTransactions = _analyticsTransactionsForFilter(
          provider,
          filter,
        );
        return _AnalyticsBarChartCard(
          provider: provider,
          transactions: filteredTransactions,
          filter: filter,
          periodOffset: _analyticsBarChartOffset,
          onNavigateToOlderPeriod: () =>
              _navigateAnalyticsBarChartPeriod(newer: false),
          onNavigateToNewerPeriod: () =>
              _navigateAnalyticsBarChartPeriod(newer: true),
          activeFilterCount: _AnalyticsChartSection.barChart.activeFilterCount(
            filter,
          ),
          onOpenFilterSheet: () => _openAnalyticsFilterSheet(
              provider, _AnalyticsChartSection.barChart),
          onChartPickerTap: _openAnalyticsChartSheet,
        );
      case _AnalyticsChartSection.pieChart:
        final filter = _analyticsPieFilter;
        final filteredTransactions = _analyticsTransactionsForFilter(
          provider,
          filter,
        );
        final usesDateRange =
            filter.startDate != null || filter.endDate != null;
        final currentPage = usesDateRange
            ? _AnalyticsCategoryChartPage(
                snapshot: _buildAnalyticsSnapshot(
                  provider,
                  sourceTransactions: filteredTransactions,
                  anchorTransactions: filteredTransactions,
                  categoryMode: filter.mode,
                  constrainSeriesToAnchorMonth: false,
                ),
                periodLabel: _formatAnalyticsChartPeriodLabel(
                  context: context,
                  filter: filter,
                  fallbackMonthDate:
                      _resolveAnalyticsChartAnchorMonth(filteredTransactions),
                ),
              )
            : _buildAnalyticsCategoryChartPage(
                provider: provider,
                transactions: filteredTransactions,
                filter: filter,
                expandedForDateRange: false,
                periodOffset: _analyticsPieChartOffset,
              );
        final previousPage = usesDateRange
            ? null
            : _buildAnalyticsCategoryChartPage(
                provider: provider,
                transactions: filteredTransactions,
                filter: filter,
                expandedForDateRange: false,
                periodOffset: _analyticsPieChartOffset - 1,
              );
        final hasNewerPiePeriod =
            !usesDateRange && _analyticsPieChartOffset < 0;
        final nextPage = usesDateRange
            ? null
            : hasNewerPiePeriod
                ? _buildAnalyticsCategoryChartPage(
                    provider: provider,
                    transactions: filteredTransactions,
                    filter: filter,
                    expandedForDateRange: false,
                    periodOffset: _analyticsPieChartOffset + 1,
                  )
                : currentPage;
        return _AnalyticsPieChartCard(
          currentPage: currentPage,
          previousPage: previousPage,
          nextPage: nextPage,
          showIncome: filter.mode == _AnalyticsHeatmapMode.income,
          usesCustomDateRange: usesDateRange,
          onNavigateToOlderPeriod: usesDateRange
              ? null
              : () => _navigateAnalyticsPieChartPeriod(newer: false),
          onNavigateToNewerPeriod: hasNewerPiePeriod
              ? () => _navigateAnalyticsPieChartPeriod(newer: true)
              : null,
          activeFilterCount: _AnalyticsChartSection.pieChart.activeFilterCount(
            filter,
          ),
          onOpenFilterSheet: () => _openAnalyticsFilterSheet(
              provider, _AnalyticsChartSection.pieChart),
          onFlowModeChanged: (mode) => _setAnalyticsChartFlowMode(
            provider,
            _AnalyticsChartSection.pieChart,
            mode,
          ),
          onChartPickerTap: _openAnalyticsChartSheet,
        );
    }
  }

  _AnalyticsSnapshot _buildAnalyticsSnapshot(
    TransactionProvider provider, {
    List<Transaction>? sourceTransactions,
    Iterable<Transaction>? anchorTransactions,
    _AnalyticsHeatmapMode categoryMode = _AnalyticsHeatmapMode.expense,
    bool constrainSeriesToAnchorMonth = true,
    DateTime? anchorDate,
  }) {
    final transactions = sourceTransactions ?? provider.allTransactions;
    final anchorSource = anchorTransactions ?? transactions;
    DateTime? latestTransactionTime;
    for (final transaction in anchorSource) {
      final dt = _parseTransactionTime(transaction.time);
      if (dt == null) continue;
      if (latestTransactionTime == null || dt.isAfter(latestTransactionTime)) {
        latestTransactionTime = dt;
      }
    }

    final anchor = anchorDate ?? latestTransactionTime ?? DateTime.now();
    final monthWindow = _resolveAnalyticsMonthWindow(anchor);
    final monthStart = monthWindow.start;
    final nextMonthStart = monthWindow.endExclusive;
    final isEthiopianCalendar = _usesEthiopianCalendar;

    final byDayIncome = <int, double>{};
    final byDayExpense = <int, double>{};
    final byDayNet = <int, double>{};
    final weekdayExpenseTotals = List<double>.filled(7, 0.0);
    final categoryTotals = <String, double>{};
    final recipientTotals = <String, _AnalyticsRecipientAccumulator>{};

    var incomeCount = 0;
    var expenseCount = 0;
    var totalFees = 0.0;
    var totalTransactions = 0;
    var totalIncome = 0.0;
    var totalExpense = 0.0;
    var recipientExpenseCount = 0;
    var largestExpense = 0.0;
    var largestDeposit = 0.0;

    for (final transaction in transactions) {
      final isCredit = transaction.type == 'CREDIT';
      final isDebit = transaction.type == 'DEBIT';
      final dt = _parseTransactionTime(transaction.time);
      final isWithinAnchorMonth =
          dt != null && !dt.isBefore(monthStart) && dt.isBefore(nextMonthStart);

      if (constrainSeriesToAnchorMonth && !isWithinAnchorMonth) {
        continue;
      }

      totalTransactions += 1;
      totalFees +=
          (transaction.serviceCharge ?? 0.0) + (transaction.vat ?? 0.0);

      final isSelfTransfer =
          isDebit ? provider.isSelfTransfer(transaction) : false;
      final category = transaction.categoryId == null
          ? null
          : provider.getCategoryById(transaction.categoryId!);
      final isMisc = category?.uncategorized == true;

      if (isCredit) {
        totalIncome += transaction.amount;
        incomeCount += 1;
        largestDeposit = math.max(largestDeposit, transaction.amount);
      } else if (isDebit) {
        totalExpense += transaction.amount;
        expenseCount += 1;
        largestExpense = math.max(largestExpense, transaction.amount);
      }

      if (isDebit && !isSelfTransfer && !isMisc) {
        recipientExpenseCount += 1;
        final recipient = _transactionCounterparty(transaction);
        final existing = recipientTotals.putIfAbsent(
          recipient,
          () => _AnalyticsRecipientAccumulator(),
        );
        existing.amount += transaction.amount;
        existing.count += 1;
      }

      if (dt == null) continue;

      final day = isEthiopianCalendar
          ? Kenat.fromGregorian(dt.year, dt.month, dt.day)
              .getEthiopian()['day']!
          : dt.day;

      if (isCredit) {
        byDayIncome[day] = (byDayIncome[day] ?? 0.0) + transaction.amount;
        byDayNet[day] = (byDayNet[day] ?? 0.0) + transaction.amount;
      } else if (isDebit) {
        byDayExpense[day] = (byDayExpense[day] ?? 0.0) + transaction.amount;
        byDayNet[day] = (byDayNet[day] ?? 0.0) - transaction.amount;
      }

      final includeBubbleCategory =
          categoryMode == _AnalyticsHeatmapMode.income ? isCredit : isDebit;
      final skipBubbleCategory = categoryMode == _AnalyticsHeatmapMode.income
          ? isMisc
          : isSelfTransfer || isMisc;

      if (includeBubbleCategory && !skipBubbleCategory) {
        final categoryName = (category?.name.trim().isNotEmpty ?? false)
            ? category!.name.trim()
            : 'Other';
        categoryTotals[categoryName] =
            (categoryTotals[categoryName] ?? 0.0) + transaction.amount;
      }

      if (isDebit && !isSelfTransfer && !isMisc) {
        final weekdayIndex = dt.weekday % 7; // Sunday = 0 ... Saturday = 6
        weekdayExpenseTotals[weekdayIndex] += transaction.amount;
      }
    }

    final categoryEntries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final categoryStats = <_AnalyticsCategoryStat>[];
    for (int i = 0; i < categoryEntries.length && i < 8; i++) {
      final entry = categoryEntries[i];
      categoryStats.add(
        _AnalyticsCategoryStat(
          label: entry.key,
          amount: entry.value,
          color: _analyticsPaletteColor(i),
        ),
      );
    }

    final recipientEntries = recipientTotals.entries.toList()
      ..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    final topRecipients = recipientEntries
        .take(5)
        .map(
          (entry) => _AnalyticsRecipientStat(
            name: entry.key,
            amount: entry.value.amount,
            count: entry.value.count,
          ),
        )
        .toList(growable: false);

    var peakWeekdayIndex = 0;
    var peakValue = -1.0;
    for (int i = 0; i < weekdayExpenseTotals.length; i++) {
      if (weekdayExpenseTotals[i] > peakValue) {
        peakValue = weekdayExpenseTotals[i];
        peakWeekdayIndex = i;
      }
    }

    final netCashFlow = totalIncome - totalExpense;
    final savingsRate = totalIncome > 0
        ? ((netCashFlow / totalIncome) * 100).clamp(-999.0, 999.0).toDouble()
        : 0.0;

    return _AnalyticsSnapshot(
      monthDate: monthStart,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      totalFees: totalFees,
      totalTransactions: totalTransactions,
      incomeCount: incomeCount,
      expenseCount: expenseCount,
      recipientExpenseCount: recipientExpenseCount,
      incomeByDay: byDayIncome,
      expenseByDay: byDayExpense,
      netByDay: byDayNet,
      weekdayExpenseTotals: weekdayExpenseTotals,
      peakWeekdayIndex: peakWeekdayIndex,
      categories: categoryStats,
      topRecipients: topRecipients,
      netCashFlow: netCashFlow,
      savingsRate: savingsRate,
      largestExpense: largestExpense,
      largestDeposit: largestDeposit,
    );
  }

  _AnalyticsSpendingByDaySnapshot _buildAnalyticsSpendingByDaySnapshot(
    TransactionProvider provider, {
    required List<Transaction> transactions,
    required String periodLabel,
    required String periodKey,
    required bool showIncome,
  }) {
    final weekdayExpenseTotals = List<double>.filled(7, 0.0);

    for (final transaction in transactions) {
      if (showIncome) {
        if (transaction.type != 'CREDIT') continue;
      } else {
        if (transaction.type != 'DEBIT') continue;
      }
      final dt = _parseTransactionTime(transaction.time);
      if (dt == null) continue;

      final isSelfTransfer = provider.isSelfTransfer(transaction);
      final category = transaction.categoryId == null
          ? null
          : provider.getCategoryById(transaction.categoryId!);
      final isMisc = category?.uncategorized == true;
      if (showIncome) {
        if (isSelfTransfer) continue;
      } else {
        if (isSelfTransfer || isMisc) continue;
      }

      final weekdayIndex = dt.weekday % 7; // Sunday = 0 ... Saturday = 6
      weekdayExpenseTotals[weekdayIndex] += transaction.amount;
    }

    var peakWeekdayIndex = 0;
    var peakValue = -1.0;
    for (int i = 0; i < weekdayExpenseTotals.length; i++) {
      if (weekdayExpenseTotals[i] > peakValue) {
        peakValue = weekdayExpenseTotals[i];
        peakWeekdayIndex = i;
      }
    }

    return _AnalyticsSpendingByDaySnapshot(
      periodLabel: periodLabel,
      periodKey: periodKey,
      emptyLabel: showIncome
          ? 'No income activity in $periodLabel.'
          : 'No expenses in $periodLabel.',
      showIncome: showIncome,
      weekdayExpenseTotals: weekdayExpenseTotals,
      peakWeekdayIndex: peakWeekdayIndex,
    );
  }

  _AnalyticsTopRecipientsSnapshot _buildAnalyticsTopRecipientsSnapshot(
    TransactionProvider provider, {
    required List<Transaction> transactions,
    required String periodLabel,
    required String periodKey,
    required bool showIncome,
  }) {
    final recipientTotals = <String, _AnalyticsRecipientAccumulator>{};
    var recipientExpenseCount = 0;

    for (final transaction in transactions) {
      if (showIncome) {
        if (transaction.type != 'CREDIT') continue;
      } else {
        if (transaction.type != 'DEBIT') continue;
      }

      final isSelfTransfer = provider.isSelfTransfer(transaction);
      final category = transaction.categoryId == null
          ? null
          : provider.getCategoryById(transaction.categoryId!);
      final isMisc = category?.uncategorized == true;
      if (showIncome) {
        if (isSelfTransfer) continue;
      } else {
        if (isSelfTransfer || isMisc) continue;
      }

      recipientExpenseCount += 1;
      final recipient = _transactionCounterparty(transaction);
      final existing = recipientTotals.putIfAbsent(
        recipient,
        () => _AnalyticsRecipientAccumulator(),
      );
      existing.amount += transaction.amount;
      existing.count += 1;
    }

    final recipientEntries = recipientTotals.entries.toList()
      ..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    final topRecipients = recipientEntries
        .take(5)
        .map(
          (entry) => _AnalyticsRecipientStat(
            name: entry.key,
            amount: entry.value.amount,
            count: entry.value.count,
          ),
        )
        .toList(growable: false);

    return _AnalyticsTopRecipientsSnapshot(
      periodLabel: periodLabel,
      periodKey: periodKey,
      showIncome: showIncome,
      recipientExpenseCount: recipientExpenseCount,
      topRecipients: topRecipients,
    );
  }

  _AnalyticsMoneyFlowSnapshot _buildAnalyticsMoneyFlowSnapshot({
    required List<Transaction> transactions,
    required String periodLabel,
    required String periodKey,
  }) {
    var totalTransactions = 0;
    var totalIncome = 0.0;
    var totalExpense = 0.0;
    var largestExpense = 0.0;
    var largestDeposit = 0.0;

    for (final transaction in transactions) {
      totalTransactions += 1;
      if (transaction.type == 'CREDIT') {
        totalIncome += transaction.amount;
        largestDeposit = math.max(largestDeposit, transaction.amount);
      } else if (transaction.type == 'DEBIT') {
        totalExpense += transaction.amount;
        largestExpense = math.max(largestExpense, transaction.amount);
      }
    }

    final netCashFlow = totalIncome - totalExpense;
    final savingsRate = totalIncome > 0
        ? ((netCashFlow / totalIncome) * 100).clamp(-999.0, 999.0).toDouble()
        : 0.0;

    return _AnalyticsMoneyFlowSnapshot(
      periodLabel: periodLabel,
      periodKey: periodKey,
      totalTransactions: totalTransactions,
      netCashFlow: netCashFlow,
      savingsRate: savingsRate,
      largestExpense: largestExpense,
      largestDeposit: largestDeposit,
    );
  }

  _LedgerViewSummary _resolveLedgerViewSummary(TransactionProvider provider) {
    final themeProvider = context.watch<ThemeProvider>();
    final sortedLedgerBankIds = _ledgerFilter.bankIds.toList()..sort();
    final cacheKey = _LedgerViewCacheKey(
      dataVersion: provider.dataVersion,
      calendar: themeProvider.appCalendar.storageValue,
      language: themeProvider.appLanguage.storageValue,
      startDateMillis: _ledgerFilter.startDate?.millisecondsSinceEpoch,
      endDateMillis: _ledgerFilter.endDate?.millisecondsSinceEpoch,
      bankIdsKey: sortedLedgerBankIds.join(','),
    );

    final cachedData = _ledgerViewCache;
    if (_ledgerViewCacheKey == cacheKey && cachedData != null) {
      return cachedData;
    }

    // Sort all transactions by time ascending for ledger view
    final allTxns = List<Transaction>.from(provider.allTransactions)
      ..sort((a, b) {
        final aTime = _parseTransactionTime(a.time);
        final bTime = _parseTransactionTime(b.time);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
    final ledgerBankIds = <int>{};
    for (final txn in allTxns) {
      if (txn.bankId != null) ledgerBankIds.add(txn.bankId!);
    }
    final invalidLedgerBankIds = _ledgerFilter.bankIds
        .where((id) => !ledgerBankIds.contains(id))
        .toList(growable: false);
    if (invalidLedgerBankIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _ledgerFilter = _LedgerFilter(
              startDate: _ledgerFilter.startDate,
              endDate: _ledgerFilter.endDate,
              bankIds: _ledgerFilter.bankIds
                  .where((id) => ledgerBankIds.contains(id))
                  .toSet(),
            );
          });
        }
      });
    }

    double? startingBalance;
    DateTime? startingBalanceDate;
    final filtered = <Transaction>[];

    for (int i = 0; i < allTxns.length; i++) {
      final txn = allTxns[i];
      final dt = _parseTransactionTime(txn.time);

      bool inRange = true;
      if (_ledgerFilter.startDate != null && dt != null) {
        final start = DateTime(
          _ledgerFilter.startDate!.year,
          _ledgerFilter.startDate!.month,
          _ledgerFilter.startDate!.day,
        );
        if (dt.isBefore(start)) inRange = false;
      }
      if (_ledgerFilter.endDate != null && dt != null) {
        final endOfDay = DateTime(
          _ledgerFilter.endDate!.year,
          _ledgerFilter.endDate!.month,
          _ledgerFilter.endDate!.day,
          23,
          59,
          59,
        );
        if (dt.isAfter(endOfDay)) inRange = false;
      }
      if (_ledgerFilter.bankIds.isNotEmpty &&
          (txn.bankId == null ||
              !_ledgerFilter.bankIds.contains(txn.bankId!))) {
        inRange = false;
      }

      if (inRange) {
        filtered.add(txn);
      }
    }

    // Compute starting balance from the oldest transaction in the range
    if (filtered.isNotEmpty) {
      final oldest = filtered.last; // descending → last is oldest
      final oldestIdx = allTxns.indexOf(oldest);
      startingBalanceDate = _parseTransactionTime(oldest.time);

      // Find the chronologically previous transaction (next index in desc list)
      for (int j = oldestIdx + 1; j < allTxns.length; j++) {
        final prevBal = _parseRunningBalance(allTxns[j].currentBalance);
        if (prevBal != null) {
          startingBalance = prevBal;
          break;
        }
      }
      // Fallback: derive from oldest transaction
      if (startingBalance == null) {
        final oldestBal = _parseRunningBalance(oldest.currentBalance);
        if (oldestBal != null) {
          if (oldest.type == 'DEBIT') {
            startingBalance = oldestBal + oldest.amount;
          } else {
            startingBalance = oldestBal - oldest.amount;
          }
        }
      }
    }

    final derivedCashBalancesByReference = _deriveCashBalancesByReference(
      allTxns: allTxns,
      accountSummaries: provider.accountSummaries,
    );

    // Build flat list: date headers (String) + transactions interleaved
    final flatItems = <Object>[];
    String? lastDateKey;
    for (final txn in filtered) {
      final dt = _parseTransactionTime(txn.time);
      final key = dt != null
          ? _formatDateHeader(dt, context)
          : context.l10nText('Unknown Date');
      if (key != lastDateKey) {
        flatItems.add(key);
        lastDateKey = key;
      }
      flatItems.add(_LedgerFlatItem(txn));
    }

    final data = _LedgerViewSummary(
      flatItems: flatItems,
      derivedCashBalancesByReference: derivedCashBalancesByReference,
      startingDate: startingBalanceDate,
      startingBalance: startingBalance,
    );
    _ledgerViewCacheKey = cacheKey;
    _ledgerViewCache = data;
    return data;
  }

  List<Widget> _buildLedgerSlivers(
    TransactionProvider provider,
    _LedgerViewSummary ledgerViewSummary,
  ) {
    final flatItems = ledgerViewSummary.flatItems;
    final derivedCashBalancesByReference =
        ledgerViewSummary.derivedCashBalancesByReference;

    return [
      // Timeline content
      // Keep rendering existing ledger rows during provider reloads so
      // category updates do not collapse scroll extent and jump to top.
      if (flatItems.isEmpty && provider.isLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _LoadingTransactions(),
          ),
        )
      else if (flatItems.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _EmptyTransactions(),
          ),
        )
      else
        SliverList.builder(
          itemCount: flatItems.length,
          itemBuilder: (context, index) {
            final item = flatItems[index];
            if (item is String) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      item,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }
            final entry = item as _LedgerFlatItem;
            final lineColor = AppColors.borderColor(context);
            return Padding(
              padding: const EdgeInsets.only(left: 20, right: 20),
              child: Stack(
                children: [
                  Positioned(
                    left: 4.25,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 1.5,
                      color: lineColor,
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 10),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _openTransactionDetailsSheet(
                              provider, entry.transaction),
                          behavior: HitTestBehavior.opaque,
                          child: _LedgerTransactionEntry(
                            transaction: entry.transaction,
                            derivedBalance: derivedCashBalancesByReference[
                                entry.transaction.reference],
                            isSelfTransfer:
                                provider.isSelfTransfer(entry.transaction),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
    ];
  }

  _ActivityTransactionsViewData _resolveActivityTransactionsViewData(
    TransactionProvider provider,
  ) {
    final themeProvider = context.watch<ThemeProvider>();
    final cacheKey = _ActivityTransactionsViewCacheKey(
      dataVersion: provider.dataVersion,
      calendar: themeProvider.appCalendar.storageValue,
      language: themeProvider.appLanguage.storageValue,
      searchQuery: _searchQuery,
      type: _filter.type,
      bankId: _filter.bankId,
      categoryId: _filter.categoryId,
      minAmount: _filter.minAmount,
      maxAmount: _filter.maxAmount,
      startDateMillis: _filter.startDate?.millisecondsSinceEpoch,
      endDateMillis: _filter.endDate?.millisecondsSinceEpoch,
      currentPage: _currentPage,
    );

    final cachedData = _activityTransactionsViewCache;
    if (_activityTransactionsViewCacheKey == cacheKey && cachedData != null) {
      return cachedData;
    }

    final filtered = _filterTransactions(provider.allTransactions);
    final summary = _summarizeActivityTransactions(filtered);
    final sorted = List<Transaction>.from(filtered)
      ..sort((a, b) {
        final aTime = _parseTransactionTime(a.time);
        final bTime = _parseTransactionTime(b.time);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

    final totalPages = (sorted.length / _pageSize).ceil().clamp(1, 999999);
    final safePage = _currentPage.clamp(0, totalPages - 1);
    final startIndex = safePage * _pageSize;
    final endIndex = (startIndex + _pageSize).clamp(0, sorted.length);
    final pageTransactions = sorted.sublist(startIndex, endIndex);

    final flatItems = <Object>[];
    String? lastDateKey;
    for (final transaction in pageTransactions) {
      final dt = _parseTransactionTime(transaction.time);
      final dateKey = dt != null
          ? _formatDateHeader(dt, context)
          : context.l10nText('Unknown Date');
      if (dateKey != lastDateKey) {
        flatItems.add(dateKey);
        lastDateKey = dateKey;
      }
      flatItems.add(transaction);
    }

    final data = _ActivityTransactionsViewData(
      totalPages: totalPages,
      safePage: safePage,
      flatItems: flatItems,
      summary: summary,
    );
    _activityTransactionsViewCacheKey = cacheKey;
    _activityTransactionsViewCache = data;
    return data;
  }

  _ActivityTransactionsSummary _summarizeActivityTransactions(
    List<Transaction> transactions,
  ) {
    var totalIncome = 0.0;
    var totalExpense = 0.0;

    for (final transaction in transactions) {
      if (transaction.type == 'CREDIT') {
        totalIncome += transaction.amount;
      } else if (transaction.type == 'DEBIT') {
        totalExpense += transaction.amount;
      }
    }

    return _ActivityTransactionsSummary(
      totalTransactions: transactions.length,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
    );
  }

  Widget _buildAccountsContent(
    TransactionProvider provider,
    AccountSyncStatusService syncStatusService,
  ) {
    final summary = provider.summary;
    final bankSummaries = provider.bankSummaries;
    final accountSummaries = provider.accountSummaries;
    final isOverview = _selectedBankId == null;

    // Overview data
    final totalBalance = summary?.totalBalance ?? 0.0;
    final bankCount = summary?.banks ?? 0;
    final accountCount = summary?.accounts ?? 0;
    final totalCredit = summary?.totalCredit ?? 0.0;
    final totalDebit = summary?.totalDebit ?? 0.0;
    final totalTxnCount = provider.allTransactions.length;

    // Bank detail data
    BankSummary? bankSummary;
    if (!isOverview) {
      for (final b in bankSummaries) {
        if (b.bankId == _selectedBankId) {
          bankSummary = b;
          break;
        }
      }
      if (bankSummary == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedBankId = null);
        });
        return const SizedBox.shrink();
      }
    }

    final accounts = isOverview
        ? <AccountSummary>[]
        : accountSummaries.where((a) => a.bankId == _selectedBankId).toList();
    final bankTxnCount = isOverview
        ? 0
        : provider.allTransactions
            .where((t) => t.bankId == _selectedBankId)
            .length;
    final selectedBankTotalBalance = bankSummary?.totalBalance ?? 0.0;
    final selectedBankAccountCount = bankSummary?.accountCount ?? 0;
    final selectedBankCredit = bankSummary?.totalCredit ?? 0.0;
    final selectedBankDebit = bankSummary?.totalDebit ?? 0.0;
    final balanceTitle = isOverview
        ? context.l10nText('TOTAL BALANCE')
        : '${_localizedBankLabel(context, _selectedBankId)} ${context.l10nText('Balance')}';
    final balanceSubtitle = isOverview
        ? '${_formatLocalizedCount(context, bankCount, 'Bank', 'Banks')} | ${_formatLocalizedCount(context, accountCount, 'Account', 'Accounts')}'
        : _formatLocalizedCount(
            context,
            selectedBankAccountCount,
            'Account',
            'Accounts',
          );

    return RefreshIndicator(
      color: AppColors.primaryLight,
      onRefresh: provider.loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          children: [
            // Balance card
            _AccountsBalanceCard(
              title: balanceTitle,
              balance: isOverview ? totalBalance : selectedBankTotalBalance,
              subtitle: balanceSubtitle,
              transactionCount: isOverview ? totalTxnCount : bankTxnCount,
              totalCredit: isOverview ? totalCredit : selectedBankCredit,
              totalDebit: isOverview ? totalDebit : selectedBankDebit,
              showBalance: _showAccountBalances,
              onToggleBalance: () =>
                  setState(() => _showAccountBalances = !_showAccountBalances),
            ),
            if (!isOverview) ...[
              const SizedBox(height: 12),
              _BankSelectorStrip(
                bankSummaries: bankSummaries,
                selectedBankId: _selectedBankId,
                onBankSelected: (id) => setState(() {
                  _selectedBankId = id;
                }),
                onTotalsSelected: () => setState(() {
                  _selectedBankId = null;
                }),
              ),
            ],
            const SizedBox(height: 16),

            // Content below balance card
            if (isOverview)
              _BankGrid(
                bankSummaries: bankSummaries,
                showBalance: _showAccountBalances,
                syncStatusService: syncStatusService,
                onBankTap: (bankId) => setState(() => _selectedBankId = bankId),
                onAddAccount: _showAddAccountSheet,
              )
            else
              ...accounts.map((account) {
                final isCash = account.bankId == CashConstants.bankId;
                final acctTxnCount = account.totalTransactions.toInt();
                final syncStatus = isCash
                    ? null
                    : syncStatusService.getSyncStatus(
                        account.accountNumber,
                        account.bankId,
                      );
                final syncProgress = isCash
                    ? null
                    : syncStatusService.getSyncProgress(
                        account.accountNumber,
                        account.bankId,
                      );
                final isReparsing = _reparsingAccountKeys
                        .contains(_accountActionKey(account)) ||
                    syncStatus != null;
                return _AccountCard(
                  account: account,
                  bankId: _selectedBankId!,
                  isCash: isCash,
                  showBalance: _showAccountBalances,
                  transactionCount: acctTxnCount,
                  syncStatus: syncStatus,
                  syncProgress: syncProgress,
                  onOpenTransactions: () =>
                      _openBankTransactionsPage(account.bankId),
                  isReparsing: isReparsing,
                  onReparse: isCash
                      ? null
                      : () => _openAccountReparseSheet(provider, account),
                  onDelete:
                      isCash ? null : () => _showDeleteConfirmation(account),
                  onCashExpense: isCash ? _showCashExpenseSheet : null,
                  onCashIncome: isCash ? _showCashIncomeSheet : null,
                  onSetCashAmount: isCash ? _showSetCashAmountSheet : null,
                  onClearCash: isCash ? _confirmClearCashWallet : null,
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilterSheet(TransactionProvider provider) async {
    // Derive unique bank IDs and account numbers from ALL transactions.
    final allTxns = provider.allTransactions;
    final bankIds = <int>{};
    final categoryIds = <int>{};
    for (final t in allTxns) {
      if (t.bankId != null) bankIds.add(t.bankId!);
      if (t.categoryId != null) categoryIds.add(t.categoryId!);
    }

    // Build category list from IDs found in transactions.
    final categories = categoryIds
        .map((id) => provider.getCategoryById(id))
        .whereType<Category>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final result = await showModalBottomSheet<_TransactionFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterTransactionsSheet(
        currentFilter: _filter,
        bankIds: bankIds.toList()..sort(),
        categories: categories,
      ),
    );
    if (result != null) {
      setState(() {
        _filter = result;
        _currentPage = 0;
      });
    }
  }

  Future<void> _openLedgerFilterSheet(TransactionProvider provider) async {
    final bankIds = <int>{};
    for (final transaction in provider.allTransactions) {
      if (transaction.bankId != null) bankIds.add(transaction.bankId!);
    }

    final result = await showModalBottomSheet<_LedgerFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LedgerFilterSheet(
        currentFilter: _ledgerFilter,
        bankIds: bankIds.toList()
          ..sort((a, b) => _bankLabel(a).compareTo(_bankLabel(b))),
      ),
    );
    if (result != null) {
      setState(() => _ledgerFilter = result);
    }
  }

  void _showFinancialHealthSheet(FinancialHealthSnapshot financialHealth) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FinancialHealthSheet(
        financialHealth: financialHealth,
      ),
    );
  }

  List<Transaction> _filterTransactions(List<Transaction> transactions) {
    var result = transactions;

    // Type filter
    if (_filter.type != null) {
      result = result.where((t) => t.type == _filter.type).toList();
    }

    // Bank filter
    if (_filter.bankId != null) {
      result = result.where((t) => t.bankId == _filter.bankId).toList();
    }

    // Category filter
    if (_filter.categoryId != null) {
      result =
          result.where((t) => t.includesCategory(_filter.categoryId)).toList();
    }

    // Amount range filter
    if (_filter.minAmount != null) {
      result = result.where((t) => t.amount >= _filter.minAmount!).toList();
    }
    if (_filter.maxAmount != null) {
      result = result.where((t) => t.amount <= _filter.maxAmount!).toList();
    }

    // Date range filter
    if (_filter.startDate != null || _filter.endDate != null) {
      result = result.where((t) {
        final dt = _parseTransactionTime(t.time);
        if (dt == null) return false;
        if (_filter.startDate != null && dt.isBefore(_filter.startDate!)) {
          return false;
        }
        if (_filter.endDate != null) {
          final endOfDay = _filter.endDate!
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1));
          if (dt.isAfter(endOfDay)) return false;
        }
        return true;
      }).toList();
    }

    // Search query filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((t) {
        final receiver = t.receiver?.toLowerCase() ?? '';
        final creditor = t.creditor?.toLowerCase() ?? '';
        final note = t.note?.toLowerCase() ?? '';
        final reference = t.reference.toLowerCase();
        final bank = _bankLabel(t.bankId).toLowerCase();
        final localizedBank =
            _localizedBankLabel(context, t.bankId).toLowerCase();
        return receiver.contains(query) ||
            creditor.contains(query) ||
            note.contains(query) ||
            reference.contains(query) ||
            bank.contains(query) ||
            localizedBank.contains(query);
      }).toList();
    }

    return result;
  }

  bool _isAdjustingCash = false;

  String _cashAccountNumber() {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final cashAccounts = provider.accountSummaries
        .where((a) => a.bankId == CashConstants.bankId)
        .toList();
    return cashAccounts.isNotEmpty
        ? cashAccounts.first.accountNumber
        : CashConstants.defaultAccountNumber;
  }

  void _showCashExpenseSheet() {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    showAddCashTransactionSheet(
      context: context,
      provider: provider,
      accountNumber: _cashAccountNumber(),
      initialIsDebit: true,
    );
  }

  void _showCashIncomeSheet() {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    showAddCashTransactionSheet(
      context: context,
      provider: provider,
      accountNumber: _cashAccountNumber(),
      initialIsDebit: false,
    );
  }

  void _showSetCashAmountSheet() async {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final cashSummaries = provider.accountSummaries
        .where((a) => a.bankId == CashConstants.bankId)
        .toList();
    final currentBalance = cashSummaries.isNotEmpty
        ? cashSummaries.fold<double>(0.0, (sum, a) => sum + a.balance)
        : 0.0;

    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SetCashAmountSheet(currentBalance: currentBalance),
    );
    if (result != null) {
      _applyCashTarget(result);
    }
  }

  void _confirmClearCashWallet() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          dialogContext.l10nText('Clear Cash Wallet'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(dialogContext),
          ),
        ),
        content: Text(
          dialogContext.l10nText(
            'This will set your cash wallet balance to zero.',
          ),
          style: TextStyle(
              fontSize: 14, color: AppColors.textSecondary(dialogContext)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              dialogContext.l10nText('Cancel'),
              style: TextStyle(color: AppColors.textSecondary(dialogContext)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _applyCashTarget(0);
            },
            child: Text(
              dialogContext.l10nText('Clear'),
              style: const TextStyle(
                color: AppColors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyCashTarget(double targetBalance) async {
    if (_isAdjustingCash) return;
    setState(() => _isAdjustingCash = true);

    try {
      final provider = Provider.of<TransactionProvider>(context, listen: false);
      final delta = await provider.setCashWalletBalance(
        targetBalance: targetBalance,
        accountNumber: _cashAccountNumber(),
      );

      if (!mounted) return;

      if (delta.abs() < 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10nTextRead('Cash wallet is already at that amount'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final direction = delta > 0
            ? context.l10nTextRead('increased')
            : context.l10nTextRead('decreased');
        final amount = formatNumberWithComma(delta.abs());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10nTextRead('Cash wallet')} $direction ${context.l10nTextRead('by')} ${context.l10nTextRead('ETB')} $amount',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10nTextRead('Failed to update cash wallet')}: $e',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdjustingCash = false);
    }
  }

  void _showAddAccountSheet({int? bankId, bank_model.Bank? initialBank}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddAccountSheet(
        initialBankId: bankId ?? _selectedBankId,
        initialBank: initialBank,
        onAccountAdded: () {
          Provider.of<TransactionProvider>(context, listen: false).loadData();
        },
      ),
    );
  }

  void _openBankTransactionsPage(int bankId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _BankTransactionsPage(bankId: bankId),
      ),
    );
  }

  String _accountActionKey(AccountSummary account) {
    return '${account.bankId}:${account.accountNumber}';
  }

  bank_model.Bank? _resolveBankInfo(int bankId) {
    for (final bank in _assetBanks) {
      if (bank.id == bankId) return bank;
    }
    return null;
  }

  List<Transaction> _transactionsForAccount(
    TransactionProvider provider,
    AccountSummary account,
  ) {
    final bank = _resolveBankInfo(account.bankId);
    return provider.allTransactions.where((transaction) {
      if (transaction.bankId != account.bankId) return false;

      if (account.bankId == CashConstants.bankId) {
        return transaction.accountNumber == account.accountNumber;
      }

      if (bank?.uniformMasking == true && bank?.maskPattern != null) {
        final maskPattern = bank!.maskPattern!;
        final transactionAccount = transaction.accountNumber?.trim();
        if (transactionAccount == null || transactionAccount.isEmpty) {
          return false;
        }
        if (account.accountNumber.length < maskPattern ||
            transactionAccount.length < maskPattern) {
          return false;
        }
        return account.accountNumber.substring(
              account.accountNumber.length - maskPattern,
            ) ==
            transactionAccount.substring(
              transactionAccount.length - maskPattern,
            );
      }

      if (bank?.uniformMasking == false) {
        return true;
      }

      return transaction.accountNumber == account.accountNumber;
    }).toList(growable: false);
  }

  Future<void> _openAccountReparseSheet(
    TransactionProvider provider,
    AccountSummary account,
  ) async {
    final selection = await showModalBottomSheet<_AccountReparseSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReparseAccountSheet(
        accountNumber: account.accountNumber,
        bankName: _localizedBankName(context, account.bankId),
      ),
    );
    if (selection == null) return;

    await _reparseTransactionsForAccount(
      provider,
      account,
      startDate: selection.startDate,
      refreshExistingTransactions: selection.refreshExistingTransactions,
      importMissedTransactions: selection.importMissedTransactions,
      applyAutoCategorization: selection.applyAutoCategorization,
    );
  }

  Future<void> _reparseTransactionsForAccount(
    TransactionProvider provider,
    AccountSummary account, {
    DateTime? startDate,
    bool refreshExistingTransactions = true,
    bool importMissedTransactions = true,
    bool applyAutoCategorization = true,
  }) async {
    final accountKey = _accountActionKey(account);
    if (_reparsingAccountKeys.contains(accountKey)) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final accountTransactions = _transactionsForAccount(provider, account);

    setState(() => _reparsingAccountKeys.add(accountKey));

    try {
      final result = await _accountTransactionReparseService
          .startReparseAccountTransactionsInBackground(
        bankId: account.bankId,
        accountNumber: account.accountNumber,
        transactions: accountTransactions,
        startDate: startDate,
        refreshExistingTransactions: refreshExistingTransactions,
        importMissedTransactions: importMissedTransactions,
        applyAutoCategorization: applyAutoCategorization,
      );

      if (!mounted) return;
      final message = result.started
          ? 'Reparse started in the background. Progress will appear on the account card.'
          : (result.errorMessage ?? 'Could not start reparse.');
      messenger?.showSnackBar(
        SnackBar(content: Text(context.l10nTextRead(message))),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10nTextRead('Could not reparse transactions')}: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _reparsingAccountKeys.remove(accountKey));
      }
    }
  }

  void _showDeleteConfirmation(AccountSummary account) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.cardColor(dialogContext),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            dialogContext.l10nText('Delete Account'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(dialogContext),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dialogContext.l10nText(
                  'Are you sure you want to delete this account?',
                ),
                style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary(dialogContext)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background(dialogContext),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${dialogContext.l10nText('Account')}: ${account.accountNumber}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary(dialogContext)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dialogContext.l10nText('Holder')}: ${account.accountHolderName}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary(dialogContext)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dialogContext.l10nText('Bank')}: ${_localizedBankName(dialogContext, account.bankId)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary(dialogContext)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                dialogContext.l10nText('This action cannot be undone.'),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.red,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                dialogContext.l10nText('Cancel'),
                style: TextStyle(color: AppColors.textSecondary(dialogContext)),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _deleteAccount(account);
              },
              child: Text(
                dialogContext.l10nText('Delete'),
                style: TextStyle(
                  color: AppColors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAccount(AccountSummary account) async {
    try {
      final accountRepo = AccountRepository();
      await accountRepo.deleteAccount(account.accountNumber, account.bankId);

      if (mounted) {
        Provider.of<TransactionProvider>(context, listen: false).loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10nTextRead('Account deleted successfully')),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10nTextRead('Error deleting account')}: $e',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

// ─── Helper functions ─────────────────────────────────────────────

String _formatDateHeader(DateTime date, [BuildContext? context]) {
  if (context != null) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        return AppDateFormat.monthDayYear(date, context: context);
      }
    } catch (_) {}
  }
  return AppDateFormat.monthDayYear(date, context: context);
}

final List<DateFormat> _fallbackTransactionTimeParsers = <DateFormat>[
  DateFormat('yyyy-MM-dd HH:mm:ss'),
  DateFormat('yyyy-MM-dd HH:mm'),
  DateFormat('yyyy/MM/dd HH:mm:ss'),
  DateFormat('yyyy/MM/dd HH:mm'),
  DateFormat('dd-MM-yyyy HH:mm:ss'),
  DateFormat('dd-MM-yyyy HH:mm'),
  DateFormat('dd/MM/yyyy HH:mm:ss'),
  DateFormat('dd/MM/yyyy HH:mm'),
  DateFormat('MM-dd-yyyy HH:mm:ss'),
  DateFormat('MM-dd-yyyy HH:mm'),
  DateFormat('MM/dd/yyyy HH:mm:ss'),
  DateFormat('MM/dd/yyyy HH:mm'),
  DateFormat('yyyy-MM-dd'),
  DateFormat('yyyy/MM/dd'),
  DateFormat('dd-MM-yyyy'),
  DateFormat('dd/MM/yyyy'),
  DateFormat('MM-dd-yyyy'),
  DateFormat('MM/dd/yyyy'),
  DateFormat('dd MMM yyyy HH:mm:ss'),
  DateFormat('dd MMM yyyy HH:mm'),
  DateFormat('dd MMM yyyy hh:mm a'),
  DateFormat('MMM dd yyyy HH:mm:ss'),
  DateFormat('MMM dd yyyy HH:mm'),
  DateFormat('MMM dd yyyy hh:mm a'),
  DateFormat('MMM dd, yyyy HH:mm:ss'),
  DateFormat('MMM dd, yyyy HH:mm'),
  DateFormat('MMM dd, yyyy hh:mm a'),
  DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
  DateFormat("yyyy-MM-dd'T'HH:mm:ssZ"),
  DateFormat('yyyy-MM-dd HH:mm:ssZ'),
];

DateTime? _parseTransactionTime(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;

  final unix = int.tryParse(value);
  if (unix != null) {
    try {
      final millis = value.length <= 10 ? unix * 1000 : unix;
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
    } catch (_) {}
  }

  try {
    return DateTime.parse(value).toLocal();
  } catch (_) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ');
    for (final parser in _fallbackTransactionTimeParsers) {
      try {
        return parser.parseLoose(normalized).toLocal();
      } catch (_) {}
    }
    return null;
  }
}

double? _parseRunningBalance(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.trim().replaceAll(',', '');
  if (cleaned.isEmpty) return null;
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(cleaned);
  if (match == null) return null;
  return double.tryParse(match.group(0)!);
}

bool _matchesAnalyticsHeatmapFilterValue(
  Transaction transaction,
  _AnalyticsHeatmapFilter filter,
) {
  final dt = _parseTransactionTime(transaction.time);

  switch (filter.mode) {
    case _AnalyticsHeatmapMode.all:
      break;
    case _AnalyticsHeatmapMode.expense:
      if (transaction.type != 'DEBIT') return false;
      break;
    case _AnalyticsHeatmapMode.income:
      if (transaction.type != 'CREDIT') return false;
      break;
  }

  if (filter.bankId != null && transaction.bankId != filter.bankId) {
    return false;
  }
  if (filter.categoryId != null &&
      !transaction.includesCategory(filter.categoryId)) {
    return false;
  }
  if (filter.startDate != null) {
    if (dt == null) return false;
    final startOfDay = DateTime(
      filter.startDate!.year,
      filter.startDate!.month,
      filter.startDate!.day,
    );
    if (dt.isBefore(startOfDay)) return false;
  }
  if (filter.endDate != null) {
    if (dt == null) return false;
    final endOfDay = filter.endDate!
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    if (dt.isAfter(endOfDay)) return false;
  }
  return true;
}

List<Transaction> _transactionsForHeatmapDayWithFilter({
  required DateTime day,
  required List<Transaction> allTransactions,
  required _AnalyticsHeatmapFilter filter,
}) {
  final start = DateTime(day.year, day.month, day.day);
  final end = start.add(const Duration(days: 1));
  final transactions = allTransactions.where((transaction) {
    final dt = _parseTransactionTime(transaction.time);
    if (dt == null) return false;
    if (dt.isBefore(start) || !dt.isBefore(end)) return false;
    return _matchesAnalyticsHeatmapFilterValue(transaction, filter);
  }).toList()
    ..sort((a, b) {
      final aTime = _parseTransactionTime(a.time);
      final bTime = _parseTransactionTime(b.time);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
  return transactions;
}

Map<String, double> _deriveCashBalancesByReference({
  required List<Transaction> allTxns,
  required List<AccountSummary> accountSummaries,
}) {
  final currentCashTotal = accountSummaries
      .where((summary) => summary.bankId == CashConstants.bankId)
      .fold<double>(0.0, (sum, summary) => sum + summary.balance);

  final cashTransactions = allTxns
      .where((transaction) => transaction.bankId == CashConstants.bankId)
      .toList(growable: false);

  if (cashTransactions.isEmpty) return const <String, double>{};

  final netCashDelta = cashTransactions.fold<double>(0.0, (sum, transaction) {
    if (transaction.type == 'DEBIT') return sum - transaction.amount;
    if (transaction.type == 'CREDIT') return sum + transaction.amount;
    return sum;
  });

  // In this codebase, account.balance acts like a base value and transactions
  // apply deltas on top. Reverse that to get the balance before ledger entries.
  final baseCashBalance = currentCashTotal - netCashDelta;
  var rollingBalance = baseCashBalance;

  final byTimeAsc = List<Transaction>.from(cashTransactions)
    ..sort((a, b) {
      final aTime = _parseTransactionTime(a.time);
      final bTime = _parseTransactionTime(b.time);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return aTime.compareTo(bTime);
    });

  final derived = <String, double>{};
  for (final transaction in byTimeAsc) {
    if (transaction.type == 'DEBIT') {
      rollingBalance -= transaction.amount;
    } else if (transaction.type == 'CREDIT') {
      rollingBalance += transaction.amount;
    }

    final parsed = _parseRunningBalance(transaction.currentBalance);
    if (parsed != null) {
      rollingBalance = parsed;
      derived[transaction.reference] = parsed;
    } else {
      derived[transaction.reference] = rollingBalance;
    }
  }
  return derived;
}

Color _healthColor(int score) {
  if (score < 30) return AppColors.red;
  if (score < 60) return AppColors.amber;
  if (score < 80) return AppColors.blue;
  return AppColors.incomeSuccess;
}

String _bankLabel(int? bankId) {
  if (bankId == null) return 'Bank';
  if (bankId == CashConstants.bankId) return CashConstants.bankShortName;
  try {
    final bank = _assetBanks.firstWhere((b) => b.id == bankId);
    return bank.shortName;
  } catch (_) {
    try {
      final bank = AppConstants.banks.firstWhere((b) => b.id == bankId);
      return bank.shortName;
    } catch (_) {
      return 'Bank $bankId';
    }
  }
}

String _localizedBankLabel(BuildContext context, int? bankId) {
  final label = _bankLabel(bankId);
  if (bankId != null && label == 'Bank $bankId') {
    return '${context.l10nText('Bank')} $bankId';
  }
  return context.l10nText(label);
}

String _localizedBankName(BuildContext context, int bankId) {
  if (bankId == CashConstants.bankId) return context.l10nText('Cash Wallet');
  try {
    final bank = _assetBanks.firstWhere((b) => b.id == bankId);
    return context.l10nText(bank.name);
  } catch (_) {
    try {
      final bank = AppConstants.banks.firstWhere((b) => b.id == bankId);
      return context.l10nText(bank.name);
    } catch (_) {
      return '${context.l10nText('Bank')} $bankId';
    }
  }
}

String _amountLabel(
  BuildContext context,
  double amount, {
  required bool isCredit,
}) {
  final formatted = formatNumberWithComma(amount);
  return '${isCredit ? '+' : '-'} ${context.l10nText('ETB')} $formatted';
}

String _transactionCounterparty(Transaction transaction,
    {bool isSelfTransfer = false}) {
  final receiver = transaction.receiver?.trim();
  final creditor = transaction.creditor?.trim();
  if (receiver != null && receiver.isNotEmpty) return receiver.toUpperCase();
  if (creditor != null && creditor.isNotEmpty) return creditor.toUpperCase();
  return isSelfTransfer ? 'YOU' : 'UNKNOWN';
}

String _localizedTransactionCounterparty(
  BuildContext context,
  Transaction transaction, {
  bool isSelfTransfer = false,
}) {
  final label =
      _transactionCounterparty(transaction, isSelfTransfer: isSelfTransfer);
  if (label == 'YOU' || label == 'UNKNOWN') return context.l10nText(label);
  return label;
}

String _localizedSyncStatus(BuildContext context, String status) {
  final progressMatch = RegExp(
    r'^(Parsing|Reparsing)\s+(\d+)\s*/\s*(\d+)\s+messages\.\.\.$',
  ).firstMatch(status);
  if (progressMatch != null) {
    final verb = context.l10nText(progressMatch.group(1)!);
    final current = progressMatch.group(2)!;
    final total = progressMatch.group(3)!;
    final messages = context.l10nText('messages');
    return '$verb $current/$total $messages...';
  }
  return context.l10nText(status);
}

String _transactionTimeLabel(Transaction transaction, [BuildContext? context]) {
  final dt = _parseTransactionTime(transaction.time);
  if (dt == null) return context?.l10nText('Unknown time') ?? 'Unknown time';

  if (context != null) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        return AppDateFormat.ethiopianTime(dt, context: context);
      }
    } catch (_) {}
  }
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _formatCount(int count) {
  final formatted = formatNumberWithComma(count.toDouble());
  return formatted.replaceFirst(RegExp(r'\.00$'), '');
}

String _formatEtbAbbrev(double value) {
  return formatNumberAbbreviated(value).replaceAll(' ', '');
}

String _formatEtbFull(double value) {
  return formatNumberWithComma(value);
}

String _formatLocalizedEtb(BuildContext context, double value) {
  return '${context.l10nText('ETB')} ${_formatEtbAbbrev(value)}';
}

String _formatLocalizedCount(
  BuildContext context,
  int count,
  String singular,
  String plural,
) {
  final label = context.l10nText(count == 1 ? singular : plural);
  return '${_formatCount(count)} $label';
}

String _formatRatioPercent(double ratio) {
  if (!ratio.isFinite) return '0%';
  return '${(ratio * 100).round()}%';
}

String _formatRunwayMonths(double value, [BuildContext? context]) {
  if (!value.isFinite) {
    return context?.l10nText('No recent spend') ?? 'No recent spend';
  }
  final monthLabel = context?.l10nText('mo') ?? 'mo';
  if (value >= 10) return '${value.round()} $monthLabel';
  return '${value.toStringAsFixed(1)} $monthLabel';
}

String _formatCompactSignedEtb(double value) {
  if (value.abs() < 0.001) return '';
  final sign = value >= 0 ? '+' : '-';
  return '$sign${_formatEtbAbbrev(value.abs())}';
}

String _safePrefix(String value, int length) {
  if (value.isEmpty || length <= 0) return '';
  final safeLength = value.length < length ? value.length : length;
  return value.substring(0, safeLength);
}

String _formatEthiopianMonthNameForContext(
  int month,
  BuildContext? context, {
  bool abbreviated = true,
}) {
  return AppDateFormat.ethiopianMonthName(
    month,
    language: AppDateFormat.languageOf(context),
    abbreviated: abbreviated,
  );
}

String _formatEthiopianMonthRangeForContext(BuildContext? context) {
  final months = AppDateFormat.ethiopianMonthNames(
    language: AppDateFormat.languageOf(context),
  );
  return '${months.first} - ${months.last}';
}

String _formatMonthYear(DateTime date, [BuildContext? context]) {
  if (context != null) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        return AppDateFormat.monthYear(date, context: context);
      }
    } catch (_) {}
  }
  return AppDateFormat.shortMonthYear(date, context: context);
}

String _formatAnalyticsChartPeriodLabel({
  BuildContext? context,
  required _AnalyticsHeatmapFilter filter,
  required DateTime fallbackMonthDate,
  bool expandedForDateRange = false,
}) {
  final startDate = filter.startDate;
  final endDate = filter.endDate;
  if (startDate != null && endDate != null) {
    return '${_formatDateHeader(startDate, context)} - ${_formatDateHeader(endDate, context)}';
  }
  if (startDate != null) {
    return expandedForDateRange
        ? 'Since ${_formatDateHeader(startDate, context)}'
        : _formatDateHeader(startDate, context);
  }
  if (endDate != null) {
    return expandedForDateRange
        ? 'Until ${_formatDateHeader(endDate, context)}'
        : _formatDateHeader(endDate, context);
  }

  if (!expandedForDateRange) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context!, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        return AppDateFormat.monthYear(fallbackMonthDate, context: context);
      }
    } catch (_) {}
    return AppDateFormat.monthYear(fallbackMonthDate, context: context);
  }

  DateTime monthEnd;
  try {
    final isEC =
        Provider.of<ThemeProvider>(context!, listen: false).appCalendar ==
            AppCalendarOption.ethiopian;
    if (isEC) {
      final ec = Kenat.fromGregorian(fallbackMonthDate.year,
              fallbackMonthDate.month, fallbackMonthDate.day)
          .getEthiopian();
      final dayCount = EthiopianCalendarUtils.getEthiopianDaysInMonth(
          ec['year']!, ec['month']!);
      final gc = Kenat.fromEthiopian(ec['year']!, ec['month']!, dayCount)
          .getGregorian();
      monthEnd = DateTime(gc['year']!, gc['month']!, gc['day']!);
    } else {
      monthEnd =
          DateTime(fallbackMonthDate.year, fallbackMonthDate.month + 1, 0);
    }
  } catch (_) {
    monthEnd = DateTime(fallbackMonthDate.year, fallbackMonthDate.month + 1, 0);
  }

  return '${_formatDateHeader(fallbackMonthDate, context)} - ${_formatDateHeader(monthEnd, context)}';
}

String _formatAnalyticsSpendingPeriodLabel(
  _AnalyticsHeatmapView view,
  DateTime periodDate, {
  BuildContext? context,
}) {
  return view == _AnalyticsHeatmapView.daily
      ? _formatMonthYear(periodDate, context)
      : () {
          if (context != null) {
            try {
              final isEC = Provider.of<ThemeProvider>(context, listen: false)
                      .appCalendar ==
                  AppCalendarOption.ethiopian;
              if (isEC) {
                final ec = Kenat.fromGregorian(
                  periodDate.year,
                  periodDate.month,
                  periodDate.day,
                ).getEthiopian();
                return '${_formatEthiopianMonthRangeForContext(context)} ${ec['year']}';
              }
            } catch (_) {}
          }
          return '${periodDate.year}';
        }();
}

String _formatFullMonthName(DateTime date, [BuildContext? context]) {
  if (context != null) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        return AppDateFormat.monthFull(date, context: context);
      }
    } catch (_) {}
  }
  return AppDateFormat.monthFull(date, context: context);
}

List<String> _analyticsWeekdayLabels(BuildContext context,
    {bool short = false}) {
  final isEC = Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
      AppCalendarOption.ethiopian;
  final isAmharic = AppDateFormat.languageOf(context).storageValue == 'am';
  if (!isEC || !isAmharic) {
    return short
        ? AppDateFormat.weekdayShortEnglishMondayFirst
        : AppDateFormat.weekdayFullEnglishMondayFirst;
  }

  // Build Amharic labels from Kenat directly, Monday-first to match chart layout.
  final mondayAnchor = DateTime(2024, 1, 1); // Monday
  final names = List<String>.generate(7, (index) {
    final dt = mondayAnchor.add(Duration(days: index));
    return Kenat.fromGregorian(dt.year, dt.month, dt.day).getWeekdayName();
  });
  if (!short) return names;
  return names
      .map((name) => name.substring(0, name.length >= 3 ? 3 : name.length))
      .toList(growable: false);
}

String _analyticsWeekdayLabel(
  BuildContext context,
  int index, {
  bool short = false,
}) {
  final labels = _analyticsWeekdayLabels(context, short: short);
  return labels[index.clamp(0, labels.length - 1)];
}

Color _analyticsPaletteColor(int index) {
  const palette = <Color>[
    Color(0xFF7C83EA),
    Color(0xFF22C55E),
    Color(0xFFFB7185),
    Color(0xFFF59E0B),
    Color(0xFFA855F7),
    Color(0xFF06B6D4),
    Color(0xFF6366F1),
    Color(0xFF6B7280),
  ];
  return palette[index % palette.length];
}

String _formatLedgerTime(DateTime dt, [BuildContext? context]) {
  if (context != null) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        return AppDateFormat.ethiopianTime(dt, context: context);
      }
    } catch (_) {}
  }
  final hour = dt.hour;
  final minute = dt.minute;
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
}

Map<String, String?> _formatLedgerTimeParts(DateTime dt,
    [BuildContext? context]) {
  if (context != null) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        final timeText = AppDateFormat.ethiopianTime(
          dt,
          context: context,
          showPeriodLabel: false,
        );
        final periodText = AppDateFormat.ethiopianPeriodLabel(
          dt,
          context: context,
        );
        return {'time': timeText, 'period': periodText};
      }
    } catch (_) {}
  }
  return {'time': _formatLedgerTime(dt, context), 'period': null};
}

String _getBankImage(int bankId) {
  if (bankId == CashConstants.bankId) return 'assets/images/eth_birr.png';
  try {
    return _assetBanks.firstWhere((b) => b.id == bankId).image;
  } catch (_) {
    try {
      return AppConstants.banks.firstWhere((b) => b.id == bankId).image;
    } catch (_) {
      return '';
    }
  }
}

// ─── Widgets ──────────────────────────────────────────────────────

class _TopTabBar extends StatelessWidget {
  final _TopTab selectedTab;
  final ValueChanged<_TopTab> onTabChanged;

  const _TopTabBar({
    required this.selectedTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TopTabItem(
          label: 'Activity',
          selected: selectedTab == _TopTab.activity,
          onTap: () => onTabChanged(_TopTab.activity),
        ),
        const SizedBox(width: 20),
        _TopTabItem(
          label: 'Accounts',
          selected: selectedTab == _TopTab.accounts,
          onTap: () => onTabChanged(_TopTab.accounts),
        ),
      ],
    );
  }
}

class _TopTabItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TopTabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(bottom: 10),
        decoration: selected
            ? const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.primaryLight,
                    width: 2.5,
                  ),
                ),
              )
            : null,
        child: Text(
          context.l10nText(label),
          style: TextStyle(
            color: selected
                ? AppColors.primaryLight
                : AppColors.textSecondary(context),
            fontSize: 20,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _FinancialHealthCard extends StatelessWidget {
  final FinancialHealthSnapshot financialHealth;
  final VoidCallback onTap;

  const _FinancialHealthCard({
    required this.financialHealth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final healthScore = financialHealth.score;
    final theme = Theme.of(context);
    final scoreColor = _healthColor(healthScore);
    final incomeFormatted = _formatEtbAbbrev(financialHealth.trailingIncome);
    final expenseFormatted = _formatEtbAbbrev(financialHealth.trailingExpense);
    final currencyLabel = context.l10nText('ETB');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10nText('Financial Health').toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$healthScore',
                          style: TextStyle(
                            color: scoreColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          ' / 100',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.l10nText('Cash Flow (90 Days)').toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+$currencyLabel $incomeFormatted',
                          style: const TextStyle(
                            color: AppColors.incomeSuccess,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          ' | ',
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '-$currencyLabel $expenseFormatted',
                          style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: AppColors.textTertiary(context),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.l10nText(
                              'Tap to see how this score works',
                            ),
                            style: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 56,
                height: 56,
                child: CustomPaint(
                  painter: _HealthGaugePainter(
                    score: healthScore,
                    color: scoreColor,
                  ),
                  child: Center(
                    child: Text(
                      '$healthScore',
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
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
}

class _FinancialHealthSheet extends StatelessWidget {
  final FinancialHealthSnapshot financialHealth;

  const _FinancialHealthSheet({
    required this.financialHealth,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final scoreColor = _healthColor(financialHealth.score);
    final netFlow = financialHealth.trailingNet;
    final currencyLabel = context.l10nText('ETB');
    final netFlowLabel =
        '${netFlow >= 0 ? '+' : '-'}$currencyLabel ${_formatEtbAbbrev(netFlow.abs())}';
    final netFlowColor = netFlow >= 0 ? AppColors.incomeSuccess : AppColors.red;
    final runwaySummary = financialHealth.averageMonthlyExpense <= 0
        ? (financialHealth.totalBalance > 0
            ? context.l10nText(
                'No recent expense history, so runway stays favorable.',
              )
            : context.l10nText(
                'No recent expense history yet, so runway stays neutral.',
              ))
        : '$currencyLabel ${_formatEtbAbbrev(financialHealth.totalBalance)} ${context.l10nText('balance')}'
            ' / $currencyLabel ${_formatEtbAbbrev(financialHealth.averageMonthlyExpense)} ${context.l10nText('avg monthly expense')}'
            ' = ${_formatRunwayMonths(financialHealth.runwayMonths, context)}';
    final stabilitySummary = financialHealth.hasStabilityHistory
        ? '${context.l10nText('Based on')} ${financialHealth.stabilitySampleCount} ${context.l10nText('prior full months.')}'
            ' ${context.l10nText('Average savings-rate swing:')}'
            ' ${_formatRatioPercent(financialHealth.stabilityAverageDeviation)}'
        : context.l10nText(
            'Not enough full-month history yet, so stability stays neutral.',
          );
    final fixedCostSummary = financialHealth.usesCategoryData
        ? '${context.l10nText('Essentials are')} ${_formatRatioPercent(financialHealth.essentialBurden)}'
            ' ${context.l10nText('of trailing income with')}'
            ' ${_formatRatioPercent(financialHealth.categorizedCoverage)}'
            ' ${context.l10nText('categorized expense coverage.')}'
        : '${_formatRatioPercent(financialHealth.categorizedCoverage)}'
            ' ${context.l10nText('of trailing expense is categorized, so fixed costs stay neutral until coverage reaches 40%.')}';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color:
                        AppColors.textTertiary(context).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10nText('Financial Health'),
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      AppIcons.close,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
              Text(
                context.l10nText(
                  'This score blends your last 90 days of cash flow with balance runway, recent consistency, and essential-cost pressure.',
                ),
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardColor(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.borderColor(context),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scoreColor.withValues(alpha: 0.25),
                          width: 4,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${financialHealth.score}',
                          style: TextStyle(
                            color: scoreColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10nText(
                              'Last 90 days cash flow used in this score',
                            ),
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.7,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '+$currencyLabel ${_formatEtbAbbrev(financialHealth.trailingIncome)}'
                            ' | -$currencyLabel ${_formatEtbAbbrev(financialHealth.trailingExpense)}',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${context.l10nText('Net')} $netFlowLabel'
                            '  •  ${context.l10nText('Savings Rate')} ${_formatRatioPercent(financialHealth.savingsRate)}',
                            style: TextStyle(
                              color: netFlowColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _FinancialHealthMetricTile(
                title: 'Cash Flow',
                weight: '40%',
                score: financialHealth.cashFlowScore,
                detail:
                    'Uses the last 90 days of income vs expense. Higher savings rate means a higher score.',
                summary:
                    '+$currencyLabel ${_formatEtbAbbrev(financialHealth.trailingIncome)}'
                    ' | -$currencyLabel ${_formatEtbAbbrev(financialHealth.trailingExpense)}'
                    ' | ${context.l10nText('Net')} $netFlowLabel',
              ),
              const SizedBox(height: 12),
              _FinancialHealthMetricTile(
                title: 'Runway',
                weight: '30%',
                score: financialHealth.runwayScore,
                detail:
                    'Compares your current total balance to your average monthly expense from the same 90-day window.',
                summary: runwaySummary,
              ),
              const SizedBox(height: 12),
              _FinancialHealthMetricTile(
                title: 'Stability',
                weight: '20%',
                score: financialHealth.stabilityScore,
                detail:
                    'Measures how much your savings rate changes across prior full months. Lower swing means higher stability.',
                summary: stabilitySummary,
              ),
              const SizedBox(height: 12),
              _FinancialHealthMetricTile(
                title: 'Fixed Costs',
                weight: '10%',
                score: financialHealth.fixedCostScore,
                detail:
                    'Uses categorized expense to estimate how heavy essentials are relative to income.',
                summary: fixedCostSummary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinancialHealthMetricTile extends StatelessWidget {
  final String title;
  final String weight;
  final int score;
  final String detail;
  final String summary;

  const _FinancialHealthMetricTile({
    required this.title,
    required this.weight,
    required this.score,
    required this.detail,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final scoreColor = _healthColor(score);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${context.l10nText(title)} ($weight)',
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '$score/100',
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  summary,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10nText(detail),
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthGaugePainter extends CustomPainter {
  final int score;
  final Color color;

  _HealthGaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    const strokeWidth = 5.0;

    // Background ring
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweepAngle = (score / 100) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HealthGaugePainter oldDelegate) {
    return oldDelegate.score != score || oldDelegate.color != color;
  }
}

class _SubTabBar extends StatelessWidget {
  final _SubTab selectedTab;
  final ValueChanged<_SubTab> onTabChanged;

  const _SubTabBar({
    required this.selectedTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.mutedFill(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: _SubTabButton(
              label: 'Transactions',
              selected: selectedTab == _SubTab.transactions,
              onTap: () => onTabChanged(_SubTab.transactions),
            ),
          ),
          Expanded(
            child: _SubTabButton(
              label: 'Analytics',
              selected: selectedTab == _SubTab.analytics,
              onTap: () => onTabChanged(_SubTab.analytics),
            ),
          ),
          Expanded(
            child: _SubTabButton(
              label: 'Ledger',
              selected: selectedTab == _SubTab.ledger,
              onTap: () => onTabChanged(_SubTab.ledger),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SubTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDark : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color:
                selected ? AppColors.white : AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          child: Text(context.l10nText(label)),
        ),
      ),
    );
  }
}

class _AnalyticsSnapshot {
  final DateTime monthDate;
  final double totalIncome;
  final double totalExpense;
  final double totalFees;
  final int totalTransactions;
  final int incomeCount;
  final int expenseCount;
  final int recipientExpenseCount;
  final Map<int, double> incomeByDay;
  final Map<int, double> expenseByDay;
  final Map<int, double> netByDay;
  final List<double> weekdayExpenseTotals;
  final int peakWeekdayIndex;
  final List<_AnalyticsCategoryStat> categories;
  final List<_AnalyticsRecipientStat> topRecipients;
  final double netCashFlow;
  final double savingsRate;
  final double largestExpense;
  final double largestDeposit;

  const _AnalyticsSnapshot({
    required this.monthDate,
    required this.totalIncome,
    required this.totalExpense,
    required this.totalFees,
    required this.totalTransactions,
    required this.incomeCount,
    required this.expenseCount,
    required this.recipientExpenseCount,
    required this.incomeByDay,
    required this.expenseByDay,
    required this.netByDay,
    required this.weekdayExpenseTotals,
    required this.peakWeekdayIndex,
    required this.categories,
    required this.topRecipients,
    required this.netCashFlow,
    required this.savingsRate,
    required this.largestExpense,
    required this.largestDeposit,
  });
}

class _ActivityTransactionsSummaryRow extends StatelessWidget {
  final _ActivityTransactionsSummary summary;

  const _ActivityTransactionsSummaryRow({
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final currencyLabel = context.l10nText('ETB');
    final transactionLabel = context.l10nText(
      summary.totalTransactions == 1 ? 'transaction' : 'transactions',
    );
    final baseStyle = TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );
    final accentStyle = baseStyle.copyWith(fontWeight: FontWeight.w600);

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                TextSpan(text: '${context.l10nText('Outgoing')} '),
                TextSpan(
                  text:
                      '-$currencyLabel ${_formatEtbAbbrev(summary.totalExpense)}',
                  style: accentStyle.copyWith(color: AppColors.red),
                ),
              ],
            ),
          ),
          Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                TextSpan(text: '${context.l10nText('Incoming')} '),
                TextSpan(
                  text:
                      '+$currencyLabel ${_formatEtbAbbrev(summary.totalIncome)}',
                  style: accentStyle.copyWith(color: AppColors.incomeSuccess),
                ),
              ],
            ),
          ),
          Text(
            '${_formatCount(summary.totalTransactions)} $transactionLabel',
            style: baseStyle,
          ),
        ],
      ),
    );
  }
}

class _AnalyticsCategoryChartPage {
  final _AnalyticsSnapshot snapshot;
  final String periodLabel;

  const _AnalyticsCategoryChartPage({
    required this.snapshot,
    required this.periodLabel,
  });
}

class _AnalyticsSupportContext {
  final List<Transaction> transactions;
  final String periodLabel;
  final String periodKey;
  final bool showIncome;

  const _AnalyticsSupportContext({
    required this.transactions,
    required this.periodLabel,
    required this.periodKey,
    required this.showIncome,
  });
}

class _AnalyticsDateWindow {
  final DateTime start;
  final DateTime endExclusive;

  const _AnalyticsDateWindow({
    required this.start,
    required this.endExclusive,
  });
}

class _AnalyticsSpendingByDaySnapshot {
  final String periodLabel;
  final String periodKey;
  final String emptyLabel;
  final bool showIncome;
  final List<double> weekdayExpenseTotals;
  final int peakWeekdayIndex;

  const _AnalyticsSpendingByDaySnapshot({
    required this.periodLabel,
    required this.periodKey,
    required this.emptyLabel,
    required this.showIncome,
    required this.weekdayExpenseTotals,
    required this.peakWeekdayIndex,
  });
}

class _AnalyticsTopRecipientsSnapshot {
  final String periodLabel;
  final String periodKey;
  final bool showIncome;
  final int recipientExpenseCount;
  final List<_AnalyticsRecipientStat> topRecipients;

  const _AnalyticsTopRecipientsSnapshot({
    required this.periodLabel,
    required this.periodKey,
    required this.showIncome,
    required this.recipientExpenseCount,
    required this.topRecipients,
  });
}

class _AnalyticsMoneyFlowSnapshot {
  final String periodLabel;
  final String periodKey;
  final int totalTransactions;
  final double netCashFlow;
  final double savingsRate;
  final double largestExpense;
  final double largestDeposit;

  const _AnalyticsMoneyFlowSnapshot({
    required this.periodLabel,
    required this.periodKey,
    required this.totalTransactions,
    required this.netCashFlow,
    required this.savingsRate,
    required this.largestExpense,
    required this.largestDeposit,
  });
}

class _AnalyticsCategoryStat {
  final String label;
  final double amount;
  final Color color;

  const _AnalyticsCategoryStat({
    required this.label,
    required this.amount,
    required this.color,
  });
}

class _AnalyticsRecipientStat {
  final String name;
  final double amount;
  final int count;

  const _AnalyticsRecipientStat({
    required this.name,
    required this.amount,
    required this.count,
  });
}

class _AnalyticsRecipientAccumulator {
  double amount = 0.0;
  int count = 0;
}

class _AnalyticsOverviewGrid extends StatelessWidget {
  final _AnalyticsSnapshot snapshot;

  const _AnalyticsOverviewGrid({
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    const spacing = 10.0;
    final incomeLabel = _formatLocalizedCount(
      context,
      snapshot.incomeCount,
      'deposit',
      'deposits',
    );
    final expenseLabel = _formatLocalizedCount(
      context,
      snapshot.expenseCount,
      'expense',
      'expenses',
    );
    final incomeFlowLabel = _formatLocalizedCount(
      context,
      snapshot.incomeCount,
      'income',
      'income',
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final cardWidth = math.max(0.0, (availableWidth - spacing) / 2);
        final cardHeight = math.min(164.0, math.max(148.0, cardWidth * 0.9));

        return Column(
          children: [
            SizedBox(
              height: cardHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _AnalyticsMetricCard(
                      icon: AppIcons.trending_up_rounded,
                      iconBg: const Color(0xFFDCFCE7),
                      iconFg: AppColors.incomeSuccess,
                      title: 'TOTAL INCOME',
                      value: _formatLocalizedEtb(context, snapshot.totalIncome),
                      subtitle: incomeLabel,
                    ),
                  ),
                  const SizedBox(width: spacing),
                  Expanded(
                    child: _AnalyticsMetricCard(
                      icon: AppIcons.trending_down_rounded,
                      iconBg: const Color(0xFFFEE2E2),
                      iconFg: AppColors.red,
                      title: 'TOTAL EXPENSE',
                      value:
                          _formatLocalizedEtb(context, snapshot.totalExpense),
                      subtitle: _formatLocalizedCount(
                        context,
                        snapshot.expenseCount,
                        'transaction',
                        'transactions',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: spacing),
            SizedBox(
              height: cardHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _AnalyticsMetricCard(
                      icon: AppIcons.receipt_long_rounded,
                      iconBg: const Color(0xFFEDE9FE),
                      iconFg: const Color(0xFF6366F1),
                      title: 'TRANSACTIONS',
                      value: _formatCount(snapshot.totalTransactions),
                      subtitle: '$expenseLabel | $incomeFlowLabel',
                    ),
                  ),
                  const SizedBox(width: spacing),
                  Expanded(
                    child: _AnalyticsMetricCard(
                      icon: AppIcons.schedule_rounded,
                      iconBg: const Color(0xFFFEF3C7),
                      iconFg: const Color(0xFFD97706),
                      title: 'TOTAL FEES',
                      value: _formatLocalizedEtb(context, snapshot.totalFees),
                      subtitle: context.l10nText('Service charges + VAT'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AnalyticsMetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String value;
  final String subtitle;

  const _AnalyticsMetricCard({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      color: AppColors.textPrimary(context),
      fontSize: 28,
      fontWeight: FontWeight.w800,
      height: 1.0,
    );
    final subtitleStyle = TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: iconFg),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10nText(title),
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
                  _AnalyticsAutoMarqueeText(
                    text: subtitle,
                    style: subtitleStyle,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsAutoMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final double gap;
  final double pixelsPerSecond;

  const _AnalyticsAutoMarqueeText({
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
    this.gap = 24,
    this.pixelsPerSecond = 26,
  });

  @override
  State<_AnalyticsAutoMarqueeText> createState() =>
      _AnalyticsAutoMarqueeTextState();
}

class _AnalyticsAutoMarqueeTextState extends State<_AnalyticsAutoMarqueeText>
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
        .clamp(3200, 22000)
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

class _AnalyticsHeatmapCard extends StatefulWidget {
  final List<Transaction> transactions;
  final DateTime focusMonth;
  final _AnalyticsHeatmapView view;
  final _AnalyticsHeatmapMode mode;
  final int activeFilterCount;
  final VoidCallback onOpenModeSheet;
  final VoidCallback onOpenChartSheet;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleView;
  final ValueChanged<DateTime>? onDaySelected;
  final ValueChanged<DateTime> onMonthSelected;

  const _AnalyticsHeatmapCard({
    super.key,
    required this.transactions,
    required this.focusMonth,
    required this.view,
    required this.mode,
    this.activeFilterCount = 0,
    required this.onOpenModeSheet,
    required this.onOpenChartSheet,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleView,
    this.onDaySelected,
    required this.onMonthSelected,
  });

  @override
  State<_AnalyticsHeatmapCard> createState() => _AnalyticsHeatmapCardState();
}

class _HeatmapHeaderWidthCache {
  final String key;
  final double previousMonthWidth;
  final double currentMonthWidth;
  final double nextMonthWidth;
  final double monthViewportWidth;
  final double yearViewportWidth;

  const _HeatmapHeaderWidthCache({
    required this.key,
    required this.previousMonthWidth,
    required this.currentMonthWidth,
    required this.nextMonthWidth,
    required this.monthViewportWidth,
    required this.yearViewportWidth,
  });
}

class _AnalyticsHeatmapCardState extends State<_AnalyticsHeatmapCard> {
  static const Duration _pageSwipeDuration = Duration(milliseconds: 450);
  static const double _sectionHeaderSpacing = 10;
  static const double _weekdayHeaderHeight = 16;
  static const double _weekdayHeaderSpacing = 8;
  static const double _sectionFooterSpacing = 10;
  static const double _pageGridHorizontalInset = 12;
  static const double _viewportOverflowSlack = 2;

  late final PageController _pageController;
  late DateTime _visibleMonth;
  bool _isRecenteringPage = false;
  _HeatmapHeaderWidthCache? _headerWidthCache;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
    _visibleMonth = _normalizeVisibleMonth(widget.focusMonth);
  }

  @override
  void didUpdateWidget(covariant _AnalyticsHeatmapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusMonth != oldWidget.focusMonth) {
      final nextVisibleMonth = _normalizeVisibleMonth(widget.focusMonth);
      if (!_isSameVisibleMonth(_visibleMonth, nextVisibleMonth)) {
        setState(() {
          _visibleMonth = nextVisibleMonth;
        });
        if (_pageController.hasClients &&
            (_pageController.page?.round() ?? 1) != 1) {
          _pageController.jumpToPage(1);
        }
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPreviousPeriod() {
    _animateToRelativePage(0);
  }

  void _goToNextPeriod() {
    _animateToRelativePage(2);
  }

  void _handleToggleView() {
    widget.onToggleView();
  }

  void _handleMonthSelected(DateTime month) {
    widget.onMonthSelected(month);
  }

  Future<void> _animateToRelativePage(int page) async {
    if (_isRecenteringPage || !_pageController.hasClients) return;
    await _pageController.animateToPage(
      page,
      duration: _pageSwipeDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  DateTime _normalizeVisibleMonth(DateTime date) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        final ec =
            Kenat.fromGregorian(date.year, date.month, date.day).getEthiopian();
        final gcStart =
            Kenat.fromEthiopian(ec['year']!, ec['month']!, 1).getGregorian();
        return DateTime(gcStart['year']!, gcStart['month']!, gcStart['day']!);
      }
    } catch (_) {}
    return DateTime(date.year, date.month, 1);
  }

  bool _isSameVisibleMonth(DateTime a, DateTime b) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        final ecA = Kenat.fromGregorian(a.year, a.month, a.day).getEthiopian();
        final ecB = Kenat.fromGregorian(b.year, b.month, b.day).getEthiopian();
        return ecA['year'] == ecB['year'] && ecA['month'] == ecB['month'];
      }
    } catch (_) {}
    return a.year == b.year && a.month == b.month;
  }

  DateTime _shiftVisibleMonth(DateTime month, int delta) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        final ec = Kenat.fromGregorian(month.year, month.month, month.day)
            .getEthiopian();
        if (widget.view == _AnalyticsHeatmapView.daily) {
          var y = ec['year']!;
          var m = ec['month']! + delta;
          while (m > 13) {
            m -= 13;
            y++;
          }
          while (m < 1) {
            m += 13;
            y--;
          }
          final gc = Kenat.fromEthiopian(y, m, 1).getGregorian();
          return DateTime(gc['year']!, gc['month']!, gc['day']!);
        }
        final gc = Kenat.fromEthiopian(ec['year']! + delta, ec['month']!, 1)
            .getGregorian();
        return DateTime(gc['year']!, gc['month']!, gc['day']!);
      }
    } catch (_) {}
    if (widget.view == _AnalyticsHeatmapView.daily) {
      return DateTime(month.year, month.month + delta, 1);
    }
    return DateTime(month.year + delta, month.month, 1);
  }

  String _formatPeriodLabel(DateTime month) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        final ec = Kenat.fromGregorian(month.year, month.month, month.day)
            .getEthiopian();
        return widget.view == _AnalyticsHeatmapView.daily
            ? _formatEthiopianMonthNameForContext(
                ec['month']!,
                context,
                abbreviated: false,
              )
            : '${ec['year']}';
      }
    } catch (_) {}
    return widget.view == _AnalyticsHeatmapView.daily
        ? _formatFullMonthName(month, context)
        : '${month.year}';
  }

  String _formatHeaderPeriodLabel(DateTime month) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        final ec = Kenat.fromGregorian(month.year, month.month, month.day)
            .getEthiopian();
        final useFullMonthName =
            AppDateFormat.languageOf(context) == AppLanguageOption.amharic;
        return widget.view == _AnalyticsHeatmapView.daily
            ? '${_formatEthiopianMonthNameForContext(
                ec['month']!,
                context,
                abbreviated: !useFullMonthName,
              )} ${ec['year']}'
            : '${ec['year']}';
      }
    } catch (_) {}
    return widget.view == _AnalyticsHeatmapView.daily
        ? _formatMonthYear(month, context)
        : '${month.year}';
  }

  void _commitPageChange(int page) {
    if (_isRecenteringPage || page == 1) return;
    final delta = page == 0 ? -1 : 1;
    final nextVisibleMonth = _shiftVisibleMonth(_visibleMonth, delta);

    setState(() {
      _visibleMonth = nextVisibleMonth;
      _isRecenteringPage = true;
    });

    if (_pageController.hasClients) {
      _pageController.jumpToPage(1);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _isRecenteringPage = false);
    });
    HapticFeedback.selectionClick();
    if (delta < 0) {
      widget.onPrevious();
    } else {
      widget.onNext();
    }
  }

  bool _handleHeatmapScrollNotification(ScrollNotification notification) {
    if (_isRecenteringPage || notification.depth != 0) return false;
    if (notification is! ScrollEndNotification) return false;

    final metrics = notification.metrics;
    if (metrics is! PageMetrics) return false;

    final page = metrics.page?.round() ?? 1;
    _commitPageChange(page);
    return false;
  }

  double _heatmapViewportHeight({
    required double width,
    required DateTime visibleMonth,
  }) {
    if (width <= 0) return 320;
    final contentWidth = math.max(
      0.0,
      width - (_pageGridHorizontalInset * 2),
    );
    if (contentWidth <= 0) return 320;

    double gridHeight;
    if (widget.view == _AnalyticsHeatmapView.daily) {
      const crossCount = 7;
      const rowCount = 6;
      const spacing = 4.0;
      const aspectRatio = 1.04;
      final cellWidth =
          (contentWidth - (spacing * (crossCount - 1))) / crossCount;
      final cellHeight = cellWidth / aspectRatio;
      gridHeight = (cellHeight * rowCount) + (spacing * (rowCount - 1));
      return _weekdayHeaderHeight +
          _weekdayHeaderSpacing +
          gridHeight +
          _viewportOverflowSlack;
    } else {
      const crossCount = 4;
      const spacing = 6.0;
      const aspectRatio = 1.35;
      const rowCount = 3;
      final cellWidth =
          (contentWidth - (spacing * (crossCount - 1))) / crossCount;
      final cellHeight = cellWidth / aspectRatio;
      gridHeight = (cellHeight * rowCount) + (spacing * (rowCount - 1));
      return gridHeight + _viewportOverflowSlack;
    }
  }

  Widget _buildAnimatedHeatmapSection({
    required BuildContext context,
    required DateTime now,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previousMonth = _shiftVisibleMonth(_visibleMonth, -1);
        final nextMonth = _shiftVisibleMonth(_visibleMonth, 1);
        final viewportHeight = math.max(
          _heatmapViewportHeight(
            width: constraints.maxWidth,
            visibleMonth: previousMonth,
          ),
          math.max(
            _heatmapViewportHeight(
              width: constraints.maxWidth,
              visibleMonth: _visibleMonth,
            ),
            _heatmapViewportHeight(
              width: constraints.maxWidth,
              visibleMonth: nextMonth,
            ),
          ),
        );
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _handleToggleView,
                    behavior: HitTestBehavior.opaque,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildAnimatedHeaderPeriodLabel(context),
                    ),
                  ),
                ),
                const _AnalyticsLegendDot(
                  color: AppColors.incomeSuccess,
                  label: 'Income',
                ),
                const SizedBox(width: 10),
                const _AnalyticsLegendDot(
                  color: AppColors.red,
                  label: 'Expense',
                ),
              ],
            ),
            const SizedBox(height: _sectionHeaderSpacing),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: viewportHeight,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleHeatmapScrollNotification,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: 3,
                    physics: const PageScrollPhysics(),
                    itemBuilder: (context, index) {
                      final pageMonth = _shiftVisibleMonth(
                        _visibleMonth,
                        index - 1,
                      );
                      final valuesByBucket =
                          widget.view == _AnalyticsHeatmapView.daily
                              ? _buildDailyValues(pageMonth)
                              : _buildMonthlyValues(pageMonth);
                      final maxMagnitude = valuesByBucket.values.fold<double>(
                        0.0,
                        (currentMax, value) =>
                            math.max(currentMax, value.abs()),
                      );

                      return KeyedSubtree(
                        key: ValueKey<String>(
                          'heatmap-page-${widget.mode.name}-${pageMonth.year}-${pageMonth.month}',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _pageGridHorizontalInset,
                          ),
                          child: _buildAnimatedHeatmapPageBody(
                            context: context,
                            pageMonth: pageMonth,
                            now: now,
                            valuesByBucket: valuesByBucket,
                            maxMagnitude: maxMagnitude,
                            onDaySelected:
                                index == 1 ? widget.onDaySelected : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: _sectionFooterSpacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AnalyticsHeatmapNavButton(
                  icon: AppIcons.chevron_left_rounded,
                  onTap: _goToPreviousPeriod,
                ),
                const SizedBox(width: 6),
                _buildAnimatedPeriodLabel(context),
                const SizedBox(width: 6),
                _AnalyticsHeatmapNavButton(
                  icon: AppIcons.chevron_right_rounded,
                  onTap: _goToNextPeriod,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnimatedHeatmapPageBody({
    required BuildContext context,
    required DateTime pageMonth,
    required DateTime now,
    required Map<int, double> valuesByBucket,
    required double maxMagnitude,
    ValueChanged<DateTime>? onDaySelected,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final isIncoming =
            (child.key as ValueKey<_AnalyticsHeatmapView>).value == widget.view;
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final t = animation.value;
            final scaleProgress = Curves.easeOutCubic.transform(t);
            final opacity = isIncoming
                ? const Interval(0.14, 1.0, curve: Curves.easeOutCubic)
                    .transform(t)
                : Curves.easeOutCubic.transform(t);
            final beginScale = isIncoming ? 0.94 : 0.98;
            final scale = beginScale + ((1.0 - beginScale) * scaleProgress);

            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: child,
              ),
            );
          },
        );
      },
      child: KeyedSubtree(
        key: ValueKey<_AnalyticsHeatmapView>(widget.view),
        child: Column(
          children: [
            if (widget.view == _AnalyticsHeatmapView.daily) ...[
              const _AnalyticsWeekdayHeader(),
              const SizedBox(height: _weekdayHeaderSpacing),
              _buildDailyGrid(
                context: context,
                visibleMonth: pageMonth,
                now: now,
                valuesByDay: valuesByBucket,
                maxMagnitude: maxMagnitude,
                onDaySelected: onDaySelected,
              ),
            ] else ...[
              _buildMonthlyGrid(
                context: context,
                visibleMonth: pageMonth,
                now: now,
                valuesByMonth: valuesByBucket,
                maxMagnitude: maxMagnitude,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedPeriodLabel(BuildContext context) {
    final textStyle = TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    return _buildAnimatedSlidingLabel(
      context: context,
      textStyle: textStyle,
      labelWidth: _measurePeriodViewportWidth(context, textStyle),
      labelHeight: 20,
      labelBuilder: _formatPeriodLabel,
    );
  }

  Widget _buildAnimatedHeaderPeriodLabel(BuildContext context) {
    final textStyle = TextStyle(
      color: AppColors.textPrimary(context),
      fontSize: 28,
      fontWeight: FontWeight.w700,
    );
    if (widget.view == _AnalyticsHeatmapView.monthly) {
      return _buildAnimatedSlidingLabel(
        context: context,
        textStyle: textStyle,
        labelWidth: _measureHeaderYearViewportWidth(context, textStyle),
        labelHeight: 36,
        labelBuilder: _formatHeaderPeriodLabel,
        itemAlignment: Alignment.centerLeft,
        axis: Axis.vertical,
      );
    }

    final isEC =
        Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
            AppCalendarOption.ethiopian;
    final previousMonth = _shiftVisibleMonth(_visibleMonth, -1);
    final nextMonth = _shiftVisibleMonth(_visibleMonth, 1);

    String getMonthLabel(DateTime month) {
      if (isEC) {
        final ec = Kenat.fromGregorian(month.year, month.month, month.day)
            .getEthiopian();
        final useFullMonthName =
            AppDateFormat.languageOf(context) == AppLanguageOption.amharic;
        return _formatEthiopianMonthNameForContext(
          ec['month']!,
          context,
          abbreviated: !useFullMonthName,
        );
      }
      return AppDateFormat.monthShort(month, context: context);
    }

    String getYearLabel(DateTime month) {
      if (isEC) {
        final ec = Kenat.fromGregorian(month.year, month.month, month.day)
            .getEthiopian();
        return '${ec['year']}';
      }
      return '${month.year}';
    }

    final currentYearLabel = getYearLabel(_visibleMonth);
    final prevYearLabel = getYearLabel(previousMonth);
    final nextYearLabel = getYearLabel(nextMonth);
    final previousMonthLabel = getMonthLabel(previousMonth);
    final currentMonthLabel = getMonthLabel(_visibleMonth);
    final nextMonthLabel = getMonthLabel(nextMonth);
    final headerWidths = _resolveHeaderWidthCache(
      context: context,
      style: textStyle,
      previousMonthLabel: previousMonthLabel,
      currentMonthLabel: currentMonthLabel,
      nextMonthLabel: nextMonthLabel,
      monthViewportLabels: _headerMonthViewportLabels(context),
      previousYearLabel: prevYearLabel,
      currentYearLabel: currentYearLabel,
      nextYearLabel: nextYearLabel,
    );
    final monthViewportWidth = headerWidths.monthViewportWidth;
    final yearViewportWidth = headerWidths.yearViewportWidth;
    final monthYearGap = _measureHeaderMonthYearGap(textStyle);

    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, _) {
        final visibleMonthWidth = _resolveAnimatedHeaderMonthWidth(
          previousWidth: headerWidths.previousMonthWidth,
          currentWidth: headerWidths.currentMonthWidth,
          nextWidth: headerWidths.nextMonthWidth,
        );
        final hiddenMonthWidth = (monthViewportWidth - visibleMonthWidth)
            .clamp(0.0, monthViewportWidth)
            .toDouble();
        final yearShift = -hiddenMonthWidth;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAnimatedSlidingLabelValues(
              textStyle: textStyle,
              labelWidth: monthViewportWidth,
              labelHeight: 36,
              previousLabel: previousMonthLabel,
              currentLabel: currentMonthLabel,
              nextLabel: nextMonthLabel,
              itemAlignment: Alignment.centerLeft,
              axis: Axis.vertical,
            ),
            Transform.translate(
              offset: Offset(yearShift, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: monthYearGap),
                  _buildAnimatedSlidingLabelValues(
                    textStyle: textStyle,
                    labelWidth: yearViewportWidth,
                    labelHeight: 36,
                    previousLabel: prevYearLabel == currentYearLabel
                        ? currentYearLabel
                        : prevYearLabel,
                    currentLabel: currentYearLabel,
                    nextLabel: nextYearLabel == currentYearLabel
                        ? currentYearLabel
                        : nextYearLabel,
                    itemAlignment: Alignment.centerLeft,
                    axis: Axis.vertical,
                    animateNegative: prevYearLabel != currentYearLabel,
                    animatePositive: nextYearLabel != currentYearLabel,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnimatedSlidingLabel({
    required BuildContext context,
    required TextStyle textStyle,
    required double labelWidth,
    required double labelHeight,
    required String Function(DateTime month) labelBuilder,
    AlignmentGeometry itemAlignment = Alignment.center,
    Axis axis = Axis.horizontal,
  }) {
    final previousMonth = _shiftVisibleMonth(_visibleMonth, -1);
    final nextMonth = _shiftVisibleMonth(_visibleMonth, 1);
    return _buildAnimatedSlidingLabelValues(
      textStyle: textStyle,
      labelWidth: labelWidth,
      labelHeight: labelHeight,
      previousLabel: labelBuilder(previousMonth),
      currentLabel: labelBuilder(_visibleMonth),
      nextLabel: labelBuilder(nextMonth),
      itemAlignment: itemAlignment,
      axis: axis,
    );
  }

  Widget _buildAnimatedSlidingLabelValues({
    required TextStyle textStyle,
    required double labelWidth,
    required double labelHeight,
    required String previousLabel,
    required String currentLabel,
    required String nextLabel,
    AlignmentGeometry itemAlignment = Alignment.center,
    Axis axis = Axis.horizontal,
    bool animateNegative = true,
    bool animatePositive = true,
  }) {
    return SizedBox(
      width: labelWidth,
      height: labelHeight,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _pageController,
          builder: (context, _) {
            final page = _pageController.hasClients
                ? (_pageController.page ?? 1.0)
                : 1.0;
            final delta = (page - 1).clamp(-1.0, 1.0);
            final shouldFreeze = (delta < 0 && !animateNegative) ||
                (delta > 0 && !animatePositive) ||
                delta == 0;
            if (shouldFreeze) {
              return _buildAnimatedPeriodLabelItem(
                label: currentLabel,
                style: textStyle,
                width: labelWidth,
                height: labelHeight,
                alignment: itemAlignment,
              );
            }
            final mainAxisExtent =
                axis == Axis.horizontal ? labelWidth : labelHeight;
            final stripWidth =
                axis == Axis.horizontal ? labelWidth * 3 : labelWidth;
            final stripHeight =
                axis == Axis.horizontal ? labelHeight : labelHeight * 3;
            final offset = axis == Axis.horizontal
                ? Offset(-(1 + delta) * mainAxisExtent, 0)
                : Offset(0, -(1 + delta) * mainAxisExtent);

            return OverflowBox(
              alignment: axis == Axis.horizontal
                  ? Alignment.centerLeft
                  : Alignment.topLeft,
              minWidth: stripWidth,
              maxWidth: stripWidth,
              minHeight: stripHeight,
              maxHeight: stripHeight,
              child: Transform.translate(
                offset: offset,
                child: SizedBox(
                  width: stripWidth,
                  height: stripHeight,
                  child: axis == Axis.horizontal
                      ? Row(
                          children: [
                            _buildAnimatedPeriodLabelItem(
                              label: previousLabel,
                              style: textStyle,
                              width: labelWidth,
                              height: labelHeight,
                              alignment: itemAlignment,
                            ),
                            _buildAnimatedPeriodLabelItem(
                              label: currentLabel,
                              style: textStyle,
                              width: labelWidth,
                              height: labelHeight,
                              alignment: itemAlignment,
                            ),
                            _buildAnimatedPeriodLabelItem(
                              label: nextLabel,
                              style: textStyle,
                              width: labelWidth,
                              height: labelHeight,
                              alignment: itemAlignment,
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _buildAnimatedPeriodLabelItem(
                              label: previousLabel,
                              style: textStyle,
                              width: labelWidth,
                              height: labelHeight,
                              alignment: itemAlignment,
                            ),
                            _buildAnimatedPeriodLabelItem(
                              label: currentLabel,
                              style: textStyle,
                              width: labelWidth,
                              height: labelHeight,
                              alignment: itemAlignment,
                            ),
                            _buildAnimatedPeriodLabelItem(
                              label: nextLabel,
                              style: textStyle,
                              width: labelWidth,
                              height: labelHeight,
                              alignment: itemAlignment,
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  double _measurePeriodViewportWidth(BuildContext context, TextStyle style) {
    final isEC =
        Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
            AppCalendarOption.ethiopian;
    final labels = widget.view == _AnalyticsHeatmapView.daily
        ? isEC
            ? List<String>.generate(
                13,
                (index) => _formatEthiopianMonthNameForContext(
                  index + 1,
                  context,
                  abbreviated: false,
                ),
              )
            : List<String>.generate(
                12,
                (index) => _formatFullMonthName(
                  DateTime(2024, index + 1, 1),
                  context,
                ),
              )
        : [
            _formatPeriodLabel(_shiftVisibleMonth(_visibleMonth, -1)),
            _formatPeriodLabel(_visibleMonth),
            _formatPeriodLabel(_shiftVisibleMonth(_visibleMonth, 1)),
          ];
    return _measureLabelViewportWidth(
      context: context,
      style: style,
      labels: labels,
      extraWidth: 8,
    );
  }

  List<String> _headerMonthViewportLabels(BuildContext context) {
    final isEC =
        Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
            AppCalendarOption.ethiopian;
    final useFullEthiopianMonthName =
        AppDateFormat.languageOf(context) == AppLanguageOption.amharic;
    return isEC
        ? List<String>.generate(
            13,
            (index) => _formatEthiopianMonthNameForContext(
              index + 1,
              context,
              abbreviated: !useFullEthiopianMonthName,
            ),
          )
        : List<String>.generate(
            12,
            (index) => AppDateFormat.monthShort(
              DateTime(2024, index + 1, 1),
              context: context,
            ),
          );
  }

  double _measureHeaderYearViewportWidth(
    BuildContext context,
    TextStyle style,
  ) {
    final labels = [
      '${_visibleMonth.year - 1}',
      '${_visibleMonth.year}',
      '${_visibleMonth.year + 1}',
    ];
    return _measureLabelViewportWidth(
      context: context,
      style: style,
      labels: labels,
      extraWidth: 8,
    );
  }

  _HeatmapHeaderWidthCache _resolveHeaderWidthCache({
    required BuildContext context,
    required TextStyle style,
    required String previousMonthLabel,
    required String currentMonthLabel,
    required String nextMonthLabel,
    required List<String> monthViewportLabels,
    required String previousYearLabel,
    required String currentYearLabel,
    required String nextYearLabel,
  }) {
    final language = AppDateFormat.languageOf(context);
    final calendar = AppDateFormat.calendarOf(context);
    final direction = Directionality.of(context);
    final fontSize = style.fontSize ?? 14;
    final scaledFontSize =
        MediaQuery.textScalerOf(context).scale(fontSize).toStringAsFixed(3);
    final key = <String>[
      widget.view.name,
      language.storageValue,
      calendar.storageValue,
      '$direction',
      scaledFontSize,
      '${style.fontWeight?.index ?? ''}',
      '${style.fontStyle?.index ?? ''}',
      '${style.letterSpacing ?? ''}',
      style.fontFamily ?? '',
      previousMonthLabel,
      currentMonthLabel,
      nextMonthLabel,
      previousYearLabel,
      currentYearLabel,
      nextYearLabel,
      ...monthViewportLabels,
    ].join('\u001f');

    final cached = _headerWidthCache;
    if (cached != null && cached.key == key) return cached;

    final nextCache = _HeatmapHeaderWidthCache(
      key: key,
      previousMonthWidth: _measureLabelTextWidth(
        context: context,
        style: style,
        label: previousMonthLabel,
      ),
      currentMonthWidth: _measureLabelTextWidth(
        context: context,
        style: style,
        label: currentMonthLabel,
      ),
      nextMonthWidth: _measureLabelTextWidth(
        context: context,
        style: style,
        label: nextMonthLabel,
      ),
      monthViewportWidth: _measureLabelViewportWidth(
        context: context,
        style: style,
        labels: monthViewportLabels,
        extraWidth: 8,
      ),
      yearViewportWidth: _measureLabelViewportWidth(
        context: context,
        style: style,
        labels: [previousYearLabel, currentYearLabel, nextYearLabel],
        extraWidth: 8,
      ),
    );
    _headerWidthCache = nextCache;
    return nextCache;
  }

  double _resolveAnimatedHeaderMonthWidth({
    required double previousWidth,
    required double currentWidth,
    required double nextWidth,
  }) {
    final page =
        _pageController.hasClients ? (_pageController.page ?? 1.0) : 1.0;
    final delta = (page - 1).clamp(-1.0, 1.0);
    if (delta.abs() < 0.001) return currentWidth;

    final targetWidth = delta < 0 ? previousWidth : nextWidth;
    final progress = delta.abs().clamp(0.0, 1.0).toDouble();
    return currentWidth + ((targetWidth - currentWidth) * progress);
  }

  double _measureHeaderMonthYearGap(TextStyle style) {
    final fontSize = style.fontSize ?? 28;
    return (fontSize * 0.38).clamp(9.0, 13.0).toDouble();
  }

  double _measureLabelViewportWidth({
    required BuildContext context,
    required TextStyle style,
    required List<String> labels,
    double extraWidth = 8,
  }) {
    var maxWidth = 0.0;

    for (final label in labels) {
      maxWidth = math.max(
        maxWidth,
        _measureLabelTextWidth(
          context: context,
          style: style,
          label: label,
        ),
      );
    }

    return maxWidth.ceilToDouble() + extraWidth;
  }

  double _measureLabelTextWidth({
    required BuildContext context,
    required TextStyle style,
    required String label,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  Widget _buildAnimatedPeriodLabelItem({
    required String label,
    required TextStyle style,
    required double width,
    required double height,
    AlignmentGeometry alignment = Alignment.center,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: Align(
        alignment: alignment,
        child: Text(
          context.l10nText(label),
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: style,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onOpenChartSheet,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Text(
                      context.l10nText('Heatmap'),
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      AppIcons.keyboard_arrow_down_rounded,
                      color: AppColors.textTertiary(context),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _AnalyticsFilterBadgeButton(
                activeCount: widget.activeFilterCount,
                onTap: widget.onOpenModeSheet,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildAnimatedHeatmapSection(
            context: context,
            now: now,
          ),
        ],
      ),
    );
  }

  Map<int, double> _buildDailyValues(DateTime month) {
    final values = <int, double>{};
    final isEC =
        Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
            AppCalendarOption.ethiopian;
    final targetEc = isEC
        ? Kenat.fromGregorian(month.year, month.month, month.day).getEthiopian()
        : null;

    for (final transaction in widget.transactions) {
      final dt = _parseTransactionTime(transaction.time);
      if (dt == null) continue;

      if (isEC) {
        final ec =
            Kenat.fromGregorian(dt.year, dt.month, dt.day).getEthiopian();
        if (ec['year'] != targetEc!['year'] || ec['month'] != targetEc['month'])
          continue;
        final delta = _heatmapDelta(transaction);
        if (delta.abs() < 0.001) continue;
        values[ec['day']!] = (values[ec['day']!] ?? 0.0) + delta;
      } else {
        if (dt.year != month.year || dt.month != month.month) continue;
        final delta = _heatmapDelta(transaction);
        if (delta.abs() < 0.001) continue;
        values[dt.day] = (values[dt.day] ?? 0.0) + delta;
      }
    }
    return values;
  }

  Map<int, double> _buildMonthlyValues(DateTime visibleMonth) {
    final values = <int, double>{};
    final isEC =
        Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
            AppCalendarOption.ethiopian;
    final targetEcYear = isEC
        ? Kenat.fromGregorian(
            visibleMonth.year,
            visibleMonth.month,
            visibleMonth.day,
          ).getEthiopian()['year']
        : null;

    for (final transaction in widget.transactions) {
      final dt = _parseTransactionTime(transaction.time);
      if (dt == null) continue;

      if (isEC) {
        final ec =
            Kenat.fromGregorian(dt.year, dt.month, dt.day).getEthiopian();
        if (ec['year'] != targetEcYear) continue;
        final delta = _heatmapDelta(transaction);
        if (delta.abs() < 0.001) continue;
        values[ec['month']!] = (values[ec['month']!] ?? 0.0) + delta;
      } else {
        if (dt.year != visibleMonth.year) continue;
        final delta = _heatmapDelta(transaction);
        if (delta.abs() < 0.001) continue;
        values[dt.month] = (values[dt.month] ?? 0.0) + delta;
      }
    }
    return values;
  }

  Widget _buildDailyGrid({
    required BuildContext context,
    required DateTime visibleMonth,
    required DateTime now,
    required Map<int, double> valuesByDay,
    required double maxMagnitude,
    ValueChanged<DateTime>? onDaySelected,
  }) {
    final isEC =
        Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
            AppCalendarOption.ethiopian;
    if (isEC) {
      final ec = Kenat.fromGregorian(
              visibleMonth.year, visibleMonth.month, visibleMonth.day)
          .getEthiopian();
      final grid =
          MonthGrid({'year': ec['year'], 'month': ec['month'], 'weekStart': 1})
              .generate();
      final List<Map<String, dynamic>?> days =
          List<Map<String, dynamic>?>.from(grid['days']);
      const totalCells = 42;

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: totalCells,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 1.04,
        ),
        itemBuilder: (context, index) {
          if (index >= days.length || days[index] == null) {
            return const SizedBox.shrink();
          }

          final dayData = days[index]!;
          final day = dayData['ethiopian']['day'] as int;
          final value = valuesByDay[day] ?? 0.0;

          final ecNow =
              Kenat.fromGregorian(now.year, now.month, now.day).getEthiopian();
          final isCurrentDay = ec['year'] == ecNow['year'] &&
              ec['month'] == ecNow['month'] &&
              day == ecNow['day'];

          return _buildHeatmapCell(
            context: context,
            label: '$day',
            value: value,
            maxMagnitude: maxMagnitude,
            isCurrent: isCurrentDay,
            onTap: onDaySelected == null
                ? null
                : () {
                    final gc = dayData['gregorian'];
                    onDaySelected(DateTime(gc['year'], gc['month'], gc['day']));
                  },
          );
        },
      );
    }

    final daysInMonth =
        DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final startOffset = visibleMonth.weekday - 1;
    const totalCells = 42;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalCells,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1.04,
      ),
      itemBuilder: (context, index) {
        final day = index - startOffset + 1;
        if (index < startOffset || day < 1 || day > daysInMonth) {
          return const SizedBox.shrink();
        }

        final value = valuesByDay[day] ?? 0.0;
        final isCurrentDay = visibleMonth.year == now.year &&
            visibleMonth.month == now.month &&
            day == now.day;

        return _buildHeatmapCell(
          context: context,
          label: '$day',
          value: value,
          maxMagnitude: maxMagnitude,
          isCurrent: isCurrentDay,
          onTap: onDaySelected == null
              ? null
              : () => onDaySelected(
                    DateTime(visibleMonth.year, visibleMonth.month, day),
                  ),
        );
      },
    );
  }

  Widget _buildMonthlyGrid({
    required BuildContext context,
    required DateTime visibleMonth,
    required DateTime now,
    required Map<int, double> valuesByMonth,
    required double maxMagnitude,
  }) {
    final isEC =
        Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
            AppCalendarOption.ethiopian;
    final itemCount = isEC ? 13 : 12;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final monthNumber = index + 1;
        final value = valuesByMonth[monthNumber] ?? 0.0;

        bool isCurrentMonth = false;
        bool isSelectedMonth = false;
        String label = '';
        DateTime monthDate;

        if (isEC) {
          final ec = Kenat.fromGregorian(
                  visibleMonth.year, visibleMonth.month, visibleMonth.day)
              .getEthiopian();
          final ecNow =
              Kenat.fromGregorian(now.year, now.month, now.day).getEthiopian();
          isCurrentMonth =
              ec['year'] == ecNow['year'] && monthNumber == ecNow['month'];
          isSelectedMonth = monthNumber == ec['month'];
          label = _formatEthiopianMonthNameForContext(monthNumber, context);
          final gc =
              Kenat.fromEthiopian(ec['year']!, monthNumber, 1).getGregorian();
          monthDate = DateTime(gc['year']!, gc['month']!, gc['day']!);
        } else {
          monthDate = DateTime(visibleMonth.year, monthNumber, 1);
          isCurrentMonth =
              visibleMonth.year == now.year && monthNumber == now.month;
          isSelectedMonth = monthNumber == visibleMonth.month;
          label = AppDateFormat.monthShort(monthDate, context: context);
        }

        return _buildHeatmapCell(
          context: context,
          label: label,
          value: value,
          maxMagnitude: maxMagnitude,
          isCurrent: isCurrentMonth,
          isSelected: isSelectedMonth,
          labelFontSize: 14,
          valueFontSize: 10,
          onTap: () => _handleMonthSelected(monthDate),
        );
      },
    );
  }

  Widget _buildHeatmapCell({
    required BuildContext context,
    required String label,
    required double value,
    required double maxMagnitude,
    required bool isCurrent,
    bool isSelected = false,
    double labelFontSize = 15,
    double valueFontSize = 11,
    VoidCallback? onTap,
  }) {
    final hasValue = value.abs() > 0.001;
    final intensity =
        maxMagnitude > 0 ? (value.abs() / maxMagnitude).clamp(0.0, 1.0) : 0.0;
    final baseValueColor = value >= 0 ? AppColors.incomeSuccess : AppColors.red;

    var backgroundColor = Colors.transparent;
    if (isSelected) {
      backgroundColor = AppColors.mutedFill(context).withValues(
        alpha: AppColors.isDark(context) ? 0.32 : 0.52,
      );
    }
    if (hasValue) {
      final heatColor =
          baseValueColor.withValues(alpha: 0.12 + (0.24 * intensity));
      backgroundColor = isSelected
          ? Color.lerp(backgroundColor, heatColor, 0.75) ?? heatColor
          : heatColor;
    }

    final borderColor = isCurrent
        ? AppColors.primaryLight
        : (isSelected ? AppColors.borderColor(context) : Colors.transparent);
    final primaryTextColor = hasValue
        ? baseValueColor
        : (isCurrent ? AppColors.primaryLight : AppColors.textPrimary(context));

    final cell = LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxHeight < 32 || constraints.maxWidth < 36;
        final isVeryCompact =
            constraints.maxHeight < 28 || constraints.maxWidth < 32;
        final showValue = hasValue &&
            constraints.maxHeight >= 30 &&
            constraints.maxWidth >= 34;
        final effectiveHorizontalPadding = isVeryCompact ? 2.0 : 4.0;
        final effectiveVerticalPadding = isCompact ? 3.0 : 6.0;
        final effectiveLabelFontSize =
            isVeryCompact ? math.max(11.0, labelFontSize - 2.0) : labelFontSize;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: effectiveHorizontalPadding,
            vertical: effectiveVerticalPadding,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: isCurrent ? 1.6 : (isSelected ? 1.1 : 1),
            ),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: primaryTextColor,
                      fontSize: effectiveLabelFontSize,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                  if (showValue)
                    Text(
                      _formatCompactSignedEtb(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: baseValueColor,
                        fontSize: valueFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (onTap == null) return cell;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: cell,
    );
  }

  double _heatmapDelta(Transaction transaction) {
    switch (widget.mode) {
      case _AnalyticsHeatmapMode.all:
        if (transaction.type == 'CREDIT') return transaction.amount;
        if (transaction.type == 'DEBIT') return -transaction.amount;
        return 0.0;
      case _AnalyticsHeatmapMode.expense:
        return transaction.type == 'DEBIT' ? -transaction.amount : 0.0;
      case _AnalyticsHeatmapMode.income:
        return transaction.type == 'CREDIT' ? transaction.amount : 0.0;
    }
  }
}

class _AnalyticsHeatmapNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AnalyticsHeatmapNavButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: AppColors.textTertiary(context),
        ),
      ),
    );
  }
}

class _AnalyticsFilterBadgeButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const _AnalyticsFilterBadgeButton({
    this.activeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilters = activeCount > 0;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: hasFilters
                  ? AppColors.primaryDark.withValues(alpha: 0.1)
                  : AppColors.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasFilters
                    ? AppColors.primaryDark
                    : AppColors.borderColor(context),
              ),
            ),
            child: Icon(
              AppIcons.filter_list,
              size: 18,
              color: hasFilters
                  ? AppColors.primaryDark
                  : AppColors.textSecondary(context),
            ),
          ),
          if (hasFilters)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnalyticsPrimaryChartHeader extends StatelessWidget {
  final String chartLabel;
  final String headline;
  final String supportingText;
  final int activeFilterCount;
  final VoidCallback? onOpenFilterSheet;
  final VoidCallback? onChartPickerTap;
  final Widget? details;

  const _AnalyticsPrimaryChartHeader({
    required this.chartLabel,
    required this.headline,
    required this.supportingText,
    this.activeFilterCount = 0,
    this.onOpenFilterSheet,
    this.onChartPickerTap,
    this.details,
  });

  @override
  Widget build(BuildContext context) {
    final showFilterButton = onOpenFilterSheet != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (onChartPickerTap == null)
              Text(
                context.l10nText(chartLabel),
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              GestureDetector(
                onTap: onChartPickerTap,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Text(
                      context.l10nText(chartLabel),
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      AppIcons.keyboard_arrow_down_rounded,
                      color: AppColors.textTertiary(context),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            if (showFilterButton)
              _AnalyticsFilterBadgeButton(
                activeCount: activeFilterCount,
                onTap: onOpenFilterSheet!,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (details != null)
          details!
        else ...[
          Text(
            context.l10nText(headline),
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10nText(supportingText),
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _AnalyticsFlowModeToggle extends StatelessWidget {
  final bool showIncome;
  final ValueChanged<_AnalyticsHeatmapMode> onChanged;

  const _AnalyticsFlowModeToggle({
    required this.showIncome,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.mutedFill(context).withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AnalyticsFlowModeToggleOption(
            label: 'Expense',
            color: AppColors.red,
            selected: !showIncome,
            onTap: () => onChanged(_AnalyticsHeatmapMode.expense),
          ),
          const SizedBox(width: 4),
          _AnalyticsFlowModeToggleOption(
            label: 'Income',
            color: AppColors.incomeSuccess,
            selected: showIncome,
            onTap: () => onChanged(_AnalyticsHeatmapMode.income),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsFlowModeToggleOption extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AnalyticsFlowModeToggleOption({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                selected ? color.withValues(alpha: 0.34) : Colors.transparent,
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: selected ? color : AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
          child: Text(context.l10nText(label)),
        ),
      ),
    );
  }
}

class _AnalyticsHorizontalSwipeBlocker extends StatelessWidget {
  final Widget child;

  const _AnalyticsHorizontalSwipeBlocker({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Consume horizontal drags so embedded charts do not bubble them upward.
      onHorizontalDragStart: (_) {},
      onHorizontalDragUpdate: (_) {},
      onHorizontalDragEnd: (_) {},
      child: child,
    );
  }
}

class _AnalyticsSwipePager extends StatefulWidget {
  final double height;
  final Object recenterKey;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final IndexedWidgetBuilder itemBuilder;

  const _AnalyticsSwipePager({
    required this.height,
    required this.recenterKey,
    this.onPrevious,
    this.onNext,
    required this.itemBuilder,
  });

  @override
  State<_AnalyticsSwipePager> createState() => _AnalyticsSwipePagerState();
}

class _AnalyticsSwipePagerState extends State<_AnalyticsSwipePager> {
  late final PageController _pageController;
  bool _isRecenteringPage = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
  }

  @override
  void didUpdateWidget(covariant _AnalyticsSwipePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recenterKey != widget.recenterKey &&
        _pageController.hasClients &&
        (_pageController.page?.round() ?? 1) != 1) {
      _pageController.jumpToPage(1);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _commitPageChange(int page) {
    if (_isRecenteringPage || page == 1) return;

    setState(() => _isRecenteringPage = true);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(1);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _isRecenteringPage = false);
    });

    if (page == 0) {
      widget.onPrevious?.call();
    } else {
      widget.onNext?.call();
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_isRecenteringPage || notification.depth != 0) return false;
    if (notification is! ScrollEndNotification) return false;

    final metrics = notification.metrics;
    if (metrics is! PageMetrics) return false;

    final page = metrics.page?.round() ?? 1;
    _commitPageChange(page);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: widget.height,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: PageView.builder(
            controller: _pageController,
            itemCount: 3,
            physics: const PageScrollPhysics(),
            itemBuilder: widget.itemBuilder,
          ),
        ),
      ),
    );
  }
}

class _AnalyticsChartEmptyState extends StatelessWidget {
  final String message;
  final double height;

  const _AnalyticsChartEmptyState({
    required this.message,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          context.l10nText(message),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _AnalyticsBottomSheetOption extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _AnalyticsBottomSheetOption({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primaryLight.withValues(alpha: 0.12)
          : AppColors.surfaceColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10nText(title),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  AppIcons.check_rounded,
                  color: AppColors.primaryLight,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _AnalyticsLegendDot({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          context.l10nText(label),
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _AnalyticsWeekdayHeader extends StatelessWidget {
  const _AnalyticsWeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final labels = _analyticsWeekdayLabels(context, short: true);
    return Row(
      children: labels
          .map(
            (label) => Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _AnalyticsExpenseBubbleCard extends StatelessWidget {
  static const double _chartMinHeight = 210.0;
  static const double _chartEdgePadding = 10.0;
  static const double _bubbleMinDiameter = 42.0;
  static const double _bubbleMaxDiameter = 136.0;
  static const List<Offset> _defaultOrbitOffsets = <Offset>[
    Offset(-36, 86),
    Offset(86, 72),
    Offset(-102, -8),
    Offset(8, -96),
    Offset(102, -6),
    Offset(-72, -78),
    Offset(-104, 42),
  ];

  final _AnalyticsCategoryChartPage currentPage;
  final _AnalyticsCategoryChartPage? previousPage;
  final _AnalyticsCategoryChartPage? nextPage;
  final bool showIncome;
  final bool usesCustomDateRange;
  final VoidCallback? onNavigateToOlderPeriod;
  final VoidCallback? onNavigateToNewerPeriod;
  final int activeFilterCount;
  final VoidCallback? onOpenFilterSheet;
  final VoidCallback? onChartPickerTap;
  final ValueChanged<_AnalyticsHeatmapMode>? onFlowModeChanged;

  const _AnalyticsExpenseBubbleCard({
    required this.currentPage,
    this.previousPage,
    this.nextPage,
    this.showIncome = false,
    this.usesCustomDateRange = false,
    this.onNavigateToOlderPeriod,
    this.onNavigateToNewerPeriod,
    this.activeFilterCount = 0,
    this.onOpenFilterSheet,
    this.onChartPickerTap,
    this.onFlowModeChanged,
  });

  String _emptyLabel() {
    return showIncome
        ? usesCustomDateRange
            ? 'No categorized income for this range.'
            : 'No categorized income this month.'
        : usesCustomDateRange
            ? 'No categorized expenses for this range.'
            : 'No categorized expenses this month.';
  }

  double _legendHeight(int categoryCount) {
    if (categoryCount <= 0) return 0;
    final rowCount = (categoryCount / 2).ceil();
    return (rowCount * 22) + ((rowCount - 1) * 8);
  }

  double _pageHeight(_AnalyticsCategoryChartPage page) {
    final categories = page.snapshot.categories;
    if (categories.isEmpty) return 200;

    final total =
        categories.fold<double>(0.0, (sum, item) => sum + item.amount);
    final bubbleNodes = _buildBubbleNodes(categories: categories, total: total);
    final bubbleChartExtents = _bubbleChartExtents(bubbleNodes);
    final bubbleChartHeight = _bubbleChartHeight(bubbleChartExtents);

    return 30 + bubbleChartHeight + 8 + _legendHeight(categories.length);
  }

  Widget _buildPage(BuildContext context, _AnalyticsCategoryChartPage page) {
    final categories = page.snapshot.categories;
    final total =
        categories.fold<double>(0.0, (sum, item) => sum + item.amount);
    final bubbleNodes = _buildBubbleNodes(categories: categories, total: total);
    final bubbleChartExtents = _bubbleChartExtents(bubbleNodes);
    final bubbleChartHeight = _bubbleChartHeight(bubbleChartExtents);

    return Column(
      key: ValueKey<String>(
        'bubble-page-${showIncome ? 'income' : 'expense'}-${page.periodLabel}',
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          page.periodLabel,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        if (categories.isEmpty)
          _AnalyticsChartEmptyState(message: _emptyLabel(), height: 170)
        else
          SizedBox(
            height: bubbleChartHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final chartCenter = _bubbleChartCenter(
                  extents: bubbleChartExtents,
                  chartWidth: constraints.maxWidth,
                  chartHeight: bubbleChartHeight,
                );
                return Stack(
                  children: [
                    for (final bubble in bubbleNodes)
                      _buildBubble(
                        context: context,
                        chartCenter: chartCenter,
                        bubble: bubble,
                      ),
                  ],
                );
              },
            ),
          ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._buildLegendRows(context, categories),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPager = previousPage != null && nextPage != null;
    final previous = previousPage ?? currentPage;
    final next = nextPage ?? currentPage;
    final viewportHeight = math.max(
      _pageHeight(previous),
      math.max(_pageHeight(currentPage), _pageHeight(next)),
    );

    final child = Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AnalyticsPrimaryChartHeader(
            chartLabel: 'Bubble Chart',
            headline: '',
            supportingText: '',
            activeFilterCount: activeFilterCount,
            onOpenFilterSheet: onOpenFilterSheet,
            onChartPickerTap: onChartPickerTap,
            details: _AnalyticsFlowModeToggle(
              showIncome: showIncome,
              onChanged: onFlowModeChanged ?? (_) {},
            ),
          ),
          const SizedBox(height: 10),
          if (!hasPager)
            _buildPage(context, currentPage)
          else
            _AnalyticsSwipePager(
              height: viewportHeight,
              recenterKey: Object.hash(
                showIncome,
                currentPage.periodLabel,
                previous.periodLabel,
                next.periodLabel,
              ),
              onPrevious: onNavigateToOlderPeriod,
              onNext: onNavigateToNewerPeriod,
              itemBuilder: (context, index) {
                final page = index == 0
                    ? previous
                    : index == 1
                        ? currentPage
                        : next;
                return _buildPage(context, page);
              },
            ),
        ],
      ),
    );

    return hasPager ? child : _AnalyticsHorizontalSwipeBlocker(child: child);
  }

  List<Widget> _buildLegendRows(
    BuildContext context,
    List<_AnalyticsCategoryStat> categories,
  ) {
    final rows = <Widget>[];
    for (int i = 0; i < categories.length; i += 2) {
      final left = categories[i];
      final right = i + 1 < categories.length ? categories[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < categories.length ? 8 : 0),
          child: Row(
            children: [
              Expanded(child: _AnalyticsLegendAmountItem(stat: left)),
              const SizedBox(width: 10),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : _AnalyticsLegendAmountItem(stat: right),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  List<_AnalyticsBubbleNode> _buildBubbleNodes({
    required List<_AnalyticsCategoryStat> categories,
    required double total,
  }) {
    if (categories.isEmpty) return const <_AnalyticsBubbleNode>[];

    final bubbles = <_AnalyticsBubbleNode>[];
    final centerStat = categories.first;
    final centerPercent = total > 0 ? (centerStat.amount / total) * 100 : 0.0;
    final centerDiameter = _bubbleDiameter(centerPercent);
    bubbles.add(
      _AnalyticsBubbleNode(
        stat: centerStat,
        percent: centerPercent,
        diameter: centerDiameter,
        offset: Offset.zero,
        isCenter: true,
      ),
    );

    final outerOffsets = _orbitOffsetsForCount(categories.length - 1);
    final orbitScale = (centerDiameter / 128.0).clamp(0.84, 1.08);

    for (int i = 1; i < categories.length; i++) {
      final stat = categories[i];
      final percent = total > 0 ? (stat.amount / total) * 100 : 0.0;
      final diameter = _bubbleDiameter(percent);
      final baseOffset = outerOffsets[i - 1];
      final radiusAdjustment = (diameter - _bubbleMinDiameter) / 2;
      final offset = Offset(
        (baseOffset.dx * orbitScale) +
            (baseOffset.dx == 0 ? 0 : baseOffset.dx.sign * radiusAdjustment),
        (baseOffset.dy * orbitScale) +
            (baseOffset.dy == 0 ? 0 : baseOffset.dy.sign * radiusAdjustment),
      );

      bubbles.add(
        _AnalyticsBubbleNode(
          stat: stat,
          percent: percent,
          diameter: diameter,
          offset: offset,
        ),
      );
    }

    return bubbles;
  }

  List<Offset> _orbitOffsetsForCount(int outerCount) {
    switch (outerCount) {
      case 0:
        return const <Offset>[];
      case 1:
        return const <Offset>[Offset(0, -96)];
      case 2:
        return const <Offset>[
          Offset(-78, -54),
          Offset(78, -54),
        ];
      case 3:
        return const <Offset>[
          Offset(-96, -10),
          Offset(0, -96),
          Offset(88, 70),
        ];
      case 4:
        return const <Offset>[
          Offset(-34, 86),
          Offset(86, 72),
          Offset(-96, -10),
          Offset(0, -96),
        ];
      case 5:
        return const <Offset>[
          Offset(-34, 86),
          Offset(86, 72),
          Offset(-102, -8),
          Offset(8, -96),
          Offset(102, -6),
        ];
      default:
        return _defaultOrbitOffsets;
    }
  }

  _BubbleChartExtents _bubbleChartExtents(List<_AnalyticsBubbleNode> bubbles) {
    if (bubbles.isEmpty) {
      return const _BubbleChartExtents(
        minX: 0,
        maxX: 0,
        minY: 0,
        maxY: 0,
      );
    }

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final bubble in bubbles) {
      final radius = bubble.diameter / 2;
      minX = math.min(minX, bubble.offset.dx - radius);
      maxX = math.max(maxX, bubble.offset.dx + radius);
      minY = math.min(minY, bubble.offset.dy - radius);
      maxY = math.max(maxY, bubble.offset.dy + radius);
    }

    return _BubbleChartExtents(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );
  }

  double _bubbleChartHeight(_BubbleChartExtents extents) {
    return math.max(_chartMinHeight, extents.height + (_chartEdgePadding * 2));
  }

  Offset _bubbleChartCenter({
    required _BubbleChartExtents extents,
    required double chartWidth,
    required double chartHeight,
  }) {
    final leftInset = math.max(0.0, (chartWidth - extents.width) / 2);
    final topInset = _chartEdgePadding +
        math.max(
          0.0,
          (chartHeight - extents.height - (_chartEdgePadding * 2)) / 2,
        );
    return Offset(
      leftInset - extents.minX,
      topInset - extents.minY,
    );
  }

  Widget _buildBubble({
    required BuildContext context,
    required Offset chartCenter,
    required _AnalyticsBubbleNode bubble,
  }) {
    final size = bubble.diameter;
    final radius = size / 2;
    final bubbleCenter = chartCenter + bubble.offset;
    final tintedFill =
        bubble.stat.color.withValues(alpha: bubble.isCenter ? 0.1 : 0.14);
    final tintedBorder =
        bubble.stat.color.withValues(alpha: bubble.isCenter ? 0.28 : 0.5);
    final fillColor = bubble.isCenter
        ? Color.lerp(AppColors.mutedFill(context), tintedFill, 0.35) ??
            AppColors.mutedFill(context)
        : tintedFill;
    final borderColor = bubble.isCenter
        ? Color.lerp(AppColors.borderColor(context), tintedBorder, 0.4) ??
            AppColors.borderColor(context)
        : tintedBorder;
    final textColor =
        bubble.isCenter ? AppColors.textPrimary(context) : bubble.stat.color;
    final fontSize = bubble.isCenter
        ? (size * 0.24).clamp(24.0, 34.0).toDouble()
        : (size * 0.24).clamp(12.0, 18.0).toDouble();

    return Positioned(
      left: bubbleCenter.dx - radius,
      top: bubbleCenter.dy - radius,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(color: borderColor),
        ),
        alignment: Alignment.center,
        child: Text(
          '${bubble.percent.round()}%',
          style: TextStyle(
            color: textColor,
            fontWeight: bubble.isCenter ? FontWeight.w800 : FontWeight.w700,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }

  double _bubbleDiameter(double percent) {
    final ratio = (percent / 100).clamp(0.0, 1.0);
    final easedRatio = math.sqrt(ratio);
    return _bubbleMinDiameter +
        ((_bubbleMaxDiameter - _bubbleMinDiameter) * easedRatio);
  }
}

class _AnalyticsBubbleNode {
  final _AnalyticsCategoryStat stat;
  final double percent;
  final double diameter;
  final Offset offset;
  final bool isCenter;

  const _AnalyticsBubbleNode({
    required this.stat,
    required this.percent,
    required this.diameter,
    required this.offset,
    this.isCenter = false,
  });
}

class _BubbleChartExtents {
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  const _BubbleChartExtents({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  double get width => maxX - minX;
  double get height => maxY - minY;
}

class _AnalyticsLegendAmountItem extends StatelessWidget {
  final _AnalyticsCategoryStat stat;

  const _AnalyticsLegendAmountItem({
    required this.stat,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: stat.color,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            context.l10nText(stat.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _formatLocalizedEtb(context, stat.amount),
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

Widget _buildAnalyticsTrendBottomAxisTitle(
  BuildContext context,
  double value,
  TitleMeta meta, {
  required _AnalyticsLineChartPeriod period,
  required List<DateTime> bucketDates,
}) {
  if ((value - value.roundToDouble()).abs() > 0.001) {
    return const SizedBox.shrink();
  }

  final index = value.toInt();
  if (index < 0 || index >= bucketDates.length) return const SizedBox.shrink();

  final labelStride = switch (period) {
    _AnalyticsLineChartPeriod.weekly => 1,
    _AnalyticsLineChartPeriod.monthly => 5,
    _AnalyticsLineChartPeriod.yearly => 3,
  };
  final shouldShow =
      index == 0 || index == bucketDates.length - 1 || index % labelStride == 0;
  if (!shouldShow) return const SizedBox.shrink();

  final isEC = Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
      AppCalendarOption.ethiopian;
  String label;
  if (isEC) {
    final ec = Kenat.fromGregorian(bucketDates[index].year,
            bucketDates[index].month, bucketDates[index].day)
        .getEthiopian();
    final monthShort =
        _formatEthiopianMonthNameForContext(ec['month']!, context);
    label = period == _AnalyticsLineChartPeriod.yearly
        ? monthShort
        : '$monthShort ${ec['day']}';
  } else {
    label = period == _AnalyticsLineChartPeriod.yearly
        ? AppDateFormat.monthShort(bucketDates[index], context: context)
        : AppDateFormat.monthDay(bucketDates[index], context: context);
  }

  return SideTitleWidget(
    axisSide: meta.axisSide,
    child: Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

Widget _buildAnalyticsTrendValueAxisTitle(
  BuildContext context,
  double value,
  TitleMeta meta,
) {
  return SideTitleWidget(
    axisSide: meta.axisSide,
    child: Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Text(
        value.abs() < 0.001 ? '0' : _formatEtbAbbrev(value),
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

double _resolveAnalyticsTrendChartMax(double maxValue) {
  if (maxValue <= 0) return 100.0;

  final roughStep = maxValue / 4;
  final magnitude =
      math.pow(10, (math.log(roughStep) / math.ln10).floor()).toDouble();
  final normalized = roughStep / magnitude;

  double niceNormalized;
  if (normalized <= 1) {
    niceNormalized = 1;
  } else if (normalized <= 2) {
    niceNormalized = 2;
  } else if (normalized <= 2.5) {
    niceNormalized = 2.5;
  } else if (normalized <= 5) {
    niceNormalized = 5;
  } else {
    niceNormalized = 10;
  }

  final step = niceNormalized * magnitude;
  return step * 4;
}

String _formatAnalyticsDateRange(DateTime start, DateTime end,
    {BuildContext? context}) {
  if (context != null) {
    try {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        final ecStart = Kenat.fromGregorian(start.year, start.month, start.day)
            .getEthiopian();
        final ecEnd =
            Kenat.fromGregorian(end.year, end.month, end.day).getEthiopian();
        final startMonth =
            _formatEthiopianMonthNameForContext(ecStart['month']!, context);
        final endMonth =
            _formatEthiopianMonthNameForContext(ecEnd['month']!, context);
        if (ecStart['year'] == ecEnd['year']) {
          if (ecStart['month'] == ecEnd['month']) {
            return '$startMonth ${ecStart['day']} - ${ecEnd['day']}, ${ecEnd['year']}';
          }
          return '$startMonth ${ecStart['day']} - $endMonth ${ecEnd['day']}, ${ecEnd['year']}';
        }
        return '$startMonth ${ecStart['day']}, ${ecStart['year']} - $endMonth ${ecEnd['day']}, ${ecEnd['year']}';
      }
    } catch (_) {}
  }

  if (start.year == end.year) {
    if (start.month == end.month) {
      return '${AppDateFormat.monthDay(start, context: context)} - ${end.day}, ${end.year}';
    }
    return '${AppDateFormat.monthDay(start, context: context)} - ${AppDateFormat.monthDayYear(end, context: context)}';
  }
  return '${AppDateFormat.monthDayYear(start, context: context)} - ${AppDateFormat.monthDayYear(end, context: context)}';
}

DateTime _shiftAnalyticsLineAnchorDate(
  DateTime anchor,
  _AnalyticsLineChartPeriod period,
  int periodOffset, {
  BuildContext? context,
}) {
  try {
    if (context != null) {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        final ec = Kenat.fromGregorian(anchor.year, anchor.month, anchor.day)
            .getEthiopian();
        var y = ec['year']!;
        var m = ec['month']!;
        switch (period) {
          case _AnalyticsLineChartPeriod.weekly:
            return anchor.add(Duration(days: periodOffset * 7));
          case _AnalyticsLineChartPeriod.monthly:
            m += periodOffset;
            while (m > 13) {
              m -= 13;
              y++;
            }
            while (m < 1) {
              m += 13;
              y--;
            }
            final gc = Kenat.fromEthiopian(y, m, 1).getGregorian();
            return DateTime(gc['year']!, gc['month']!, gc['day']!);
          case _AnalyticsLineChartPeriod.yearly:
            y += periodOffset;
            final gc = Kenat.fromEthiopian(y, m, 1).getGregorian();
            return DateTime(gc['year']!, gc['month']!, gc['day']!);
        }
      }
    }
  } catch (_) {}

  switch (period) {
    case _AnalyticsLineChartPeriod.weekly:
      return DateTime(
          anchor.year, anchor.month, anchor.day + (periodOffset * 7));
    case _AnalyticsLineChartPeriod.monthly:
      return DateTime(anchor.year, anchor.month + periodOffset, 1);
    case _AnalyticsLineChartPeriod.yearly:
      return DateTime(anchor.year + periodOffset, anchor.month, 1);
  }
}

DateTime _shiftAnalyticsBarAnchorDate(
  DateTime anchor,
  _AnalyticsBarChartPeriod period,
  int periodOffset, {
  BuildContext? context,
}) {
  try {
    if (context != null) {
      final isEC =
          Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
              AppCalendarOption.ethiopian;
      if (isEC) {
        final ec = Kenat.fromGregorian(anchor.year, anchor.month, anchor.day)
            .getEthiopian();
        var y = ec['year']!;
        var m = ec['month']!;
        switch (period) {
          case _AnalyticsBarChartPeriod.weekly:
            return anchor.add(Duration(days: periodOffset * 7));
          case _AnalyticsBarChartPeriod.monthly:
            m += periodOffset;
            while (m > 13) {
              m -= 13;
              y++;
            }
            while (m < 1) {
              m += 13;
              y--;
            }
            final gc = Kenat.fromEthiopian(y, m, 1).getGregorian();
            return DateTime(gc['year']!, gc['month']!, gc['day']!);
          case _AnalyticsBarChartPeriod.yearly:
            y += periodOffset;
            final gc = Kenat.fromEthiopian(y, m, 1).getGregorian();
            return DateTime(gc['year']!, gc['month']!, gc['day']!);
        }
      }
    }
  } catch (_) {}

  switch (period) {
    case _AnalyticsBarChartPeriod.weekly:
      return DateTime(
          anchor.year, anchor.month, anchor.day + (periodOffset * 7));
    case _AnalyticsBarChartPeriod.monthly:
      return DateTime(anchor.year, anchor.month + periodOffset, 1);
    case _AnalyticsBarChartPeriod.yearly:
      return DateTime(anchor.year + periodOffset, anchor.month, 1);
  }
}

class _AnalyticsLineChartCard extends StatelessWidget {
  final TransactionProvider provider;
  final List<Transaction> transactions;
  final _AnalyticsLineChartPeriod period;
  final int periodOffset;
  final ValueChanged<_AnalyticsLineChartPeriod>? onPeriodChanged;
  final VoidCallback? onNavigateToOlderPeriod;
  final VoidCallback? onNavigateToNewerPeriod;
  final int activeFilterCount;
  final VoidCallback? onOpenFilterSheet;
  final VoidCallback? onChartPickerTap;

  const _AnalyticsLineChartCard({
    required this.provider,
    required this.transactions,
    required this.period,
    this.periodOffset = 0,
    this.onPeriodChanged,
    this.onNavigateToOlderPeriod,
    this.onNavigateToNewerPeriod,
    this.activeFilterCount = 0,
    this.onOpenFilterSheet,
    this.onChartPickerTap,
  });

  DateTime _anchorDate() {
    DateTime? latest;
    for (final transaction in transactions) {
      final dt = _parseTransactionTime(transaction.time);
      if (dt == null) continue;
      if (latest == null || dt.isAfter(latest)) {
        latest = dt;
      }
    }

    final anchor = latest ?? DateTime.now();
    return DateTime(anchor.year, anchor.month, anchor.day);
  }

  _AnalyticsLineSeries _buildSeries(
      BuildContext context, int effectivePeriodOffset) {
    final isEC =
        Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
            AppCalendarOption.ethiopian;
    final anchorDate = _shiftAnalyticsLineAnchorDate(
      _anchorDate(),
      period,
      effectivePeriodOffset,
      context: context,
    );

    late final DateTime anchorMonth;
    if (isEC) {
      final ec =
          Kenat.fromGregorian(anchorDate.year, anchorDate.month, anchorDate.day)
              .getEthiopian();
      final gc =
          Kenat.fromEthiopian(ec['year']!, ec['month']!, 1).getGregorian();
      anchorMonth = DateTime(gc['year']!, gc['month']!, gc['day']!);
    } else {
      anchorMonth = DateTime(anchorDate.year, anchorDate.month, 1);
    }

    late final List<DateTime> bucketDates;
    late final List<double> incomeValues;
    late final List<double> expenseValues;
    late final String supportingText;
    late final String rangeLabel;

    if (isEC) {
      final ecAnchor =
          Kenat.fromGregorian(anchorDate.year, anchorDate.month, anchorDate.day)
              .getEthiopian();
      switch (period) {
        case _AnalyticsLineChartPeriod.weekly:
          {
            final grid = MonthGrid({
              'year': ecAnchor['year'],
              'month': ecAnchor['month'],
              'weekStart': 0
            }).generate();
            final List<Map<String, dynamic>?> allDays =
                List<Map<String, dynamic>?>.from(grid['days']);
            // Find the week that contains ecAnchor
            final anchorIdx = allDays.indexWhere(
                (d) => d != null && d['ethiopian']['day'] == ecAnchor['day']);
            final startIdx = (anchorIdx ~/ 7) * 7;
            final weekDays = allDays.sublist(startIdx, startIdx + 7);
            bucketDates = weekDays.map((d) {
              if (d == null) return DateTime(2000); // Placeholder
              final g = d['gregorian'];
              return DateTime(g['year'], g['month'], g['day']);
            }).toList();

            final validDates = bucketDates.where((d) => d.year > 2000).toList();
            incomeValues = List<double>.filled(7, 0.0);
            expenseValues = List<double>.filled(7, 0.0);
            supportingText = _formatAnalyticsDateRange(
                validDates.first, validDates.last,
                context: context);
            final ecStart = Kenat.fromGregorian(validDates.first.year,
                    validDates.first.month, validDates.first.day)
                .getEthiopian();
            rangeLabel =
                '${context.l10nText('Week of')} ${_formatEthiopianMonthNameForContext(ecStart['month']!, context)} ${ecStart['day']}';
            break;
          }
        case _AnalyticsLineChartPeriod.monthly:
          {
            final gcStartMap =
                Kenat.fromEthiopian(ecAnchor['year']!, ecAnchor['month']!, 1)
                    .getGregorian();
            final startDate = DateTime(
                gcStartMap['year']!, gcStartMap['month']!, gcStartMap['day']!);
            final dayCount = EthiopianCalendarUtils.getEthiopianDaysInMonth(
                ecAnchor['year']!, ecAnchor['month']!);
            bucketDates = List<DateTime>.generate(dayCount, (index) {
              final g = Kenat.fromEthiopian(
                      ecAnchor['year']!, ecAnchor['month']!, index + 1)
                  .getGregorian();
              return DateTime(g['year']!, g['month']!, g['day']!);
            });
            incomeValues = List<double>.filled(dayCount, 0.0);
            expenseValues = List<double>.filled(dayCount, 0.0);
            supportingText =
                '${_formatEthiopianMonthNameForContext(ecAnchor['month']!, context)} ${ecAnchor['year']}';
            rangeLabel = supportingText;
            break;
          }
        case _AnalyticsLineChartPeriod.yearly:
          {
            bucketDates = List<DateTime>.generate(13, (index) {
              final g = Kenat.fromEthiopian(ecAnchor['year']!, index + 1, 1)
                  .getGregorian();
              return DateTime(g['year']!, g['month']!, g['day']!);
            });
            incomeValues = List<double>.filled(13, 0.0);
            expenseValues = List<double>.filled(13, 0.0);
            supportingText =
                '${_formatEthiopianMonthRangeForContext(context)} ${ecAnchor['year']}';
            rangeLabel = '${ecAnchor['year']}';
            break;
          }
      }
    } else {
      switch (period) {
        case _AnalyticsLineChartPeriod.weekly:
          {
            final startDate = anchorDate.subtract(
              Duration(days: anchorDate.weekday - DateTime.monday),
            );
            final endDate = startDate.add(const Duration(days: 6));
            bucketDates = List<DateTime>.generate(
              7,
              (index) => startDate.add(Duration(days: index)),
              growable: false,
            );
            incomeValues = List<double>.filled(7, 0.0);
            expenseValues = List<double>.filled(7, 0.0);
            supportingText =
                _formatAnalyticsDateRange(startDate, endDate, context: context);
            rangeLabel =
                '${context.l10nText('Week of')} ${AppDateFormat.monthDay(startDate, context: context)}';
            break;
          }
        case _AnalyticsLineChartPeriod.monthly:
          {
            final startDate = DateTime(anchorDate.year, anchorDate.month, 1);
            final dayCount =
                DateTime(anchorDate.year, anchorDate.month + 1, 0).day;
            bucketDates = List<DateTime>.generate(
              dayCount,
              (index) => startDate.add(Duration(days: index)),
              growable: false,
            );
            incomeValues = List<double>.filled(dayCount, 0.0);
            expenseValues = List<double>.filled(dayCount, 0.0);
            supportingText =
                AppDateFormat.monthYear(startDate, context: context);
            rangeLabel =
                AppDateFormat.shortMonthYear(startDate, context: context);
            break;
          }
        case _AnalyticsLineChartPeriod.yearly:
          {
            final startMonth = DateTime(anchorDate.year, 1, 1);
            bucketDates = List<DateTime>.generate(
              12,
              (index) => DateTime(startMonth.year, startMonth.month + index, 1),
              growable: false,
            );
            incomeValues = List<double>.filled(12, 0.0);
            expenseValues = List<double>.filled(12, 0.0);
            supportingText = 'Jan - Dec ${startMonth.year}';
            rangeLabel = '${startMonth.year}';
            break;
          }
      }
    }

    for (final transaction in transactions) {
      final dt = _parseTransactionTime(transaction.time);
      if (dt == null) continue;
      if (provider.isSelfTransfer(transaction)) continue;

      final category = provider.getCategoryById(transaction.categoryId);
      if (category?.uncategorized == true) continue;

      final amount = transaction.amount.abs();
      if (amount <= 0.001) continue;

      int? bucketIndex;
      if (isEC) {
        final ecDt =
            Kenat.fromGregorian(dt.year, dt.month, dt.day).getEthiopian();
        switch (period) {
          case _AnalyticsLineChartPeriod.weekly:
            {
              final dateOnly = DateTime(dt.year, dt.month, dt.day);
              bucketIndex = bucketDates.indexWhere((d) =>
                  d.year == dateOnly.year &&
                  d.month == dateOnly.month &&
                  d.day == dateOnly.day);
              break;
            }
          case _AnalyticsLineChartPeriod.monthly:
            {
              final ecAnchor = Kenat.fromGregorian(bucketDates.first.year,
                      bucketDates.first.month, bucketDates.first.day)
                  .getEthiopian();
              if (ecDt['year'] == ecAnchor['year'] &&
                  ecDt['month'] == ecAnchor['month']) {
                bucketIndex = ecDt['day']! - 1;
              }
              break;
            }
          case _AnalyticsLineChartPeriod.yearly:
            {
              final ecAnchor = Kenat.fromGregorian(bucketDates.first.year,
                      bucketDates.first.month, bucketDates.first.day)
                  .getEthiopian();
              if (ecDt['year'] == ecAnchor['year']) {
                bucketIndex = ecDt['month']! - 1;
              }
              break;
            }
        }
      } else {
        switch (period) {
          case _AnalyticsLineChartPeriod.weekly:
            {
              final dateOnly = DateTime(dt.year, dt.month, dt.day);
              final startDate = bucketDates.first;
              final endDate = bucketDates.last;
              if (dateOnly.isBefore(startDate) || dateOnly.isAfter(endDate)) {
                continue;
              }
              bucketIndex = dateOnly.difference(startDate).inDays;
              break;
            }
          case _AnalyticsLineChartPeriod.monthly:
            {
              final dateOnly = DateTime(dt.year, dt.month, dt.day);
              final startDate = bucketDates.first;
              final endDate = bucketDates.last;
              if (dateOnly.isBefore(startDate) || dateOnly.isAfter(endDate)) {
                continue;
              }
              bucketIndex = dateOnly.difference(startDate).inDays;
              break;
            }
          case _AnalyticsLineChartPeriod.yearly:
            {
              final monthDate = DateTime(dt.year, dt.month, 1);
              final startMonth = bucketDates.first;
              final endMonth = bucketDates.last;
              if (monthDate.isBefore(startMonth) ||
                  monthDate.isAfter(endMonth)) {
                continue;
              }
              bucketIndex = (monthDate.year - startMonth.year) * 12 +
                  monthDate.month -
                  startMonth.month;
              break;
            }
        }
      }

      if (bucketIndex == null ||
          bucketIndex < 0 ||
          bucketIndex >= bucketDates.length) continue;

      if (transaction.type == 'CREDIT') {
        incomeValues[bucketIndex] += amount;
      } else if (transaction.type == 'DEBIT') {
        expenseValues[bucketIndex] += amount;
      }
    }

    final totalIncome =
        incomeValues.fold<double>(0.0, (sum, value) => sum + value);
    final totalExpense =
        expenseValues.fold<double>(0.0, (sum, value) => sum + value);
    final maxIncome = incomeValues.fold<double>(0.0, math.max);
    final maxExpense = expenseValues.fold<double>(0.0, math.max);
    final maxValue = math.max(maxIncome, maxExpense);

    return _AnalyticsLineSeries(
      period: period,
      bucketDates: bucketDates,
      incomeValues: incomeValues,
      expenseValues: expenseValues,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      maxValue: maxValue,
      supportingText: supportingText,
      rangeLabel: rangeLabel,
      emptyMessage:
          '${context.l10nText('No income or expense data for')} $rangeLabel.',
    );
  }

  double _pageHeight(_AnalyticsLineSeries series) {
    return series.maxValue > 0.001 ? 252 : 248;
  }

  Widget _buildPage(BuildContext context, _AnalyticsLineSeries series) {
    final leftAxisReservedWidth =
        period == _AnalyticsLineChartPeriod.yearly ? 52.0 : 36.0;
    const rightAxisReservedWidth = 12.0;
    final hasData = series.maxValue > 0.001;
    final chartMax = _resolveAnalyticsTrendChartMax(series.maxValue);
    final interval = chartMax / 4;
    final pointCount = series.bucketDates.length;

    return Column(
      key: ValueKey<String>('line-page-${period.name}-${series.rangeLabel}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          series.supportingText,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        if (!hasData)
          _AnalyticsChartEmptyState(
            message: series.emptyMessage,
          )
        else ...[
          SizedBox(
            height: 184,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: pointCount <= 1 ? 1 : (pointCount - 1).toDouble(),
                minY: 0,
                maxY: chartMax,
                clipData: const FlClipData.all(),
                lineTouchData: const LineTouchData(enabled: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color:
                        AppColors.borderColor(context).withValues(alpha: 0.7),
                    strokeWidth: 0.9,
                    dashArray: const [3, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: rightAxisReservedWidth,
                      getTitlesWidget: (value, meta) => const SizedBox.shrink(),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 38,
                      getTitlesWidget: (value, meta) =>
                          _buildAnalyticsTrendBottomAxisTitle(
                        context,
                        value,
                        meta,
                        period: series.period,
                        bucketDates: series.bucketDates,
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: interval,
                      reservedSize: leftAxisReservedWidth,
                      getTitlesWidget: (value, meta) =>
                          _buildAnalyticsTrendValueAxisTitle(
                        context,
                        value,
                        meta,
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.borderColor(context),
                      width: 1,
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (int index = 0; index < pointCount; index++)
                        FlSpot(index.toDouble(), series.incomeValues[index]),
                    ],
                    isCurved: true,
                    curveSmoothness: 0.32,
                    preventCurveOverShooting: true,
                    color: AppColors.incomeSuccess,
                    barWidth: 2.2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                  LineChartBarData(
                    spots: [
                      for (int index = 0; index < pointCount; index++)
                        FlSpot(index.toDouble(), series.expenseValues[index]),
                    ],
                    isCurved: true,
                    curveSmoothness: 0.32,
                    preventCurveOverShooting: true,
                    color: AppColors.red,
                    barWidth: 2.2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.only(left: leftAxisReservedWidth),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Text(
                  '+ ${_formatLocalizedEtb(context, series.totalIncome)}',
                  style: TextStyle(
                    color: AppColors.incomeSuccess,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '- ${_formatLocalizedEtb(context, series.totalExpense)}',
                  style: TextStyle(
                    color: AppColors.red,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${context.l10nText('Peak')}: ${_formatLocalizedEtb(context, series.maxValue)}',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  series.rangeLabel,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final previousSeries = _buildSeries(context, periodOffset - 1);
    final currentSeries = _buildSeries(context, periodOffset);
    final hasNewerPeriod = periodOffset < 0;
    final nextSeries = hasNewerPeriod
        ? _buildSeries(context, periodOffset + 1)
        : currentSeries;
    final viewportHeight = math.max(
      _pageHeight(previousSeries),
      math.max(_pageHeight(currentSeries), _pageHeight(nextSeries)),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AnalyticsPrimaryChartHeader(
            chartLabel: 'Line Chart',
            headline: period == _AnalyticsLineChartPeriod.weekly
                ? 'Weekly Spending'
                : period == _AnalyticsLineChartPeriod.monthly
                    ? 'Monthly Spending'
                    : 'Yearly Spending',
            supportingText: currentSeries.supportingText,
            activeFilterCount: activeFilterCount,
            onOpenFilterSheet: onOpenFilterSheet,
            onChartPickerTap: onChartPickerTap,
            details: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10nText('Income vs Expense'),
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _AnalyticsLinePeriodToggle(
                      selectedPeriod: period,
                      onChanged: onPeriodChanged ?? (_) {},
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _AnalyticsSwipePager(
                  height: viewportHeight,
                  recenterKey:
                      Object.hash(period, periodOffset, transactions.length),
                  onPrevious: onNavigateToOlderPeriod,
                  onNext: hasNewerPeriod ? onNavigateToNewerPeriod : null,
                  itemBuilder: (context, index) {
                    final series = index == 0
                        ? previousSeries
                        : index == 1
                            ? currentSeries
                            : nextSeries;
                    return _buildPage(context, series);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsLineSeries {
  final _AnalyticsLineChartPeriod period;
  final List<DateTime> bucketDates;
  final List<double> incomeValues;
  final List<double> expenseValues;
  final double totalIncome;
  final double totalExpense;
  final double maxValue;
  final String supportingText;
  final String rangeLabel;
  final String emptyMessage;

  const _AnalyticsLineSeries({
    required this.period,
    required this.bucketDates,
    required this.incomeValues,
    required this.expenseValues,
    required this.totalIncome,
    required this.totalExpense,
    required this.maxValue,
    required this.supportingText,
    required this.rangeLabel,
    required this.emptyMessage,
  });
}

class _AnalyticsLinePeriodToggle extends StatelessWidget {
  final _AnalyticsLineChartPeriod selectedPeriod;
  final ValueChanged<_AnalyticsLineChartPeriod> onChanged;

  const _AnalyticsLinePeriodToggle({
    required this.selectedPeriod,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.mutedFill(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AnalyticsLinePeriodToggleOption(
            label: 'Week',
            selected: selectedPeriod == _AnalyticsLineChartPeriod.weekly,
            onTap: () => onChanged(_AnalyticsLineChartPeriod.weekly),
          ),
          _AnalyticsLinePeriodToggleOption(
            label: 'Month',
            selected: selectedPeriod == _AnalyticsLineChartPeriod.monthly,
            onTap: () => onChanged(_AnalyticsLineChartPeriod.monthly),
          ),
          _AnalyticsLinePeriodToggleOption(
            label: 'Year',
            selected: selectedPeriod == _AnalyticsLineChartPeriod.yearly,
            onTap: () => onChanged(_AnalyticsLineChartPeriod.yearly),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsLinePeriodToggleOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AnalyticsLinePeriodToggleOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardColor(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          context.l10nText(label),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected
                ? AppColors.textPrimary(context)
                : AppColors.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

class _AnalyticsBarChartCard extends StatelessWidget {
  final TransactionProvider provider;
  final List<Transaction> transactions;
  final _AnalyticsHeatmapFilter filter;
  final int periodOffset;
  final VoidCallback? onNavigateToOlderPeriod;
  final VoidCallback? onNavigateToNewerPeriod;
  final int activeFilterCount;
  final VoidCallback? onOpenFilterSheet;
  final VoidCallback? onChartPickerTap;

  const _AnalyticsBarChartCard({
    required this.provider,
    required this.transactions,
    required this.filter,
    this.periodOffset = 0,
    this.onNavigateToOlderPeriod,
    this.onNavigateToNewerPeriod,
    this.activeFilterCount = 0,
    this.onOpenFilterSheet,
    this.onChartPickerTap,
  });

  _AnalyticsHeatmapMode get _effectiveMode =>
      filter.mode == _AnalyticsHeatmapMode.income
          ? _AnalyticsHeatmapMode.income
          : _AnalyticsHeatmapMode.expense;

  String _periodTitle() {
    switch (filter.barPeriod) {
      case _AnalyticsBarChartPeriod.weekly:
        return 'Weekly';
      case _AnalyticsBarChartPeriod.monthly:
        return 'Monthly';
      case _AnalyticsBarChartPeriod.yearly:
        return 'Yearly';
    }
  }

  DateTime _anchorDate() {
    DateTime? latest;
    for (final transaction in transactions) {
      final dt = _parseTransactionTime(transaction.time);
      if (dt == null) continue;
      if (latest == null || dt.isAfter(latest)) {
        latest = dt;
      }
    }
    return latest ?? DateTime.now();
  }

  Color _categoryColor(int index) {
    const palette = <Color>[
      Color(0xFF8D8B98),
      Color(0xFF6366F1),
      Color(0xFFEC4899),
      Color(0xFF7DD3FC),
      Color(0xFF4D7C0F),
      Color(0xFFF97316),
      Color(0xFFCB85FF),
      Color(0xFF60A5FA),
      Color(0xFFF472B6),
      Color(0xFFF8E16C),
      Color(0xFF6B7280),
      Color(0xFFFB7185),
      Color(0xFF14B8A6),
      Color(0xFF8B5CF6),
      Color(0xFF2DD4BF),
      Color(0xFFEF4444),
    ];
    return palette[index % palette.length];
  }

  double _barWidth() {
    switch (filter.barPeriod) {
      case _AnalyticsBarChartPeriod.weekly:
        return 30;
      case _AnalyticsBarChartPeriod.monthly:
        return 42;
      case _AnalyticsBarChartPeriod.yearly:
        return 18;
    }
  }

  _AnalyticsBarSeries _buildSeries(
      BuildContext context, int effectivePeriodOffset) {
    final isEC =
        Provider.of<ThemeProvider>(context, listen: false).appCalendar ==
            AppCalendarOption.ethiopian;
    final mode = _effectiveMode;
    final anchor = _shiftAnalyticsBarAnchorDate(
      _anchorDate(),
      filter.barPeriod,
      effectivePeriodOffset,
      context: context,
    );
    final yearlyLabelsDefault = List<String>.generate(
      12,
      (index) => AppDateFormat.gregorianMonthName(
        index + 1,
        language: AppDateFormat.languageOf(context),
        abbreviated: true,
      ),
    );
    final isAmharic = AppDateFormat.languageOf(context).storageValue == 'am';
    final weeklyLabels = isEC && isAmharic
        ? [
            DaysOfWeek.amharic[1], // Monday
            DaysOfWeek.amharic[2], // Tuesday
            DaysOfWeek.amharic[3], // Wednesday
            DaysOfWeek.amharic[4], // Thursday
            DaysOfWeek.amharic[5], // Friday
            DaysOfWeek.amharic[6], // Saturday
            DaysOfWeek.amharic[0], // Sunday
          ].map((d) => d.substring(0, d.length >= 3 ? 3 : d.length)).toList()
        : AppDateFormat.weekdayShortEnglishMondayFirst;
    final monthlyLabels = isEC && isAmharic
        ? ['ሳ1', 'ሳ2', 'ሳ3', 'ሳ4', 'ሳ5']
        : ['W1', 'W2', 'W3', 'W4', 'W5'];
    final yearlyLabels = isEC
        ? AppDateFormat.ethiopianMonthNames(
            language: AppDateFormat.languageOf(context),
          )
        : yearlyLabelsDefault;

    final labels = switch (filter.barPeriod) {
      _AnalyticsBarChartPeriod.weekly => weeklyLabels,
      _AnalyticsBarChartPeriod.monthly => monthlyLabels,
      _AnalyticsBarChartPeriod.yearly => yearlyLabels,
    };
    final bucketCount = labels.length;
    final statsByKey = <String, _AnalyticsBarCategoryAccumulator>{};
    final bucketDates = <DateTime>[];

    int? bucketIndexFor(DateTime dt) {
      if (isEC) {
        final ecDt =
            Kenat.fromGregorian(dt.year, dt.month, dt.day).getEthiopian();
        final ecAnchor =
            Kenat.fromGregorian(anchor.year, anchor.month, anchor.day)
                .getEthiopian();
        switch (filter.barPeriod) {
          case _AnalyticsBarChartPeriod.weekly:
            final anchorGC = DateTime(anchor.year, anchor.month, anchor.day);
            final weekStartGC = anchorGC
                .subtract(Duration(days: anchorGC.weekday - DateTime.monday));
            if (dt.isBefore(weekStartGC) ||
                !dt.isBefore(weekStartGC.add(const Duration(days: 7))))
              return null;
            return dt.difference(weekStartGC).inDays;
          case _AnalyticsBarChartPeriod.monthly:
            if (ecDt['year'] == ecAnchor['year'] &&
                ecDt['month'] == ecAnchor['month']) {
              return ((ecDt['day']! - 1) ~/ 7).clamp(0, 4);
            }
            return null;
          case _AnalyticsBarChartPeriod.yearly:
            if (ecDt['year'] == ecAnchor['year']) {
              return ecDt['month']! - 1;
            }
            return null;
        }
      } else {
        final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);
        final weekStart = anchorDay
            .subtract(Duration(days: anchorDay.weekday - DateTime.monday));
        final monthStart = DateTime(anchor.year, anchor.month, 1);
        final nextMonthStart = DateTime(anchor.year, anchor.month + 1, 1);
        final yearStart = DateTime(anchor.year, 1, 1);
        final nextYearStart = DateTime(anchor.year + 1, 1, 1);

        switch (filter.barPeriod) {
          case _AnalyticsBarChartPeriod.weekly:
            if (dt.isBefore(weekStart) ||
                !dt.isBefore(weekStart.add(const Duration(days: 7))))
              return null;
            return dt.difference(weekStart).inDays;
          case _AnalyticsBarChartPeriod.monthly:
            if (dt.isBefore(monthStart) || !dt.isBefore(nextMonthStart))
              return null;
            return ((dt.day - 1) ~/ 7).clamp(0, 4);
          case _AnalyticsBarChartPeriod.yearly:
            if (dt.isBefore(yearStart) || !dt.isBefore(nextYearStart))
              return null;
            return dt.month - 1;
        }
      }
    }

    // Populate bucketDates for helper
    if (filter.barPeriod == _AnalyticsBarChartPeriod.weekly) {
      final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);
      final start = isEC
          ? anchor.subtract(Duration(days: anchor.weekday - DateTime.monday))
          : anchorDay
              .subtract(Duration(days: anchorDay.weekday - DateTime.monday));
      for (int i = 0; i < 7; i++) bucketDates.add(start.add(Duration(days: i)));
    }

    for (final transaction in transactions) {
      final isIncome = transaction.type == 'CREDIT';
      final isExpense = transaction.type == 'DEBIT';
      if (mode == _AnalyticsHeatmapMode.income && !isIncome) continue;
      if (mode == _AnalyticsHeatmapMode.expense && !isExpense) continue;
      if (provider.isSelfTransfer(transaction)) continue;

      final dt = _parseTransactionTime(transaction.time);
      if (dt == null) continue;

      final bucketIndex = bucketIndexFor(dt);
      if (bucketIndex == null) continue;

      final category = transaction.categoryId == null
          ? null
          : provider.getCategoryById(transaction.categoryId!);
      final categoryName = category?.name.trim() ?? '';
      final isOther =
          category == null || category.uncategorized || categoryName.isEmpty;
      final label = isOther ? 'Other' : categoryName;
      final key = isOther ? 'other' : 'category:${category.id}';
      final accumulator = statsByKey.putIfAbsent(
        key,
        () => _AnalyticsBarCategoryAccumulator(
          label: label,
          bucketValues: List<double>.filled(bucketCount, 0.0),
          orderSeed: statsByKey.length,
        ),
      );

      final amount = transaction.amount.abs();
      accumulator.bucketValues[bucketIndex] += amount;
      accumulator.total += amount;
    }

    final sorted = statsByKey.values.toList()
      ..sort((a, b) {
        final totalCompare = b.total.compareTo(a.total);
        if (totalCompare != 0) return totalCompare;
        return a.orderSeed.compareTo(b.orderSeed);
      });

    final categories = <_AnalyticsBarCategorySeries>[];
    for (int index = 0; index < sorted.length; index++) {
      final item = sorted[index];
      categories.add(
        _AnalyticsBarCategorySeries(
          label: item.label,
          total: item.total,
          bucketValues: item.bucketValues,
          color: _categoryColor(index),
        ),
      );
    }

    final totalsByBucket = List<double>.generate(
      bucketCount,
      (index) => categories.fold<double>(
        0.0,
        (sum, category) => sum + category.bucketValues[index],
      ),
    );

    String supportingText;
    if (isEC) {
      final ecAnchor =
          Kenat.fromGregorian(anchor.year, anchor.month, anchor.day)
              .getEthiopian();
      supportingText = switch (filter.barPeriod) {
        _AnalyticsBarChartPeriod.weekly => _formatAnalyticsDateRange(
            bucketDates.first,
            bucketDates.last,
            context: context,
          ),
        _AnalyticsBarChartPeriod.monthly =>
          '${_formatEthiopianMonthNameForContext(ecAnchor['month']!, context)} ${ecAnchor['year']}',
        _AnalyticsBarChartPeriod.yearly =>
          '${_formatEthiopianMonthRangeForContext(context)} ${ecAnchor['year']}',
      };
    } else {
      final monthStart = DateTime(anchor.year, anchor.month, 1);
      supportingText = switch (filter.barPeriod) {
        _AnalyticsBarChartPeriod.weekly => _formatAnalyticsDateRange(
            bucketDates.first,
            bucketDates.last,
            context: context,
          ),
        _AnalyticsBarChartPeriod.monthly =>
          AppDateFormat.monthYear(monthStart, context: context),
        _AnalyticsBarChartPeriod.yearly => '${anchor.year}',
      };
    }

    double totalIncome = 0;
    double totalExpense = 0;
    for (final c in statsByKey.values) {
      if (mode == _AnalyticsHeatmapMode.income)
        totalIncome += c.total;
      else
        totalExpense += c.total;
    }

    final flowLabel =
        mode == _AnalyticsHeatmapMode.income ? 'Income' : 'Expense';
    final periodLabel = supportingText;

    return _AnalyticsBarSeries(
      title:
          '${context.l10nText(_periodTitle())} ${context.l10nText(flowLabel)}',
      supportingText: periodLabel,
      labels: labels,
      categories: categories,
      totalsByBucket: totalsByBucket,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      emptyMessage:
          '${context.l10nText(mode == _AnalyticsHeatmapMode.income ? 'No income activity for' : 'No expense activity for')} $periodLabel.',
    );
  }

  double _pageHeight(_AnalyticsBarSeries series) {
    final hasData = series.totalsByBucket.fold<double>(0.0, math.max) > 0.001;
    // Small safety margin to avoid label/legend clipping on some text scales.
    return hasData ? 362 : 282;
  }

  Widget _buildPage(BuildContext context, _AnalyticsBarSeries series) {
    final maxValue = series.totalsByBucket.fold<double>(0.0, math.max);
    final chartMax = maxValue <= 0 ? 100.0 : math.max(100.0, maxValue * 1.18);
    final interval = math.max(25.0, chartMax / 4);
    final hasData = maxValue > 0.001;

    return Column(
      key: ValueKey<String>(
        'bar-page-${filter.barPeriod.name}-${_effectiveMode.name}-${series.supportingText}',
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          series.title,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          series.supportingText,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        if (!hasData)
          _AnalyticsChartEmptyState(
            message: series.emptyMessage,
          )
        else ...[
          SizedBox(
            height: 208,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                minY: 0,
                maxY: chartMax,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color:
                        AppColors.borderColor(context).withValues(alpha: 0.65),
                    strokeWidth: 0.8,
                    dashArray: const [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= series.labels.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 8,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              series.labels[index],
                              style: TextStyle(
                                color: AppColors.textTertiary(context),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipRoundedRadius: 12,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (group) => AppColors.cardColor(context),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final index = group.x.toInt();
                      return BarTooltipItem(
                        '${series.labels[index]}\n${_formatLocalizedEtb(context, series.totalsByBucket[index])}',
                        TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (int index = 0; index < series.labels.length; index++)
                    _buildAnalyticsBarGroup(
                      index: index,
                      categories: series.categories,
                      width: _barWidth(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 78,
            child: _AnalyticsBarCategoryScroller(
              categories: series.categories,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final previousSeries = _buildSeries(context, periodOffset - 1);
    final currentSeries = _buildSeries(context, periodOffset);
    final hasNewerPeriod = periodOffset < 0;
    final nextSeries = hasNewerPeriod
        ? _buildSeries(context, periodOffset + 1)
        : currentSeries;
    final viewportHeight = math.max(
      _pageHeight(previousSeries),
      math.max(_pageHeight(currentSeries), _pageHeight(nextSeries)),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AnalyticsPrimaryChartHeader(
            chartLabel: 'Bar Chart',
            headline: filter.barPeriod == _AnalyticsBarChartPeriod.weekly
                ? 'Weekly Spending'
                : filter.barPeriod == _AnalyticsBarChartPeriod.monthly
                    ? 'Monthly Spending'
                    : 'Yearly Spending',
            supportingText: currentSeries.supportingText,
            activeFilterCount: activeFilterCount,
            onOpenFilterSheet: onOpenFilterSheet,
            onChartPickerTap: onChartPickerTap,
            details: _AnalyticsSwipePager(
              height: viewportHeight,
              recenterKey: Object.hash(
                filter.barPeriod,
                _effectiveMode,
                periodOffset,
                transactions.length,
              ),
              onPrevious: onNavigateToOlderPeriod,
              onNext: hasNewerPeriod ? onNavigateToNewerPeriod : null,
              itemBuilder: (context, index) {
                final series = index == 0
                    ? previousSeries
                    : index == 1
                        ? currentSeries
                        : nextSeries;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (series != currentSeries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          series.supportingText,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    _buildPage(context, series),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

BarChartGroupData _buildAnalyticsBarGroup({
  required int index,
  required List<_AnalyticsBarCategorySeries> categories,
  required double width,
}) {
  double runningTotal = 0.0;
  final stacks = <BarChartRodStackItem>[];

  for (final category in categories.reversed) {
    final value = category.bucketValues[index];
    if (value <= 0) continue;
    stacks.add(
      BarChartRodStackItem(
        runningTotal,
        runningTotal + value,
        category.color,
      ),
    );
    runningTotal += value;
  }

  return BarChartGroupData(
    x: index,
    barsSpace: 0,
    barRods: [
      BarChartRodData(
        toY: runningTotal,
        width: width,
        color: categories.isEmpty
            ? AppColors.primaryLight
            : categories.first.color,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(6),
        ),
        rodStackItems: stacks,
      ),
    ],
  );
}

class _AnalyticsBarSeries {
  final String title;
  final String supportingText;
  final List<String> labels;
  final List<_AnalyticsBarCategorySeries> categories;
  final List<double> totalsByBucket;
  final double totalIncome;
  final double totalExpense;
  final String emptyMessage;

  const _AnalyticsBarSeries({
    required this.title,
    required this.supportingText,
    required this.labels,
    required this.categories,
    required this.totalsByBucket,
    required this.totalIncome,
    required this.totalExpense,
    required this.emptyMessage,
  });
}

class _AnalyticsBarCategorySeries {
  final String label;
  final double total;
  final List<double> bucketValues;
  final Color color;

  const _AnalyticsBarCategorySeries({
    required this.label,
    required this.total,
    required this.bucketValues,
    required this.color,
  });
}

class _AnalyticsBarCategoryAccumulator {
  final String label;
  final List<double> bucketValues;
  final int orderSeed;
  double total = 0.0;

  _AnalyticsBarCategoryAccumulator({
    required this.label,
    required this.bucketValues,
    required this.orderSeed,
  });
}

class _AnalyticsBarCategoryScroller extends StatelessWidget {
  final List<_AnalyticsBarCategorySeries> categories;

  const _AnalyticsBarCategoryScroller({
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final columns = <Widget>[];
    for (int index = 0; index < categories.length; index += 2) {
      final top = categories[index];
      final bottom =
          index + 1 < categories.length ? categories[index + 1] : null;
      columns.add(
        Padding(
          padding:
              EdgeInsets.only(right: index + 2 < categories.length ? 14 : 0),
          child: SizedBox(
            width: 186,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AnalyticsBarCategoryItem(stat: top),
                const SizedBox(height: 10),
                if (bottom != null)
                  _AnalyticsBarCategoryItem(stat: bottom)
                else
                  const SizedBox(height: 38),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(right: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columns,
      ),
    );
  }
}

class _AnalyticsBarCategoryItem extends StatelessWidget {
  final _AnalyticsBarCategorySeries stat;

  const _AnalyticsBarCategoryItem({
    required this.stat,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: stat.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.l10nText(stat.label),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _formatLocalizedEtb(context, stat.total),
          textAlign: TextAlign.right,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AnalyticsPieChartCard extends StatelessWidget {
  final _AnalyticsCategoryChartPage currentPage;
  final _AnalyticsCategoryChartPage? previousPage;
  final _AnalyticsCategoryChartPage? nextPage;
  final bool showIncome;
  final bool usesCustomDateRange;
  final VoidCallback? onNavigateToOlderPeriod;
  final VoidCallback? onNavigateToNewerPeriod;
  final int activeFilterCount;
  final VoidCallback? onOpenFilterSheet;
  final ValueChanged<_AnalyticsHeatmapMode>? onFlowModeChanged;
  final VoidCallback? onChartPickerTap;

  const _AnalyticsPieChartCard({
    required this.currentPage,
    this.previousPage,
    this.nextPage,
    this.showIncome = false,
    this.usesCustomDateRange = false,
    this.onNavigateToOlderPeriod,
    this.onNavigateToNewerPeriod,
    this.activeFilterCount = 0,
    this.onOpenFilterSheet,
    this.onFlowModeChanged,
    this.onChartPickerTap,
  });

  String _emptyLabel() {
    return showIncome
        ? usesCustomDateRange
            ? 'No categorized income data for this range.'
            : 'No categorized income data for this month.'
        : usesCustomDateRange
            ? 'No categorized expense data for this range.'
            : 'No categorized expense data for this month.';
  }

  double _legendHeight(int categoryCount) {
    if (categoryCount <= 0) return 0;
    final rowCount = (categoryCount / 2).ceil();
    return (rowCount * 22) + ((rowCount - 1) * 8);
  }

  double _pageHeight(_AnalyticsCategoryChartPage page) {
    final categories = page.snapshot.categories.take(6).toList(growable: false);
    final total =
        categories.fold<double>(0.0, (sum, stat) => sum + stat.amount);
    final hasData = total > 0.001;

    return 32 + 220 + (hasData ? 10 + _legendHeight(categories.length) : 0);
  }

  Widget _buildPage(BuildContext context, _AnalyticsCategoryChartPage page) {
    final categories = page.snapshot.categories.take(6).toList(growable: false);
    final total =
        categories.fold<double>(0.0, (sum, stat) => sum + stat.amount);
    final hasData = total > 0.001;

    return Column(
      key: ValueKey<String>(
        'pie-page-${showIncome ? 'income' : 'expense'}-${page.periodLabel}',
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${context.l10nText('Category share for')} ${page.periodLabel}',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        if (!hasData)
          _AnalyticsChartEmptyState(
            message: _emptyLabel(),
          )
        else
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 54,
                    sections: [
                      for (final stat in categories)
                        PieChartSectionData(
                          value: stat.amount,
                          color: stat.color,
                          radius: 56,
                          title: total <= 0
                              ? ''
                              : '${((stat.amount / total) * 100).round()}%',
                          titleStyle: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatLocalizedEtb(context, total),
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10nText(showIncome ? 'Income' : 'Expenses'),
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (hasData) ...[
          const SizedBox(height: 10),
          ..._buildLegendRows(context, categories),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPager = previousPage != null && nextPage != null;
    final previous = previousPage ?? currentPage;
    final next = nextPage ?? currentPage;
    final viewportHeight = math.max(
      _pageHeight(previous),
      math.max(_pageHeight(currentPage), _pageHeight(next)),
    );

    final child = Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AnalyticsPrimaryChartHeader(
            chartLabel: 'Pie Chart',
            headline: showIncome ? 'Income Categories' : 'Expense Categories',
            supportingText: currentPage.periodLabel,
            activeFilterCount: activeFilterCount,
            onOpenFilterSheet: onOpenFilterSheet,
            onChartPickerTap: onChartPickerTap,
            details: _AnalyticsSwipePager(
              height: viewportHeight,
              recenterKey: Object.hash(
                showIncome,
                usesCustomDateRange,
                currentPage.periodLabel,
                previous.periodLabel,
                next.periodLabel,
              ),
              onPrevious: onNavigateToOlderPeriod,
              onNext: onNavigateToNewerPeriod,
              itemBuilder: (context, index) {
                final page = index == 0
                    ? previous
                    : index == 1
                        ? currentPage
                        : next;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (page != currentPage)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          page.periodLabel,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    _buildPage(context, page),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );

    return hasPager ? child : _AnalyticsHorizontalSwipeBlocker(child: child);
  }

  List<Widget> _buildLegendRows(
    BuildContext context,
    List<_AnalyticsCategoryStat> categories,
  ) {
    final rows = <Widget>[];
    for (int i = 0; i < categories.length; i += 2) {
      final left = categories[i];
      final right = i + 1 < categories.length ? categories[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < categories.length ? 8 : 0),
          child: Row(
            children: [
              Expanded(child: _AnalyticsLegendAmountItem(stat: left)),
              const SizedBox(width: 10),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : _AnalyticsLegendAmountItem(stat: right),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }
}

class _AnalyticsSpendingByDayCard extends StatelessWidget {
  final _AnalyticsSpendingByDaySnapshot snapshot;

  const _AnalyticsSpendingByDayCard({
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = snapshot.weekdayExpenseTotals.fold<double>(0.0, math.max);
    final peakDay = _analyticsWeekdayLabel(
      context,
      snapshot.peakWeekdayIndex,
      short: true,
    );
    final periodLabel = snapshot.periodLabel;
    final periodKey = snapshot.periodKey;
    final emptyText = snapshot.showIncome
        ? '${context.l10nText('No income activity in')} $periodLabel.'
        : '${context.l10nText('No expenses in')} $periodLabel.';
    final infoText =
        maxValue > 0 ? '${context.l10nText('Peak')}: $peakDay' : emptyText;
    final titleStyle = TextStyle(
      color: AppColors.textPrimary(context),
      fontSize: 20,
      fontWeight: FontWeight.w800,
      height: 1.05,
    );

    Widget buildAnimatedInlineTransition(Widget child) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        reverseDuration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        child: child,
      );
    }

    return _AnalyticsHorizontalSwipeBlocker(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        context.l10nText(snapshot.showIncome
                            ? 'Income by Day'
                            : 'Spending by Day'),
                        style: titleStyle,
                      ),
                      buildAnimatedInlineTransition(
                        Container(
                          key: ValueKey<String>('spending-period-$periodKey'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.mutedFill(context).withValues(
                              alpha: AppColors.isDark(context) ? 0.38 : 0.7,
                            ),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: AppColors.borderColor(context),
                            ),
                          ),
                          child: Text(
                            periodLabel,
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            buildAnimatedInlineTransition(
              Text(
                infoText,
                key: ValueKey<String>('spending-summary-$periodKey-$infoText'),
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              reverseDuration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                );
              },
              child: maxValue <= 0
                  ? SizedBox(
                      key: ValueKey<String>('spending-empty-$periodKey'),
                      height: 84,
                      child: Center(
                        child: Text(
                          emptyText,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  : SizedBox(
                      key: const ValueKey<String>('spending-bars'),
                      height: 84,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(7, (index) {
                          final value = snapshot.weekdayExpenseTotals[index];
                          final ratio = maxValue > 0
                              ? (value / maxValue).clamp(0.0, 1.0)
                              : 0.0;
                          final barHeight = 10 + (ratio * 52);
                          final isPeak = index == snapshot.peakWeekdayIndex &&
                              maxValue > 0;
                          return Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  AnimatedContainer(
                                    duration: Duration(
                                      milliseconds: 260 + (index * 28),
                                    ),
                                    curve: Curves.easeOutCubic,
                                    height: barHeight,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: isPeak
                                            ? const [
                                                Color(0xFF4ADE80),
                                                Color(0xFF22C55E),
                                              ]
                                            : const [
                                                Color(0xFF7C83EA),
                                                Color(0xFF5B60D9),
                                              ],
                                      ),
                                      borderRadius: BorderRadius.circular(7),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (isPeak
                                                  ? const Color(0xFF22C55E)
                                                  : const Color(0xFF5B60D9))
                                              .withValues(alpha: 0.18),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    style: TextStyle(
                                      color: isPeak
                                          ? AppColors.textPrimary(context)
                                          : AppColors.textSecondary(context),
                                      fontSize: 12,
                                      fontWeight: isPeak
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                    ),
                                    child: Text(
                                      _analyticsWeekdayLabel(
                                        context,
                                        index,
                                        short: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsTopRecipientsCard extends StatelessWidget {
  final _AnalyticsTopRecipientsSnapshot snapshot;

  const _AnalyticsTopRecipientsCard({
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    final maxAmount = snapshot.topRecipients.isEmpty
        ? 0.0
        : snapshot.topRecipients.first.amount;
    final periodLabel = snapshot.periodLabel;
    final periodKey = snapshot.periodKey;
    final emptyText = snapshot.showIncome
        ? '${context.l10nText('No income senders in')} $periodLabel.'
        : '${context.l10nText('No expense recipients in')} $periodLabel.';
    final infoText = snapshot.topRecipients.isEmpty
        ? emptyText
        : '${_formatCount(snapshot.recipientExpenseCount)} ${context.l10nText('total')}';
    final titleStyle = TextStyle(
      color: AppColors.textPrimary(context),
      fontSize: 20,
      fontWeight: FontWeight.w800,
      height: 1.05,
    );

    Widget buildAnimatedInlineTransition(Widget child) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        reverseDuration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        child: child,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      context.l10nText(
                        snapshot.showIncome ? 'Top Senders' : 'Top Recipients',
                      ),
                      style: titleStyle,
                    ),
                    buildAnimatedInlineTransition(
                      Container(
                        key: ValueKey<String>('recipients-period-$periodKey'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.mutedFill(context).withValues(
                            alpha: AppColors.isDark(context) ? 0.38 : 0.7,
                          ),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: AppColors.borderColor(context),
                          ),
                        ),
                        child: Text(
                          periodLabel,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          buildAnimatedInlineTransition(
            Text(
              infoText,
              key: ValueKey<String>('recipients-summary-$periodKey-$infoText'),
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            reverseDuration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
            child: snapshot.topRecipients.isEmpty
                ? Padding(
                    key: ValueKey<String>('recipients-empty-$periodKey'),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        emptyText,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : Column(
                    key: ValueKey<String>('recipients-list-$periodKey'),
                    children:
                        snapshot.topRecipients.asMap().entries.map((entry) {
                      final index = entry.key;
                      final stat = entry.value;
                      final ratio = maxAmount > 0
                          ? (stat.amount / maxAmount).clamp(0.0, 1.0)
                          : 0.0;
                      return Padding(
                        padding: EdgeInsets.only(
                          top: index == 0 ? 4 : 12,
                          bottom: index + 1 == snapshot.topRecipients.length
                              ? 0
                              : 2,
                        ),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 22,
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: AppColors.textTertiary(context),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stat.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.textPrimary(context),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: AppColors.mutedFill(context),
                                          borderRadius:
                                              BorderRadius.circular(99),
                                        ),
                                        child: AnimatedFractionallySizedBox(
                                          duration: Duration(
                                            milliseconds: 260 + (index * 28),
                                          ),
                                          curve: Curves.easeOutCubic,
                                          alignment: Alignment.centerLeft,
                                          widthFactor: ratio,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: snapshot.showIncome
                                                  ? AppColors.incomeSuccess
                                                  : const Color(0xFF6D7EE8),
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${snapshot.showIncome ? '+' : '-'}${_formatLocalizedEtb(context, stat.amount)}',
                                      style: TextStyle(
                                        color: snapshot.showIncome
                                            ? AppColors.incomeSuccess
                                            : AppColors.red,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_formatCount(stat.count)} ${context.l10nText('tx')}',
                                      style: TextStyle(
                                        color: AppColors.textTertiary(context),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (index + 1 != snapshot.topRecipients.length)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Divider(
                                  height: 1,
                                  color: AppColors.borderColor(context),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsMoneyFlowCard extends StatelessWidget {
  final _AnalyticsMoneyFlowSnapshot snapshot;

  const _AnalyticsMoneyFlowCard({
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    final flowColor =
        snapshot.netCashFlow >= 0 ? AppColors.incomeSuccess : AppColors.red;
    final periodLabel = snapshot.periodLabel;
    final periodKey = snapshot.periodKey;
    final infoText = snapshot.totalTransactions == 0
        ? '${context.l10nText('No transactions in')} $periodLabel.'
        : '${_formatCount(snapshot.totalTransactions)} ${context.l10nText('total')}';
    final titleStyle = TextStyle(
      color: AppColors.textPrimary(context),
      fontSize: 20,
      fontWeight: FontWeight.w800,
      height: 1.05,
    );

    Widget buildAnimatedInlineTransition(Widget child) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        reverseDuration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        child: child,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      context.l10nText('Money Flow'),
                      style: titleStyle,
                    ),
                    buildAnimatedInlineTransition(
                      Container(
                        key: ValueKey<String>('money-flow-period-$periodKey'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.mutedFill(context).withValues(
                            alpha: AppColors.isDark(context) ? 0.38 : 0.7,
                          ),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: AppColors.borderColor(context),
                          ),
                        ),
                        child: Text(
                          periodLabel,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          buildAnimatedInlineTransition(
            Text(
              infoText,
              key: ValueKey<String>('money-flow-summary-$periodKey-$infoText'),
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            reverseDuration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
            child: Column(
              key: ValueKey<String>('money-flow-body-$periodKey'),
              children: [
                _MoneyFlowRow(
                  label: 'Net Cash Flow',
                  value:
                      '${snapshot.netCashFlow >= 0 ? '+' : '-'}${_formatLocalizedEtb(context, snapshot.netCashFlow.abs())}',
                  valueColor: flowColor,
                ),
                _MoneyFlowRow(
                  label: 'Savings Rate',
                  value: '${snapshot.savingsRate.toStringAsFixed(1)}%',
                ),
                _MoneyFlowRow(
                  label: 'Largest Expense',
                  value: _formatLocalizedEtb(context, snapshot.largestExpense),
                ),
                _MoneyFlowRow(
                  label: 'Largest Deposit',
                  value: _formatLocalizedEtb(context, snapshot.largestDeposit),
                ),
                _MoneyFlowRow(
                  label: 'Total Transactions',
                  value: _formatCount(snapshot.totalTransactions),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyFlowRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MoneyFlowRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10nText(label),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary(context),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchFilterRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;
  final int activeFilterCount;

  const _SearchFilterRow({
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
    this.activeFilterCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(
                  fontSize: 14, color: AppColors.textPrimary(context)),
              decoration: InputDecoration(
                hintText: context.l10nText('Search Transactions'),
                hintStyle: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                filled: true,
                fillColor: AppColors.surfaceColor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderColor(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderColor(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.primaryLight,
                    width: 1.3,
                  ),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _FilterActionButton(
          onTap: onFilterTap,
          activeFilterCount: activeFilterCount,
        ),
      ],
    );
  }
}

class _FilterActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final int activeFilterCount;
  final double size;

  const _FilterActionButton({
    required this.onTap,
    this.activeFilterCount = 0,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilters = activeFilterCount > 0;
    final badgeSize = size <= 40 ? 16.0 : 18.0;
    final badgeOffset = size <= 40 ? -3.0 : -4.0;
    final iconSize = size <= 40 ? 18.0 : 22.0;
    final borderRadius = size <= 40 ? 9.0 : 10.0;
    final badgeFontSize = size <= 40 ? 9.0 : 10.0;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: hasFilters
                  ? AppColors.primaryDark.withValues(alpha: 0.1)
                  : AppColors.cardColor(context),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: hasFilters
                    ? AppColors.primaryDark
                    : AppColors.borderColor(context),
              ),
            ),
            child: Icon(
              AppIcons.filter_list,
              color: hasFilters
                  ? AppColors.primaryDark
                  : AppColors.textSecondary(context),
              size: iconSize,
            ),
          ),
          if (hasFilters)
            Positioned(
              top: badgeOffset,
              right: badgeOffset,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$activeFilterCount',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: badgeFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LedgerHeaderSummary extends StatelessWidget {
  final DateTime? startingDate;
  final double? startingBalance;

  const _LedgerHeaderSummary({
    required this.startingDate,
    required this.startingBalance,
  });

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    final labelStyle = TextStyle(
      color: AppColors.textTertiary(context),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );

    if (startingDate != null) {
      lines.add(
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${context.l10nText('Starting Date')}: ',
                style: labelStyle,
              ),
              TextSpan(
                text: _formatDateHeader(startingDate!, context),
                style: valueStyle,
              ),
            ],
          ),
        ),
      );
    }

    if (startingBalance != null) {
      if (lines.isNotEmpty) {
        lines.add(const SizedBox(height: 4));
      }
      lines.add(
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${context.l10nText('Starting Balance')}: ',
                style: labelStyle,
              ),
              TextSpan(
                text:
                    '${context.l10nText('ETB')} ${formatNumberWithComma(startingBalance)}',
                style: valueStyle,
              ),
            ],
          ),
        ),
      );
    }

    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  const _SelectionBar({
    required this.count,
    required this.onDelete,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            '$count ${context.l10nText('selected')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onDelete,
            child: Icon(AppIcons.delete_outline_rounded,
                size: 20, color: AppColors.red),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: onClear,
            child: Icon(AppIcons.close_rounded,
                size: 20, color: AppColors.slate600),
          ),
        ],
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final String label;

  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.isDark(context)
              ? AppColors.slate400
              : AppColors.slate700,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

const int _paginationVisiblePageButtonCount = 5;
const double _paginationPageButtonSize = 34;
const double _paginationPageButtonHorizontalMargin = 3;
const double _paginationPageButtonStripWidth =
    _paginationVisiblePageButtonCount *
        (_paginationPageButtonSize +
            (_paginationPageButtonHorizontalMargin * 2));

class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ArrowButton(
            icon: AppIcons.chevron_left_rounded,
            enabled: currentPage > 0,
            onTap: () => onPageChanged(currentPage - 1),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: _paginationPageButtonStripWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _buildPageButtons(),
            ),
          ),
          const SizedBox(width: 8),
          _ArrowButton(
            icon: AppIcons.chevron_right_rounded,
            enabled: currentPage < totalPages - 1,
            onTap: () => onPageChanged(currentPage + 1),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageButtons() {
    final pages = <Widget>[];

    if (totalPages <= _paginationVisiblePageButtonCount) {
      for (int i = 0; i < totalPages; i++) {
        pages.add(
          _PageButton(
            page: i,
            isCurrent: i == currentPage,
            onTap: () => onPageChanged(i),
          ),
        );
      }

      return pages;
    }

    const middleVisiblePageButtonCount = _paginationVisiblePageButtonCount - 2;
    final middleStartPage = math.min(
      math.max(1, currentPage - (middleVisiblePageButtonCount ~/ 2)),
      totalPages - middleVisiblePageButtonCount - 1,
    );
    final middleEndPage = middleStartPage + middleVisiblePageButtonCount;

    pages.add(
      _PageButton(
        page: 0,
        isCurrent: currentPage == 0,
        onTap: () => onPageChanged(0),
      ),
    );

    for (int i = middleStartPage; i < middleEndPage; i++) {
      pages.add(
        _PageButton(
          page: i,
          isCurrent: i == currentPage,
          onTap: () => onPageChanged(i),
        ),
      );
    }

    pages.add(
      _PageButton(
        page: totalPages - 1,
        isCurrent: currentPage == totalPages - 1,
        onTap: () => onPageChanged(totalPages - 1),
      ),
    );

    return pages;
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _ArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: _paginationPageButtonSize,
        height: _paginationPageButtonSize,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primaryLight.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? AppColors.primaryLight
              : AppColors.textTertiary(context),
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final int page;
  final bool isCurrent;
  final VoidCallback onTap;

  const _PageButton({
    required this.page,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isCurrent ? null : onTap,
      child: Container(
        width: _paginationPageButtonSize,
        height: _paginationPageButtonSize,
        margin: const EdgeInsets.symmetric(
          horizontal: _paginationPageButtonHorizontalMargin,
        ),
        decoration: BoxDecoration(
          color: isCurrent ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '${page + 1}',
            style: TextStyle(
              color: isCurrent
                  ? AppColors.white
                  : AppColors.textSecondary(context),
              fontSize: 13,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingTransactions extends StatelessWidget {
  const _LoadingTransactions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.cardColor(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.mutedFill(context),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        context.l10nText('No transactions found'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 14,
        ),
      ),
    );
  }
}

class _LedgerFlatItem {
  final Transaction transaction;
  const _LedgerFlatItem(this.transaction);
}

class _BankTransactionsPage extends StatefulWidget {
  final int bankId;

  const _BankTransactionsPage({
    required this.bankId,
  });

  @override
  State<_BankTransactionsPage> createState() => _BankTransactionsPageState();
}

class _BankTransactionsPageState extends State<_BankTransactionsPage> {
  static const int _itemsPerPage = 20;
  static const double _stickyPaginationHeight = 62;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedRefs = <String>{};
  String _searchQuery = '';
  _TransactionFilter _filter = _TransactionFilter();
  int _currentPage = 0;

  bool get _isSelecting => _selectedRefs.isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleSelection(Transaction transaction) {
    setState(() {
      if (_selectedRefs.contains(transaction.reference)) {
        _selectedRefs.remove(transaction.reference);
      } else {
        _selectedRefs.add(transaction.reference);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedRefs.clear());

  void _setPage(int page) {
    if (_currentPage == page) return;
    setState(() => _currentPage = page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    });
  }

  List<Transaction> _bankTransactions(TransactionProvider provider) {
    return provider.allTransactions
        .where((transaction) => transaction.bankId == widget.bankId)
        .toList(growable: false);
  }

  List<Category> _categoriesForBankTransactions(
    TransactionProvider provider,
    List<Transaction> transactions,
  ) {
    final categoryIds = <int>{};
    for (final transaction in transactions) {
      categoryIds.addAll(transaction.selectedCategoryIds);
    }

    final categories = categoryIds
        .map((id) => provider.getCategoryById(id))
        .whereType<Category>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return categories;
  }

  Future<void> _openFilterSheet(TransactionProvider provider) async {
    final transactions = _bankTransactions(provider);
    final categories = _categoriesForBankTransactions(provider, transactions);

    final result = await showModalBottomSheet<_TransactionFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterTransactionsSheet(
        currentFilter: _filter,
        bankIds: const <int>[],
        categories: categories,
        showBankFilter: false,
      ),
    );
    if (result == null) return;

    setState(() {
      _filter = result;
      _currentPage = 0;
    });
  }

  List<Transaction> _filterTransactions(
    TransactionProvider provider,
    List<Transaction> transactions,
  ) {
    var result = transactions;

    if (_filter.type != null) {
      result = result.where((t) => t.type == _filter.type).toList();
    }

    if (_filter.categoryId != null) {
      result =
          result.where((t) => t.includesCategory(_filter.categoryId)).toList();
    }

    if (_filter.minAmount != null) {
      result = result.where((t) => t.amount >= _filter.minAmount!).toList();
    }
    if (_filter.maxAmount != null) {
      result = result.where((t) => t.amount <= _filter.maxAmount!).toList();
    }

    if (_filter.startDate != null || _filter.endDate != null) {
      result = result.where((t) {
        final dt = _parseTransactionTime(t.time);
        if (dt == null) return false;
        if (_filter.startDate != null && dt.isBefore(_filter.startDate!)) {
          return false;
        }
        if (_filter.endDate != null) {
          final endOfDay = _filter.endDate!
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1));
          if (dt.isAfter(endOfDay)) return false;
        }
        return true;
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((t) {
        final receiver = t.receiver?.toLowerCase() ?? '';
        final creditor = t.creditor?.toLowerCase() ?? '';
        final note = t.note?.toLowerCase() ?? '';
        final reference = t.reference.toLowerCase();
        final accountNumber = t.accountNumber?.toLowerCase() ?? '';
        final categoryLabel = provider.categoryLabelForTransaction(t);
        final categorySearchLabel = categoryLabel.toLowerCase();
        final localizedCategory = context.l10nText(categoryLabel).toLowerCase();
        final bank = _bankLabel(t.bankId).toLowerCase();
        final localizedBank =
            _localizedBankLabel(context, t.bankId).toLowerCase();
        return receiver.contains(query) ||
            creditor.contains(query) ||
            note.contains(query) ||
            reference.contains(query) ||
            accountNumber.contains(query) ||
            categorySearchLabel.contains(query) ||
            localizedCategory.contains(query) ||
            bank.contains(query) ||
            localizedBank.contains(query);
      }).toList();
    }

    return result;
  }

  _ActivityTransactionsSummary _summarizeTransactions(
    List<Transaction> transactions,
  ) {
    var totalIncome = 0.0;
    var totalExpense = 0.0;

    for (final transaction in transactions) {
      if (transaction.type == 'CREDIT') {
        totalIncome += transaction.amount;
      } else if (transaction.type == 'DEBIT') {
        totalExpense += transaction.amount;
      }
    }

    return _ActivityTransactionsSummary(
      totalTransactions: transactions.length,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
    );
  }

  List<Object> _buildFlatItems(List<Transaction> transactions) {
    final flatItems = <Object>[];
    String? lastDateKey;
    for (final transaction in transactions) {
      final dt = _parseTransactionTime(transaction.time);
      final dateKey = dt != null
          ? _formatDateHeader(dt, context)
          : context.l10nText('Unknown Date');
      if (dateKey != lastDateKey) {
        flatItems.add(dateKey);
        lastDateKey = dateKey;
      }
      flatItems.add(transaction);
    }
    return flatItems;
  }

  Future<void> _deleteSelected(TransactionProvider provider) async {
    if (_selectedRefs.isEmpty) return;
    final count = _selectedRefs.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardColor(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '${ctx.l10nText('Delete')} $count ${ctx.l10nText(count > 1 ? 'transactions' : 'transaction')}?',
          style: TextStyle(color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          ctx.l10nText('This cannot be undone.'),
          style: TextStyle(color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              ctx.l10nText('Cancel'),
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
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
    );
    if (!mounted || confirmed != true) return;

    final refs = _selectedRefs.toList();
    _clearSelection();

    try {
      await provider.deleteTransactionsByReferences(refs);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10nTextRead('Deleted')} $count ${context.l10nTextRead(count > 1 ? 'transactions' : 'transaction')}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10nTextRead('Failed to delete')}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openTransactionDetailsSheet(
    TransactionProvider provider,
    Transaction transaction,
  ) async {
    await showTransactionDetailsSheet(
      context: context,
      transaction: transaction,
      provider: provider,
    );
  }

  Future<void> _openTransactionCategorySheet(
    TransactionProvider provider,
    Transaction transaction,
  ) async {
    await showTransactionCategorySheet(
      context: context,
      transaction: transaction,
      provider: provider,
    );
  }

  Widget _buildTransactionTile(
    TransactionProvider provider,
    Transaction transaction,
  ) {
    final bankLabel = _localizedBankLabel(context, transaction.bankId);
    final category = provider.getCategoryById(transaction.categoryId);
    final isSelfTransfer = provider.isSelfTransfer(transaction);
    final isMisc = category?.uncategorized == true;
    final categoryLabel = isSelfTransfer
        ? context.l10nText('Self')
        : provider.categoryLabelForTransaction(
            transaction,
            uncategorizedLabel: 'Categorize',
          );
    final localizedCategoryLabel = context.l10nText(categoryLabel);
    final isCategorized =
        isSelfTransfer || transaction.selectedCategoryIds.isNotEmpty;
    final isCredit = transaction.type == 'CREDIT';
    final selected = _selectedRefs.contains(transaction.reference);

    return TransactionTile(
      bank: bankLabel,
      category: localizedCategoryLabel,
      categoryModel: category,
      personLabel: provider.loanDebtPersonNameForTransaction(transaction),
      onPersonTap: (personName) => openLoansPersonPage(
        context: context,
        personName: personName,
      ),
      isCategorized: isCategorized,
      isDebit: !isCredit,
      isSelfTransfer: isSelfTransfer,
      isMisc: isMisc,
      isSharing: provider.isSharingSharedExpenseTransaction(transaction),
      isShared: provider.isSharedExpenseTransaction(transaction),
      amount: _amountLabel(
        context,
        transaction.amount,
        isCredit: isCredit,
      ),
      amountColor: isCredit ? AppColors.incomeSuccess : AppColors.red,
      name: _localizedTransactionCounterparty(
        context,
        transaction,
        isSelfTransfer: isSelfTransfer,
      ),
      timestamp: _transactionTimeLabel(transaction, context),
      selected: selected,
      onTap: _isSelecting
          ? () => _toggleSelection(transaction)
          : () => _openTransactionDetailsSheet(provider, transaction),
      onCategoryTap: _isSelecting
          ? () => _toggleSelection(transaction)
          : () => _openTransactionCategorySheet(provider, transaction),
      onLongPress: () => _toggleSelection(transaction),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final bankName = _localizedBankName(context, widget.bankId);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final bankTransactions = _bankTransactions(provider);
        final filtered = _filterTransactions(provider, bankTransactions)
          ..sort((a, b) {
            final aTime = _parseTransactionTime(a.time);
            final bTime = _parseTransactionTime(b.time);
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });
        final summary = _summarizeTransactions(filtered);
        final totalPages =
            (filtered.length / _itemsPerPage).ceil().clamp(1, 999999);
        final safePage = _currentPage.clamp(0, totalPages - 1);
        final startIndex = safePage * _itemsPerPage;
        final endIndex = (startIndex + _itemsPerPage).clamp(0, filtered.length);
        final pageTransactions = filtered.sublist(startIndex, endIndex);
        final flatItems = _buildFlatItems(pageTransactions);
        final title = _isSelecting
            ? '${_selectedRefs.length} ${context.l10nText('selected')}'
            : bankName;
        final showsPagination = flatItems.isNotEmpty && totalPages > 1;

        return Scaffold(
          backgroundColor: AppColors.background(context),
          appBar: AppBar(
            backgroundColor: AppColors.background(context),
            surfaceTintColor: Colors.transparent,
            leading: _isSelecting
                ? IconButton(
                    onPressed: _clearSelection,
                    icon: const Icon(AppIcons.close),
                  )
                : IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(AppIcons.arrow_back_rounded),
                  ),
            title: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: _isSelecting
                    ? AppColors.primaryDark
                    : AppColors.textPrimary(context),
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (_isSelecting)
                IconButton(
                  onPressed: () => _deleteSelected(provider),
                  icon: const Icon(
                    AppIcons.delete_outline_rounded,
                    color: AppColors.red,
                  ),
                ),
            ],
          ),
          body: Stack(
            children: [
              RefreshIndicator(
                color: AppColors.primaryLight,
                onRefresh: provider.loadData,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SearchFilterRow(
                              controller: _searchController,
                              onChanged: (value) => setState(() {
                                _searchQuery = value;
                                _currentPage = 0;
                              }),
                              onFilterTap: () => _openFilterSheet(provider),
                              activeFilterCount: _filter.activeCount,
                            ),
                            if (!(provider.isLoading &&
                                provider.allTransactions.isEmpty)) ...[
                              const SizedBox(height: 12),
                              _ActivityTransactionsSummaryRow(
                                summary: summary,
                              ),
                            ],
                            if (_isSelecting) ...[
                              const SizedBox(height: 12),
                              _SelectionBar(
                                count: _selectedRefs.length,
                                onDelete: () => _deleteSelected(provider),
                                onClear: _clearSelection,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (flatItems.isEmpty && provider.isLoading)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: _LoadingTransactions(),
                        ),
                      )
                    else if (flatItems.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: _EmptyTransactions(),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                        sliver: SliverList.builder(
                          itemCount: flatItems.length,
                          itemBuilder: (context, index) {
                            final item = flatItems[index];
                            if (item is String) {
                              return _DateHeader(label: item);
                            }
                            return _buildTransactionTile(
                              provider,
                              item as Transaction,
                            );
                          },
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.only(
                        bottom: bottomPadding +
                            24 +
                            (showsPagination ? _stickyPaginationHeight : 0),
                      ),
                    ),
                  ],
                ),
              ),
              if (showsPagination)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.background(context),
                      border: Border(
                        top: BorderSide(color: AppColors.borderColor(context)),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                      child: _PaginationBar(
                        currentPage: safePage,
                        totalPages: totalPages,
                        onPageChanged: _setPage,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HeatmapDayLedgerPage extends StatelessWidget {
  final DateTime date;
  final _AnalyticsHeatmapFilter filter;

  const _HeatmapDayLedgerPage({
    required this.date,
    required this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final transactions = _transactionsForHeatmapDayWithFilter(
      day: date,
      allTransactions: provider.allTransactions,
      filter: filter,
    );
    final derivedBalancesByReference = _deriveCashBalancesByReference(
      allTxns: provider.allTransactions,
      accountSummaries: provider.accountSummaries,
    );
    final weekdayLabel = _analyticsWeekdayLabel(
      context,
      date.weekday % 7,
      short: false,
    );
    var incomeTotal = 0.0;
    var expenseTotal = 0.0;
    for (final transaction in transactions) {
      if (transaction.type == 'CREDIT') {
        incomeTotal += transaction.amount;
      } else if (transaction.type == 'DEBIT') {
        expenseTotal += transaction.amount;
      }
    }
    final netTotal = incomeTotal - expenseTotal;
    final transactionLabel = _formatLocalizedCount(
      context,
      transactions.length,
      'transaction',
      'transactions',
    );
    final netPrefix = netTotal >= 0 ? '+' : '-';

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        toolbarHeight: 74,
        titleSpacing: 8,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatDateHeader(date, context),
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$weekdayLabel • $transactionLabel',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _HeatmapDayInlineStat(
                    label: 'Income',
                    value: '+${_formatLocalizedEtb(context, incomeTotal)}',
                    valueColor: AppColors.incomeSuccess,
                  ),
                  _HeatmapDayInlineStat(
                    label: 'Expense',
                    value: '-${_formatLocalizedEtb(context, expenseTotal)}',
                    valueColor: AppColors.red,
                  ),
                  _HeatmapDayInlineStat(
                    label: 'Net',
                    value:
                        '$netPrefix${_formatLocalizedEtb(context, netTotal.abs())}',
                    valueColor:
                        netTotal >= 0 ? AppColors.incomeSuccess : AppColors.red,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              color: AppColors.borderColor(context),
            ),
            const SizedBox(height: 4),
            if (transactions.isEmpty)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding + 16),
                  child: const Align(
                    alignment: Alignment.topCenter,
                    child: _EmptyTransactions(),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(0, 4, 0, bottomPadding + 12),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final transaction = transactions[index];
                    final lineColor = AppColors.borderColor(context);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 10,
                              child: Center(
                                child: Container(
                                  width: 1.5,
                                  color: lineColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => showTransactionDetailsSheet(
                                    context: context,
                                    transaction: transaction,
                                    provider: provider,
                                  ),
                                  child: _LedgerTransactionEntry(
                                    transaction: transaction,
                                    derivedBalance: derivedBalancesByReference[
                                        transaction.reference],
                                    isSelfTransfer:
                                        provider.isSelfTransfer(transaction),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeatmapDayInlineStat extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _HeatmapDayInlineStat({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${context.l10nText(label)} ',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: valueColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _LedgerTransactionEntry extends StatelessWidget {
  final Transaction transaction;
  final double? derivedBalance;
  final bool isSelfTransfer;

  const _LedgerTransactionEntry({
    required this.transaction,
    this.derivedBalance,
    this.isSelfTransfer = false,
  });

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.type == 'CREDIT';
    final amountColor = isCredit ? AppColors.incomeSuccess : AppColors.red;
    final arrow = isCredit ? '↓' : '↑';
    final sign = isCredit ? '+' : '-';
    final currencyLabel = context.l10nText('ETB');

    final amount = transaction.amount;
    final amountStr = formatNumberAbbreviated(amount).replaceAll('k', 'K');

    final name = isSelfTransfer
        ? context.l10nText('YOU')
        : _localizedTransactionCounterparty(context, transaction);
    final bankName = _localizedBankLabel(context, transaction.bankId);

    final dt = _parseTransactionTime(transaction.time);
    final timeParts = dt != null
        ? _formatLedgerTimeParts(dt, context)
        : const {'time': '', 'period': null};
    final timeStr = timeParts['time'] ?? '';
    final periodStr = timeParts['period'];

    final parsedBalance = _parseRunningBalance(transaction.currentBalance);
    final effectiveBalance = parsedBalance ?? derivedBalance;
    final balanceStr = effectiveBalance != null
        ? formatNumberAbbreviated(effectiveBalance).replaceAll('k', 'K')
        : '-';

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (periodStr != null && periodStr.isNotEmpty)
                  Text(
                    periodStr,
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$arrow  $sign$currencyLabel $amountStr',
                  style: TextStyle(
                    color: amountColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${context.l10nText('Balance')}: $balanceStr',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            bankName,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Accounts Widgets ─────────────────────────────────────────────

const _balanceCardGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
);

class _AccountsBalanceCard extends StatelessWidget {
  final String title;
  final double balance;
  final String subtitle;
  final int transactionCount;
  final double totalCredit;
  final double totalDebit;
  final bool showBalance;
  final VoidCallback onToggleBalance;

  const _AccountsBalanceCard({
    required this.title,
    required this.balance,
    required this.subtitle,
    required this.transactionCount,
    required this.totalCredit,
    required this.totalDebit,
    required this.showBalance,
    required this.onToggleBalance,
  });

  @override
  Widget build(BuildContext context) {
    final currencyLabel = context.l10nText('ETB');
    final balanceLabel = showBalance
        ? '$currencyLabel ${_formatEtbFull(balance)}'
        : '$currencyLabel ***';
    final creditLabel = showBalance
        ? '+$currencyLabel ${_formatEtbFull(totalCredit)}'
        : '+$currencyLabel ***';
    final debitLabel = showBalance
        ? '-$currencyLabel ${_formatEtbFull(totalDebit)}'
        : '-$currencyLabel ***';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _balanceCardGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                balanceLabel,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onToggleBalance,
                child: Icon(
                  showBalance
                      ? AppIcons.visibility_outlined
                      : AppIcons.visibility_off_outlined,
                  color: AppColors.white.withValues(alpha: 0.9),
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$subtitle | ${_formatLocalizedCount(context, transactionCount, 'Txn', 'Txns')}',
            style: TextStyle(
              color: AppColors.white.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: AppColors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                creditLabel,
                style: const TextStyle(
                  color: AppColors.incomeSuccess,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                ' | ',
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),
              Text(
                debitLabel,
                style: const TextStyle(
                  color: AppColors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BankGrid extends StatefulWidget {
  final List<BankSummary> bankSummaries;
  final bool showBalance;
  final AccountSyncStatusService syncStatusService;
  final ValueChanged<int> onBankTap;
  final void Function({int? bankId, bank_model.Bank? initialBank}) onAddAccount;

  const _BankGrid({
    required this.bankSummaries,
    required this.showBalance,
    required this.syncStatusService,
    required this.onBankTap,
    required this.onAddAccount,
  });

  @override
  State<_BankGrid> createState() => _BankGridState();
}

class _BankGridState extends State<_BankGrid> with WidgetsBindingObserver {
  final BankDetectionService _detectionService = BankDetectionService();
  List<DetectedBank> _detectedBanks = [];
  bool _awaitingPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDetectedBanks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(_BankGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload when the registered bank list changes (account added/removed)
    if (oldWidget.bankSummaries.length != widget.bankSummaries.length) {
      _loadDetectedBanks(forceRefresh: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPermission) {
      _awaitingPermission = false;
      _loadDetectedBanks();
    }
  }

  Future<void> _loadDetectedBanks({bool forceRefresh = false}) async {
    try {
      var permissionStatus = await Permission.sms.status;
      if (!permissionStatus.isGranted) {
        permissionStatus = await Permission.sms.request();
      }
      if (!permissionStatus.isGranted) {
        _awaitingPermission = true;
        return;
      }

      final banks = await _detectionService.detectUnregisteredBanks(
        forceRefresh: forceRefresh,
      );
      banks.sort((a, b) => a.bank.shortName
          .toLowerCase()
          .compareTo(b.bank.shortName.toLowerCase()));
      if (mounted) setState(() => _detectedBanks = banks);
    } catch (_) {
      // Silently fail — detected banks are a nice-to-have
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      ...widget.bankSummaries.map((bank) {
        final isCash = bank.bankId == CashConstants.bankId;
        return _BankGridCard(
          bankId: bank.bankId,
          isCash: isCash,
          accountCount: bank.accountCount,
          balance: bank.totalBalance,
          showBalance: widget.showBalance,
          syncProgress: isCash
              ? null
              : widget.syncStatusService.getSyncProgressForBank(bank.bankId),
          onTap: () => widget.onBankTap(bank.bankId),
        );
      }),
      ..._detectedBanks.map((detected) => _DetectedBankCard(
            detected: detected,
            onTap: () => widget.onAddAccount(
              bankId: detected.bank.id,
              initialBank: detected.bank,
            ),
          )),
      _AddAccountCard(onTap: () => widget.onAddAccount()),
    ];

    final rows = <Widget>[];
    for (int i = 0; i < cards.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < cards.length ? 12 : 0),
          child: Row(
            children: [
              Expanded(child: cards[i]),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < cards.length ? cards[i + 1] : const SizedBox(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _BankGridCard extends StatelessWidget {
  final int bankId;
  final bool isCash;
  final int accountCount;
  final double balance;
  final bool showBalance;
  final double? syncProgress;
  final VoidCallback onTap;

  const _BankGridCard({
    required this.bankId,
    required this.isCash,
    required this.accountCount,
    required this.balance,
    required this.showBalance,
    this.syncProgress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bankName = isCash
        ? context.l10nText('Cash Wallet')
        : _localizedBankLabel(context, bankId);
    final bankImage = _getBankImage(bankId);
    final currencyLabel = context.l10nText('ETB');
    final balanceLabel =
        showBalance ? '$currencyLabel ${_formatEtbFull(balance)}' : '*****';
    final subtitleLabel = isCash
        ? context.l10nText('On-hand cash')
        : _formatLocalizedCount(context, accountCount, 'Account', 'Accounts');
    final isSyncing = syncProgress != null;
    final normalizedProgress = syncProgress?.clamp(0.0, 1.0).toDouble();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primaryLight.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          bankName,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _BankLogoCircle(imagePath: bankImage, size: 40),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitleLabel,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isSyncing
                        ? '${context.l10nText('Syncing')} ${(normalizedProgress! * 100).round()}%'
                        : balanceLabel,
                    style: TextStyle(
                      color: isSyncing
                          ? AppColors.primaryLight
                          : showBalance
                              ? (AppColors.isDark(context)
                                  ? AppColors.slate400
                                  : AppColors.slate700)
                              : AppColors.textSecondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: (isSyncing || showBalance) ? 0 : 2,
                    ),
                  ),
                ],
              ),
            ),
            if (isSyncing)
              LinearProgressIndicator(
                value: normalizedProgress,
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.primaryLight),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddAccountCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddAccountCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.borderColor(context), style: BorderStyle.solid),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    context.l10nText('Add Account'),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.mutedFill(context), width: 1.5),
                  ),
                  child: Icon(
                    AppIcons.add,
                    color: AppColors.textSecondary(context),
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.l10nText('Register new'),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10nText('Bank Account'),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectedBankCard extends StatelessWidget {
  final DetectedBank detected;
  final VoidCallback onTap;

  const _DetectedBankCard({
    required this.detected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    context.l10nText(detected.bank.shortName),
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _BankLogoCircle(imagePath: detected.bank.image, size: 40),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _formatLocalizedCount(
                context,
                detected.messageCount,
                'message',
                'messages',
              ),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    AppIcons.add_rounded,
                    size: 12,
                    color: AppColors.primaryLight,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    context.l10nText('Tap to add'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankSelectorStrip extends StatelessWidget {
  final List<BankSummary> bankSummaries;
  final int? selectedBankId;
  final ValueChanged<int> onBankSelected;
  final VoidCallback onTotalsSelected;

  const _BankSelectorStrip({
    required this.bankSummaries,
    required this.selectedBankId,
    required this.onBankSelected,
    required this.onTotalsSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isTotalsSelected = selectedBankId == null;

    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Totals icon (first)
              GestureDetector(
                onTap: onTotalsSelected,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: isTotalsSelected
                        ? Border.all(color: AppColors.primaryLight, width: 2.5)
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/icon/totals_icon.png',
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              // Bank icons
              ...bankSummaries.map((bank) {
                final isSelected = bank.bankId == selectedBankId;
                final image = _getBankImage(bank.bankId);
                return GestureDetector(
                  onTap: () => onBankSelected(bank.bankId),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: AppColors.primaryLight, width: 2.5)
                          : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: _BankLogoCircle(
                        imagePath: image,
                        size: 36,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final AccountSummary account;
  final int bankId;
  final bool isCash;
  final bool showBalance;
  final int transactionCount;
  final String? syncStatus;
  final double? syncProgress;
  final bool isReparsing;
  final VoidCallback onOpenTransactions;
  final VoidCallback? onReparse;
  final VoidCallback? onDelete;
  final VoidCallback? onCashExpense;
  final VoidCallback? onCashIncome;
  final VoidCallback? onSetCashAmount;
  final VoidCallback? onClearCash;

  const _AccountCard({
    required this.account,
    required this.bankId,
    required this.isCash,
    required this.showBalance,
    required this.transactionCount,
    required this.syncStatus,
    required this.syncProgress,
    this.isReparsing = false,
    required this.onOpenTransactions,
    this.onReparse,
    this.onDelete,
    this.onCashExpense,
    this.onCashIncome,
    this.onSetCashAmount,
    this.onClearCash,
  });

  @override
  Widget build(BuildContext context) {
    final bankImage = _getBankImage(bankId);
    final currencyLabel = context.l10nText('ETB');
    final balanceLabel = showBalance
        ? '$currencyLabel ${_formatEtbFull(account.balance)}'
        : '*****';
    final creditLabel = showBalance
        ? '+$currencyLabel ${_formatEtbFull(account.totalCredit)}'
        : '***';
    final debitLabel = showBalance
        ? '-$currencyLabel ${_formatEtbFull(account.totalDebit)}'
        : '***';
    final normalizedProgress = syncProgress?.clamp(0.0, 1.0).toDouble();
    final syncPercentLabel = normalizedProgress == null
        ? null
        : '${(normalizedProgress * 100).round()}%';
    final primaryValueLabel =
        syncStatus != null ? (syncPercentLabel ?? '0%') : balanceLabel;
    final isBusy = isReparsing || syncStatus != null;
    final canDelete = onDelete != null && !isBusy;

    final accountLabel =
        isCash ? context.l10nText('On-hand cash') : account.accountNumber;
    final holderLabel = isCash
        ? context.l10nText('Personal funds')
        : account.accountHolderName.toUpperCase();
    final localizedSyncStatus =
        syncStatus == null ? null : _localizedSyncStatus(context, syncStatus!);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: InkWell(
        onTap: onOpenTransactions,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _BankLogoCircle(imagePath: bankImage, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              accountLabel,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              holderLabel,
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (localizedSyncStatus != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                localizedSyncStatus,
                                style: const TextStyle(
                                  color: AppColors.primaryLight,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        AppIcons.chevron_right_rounded,
                        color: AppColors.textSecondary(context),
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(width: 56),
                      Text(
                        primaryValueLabel,
                        style: TextStyle(
                          color: syncStatus != null
                              ? AppColors.primaryLight
                              : showBalance
                                  ? (AppColors.isDark(context)
                                      ? AppColors.slate400
                                      : AppColors.slate700)
                                  : AppColors.textSecondary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing:
                              (syncPercentLabel != null || showBalance) ? 0 : 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: AppColors.borderColor(context)),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10nText('TRANSACTIONS'),
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 10,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatCount(transactionCount),
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10nText('IN & OUT'),
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 10,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  creditLabel,
                                  style: const TextStyle(
                                    color: AppColors.incomeSuccess,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '|',
                                  style: TextStyle(
                                    color: AppColors.textTertiary(context),
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  debitLabel,
                                  style: const TextStyle(
                                    color: AppColors.red,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (onReparse != null || onDelete != null) ...[
                    const SizedBox(height: 14),
                    Container(height: 1, color: AppColors.borderColor(context)),
                    if (onReparse != null) ...[
                      const SizedBox(height: 12),
                      _CashActionButton(
                        label: isBusy ? 'Syncing...' : 'Reparse SMS',
                        icon: AppIcons.refresh,
                        color: AppColors.primaryDark,
                        outlined: true,
                        isLoading: isBusy,
                        onTap: isBusy ? null : onReparse,
                      ),
                    ],
                    if (onDelete != null) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: canDelete ? onDelete : null,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              AppIcons.delete_outline_rounded,
                              size: 16,
                              color: AppColors.red.withValues(
                                alpha: canDelete ? 0.7 : 0.35,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              context.l10nText('Remove Account'),
                              style: TextStyle(
                                color: AppColors.red.withValues(
                                  alpha: canDelete ? 0.7 : 0.35,
                                ),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  // Cash wallet actions – always visible below the card
                  if (isCash) ...[
                    const SizedBox(height: 12),
                    Container(height: 1, color: AppColors.borderColor(context)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _CashActionButton(
                            label: 'Expense',
                            icon: AppIcons.remove_circle_outline,
                            color: AppColors.red,
                            onTap: onCashExpense,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CashActionButton(
                            label: 'Income',
                            icon: AppIcons.add_circle_outline,
                            color: AppColors.incomeSuccess,
                            onTap: onCashIncome,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CashActionButton(
                            label: 'Clear',
                            icon: AppIcons.cleaning_services_outlined,
                            color: AppColors.red,
                            outlined: true,
                            onTap: onClearCash,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CashActionButton(
                            label: 'Set amount',
                            icon: AppIcons.tune,
                            color: AppColors.primaryDark,
                            outlined: true,
                            onTap: onSetCashAmount,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Sync progress bar — sits at the bottom edge of the card
            if (syncStatus != null)
              LinearProgressIndicator(
                value: normalizedProgress,
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.primaryLight),
              ),
          ],
        ),
      ),
    );
  }
}

class _BankLogoCircle extends StatelessWidget {
  final String imagePath;
  final double size;

  const _BankLogoCircle({
    required this.imagePath,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePath.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.mutedFill(context),
          shape: BoxShape.circle,
        ),
        child: Icon(
          AppIcons.account_balance,
          size: size * 0.5,
          color: AppColors.textSecondary(context),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: AppColors.mutedFill(context),
          child: Icon(
            AppIcons.account_balance,
            size: size * 0.5,
            color: AppColors.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

class _CashActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool outlined;
  final bool isLoading;
  final VoidCallback? onTap;

  const _CashActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.outlined = false,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    final effectiveColor = isDisabled ? color.withValues(alpha: 0.5) : color;
    final foregroundColor = outlined ? effectiveColor : AppColors.white;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: outlined ? AppColors.cardColor(context) : effectiveColor,
          borderRadius: BorderRadius.circular(10),
          border: outlined
              ? Border.all(color: effectiveColor.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foregroundColor,
                ),
              )
            else
              Icon(icon, size: 16, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              context.l10nText(label),
              style: TextStyle(
                color: foregroundColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Set Cash Amount Sheet ───────────────────────────────────────

class _SetCashAmountSheet extends StatefulWidget {
  final double currentBalance;

  const _SetCashAmountSheet({required this.currentBalance});

  @override
  State<_SetCashAmountSheet> createState() => _SetCashAmountSheetState();
}

class _SetCashAmountSheetState extends State<_SetCashAmountSheet> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final initial = widget.currentBalance > 0
        ? widget.currentBalance.toStringAsFixed(2)
        : '';
    _controller = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? _parseAmount(String raw) {
    final cleaned = raw.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final navBarInset = mediaQuery.padding.bottom;
    final bottomPadding = bottomInset + navBarInset + 20;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 16),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.slate400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  context.l10nText('Set cash wallet amount'),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    labelText: context.l10nText('Target balance'),
                    prefixText: '${context.l10nText('ETB')} ',
                    prefixStyle: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    hintText: '0.00',
                    filled: true,
                    fillColor: AppColors.surfaceColor(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: AppColors.borderColor(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: AppColors.borderColor(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.primaryLight),
                    ),
                  ),
                  validator: (value) {
                    final parsed = _parseAmount(value ?? '');
                    if (parsed == null) {
                      return context.l10nTextRead('Enter a valid amount');
                    }
                    if (parsed < 0) {
                      return context.l10nTextRead('Amount cannot be negative');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side:
                              BorderSide(color: AppColors.borderColor(context)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          context.l10nText('Cancel'),
                          style: TextStyle(
                              color: AppColors.textSecondary(context)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          if (!_formKey.currentState!.validate()) return;
                          final parsed = _parseAmount(_controller.text);
                          Navigator.pop(context, parsed);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: AppColors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          context.l10nText('Set amount'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Add Account Sheet ───────────────────────────────────────────

class _AddAccountSheet extends StatefulWidget {
  final int? initialBankId;
  final bank_model.Bank? initialBank;
  final VoidCallback onAccountAdded;

  const _AddAccountSheet({
    this.initialBankId,
    this.initialBank,
    required this.onAccountAdded,
  });

  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  final _accountNumberController = TextEditingController();
  final _holderNameController = TextEditingController();
  final SmsConfigService _smsConfigService = SmsConfigService();
  List<bank_model.Bank> _banks = [];
  Set<int> _supportedBankIds = <int>{};
  int? _selectedBankId;
  bool _isFormValid = false;
  bool _isSubmitting = false;
  bool _isLoadingBanks = true;
  bool _syncPreviousSms = true;

  @override
  void initState() {
    super.initState();
    _accountNumberController.addListener(_validateForm);
    _holderNameController.addListener(_validateForm);
    _loadBanks();
  }

  @override
  void dispose() {
    _accountNumberController.dispose();
    _holderNameController.dispose();
    super.dispose();
  }

  List<BankSelectorOption> get _bankOptions {
    return buildBankSelectorOptions(_banks, _supportedBankIds);
  }

  bool get _hasSupportedBanks {
    return _bankOptions.any((option) => option.isSupported);
  }

  bool get _canSubmit {
    return _isFormValid &&
        !_isSubmitting &&
        _selectedBankId != null &&
        _hasSupportedBanks;
  }

  Future<Set<int>> _loadSupportedBankIds() async {
    try {
      final patterns =
          await _smsConfigService.getPatterns(allowRemoteFetch: false);
      return {
        ...patterns.map((pattern) => pattern.bankId),
        ...await FallbackSmsParser.supportedBankIds(),
      };
    } catch (e) {
      debugPrint("debug: Error loading SMS patterns: $e");
      return FallbackSmsParser.supportedBankIds();
    }
  }

  Future<void> _loadBanks() async {
    final supportedBankIds = await _loadSupportedBankIds();
    final banks = List<bank_model.Bank>.from(_assetBanks);
    final initialBank = widget.initialBank;
    if (initialBank != null) {
      final existingIndex =
          banks.indexWhere((bank) => bank.id == initialBank.id);
      if (existingIndex >= 0) {
        banks[existingIndex] = initialBank;
      } else {
        banks.insert(0, initialBank);
      }
    }
    final dedupedBanks = _dedupeBanksForSelection(banks);
    if (mounted) {
      setState(() {
        _banks = dedupedBanks;
        _supportedBankIds = supportedBankIds;
        _isLoadingBanks = false;
        if (dedupedBanks.isEmpty) {
          _selectedBankId = null;
          return;
        }
        _selectedBankId = resolveSupportedBankId(
          banks: dedupedBanks,
          supportedBankIds: supportedBankIds,
          preferredBankId: widget.initialBankId ?? initialBank?.id,
        );
      });
    }
  }

  void _validateForm() {
    setState(() {
      _isFormValid = _accountNumberController.text.trim().isNotEmpty &&
          _holderNameController.text.trim().isNotEmpty;
    });
  }

  Widget _buildUnsupportedBankNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.red,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10nText(
                'Only banks with parsing support can be selected right now. Unsupported banks stay visible in the selector but cannot be chosen.',
              ),
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedBankId == null) return;
    final accountNumber = _accountNumberController.text.trim();
    final accountHolderName = _holderNameController.text.trim();
    final bankId = _selectedBankId!;
    final messenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<TransactionProvider>(context, listen: false);

    setState(() => _isSubmitting = true);

    try {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      final service = AccountRegistrationService();
      final account = await service.registerAccount(
        accountNumber: accountNumber,
        accountHolderName: accountHolderName,
        bankId: bankId,
        syncPreviousSms: _syncPreviousSms,
        onSyncComplete: () {
          provider.loadData();
        },
      );

      if (account == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10nTextRead('This account already exists')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await provider.loadData();
      widget.onAccountAdded();

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _syncPreviousSms
                ? context.l10nTextRead(
                    "Adding your account. You can leave the app, we'll notify you when it's done.",
                  )
                : context.l10nTextRead('Account added successfully'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${context.l10nTextRead('Error adding account')}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final navBarInset = MediaQuery.of(context).viewPadding.bottom;
    final hintColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: bottomInset + navBarInset),
          child: _isLoadingBanks
              ? Padding(
                  padding: EdgeInsets.only(
                    top: 28,
                    bottom: bottomInset + navBarInset + 20,
                  ),
                  child: const Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 16),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.slate400,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.l10nText('Add Account'),
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceColor(context),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              AppIcons.close,
                              color: AppColors.textSecondary(context),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Bank selector
                    Text(
                      context.l10nText('Bank'),
                      style: TextStyle(
                        color: AppColors.isDark(context)
                            ? AppColors.slate400
                            : AppColors.slate700,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InlineBankSelector(
                      options: _bankOptions,
                      selectedBankId: _selectedBankId,
                      borderRadius: 12,
                      onChanged: (bankId) {
                        setState(() => _selectedBankId = bankId);
                      },
                    ),
                    if (!_hasSupportedBanks) ...[
                      const SizedBox(height: 12),
                      _buildUnsupportedBankNotice(),
                    ],
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _accountNumberController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        labelText: context.l10nText('Account Number'),
                        hintText: context.l10nText('Enter account number'),
                        hintStyle: TextStyle(color: hintColor),
                        labelStyle: TextStyle(color: hintColor),
                        floatingLabelStyle: TextStyle(
                          color: hintColor,
                          fontWeight: FontWeight.w500,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceColor(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: AppColors.borderColor(context)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: AppColors.borderColor(context)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.primaryLight),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? context.l10nTextRead('Required')
                          : null,
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _holderNameController,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        labelText: context.l10nText('Account Holder Name'),
                        hintText: context.l10nText('Enter account holder name'),
                        hintStyle: TextStyle(color: hintColor),
                        labelStyle: TextStyle(color: hintColor),
                        floatingLabelStyle: TextStyle(
                          color: hintColor,
                          fontWeight: FontWeight.w500,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceColor(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: AppColors.borderColor(context)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: AppColors.borderColor(context)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.primaryLight),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? context.l10nTextRead('Required')
                          : null,
                    ),
                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceColor(context),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.borderColor(context)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            AppIcons.sms_outlined,
                            color: AppColors.textSecondary(context),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10nText('Sync SMS History'),
                                  style: TextStyle(
                                    color: AppColors.textPrimary(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  context.l10nText(
                                      'Import past transactions for this account'),
                                  style: TextStyle(
                                    color: AppColors.textSecondary(context),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _syncPreviousSms,
                            onChanged: (value) {
                              setState(() => _syncPreviousSms = value);
                            },
                            activeColor: AppColors.primaryDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(
                                  color: AppColors.borderColor(context)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              context.l10nText('Cancel'),
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _canSubmit ? _submit : null,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: AppColors.primaryDark,
                              foregroundColor: AppColors.white,
                              elevation: 0,
                              disabledBackgroundColor:
                                  AppColors.mutedFill(context),
                              disabledForegroundColor:
                                  AppColors.textTertiary(context),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.white,
                                    ),
                                  )
                                : Text(
                                    context.l10nText('Add Account'),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AccountReparseSelection {
  final DateTime? startDate;
  final bool refreshExistingTransactions;
  final bool importMissedTransactions;
  final bool applyAutoCategorization;

  const _AccountReparseSelection({
    this.startDate,
    this.refreshExistingTransactions = true,
    this.importMissedTransactions = true,
    this.applyAutoCategorization = true,
  });
}

class _ReparseAccountSheet extends StatefulWidget {
  final String accountNumber;
  final String bankName;

  const _ReparseAccountSheet({
    required this.accountNumber,
    required this.bankName,
  });

  @override
  State<_ReparseAccountSheet> createState() => _ReparseAccountSheetState();
}

class _ReparseAccountSheetState extends State<_ReparseAccountSheet> {
  DateTime? _startDate;
  bool _refreshExistingTransactions = true;
  bool _importMissedTransactions = true;
  bool _applyAutoCategorization = true;

  bool get _hasSelectedAction =>
      _refreshExistingTransactions ||
      _importMissedTransactions ||
      _applyAutoCategorization;

  Future<void> _pickStartDate() async {
    final initialDate = _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) {
        final dark = AppColors.isDark(ctx);
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: dark
                ? ColorScheme.dark(
                    primary: AppColors.primaryLight,
                    onPrimary: AppColors.white,
                    surface: AppColors.darkCard,
                    onSurface: AppColors.white,
                  )
                : const ColorScheme.light(
                    primary: AppColors.primaryDark,
                    onPrimary: AppColors.white,
                    surface: AppColors.white,
                    onSurface: AppColors.slate900,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final navBarInset = MediaQuery.of(context).viewPadding.bottom;
    final hintColor = AppColors.textSecondary(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottomInset + navBarInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slate400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10nText('Reparse SMS'),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceColor(context),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      AppIcons.close,
                      color: AppColors.textSecondary(context),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.l10nText(
                'Choose what this scan should do for the selected account. Existing categories stay untouched; auto-categorization only fills uncategorized transactions.',
              ),
              style: TextStyle(
                color: hintColor,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceColor(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.bankName,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.accountNumber,
                    style: TextStyle(
                      color: hintColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              context.l10nText('Actions'),
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _ReparseScopeTile(
              title: 'Refresh existing transactions',
              subtitle:
                  'Update details like receipt links, balances, counterparties, and account info from matching SMS.',
              value: _refreshExistingTransactions,
              onChanged: (value) {
                setState(() => _refreshExistingTransactions = value);
              },
            ),
            const SizedBox(height: 10),
            _ReparseScopeTile(
              title: 'Import missed transactions',
              subtitle:
                  'Create transactions for matching bank SMS that were never imported before.',
              value: _importMissedTransactions,
              onChanged: (value) {
                setState(() => _importMissedTransactions = value);
              },
            ),
            const SizedBox(height: 10),
            _ReparseScopeTile(
              title: 'Apply auto-categorization',
              subtitle:
                  'Run saved auto-category rules on uncategorized matched or newly imported transactions.',
              value: _applyAutoCategorization,
              onChanged: (value) {
                setState(() => _applyAutoCategorization = value);
              },
            ),
            if (!_hasSelectedAction) ...[
              const SizedBox(height: 8),
              Text(
                context.l10nText('Choose at least one action to run.'),
                style: TextStyle(
                  color: AppColors.red.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              context.l10nText('Start date'),
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickStartDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceColor(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderColor(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _startDate == null
                                ? context
                                    .l10nText('All available bank messages')
                                : _formatDateHeader(_startDate!, context),
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _startDate == null
                                ? context.l10nText(
                                    'Leave blank to scan the full SMS history for this bank.',
                                  )
                                : context.l10nText(
                                    'Only scan messages from this date onward.',
                                  ),
                            style: TextStyle(
                              color: hintColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      AppIcons.chevron_right_rounded,
                      size: 18,
                      color: hintColor,
                    ),
                  ],
                ),
              ),
            ),
            if (_startDate != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _startDate = null),
                  child: Text(context.l10nText('Clear start date')),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: AppColors.borderColor(context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      context.l10nText('Cancel'),
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: !_hasSelectedAction
                        ? null
                        : () => Navigator.of(context).pop(
                              _AccountReparseSelection(
                                startDate: _startDate,
                                refreshExistingTransactions:
                                    _refreshExistingTransactions,
                                importMissedTransactions:
                                    _importMissedTransactions,
                                applyAutoCategorization:
                                    _applyAutoCategorization,
                              ),
                            ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      context.l10nText('Run Reparse'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _ReparseScopeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ReparseScopeTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10nText(title),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.l10nText(subtitle),
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primaryDark,
            activeTrackColor: AppColors.primaryDark.withValues(alpha: 0.32),
          ),
        ],
      ),
    );
  }
}

// ─── Filter Bottom Sheet ──────────────────────────────────────────

class _FilterTransactionsSheet extends StatefulWidget {
  final _TransactionFilter currentFilter;
  final List<int> bankIds;
  final List<Category> categories;
  final bool showBankFilter;

  const _FilterTransactionsSheet({
    required this.currentFilter,
    required this.bankIds,
    required this.categories,
    this.showBankFilter = true,
  });

  @override
  State<_FilterTransactionsSheet> createState() =>
      _FilterTransactionsSheetState();
}

class _FilterTransactionsSheetState extends State<_FilterTransactionsSheet> {
  late String? _selectedType;
  late int? _selectedBankId;
  late int? _selectedCategoryId;
  late final TextEditingController _minAmountController;
  late final TextEditingController _maxAmountController;
  String? _amountErrorText;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.currentFilter.type;
    _selectedBankId = widget.currentFilter.bankId;
    _selectedCategoryId = widget.currentFilter.categoryId;
    _minAmountController = TextEditingController(
      text: _formatAmountInput(widget.currentFilter.minAmount),
    );
    _maxAmountController = TextEditingController(
      text: _formatAmountInput(widget.currentFilter.maxAmount),
    );
    _startDate = widget.currentFilter.startDate;
    _endDate = widget.currentFilter.endDate;
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  void _clearAll() {
    setState(() {
      _selectedType = null;
      _selectedBankId = null;
      _selectedCategoryId = null;
      _minAmountController.clear();
      _maxAmountController.clear();
      _amountErrorText = null;
      _startDate = null;
      _endDate = null;
    });
  }

  void _apply() {
    final minRaw = _minAmountController.text;
    final maxRaw = _maxAmountController.text;
    final minAmount = _parseAmountInput(minRaw);
    final maxAmount = _parseAmountInput(maxRaw);
    final amountError = _buildAmountValidationMessage(
      minRaw: minRaw,
      maxRaw: maxRaw,
      minAmount: minAmount,
      maxAmount: maxAmount,
    );

    if (amountError != null) {
      setState(() => _amountErrorText = amountError);
      return;
    }

    Navigator.of(context).pop(
      _TransactionFilter(
        type: _selectedType,
        bankId: _selectedBankId,
        categoryId: _selectedCategoryId,
        minAmount: minAmount,
        maxAmount: maxAmount,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
  }

  double? _parseAmountInput(String raw) {
    final normalized = raw.replaceAll(',', '').trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  bool _hasInvalidAmountInput(String raw) {
    final normalized = raw.replaceAll(',', '').trim();
    return normalized.isNotEmpty && double.tryParse(normalized) == null;
  }

  String? _buildAmountValidationMessage({
    required String minRaw,
    required String maxRaw,
    required double? minAmount,
    required double? maxAmount,
  }) {
    if (_hasInvalidAmountInput(minRaw) || _hasInvalidAmountInput(maxRaw)) {
      return 'Enter a valid amount';
    }
    if (minAmount != null && maxAmount != null && maxAmount < minAmount) {
      return 'Maximum must be at least minimum.';
    }
    return null;
  }

  String _formatAmountInput(double? amount) {
    if (amount == null) return '';
    if (amount == amount.roundToDouble()) {
      return amount.toStringAsFixed(0);
    }
    return amount
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _handleAmountChanged(String _) {
    if (_amountErrorText == null) return;
    final minRaw = _minAmountController.text;
    final maxRaw = _maxAmountController.text;
    final minAmount = _parseAmountInput(minRaw);
    final maxAmount = _parseAmountInput(maxRaw);
    setState(() {
      _amountErrorText = _buildAmountValidationMessage(
        minRaw: minRaw,
        maxRaw: maxRaw,
        minAmount: minAmount,
        maxAmount: maxAmount,
      );
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) {
        final dark = AppColors.isDark(ctx);
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: dark
                ? ColorScheme.dark(
                    primary: AppColors.primaryLight,
                    onPrimary: AppColors.white,
                    surface: AppColors.darkCard,
                    onSurface: AppColors.white,
                  )
                : const ColorScheme.light(
                    primary: AppColors.primaryDark,
                    onPrimary: AppColors.white,
                    surface: AppColors.white,
                    onSurface: AppColors.slate900,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  String _formatDate(DateTime date) {
    return _formatDateHeader(date, context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final navBarPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.slate400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10nText('Filter Transactions'),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(AppIcons.close,
                      color: AppColors.textSecondary(context)),
                  splashRadius: 20,
                ),
              ],
            ),
          ),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 16 + bottomPadding + navBarPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── TYPE ──
                  _sectionLabel('TYPE'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: _selectedType == null,
                        onTap: () => setState(() => _selectedType = null),
                      ),
                      _FilterChip(
                        label: 'Expense',
                        selected: _selectedType == 'DEBIT',
                        onTap: () => setState(() => _selectedType = 'DEBIT'),
                      ),
                      _FilterChip(
                        label: 'Income',
                        selected: _selectedType == 'CREDIT',
                        onTap: () => setState(() => _selectedType = 'CREDIT'),
                      ),
                    ],
                  ),

                  if (widget.showBankFilter) ...[
                    const SizedBox(height: 20),

                    // ── BANK ──
                    _sectionLabel('BANK'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FilterChip(
                          label: 'All Banks',
                          selected: _selectedBankId == null,
                          onTap: () => setState(() => _selectedBankId = null),
                        ),
                        for (final bankId in widget.bankIds)
                          _FilterChip(
                            label: _localizedBankLabel(context, bankId),
                            selected: _selectedBankId == bankId,
                            onTap: () =>
                                setState(() => _selectedBankId = bankId),
                          ),
                      ],
                    ),
                  ],

                  if (widget.categories.isNotEmpty) ...[
                    const SizedBox(height: 20),

                    // ── CATEGORY ──
                    _sectionLabel('CATEGORY'),
                    const SizedBox(height: 8),
                    SizedBox(
                      // Break out of parent horizontal padding so the
                      // scroll starts and ends edge-to-edge.
                      width: MediaQuery.of(context).size.width,
                      child: Transform.translate(
                        offset: const Offset(-20, 0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              _FilterChip(
                                label: 'All',
                                selected: _selectedCategoryId == null,
                                onTap: () =>
                                    setState(() => _selectedCategoryId = null),
                              ),
                              for (final cat in widget.categories)
                                if (cat.id != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _FilterChip(
                                      label: cat.name,
                                      selected: _selectedCategoryId == cat.id,
                                      onTap: () => setState(
                                          () => _selectedCategoryId = cat.id),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // ── AMOUNT RANGE ──
                  _sectionLabel('AMOUNT RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _AmountFilterField(
                          controller: _minAmountController,
                          hint: 'Min',
                          hasError: _amountErrorText != null,
                          onChanged: _handleAmountChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _AmountFilterField(
                          controller: _maxAmountController,
                          hint: 'Max',
                          hasError: _amountErrorText != null,
                          onChanged: _handleAmountChanged,
                        ),
                      ),
                    ],
                  ),
                  if (_amountErrorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.l10nText(_amountErrorText!),
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // ── DATE RANGE ──
                  _sectionLabel('DATE RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DatePickerField(
                          hint: 'Start date',
                          value: _startDate != null
                              ? _formatDate(_startDate!)
                              : null,
                          onTap: () => _pickDate(isStart: true),
                          onClear: _startDate != null
                              ? () => setState(() => _startDate = null)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DatePickerField(
                          hint: 'End date',
                          value:
                              _endDate != null ? _formatDate(_endDate!) : null,
                          onTap: () => _pickDate(isStart: false),
                          onClear: _endDate != null
                              ? () => setState(() => _endDate = null)
                              : null,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── ACTIONS ──
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clearAll,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary(context),
                            side: BorderSide(
                                color: AppColors.borderColor(context)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Clear All'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _apply,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Apply Filters'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      context.l10nText(text),
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _LedgerFilterSheet extends StatefulWidget {
  final _LedgerFilter currentFilter;
  final List<int> bankIds;

  const _LedgerFilterSheet({
    required this.currentFilter,
    required this.bankIds,
  });

  @override
  State<_LedgerFilterSheet> createState() => _LedgerFilterSheetState();
}

class _LedgerFilterSheetState extends State<_LedgerFilterSheet> {
  DateTime? _startDate;
  DateTime? _endDate;
  late Set<int> _selectedBankIds;

  @override
  void initState() {
    super.initState();
    _startDate = widget.currentFilter.startDate;
    _endDate = widget.currentFilter.endDate;
    _selectedBankIds = widget.currentFilter.bankIds.toSet();
  }

  void _clearAll() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedBankIds = <int>{};
    });
  }

  void _toggleBank(int bankId) {
    setState(() {
      if (_selectedBankIds.contains(bankId)) {
        _selectedBankIds.remove(bankId);
      } else {
        _selectedBankIds.add(bankId);
      }
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      _LedgerFilter(
        startDate: _startDate,
        endDate: _endDate,
        bankIds: _selectedBankIds.toSet(),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) {
        final dark = AppColors.isDark(ctx);
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: dark
                ? ColorScheme.dark(
                    primary: AppColors.primaryLight,
                    onPrimary: AppColors.white,
                    surface: AppColors.darkCard,
                    onSurface: AppColors.white,
                  )
                : const ColorScheme.light(
                    primary: AppColors.primaryDark,
                    onPrimary: AppColors.white,
                    surface: AppColors.white,
                    onSurface: AppColors.slate900,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  String _formatDate(DateTime date) {
    return _formatDateHeader(date, context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final navBarPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.slate400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10nText('Filter Ledger'),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    AppIcons.close,
                    color: AppColors.textSecondary(context),
                  ),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                16 + bottomPadding + navBarPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('DATE RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DatePickerField(
                          hint: 'Start date',
                          value: _startDate != null
                              ? _formatDate(_startDate!)
                              : null,
                          onTap: () => _pickDate(isStart: true),
                          onClear: _startDate != null
                              ? () => setState(() => _startDate = null)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DatePickerField(
                          hint: 'End date',
                          value:
                              _endDate != null ? _formatDate(_endDate!) : null,
                          onTap: () => _pickDate(isStart: false),
                          onClear: _endDate != null
                              ? () => setState(() => _endDate = null)
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('BANK'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: 'All Banks',
                        selected: _selectedBankIds.isEmpty,
                        onTap: () => setState(() => _selectedBankIds.clear()),
                      ),
                      for (final bankId in widget.bankIds)
                        _FilterChip(
                          label: _localizedBankLabel(context, bankId),
                          selected: _selectedBankIds.contains(bankId),
                          onTap: () => _toggleBank(bankId),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clearAll,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary(context),
                            side: BorderSide(
                              color: AppColors.borderColor(context),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Clear All'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _apply,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Apply Filters'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      context.l10nText(text),
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _AnalyticsChartFilterSheet extends StatefulWidget {
  final _AnalyticsChartSection chartSection;
  final _AnalyticsHeatmapFilter currentFilter;
  final List<int> bankIds;
  final List<Category> categories;

  const _AnalyticsChartFilterSheet({
    required this.chartSection,
    required this.currentFilter,
    required this.bankIds,
    required this.categories,
  });

  @override
  State<_AnalyticsChartFilterSheet> createState() =>
      _AnalyticsChartFilterSheetState();
}

class _AnalyticsChartFilterSheetState
    extends State<_AnalyticsChartFilterSheet> {
  late _AnalyticsHeatmapMode _selectedMode;
  late _AnalyticsBarChartPeriod _selectedBarPeriod;
  late int? _selectedBankId;
  late int? _selectedCategoryId;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.currentFilter.mode;
    _selectedBarPeriod = widget.currentFilter.barPeriod;
    _selectedBankId = widget.currentFilter.bankId;
    _selectedCategoryId = widget.currentFilter.categoryId;
    _startDate = widget.currentFilter.startDate;
    _endDate = widget.currentFilter.endDate;
  }

  void _clearAll() {
    setState(() {
      if (widget.chartSection.showsModeFilter) {
        _selectedMode = widget.chartSection.defaultFilterMode;
      }
      if (widget.chartSection.showsPeriodFilter) {
        _selectedBarPeriod = widget.chartSection.defaultBarChartPeriod;
      }
      if (widget.chartSection.showsBankFilter) {
        _selectedBankId = null;
      }
      if (widget.chartSection.showsCategoryFilter) {
        _selectedCategoryId = null;
      }
      if (widget.chartSection.showsDateRangeFilter) {
        _startDate = null;
        _endDate = null;
      }
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      _AnalyticsHeatmapFilter(
        mode: widget.chartSection.showsModeFilter
            ? _selectedMode
            : widget.currentFilter.mode,
        barPeriod: widget.chartSection.showsPeriodFilter
            ? _selectedBarPeriod
            : widget.currentFilter.barPeriod,
        bankId: widget.chartSection.showsBankFilter ? _selectedBankId : null,
        categoryId: widget.chartSection.showsCategoryFilter
            ? _selectedCategoryId
            : null,
        startDate: widget.chartSection.showsDateRangeFilter
            ? _startDate
            : widget.currentFilter.startDate,
        endDate: widget.chartSection.showsDateRangeFilter
            ? _endDate
            : widget.currentFilter.endDate,
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) {
        final dark = AppColors.isDark(ctx);
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: dark
                ? ColorScheme.dark(
                    primary: AppColors.primaryLight,
                    onPrimary: AppColors.white,
                    surface: AppColors.darkCard,
                    onSurface: AppColors.white,
                  )
                : const ColorScheme.light(
                    primary: AppColors.primaryDark,
                    onPrimary: AppColors.white,
                    surface: AppColors.white,
                    onSurface: AppColors.slate900,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  String _formatDate(DateTime date) {
    return _formatDateHeader(date, context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final navBarPadding = MediaQuery.of(context).padding.bottom;
    final showsBankSection =
        widget.chartSection.showsBankFilter && widget.bankIds.isNotEmpty;
    final showsCategorySection =
        widget.chartSection.showsCategoryFilter && widget.categories.isNotEmpty;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.slate400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10nText(widget.chartSection.filterTitle),
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10nText(widget.chartSection.filterSubtitle),
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    AppIcons.close,
                    color: AppColors.textSecondary(context),
                  ),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                16 + bottomPadding + navBarPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.chartSection.showsModeFilter) ...[
                    _sectionLabel('TYPE'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (widget.chartSection !=
                            _AnalyticsChartSection.barChart)
                          _FilterChip(
                            label: 'All',
                            selected:
                                _selectedMode == _AnalyticsHeatmapMode.all,
                            onTap: () => setState(
                              () => _selectedMode = _AnalyticsHeatmapMode.all,
                            ),
                          ),
                        _FilterChip(
                          label: 'Expense',
                          selected:
                              _selectedMode == _AnalyticsHeatmapMode.expense,
                          onTap: () => setState(
                            () => _selectedMode = _AnalyticsHeatmapMode.expense,
                          ),
                        ),
                        _FilterChip(
                          label: 'Income',
                          selected:
                              _selectedMode == _AnalyticsHeatmapMode.income,
                          onTap: () => setState(
                            () => _selectedMode = _AnalyticsHeatmapMode.income,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (widget.chartSection.showsPeriodFilter) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('PERIOD'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FilterChip(
                          label: 'Weekly',
                          selected: _selectedBarPeriod ==
                              _AnalyticsBarChartPeriod.weekly,
                          onTap: () => setState(
                            () => _selectedBarPeriod =
                                _AnalyticsBarChartPeriod.weekly,
                          ),
                        ),
                        _FilterChip(
                          label: 'Monthly',
                          selected: _selectedBarPeriod ==
                              _AnalyticsBarChartPeriod.monthly,
                          onTap: () => setState(
                            () => _selectedBarPeriod =
                                _AnalyticsBarChartPeriod.monthly,
                          ),
                        ),
                        _FilterChip(
                          label: 'Yearly',
                          selected: _selectedBarPeriod ==
                              _AnalyticsBarChartPeriod.yearly,
                          onTap: () => setState(
                            () => _selectedBarPeriod =
                                _AnalyticsBarChartPeriod.yearly,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (showsBankSection) ...[
                    if (widget.chartSection.showsModeFilter ||
                        widget.chartSection.showsPeriodFilter)
                      const SizedBox(height: 20),
                    _sectionLabel('BANK'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FilterChip(
                          label: 'All Banks',
                          selected: _selectedBankId == null,
                          onTap: () => setState(() => _selectedBankId = null),
                        ),
                        for (final bankId in widget.bankIds)
                          _FilterChip(
                            label: _localizedBankLabel(context, bankId),
                            selected: _selectedBankId == bankId,
                            onTap: () =>
                                setState(() => _selectedBankId = bankId),
                          ),
                      ],
                    ),
                  ],
                  if (widget.chartSection.showsDateRangeFilter) ...[
                    if (widget.chartSection.showsModeFilter || showsBankSection)
                      const SizedBox(height: 20),
                    _sectionLabel('DATE RANGE'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _DatePickerField(
                            hint: 'Start date',
                            value: _startDate != null
                                ? _formatDate(_startDate!)
                                : null,
                            onTap: () => _pickDate(isStart: true),
                            onClear: _startDate != null
                                ? () => setState(() => _startDate = null)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DatePickerField(
                            hint: 'End date',
                            value: _endDate != null
                                ? _formatDate(_endDate!)
                                : null,
                            onTap: () => _pickDate(isStart: false),
                            onClear: _endDate != null
                                ? () => setState(() => _endDate = null)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (showsCategorySection) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('CATEGORY'),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: MediaQuery.of(context).size.width,
                      child: Transform.translate(
                        offset: const Offset(-20, 0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              _FilterChip(
                                label: 'All',
                                selected: _selectedCategoryId == null,
                                onTap: () => setState(
                                  () => _selectedCategoryId = null,
                                ),
                              ),
                              for (final category in widget.categories)
                                if (category.id != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _FilterChip(
                                      label: category.name,
                                      selected:
                                          _selectedCategoryId == category.id,
                                      onTap: () => setState(
                                        () => _selectedCategoryId = category.id,
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clearAll,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary(context),
                            side: BorderSide(
                              color: AppColors.borderColor(context),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Clear All'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _apply,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Apply Filters'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      context.l10nText(text),
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryDark
              : AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primaryDark
                : AppColors.borderColor(context),
          ),
        ),
        child: Text(
          context.l10nText(label),
          style: TextStyle(
            color:
                selected ? AppColors.white : AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String hint;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DatePickerField({
    required this.hint,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? context.l10nText(hint),
                style: TextStyle(
                  color: value != null
                      ? AppColors.textPrimary(context)
                      : AppColors.textTertiary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  AppIcons.close,
                  size: 16,
                  color: AppColors.textTertiary(context),
                ),
              )
            else
              Icon(
                AppIcons.calendar_today_outlined,
                size: 16,
                color: AppColors.textTertiary(context),
              ),
          ],
        ),
      ),
    );
  }
}

class _AmountFilterField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  const _AmountFilterField({
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      style: TextStyle(
        color: AppColors.textPrimary(context),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: context.l10nText(hint),
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        prefixText: '${context.l10nText('ETB')} ',
        prefixStyle: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: AppColors.surfaceColor(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.borderColor(context),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.borderColor(context),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.primaryLight,
          ),
        ),
      ),
    );
  }
}
