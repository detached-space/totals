import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/widgets/auth_page.dart';
import 'package:totals/widgets/home_tabs.dart';
import 'package:totals/widgets/banks_summary_list.dart';
import 'package:totals/widgets/bank_detail.dart';
import 'package:totals/widgets/add_account_form.dart';
import 'package:totals/widgets/total_balance_card.dart';
import 'package:totals/widgets/debug_sms_dialog.dart';
import 'package:totals/widgets/debug_transactions_dialog.dart';
import 'package:totals/widgets/failed_parse_dialog.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final LocalAuthentication _auth = LocalAuthentication();
  final SmsService _smsService = SmsService();
  final PageController _pageController = PageController();

  bool _isAuthenticated = false;

  // UI State
  bool showTotalBalance = false;
  List<String> visibleTotalBalancesForSubCards = [];
  int activeTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize services
    _smsService.init();
    _smsService.onMessageReceived = () {
      // Reload data on new SMS
      Provider.of<TransactionProvider>(context, listen: false).loadData();
    };

    // Initial Load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TransactionProvider>(context, listen: false).loadData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Provider.of<TransactionProvider>(context, listen: false).loadData();
      // _syncService.syncTransactions();
    }
  }

  Future<void> authenticateUser() async {
    if (!_isAuthenticated) {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      if (canAuthenticateWithBiometrics) {
        try {
          final bool didAuthenticate = await _auth.authenticate(
              localizedReason: 'Please authenticate to show account details',
              options: const AuthenticationOptions(biometricOnly: false));
          setState(() {
            _isAuthenticated = didAuthenticate;
          });
        } catch (e) {
          print(e);
        }
      }
    } else {
      setState(() {
        _isAuthenticated = false;
      });
    }
  }

  void changeTab(int tabId) {
    setState(() {
      activeTab = tabId;
    });
    // Find the index of the tab in the tabs list
    final tabs = _getTabs();
    final index = tabs.indexOf(tabId);
    if (index != -1 && _pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  List<int> _getTabs() {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    List<int> tabs = [0];
    if (provider.bankSummaries.isNotEmpty) {
      tabs.addAll(provider.bankSummaries.map((b) => b.bankId));
    }
    return tabs;
  }

  Future<void> _selectDate(BuildContext context) async {
    var provider = Provider.of<TransactionProvider>(context, listen: false);
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: provider.selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      provider.updateDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return AuthPage(onAuthenticate: authenticateUser);
    }

    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        // Calculate tabs dynamically based on available banks
        List<int> tabs = [0];
        if (provider.bankSummaries.isNotEmpty) {
          tabs.addAll(provider.bankSummaries.map((b) => b.bankId));
        }

        return Scaffold(
          backgroundColor: const Color(0xffF1F4FF),
          floatingActionButton: SizedBox(
            width: 65,
            height: 65,
            child: FloatingActionButton(
              onPressed: () {
                showModalBottomSheet(
                  isScrollControlled: true,
                  context: context,
                  builder: (context) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 20, horizontal: 20),
                        height: MediaQuery.of(context).size.height * 0.83,
                        child: SingleChildScrollView(
                          child: RegisterAccountForm(
                            onSubmit: () {
                              provider.loadData();
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              backgroundColor: const Color(0xFF294EC3),
              shape: const CircleBorder(),
              child: const Icon(
                Icons.add,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          appBar: AppBar(
              backgroundColor: const Color(0xffF1F4FF),
              toolbarHeight: 60,
              scrolledUnderElevation: 0,
              elevation: 0,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        child: Image.asset(
                          "assets/images/logo-text.png",
                          fit: BoxFit.cover,
                          width: 100,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.list_alt,
                            color: Color(0xFF8DA1E1), size: 25),
                        onPressed: () => showDebugTransactionsDialog(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_month_outlined,
                            color: Color(0xFF8DA1E1), size: 25),
                        onPressed: () => _selectDate(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.message_outlined,
                            color: Color(0xFF8DA1E1), size: 25),
                        onPressed: () => showDebugSmsDialog(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.error_outline,
                            color: Color(0xFF8DA1E1), size: 25),
                        onPressed: () => showFailedParseDialog(context),
                        tooltip: "View Failed Parsings",
                      ),
                      IconButton(
                        icon: const Icon(Icons.lock_outline,
                            color: Color(0xFF8DA1E1), size: 25),
                        onPressed: () {
                          setState(() {
                            _isAuthenticated = false;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              )),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeTabs(
                  tabs: tabs, activeTab: activeTab, onChangeTab: changeTab),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      activeTab = tabs[index];
                    });
                  },
                  itemCount: tabs.length,
                  itemBuilder: (context, index) {
                    final tabId = tabs[index];
                    return RefreshIndicator(
                      onRefresh: () async {
                        await provider.loadData();
                        // await _syncService.syncTransactions();
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Page Refreshed')));
                      },
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),
                            tabId == 0
                                ? SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.8,
                                    child: Column(
                                      children: [
                                        TotalBalanceCard(
                                          summary: provider.summary,
                                          showBalance: showTotalBalance,
                                          onToggleBalance: () {
                                            setState(() {
                                              showTotalBalance =
                                                  !showTotalBalance;
                                              visibleTotalBalancesForSubCards =
                                                  visibleTotalBalancesForSubCards
                                                          .isEmpty
                                                      ? provider.bankSummaries
                                                          .map((e) => e.bankId
                                                              .toString())
                                                          .toList()
                                                      : [];
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        Flexible(
                                          child: BanksSummaryList(
                                              banks: provider.bankSummaries,
                                              visibleTotalBalancesForSubCards:
                                                  visibleTotalBalancesForSubCards),
                                        )
                                      ],
                                    ))
                                : BankDetail(
                                    bankId: tabId,
                                    accountSummaries: provider.accountSummaries
                                        .where((e) => e.bankId == tabId)
                                        .toList(),
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
        );
      },
    );
  }
}
