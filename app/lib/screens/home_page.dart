import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/bank_detection_service.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/widgets/auth_page.dart';
import 'package:totals/widgets/home_tabs.dart';
import 'package:totals/widgets/banks_summary_list.dart';
import 'package:totals/widgets/bank_detail.dart';
import 'package:totals/widgets/add_account_form.dart';
import 'package:totals/widgets/total_balance_card.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/widgets/custom_bottom_nav.dart';
import 'package:totals/widgets/detected_banks_widget.dart';
import 'package:totals/screens/failed_parses_page.dart';
import 'package:totals/screens/analytics_page.dart';
import 'package:totals/screens/web_page.dart';
import 'package:totals/screens/settings_page.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_intent_bus.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/widgets/today_transactions_list.dart';
import 'package:totals/widgets/categorize_transaction_sheet.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  bool _isAuthenticating = false;
  bool _hasCheckedInternet = false;
  bool _hasCheckedNotificationPermissions = false;

  // UI State
  bool showTotalBalance = false;
  List<String> visibleTotalBalancesForSubCards = [];
  int activeTab = 0;
  int _bottomNavIndex = 0;
  StreamSubscription<NotificationIntent>? _notificationIntentSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize services and check permissions
    _initPermissions().catchError((error) {
      if (kDebugMode) {
        print('debug: _initPermissions failed: $error');
      }
    });

    _notificationIntentSub = NotificationIntentBus.instance.stream.listen(
      (intent) {
        if (!mounted) return;
        if (intent is CategorizeTransactionIntent) {
          _openTodayAndCategorize(intent.reference);
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.instance.emitLaunchIntentIfAny();
    });

    // Set up callback with mounted check
    _smsService.onTransactionSaved = (tx) {
      if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        Provider.of<TransactionProvider>(context, listen: false).loadData();

        final bankLabel = AppConstants.banks
            .firstWhere(
              (b) => b.id == tx.bankId,
              orElse: () => const Bank(
                id: -1,
                name: 'Totals',
                shortName: 'Totals',
                codes: [],
                image: '',
              ),
            )
            .shortName;

        final sign = tx.type == 'CREDIT'
            ? '+'
            : tx.type == 'DEBIT'
                ? '-'
                : '';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$bankLabel: $sign ETB ${formatNumberWithComma(tx.amount)} • Tap to categorize',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      });
    };

    // Initial Load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<TransactionProvider>(context, listen: false).loadData();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticateIfAvailable();
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
    _notificationIntentSub?.cancel();
    _pageController.dispose();
    _mainPageController.dispose();
    super.dispose();
  }

  Future<void> _openTodayAndCategorize(String reference) async {
    if (!mounted) return;

    if (_bottomNavIndex != 0) {
      setState(() {
        _bottomNavIndex = 0;
      });
      _mainPageController.jumpToPage(0);
    }

    changeTab(HomeTabs.recentTabId);

    final provider = Provider.of<TransactionProvider>(context, listen: false);
    await provider.loadData();
    if (!mounted) return;

    Transaction? match;
    for (final t in provider.allTransactions) {
      if (t.reference == reference) {
        match = t;
        break;
      }
    }

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction not found')),
      );
      return;
    }

    await showCategorizeTransactionSheet(
      context: context,
      provider: provider,
      transaction: match,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Provider.of<TransactionProvider>(context, listen: false).loadData();
    }
  }

  Future<void> authenticateUser() async {
    if (_isAuthenticated) {
      setState(() {
        _isAuthenticated = false;
        _hasCheckedInternet = false; // Reset when logging out
      });
      return;
    }

    await _authenticateIfAvailable();
  }

  void _setAuthenticated(bool value) {
    if (!mounted) return;
    setState(() {
      _isAuthenticated = value;
    });

    if (value && !_hasCheckedInternet) {
      _hasCheckedInternet = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkInternetRequirement();
      });
    }
  }

  bool _shouldBypassSecurity(PlatformException error) {
    final code = error.code.toLowerCase();
    return code.contains('notavailable') ||
        code.contains('notenrolled') ||
        code.contains('passcodenotset') ||
        code.contains('passcode_not_set') ||
        code.contains('not_enrolled') ||
        code.contains('not_available');
  }

  Future<void> _authenticateIfAvailable() async {
    if (_isAuthenticated || _isAuthenticating) return;

    if (kIsWeb) {
      _setAuthenticated(true);
      return;
    }

    setState(() {
      _isAuthenticating = true;
    });

    try {
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();

      if (!canCheckBiometrics && !isDeviceSupported) {
        _setAuthenticated(true);
        return;
      }

      final didAuthenticate = await _auth.authenticate(
        localizedReason: 'Please authenticate to show account details',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      if (!mounted) return;
      if (didAuthenticate) {
        _setAuthenticated(true);
      }
    } on PlatformException catch (e) {
      if (_shouldBypassSecurity(e)) {
        _setAuthenticated(true);
      } else {
        if (kDebugMode) {
          print('debug: Authentication error: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('debug: Authentication error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }

  Future<void> _checkInternetRequirement() async {
    final configService = SmsConfigService();
    final needsInternet = await configService.initializePatterns();
    if (needsInternet && mounted) {
      _showInternetDialog();
    }
  }

  Future<void> _initPermissions() async {
    try {
      // Check SMS permission status first
      final smsPermissionStatus = await Permission.sms.status;
      final smsAlreadyGranted = smsPermissionStatus.isGranted;

      // Initialize SMS service (this may show a permission dialog)
      await _smsService.init();

      // If SMS permission was already granted, we can check notification permissions immediately
      // Otherwise, wait briefly to allow the SMS permission dialog to be shown and dismissed
      final delay = smsAlreadyGranted
          ? const Duration(
              milliseconds: 1) // Minimal delay if no SMS dialog will show
          : const Duration(
              milliseconds: 1); // Brief delay if SMS dialog was shown

      await Future.delayed(delay);

      if (mounted && !_hasCheckedNotificationPermissions) {
        await _checkNotificationPermissions();
      }
    } catch (e) {
      if (kDebugMode) {
        print('debug: Error in _initPermissions: $e');
      }
      // Even if there's an error, try to check notification permissions
      if (mounted && !_hasCheckedNotificationPermissions) {
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          await _checkNotificationPermissions();
        }
      }
    }
  }

  Future<void> _checkNotificationPermissions() async {
    if (kIsWeb) return;
    if (_hasCheckedNotificationPermissions) return;

    // Set flag immediately to prevent duplicate checks
    _hasCheckedNotificationPermissions = true;

    final permissionsGranted =
        await NotificationService.instance.arePermissionsGranted();
    if (!permissionsGranted && mounted) {
      // Automatically trigger the system permission dialog
      await NotificationService.instance.requestPermissionsIfNeeded();
    }
  }

  Future<void> _openFailedParsesPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FailedParsesPage()),
    );
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
    List<int> tabs = [0, HomeTabs.recentTabId];
    if (provider.bankSummaries.isNotEmpty) {
      tabs.addAll(provider.bankSummaries.map((b) => b.bankId));
    }
    return tabs;
  }

  List<Transaction> _todayTransactions(TransactionProvider provider) {
    final now = DateTime.now();
    return provider.allTransactions.where((t) {
      final raw = t.time;
      if (raw == null || raw.isEmpty) return false;
      try {
        final dt = DateTime.parse(raw).toLocal();
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      } catch (_) {
        return false;
      }
    }).toList(growable: false);
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
                  final bankConfigService = BankConfigService();
                  try {
                    await configService.syncRemoteConfig();
                    await bankConfigService.syncRemoteConfig();
                  } catch (e) {
                    print("debug: Error syncing patterns: $e");
                  }

                  // Clear bank detection cache so it picks up newly synced banks
                  final bankDetectionService = BankDetectionService();
                  await bankDetectionService.clearCache();

                  // Reload transaction data (this will recalculate bankSummaries)
                  await provider.loadData();

                  // Force rebuild to ensure UI updates with new banks
                  if (mounted) {
                    setState(() {});
                  }

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
                                    onAccountAdded: () {
                                      provider.loadData();
                                    },
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
                    : tabId == HomeTabs.recentTabId
                        ? ListView(
                            children: [
                              const SizedBox(height: 12),
                              Builder(
                                builder: (context) {
                                  final today = _todayTransactions(provider);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "Today's transactions",
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '${today.length}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              Builder(
                                builder: (context) {
                                  final today = _todayTransactions(provider);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: TodayTransactionsList(
                                      transactions: today,
                                      provider: provider,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 100),
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
                            // Debug buttons grouped in a container
                            Flexible(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceVariant
                                      .withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    //         InkWell(
                                    //           onTap: () =>
                                    //               showDebugTransactionsDialog(context),
                                    //           borderRadius: BorderRadius.circular(8),
                                    //           child: Container(
                                    //             width: 40,
                                    //             height: 40,
                                    //             padding: const EdgeInsets.all(8),
                                    //             child: Icon(
                                    //               Icons.list_alt,
                                    //               color: Theme.of(context)
                                    //                   .iconTheme
                                    //                   .color,
                                    //               size: 20,
                                    //             ),
                                    //           ),
                                    //         ),
                                    //         InkWell(
                                    //           onTap: () => showDebugSmsDialog(context),
                                    //           borderRadius: BorderRadius.circular(8),
                                    //           child: Container(
                                    //             width: 40,
                                    //             height: 40,
                                    //             padding: const EdgeInsets.all(8),
                                    //             child: Icon(
                                    //               Icons.message_outlined,
                                    //               color: Theme.of(context)
                                    //                   .iconTheme
                                    //                   .color,
                                    //               size: 20,
                                    //             ),
                                    //           ),
                                    //         ),
                                    InkWell(
                                      onTap: _openFailedParsesPage,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Tooltip(
                                        message: 'View Failed Parsings',
                                        child: Container(
                                          width: 40,
                                          height: 40,
                                          padding: const EdgeInsets.all(8),
                                          child: Icon(
                                            Icons.error_outline,
                                            color: Theme.of(context)
                                                .iconTheme
                                                .color,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Debug menu button
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
