import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/bank_config_service.dart';
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
import 'package:totals/widgets/category_filter_button.dart';
import 'package:totals/widgets/category_filter_sheet.dart';
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
  bool _hasInitializedPermissions = false;
  bool _hasInitializedSmsPermissions = false;
  bool _isRefreshingTodaySms = false;

  // UI State
  bool showTotalBalance = false;
  List<String> visibleTotalBalancesForSubCards = [];
  int activeTab = 0;
  int _bottomNavIndex = 0;
  StreamSubscription<NotificationIntent>? _notificationIntentSub;
  String? _pendingNotificationReference;
  String? _highlightedReference;
  Set<int?> _selectedTodayIncomeCategoryIds = {};
  Set<int?> _selectedTodayExpenseCategoryIds = {};
  Set<String> _selectedTodayReferences = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _notificationIntentSub = NotificationIntentBus.instance.stream.listen(
      (intent) {
        if (!mounted) return;
        if (intent is CategorizeTransactionIntent) {
          _handleNotificationCategorize(intent.reference);
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initSmsPermissions();
      if (mounted) {
        _authenticateIfAvailable();
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
    _notificationIntentSub?.cancel();
    _pageController.dispose();
    _mainPageController.dispose();
    super.dispose();
  }

  Future<void> _openTodayAndCategorize(String reference) async {
    await _openTodayFromNotification(reference, openSheet: true);
  }

  Future<void> _openTodayFromNotification(
    String reference, {
    required bool openSheet,
  }) async {
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

    if (openSheet) {
      await showCategorizeTransactionSheet(
        context: context,
        provider: provider,
        transaction: match,
      );
    } else {
      _highlightTransaction(reference);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tap the highlighted transaction to categorize it.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _handleNotificationCategorize(String reference) {
    if (!_isAuthenticated) {
      _pendingNotificationReference = reference;
      _authenticateIfAvailable();
      return;
    }
    _openTodayFromNotification(reference, openSheet: true);
  }

  void _highlightTransaction(String reference) {
    setState(() {
      _highlightedReference = reference;
    });
    Future.delayed(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_highlightedReference != reference) return;
      setState(() {
        _highlightedReference = null;
      });
    });
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

    await _initSmsPermissions();
    await _authenticateIfAvailable();
  }

  void _setAuthenticated(bool value) {
    if (!mounted) return;
    setState(() {
      _isAuthenticated = value;
    });

    if (value && !_hasInitializedPermissions) {
      _hasInitializedPermissions = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initPermissions().catchError((error) {
          if (kDebugMode) {
            print('debug: _initPermissions failed: $error');
          }
        });
      });
    }

    if (value && _pendingNotificationReference != null) {
      final reference = _pendingNotificationReference!;
      _pendingNotificationReference = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openTodayFromNotification(reference, openSheet: true);
      });
    }

    if (value && !_hasCheckedInternet) {
      _hasCheckedInternet = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _checkInternetRequirement();
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

  Future<void> _initSmsPermissions() async {
    if (_hasInitializedSmsPermissions) return;
    _hasInitializedSmsPermissions = true;
    try {
      await _smsService.init();
    } catch (e) {
      if (kDebugMode) {
        print('debug: SMS permission init failed: $e');
      }
    }
  }

  Future<void> _checkInternetRequirement() async {
    final configService = SmsConfigService();
    final bankConfigService = BankConfigService();

    // Check if patterns and banks exist
    final needsInternetForPatterns = await configService.initializePatterns();
    final needsInternetForBanks = await bankConfigService.initializeBanks();

    // If either needs internet and we don't have it, show dialog
    if ((needsInternetForPatterns || needsInternetForBanks) && mounted) {
      _showInternetDialog();
    }
  }

  Future<void> _initPermissions() async {
    try {
      if (!_hasInitializedSmsPermissions) {
        _hasInitializedSmsPermissions = true;
        await _smsService.init();
      }

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

  void _syncActiveTabWithPage(List<int> tabs) {
    if (!mounted) return;
    if (!_pageController.hasClients || tabs.isEmpty) return;

    final pageIndex =
        _pageController.page?.round() ?? _pageController.initialPage;
    final safeIndex = pageIndex.clamp(0, tabs.length - 1);
    final pageTabId = tabs[safeIndex];

    if (activeTab != pageTabId) {
      setState(() {
        activeTab = pageTabId;
      });
    }
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

  bool _matchesCategorySelection(int? categoryId, Set<int?> selection) {
    if (selection.isEmpty) return true;
    if (categoryId == null) return selection.contains(null);
    return selection.contains(categoryId);
  }

  bool _matchesCategoryFilter(Transaction transaction) {
    if (_selectedTodayIncomeCategoryIds.isEmpty &&
        _selectedTodayExpenseCategoryIds.isEmpty) {
      return true;
    }
    if (transaction.type == 'CREDIT') {
      return _matchesCategorySelection(
          transaction.categoryId, _selectedTodayIncomeCategoryIds);
    }
    if (transaction.type == 'DEBIT') {
      return _matchesCategorySelection(
          transaction.categoryId, _selectedTodayExpenseCategoryIds);
    }
    return true;
  }

  List<Transaction> _filterByCategory(List<Transaction> transactions) {
    return transactions.where(_matchesCategoryFilter).toList(growable: false);
  }

  Future<void> _openTodayCategoryFilterSheet(
    TransactionProvider provider, {
    required String flow,
  }) async {
    final result = await showCategoryFilterSheet(
      context: context,
      provider: provider,
      selectedCategoryIds: flow == 'income'
          ? _selectedTodayIncomeCategoryIds
          : _selectedTodayExpenseCategoryIds,
      flow: flow,
    );
    if (result == null) return;
    setState(() {
      if (flow == 'income') {
        _selectedTodayIncomeCategoryIds = result.toSet();
      } else {
        _selectedTodayExpenseCategoryIds = result.toSet();
      }
    });
  }

  bool get _isTodaySelectionMode => _selectedTodayReferences.isNotEmpty;

  void _toggleTodaySelection(Transaction transaction) {
    setState(() {
      if (_selectedTodayReferences.contains(transaction.reference)) {
        _selectedTodayReferences.remove(transaction.reference);
      } else {
        _selectedTodayReferences.add(transaction.reference);
      }
      if (_highlightedReference == transaction.reference) {
        _highlightedReference = null;
      }
    });
  }

  void _clearTodaySelection() {
    if (_selectedTodayReferences.isEmpty) return;
    setState(() {
      _selectedTodayReferences.clear();
    });
  }

  void _toggleSelectAllToday(List<Transaction> transactions) {
    final references =
        transactions.map((transaction) => transaction.reference).toSet();
    setState(() {
      if (references.isEmpty) {
        _selectedTodayReferences.clear();
        return;
      }
      final isAllSelected =
          _selectedTodayReferences.length == references.length &&
              _selectedTodayReferences.containsAll(references);
      if (isAllSelected) {
        _selectedTodayReferences.clear();
      } else {
        _selectedTodayReferences = references;
      }
    });
  }

  void _invertTodaySelection(List<Transaction> transactions) {
    final references =
        transactions.map((transaction) => transaction.reference).toSet();
    setState(() {
      _selectedTodayReferences = references.difference(_selectedTodayReferences);
    });
  }

  void _pruneTodaySelection(Set<String> validReferences) {
    if (_selectedTodayReferences.isEmpty) return;
    if (_selectedTodayReferences.every(validReferences.contains)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedTodayReferences.removeWhere(
          (reference) => !validReferences.contains(reference),
        );
      });
    });
  }

  Future<void> _confirmDeleteTodaySelection(
    TransactionProvider provider,
  ) async {
    if (_selectedTodayReferences.isEmpty) return;
    final count = _selectedTodayReferences.length;
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
    final clearHighlight = _highlightedReference != null &&
        _selectedTodayReferences.contains(_highlightedReference);
    await provider.deleteTransactionsByReferences(_selectedTodayReferences);
    if (!mounted) return;
    setState(() {
      _selectedTodayReferences.clear();
      if (clearHighlight) {
        _highlightedReference = null;
      }
    });
  }

  Future<void> _refreshTodaySms(TransactionProvider provider) async {
    if (_isRefreshingTodaySms) return;
    setState(() {
      _isRefreshingTodaySms = true;
    });

    try {
      final result = await _smsService.syncTodayBankSms();
      if (!mounted) return;

      if (result.permissionDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS permission denied.'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      if (result.added > 0) {
        await provider.loadData();
      }

      final message = result.added > 0
          ? 'Added ${result.added} new transactions'
          : 'No missed transactions';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to refresh SMS'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingTodaySms = false;
        });
      }
    }
  }

  Widget _buildTodayRefreshButton(TransactionProvider provider) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.onSurfaceVariant.withOpacity(0.2);
    final background = theme.colorScheme.surfaceVariant.withOpacity(0.3);
    final iconColor = theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: "Refresh today's SMS",
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isRefreshingTodaySms ? null : () => _refreshTodaySms(provider),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: _isRefreshingTodaySms
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                      ),
                    )
                  : Icon(
                      Icons.refresh_rounded,
                      size: 20,
                      color: iconColor,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeContent(TransactionProvider provider) {
    final tabs = _getTabs();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncActiveTabWithPage(tabs);
    });

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
                          // const SizedBox(height: 12),
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
                        ],
                      )
                    : tabId == HomeTabs.recentTabId
                        ? Builder(
                            builder: (context) {
                              final today = _todayTransactions(provider);
                              final filteredToday = _filterByCategory(today);
                              final filteredReferences = filteredToday
                                  .map((transaction) => transaction.reference)
                                  .toSet();
                              _pruneTodaySelection(filteredReferences);
                              final selectionCount =
                                  _selectedTodayReferences.length;

                              final headerRow = Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_isTodaySelectionMode) ...[
                                          IconButton(
                                            icon: const Icon(Icons.close),
                                            tooltip: 'Clear selection',
                                            onPressed: _clearTodaySelection,
                                          ),
                                          Text(
                                            '$selectionCount selected',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                            ),
                                          ),
                                        ] else ...[
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
                                          const SizedBox(width: 8),
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
                                              '${filteredToday.length}',
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
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: _isTodaySelectionMode
                                        ? [
                                            IconButton(
                                              tooltip: 'Select all',
                                              icon: const Icon(
                                                  Icons.select_all),
                                              onPressed: () =>
                                                  _toggleSelectAllToday(
                                                      filteredToday),
                                            ),
                                            IconButton(
                                              tooltip: 'Invert selection',
                                              icon: const Icon(Icons.swap_horiz),
                                              onPressed: () =>
                                                  _invertTodaySelection(
                                                      filteredToday),
                                            ),
                                            IconButton(
                                              tooltip: 'Delete selected',
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                              onPressed: () =>
                                                  _confirmDeleteTodaySelection(
                                                      provider),
                                            ),
                                          ]
                                        : [
                                            _buildTodayRefreshButton(provider),
                                            const SizedBox(width: 8),
                                            CategoryFilterIconButton(
                                              icon: Icons.toc_rounded,
                                              iconColor: Colors.green,
                                              flipIconHorizontally: true,
                                              selectedCount:
                                                  _selectedTodayIncomeCategoryIds
                                                      .length,
                                              tooltip: 'Income categories',
                                              onTap: () =>
                                                  _openTodayCategoryFilterSheet(
                                                provider,
                                                flow: 'income',
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            CategoryFilterIconButton(
                                              icon: Icons.toc_rounded,
                                              iconColor: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                              flipIconHorizontally: true,
                                              selectedCount:
                                                  _selectedTodayExpenseCategoryIds
                                                      .length,
                                              tooltip: 'Expense categories',
                                              onTap: () =>
                                                  _openTodayCategoryFilterSheet(
                                                provider,
                                                flow: 'expense',
                                              ),
                                            ),
                                          ],
                                  ),
                                ],
                              );

                              return CustomScrollView(
                                slivers: [
                                  const SliverToBoxAdapter(
                                    child: SizedBox(height: 12),
                                  ),
                                  SliverPersistentHeader(
                                    pinned: true,
                                    delegate: _StickyHeaderDelegate(
                                      height: 64,
                                      child: Container(
                                        color: Theme.of(context)
                                            .scaffoldBackgroundColor,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        child: headerRow,
                                      ),
                                    ),
                                  ),
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: TodayTransactionsList(
                                        transactions: filteredToday,
                                        provider: provider,
                                        highlightedReference:
                                            _highlightedReference,
                                        selectionMode: _isTodaySelectionMode,
                                        selectedReferences:
                                            _selectedTodayReferences,
                                        onTransactionTap:
                                            (transaction) async {
                                          if (_isTodaySelectionMode) {
                                            _toggleTodaySelection(transaction);
                                            return;
                                          }
                                          setState(() {
                                            if (_highlightedReference ==
                                                transaction.reference) {
                                              _highlightedReference = null;
                                            }
                                          });
                                          await showCategorizeTransactionSheet(
                                            context: context,
                                            provider: provider,
                                            transaction: transaction,
                                          );
                                        },
                                        onTransactionLongPress: (transaction) {
                                          _toggleTodaySelection(transaction);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
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
            return Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              appBar: _buildHomeAppBar(),
              body: _buildHomeContent(provider),
            );
          },
        ),
        const AnalyticsPage(),
        const WebPage(),
        const SettingsPage(),
      ],
    );
  }

  PreferredSizeWidget _buildHomeAppBar() {
    return AppBar(
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

                        // InkWell(
                        //   onTap: _openFailedParsesPage,
                        //   borderRadius: BorderRadius.circular(8),
                        //   child: Tooltip(
                        //     message: 'View Failed Parsings',
                        //     child: Container(
                        //       padding: const EdgeInsets.all(8),
                        //       child: Icon(
                        //         Icons.error_outline,
                        //         color: Theme.of(context).iconTheme.color,
                        //         size: 22,
                        //       ),
                        //     ),
                        //   ),
                        // ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.error_outline,
                        color: Theme.of(context).iconTheme.color, size: 22),
                    onPressed: _openFailedParsesPage,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                ),
                // Debug menu button
                const SizedBox(width: 7),
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
                        color: Theme.of(context).iconTheme.color, size: 22),
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
      ),
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

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _StickyHeaderDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return height != oldDelegate.height || child != oldDelegate.child;
  }
}
