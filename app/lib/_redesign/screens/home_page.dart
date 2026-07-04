import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/theme/app_calendar_option.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_home_page.dart';
import 'package:totals/_redesign/screens/redesign_shell.dart';
import 'package:totals/_redesign/screens/loans_page.dart';
import 'package:totals/screens/accounts_page.dart';
import 'package:totals/screens/failed_parses_page.dart';
import 'package:totals/screens/verify_payments_page.dart';
import 'package:totals/screens/web_page.dart';
import 'package:totals/services/advanced_settings_service.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/utils/app_date_format.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/_redesign/widgets/transaction_category_sheet.dart';
import 'package:totals/_redesign/screens/todays_transactions_page.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/_redesign/widgets/transaction_tile.dart';
import 'package:totals/widgets/add_cash_transaction_sheet.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

class RedesignHomePage extends StatefulWidget {
  final ValueNotifier<bool>? toolsMenuOpenNotifier;

  const RedesignHomePage({
    super.key,
    this.toolsMenuOpenNotifier,
  });

  @override
  State<RedesignHomePage> createState() => _RedesignHomePageState();
}

enum _ChartRange { week, month }

const double _kHomeTrendLeftAxisReservedWidth = 36.0;
const double _kHomeTrendRightAxisReservedWidth = 12.0;

