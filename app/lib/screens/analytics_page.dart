import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:intl/intl.dart';
import 'package:totals/screens/transactions_for_period_page.dart';
import 'package:totals/widgets/analytics/time_period_selector.dart';
import 'package:totals/widgets/analytics/filter_section.dart';
import 'package:totals/widgets/analytics/income_expense_cards.dart';
import 'package:totals/widgets/analytics/chart_type_selector.dart';
import 'package:totals/widgets/analytics/chart_container.dart';
import 'package:totals/widgets/analytics/category_breakdown.dart';
import 'package:totals/widgets/analytics/transactions_list.dart';
import 'package:totals/widgets/analytics/chart_data_point.dart';
import 'package:totals/widgets/analytics/chart_data_utils.dart';
import 'package:totals/widgets/categorize_transaction_sheet.dart';

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
  int _timeFrameOffset = 0;

  late PageController _timeFramePageController;
  bool _isTransitioning = false;
  final Map<String, DateTime?> _transactionDateCache = {};
  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank> _banks = [];

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
    if (accounts.isEmpty) return null;
    return accounts.firstWhere(
      (a) =>
          a.accountNumber == _selectedAccountFilter &&
          a.bankId == _selectedBankFilter,
      orElse: () => accounts.firstWhere(
        (a) => a.bankId == _selectedBankFilter,
        orElse: () => accounts.first,
      ),
    );
  }

  bool _matchesSelectedAccount(
      Transaction transaction, AccountSummary account) {
    final txnAccount = transaction.accountNumber;
    if (txnAccount == null || txnAccount.isEmpty) {
      return transaction.bankId == account.bankId;
    }

    try {
      final bank = _banks.firstWhere((b) => b.id == account.bankId);

      if (bank.uniformMasking == true && bank.maskPattern != null) {
        return txnAccount.substring(txnAccount.length - bank.maskPattern!) ==
            account.accountNumber
                .substring(account.accountNumber.length - bank.maskPattern!);
      } else if (bank.uniformMasking == false) {
        // Match by bankId only
        return transaction.bankId == account.bankId;
      } else {
        // Exact match (uniformMasking is null)
        return txnAccount == account.accountNumber;
      }
    } catch (e) {
      // Bank not found in database, fallback to bankId match
      return transaction.bankId == account.bankId;
    }
  }

  bool _hasMatchingAccount(
    Transaction transaction,
    Map<int, List<AccountSummary>> accountsByBank,
  ) {
    final bankId = transaction.bankId;
    if (bankId == null) return false;
    final bankAccounts = accountsByBank[bankId] ?? const <AccountSummary>[];
    if (bankAccounts.isEmpty) return false;

    if (transaction.accountNumber != null &&
        transaction.accountNumber!.isNotEmpty) {
      for (final account in bankAccounts) {
        bool matches = false;

        try {
          final bank = _banks.firstWhere((b) => b.id == account.bankId);

          if (bank.uniformMasking == true && bank.maskPattern != null) {
            // Match last N digits based on mask pattern
            if (transaction.accountNumber!.length >= bank.maskPattern! &&
                account.accountNumber.length >= bank.maskPattern!) {
              matches = transaction.accountNumber!.substring(
                      transaction.accountNumber!.length - bank.maskPattern!) ==
                  account.accountNumber.substring(
                      account.accountNumber.length - bank.maskPattern!);
            }
          } else if (bank.uniformMasking == false) {
            // Match by bankId only
            matches = true;
          } else {
            // Exact match (uniformMasking is null)
            matches = transaction.accountNumber == account.accountNumber;
          }
        } catch (e) {
          // Bank not found in database, fallback to exact match
          matches = transaction.accountNumber == account.accountNumber;
        }

        if (matches) {
          return true;
        }
      }
      return false;
    } else {
      return bankAccounts.length == 1;
    }
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
    if (selectedAccount != null &&
        !_matchesSelectedAccount(transaction, selectedAccount)) {
      return false;
    }
    return true;
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
      List<Transaction> allTransactions) {
    if (_selectedBankFilter == null) return allTransactions;
    return allTransactions
        .where((t) => t.bankId == _selectedBankFilter)
        .toList();
  }

  List<Transaction> _filterTransactionsForPnl(
    List<Transaction> allTransactions,
    AccountSummary? selectedAccount,
  ) {
    final filtered = <Transaction>[];
    for (final transaction in allTransactions) {
      if (_selectedCard == 'Income' && transaction.type != 'CREDIT') {
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
  ) {
    return ChartDataUtils.getChartData(
      transactions,
      _selectedPeriod,
      baseDate,
      dateForTransaction: _resolveTransactionDate,
    );
  }

  List<Transaction> _transactionsForCalendarCell(
    DateTime cellDate,
    List<Transaction> transactions,
  ) {
    return transactions.where((transaction) {
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
  ) {
    final filtered = _transactionsForCalendarCell(cellDate, transactions);
    final subtitle = _formatCalendarSelectionLabel(cellDate);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionsForPeriodPage(
          transactions: filtered,
          provider: provider,
          title: 'Transactions',
          subtitle: subtitle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        final allTransactions = provider.allTransactions;
        final bankSummaries = provider.bankSummaries;
        final accounts = provider.accountSummaries;

        final baseDate = _getBaseDate();
        final accountsByBank = _groupAccountsByBank(accounts);
        final selectedAccount = _resolveSelectedAccount(accounts);

        final baseFilteredTransactions = _filterBaseTransactions(
          allTransactions,
          accountsByBank,
          selectedAccount,
        );
        final filteredTransactions =
            _filterByPeriod(baseFilteredTransactions, baseDate);
        final barChartTransactions =
            _filterTransactionsForBarChart(allTransactions);
        final pnlTransactions =
            _filterTransactionsForPnl(allTransactions, selectedAccount);

        final chartData = _getChartData(filteredTransactions, baseDate);
        final chartDataByOffset = <int, List<ChartDataPoint>>{};

        List<ChartDataPoint> getChartDataForOffset(int offset) {
          return chartDataByOffset.putIfAbsent(offset, () {
            final offsetDate = _getBaseDate(offset);
            final periodFiltered = _filterByPeriod(
              baseFilteredTransactions,
              offsetDate,
            );
            return _getChartData(periodFiltered, offsetDate);
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
                    const SizedBox(height: 24),
                    TimePeriodSelector(
                      selectedPeriod: _selectedPeriod,
                      onPeriodChanged: (period) {
                        setState(() {
                          _selectedPeriod = period;
                          _timeFrameOffset = 0;
                        });
                      },
                      onPeriodChange: () {
                        if (_timeFramePageController.hasClients) {
                          _timeFramePageController.jumpToPage(1);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
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
                    IncomeExpenseCards(
                      selectedCard: _selectedCard,
                      selectedPeriod: _selectedPeriod,
                      selectedBankFilter: _selectedBankFilter,
                      selectedAccountFilter: _selectedAccountFilter,
                      getBaseDate: _getBaseDate,
                      onCardSelected: (card) {
                        setState(() {
                          _selectedCard = card;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ChartTypeSelector(
                          chartType: _chartType,
                          onChartTypeChanged: (type) {
                            setState(() {
                              _chartType = type;
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
                      barChartTransactions: barChartTransactions,
                      pnlTransactions: pnlTransactions,
                      dateForTransaction: _resolveTransactionDate,
                      onCalendarCellSelected: (date) {
                        _openCalendarTransactions(
                          date,
                          pnlTransactions,
                          provider,
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
                    TransactionsList(
                      transactions: filteredTransactions,
                      sortBy: _sortBy,
                      provider: provider,
                      onTransactionTap: (transaction) async {
                        await showCategorizeTransactionSheet(
                          context: context,
                          provider: provider,
                          transaction: transaction,
                        );
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
