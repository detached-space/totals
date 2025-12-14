import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/widgets/analytics/time_period_selector.dart';
import 'package:totals/widgets/analytics/filter_section.dart';
import 'package:totals/widgets/analytics/income_expense_cards.dart';
import 'package:totals/widgets/analytics/chart_type_selector.dart';
import 'package:totals/widgets/analytics/chart_container.dart';
import 'package:totals/widgets/analytics/transactions_list.dart';
import 'package:totals/widgets/analytics/loading_states.dart';
import 'package:totals/widgets/analytics/chart_data_point.dart';
import 'package:totals/widgets/analytics/chart_data_utils.dart';

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
  String _chartType = 'P&L Calendar';
  int _timeFrameOffset = 0;
  
  late PageController _timeFramePageController;
  bool _isTransitioning = false;
  bool _isLoadingData = false;
  int? _pendingTimeFrameOffset;

  @override
  void initState() {
    super.initState();
    _timeFramePageController = PageController(initialPage: 1);
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
    
    _isTransitioning = true;
    setState(() {
      _isLoadingData = true;
    });
    
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) {
        _isTransitioning = false;
        _isLoadingData = false;
        return;
      }
      
      if (page == 0) {
        _pendingTimeFrameOffset = _timeFrameOffset - 1;
        if (mounted && _timeFramePageController.hasClients) {
          _timeFramePageController.jumpToPage(1);
        }
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            setState(() {
              _timeFrameOffset = _pendingTimeFrameOffset!;
              _pendingTimeFrameOffset = null;
            });
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                setState(() {
                  _isTransitioning = false;
                  _isLoadingData = false;
                });
              }
            });
          }
        });
      } else if (page == 2) {
        _pendingTimeFrameOffset = _timeFrameOffset + 1;
        if (mounted && _timeFramePageController.hasClients) {
          _timeFramePageController.jumpToPage(1);
        }
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            setState(() {
              _timeFrameOffset = _pendingTimeFrameOffset!;
              _pendingTimeFrameOffset = null;
            });
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                setState(() {
                  _isTransitioning = false;
                  _isLoadingData = false;
                });
              }
            });
          }
        });
      } else {
        setState(() {
          _isTransitioning = false;
          _isLoadingData = false;
        });
      }
    });
  }

  List<Transaction> _filterTransactions(List<Transaction> allTransactions, List accounts, DateTime now) {
    return allTransactions.where((t) {
      bool matchesCard = true;
      if (_selectedCard == 'Income') {
        matchesCard = t.type == 'CREDIT';
      } else if (_selectedCard == 'Expense') {
        matchesCard = t.type == 'DEBIT';
      }
      
      bool matchesBank = _selectedBankFilter == null || t.bankId == _selectedBankFilter;
      
      bool matchesAccount = true;
      if (_selectedAccountFilter != null && _selectedBankFilter != null) {
        final account = accounts.firstWhere(
          (a) => a.accountNumber == _selectedAccountFilter && a.bankId == _selectedBankFilter,
          orElse: () => accounts.firstWhere((a) => a.bankId == _selectedBankFilter, orElse: () => accounts.first),
        );
        
        if (account.bankId == 1 && t.accountNumber != null && account.accountNumber.length >= 4) {
          matchesAccount = t.accountNumber!.substring(t.accountNumber!.length - 4) ==
              account.accountNumber.substring(account.accountNumber.length - 4);
        } else if (account.bankId == 4 && t.accountNumber != null && account.accountNumber.length >= 3) {
          matchesAccount = t.accountNumber!.substring(t.accountNumber!.length - 3) ==
              account.accountNumber.substring(account.accountNumber.length - 3);
        } else if (account.bankId == 3 && t.accountNumber != null && account.accountNumber.length >= 2) {
          matchesAccount = t.accountNumber!.substring(t.accountNumber!.length - 2) ==
              account.accountNumber.substring(account.accountNumber.length - 2);
        } else {
          matchesAccount = t.accountNumber == account.accountNumber;
        }
      }
      
      bool matchesPeriod = true;
      if (t.time != null) {
        try {
          final transactionDate = DateTime.parse(t.time!);
          if (_selectedPeriod == 'Week') {
            int daysSinceMonday = (now.weekday - 1) % 7;
            final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysSinceMonday));
            matchesPeriod = transactionDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
                           transactionDate.isBefore(now.add(const Duration(days: 1)));
          } else if (_selectedPeriod == 'Month') {
            matchesPeriod = transactionDate.year == now.year && transactionDate.month == now.month;
          } else if (_selectedPeriod == 'Year') {
            matchesPeriod = transactionDate.year == now.year;
          }
        } catch (e) {
          matchesPeriod = false;
        }
      } else {
        matchesPeriod = false;
      }
      
      return matchesCard && matchesBank && matchesAccount && matchesPeriod;
    }).toList();
  }

  List<ChartDataPoint> _getChartData(
    List<Transaction> transactions,
    String period,
    int? bankFilter,
    String? accountFilter, {
    DateTime? baseDate,
  }) {
    var filteredTransactions = transactions;
    if (bankFilter != null) {
      filteredTransactions = transactions.where((t) => t.bankId == bankFilter).toList();
    }
    
    final effectiveBaseDate = baseDate ?? _getBaseDate();
    return ChartDataUtils.getChartData(filteredTransactions, period, effectiveBaseDate);
  }

  List<ChartDataPoint> _getChartDataForOffset(List<ChartDataPoint> baseData, int offset) {
    final baseDate = _getBaseDate(offset);
    final allTransactions = Provider.of<TransactionProvider>(context, listen: false).allTransactions;
    final accounts = Provider.of<TransactionProvider>(context, listen: false).accountSummaries;
    
    final filteredTransactions = allTransactions.where((t) {
      bool matchesCard = true;
      if (_selectedCard == 'Income') {
        matchesCard = t.type == 'CREDIT';
      } else if (_selectedCard == 'Expense') {
        matchesCard = t.type == 'DEBIT';
      }
      
      bool matchesBank = _selectedBankFilter == null || t.bankId == _selectedBankFilter;
      
      bool matchesAccount = true;
      if (_selectedAccountFilter != null && _selectedBankFilter != null) {
        final account = accounts.firstWhere(
          (a) => a.accountNumber == _selectedAccountFilter && a.bankId == _selectedBankFilter,
          orElse: () => accounts.firstWhere((a) => a.bankId == _selectedBankFilter, orElse: () => accounts.first),
        );
        
        if (account.bankId == 1 && t.accountNumber != null && account.accountNumber.length >= 4) {
          matchesAccount = t.accountNumber!.substring(t.accountNumber!.length - 4) ==
              account.accountNumber.substring(account.accountNumber.length - 4);
        } else if (account.bankId == 4 && t.accountNumber != null && account.accountNumber.length >= 3) {
          matchesAccount = t.accountNumber!.substring(t.accountNumber!.length - 3) ==
              account.accountNumber.substring(account.accountNumber.length - 3);
        } else if (account.bankId == 3 && t.accountNumber != null && account.accountNumber.length >= 2) {
          matchesAccount = t.accountNumber!.substring(t.accountNumber!.length - 2) ==
              account.accountNumber.substring(account.accountNumber.length - 2);
        } else {
          matchesAccount = t.accountNumber == account.accountNumber;
        }
      }
      
      bool matchesPeriod = true;
      if (t.time != null) {
        try {
          final transactionDate = DateTime.parse(t.time!);
          if (_selectedPeriod == 'Week') {
            int daysSinceMonday = (baseDate.weekday - 1) % 7;
            final weekStart = DateTime(baseDate.year, baseDate.month, baseDate.day).subtract(Duration(days: daysSinceMonday));
            matchesPeriod = transactionDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
                           transactionDate.isBefore(baseDate.add(const Duration(days: 1)));
          } else if (_selectedPeriod == 'Month') {
            matchesPeriod = transactionDate.year == baseDate.year && transactionDate.month == baseDate.month;
          } else if (_selectedPeriod == 'Year') {
            matchesPeriod = transactionDate.year == baseDate.year;
          }
        } catch (e) {
          matchesPeriod = false;
        }
      } else {
        matchesPeriod = false;
      }
      
      return matchesCard && matchesBank && matchesAccount && matchesPeriod;
    }).toList();
    
    return _getChartData(
      filteredTransactions, 
      _selectedPeriod, 
      _selectedBankFilter, 
      _selectedAccountFilter,
      baseDate: baseDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        final allTransactions = provider.allTransactions;
        final bankSummaries = provider.bankSummaries;
        final accounts = provider.accountSummaries;
        
        final now = _getBaseDate();
        final filteredTransactions = _filterTransactions(allTransactions, accounts, now);

        final chartData = _getChartData(filteredTransactions, _selectedPeriod, _selectedBankFilter, _selectedAccountFilter);
        final maxValue = chartData.isEmpty 
            ? 5000.0 
            : (chartData.map((e) => e.value).reduce((a, b) => a > b ? a : b) * 1.2).clamp(100.0, double.infinity);

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

                    _isLoadingData 
                        ? const LoadingIncomeExpenseCards()
                        : IncomeExpenseCards(
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
                      pendingTimeFrameOffset: _pendingTimeFrameOffset,
                      isLoadingData: _isLoadingData,
                      timeFramePageController: _timeFramePageController,
                      onTimeFramePageChanged: _onTimeFramePageChanged,
                      getBaseDate: _getBaseDate,
                      getChartDataForOffset: _getChartDataForOffset,
                      selectedCard: _selectedCard,
                      selectedBankFilter: _selectedBankFilter,
                      selectedAccountFilter: _selectedAccountFilter,
                      onResetTimeFrame: _resetTimeFrame,
                      onNavigateTimeFrame: _navigateTimeFrame,
                    ),
                    const SizedBox(height: 24),

                    _isLoadingData 
                        ? const LoadingTransactionsList()
                        : TransactionsList(
                            transactions: filteredTransactions,
                            sortBy: _sortBy,
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