class _RedesignHomePageState extends State<RedesignHomePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final SmsService _smsService = SmsService();
  final DataExportImportService _dataExportImportService =
      DataExportImportService();
  bool _showBalance = false;
  _ChartRange _chartRange = _ChartRange.week;
  final Set<String> _selectedRefs = {};
  bool _isRefreshingTodaySms = false;
  bool _isBootstrapping = true;
  bool _isImportingBackup = false;
  bool _isToolsMenuOpen = false;
  Set<ToolsFabItem> _visibleToolsFabItems =
      AdvancedSettingsService.defaultToolsFabItems;

  bool get _isSelecting => _selectedRefs.isNotEmpty;

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

  void _setToolsMenuOpen(bool isOpen) {
    final notifier = widget.toolsMenuOpenNotifier;
    if (_isToolsMenuOpen != isOpen) {
      setState(() => _isToolsMenuOpen = isOpen);
    }
    if (notifier != null && notifier.value != isOpen) {
      notifier.value = isOpen;
    }
  }

  void _handleToolsMenuNotifierChanged() {
    final notifier = widget.toolsMenuOpenNotifier;
    if (notifier == null || notifier.value == _isToolsMenuOpen) return;
    setState(() => _isToolsMenuOpen = notifier.value);
  }

  void _handleToolsFabItemsChanged() {
    if (!mounted) return;
    setState(() {
      _visibleToolsFabItems =
          AdvancedSettingsService.instance.toolsFabItems.value;
    });
  }

  Future<void> _refreshTodaySms(TransactionProvider provider) async {
    if (_isRefreshingTodaySms) return;
    setState(() => _isRefreshingTodaySms = true);

    try {
      final result = await _smsService.syncTodayBankSms();
      if (!mounted) return;

      if (result.permissionDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10nTextRead('SMS permission denied.')),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      if (result.added > 0) {
        await provider.loadData();
      }

      final message = result.added > 0
          ? '${context.l10nTextRead('Added')} ${result.added} ${context.l10nTextRead('new transactions')}'
          : context.l10nTextRead('No missed transactions');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10nTextRead('Failed to refresh SMS')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _isRefreshingTodaySms = false);
    }
  }

  Future<void> _deleteSelected(TransactionProvider provider) async {
    if (_selectedRefs.isEmpty) return;
    final count = _selectedRefs.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${ctx.l10nText('Delete')} $count ${ctx.l10nText(count > 1 ? 'transactions' : 'transaction')}?',
        ),
        content: Text(ctx.l10nText('This cannot be undone.')),
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
    );
    if (confirmed == true) {
      await provider.deleteTransactionsByReferences(_selectedRefs.toList());
      _clearSelection();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.toolsMenuOpenNotifier?.addListener(_handleToolsMenuNotifierChanged);
    AdvancedSettingsService.instance.toolsFabItems
        .addListener(_handleToolsFabItemsChanged);
    AdvancedSettingsService.instance.ensureLoaded().then((_) {
      _handleToolsFabItemsChanged();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = Provider.of<TransactionProvider>(context, listen: false);
      if (provider.dataVersion == 0) {
        await provider.loadData();
      }
      if (mounted) {
        setState(() => _isBootstrapping = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant RedesignHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toolsMenuOpenNotifier == widget.toolsMenuOpenNotifier) {
      return;
    }
    oldWidget.toolsMenuOpenNotifier
        ?.removeListener(_handleToolsMenuNotifierChanged);
    widget.toolsMenuOpenNotifier?.addListener(_handleToolsMenuNotifierChanged);
    _handleToolsMenuNotifierChanged();
  }

  @override
  void dispose() {
    widget.toolsMenuOpenNotifier
        ?.removeListener(_handleToolsMenuNotifierChanged);
    AdvancedSettingsService.instance.toolsFabItems
        .removeListener(_handleToolsFabItemsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        final showInitialSkeleton = provider.dataVersion == 0 &&
            (_isBootstrapping || provider.isLoading);
        final summary = provider.summary;
        final totalBalance = summary?.totalBalance ?? 0.0;
        final todaySorted = provider.todayTransactions;
        final todayCount = todaySorted.length;
        final monthTransactionsCount = provider.monthTransactions.length;
        final todayList = todaySorted.take(3).toList(growable: false);
        final todayTotals = provider.todayTotals;
        final weekTotals = provider.weekTotals;
        final monthTotals = provider.monthTotals;
        final thirtyDayTotals = provider.thirtyDayTotals;
        final selfTransferCount = provider.selfTransferCount;
        final hasAddedBankAccounts = provider.accountSummaries.any(
          (account) => account.bankId != CashConstants.bankId,
        );
        final insightMessage = provider.monthlyInsight;
        final trendSeries = _chartRange == _ChartRange.week
            ? provider.weekTrendSeries
            : provider.monthTrendSeries;
        return Scaffold(
          backgroundColor: AppColors.background(context),
          body: SafeArea(
            child: Stack(
              children: [
                RefreshIndicator(
                  color: AppColors.primaryLight,
                  onRefresh: provider.loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: showInitialSkeleton
                        ? const _HomeLoadingSkeleton()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TotalBalanceCard(
                                totalBalance: totalBalance,
                                todayIncome: todayTotals.income,
                                todayExpense: todayTotals.expense,
                                weekIncome: weekTotals.income,
                                weekExpense: weekTotals.expense,
                                showBalance: _showBalance,
                                onToggleBalance: () {
                                  setState(() {
                                    _showBalance = !_showBalance;
                                  });
                                },
                                hasAddedBankAccounts: hasAddedBankAccounts,
                                onCardTap: _openAccountsPage,
                                onBreakdownTap: () => _openBalanceBreakdown(
                                  totalBalance: totalBalance,
                                  monthTransactions: monthTransactionsCount,
                                  selfTransferCount: selfTransferCount,
                                  monthTotals: monthTotals,
                                  thirtyDayTotals: thirtyDayTotals,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _InsightCard(
                                message: insightMessage,
                                showImportBackupPrompt: !hasAddedBankAccounts,
                                isImportingBackup: _isImportingBackup,
                                onImportBackupTap: () =>
                                    _importBackup(provider),
                              ),
                              const SizedBox(height: 16),
                              _QuickCashActions(
                                onExpenseTap: _showCashExpenseSheet,
                                onIncomeTap: _showCashIncomeSheet,
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${context.l10nText('Today')} ($todayCount)',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton(
                                        onPressed: _openAllTodayTransactions,
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          foregroundColor:
                                              AppColors.primaryLight,
                                        ),
                                        child:
                                            Text(context.l10nText('See all')),
                                      ),
                                      const SizedBox(width: 4),
                                      _RefreshButton(
                                        isLoading: _isRefreshingTodaySms,
                                        onTap: () => _refreshTodaySms(provider),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (_isSelecting) ...[
                                const SizedBox(height: 8),
                                _SelectionBar(
                                  count: _selectedRefs.length,
                                  onDelete: () => _deleteSelected(provider),
                                  onClear: _clearSelection,
                                ),
                              ],
                              const SizedBox(height: 8),
                              // Keep the empty/loaded state stable during background
                              // reloads so returning to Home does not flicker.
                              if (todayList.isEmpty)
                                const _EmptyTransactions()
                              else
                                ...todayList.map((transaction) {
                                  final bankLabel = context.l10nText(
                                    provider
                                        .getBankShortName(transaction.bankId),
                                  );
                                  final category = provider
                                      .getCategoryById(transaction.categoryId);
                                  final isSelfTransfer =
                                      provider.isSelfTransfer(transaction);
                                  final isMisc =
                                      category?.uncategorized == true;
                                  final categoryLabel = isSelfTransfer
                                      ? 'Self'
                                      : provider.categoryLabelForTransaction(
                                          transaction,
                                          uncategorizedLabel: 'Categorize',
                                        );
                                  final isCategorize = isSelfTransfer ||
                                      transaction
                                          .selectedCategoryIds.isNotEmpty;
                                  final isCredit = transaction.type == 'CREDIT';
                                  final amountLabel = _amountLabel(
                                    transaction.amount,
                                    isCredit: isCredit,
                                    currencyLabel: context.l10nText('ETB'),
                                  );
                                  final selected = _selectedRefs
                                      .contains(transaction.reference);
                                  return TransactionTile(
                                    bank: bankLabel,
                                    category: categoryLabel,
                                    categoryModel: category,
                                    personLabel: provider
                                        .loanDebtPersonNameForTransaction(
                                            transaction),
                                    onPersonTap: (personName) =>
                                        openLoansPersonPage(
                                      context: context,
                                      personName: personName,
                                    ),
                                    isCategorized: isCategorize,
                                    isDebit: !isCredit,
                                    isSelfTransfer: isSelfTransfer,
                                    isMisc: isMisc,
                                    isSharing: provider
                                        .isSharingSharedExpenseTransaction(
                                            transaction),
                                    isShared:
                                        provider.isSharedExpenseTransaction(
                                            transaction),
                                    amount: amountLabel,
                                    amountColor: isCredit
                                        ? AppColors.incomeSuccess
                                        : AppColors.red,
                                    name: _transactionCounterparty(transaction,
                                        isSelfTransfer: isSelfTransfer),
                                    timestamp: _transactionTimeLabel(
                                        transaction, context),
                                    selected: selected,
                                    onTap: _isSelecting
                                        ? () => _toggleSelection(transaction)
                                        : () => _openTransactionDetailsSheet(
                                              provider: provider,
                                              transaction: transaction,
                                            ),
                                    onCategoryTap: _isSelecting
                                        ? () => _toggleSelection(transaction)
                                        : () => _openTransactionCategorySheet(
                                              provider: provider,
                                              transaction: transaction,
                                            ),
                                    onLongPress: () =>
                                        _toggleSelection(transaction),
                                  );
                                }),
                              const SizedBox(height: 16),
                              _IncomeExpenseCard(
                                trendSeries: trendSeries,
                                selectedRange: _chartRange,
                                onRangeChanged: (value) {
                                  if (_chartRange == value) return;
                                  setState(() {
                                    _chartRange = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_isToolsMenuOpen,
                    child: AnimatedOpacity(
                      opacity: _isToolsMenuOpen ? 1 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _setToolsMenuOpen(false),
                        child: Container(
                          color: AppColors.black.withValues(
                            alpha: AppColors.isDark(context) ? 0.5 : 0.28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 8,
                  child: _HomeToolsFabMenu(
                    isOpen: _isToolsMenuOpen,
                    visibleItems: _visibleToolsFabItems,
                    onOpenChanged: _setToolsMenuOpen,
                    onWebDashboardTap: _openWebDashboard,
                    onQuickAccountsTap: _openQuickAccountsPage,
                    onVerifyPaymentsTap: _openVerifyPayments,
                    onFailedParsingsTap: _openFailedParsings,
                    onDataSyncTap: _openDataSync,
                    onLoansTap: _openLoansPlaceholder,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openAllTodayTransactions() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const TodaysTransactionsPage(),
      ),
    );
  }

  void _openAccountsPage() {
    final shellState = context.findAncestorStateOfType<RedesignShellState>();
    shellState?.openMoneyAccountsPage();
  }

  void _openQuickAccountsPage() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const AccountsPage(),
      ),
    );
  }

  void _openWebDashboard() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const WebPage(),
      ),
    );
  }

  void _openVerifyPayments() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const VerifyPaymentsPage(),
      ),
    );
  }

  void _openFailedParsings() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const FailedParsesPage(),
      ),
    );
  }

  void _openDataSync() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const DataSyncHomePage(),
      ),
    );
  }

  void _openLoansPlaceholder() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const LoansPage(),
      ),
    );
  }

  Future<void> _importBackup(TransactionProvider provider) async {
    if (_isImportingBackup) return;
    setState(() => _isImportingBackup = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose your Totals backup',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null ||
          result.files.isEmpty ||
          result.files.single.path == null) {
        return;
      }

      final file = File(result.files.single.path!);
      final jsonData = await file.readAsString();

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cardColor(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Import backup?',
            style: TextStyle(color: AppColors.textPrimary(ctx)),
          ),
          content: Text(
            'This restores data from the selected backup file. '
            'Existing data stays in place and duplicates are skipped.',
            style: TextStyle(color: AppColors.textSecondary(ctx)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary(ctx)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(ctx.l10nText('Import')),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      await _dataExportImportService.importAllData(jsonData);
      await provider.loadData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10nTextRead('Backup imported successfully')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10nTextRead('Import failed')}: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _isImportingBackup = false);
    }
  }

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
      showTypeSelector: false,
    );
  }

  void _showCashIncomeSheet() {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    showAddCashTransactionSheet(
      context: context,
      provider: provider,
      accountNumber: _cashAccountNumber(),
      initialIsDebit: false,
      showTypeSelector: false,
    );
  }

  Future<void> _openTransactionDetailsSheet({
    required TransactionProvider provider,
    required Transaction transaction,
  }) async {
    await showTransactionDetailsSheet(
      context: context,
      transaction: transaction,
      provider: provider,
    );
  }

  Future<void> _openTransactionCategorySheet({
    required TransactionProvider provider,
    required Transaction transaction,
  }) async {
    await showTransactionCategorySheet(
      context: context,
      transaction: transaction,
      provider: provider,
    );
  }

  void _openBalanceBreakdown({
    required double totalBalance,
    required int monthTransactions,
    required int selfTransferCount,
    required TransactionTotals monthTotals,
    required TransactionTotals thirtyDayTotals,
  }) {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _BalanceBreakdownSheet(
          totalBalance: totalBalance,
          monthTransactions: monthTransactions,
          selfTransferCount: selfTransferCount,
          monthTotals: monthTotals,
          thirtyDayTotals: thirtyDayTotals,
          allTransactions: provider.allTransactions,
          provider: provider,
        );
      },
    );
  }
}

