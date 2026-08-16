import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/account.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:intl/intl.dart';
import 'package:totals/screens/transactions_for_period_page.dart';
import 'package:totals/widgets/analytics/time_period_selector.dart';
import 'package:totals/widgets/analytics/filter_section.dart';
import 'package:totals/widgets/analytics/income_expense_cards.dart';
import 'package:totals/widgets/analytics/chart_type_selector.dart';
import 'package:totals/widgets/analytics/chart_container.dart';
import 'package:totals/widgets/analytics/transactions_list.dart';
import 'package:totals/widgets/analytics/chart_data_point.dart';
import 'package:totals/widgets/analytics/chart_data_utils.dart';
import 'package:totals/screens/insights_page.dart';
import 'package:totals/widgets/categorize_transaction_sheet.dart';
import 'package:totals/widgets/category_filter_button.dart';
import 'package:totals/widgets/category_filter_sheet.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/utils/account_identity.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  String? _selectedCard;
  String _selectedPeriod = 'Month';
  int? _selectedBankFilter;
  String? _selectedAccountFilter;
  String _sortBy = 'Date';
  String _chartType = 'Heatmap';
  String _barChartFlow = 'Expense';
  int _timeFrameOffset = 0;
  Set<int?> _selectedIncomeCategoryIds = {};
  Set<int?> _selectedExpenseCategoryIds = {};
  Set<String> _selectedReferences = {};

  late PageController _timeFramePageController;
  bool _isTransitioning = false;
  final Map<String, DateTime?> _transactionDateCache = {};
  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank> _banks = [];
  List<Account> _registeredAccounts = const <Account>[];

  @override
  void initState() {
    super.initState();
    _timeFramePageController = PageController(initialPage: 1);
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    try {
      final banks = await _bankConfigService.getBanks();
      if (mounted) {
        setState(() {
          _banks = banks;
        });
      }
    } catch (e) {
      print("debug: Error loading banks: $e");
    }
  }

  @override
  void dispose() {
    _timeFramePageController.dispose();
    super.dispose();
  }

  DateTime _getBaseDate([int? offset]) {
    final now = DateTime.now();
    final effectiveOffset = offset ?? _timeFrameOffset;
    if (effectiveOffset == 0) return now;

    if (_selectedPeriod == 'Week') {
      return now.add(Duration(days: effectiveOffset * 7));
    } else if (_selectedPeriod == 'Month') {
      return DateTime(now.year, now.month + effectiveOffset, now.day);
    } else {
      return DateTime(now.year + effectiveOffset, now.month, now.day);
    }
  }

  void _setSelectedPeriod(String period) {
    if (_timeFramePageController.hasClients) {
      _timeFramePageController.jumpToPage(1);
    }
    setState(() {
      _selectedPeriod = period;
      _timeFrameOffset = 0;
    });
  }

  void _setBarChartFlow(String flow) {
    final normalized = flow == 'Income' ? 'Income' : 'Expense';
    setState(() {
      _barChartFlow = normalized;
      _selectedCard = normalized;
    });
  }

  void _resetTimeFrame() {
    if (_timeFrameOffset == 0 || !_timeFramePageController.hasClients) return;
    _timeFramePageController.jumpToPage(1);
    setState(() {
      _timeFrameOffset = 0;
    });
  }

  void _navigateTimeFrame(bool forward) {
    if (!_timeFramePageController.hasClients) return;

    if (forward) {
      _timeFramePageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _timeFramePageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onTimeFramePageChanged(int page) {
    if (_isTransitioning) return;

    // Only handle edge pages (0 = previous, 2 = next)
    if (page == 0 || page == 2) {
      _isTransitioning = true;
      final newOffset = page == 0 ? _timeFrameOffset - 1 : _timeFrameOffset + 1;

      // Update offset and jump back to center in one frame
      setState(() {
        _timeFrameOffset = newOffset;
      });

      // Jump back to center page after the frame renders
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _timeFramePageController.hasClients) {
          _timeFramePageController.jumpToPage(1);
        }
        // Small delay to prevent rapid consecutive swipes from breaking
        Future.delayed(const Duration(milliseconds: 50), () {
          _isTransitioning = false;
        });
      });
    }
  }

  DateTime? _resolveTransactionDate(Transaction transaction) {
    final rawTime = transaction.time;
    if (rawTime == null || rawTime.isEmpty) return null;
    if (_transactionDateCache.containsKey(rawTime)) {
      return _transactionDateCache[rawTime];
    }
    try {
      final parsed = DateTime.parse(rawTime);
      _transactionDateCache[rawTime] = parsed;
      return parsed;
    } catch (_) {
      _transactionDateCache[rawTime] = null;
      return null;
    }
  }

  Map<int, List<AccountSummary>> _groupAccountsByBank(
      List<AccountSummary> accounts) {
    final grouped = <int, List<AccountSummary>>{};
    for (final account in accounts) {
      grouped
          .putIfAbsent(account.bankId, () => <AccountSummary>[])
          .add(account);
    }
    return grouped;
  }

  AccountSummary? _resolveSelectedAccount(List<AccountSummary> accounts) {
    if (_selectedAccountFilter == null || _selectedBankFilter == null) {
      return null;
    }
    for (final account in accounts) {
      if (account.accountNumber == _selectedAccountFilter &&
          account.bankId == _selectedBankFilter) {
        return account;
      }
    }
    return null;
  }

  bool _matchesSelectedAccount(
      Transaction transaction, AccountSummary account) {
    if (account.bankId == CashConstants.bankId) {
      return transaction.bankId == CashConstants.bankId &&
          transaction.accountNumber == account.accountNumber;
    }

    Bank? bank;
    for (final candidate in _banks) {
      if (candidate.id == account.bankId) {
        bank = candidate;
        break;
      }
    }
    if (bank == null) return false;

    Account? target;
    for (final candidate in _registeredAccounts) {
      if (candidate.bank == account.bankId &&
          registeredAccountNumbersMatch(
            bank,
            candidate.accountNumber,
            account.accountNumber,
          )) {
        target = candidate;
        break;
      }
    }
    if (target == null) return false;
    return transactionBelongsToAccount(
      transaction: transaction,
      account: target,
      bank: bank,
      accounts: _registeredAccounts,
    );
  }

  bool _hasMatchingAccount(
    Transaction transaction,
    Map<int, List<AccountSummary>> accountsByBank,
  ) {
    final bankId = transaction.bankId;
    if (bankId == null) return false;
    final bankAccounts = accountsByBank[bankId] ?? const <AccountSummary>[];
    if (bankAccounts.isEmpty) return false;
    // Keep unresolved legacy SMS in bank-level analytics; account-specific
    // filtering is applied separately with the ownership predicate above.
    return true;
  }

  bool _matchesBaseFilters(
    Transaction transaction,
    AccountSummary? selectedAccount,
  ) {
    if (_selectedCard == 'Income' && transaction.type != 'CREDIT') {
      return false;
    }
    if (_selectedCard == 'Expense' && transaction.type != 'DEBIT') {
      return false;
    }
    if (_selectedBankFilter != null &&
        transaction.bankId != _selectedBankFilter) {
      return false;
    }
    if (_selectedAccountFilter != null) {
      if (selectedAccount == null ||
          !_matchesSelectedAccount(transaction, selectedAccount)) {
        return false;
      }
    }
    return true;
  }

  List<Transaction> _filterByCategorySelections(
    List<Transaction> transactions,
    TransactionProvider provider,
  ) {
    if (_selectedIncomeCategoryIds.isEmpty &&
        _selectedExpenseCategoryIds.isEmpty) {
      return transactions;
    }

    final filtered = <Transaction>[];
    for (final transaction in transactions) {
      if (transaction.type == 'CREDIT') {
        if (provider.matchesCategoryFilterSelection(
          transaction,
          _selectedIncomeCategoryIds,
        )) {
          filtered.add(transaction);
        }
        continue;
      }
      if (transaction.type == 'DEBIT') {
        if (provider.matchesCategoryFilterSelection(
          transaction,
          _selectedExpenseCategoryIds,
        )) {
          filtered.add(transaction);
        }
        continue;
      }
      if (_selectedIncomeCategoryIds.isEmpty &&
          _selectedExpenseCategoryIds.isEmpty) {
        filtered.add(transaction);
      }
    }
    return filtered;
  }

  bool _matchesPeriod(DateTime transactionDate, DateTime baseDate) {
    if (_selectedPeriod == 'Week') {
      final baseDay = DateTime(baseDate.year, baseDate.month, baseDate.day);
      final daysSinceMonday = (baseDay.weekday - 1) % 7;
      final weekStart = baseDay.subtract(Duration(days: daysSinceMonday));
      final weekEnd = weekStart.add(const Duration(days: 6));
      final transactionDay = DateTime(
        transactionDate.year,
        transactionDate.month,
        transactionDate.day,
      );
      return !transactionDay.isBefore(weekStart) &&
          !transactionDay.isAfter(weekEnd);
    } else if (_selectedPeriod == 'Month') {
      return transactionDate.year == baseDate.year &&
          transactionDate.month == baseDate.month;
    } else {
      return transactionDate.year == baseDate.year;
    }
  }

  List<Transaction> _filterBaseTransactions(
    List<Transaction> allTransactions,
    Map<int, List<AccountSummary>> accountsByBank,
    AccountSummary? selectedAccount,
  ) {
    final filtered = <Transaction>[];
    for (final transaction in allTransactions) {
      if (!_hasMatchingAccount(transaction, accountsByBank)) {
        continue;
      }
      if (!_matchesBaseFilters(transaction, selectedAccount)) {
        continue;
      }
      filtered.add(transaction);
    }
    return filtered;
  }

  List<Transaction> _filterByPeriod(
    List<Transaction> transactions,
    DateTime baseDate,
  ) {
    final filtered = <Transaction>[];
    for (final transaction in transactions) {
      final transactionDate = _resolveTransactionDate(transaction);
      if (transactionDate == null) continue;
      if (_matchesPeriod(transactionDate, baseDate)) {
        filtered.add(transaction);
      }
    }
    return filtered;
  }

  List<Transaction> _filterTransactionsForBarChart(
    List<Transaction> allTransactions,
    Map<int, List<AccountSummary>> accountsByBank,
    AccountSummary? selectedAccount,
    TransactionProvider provider,
  ) {
    final filtered = <Transaction>[];
    for (final transaction in allTransactions) {
      if (!_hasMatchingAccount(transaction, accountsByBank)) {
        continue;
      }
      if (provider.isSelfTransfer(transaction)) {
        continue;
      }
      if (_selectedBankFilter != null &&
          transaction.bankId != _selectedBankFilter) {
        continue;
      }
      if (selectedAccount != null &&
          !_matchesSelectedAccount(transaction, selectedAccount)) {
        continue;
      }
      filtered.add(transaction);
    }
    return filtered;
  }

  List<Transaction> _filterTransactionsForPnl(
    List<Transaction> allTransactions,
    AccountSummary? selectedAccount,
  ) {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final filtered = <Transaction>[];
    for (final transaction in allTransactions) {
      if (provider.isSelfTransfer(transaction)) {
        continue;
      }
      if (_selectedCard == 'Income' && transaction.type != 'CREDIT') {
        continue;
      }
      if (_selectedCard == 'Income' &&
          provider.isReimbursementTransaction(transaction)) {
        continue;
      }
      if (_selectedCard == 'Expense' && transaction.type != 'DEBIT') {
        continue;
      }
      if (_selectedBankFilter != null &&
          transaction.bankId != _selectedBankFilter) {
        continue;
      }
      if (selectedAccount != null &&
          !_matchesSelectedAccount(transaction, selectedAccount)) {
        continue;
      }
      filtered.add(transaction);
    }
    return filtered;
  }

  List<ChartDataPoint> _getChartData(
    List<Transaction> transactions,
    DateTime baseDate,
    TransactionProvider provider,
  ) {
    final chartTransactions = transactions
        .map((transaction) {
          final amount = transaction.type == 'CREDIT'
              ? provider.incomeAmountForTransaction(transaction)
              : transaction.type == 'DEBIT'
                  ? provider.netExpenseAmountForTransaction(transaction)
                  : transaction.amount.abs();
          return transaction.copyWith(amount: amount);
        })
        .where((transaction) => transaction.amount > 0)
        .toList(growable: false);
    return ChartDataUtils.getChartData(
      chartTransactions,
      _selectedPeriod,
      baseDate,
      dateForTransaction: _resolveTransactionDate,
    );
  }

  List<Transaction> _transactionsForCalendarCell(
    DateTime cellDate,
    List<Transaction> transactions,
    TransactionProvider provider,
    AccountSummary? selectedAccount,
  ) {
    final filtered = transactions.where((transaction) {
      final transactionDate = _resolveTransactionDate(transaction);
      if (transactionDate == null) return false;
      if (_selectedPeriod == 'Year') {
        return transactionDate.year == cellDate.year &&
            transactionDate.month == cellDate.month;
      }
      return transactionDate.year == cellDate.year &&
          transactionDate.month == cellDate.month &&
          transactionDate.day == cellDate.day;
    }).toList();

    final selfTransfers = <Transaction>[];
    for (final transaction in provider.allTransactions) {
      if (!provider.isSelfTransfer(transaction)) continue;
      final transactionDate = _resolveTransactionDate(transaction);
      if (transactionDate == null) continue;
      if (_selectedPeriod == 'Year') {
        if (transactionDate.year != cellDate.year ||
            transactionDate.month != cellDate.month) {
          continue;
        }
      } else if (transactionDate.year != cellDate.year ||
          transactionDate.month != cellDate.month ||
          transactionDate.day != cellDate.day) {
        continue;
      }
      if (_selectedBankFilter != null &&
          transaction.bankId != _selectedBankFilter) {
        continue;
      }
      if (selectedAccount != null &&
          !_matchesSelectedAccount(transaction, selectedAccount)) {
        continue;
      }
      selfTransfers.add(transaction);
    }

    if (selfTransfers.isEmpty) {
      return filtered;
    }

    final references = {
      for (final transaction in filtered) transaction.reference,
    };
    for (final transaction in selfTransfers) {
      if (references.add(transaction.reference)) {
        filtered.add(transaction);
      }
    }
    return filtered;
  }

  String _formatCalendarSelectionLabel(DateTime cellDate) {
    if (_selectedPeriod == 'Year') {
      return DateFormat('MMMM yyyy').format(cellDate);
    }
    return DateFormat('MMM dd, yyyy').format(cellDate);
  }

  void _openCalendarTransactions(
    DateTime cellDate,
    List<Transaction> transactions,
    TransactionProvider provider,
    AccountSummary? selectedAccount,
  ) {
    final filtered = _transactionsForCalendarCell(
      cellDate,
      transactions,
      provider,
      selectedAccount,
    );
    final subtitle = _formatCalendarSelectionLabel(cellDate);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionsForPeriodPage(
          transactions: filtered,
          provider: provider,
          title: 'Transactions',
          subtitle: subtitle,
          dimSelfTransfers: true,
        ),
      ),
    );
  }

  Future<void> _openCategoryFilterSheet({
    required TransactionProvider provider,
    required String flow,
  }) async {
    final currentSelection = flow == 'income'
        ? _selectedIncomeCategoryIds
        : _selectedExpenseCategoryIds;
    final result = await showCategoryFilterSheet(
      context: context,
      provider: provider,
      selectedCategoryIds: currentSelection,
      title: flow == 'income'
          ? 'Filter income categories'
          : 'Filter expense categories',
      flow: flow,
    );
    if (result == null) return;

    setState(() {
      if (flow == 'income') {
        _selectedIncomeCategoryIds = result.toSet();
      } else {
        _selectedExpenseCategoryIds = result.toSet();
      }
    });
  }

  bool get _isSelectionMode => _selectedReferences.isNotEmpty;

  void _toggleSelection(Transaction transaction) {
    setState(() {
      if (_selectedReferences.contains(transaction.reference)) {
        _selectedReferences.remove(transaction.reference);
      } else {
        _selectedReferences.add(transaction.reference);
      }
    });
  }

  void _clearSelection() {
    if (_selectedReferences.isEmpty) return;
    setState(() {
      _selectedReferences.clear();
    });
  }

  void _toggleSelectAll(List<Transaction> transactions) {
    final references =
        transactions.map((transaction) => transaction.reference).toSet();
    setState(() {
      if (references.isEmpty) {
        _selectedReferences.clear();
        return;
      }
      final isAllSelected = _selectedReferences.length == references.length &&
          _selectedReferences.containsAll(references);
      if (isAllSelected) {
        _selectedReferences.clear();
      } else {
        _selectedReferences = references;
      }
    });
  }

  void _invertSelection(List<Transaction> transactions) {
    final references =
        transactions.map((transaction) => transaction.reference).toSet();
    setState(() {
      _selectedReferences = references.difference(_selectedReferences);
    });
  }

  void _pruneSelection(Set<String> validReferences) {
    if (_selectedReferences.isEmpty) return;
    if (_selectedReferences.every(validReferences.contains)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedReferences.removeWhere(
          (reference) => !validReferences.contains(reference),
        );
      });
    });
  }

  Future<void> _confirmDeleteSelected(TransactionProvider provider) async {
    if (_selectedReferences.isEmpty) return;
    final count = _selectedReferences.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Delete $count transaction${count == 1 ? '' : 's'}?'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await provider.deleteTransactionsByReferences(_selectedReferences);
    if (!mounted) return;
    setState(() {
      _selectedReferences.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        final allTransactions = provider.allTransactions;
        final bankSummaries = provider.bankSummaries;
        final accounts = provider.accountSummaries;
        _registeredAccounts = provider.accounts;
        final baseDate = _getBaseDate();
        final accountsByBank = _groupAccountsByBank(accounts);
        final selectedAccount = _resolveSelectedAccount(accounts);

        final baseFilteredTransactions = _filterBaseTransactions(
          allTransactions,
          accountsByBank,
          selectedAccount,
        );
        final categoryFilteredBase = _filterByCategorySelections(
          baseFilteredTransactions,
          provider,
        );
        final filteredTransactions =
            _filterByPeriod(categoryFilteredBase, baseDate);
        _pruneSelection(filteredTransactions
            .map((transaction) => transaction.reference)
            .toSet());
        final barChartTransactions = _filterTransactionsForBarChart(
          allTransactions,
          accountsByBank,
          selectedAccount,
          provider,
        );
        final pnlTransactions = _filterByCategorySelections(
          _filterTransactionsForPnl(allTransactions, selectedAccount),
          provider,
        );

        final chartData =
            _getChartData(filteredTransactions, baseDate, provider);
        final chartDataByOffset = <int, List<ChartDataPoint>>{};

        List<ChartDataPoint> getChartDataForOffset(int offset) {
          return chartDataByOffset.putIfAbsent(offset, () {
            final offsetDate = _getBaseDate(offset);
            final periodFiltered = _filterByPeriod(
              categoryFilteredBase,
              offsetDate,
            );
            return _getChartData(periodFiltered, offsetDate, provider);
          });
        }

        final maxValue = chartData.isEmpty
            ? 5000.0
            : (chartData.map((e) => e.value).reduce((a, b) => a > b ? a : b) *
                    1.2)
                .clamp(100.0, double.infinity);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Statistics',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_chartType != 'Bar Chart') ...[
                      TimePeriodSelector(
                        selectedPeriod: _selectedPeriod,
                        onPeriodChanged: _setSelectedPeriod,
                        onPeriodChange: () {
                          if (_timeFramePageController.hasClients) {
                            _timeFramePageController.jumpToPage(1);
                          }
                        },
                        onInsightsTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => InsightsPage(
                                transactions: filteredTransactions,
                                periodLabel: 'Based on $_selectedPeriod view',
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                    FilterSection(
                      bankSummaries: bankSummaries,
                      selectedBankFilter: _selectedBankFilter,
                      selectedAccountFilter: _selectedAccountFilter,
                      accounts: accounts,
                      onBankFilterChanged: (bankId) {
                        setState(() {
                          _selectedBankFilter = bankId;
                          _selectedAccountFilter = null;
                        });
                      },
                      onAccountFilterChanged: (accountNumber) {
                        setState(() {
                          _selectedAccountFilter = accountNumber;
                        });
                      },
                    ),
                    if (_selectedBankFilter != null) const SizedBox(height: 16),
                    const SizedBox(height: 24),
                    if (_chartType != 'Bar Chart') ...[
                      IncomeExpenseCards(
                        selectedCard: _selectedCard,
                        selectedPeriod: _selectedPeriod,
                        selectedBankFilter: _selectedBankFilter,
                        selectedAccountFilter: _selectedAccountFilter,
                        selectedIncomeCategoryIds: _selectedIncomeCategoryIds,
                        selectedExpenseCategoryIds: _selectedExpenseCategoryIds,
                        getBaseDate: _getBaseDate,
                        onCardSelected: (card) {
                          setState(() {
                            _selectedCard = card;
                            if (card != null) {
                              _barChartFlow = card;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        CategoryFilterIconButton(
                          icon: Icons.toc_rounded,
                          selectedCount: _selectedIncomeCategoryIds.length,
                          tooltip: 'Income categories',
                          iconColor: Colors.green,
                          flipIconHorizontally: true,
                          onTap: () => _openCategoryFilterSheet(
                            provider: provider,
                            flow: 'income',
                          ),
                        ),
                        const SizedBox(width: 8),
                        CategoryFilterIconButton(
                          icon: Icons.toc_rounded,
                          selectedCount: _selectedExpenseCategoryIds.length,
                          tooltip: 'Expense categories',
                          iconColor: Theme.of(context).colorScheme.error,
                          flipIconHorizontally: true,
                          onTap: () => _openCategoryFilterSheet(
                            provider: provider,
                            flow: 'expense',
                          ),
                        ),
                        const SizedBox(width: 8),
                        ChartTypeSelector(
                          chartType: _chartType,
                          onChartTypeChanged: (type) {
                            setState(() {
                              _chartType = type;
                              if (type == 'Bar Chart') {
                                _selectedCard = _barChartFlow;
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ChartContainer(
                      data: chartData,
                      maxValue: maxValue,
                      chartType: _chartType,
                      selectedPeriod: _selectedPeriod,
                      timeFrameOffset: _timeFrameOffset,
                      timeFramePageController: _timeFramePageController,
                      onTimeFramePageChanged: _onTimeFramePageChanged,
                      getBaseDate: _getBaseDate,
                      getChartDataForOffset: getChartDataForOffset,
                      selectedCard: _selectedCard,
                      barChartFlow: _barChartFlow,
                      barChartTransactions: barChartTransactions,
                      pnlTransactions: pnlTransactions,
                      selectedIncomeCategoryIds: _selectedIncomeCategoryIds,
                      selectedExpenseCategoryIds: _selectedExpenseCategoryIds,
                      dateForTransaction: _resolveTransactionDate,
                      onBarChartFlowChanged: _setBarChartFlow,
                      onBarChartPeriodChanged: _setSelectedPeriod,
                      onCalendarCellSelected: (date) {
                        _openCalendarTransactions(
                          date,
                          pnlTransactions,
                          provider,
                          selectedAccount,
                        );
                      },
                      onResetTimeFrame: _resetTimeFrame,
                      onNavigateTimeFrame: _navigateTimeFrame,
                    ),
                    // const SizedBox(height: 24),
                    // CategoryBreakdown(
                    //   transactions: filteredTransactions,
                    //   provider: provider,
                    //   selectedCard: _selectedCard,
                    // ),
                    const SizedBox(height: 24),
                    if (_isSelectionMode) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: 'Clear selection',
                                onPressed: _clearSelection,
                              ),
                              Text(
                                '${_selectedReferences.length} selected',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Select all',
                                icon: const Icon(Icons.select_all),
                                onPressed: () =>
                                    _toggleSelectAll(filteredTransactions),
                              ),
                              IconButton(
                                tooltip: 'Invert selection',
                                icon: const Icon(Icons.swap_horiz),
                                onPressed: () =>
                                    _invertSelection(filteredTransactions),
                              ),
                              IconButton(
                                tooltip: 'Delete selected',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    _confirmDeleteSelected(provider),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    TransactionsList(
                      transactions: filteredTransactions,
                      sortBy: _sortBy,
                      provider: provider,
                      selectionMode: _isSelectionMode,
                      selectedReferences: _selectedReferences,
                      onTransactionTap: (transaction) async {
                        if (_isSelectionMode) {
                          _toggleSelection(transaction);
                          return;
                        }
                        await showCategorizeTransactionSheet(
                          context: context,
                          provider: provider,
                          transaction: transaction,
                        );
                      },
                      onTransactionLongPress: (transaction) {
                        _toggleSelection(transaction);
                      },
                      onSortChanged: (sort) {
                        setState(() {
                          _sortBy = sort;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
