import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:intl/intl.dart';

import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/widgets/analytics/transactions_list.dart';
import 'package:totals/widgets/category_filter_button.dart';
import 'package:totals/widgets/category_filter_sheet.dart';
import 'package:totals/widgets/categorize_transaction_sheet.dart';

class AccountDetailPage extends StatefulWidget {
  final String accountNumber;
  final int bankId;
  const AccountDetailPage(
      {super.key, required this.accountNumber, required this.bankId});

  @override
  _AccountDetailPageState createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  List<String> tabs = ["All Transactions", "Credits", "Debits"];
  String activeTab = "All Transactions";
  String searchTerm = "";
  bool showTotalBalance = false;
  bool isExpanded = false;
  Set<int?> _selectedIncomeCategoryIds = {};
  Set<int?> _selectedExpenseCategoryIds = {};

  // Date filter - default to last 30 days
  late DateTime _startDate;
  late DateTime _endDate;

  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank> _banks = [];

  @override
  void initState() {
    super.initState();
    // Default to last 30 days
    _endDate = DateTime.now();
    _startDate = _endDate.subtract(const Duration(days: 30));
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

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Color(0xFF294EC3),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF444750),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Bank? _getBankInfo() {
    try {
      return _banks.firstWhere((element) => element.id == widget.bankId);
    } catch (e) {
      return null;
    }
  }

  String _formatCurrency(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }

  String _getBankLabel(Transaction transaction) {
    final bankId = transaction.bankId ?? widget.bankId;
    if (bankId == null) return 'Unknown bank';
    try {
      final bank = _banks.firstWhere((b) => b.id == bankId);
      final shortName = bank.shortName.trim();
      return shortName.isNotEmpty ? shortName : bank.name;
    } catch (e) {
      return 'Bank $bankId';
    }
  }

  bool _matchesCategorySelection(int? categoryId, Set<int?> selection) {
    if (selection.isEmpty) return true;
    if (categoryId == null) return selection.contains(null);
    return selection.contains(categoryId);
  }

  bool _matchesCategoryFilter(Transaction transaction) {
    if (_selectedIncomeCategoryIds.isEmpty &&
        _selectedExpenseCategoryIds.isEmpty) {
      return true;
    }
    if (transaction.type == 'CREDIT') {
      return _matchesCategorySelection(
          transaction.categoryId, _selectedIncomeCategoryIds);
    }
    if (transaction.type == 'DEBIT') {
      return _matchesCategorySelection(
          transaction.categoryId, _selectedExpenseCategoryIds);
    }
    return true;
  }