DateTime? _parseTransactionTime(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toLocal();
  } catch (_) {
    return null;
  }
}

Map<String, double> _deriveCashBalancesForHomeBreakdown({
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

  // Account balances are stored as present totals; reverse the transaction
  // deltas to estimate the opening point, then roll forward chronologically.
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

    final parsed = double.tryParse(transaction.currentBalance ?? '');
    if (parsed != null) {
      rollingBalance = parsed;
      derived[transaction.reference] = parsed;
    } else {
      derived[transaction.reference] = rollingBalance;
    }
  }

  return derived;
}

String _formatCompactEtbValue(double value) {
  return formatNumberAbbreviated(value).replaceAll(' ', '');
}

String _amountLabel(
  double amount, {
  required bool isCredit,
  required String currencyLabel,
}) {
  final formatted = formatNumberWithComma(amount);
  return '${isCredit ? '+' : '-'} $currencyLabel $formatted';
}

String _transactionCounterparty(Transaction transaction,
    {bool isSelfTransfer = false}) {
  final receiver = transaction.receiver?.trim();
  final creditor = transaction.creditor?.trim();
  if (receiver != null && receiver.isNotEmpty) return receiver.toUpperCase();
  if (creditor != null && creditor.isNotEmpty) return creditor.toUpperCase();
  return isSelfTransfer ? 'YOU' : 'UNKNOWN';
}

