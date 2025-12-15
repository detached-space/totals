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
import 'package:totals/widgets/clear_database_dialog.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/widgets/custom_bottom_nav.dart';
import 'package:totals/widgets/detected_banks_widget.dart';
import 'package:totals/screens/analytics_page.dart';
import 'package:totals/screens/web_page.dart';
import 'package:totals/screens/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final LocalAuthentication _auth = LocalAuthentication();
  final SmsService _smsService = SmsService();
  final PageController _pageController = PageController();
  final PageController _mainPageController = PageController();

  bool _isAuthenticated = false;
  bool _hasCheckedInternet = false;

  // UI State
  bool showTotalBalance = false;
  List<String> visibleTotalBalancesForSubCards = [];
  int activeTab = 0;
  int _bottomNavIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize services
    _smsService.init();

    // Set up callback with mounted check
    _smsService.onMessageReceived = () {
      // Reload data on new SMS - check if widget is still mounted
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Provider.of<TransactionProvider>(context, listen: false).loadData();
          }
        });
      }
    };

    // Initial Load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<TransactionProvider>(context, listen: false).loadData();
      }
    });
  }

  void _showInternetDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("Pattern Matching Setup"),
          content: const Text(
              "Would you like to fetch the latest pattern matching rules from the internet, or continue with the built-in patterns?"),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                // Try to initialize again
                final configService = SmsConfigService();
                final stillNeedsInternet =
                    await configService.initializePatterns();
                if (stillNeedsInternet && mounted) {
                  _showInternetDialog();
                }
              },
              child: const Text("Fetch from Internet"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Use Built-in Patterns"),
            ),
          ],
        ),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _mainPageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Provider.of<TransactionProvider>(context, listen: false).loadData();
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

          // Check internet requirement after successful authentication
          if (didAuthenticate && !_hasCheckedInternet) {
            _hasCheckedInternet = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _checkInternetRequirement();
            });
          }
        } catch (e) {
          print(e);
        }
      }
    } else {
      setState(() {
        _isAuthenticated = false;
        _hasCheckedInternet = false; // Reset when logging out
      });
    }
  }

  Future<void> _checkInternetRequirement() async {
    final configService = SmsConfigService();
    final needsInternet = await configService.initializePatterns();
    if (needsInternet && mounted) {
      _showInternetDialog();
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

  Widget _buildHomeContent(TransactionProvider provider) {
    final tabs = _getTabs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeTabs(tabs: tabs, activeTab: activeTab, onChangeTab: changeTab),
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
                  // Sync regex patterns from remote
                  final configService = SmsConfigService();
                  try {
                    await configService.syncRemoteConfig();
                  } catch (e) {
                    print("debug: Error syncing patterns: $e");
                  }

                  // Reload transaction data
                  await provider.loadData();

                  ScaffoldMessenger.of(context).showSnackBar(
                    // style it
                    SnackBar(
                      content: const Text(
                        'Sweet!',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                      backgroundColor: Colors.blue[200],
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: tabId == 0
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          TotalBalanceCard(
                            summary: provider.summary,
                            showBalance: showTotalBalance,
                            onToggleBalance: () {
                              setState(() {
                                showTotalBalance = !showTotalBalance;
                                visibleTotalBalancesForSubCards =
                                    visibleTotalBalancesForSubCards.isEmpty
                                        ? provider.bankSummaries
                                            .map((e) => e.bankId.toString())
                                            .toList()
                                        : [];
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: provider.accountSummaries.isEmpty
                                ? DetectedBanksWidget(
                                    onAccountAdded: () {
                                      provider.loadData();
                                    },
                                  )
                                : BanksSummaryList(
                                    banks: provider.bankSummaries,
                                    visibleTotalBalancesForSubCards:
                                        visibleTotalBalancesForSubCards,
                                    onBankTap: changeTab,
                                    onAddAccount: () {
                                      showModalBottomSheet(
                                        isScrollControlled: true,
                                        context: context,
                                        builder: (context) {
                                          return ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(15),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 20,
                                                      horizontal: 20),
                                              height: MediaQuery.of(context)
                                                      .size
                                                      .height *
                                                  0.83,
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
                                  ),
                          ),
                          const SizedBox(
                              height: 100), // Padding for floating nav
                        ],
                      )
                    : BankDetail(
                        bankId: tabId,
                        accountSummaries: provider.accountSummaries
                            .where((e) => e.bankId == tabId)
                            .toList(),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentPage() {
    return PageView(
      controller: _mainPageController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Consumer<TransactionProvider>(
          builder: (context, provider, child) {
            return _buildHomeContent(provider);
          },
        ),
        const AnalyticsPage(),
        const WebPage(),
        const SettingsPage(),
      ],
    );
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
          extendBody: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: _bottomNavIndex == 0
              ? AppBar(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  toolbarHeight: 70,
                  scrolledUnderElevation: 0,
                  elevation: 0,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          "assets/images/logo-text.png",
                          fit: BoxFit.contain,
                          width: 80,
                          height: 24,
                        ),
                      ),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 4),
                            // Lock button
                            Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceVariant
                                    .withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                icon: Icon(Icons.lock_outline,
                                    color: Theme.of(context).iconTheme.color,
                                    size: 22),
                                onPressed: () {
                                  setState(() {
                                    _isAuthenticated = false;
                                  });
                                },
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ))
              : null,
          body: _buildCurrentPage(),
          bottomNavigationBar: CustomBottomNavModern(
            currentIndex: _bottomNavIndex,
            onTap: (index) {
              setState(() {
                _bottomNavIndex = index;
              });
              _mainPageController.jumpToPage(index);
            },
          ),
        );
      },
    );
  }
}
