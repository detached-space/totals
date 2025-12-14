import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/transaction.dart';
import 'package:intl/intl.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> with SingleTickerProviderStateMixin {
  String? _selectedCard; // null, 'Income', or 'Expense'
  String _selectedPeriod = 'Month'; // 'Week', 'Month', 'Year'
  int? _selectedBankFilter; // null for 'All', or bankId
  String? _selectedAccountFilter; // null for 'All', or accountNumber
  String _sortBy = 'Date'; // 'Date', 'Amount', 'Reference'
  String _chartType = 'P&L Calendar'; // 'Line Chart', 'Bar Chart', 'Pie Chart', 'P&L Calendar'
  int _timeFrameOffset = 0; // 0 = current, -1 = previous, +1 = next
  
  late AnimationController _slideAnimationController;
  late Animation<Offset> _slideAnimation;
  bool _isNavigating = false;
  bool _leftButtonPressed = false;
  bool _rightButtonPressed = false;
  double _dragOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _slideAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideAnimationController,
      curve: Curves.easeInOut,
    ));
    // Initialize animation at zero
    _slideAnimationController.value = 0.0;
    _dragOffset = 0.0;
  }

  @override
  void dispose() {
    _slideAnimationController.dispose();
    super.dispose();
  }

  DateTime _getBaseDate() {
    final now = DateTime.now();
    if (_timeFrameOffset == 0) return now;
    
    if (_selectedPeriod == 'Week') {
      return now.add(Duration(days: _timeFrameOffset * 7));
    } else if (_selectedPeriod == 'Month') {
      return DateTime(now.year, now.month + _timeFrameOffset, now.day);
    } else { // Year
      return DateTime(now.year + _timeFrameOffset, now.month, now.day);
    }
  }

  Future<void> _navigateTimeFrame(bool forward) async {
    if (_isNavigating) return;
    
    setState(() {
      _isNavigating = true;
      _dragOffset = 0.0; // Reset drag offset
    });

    // Set animation direction
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(forward ? -1.0 : 1.0, 0),
    ).animate(CurvedAnimation(
      parent: _slideAnimationController,
      curve: Curves.easeInOut,
    ));

    // Start slide out animation
    await _slideAnimationController.forward();

    // Update the offset
    setState(() {
      if (forward) {
        _timeFrameOffset++;
      } else {
        _timeFrameOffset--;
      }
    });

    // Reset animation for slide in
    _slideAnimation = Tween<Offset>(
      begin: Offset(forward ? 1.0 : -1.0, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideAnimationController,
      curve: Curves.easeInOut,
    ));

    // Reset controller and slide in
    _slideAnimationController.reset();
    await _slideAnimationController.forward();

    setState(() {
      _isNavigating = false;
      _dragOffset = 0.0; // Ensure drag offset is reset
    });
  }

  Future<void> _resetTimeFrame() async {
    if (_isNavigating || _timeFrameOffset == 0) return;
    
    final offsetDirection = _timeFrameOffset > 0 ? 1.0 : -1.0;
    
    setState(() {
      _isNavigating = true;
      _dragOffset = 0.0; // Reset drag offset
    });

    // Set animation direction
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(-offsetDirection, 0),
    ).animate(CurvedAnimation(
      parent: _slideAnimationController,
      curve: Curves.easeInOut,
    ));

    // Start slide out animation
    await _slideAnimationController.forward();

    // Update the offset
    setState(() {
      _timeFrameOffset = 0;
    });

    // Reset animation for slide in
    _slideAnimation = Tween<Offset>(
      begin: Offset(offsetDirection, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideAnimationController,
      curve: Curves.easeInOut,
    ));

    // Reset controller and slide in
    _slideAnimationController.reset();
    await _slideAnimationController.forward();

    setState(() {
      _isNavigating = false;
      _dragOffset = 0.0; // Ensure drag offset is reset
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        final allTransactions = provider.allTransactions;
        final bankSummaries = provider.bankSummaries;
        final accounts = provider.accountSummaries;
        
        // Filter transactions based on selected card, period, and bank
        final now = _getBaseDate();
        final filteredTransactions = allTransactions.where((t) {
          // Filter by selected card (Income/Expense)
          bool matchesCard = true;
          if (_selectedCard == 'Income') {
            matchesCard = t.type == 'CREDIT';
          } else if (_selectedCard == 'Expense') {
            matchesCard = t.type == 'DEBIT';
          }
          
          // Filter by bank if selected
          bool matchesBank = _selectedBankFilter == null || t.bankId == _selectedBankFilter;
          
          // Filter by account if selected
          bool matchesAccount = true;
          if (_selectedAccountFilter != null && _selectedBankFilter != null) {
            // Match account number (handle different bank matching logic)
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
          
          // Filter by period
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
        
        // Calculate totals for the selected type
        final selectedTotal = filteredTransactions
            .fold(0.0, (sum, t) => sum + t.amount);
        
        // Calculate income and expense totals for display
        final income = allTransactions
            .where((t) => t.type == 'CREDIT')
            .fold(0.0, (sum, t) => sum + t.amount);
        final expenses = allTransactions
            .where((t) => t.type == 'DEBIT')
            .fold(0.0, (sum, t) => sum + t.amount);

        // Get chart data based on selected period and filtered transactions
        final chartData = _getChartData(filteredTransactions, _selectedPeriod, _selectedBankFilter, _selectedAccountFilter);
        final maxValue = chartData.isEmpty 
            ? 5000.0 
            : (chartData.map((e) => e.value).reduce((a, b) => a > b ? a : b) * 1.2).clamp(100.0, double.infinity);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Statistics Title
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

                    // Time Period Selector
                    _buildTimePeriodSelector(),
                    const SizedBox(height: 24),

                    // Bank Filter Selector
                    _buildFilterSection(bankSummaries),
                    const SizedBox(height: 16),
                    
                    // Account Filter Selector (only show if bank is selected and has multiple accounts)
                    if (_selectedBankFilter != null)
                      _buildAccountFilterSection(accounts),
                    if (_selectedBankFilter != null) const SizedBox(height: 24),

                    // Income/Expense Cards
                    _buildIncomeExpenseCards(income, expenses),
                    const SizedBox(height: 24),

                    // Chart Type Selector
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildChartTypeDropdown(),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Chart
                    _buildChart(chartData, maxValue),
                    const SizedBox(height: 24),

                    // Transactions List Header with Sort By
                    _buildTransactionsHeader(),
                    const SizedBox(height: 12),

                    // Transactions List
                    _buildTransactionsList(filteredTransactions),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }


  Widget _buildIncomeExpenseCards(double income, double expenses) {
    // Filter transactions based on selected period for accurate totals
    final allTransactions = Provider.of<TransactionProvider>(context, listen: false).allTransactions;
    
    // Filter by period
    final now = _getBaseDate();
    List<Transaction> periodFiltered = [];
    
    if (_selectedPeriod == 'Week') {
      int daysSinceMonday = (now.weekday - 1) % 7;
      final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysSinceMonday));
      periodFiltered = allTransactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
                 transactionDate.isBefore(now.add(const Duration(days: 1)));
        } catch (e) {
          return false;
        }
      }).toList();
    } else if (_selectedPeriod == 'Month') {
      final monthStart = DateTime(now.year, now.month, 1);
      periodFiltered = allTransactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate.year == now.year && transactionDate.month == now.month;
        } catch (e) {
          return false;
        }
      }).toList();
    } else { // Year
      periodFiltered = allTransactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate.year == now.year;
        } catch (e) {
          return false;
        }
      }).toList();
    }
    
    // Filter by bank if selected
    if (_selectedBankFilter != null) {
      periodFiltered = periodFiltered.where((t) => t.bankId == _selectedBankFilter).toList();
    }
    
    // Filter by account if selected
    if (_selectedAccountFilter != null && _selectedBankFilter != null) {
      final accounts = Provider.of<TransactionProvider>(context, listen: false).accountSummaries;
      final account = accounts.firstWhere(
        (a) => a.accountNumber == _selectedAccountFilter && a.bankId == _selectedBankFilter,
        orElse: () => accounts.firstWhere((a) => a.bankId == _selectedBankFilter, orElse: () => accounts.first),
      );
      
      periodFiltered = periodFiltered.where((t) {
        if (account.bankId == 1 && t.accountNumber != null && account.accountNumber.length >= 4) {
          return t.accountNumber!.substring(t.accountNumber!.length - 4) ==
              account.accountNumber.substring(account.accountNumber.length - 4);
        } else if (account.bankId == 4 && t.accountNumber != null && account.accountNumber.length >= 3) {
          return t.accountNumber!.substring(t.accountNumber!.length - 3) ==
              account.accountNumber.substring(account.accountNumber.length - 3);
        } else if (account.bankId == 3 && t.accountNumber != null && account.accountNumber.length >= 2) {
          return t.accountNumber!.substring(t.accountNumber!.length - 2) ==
              account.accountNumber.substring(account.accountNumber.length - 2);
        } else {
          return t.accountNumber == account.accountNumber;
        }
      }).toList();
    }
    
    // Calculate income and expenses for the period
    final periodIncome = periodFiltered
        .where((t) => t.type == 'CREDIT')
        .fold(0.0, (sum, t) => sum + t.amount);
    final periodExpenses = periodFiltered
        .where((t) => t.type == 'DEBIT')
        .fold(0.0, (sum, t) => sum + t.amount);
    
    return Row(
      children: [
        Expanded(
          child: _buildIncomeExpenseCard('Income', periodIncome, Colors.green, 'Income'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildIncomeExpenseCard('Expense', periodExpenses, Theme.of(context).colorScheme.error, 'Expense'),
        ),
      ],
    );
  }

  Widget _buildIncomeExpenseCard(String label, double amount, Color color, String cardType) {
    final isSelected = _selectedCard == cardType;
    final isIncome = cardType == 'Income';
    
    return GestureDetector(
      onTap: () {
        setState(() {
          // Toggle selection: if already selected, unselect; otherwise select
          _selectedCard = isSelected ? null : cardType;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isIncome ? Colors.green : Theme.of(context).colorScheme.error)
              : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : color.withOpacity(0.3),
            width: isSelected ? 0 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ETB ${_formatCurrency(amount)}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Colors.white
                    : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['Week', 'Month', 'Year'].map((period) {
          final isSelected = _selectedPeriod == period;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedPeriod = period;
                _timeFrameOffset = 0; // Reset to current time frame when period changes
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.primary.withOpacity(0.8),
                        ],
                      )
                    : null,
                color: isSelected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                period,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChartTypeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.2),
        ),
      ),
      child: PopupMenuButton<String>(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getChartTypeIcon(_chartType),
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              _chartType,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        onSelected: (value) {
          setState(() {
            _chartType = value;
          });
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'Line Chart',
            child: Row(
              children: [
                Icon(Icons.show_chart, size: 18),
                const SizedBox(width: 12),
                const Text('Line Chart'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'Bar Chart',
            child: Row(
              children: [
                Icon(Icons.bar_chart, size: 18),
                const SizedBox(width: 12),
                const Text('Bar Chart'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'Pie Chart',
            child: Row(
              children: [
                Icon(Icons.pie_chart, size: 18),
                const SizedBox(width: 12),
                const Text('Pie Chart'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'P&L Calendar',
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 18),
                const SizedBox(width: 12),
                const Text('P&L Calendar'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getChartTypeIcon(String chartType) {
    switch (chartType) {
      case 'Line Chart':
        return Icons.show_chart;
      case 'Bar Chart':
        return Icons.bar_chart;
      case 'Pie Chart':
        return Icons.pie_chart;
      case 'P&L Calendar':
        return Icons.calendar_today;
      default:
        return Icons.show_chart;
    }
  }

  Widget _buildChart(List<ChartDataPoint> data, double maxValue) {
    if (data.isEmpty) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    Widget chartWidget;
    switch (_chartType) {
      case 'Bar Chart':
        chartWidget = _buildBarChart(data, maxValue);
        break;
      case 'Pie Chart':
        chartWidget = _buildPieChart(data);
        break;
      case 'P&L Calendar':
        chartWidget = _buildTradingPnL(data, maxValue);
        break;
      case 'Line Chart':
      default:
        chartWidget = _buildLineChart(data, maxValue);
        break;
    }

    return Column(
      children: [
        // Navigation buttons at the top
        Stack(
          alignment: Alignment.center,
          children: [
            // Row with buttons at each end
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left navigation button
                GestureDetector(
                  onTapDown: (_) {
                    setState(() => _leftButtonPressed = true);
                  },
                  onTapUp: (_) {
                    setState(() => _leftButtonPressed = false);
                    _navigateTimeFrame(false);
                  },
                  onTapCancel: () {
                    setState(() => _leftButtonPressed = false);
                  },
                  child: AnimatedScale(
                    scale: _leftButtonPressed ? 0.9 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeInOut,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeInOut,
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.chevron_left,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                // Right navigation button
                GestureDetector(
                  onTapDown: (_) {
                    setState(() => _rightButtonPressed = true);
                  },
                  onTapUp: (_) {
                    setState(() => _rightButtonPressed = false);
                    _navigateTimeFrame(true);
                  },
                  onTapCancel: () {
                    setState(() => _rightButtonPressed = false);
                  },
                  child: AnimatedScale(
                    scale: _rightButtonPressed ? 0.9 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeInOut,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeInOut,
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Today button (centered)
            if (_timeFrameOffset != 0)
              GestureDetector(
                onTap: _resetTimeFrame,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.today,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Today',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Chart widget with swipe gesture and slide animation
        GestureDetector(
          onHorizontalDragStart: (details) {
            if (_isNavigating) return;
            _dragOffset = 0.0;
            setState(() {});
          },
          onHorizontalDragUpdate: (details) {
            if (_isNavigating) return;
            final screenWidth = MediaQuery.of(context).size.width;
            _dragOffset = details.primaryDelta! / screenWidth;
            setState(() {});
          },
          onHorizontalDragEnd: (details) {
            if (_isNavigating) return;
            final velocity = details.primaryVelocity;
            if (velocity != null) {
              // Swipe right (drag left, positive velocity) = go to previous time frame
              if (velocity > 200) {
                _navigateTimeFrame(false);
              }
              // Swipe left (drag right, negative velocity) = go to next time frame
              else if (velocity < -200) {
                _navigateTimeFrame(true);
              } else {
                // Reset drag offset if swipe wasn't strong enough
                _dragOffset = 0.0;
                setState(() {});
              }
            } else {
              _dragOffset = 0.0;
              setState(() {});
            }
          },
          onHorizontalDragCancel: () {
            _dragOffset = 0.0;
            setState(() {});
          },
          child: ClipRect(
            child: SlideTransition(
              position: _dragOffset != 0.0
                  ? AlwaysStoppedAnimation(Offset(_dragOffset, 0))
                  : _slideAnimation,
              child: chartWidget,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLineChart(List<ChartDataPoint> data, double maxValue) {
    // Find the highest point and current day
    int highestIndex = 0;
    double highestValue = 0;
    for (int i = 0; i < data.length; i++) {
      if (data[i].value > highestValue) {
        highestValue = data[i].value;
        highestIndex = i;
      }
    }

    // Find current day index based on actual current date
    int currentDayIndex = _getCurrentDayIndex(data);

    return Stack(
      children: [
        Container(
          height: 280,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (maxValue / 5).clamp(100.0, double.infinity),
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.08),
                    strokeWidth: 1,
                  );
                },
              ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < data.length) {
                    final isCurrentDay = _timeFrameOffset == 0 && index == currentDayIndex;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                        child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isCurrentDay
                              ? Theme.of(context).colorScheme.primary.withOpacity(0.25)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          data[index].label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isCurrentDay ? FontWeight.bold : FontWeight.w500,
                            color: isCurrentDay
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
                reservedSize: 40,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: (maxValue / 5).clamp(100.0, double.infinity),
                reservedSize: 45,
                getTitlesWidget: (value, meta) {
                  if (value == 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    '${(value / 1000).toStringAsFixed(0)}k',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (data.length - 1).toDouble(),
          minY: 0,
          maxY: maxValue,
          lineBarsData: [
            LineChartBarData(
              spots: data.asMap().entries.map((entry) {
                return FlSpot(entry.key.toDouble(), entry.value.value);
              }).toList(),
              isCurved: true,
              curveSmoothness: 0.5,
              color: Theme.of(context).colorScheme.primary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: false,
              ),
              belowBarData: BarAreaData(
                show: false,
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) =>
                  Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.9),
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBarChart(List<ChartDataPoint> data, double maxValue) {
    if (data.isEmpty) {
      return Container(
        height: 280,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    
    // Get income and expense data separately by recalculating for each period point
    final allTransactions = Provider.of<TransactionProvider>(context, listen: false).allTransactions;
    
    // Filter by bank if selected
    var bankFiltered = allTransactions;
    if (_selectedBankFilter != null) {
      bankFiltered = allTransactions.where((t) => t.bankId == _selectedBankFilter).toList();
    }
    
    // Calculate income and expense for each period point using the same logic as chart data
    final incomeData = <double>[];
    final expenseData = <double>[];
    
    for (var point in data) {
      final pointDate = point.date;
      if (pointDate == null) {
        incomeData.add(0.0);
        expenseData.add(0.0);
        continue;
      }
      
      // Filter transactions for this specific period point
      final pointTransactions = bankFiltered.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          if (_selectedPeriod == 'Week') {
            return transactionDate.year == pointDate.year &&
                   transactionDate.month == pointDate.month &&
                   transactionDate.day == pointDate.day;
          } else if (_selectedPeriod == 'Month') {
            // For month view, match week ranges
            final weekStart = pointDate;
            final weekEnd = weekStart.add(const Duration(days: 6));
            return transactionDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
                   transactionDate.isBefore(weekEnd.add(const Duration(days: 1)));
          } else {
            // For year view, match month
            return transactionDate.year == pointDate.year &&
                   transactionDate.month == pointDate.month;
          }
        } catch (e) {
          return false;
        }
      }).toList();
      
      final income = pointTransactions
          .where((t) => t.type == 'CREDIT')
          .fold(0.0, (sum, t) => sum + t.amount);
      final expense = pointTransactions
          .where((t) => t.type == 'DEBIT')
          .fold(0.0, (sum, t) => sum + t.amount);
      
      incomeData.add(income);
      expenseData.add(expense);
    }
    
    final maxBarValue = [
      ...incomeData,
      ...expenseData,
    ].reduce((a, b) => a > b ? a : b);
    final chartMaxValue = (maxBarValue * 1.2).clamp(100.0, double.infinity);
    
    int currentDayIndex = _getCurrentDayIndex(data);
    
    return Container(
      height: 280,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (chartMaxValue / 5).clamp(100.0, double.infinity),
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.08),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < data.length) {
                    final isCurrentDay = _timeFrameOffset == 0 && index == currentDayIndex;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isCurrentDay
                              ? Theme.of(context).colorScheme.primary.withOpacity(0.25)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          data[index].label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isCurrentDay ? FontWeight.bold : FontWeight.w500,
                            color: isCurrentDay
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
                reservedSize: 40,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: (chartMaxValue / 5).clamp(100.0, double.infinity),
                reservedSize: 45,
                getTitlesWidget: (value, meta) {
                  if (value == 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    '${(value / 1000).toStringAsFixed(0)}k',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: data.asMap().entries.map((entry) {
            final index = entry.key;
            final isCurrentDay = _timeFrameOffset == 0 && index == currentDayIndex;
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  fromY: 0,
                  toY: incomeData[index],
                  color: Colors.green,
                  width: 8,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
                BarChartRodData(
                  fromY: 0,
                  toY: -expenseData[index],
                  color: Theme.of(context).colorScheme.error,
                  width: 8,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(2)),
                ),
              ],
            );
          }).toList(),
          minY: -chartMaxValue,
          maxY: chartMaxValue,
        ),
      ),
    );
  }

  Widget _buildPieChart(List<ChartDataPoint> data) {
    final total = data.fold(0.0, (sum, point) => sum + point.value);
    if (total == 0) {
      return Container(
        height: 280,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 50,
          sections: data.asMap().entries.map((entry) {
            final index = entry.key;
            final point = entry.value;
            final percentage = (point.value / total) * 100;
            return PieChartSectionData(
              value: point.value,
              title: '${point.label}\n${percentage.toStringAsFixed(1)}%',
              color: Theme.of(context).colorScheme.primary.withOpacity(
                0.3 + (index % 3) * 0.2,
              ),
              radius: 90,
              titleStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTradingPnL(List<ChartDataPoint> data, double maxValue) {
    final allTransactions = Provider.of<TransactionProvider>(context, listen: false).allTransactions;
    final now = _getBaseDate();
    
    // Filter by bank, account, and income/expense card
    var filtered = allTransactions;
    
    // Filter by selected card (Income/Expense)
    if (_selectedCard == 'Income') {
      filtered = filtered.where((t) => t.type == 'CREDIT').toList();
    } else if (_selectedCard == 'Expense') {
      filtered = filtered.where((t) => t.type == 'DEBIT').toList();
    }
    
    // Filter by bank
    if (_selectedBankFilter != null) {
      filtered = filtered.where((t) => t.bankId == _selectedBankFilter).toList();
    }
    
    // Filter by account if selected
    if (_selectedAccountFilter != null && _selectedBankFilter != null) {
      final accounts = Provider.of<TransactionProvider>(context, listen: false).accountSummaries;
      final account = accounts.firstWhere(
        (a) => a.accountNumber == _selectedAccountFilter && a.bankId == _selectedBankFilter,
        orElse: () => accounts.firstWhere((a) => a.bankId == _selectedBankFilter, orElse: () => accounts.first),
      );
      
      filtered = filtered.where((t) {
        if (account.bankId == 1 && t.accountNumber != null && account.accountNumber.length >= 4) {
          return t.accountNumber!.substring(t.accountNumber!.length - 4) ==
              account.accountNumber.substring(account.accountNumber.length - 4);
        } else if (account.bankId == 4 && t.accountNumber != null && account.accountNumber.length >= 3) {
          return t.accountNumber!.substring(t.accountNumber!.length - 3) ==
              account.accountNumber.substring(account.accountNumber.length - 3);
        } else if (account.bankId == 3 && t.accountNumber != null && account.accountNumber.length >= 2) {
          return t.accountNumber!.substring(t.accountNumber!.length - 2) ==
              account.accountNumber.substring(account.accountNumber.length - 2);
        } else {
          return t.accountNumber == account.accountNumber;
        }
      }).toList();
    }
    
    // Determine date range based on selected period
    DateTime startDate;
    DateTime endDate;
    String periodLabel;
    List<DateTime> dates = [];
    
    if (_selectedPeriod == 'Week') {
      // Week view - show 7 days starting from Monday
      int daysSinceMonday = (now.weekday - 1) % 7;
      startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysSinceMonday));
      endDate = startDate.add(const Duration(days: 6));
      periodLabel = 'Week of ${DateFormat('MMM dd').format(startDate)}';
      for (int i = 0; i < 7; i++) {
        dates.add(startDate.add(Duration(days: i)));
      }
    } else if (_selectedPeriod == 'Month') {
      // Month view - show current month
      startDate = DateTime(now.year, now.month, 1);
      endDate = DateTime(now.year, now.month + 1, 0);
      periodLabel = DateFormat('MMMM yyyy').format(startDate);
      final daysInMonth = endDate.day;
      for (int day = 1; day <= daysInMonth; day++) {
        dates.add(DateTime(now.year, now.month, day));
      }
    } else {
      // Year view - show 12 months
      startDate = DateTime(now.year, 1, 1);
      endDate = DateTime(now.year, 12, 31);
      periodLabel = '${now.year}';
      for (int month = 1; month <= 12; month++) {
        dates.add(DateTime(now.year, month, 1));
      }
    }
    
    // Calculate which day of the week the period starts on (Monday = 0)
    final firstWeekday = (dates.first.weekday - 1) % 7;
    
    // Calculate P&L for each date in the period
    final dailyPnL = <DateTime, double>{};
    for (final date in dates) {
      final dayTransactions = filtered.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          if (_selectedPeriod == 'Week') {
            // Match exact day
            return transactionDate.year == date.year &&
                   transactionDate.month == date.month &&
                   transactionDate.day == date.day;
          } else if (_selectedPeriod == 'Month') {
            // Match exact day
            return transactionDate.year == date.year &&
                   transactionDate.month == date.month &&
                   transactionDate.day == date.day;
          } else {
            // Match month for year view
            return transactionDate.year == date.year &&
                   transactionDate.month == date.month;
          }
        } catch (e) {
          return false;
        }
      }).toList();
      
      // Calculate P&L based on selected filter
      double pnl = 0.0;
      if (_selectedCard == 'Income') {
        // Only show income (positive values)
        pnl = dayTransactions.fold(0.0, (sum, t) => sum + t.amount);
      } else if (_selectedCard == 'Expense') {
        // Only show expenses (negative values)
        pnl = -dayTransactions.fold(0.0, (sum, t) => sum + t.amount);
      } else {
        // Show net P&L (income - expenses)
        final income = dayTransactions
            .where((t) => t.type == 'CREDIT')
            .fold(0.0, (sum, t) => sum + t.amount);
        final expenses = dayTransactions
            .where((t) => t.type == 'DEBIT')
            .fold(0.0, (sum, t) => sum + t.amount);
        pnl = income - expenses;
      }
      
      dailyPnL[date] = pnl;
    }
    
    final maxPnL = dailyPnL.values.isEmpty
        ? 100.0
        : dailyPnL.values.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
    
    // Calculate grid layout based on period
    int weeks;
    int itemsPerRow;
    if (_selectedPeriod == 'Week') {
      weeks = 1;
      itemsPerRow = 7;
    } else if (_selectedPeriod == 'Month') {
      final daysInMonth = dates.length;
      final totalCells = firstWeekday + daysInMonth;
      weeks = (totalCells / 7).ceil();
      itemsPerRow = 7;
    } else {
      // Year view - show months in a grid
      weeks = 4; // 3 rows of 4 months
      itemsPerRow = 4;
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                periodLabel,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              // Legend
              Row(
                children: [
                  _buildLegendItem('Profit', Colors.green),
                  const SizedBox(width: 12),
                  _buildLegendItem('Loss', Theme.of(context).colorScheme.error),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Calendar grid
          Column(
            children: [
              // Headers based on period
              if (_selectedPeriod == 'Year')
                Row(
                  children: ['Q1', 'Q2', 'Q3', 'Q4'].map((quarter) {
                    return Expanded(
                      child: Center(
                        child: Text(
                          quarter,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                )
              else
                Row(
                  children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((day) {
                    return Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 8),
              // Calendar grid
              ...List.generate(weeks, (weekIndex) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: List.generate(itemsPerRow, (dayIndex) {
                      final cellIndex = weekIndex * itemsPerRow + dayIndex;
                      
                      if (_selectedPeriod == 'Year') {
                        // Year view - show months
                        if (cellIndex >= dates.length) {
                          return Expanded(child: Container());
                        }
                        final date = dates[cellIndex];
                        final monthName = DateFormat('MMM').format(date);
                        final pnl = dailyPnL[date] ?? 0.0;
                        final isCurrentMonth = _timeFrameOffset == 0 && date.year == DateTime.now().year && date.month == DateTime.now().month;
                        final intensity = maxPnL > 0 ? (pnl.abs() / maxPnL).clamp(0.0, 1.0) : 0.0;
                        final isPositive = pnl >= 0;
                        final bgOpacity = 0.2 + intensity * 0.6;
                        final useWhiteText = bgOpacity > 0.5;
                        
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: isPositive
                                    ? Colors.green.withOpacity(bgOpacity)
                                    : Theme.of(context).colorScheme.error.withOpacity(bgOpacity),
                                borderRadius: BorderRadius.circular(8),
                                border: isCurrentMonth
                                    ? Border.all(
                                        color: Theme.of(context).colorScheme.primary,
                                        width: 2,
                                      )
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    monthName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isCurrentMonth ? FontWeight.bold : FontWeight.w500,
                                      color: useWhiteText
                                          ? Colors.white
                                          : Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  if (pnl != 0)
                                    Text(
                                      '${pnl > 0 ? '+' : ''}${(pnl / 1000).toStringAsFixed(1)}k',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: useWhiteText
                                            ? Colors.white
                                            : (isPositive ? Colors.green.shade700 : Theme.of(context).colorScheme.error),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      } else {
                        // Week or Month view
                        final cellIndexWithOffset = weekIndex * itemsPerRow + dayIndex;
                        final dayNumber = cellIndexWithOffset - firstWeekday + 1;
                        
                        if (_selectedPeriod == 'Week') {
                          if (cellIndexWithOffset >= dates.length) {
                            return Expanded(child: Container());
                          }
                          final date = dates[cellIndexWithOffset];
                          final dayNumber = date.day;
                          final pnl = dailyPnL[date] ?? 0.0;
                          final isToday = _timeFrameOffset == 0 && 
                                         date.year == DateTime.now().year &&
                                         date.month == DateTime.now().month &&
                                         date.day == DateTime.now().day;
                          final intensity = maxPnL > 0 ? (pnl.abs() / maxPnL).clamp(0.0, 1.0) : 0.0;
                          final isPositive = pnl >= 0;
                          final bgOpacity = 0.2 + intensity * 0.6;
                          final useWhiteText = bgOpacity > 0.5;
                          
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isPositive
                                      ? Colors.green.withOpacity(bgOpacity)
                                      : Theme.of(context).colorScheme.error.withOpacity(bgOpacity),
                                  borderRadius: BorderRadius.circular(8),
                                  border: isToday
                                      ? Border.all(
                                          color: Theme.of(context).colorScheme.primary,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$dayNumber',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                                        color: useWhiteText
                                            ? Colors.white
                                            : Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    if (pnl != 0)
                                      Text(
                                        '${pnl > 0 ? '+' : ''}${(pnl / 1000).toStringAsFixed(1)}k',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: useWhiteText
                                              ? Colors.white
                                              : (isPositive ? Colors.green.shade700 : Theme.of(context).colorScheme.error),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        } else {
                          // Month view
                          if (dayNumber < 1 || dayNumber > dates.length) {
                            return Expanded(child: Container());
                          }
                          
                          final date = dates[dayNumber - 1];
                          final pnl = dailyPnL[date] ?? 0.0;
                          final isToday = _timeFrameOffset == 0 && 
                                         date.year == DateTime.now().year &&
                                         date.month == DateTime.now().month &&
                                         date.day == DateTime.now().day;
                          final intensity = maxPnL > 0 ? (pnl.abs() / maxPnL).clamp(0.0, 1.0) : 0.0;
                          final isPositive = pnl >= 0;
                          final bgOpacity = 0.2 + intensity * 0.6;
                          final useWhiteText = bgOpacity > 0.5;
                          
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isPositive
                                      ? Colors.green.withOpacity(bgOpacity)
                                      : Theme.of(context).colorScheme.error.withOpacity(bgOpacity),
                                  borderRadius: BorderRadius.circular(8),
                                  border: isToday
                                      ? Border.all(
                                          color: Theme.of(context).colorScheme.primary,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$dayNumber',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                                        color: useWhiteText
                                            ? Colors.white
                                            : Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    if (pnl != 0)
                                      Text(
                                        '${pnl > 0 ? '+' : ''}${(pnl / 1000).toStringAsFixed(1)}k',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: useWhiteText
                                              ? Colors.white
                                              : (isPositive ? Colors.green.shade700 : Theme.of(context).colorScheme.error),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                      }
                    }),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withOpacity(0.6),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterSection(List bankSummaries) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip('All', _selectedBankFilter == null,
            onTap: () => setState(() {
              _selectedBankFilter = null;
              _selectedAccountFilter = null;
            }),
          ),
          const SizedBox(width: 8),
          ...bankSummaries.map((bank) {
            final bankInfo = AppConstants.banks.firstWhere(
              (b) => b.id == bank.bankId,
              orElse: () => AppConstants.banks.first,
            );
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildFilterChip(
                bankInfo.shortName,
                _selectedBankFilter == bank.bankId,
                onTap: () => setState(() {
                  _selectedBankFilter = bank.bankId;
                  _selectedAccountFilter = null; // Reset account filter when bank changes
                }),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAccountFilterSection(List accounts) {
    // Filter accounts by selected bank
    final bankAccounts = accounts.where((a) => a.bankId == _selectedBankFilter).toList();
    
    // Only show if there are multiple accounts
    if (bankAccounts.length <= 1) {
      return const SizedBox.shrink();
    }
    
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip('All', _selectedAccountFilter == null,
            onTap: () => setState(() => _selectedAccountFilter = null),
          ),
          const SizedBox(width: 8),
          ...bankAccounts.map((account) {
            final accountDisplay = account.accountNumber.length > 4
                ? account.accountNumber.substring(account.accountNumber.length - 4)
                : account.accountNumber;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildFilterChip(
                accountDisplay,
                _selectedAccountFilter == account.accountNumber,
                onTap: () => setState(() => _selectedAccountFilter = account.accountNumber),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTransactionsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Transactions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        _buildSortByDropdown(),
      ],
    );
  }

  Widget _buildSortByDropdown() {
    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sort,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            'Sort by',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onSelected: (value) {
        setState(() {
          _sortBy = value;
        });
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'Date',
          child: Text('Date'),
        ),
        const PopupMenuItem(
          value: 'Amount',
          child: Text('Amount'),
        ),
        const PopupMenuItem(
          value: 'Reference',
          child: Text('Reference'),
        ),
      ],
    );
  }

  Widget _buildTransactionsList(List<Transaction> transactions) {
    // Sort transactions (already filtered by tab and bank)
    final sortedTransactions = List<Transaction>.from(transactions);
    sortedTransactions.sort((a, b) {
      switch (_sortBy) {
        case 'Amount':
          return b.amount.compareTo(a.amount); // Descending
        case 'Reference':
          return a.reference.compareTo(b.reference);
        case 'Date':
        default:
          // Sort by date, most recent first
          if (a.time == null && b.time == null) return 0;
          if (a.time == null) return 1;
          if (b.time == null) return -1;
          try {
            final dateA = DateTime.parse(a.time!);
            final dateB = DateTime.parse(b.time!);
            return dateB.compareTo(dateA); // Descending
          } catch (e) {
            return 0;
          }
      }
    });

    if (sortedTransactions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No transactions found',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedTransactions.length,
      itemBuilder: (context, index) {
        final transaction = sortedTransactions[index];
        return _buildTransactionItem(transaction);
      },
    );
  }

  Widget _buildTransactionItem(Transaction transaction) {
    final isCredit = transaction.type == 'CREDIT';
    final dateTime = transaction.time != null
        ? (() {
            try {
              return DateTime.parse(transaction.time!);
            } catch (e) {
              return null;
            }
          })()
        : null;
    final dateStr = dateTime != null
        ? DateFormat('MMM dd, yyyy').format(dateTime)
        : 'Unknown date';
    final timeStr = dateTime != null
        ? DateFormat('hh:mm a').format(dateTime)
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.reference,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (transaction.creditor != null || transaction.receiver != null)
                      const SizedBox(height: 4),
                    if (transaction.creditor != null)
                      Text(
                        transaction.creditor!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (transaction.receiver != null)
                      Text(
                        transaction.receiver!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isCredit ? '+' : '-'}ETB ${_formatCurrency(transaction.amount)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isCredit
                          ? Colors.green
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (dateTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (timeStr.isNotEmpty)
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                        ),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap ?? () => setState(() => _selectedBankFilter = null),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
              : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }


  List<ChartDataPoint> _getChartData(
    List<Transaction> transactions,
    String period,
    int? bankFilter,
    String? accountFilter,
  ) {
    // Filter by bank if selected (transactions are already filtered by type)
    var filteredTransactions = transactions;
    if (bankFilter != null) {
      filteredTransactions = transactions.where((t) => t.bankId == bankFilter).toList();
    }
    
    // Filter by account if selected (account filtering is already done in main filter, but keep for consistency)

    if (period == 'Week') {
      return _getWeeklyData(filteredTransactions);
    } else if (period == 'Month') {
      return _getMonthlyData(filteredTransactions);
    } else {
      return _getYearlyData(filteredTransactions);
    }
  }

  List<ChartDataPoint> _getWeeklyData(List<Transaction> transactions) {
    final now = _getBaseDate();
    // Get the start of the week (Monday)
    int daysSinceMonday = (now.weekday - 1) % 7;
    final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysSinceMonday));
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    
    return List.generate(7, (index) {
      final date = weekStart.add(Duration(days: index));
      final dayTransactions = transactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate.year == date.year &&
              transactionDate.month == date.month &&
              transactionDate.day == date.day;
        } catch (e) {
          return false;
        }
      }).toList();
      
      final total = dayTransactions.fold(0.0, (sum, t) => sum + t.amount);
      return ChartDataPoint(
        label: days[index],
        value: total,
        date: date,
      );
    });
  }

  List<ChartDataPoint> _getMonthlyData(List<Transaction> transactions) {
    final now = _getBaseDate();
    final monthStart = DateTime(now.year, now.month, 1);
    final weeksInMonth = ((now.difference(monthStart).inDays) / 7).ceil();
    
    return List.generate(weeksInMonth.clamp(1, 4), (index) {
      final weekStart = monthStart.add(Duration(days: index * 7));
      final weekEnd = weekStart.add(const Duration(days: 6));
      
      final weekTransactions = transactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
              transactionDate.isBefore(weekEnd.add(const Duration(days: 1)));
        } catch (e) {
          return false;
        }
      }).toList();
      
      final total = weekTransactions.fold(0.0, (sum, t) => sum + t.amount);
      return ChartDataPoint(
        label: 'W${index + 1}',
        value: total,
        date: weekStart,
      );
    });
  }

  List<ChartDataPoint> _getYearlyData(List<Transaction> transactions) {
    final now = _getBaseDate();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    return List.generate(12, (index) {
      final monthTransactions = transactions.where((t) {
        if (t.time == null) return false;
        try {
          final transactionDate = DateTime.parse(t.time!);
          return transactionDate.year == now.year && transactionDate.month == index + 1;
        } catch (e) {
          return false;
        }
      }).toList();
      
      final total = monthTransactions.fold(0.0, (sum, t) => sum + t.amount);
      return ChartDataPoint(
        label: months[index],
        value: total,
        date: DateTime(now.year, index + 1, 1),
      );
    });
  }

  String _formatCurrency(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }

  int _getCurrentDayIndex(List<ChartDataPoint> data) {
    final now = _getBaseDate();
    
    if (_selectedPeriod == 'Week') {
      // Find the index that matches today's date
      for (int i = 0; i < data.length; i++) {
        if (data[i].date != null) {
          final dataDate = data[i].date!;
          if (dataDate.year == now.year &&
              dataDate.month == now.month &&
              dataDate.day == now.day) {
            return i;
          }
        }
      }
      // Fallback: return today's weekday index (0-6, where 0 is Saturday)
      int daysSinceSaturday = (now.weekday + 1) % 7;
      return daysSinceSaturday.clamp(0, data.length - 1);
    } else if (_selectedPeriod == 'Month') {
      // Find current week index
      final monthStart = DateTime(now.year, now.month, 1);
      final weekNumber = ((now.difference(monthStart).inDays) / 7).floor();
      return weekNumber.clamp(0, data.length - 1);
    } else {
      // For year view, return current month index
      return (now.month - 1).clamp(0, data.length - 1);
    }
  }
}

class ChartDataPoint {
  final String label;
  final double value;
  final DateTime? date;

  ChartDataPoint({required this.label, required this.value, this.date});
}