  Future<void> _openCategoryFilterSheet(
    TransactionProvider provider, {
    required String flow,
  }) async {
    final result = await showCategoryFilterSheet(
      context: context,
      provider: provider,
      selectedCategoryIds: flow == 'income'
          ? _selectedIncomeCategoryIds
          : _selectedExpenseCategoryIds,
      flow: flow,
      title: flow == 'income' ? 'Income categories' : 'Expense categories',
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

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(builder: (context, provider, child) {
      // 1. Find the AccountSummary
      final accountSummary = provider.accountSummaries.firstWhere(
        (a) => a.accountNumber == widget.accountNumber,
        orElse: () => AccountSummary(
          bankId: widget.bankId,
          accountNumber: widget.accountNumber,
          accountHolderName: "Unknown",
          totalTransactions: 0,
          totalCredit: 0,
          totalDebit: 0,
          settledBalance: 0,
          balance: 0,
          pendingCredit: 0,
        ),
      );

      // 2. Filter Transactions for this account
      // Use helper logic similar to provider to match account
      List<Transaction> transactions = provider.allTransactions.where((t) {
        if (t.bankId != widget.bankId) return false;

        // Get bank info with error handling
        try {
          final bank = _banks.firstWhere((b) => b.id == widget.bankId);

          if (bank.uniformMasking == true && bank.maskPattern != null) {
            // Match last N digits based on mask pattern
            if (t.accountNumber == null || t.accountNumber!.isEmpty) {
              return false;
            }
            if (widget.accountNumber.length < bank.maskPattern! ||
                t.accountNumber!.length < bank.maskPattern!) {
              return false;
            }
            return widget.accountNumber.substring(
                    widget.accountNumber.length - bank.maskPattern!) ==
                t.accountNumber!
                    .substring(t.accountNumber!.length - bank.maskPattern!);
          } else if (bank.uniformMasking == false) {
            // Match by bankId only
            return true;
          } else {
            // Exact match (uniformMasking is null)
            return t.accountNumber == widget.accountNumber;
          }
        } catch (e) {
          // Bank not found in database, fallback to exact match
          return t.accountNumber == widget.accountNumber;
        }
      }).toList();

      // 3. Filter by Date Range
      List<Transaction> dateFilteredTransactions = transactions.where((t) {
        if (t.time == null) return false;

        try {
          DateTime? transactionDate;
          if (t.time!.contains('T')) {
            transactionDate = DateTime.parse(t.time!);
          } else {
            transactionDate = DateTime.tryParse(t.time!);
          }

          if (transactionDate == null) return false;

          // Normalize to start of day for comparison
          DateTime transactionDateStart = DateTime(
            transactionDate.year,
            transactionDate.month,
            transactionDate.day,
          );

          DateTime startDateNormalized = DateTime(
            _startDate.year,
            _startDate.month,
            _startDate.day,
          );

          DateTime endDateNormalized = DateTime(
            _endDate.year,
            _endDate.month,
            _endDate.day,
          );

          // Check if transaction date is within range (inclusive)
          return transactionDateStart.compareTo(startDateNormalized) >= 0 &&
              transactionDateStart.compareTo(endDateNormalized) <= 0;
        } catch (e) {
          print("debug: Error parsing transaction date: ${t.time}, error: $e");
          return false;
        }
      }).toList();

      // 4. Local Search & Tab Filter
      List<Transaction> visibleTransaction = dateFilteredTransactions;

      print("debug: Visible transactions: ${visibleTransaction.length}");

      // Apply Search
      if (searchTerm.isNotEmpty) {
        visibleTransaction = visibleTransaction
            .where((t) =>
                (t.creditor?.toLowerCase().contains(searchTerm.toLowerCase()) ??
                    false) ||
                (t.reference.toLowerCase().contains(searchTerm.toLowerCase())))
            .toList();
      }

      // Apply Tabs
      if (activeTab == "Credits") {
        visibleTransaction =
            visibleTransaction.where((t) => t.type == "CREDIT").toList();
      } else if (activeTab == "Debits") {
        visibleTransaction =
            visibleTransaction.where((t) => t.type == "DEBIT").toList();
      }

      // Apply Category Filters
      visibleTransaction =
          visibleTransaction.where(_matchesCategoryFilter).toList();

      // Sort by date desc
      visibleTransaction.sort((a, b) =>
          (DateTime.tryParse(b.time ?? "") ?? DateTime(0))
              .compareTo(DateTime.tryParse(a.time ?? "") ?? DateTime(0)));

      final showIncomeFilter = activeTab != "Debits";
      final showExpenseFilter = activeTab != "Credits";

      return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            title: Text('Transaction History',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.primary)),
          ),
          body: SingleChildScrollView(
              child: Column(
            children: [
              Container(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: Theme.of(context).dividerColor, width: .2),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(tabs.length, (index) {
                      return Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                  color: activeTab == tabs[index]
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  width: activeTab == tabs[index] ? 2 : 0),
                            ),
                          ),
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                activeTab = tabs[index];
                                // Filtering handled in build
                              });
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: activeTab == tabs[index]
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                              textStyle: const TextStyle(fontSize: 14),
                            ),
                            child: Text(tabs[index]),
                          ));
                    }),
                  )),
              const SizedBox(height: 10),
              // Use accountSummary fields
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    color: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    elevation: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF172B6D), // Your first color
                            Color(0xFF274AB9), // Your second color
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16.0, 28.0, 16.0, 28.0),
                        child: Column(
                          children: [
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 60,
                                    height: 60,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.asset(
                                        _getBankInfo()?.image ??
                                            "assets/images/cbe.png",
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _getBankInfo()?.name ??
                                                    "Unknown Bank",
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  color: Color(0xFFF7F8FB),
                                                  // Subtle text color
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    isExpanded = !isExpanded;
                                                  });
                                                },
                                                child: Icon(
                                                  isExpanded
                                                      ? Icons.keyboard_arrow_up
                                                      : Icons
                                                          .keyboard_arrow_down,
                                                  color: Colors.white,
                                                  size: 28,
                                                ))
                                          ],
                                        ),
                                        const SizedBox(
                                          height: 4,
                                        ),
                                        Text(
                                          accountSummary.accountNumber,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF9FABD2),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          accountSummary.accountHolderName,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF9FABD2),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              "${showTotalBalance ? formatNumberWithComma(accountSummary.balance) : '*' * ((accountSummary.balance).toString()).length} ETB",
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: Color(0xFFF7F8FB),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    showTotalBalance =
                                                        !showTotalBalance;
                                                  });
                                                },
                                                child: Icon(
                                                    showTotalBalance == true
                                                        ? Icons.visibility_off
                                                        : Icons
                                                            .remove_red_eye_outlined,
                                                    color: Colors.grey[400],
                                                    size: 20))
                                          ],
                                        ),
                                      ],
                                    ),
                                  )
                                ]),
                            isExpanded
                                ? Column(
                                    children: [
                                      const SizedBox(
                                        height: 12,
                                      ),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment
                                            .spaceBetween, // Centers horizontally
                                        children: [
                                          Text(
                                            "Total Credit",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                              "${formatNumberWithComma(accountSummary.totalCredit)} ETB",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                fontSize: 14,
                                              )),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment
                                            .spaceBetween, // Centers horizontally
                                        children: [
                                          const Text(
                                            "Total Debit",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                              "${formatNumberWithComma(accountSummary.totalDebit)} ETB",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                fontSize: 14,
                                              )),
                                        ],
                                      )
                                    ],
                                  )
                                : Container()
                          ],
                        ),
                      ),
                    )),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(children: [
                    TextField(
                      onChanged: (value) {
                        setState(() {
                          searchTerm = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search for Transactions',
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w300,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: Theme.of(context).dividerColor, width: 1),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: Theme.of(context).dividerColor, width: 1),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Date Filter Button
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Filter by Date',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          GestureDetector(
                            onTap: _selectDateRange,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Color(0xFF294EC3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${DateFormat('MMM dd').format(_startDate)} - ${DateFormat('MMM dd, yyyy').format(_endDate)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Category Filter Buttons
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Filter by Category',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          Row(
                            children: [
                              if (showIncomeFilter)
                                CategoryFilterIconButton(
                                  icon: Icons.toc_rounded,
                                  iconColor: Colors.green,
                                  flipIconHorizontally: true,
                                  selectedCount:
                                      _selectedIncomeCategoryIds.length,
                                  tooltip: 'Income categories',
                                  onTap: () => _openCategoryFilterSheet(
                                    provider,
                                    flow: 'income',
                                  ),
                                ),
                              if (showIncomeFilter && showExpenseFilter)
                                const SizedBox(width: 8),
                              if (showExpenseFilter)
                                CategoryFilterIconButton(
                                  icon: Icons.toc_rounded,
                                  iconColor:
                                      Theme.of(context).colorScheme.error,
                                  flipIconHorizontally: true,
                                  selectedCount:
                                      _selectedExpenseCategoryIds.length,
                                  tooltip: 'Expense categories',
                                  onTap: () => _openCategoryFilterSheet(
                                    provider,
                                    flow: 'expense',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visibleTransaction.length,
                      itemBuilder: (context, index) {
                        final transaction = visibleTransaction[index];
                        return TransactionListItem(
                          transaction: transaction,
                          bankLabel: _getBankLabel(transaction),
                          provider: provider,
                          formatCurrency: _formatCurrency,
                          onTap: () async {
                            await showCategorizeTransactionSheet(
                              context: context,
                              provider: provider,
                              transaction: transaction,
                            );
                          },
                        );
                      },
                    ),
                  ]),
                ),
              ])
            ],
          )));
    });
  }
}