String _transactionTimeLabel(Transaction transaction, BuildContext context) {
  final dt = _parseTransactionTime(transaction.time);
  if (dt == null) return context.l10nText('Unknown time');
  final isEC =
      context.watch<ThemeProvider>().appCalendar == AppCalendarOption.ethiopian;
  if (isEC) {
    return AppDateFormat.ethiopianTime(dt, context: context);
  }
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

class _TotalBalanceCard extends StatelessWidget {
  final double totalBalance;
  final double todayIncome;
  final double todayExpense;
  final double weekIncome;
  final double weekExpense;
  final bool showBalance;
  final VoidCallback onToggleBalance;
  final bool hasAddedBankAccounts;
  final VoidCallback onCardTap;
  final VoidCallback onBreakdownTap;

  const _TotalBalanceCard({
    required this.totalBalance,
    required this.todayIncome,
    required this.todayExpense,
    required this.weekIncome,
    required this.weekExpense,
    required this.showBalance,
    required this.onToggleBalance,
    required this.hasAddedBankAccounts,
    required this.onCardTap,
    required this.onBreakdownTap,
  });

  @override
  Widget build(BuildContext context) {
    final currencyLabel = context.l10nText('ETB');
    final displayBalance =
        showBalance ? formatNumberWithComma(totalBalance) : '***';
    final todayIncomeLabel =
        showBalance ? '+ ${_formatDelta(todayIncome)}' : '***';
    final todayExpenseLabel =
        showBalance ? '- ${_formatDelta(todayExpense)}' : '***';
    final weekIncomeLabel =
        showBalance ? '+ ${_formatDelta(weekIncome)}' : '***';
    final weekExpenseLabel =
        showBalance ? '- ${_formatDelta(weekExpense)}' : '***';

    return GestureDetector(
      onTap: onCardTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  context.l10nText(
                    hasAddedBankAccounts ? 'TOTAL BALANCE' : 'GET STARTED',
                  ),
                  style: TextStyle(
                    color: AppColors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (hasAddedBankAccounts) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '$currencyLabel $displayBalance',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onToggleBalance,
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.white.withValues(alpha: 0.9),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(24, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      showBalance
                          ? AppIcons.visibility_outlined
                          : AppIcons.visibility_off_outlined,
                      size: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: onBreakdownTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        context.l10nText('How did I get here?'),
                        style: TextStyle(
                          color: AppColors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        AppIcons.arrow_forward,
                        size: 14,
                        color: AppColors.white.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 1,
                color: AppColors.white.withValues(alpha: 0.22),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _BalanceDelta(
                      label: context.l10nText('Today'),
                      income: todayIncomeLabel,
                      expense: todayExpenseLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BalanceDelta(
                      label: context.l10nText('This week'),
                      income: weekIncomeLabel,
                      expense: weekExpenseLabel,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 14),
              Text(
                context.l10nText('No bank accounts added yet.'),
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10nText(
                  'Tap this card to open Accounts and add your bank accounts.',
                ),
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.82),
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    context.l10nText('Open Accounts'),
                    style: TextStyle(
                      color: AppColors.white.withValues(alpha: 0.95),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    AppIcons.arrow_forward,
                    size: 16,
                    color: AppColors.white.withValues(alpha: 0.9),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _RefreshButton({
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      width: 40,
      child: IconButton(
        onPressed: isLoading ? null : onTap,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.cardColor(context),
          side: BorderSide(color: AppColors.borderColor(context)),
          foregroundColor: AppColors.isDark(context)
              ? AppColors.slate400
              : AppColors.slate700,
          disabledForegroundColor: AppColors.textTertiary(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryLight,
                ),
              )
            : const Icon(AppIcons.refresh, size: 18),
      ),
    );
  }
}

class _BalanceDelta extends StatelessWidget {
  final String label;
  final String income;
  final String expense;

  const _BalanceDelta({
    required this.label,
    required this.income,
    required this.expense,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.white.withValues(alpha: 0.85),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              income,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.incomeSuccess,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 12,
              color: AppColors.white.withValues(alpha: 0.35),
            ),
            const SizedBox(width: 8),
            Text(
              expense,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.red,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatDelta(double value) {
  final formatted = formatNumberAbbreviated(value).replaceAll('k', 'K');
  return formatted;
}

class _HomeToolsFabMenu extends StatefulWidget {
  final bool isOpen;
  final Set<ToolsFabItem> visibleItems;
  final ValueChanged<bool> onOpenChanged;
  final VoidCallback onWebDashboardTap;
  final VoidCallback onQuickAccountsTap;
  final VoidCallback onVerifyPaymentsTap;
  final VoidCallback onFailedParsingsTap;
  final VoidCallback onDataSyncTap;
  final VoidCallback onLoansTap;

  const _HomeToolsFabMenu({
    required this.isOpen,
    required this.visibleItems,
    required this.onOpenChanged,
    required this.onWebDashboardTap,
    required this.onQuickAccountsTap,
    required this.onVerifyPaymentsTap,
    required this.onFailedParsingsTap,
    required this.onDataSyncTap,
    required this.onLoansTap,
  });

  @override
  State<_HomeToolsFabMenu> createState() => _HomeToolsFabMenuState();
}

class _HomeToolsFabMenuState extends State<_HomeToolsFabMenu> {
  void _toggleMenu() {
    widget.onOpenChanged(!widget.isOpen);
  }

  void _runAction(VoidCallback? onTap) {
    if (onTap == null) return;
    widget.onOpenChanged(false);
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    const menuWidth = 280.0;
    const fabSize = 56.0;
    const itemHeight = 48.0;
    const itemGap = 8.0;
    const menuGap = 8.0;
    const actionColor = AppColors.primaryLight;
    final visibleItems = widget.visibleItems.isEmpty
        ? AdvancedSettingsService.defaultToolsFabItems
        : widget.visibleItems;
    final actions = <_HomeToolsFabAction>[
      _HomeToolsFabAction(
        item: ToolsFabItem.quickAccounts,
        icon: AppIcons.account_balance_outlined,
        color: actionColor,
        label: context.l10nText('Quick Accounts'),
        onTap: widget.onQuickAccountsTap,
      ),
      _HomeToolsFabAction(
        item: ToolsFabItem.verifyPayments,
        icon: AppIcons.qr_code_scanner_rounded,
        color: actionColor,
        label: context.l10nText('Verify Payments'),
        onTap: widget.onVerifyPaymentsTap,
      ),
      _HomeToolsFabAction(
        item: ToolsFabItem.loans,
        icon: AppIcons.debts,
        color: actionColor,
        label: context.l10nText('Loans'),
        onTap: widget.onLoansTap,
      ),
      _HomeToolsFabAction(
        item: ToolsFabItem.failedParsings,
        icon: AppIcons.sms_outlined,
        color: actionColor,
        label: context.l10nText('Failed Parsings'),
        onTap: widget.onFailedParsingsTap,
      ),
      _HomeToolsFabAction(
        item: ToolsFabItem.dataSync,
        icon: AppIcons.cloud_download,
        color: actionColor,
        label: context.l10nText('Data Sync'),
        onTap: widget.onDataSyncTap,
      ),
      _HomeToolsFabAction(
        item: ToolsFabItem.webDashboard,
        icon: AppIcons.dashboard_outlined,
        color: actionColor,
        label: context.l10nText('Web Dashboard'),
        onTap: widget.onWebDashboardTap,
      ),
    ].where((action) => visibleItems.contains(action.item)).toList();
    final openHeight = fabSize +
        menuGap +
        actions.length * itemHeight +
        (actions.length - 1) * itemGap;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: menuWidth,
      height: widget.isOpen ? openHeight : fabSize,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          for (var index = 0; index < actions.length; index++)
            Positioned(
              right: 0,
              bottom: fabSize +
                  menuGap +
                  (actions.length - index - 1) * (itemHeight + itemGap),
              child: IgnorePointer(
                ignoring: !widget.isOpen,
                child: AnimatedOpacity(
                  opacity: widget.isOpen ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: AnimatedScale(
                    scale: widget.isOpen ? 1 : 0.92,
                    alignment: Alignment.bottomRight,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: _HomeToolsFabMenuItem(
                      action: actions[index],
                      onTap: () => _runAction(actions[index].onTap),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Tooltip(
              message: context.l10nText('Tools'),
              child: FloatingActionButton(
                heroTag: 'home-tools-fab',
                onPressed: _toggleMenu,
                backgroundColor: AppColors.primaryLight,
                foregroundColor: AppColors.white,
                elevation: 0,
                focusElevation: 0,
                hoverElevation: 0,
                highlightElevation: 0,
                disabledElevation: 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Icon(
                    widget.isOpen ? Icons.remove : AppIcons.grid_view_outlined,
                    key: ValueKey(
                      widget.isOpen ? 'tools-minus' : 'tools-grid',
                    ),
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

class _HomeToolsFabAction {
  final ToolsFabItem item;
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _HomeToolsFabAction({
    required this.item,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
}

class _HomeToolsFabMenuItem extends StatelessWidget {
  final _HomeToolsFabAction action;
  final VoidCallback onTap;

  const _HomeToolsFabMenuItem({
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = action.onTap != null;
    final iconColor =
        isEnabled ? action.color : AppColors.textTertiary(context);
    final textColor = isEnabled
        ? AppColors.textPrimary(context)
        : AppColors.textTertiary(context);

    return Tooltip(
      message: action.label,
      child: Opacity(
        opacity: isEnabled ? 1 : 0.56,
        child: Material(
          color: AppColors.cardColor(context),
          elevation: 8,
          shadowColor: AppColors.black.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: isEnabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 280,
              height: 48,
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 10),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(
                        alpha: AppColors.isDark(context) ? 0.18 : 0.1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Icon(
                        action.icon,
                        color: iconColor,
                        size: 19,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _localizedHomeInsight(BuildContext context, String message) {
  final directTranslation = context.l10nText(message);
  if (directTranslation != message) return directTranslation;

  if (context.l10nText('INSIGHT') == 'INSIGHT') return message;

  final currencyLabel = context.l10nText('ETB');
  final savedSoFarMatch = RegExp(
    r"^You've saved ETB (.+) so far this month\.$",
  ).firstMatch(message);
  if (savedSoFarMatch != null) {
    final amount = savedSoFarMatch.group(1)!;
    return 'በዚህ ወር እስካሁን $amount $currencyLabel ቆጥበዋል።';
  }

  final spentSoFarMatch = RegExp(
    r"^You've spent ETB (.+) more than you earned this month\.$",
  ).firstMatch(message);
  if (spentSoFarMatch != null) {
    final amount = spentSoFarMatch.group(1)!;
    return 'በዚህ ወር ካገኙት በ$amount $currencyLabel በላይ ወጪ አድርገዋል።';
  }

  final comparisonMatch = RegExp(
    r"^You've (saved|spent more than earned) ETB (.+) this month, (\d+)% (better|lower) than your 3-month average\.$",
  ).firstMatch(message);
  if (comparisonMatch != null) {
    final status = comparisonMatch.group(1)!;
    final amount = comparisonMatch.group(2)!;
    final percent = comparisonMatch.group(3)!;
    final direction = comparisonMatch.group(4)! == 'better' ? 'የተሻለ' : 'ዝቅተኛ';
    final summary = status == 'saved'
        ? 'በዚህ ወር $amount $currencyLabel ቆጥበዋል'
        : 'በዚህ ወር ካገኙት በ$amount $currencyLabel በላይ ወጪ አድርገዋል';
    return '$summary፣ ከ3 ወር አማካይዎ $percent% $direction ነው።';
  }

  return message;
}

class _InsightCard extends StatelessWidget {
  final String message;
  final bool showImportBackupPrompt;
  final bool isImportingBackup;
  final VoidCallback? onImportBackupTap;

  const _InsightCard({
    required this.message,
    this.showImportBackupPrompt = false,
    this.isImportingBackup = false,
    this.onImportBackupTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizedMessage = _localizedHomeInsight(context, message);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!showImportBackupPrompt) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                AppIcons.lightbulb_outline,
                color: AppColors.amber,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10nText(
                    showImportBackupPrompt ? 'RESTORE FROM BACKUP' : 'INSIGHT',
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary(context),
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                if (showImportBackupPrompt) ...[
                  Text(
                    context.l10nText(
                      'Used Totals before? Import your backup to restore your accounts, transactions, budgets, and categories.',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.isDark(context)
                          ? AppColors.slate400
                          : AppColors.slate700,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: isImportingBackup ? null : onImportBackupTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: isImportingBackup
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : const Icon(AppIcons.cloud_download, size: 16),
                    label: Text(
                      context.l10nText(
                        isImportingBackup ? 'Importing...' : 'Import Backup',
                      ),
                    ),
                  ),
                ] else
                  Text(
                    localizedMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.isDark(context)
                          ? AppColors.slate400
                          : AppColors.slate700,
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

class _QuickCashActions extends StatelessWidget {
  final VoidCallback onExpenseTap;
  final VoidCallback onIncomeTap;

  const _QuickCashActions({
    required this.onExpenseTap,
    required this.onIncomeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickCashActionButton(
            label: 'Expense',
            icon: AppIcons.upload_rounded,
            color: AppColors.red,
            onTap: onExpenseTap,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _QuickCashActionButton(
            label: 'Income',
            icon: AppIcons.download_rounded,
            color: AppColors.incomeSuccess,
            filled: true,
            onTap: onIncomeTap,
          ),
        ),
      ],
    );
  }
}

class _QuickCashActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _QuickCashActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = filled
        ? color.withValues(alpha: AppColors.isDark(context) ? 0.14 : 0.09)
        : AppColors.cardColor(context);
    final borderColor = filled
        ? color.withValues(alpha: AppColors.isDark(context) ? 0.42 : 0.28)
        : AppColors.borderColor(context).withValues(
            alpha: AppColors.isDark(context) ? 0.72 : 0.9,
          );

    return CustomPaint(
      foregroundPainter: _DottedRoundedBorderPainter(
        color: borderColor,
        radius: 8,
      ),
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    context.l10nText(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: filled
                          ? color
                          : AppColors.textPrimary(context).withValues(
                              alpha: AppColors.isDark(context) ? 0.9 : 0.76,
                            ),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DottedRoundedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DottedRoundedBorderPainter({
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(0.75),
          Radius.circular(radius),
        ),
      );
    final metrics = path.computeMetrics();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const dotRadius = 1.2;
    const targetSpacing = 6.0;
    for (final metric in metrics) {
      final dotCount = math.max(1, (metric.length / targetSpacing).round());
      final spacing = metric.length / dotCount;

      for (var index = 0; index < dotCount; index += 1) {
        final distance = (index + 0.5) * spacing;
        final tangent = metric.getTangentForOffset(distance);
        if (tangent != null) {
          canvas.drawCircle(tangent.position, dotRadius, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedRoundedBorderPainter oldDelegate) {
    return color != oldDelegate.color || radius != oldDelegate.radius;
  }
}

class _HomeLoadingSkeleton extends StatefulWidget {
  const _HomeLoadingSkeleton();

  @override
  State<_HomeLoadingSkeleton> createState() => _HomeLoadingSkeletonState();
}

class _HomeLoadingSkeletonState extends State<_HomeLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBalanceCardSkeleton(context),
        const SizedBox(height: 12),
        _buildInsightCardSkeleton(context),
        const SizedBox(height: 16),
        _buildQuickCashActionsSkeleton(context),
        const SizedBox(height: 20),
        _buildTodayHeaderSkeleton(context),
        const SizedBox(height: 12),
        for (int index = 0; index < 3; index++)
          _buildTransactionSkeleton(context, index),
        const SizedBox(height: 16),
        _buildChartSkeleton(context),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildBalanceCardSkeleton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.l10nText('TOTAL BALANCE'),
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.82),
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${context.l10nText('ETB')} ...',
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.74),
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              Icon(
                AppIcons.visibility_off_outlined,
                size: 22,
                color: AppColors.white.withValues(alpha: 0.42),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.l10nText('How did I get here?'),
            style: TextStyle(
              color: AppColors.white.withValues(alpha: 0.7),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: AppColors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildBalanceDeltaSkeleton(
                  context,
                  label: context.l10nText('Today'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBalanceDeltaSkeleton(
                  context,
                  label: context.l10nText('This week'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceDeltaSkeleton(
    BuildContext context, {
    required String label,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.white.withValues(alpha: 0.82),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+ ...',
              style: TextStyle(
                color: AppColors.incomeSuccess.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 12,
              color: AppColors.white.withValues(alpha: 0.24),
            ),
            const SizedBox(width: 8),
            Text(
              '- ...',
              style: TextStyle(
                color: AppColors.red.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInsightCardSkeleton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              AppIcons.lightbulb_outline,
              size: 18,
              color: AppColors.amber.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10nText('INSIGHT'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Preparing your latest insight...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
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

  Widget _buildQuickCashActionsSkeleton(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildQuickCashActionSkeleton(context)),
        const SizedBox(width: 14),
        Expanded(child: _buildQuickCashActionSkeleton(context)),
      ],
    );
  }

  Widget _buildQuickCashActionSkeleton(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 84,
        height: 16,
        decoration: BoxDecoration(
          color: AppColors.mutedFill(context).withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildTodayHeaderSkeleton(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          context.l10nText('Today'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10nText('See all'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.primaryLight.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(width: 8),
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.cardColor(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              child: Icon(
                AppIcons.refresh,
                size: 18,
                color: AppColors.textTertiary(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTransactionSkeleton(BuildContext context, int index) {
    const chipWidths = [84.0, 96.0, 78.0];
    const amountWidths = [72.0, 82.0, 68.0];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildShimmerBox(
                context,
                width: 18,
                height: 18,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(width: 10),
              _buildShimmerBox(
                context,
                width: chipWidths[index],
                height: 20,
                borderRadius: BorderRadius.circular(999),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildShimmerBox(
                context,
                width: amountWidths[index],
                height: 18,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 8),
              _buildShimmerBox(
                context,
                width: 20,
                height: 8,
                borderRadius: BorderRadius.circular(999),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartSkeleton(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.l10nText('Income vs Expense'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const Spacer(),
              const _StaticRangeToggle(
                selectedRange: _ChartRange.week,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildShimmerBox(
            context,
            height: 184,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(height: 10),
          Padding(
            padding:
                const EdgeInsets.only(left: _kHomeTrendLeftAxisReservedWidth),
            child: Text(
              'Updating your chart...',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerBox(
    BuildContext context, {
    double? width,
    required double height,
    required BorderRadius borderRadius,
    bool onPrimary = false,
  }) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = Curves.easeInOut.transform(_controller.value);
        final baseColor = onPrimary
            ? AppColors.white.withValues(alpha: 0.10)
            : AppColors.mutedFill(context).withValues(
                alpha: AppColors.isDark(context) ? 0.46 : 0.58,
              );
        final activeColor = onPrimary
            ? AppColors.white.withValues(alpha: 0.14)
            : AppColors.mutedFill(context).withValues(
                alpha: AppColors.isDark(context) ? 0.56 : 0.68,
              );
        final fillColor =
            Color.lerp(baseColor, activeColor, pulse) ?? baseColor;

        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: fillColor,
          ),
        );
      },
    );
  }
}

class _StaticRangeToggle extends StatelessWidget {
  final _ChartRange selectedRange;

  const _StaticRangeToggle({
    required this.selectedRange,
  });

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
        mainAxisSize: MainAxisSize.min,
        children: [
          _StaticRangeToggleButton(
            label: '7D',
            selected: selectedRange == _ChartRange.week,
          ),
          _StaticRangeToggleButton(
            label: '30D',
            selected: selectedRange == _ChartRange.month,
          ),
        ],
      ),
    );
  }
}

class _StaticRangeToggleButton extends StatelessWidget {
  final String label;
  final bool selected;

  const _StaticRangeToggleButton({
    required this.label,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
            '$count selected',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(AppIcons.delete_outline_rounded,
                size: 20, color: AppColors.red),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: onClear,
            child: Icon(AppIcons.close_rounded,
                size: 20, color: AppColors.textSecondary(context)),
          ),
        ],
      ),
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppIcons.receipt_long_rounded,
            size: 40,
            color: AppColors.textTertiary(context),
          ),
          const SizedBox(height: 10),
          Text(
            context.l10nText('No transactions today'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.isDark(context)
                  ? AppColors.slate400
                  : AppColors.slate700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10nText(
              'New transactions will appear here as they come in.',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomeExpenseCard extends StatelessWidget {
  final TransactionTrendSeries trendSeries;
  final _ChartRange selectedRange;
  final ValueChanged<_ChartRange> onRangeChanged;

  const _IncomeExpenseCard({
    required this.trendSeries,
    required this.selectedRange,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyLabel = context.l10nText('ETB');
    final rangeLabel = trendSeries.days == 7
        ? context.l10nText('Last 7 days')
        : context.l10nText('Last 30 days');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.l10nText('Income vs Expense'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const Spacer(),
              _RangeToggle(
                selectedRange: selectedRange,
                onRangeChanged: onRangeChanged,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 184,
            width: double.infinity,
            child: _IncomeExpenseTrendChart(
              trendSeries: trendSeries,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding:
                const EdgeInsets.only(left: _kHomeTrendLeftAxisReservedWidth),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Text(
                  '+ $currencyLabel ${_formatCompactEtbValue(trendSeries.totalIncome)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.incomeSuccess,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '- $currencyLabel ${_formatCompactEtbValue(trendSeries.totalExpense)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${context.l10nText('Peak')}: $currencyLabel ${_formatCompactEtbValue(trendSeries.maxValue)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  rangeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary(context),
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

class _RangeToggle extends StatelessWidget {
  final _ChartRange selectedRange;
  final ValueChanged<_ChartRange> onRangeChanged;

  const _RangeToggle({
    required this.selectedRange,
    required this.onRangeChanged,
  });

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
        mainAxisSize: MainAxisSize.min,
        children: [
          _RangeToggleButton(
            label: '7D',
            selected: selectedRange == _ChartRange.week,
            onTap: () => onRangeChanged(_ChartRange.week),
          ),
          _RangeToggleButton(
            label: '30D',
            selected: selectedRange == _ChartRange.month,
            onTap: () => onRangeChanged(_ChartRange.month),
          ),
        ],
      ),
    );
  }
}

class _RangeToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangeToggleButton({
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

class _IncomeExpenseTrendChart extends StatelessWidget {
  final TransactionTrendSeries trendSeries;

  const _IncomeExpenseTrendChart({
    required this.trendSeries,
  });

  @override
  Widget build(BuildContext context) {
    final isEC = context.watch<ThemeProvider>().appCalendar ==
        AppCalendarOption.ethiopian;

    if (trendSeries.maxValue <= 0.001) {
      return Center(
        child: Text(
          context.l10nText('No income or expense data yet.'),
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
          ),
        ),
      );
    }

    final incomeValues = trendSeries.incomePoints
        .map((value) => value * trendSeries.maxValue)
        .toList(growable: false);
    final expenseValues = trendSeries.expensePoints
        .map((value) => value * trendSeries.maxValue)
        .toList(growable: false);
    final pointCount = incomeValues.length;
    final chartMax = _resolveHomeTrendChartMax(trendSeries.maxValue);
    final interval = chartMax / 4;

    return LineChart(
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
            color: AppColors.borderColor(context).withValues(alpha: 0.7),
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
              reservedSize: _kHomeTrendRightAxisReservedWidth,
              getTitlesWidget: (value, meta) => const SizedBox.shrink(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 38,
              getTitlesWidget: (value, meta) => _buildHomeTrendBottomAxisTitle(
                context,
                value,
                meta,
                pointCount,
                isEC,
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: interval,
              reservedSize: _kHomeTrendLeftAxisReservedWidth,
              getTitlesWidget: (value, meta) =>
                  _buildHomeTrendAxisTitle(context, value, meta),
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
              for (int index = 0; index < incomeValues.length; index++)
                FlSpot(index.toDouble(), incomeValues[index]),
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
              for (int index = 0; index < expenseValues.length; index++)
                FlSpot(index.toDouble(), expenseValues[index]),
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
    );
  }
}

double _resolveHomeTrendChartMax(double maxValue) {
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

Widget _buildHomeTrendAxisTitle(
  BuildContext context,
  double value,
  TitleMeta meta,
) {
  return SideTitleWidget(
    axisSide: meta.axisSide,
    child: Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Text(
        value.abs() < 0.001 ? '0' : _formatCompactEtbValue(value),
        style: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

Widget _buildHomeTrendBottomAxisTitle(
  BuildContext context,
  double value,
  TitleMeta meta,
  int pointCount,
  bool isEC,
) {
  if ((value - value.roundToDouble()).abs() > 0.001) {
    return const SizedBox.shrink();
  }

  final index = value.toInt();
  if (index < 0 || index >= pointCount) return const SizedBox.shrink();

  final labelStride = pointCount <= 7 ? 1 : 5;
  final shouldShow =
      index == 0 || index == pointCount - 1 || index % labelStride == 0;
  if (!shouldShow) return const SizedBox.shrink();

  final today = DateTime.now();
  final endDate = DateTime(today.year, today.month, today.day);
  final date = endDate.subtract(Duration(days: pointCount - 1 - index));

  final label = AppDateFormat.monthDay(date, context: context);

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

class _BalanceBreakdownSheet extends StatefulWidget {
  final double totalBalance;
  final int monthTransactions;
  final int selfTransferCount;
  final TransactionTotals monthTotals;
  final TransactionTotals thirtyDayTotals;
  final List<Transaction> allTransactions;
  final TransactionProvider provider;

  const _BalanceBreakdownSheet({
    required this.totalBalance,
    required this.monthTransactions,
    required this.selfTransferCount,
    required this.monthTotals,
    required this.thirtyDayTotals,
    required this.allTransactions,
    required this.provider,
  });

  @override
  State<_BalanceBreakdownSheet> createState() => _BalanceBreakdownSheetState();
}

class _BalanceBreakdownSheetState extends State<_BalanceBreakdownSheet> {
  bool _showWeek = true; // true = this week, false = this month

  // Precomputed flat list caches
  late List<Object> _weekItems;
  late List<Object> _monthItems;
  late Map<String, double> _derivedCashBalancesByReference;
  late double? _weekStartingBalance;
  late DateTime? _weekStartingDate;
  late double? _monthStartingBalance;
  late DateTime? _monthStartingDate;

  @override
  void initState() {
    super.initState();
    _precompute();
  }

  void _precompute() {
    final now = DateTime.now();
    // Rolling 7-day window (today + previous 6 days), not calendar week.
    final today = DateTime(now.year, now.month, now.day);
    final weekStartDay = today.subtract(const Duration(days: 6));
    final monthStartDay = DateTime(now.year, now.month, 1);

    // Sort descending (newest first)
    final sorted = List<Transaction>.from(widget.allTransactions)
      ..sort((a, b) {
        final aT = _parseTransactionTime(a.time);
        final bT = _parseTransactionTime(b.time);
        if (aT == null && bT == null) return 0;
        if (aT == null) return 1;
        if (bT == null) return -1;
        return bT.compareTo(aT);
      });

    _derivedCashBalancesByReference = _deriveCashBalancesForHomeBreakdown(
      allTxns: sorted,
      accountSummaries: widget.provider.accountSummaries,
    );

    _weekItems = _buildFlatItems(sorted, weekStartDay);
    _monthItems = _buildFlatItems(sorted, monthStartDay);

    _weekStartingBalance = _computeStartingBalance(
      sorted,
      weekStartDay,
      _derivedCashBalancesByReference,
    );
    _weekStartingDate = weekStartDay;
    _monthStartingBalance = _computeStartingBalance(
      sorted,
      monthStartDay,
      _derivedCashBalancesByReference,
    );
    _monthStartingDate = monthStartDay;
  }

  List<Object> _buildFlatItems(List<Transaction> sorted, DateTime startDay) {
    final items = <Object>[];
    String? lastKey;
    for (final txn in sorted) {
      final dt = _parseTransactionTime(txn.time);
      if (dt == null || dt.isBefore(startDay)) continue;
      final key = _formatDateKey(dt);
      if (key != lastKey) {
        items.add(key);
        lastKey = key;
      }
      items.add(txn);
    }
    return items;
  }

  double? _computeStartingBalance(
    List<Transaction> sorted,
    DateTime startDay,
    Map<String, double> derivedCashBalancesByReference,
  ) {
    // sorted is descending; walk backwards (ascending) to find
    // the last transaction before startDay
    for (int i = sorted.length - 1; i >= 0; i--) {
      final dt = _parseTransactionTime(sorted[i].time);
      if (dt != null && dt.isBefore(startDay)) {
        final parsed = double.tryParse(sorted[i].currentBalance ?? '');
        if (parsed != null) return parsed;
        if (sorted[i].bankId == CashConstants.bankId) {
          return derivedCashBalancesByReference[sorted[i].reference];
        }
        return null;
      }
    }
    return null;
  }

  String _formatDateKey(DateTime dt) {
    return AppDateFormat.monthDayYear(dt, context: context);
  }

  String _formatTime(DateTime dt) {
    if (AppDateFormat.usesEthiopianCalendar(context)) {
      return AppDateFormat.ethiopianTime(dt, context: context);
    }

    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flatItems = _showWeek ? _weekItems : _monthItems;
    final startBal = _showWeek ? _weekStartingBalance : _monthStartingBalance;
    final startDate = _showWeek ? _weekStartingDate : _monthStartingDate;
    final transactionCount =
        flatItems.where((entry) => entry is Transaction).length;
    final currencyLabel = context.l10nText('ETB');

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
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
                    context.l10nText('How did I get here?'),
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
            // Week / Month toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  _PeriodChip(
                    label: context.l10nText('Last 7 days'),
                    selected: _showWeek,
                    onTap: () => setState(() => _showWeek = true),
                  ),
                  const SizedBox(width: 8),
                  _PeriodChip(
                    label: context.l10nText('This month'),
                    selected: !_showWeek,
                    onTap: () => setState(() => _showWeek = false),
                  ),
                  const Spacer(),
                  Text(
                    '$transactionCount ${context.l10nText('txns')}',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.borderColor(context)),
            // Starting balance
            if (startBal != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  '${startDate != null ? '${_formatDateKey(startDate)} ' : ''}${context.l10nText('Starting Balance')}: $currencyLabel ${formatNumberWithComma(startBal)}',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            // Ledger timeline
            Expanded(
              child: flatItems.isEmpty
                  ? Center(
                      child: Text(
                        context.l10nText(
                          _showWeek
                              ? 'No transactions this last 7 days'
                              : 'No transactions this month',
                        ),
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: flatItems.length,
                      itemBuilder: (context, index) {
                        final item = flatItems[index];

                        // Date header
                        if (item is String) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
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
                                const SizedBox(width: 10),
                                Text(
                                  item,
                                  style: TextStyle(
                                    color: AppColors.textPrimary(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Transaction entry
                        final txn = item as Transaction;
                        final lineColor = AppColors.borderColor(context);
                        final isCredit = txn.type == 'CREDIT';
                        final arrow = isCredit ? '↓' : '↑';
                        final sign = isCredit ? '+' : '-';
                        final amountStr = formatNumberAbbreviated(txn.amount)
                            .replaceAll('k', 'K');
                        final amountColor =
                            isCredit ? AppColors.incomeSuccess : AppColors.red;
                        final isSelfTransfer =
                            widget.provider.isSelfTransfer(txn);
                        final name = isSelfTransfer
                            ? 'YOU'
                            : _transactionCounterparty(txn);
                        final bank = context.l10nText(
                          widget.provider.getBankShortName(txn.bankId),
                        );
                        final dt = _parseTransactionTime(txn.time);
                        final timeStr = dt != null ? _formatTime(dt) : '';
                        final parsedBalance =
                            double.tryParse(txn.currentBalance ?? '');
                        final effectiveBalance = parsedBalance ??
                            (txn.bankId == CashConstants.bankId
                                ? _derivedCashBalancesByReference[txn.reference]
                                : null);
                        final balStr = effectiveBalance != null
                            ? formatNumberAbbreviated(effectiveBalance)
                                .replaceAll('k', 'K')
                            : '-';

                        return Padding(
                          padding: const EdgeInsets.only(left: 16, right: 16),
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
                                const SizedBox(width: 10),
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      showTransactionDetailsSheet(
                                        context: context,
                                        transaction: txn,
                                        provider: widget.provider,
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          top: 12, bottom: 6),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 58,
                                            child: Text(
                                              timeStr,
                                              style: TextStyle(
                                                color: AppColors.textSecondary(
                                                    context),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.textPrimary(
                                                            context),
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '$arrow $sign$currencyLabel $amountStr',
                                                  style: TextStyle(
                                                    color: amountColor,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Bal: $balStr',
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.textSecondary(
                                                            context),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            bank,
                                            style: TextStyle(
                                              color: AppColors.textTertiary(
                                                  context),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
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

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDark : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.primaryDark
                : AppColors.borderColor(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? AppColors.white : AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
