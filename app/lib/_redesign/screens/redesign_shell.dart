import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/_redesign/screens/home_page.dart';
import 'package:totals/_redesign/screens/lock_screen.dart';
import 'package:totals/_redesign/screens/money/money_page.dart';
import 'package:totals/_redesign/screens/budget_page.dart';
import 'package:totals/_redesign/screens/settings_page.dart';
import 'package:totals/_redesign/screens/tools_page.dart';
import 'package:totals/_redesign/widgets/redesign_bottom_nav.dart';
import 'package:totals/screens/accounts_page.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/profile.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/user_account.dart';
import 'package:totals/providers/budget_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/repositories/user_account_repository.dart';
import 'package:totals/services/bank_detection_startup_service.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_intent_bus.dart';
import 'package:totals/services/background_refresh_signal_service.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/services/widget_launch_intent_service.dart';
import 'package:totals/utils/account_share_payload.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/widgets/account_share_qr_code.dart';
import 'package:totals/widgets/add_cash_transaction_sheet.dart';

class RedesignShell extends StatefulWidget {
  const RedesignShell({super.key});

  @override
  State<RedesignShell> createState() => RedesignShellState();
}

class RedesignShellState extends State<RedesignShell>
    with WidgetsBindingObserver {
  // Temporary kill switch for the automatic battery optimization prompt.
  // Users can still request the exemption manually from notification settings.
  static const bool _autoShowBatteryOptimizationPrompt = false;
  static const int _homeIndex = 0;
  static const int _moneyIndex = 1;
  static const int _budgetIndex = 2;
  static const int _settingsIndex = 4;
  final GlobalKey<RedesignMoneyPageState> _moneyPageKey =
      GlobalKey<RedesignMoneyPageState>();
  final GlobalKey<RedesignBudgetPageState> _budgetPageKey =
      GlobalKey<RedesignBudgetPageState>();
  final PageController _pageController =
      PageController(initialPage: _homeIndex);
  DateTime? _lastProfileTabTapAt;
  int _currentIndex = _homeIndex;
  int? _activeProfileId;
  StreamSubscription<WidgetLaunchTarget>? _widgetLaunchIntentSub;
  StreamSubscription<NotificationIntent>? _notificationIntentSub;
  StreamSubscription<void>? _backgroundRefreshSub;
  final ProfileRepository _profileRepo = ProfileRepository();
  final AccountRepository _accountRepo = AccountRepository();
  final UserAccountRepository _userAccountRepo = UserAccountRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  final SmsService _smsService = SmsService();

  // Auth state
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;
  bool _hasInitializedSmsPermissions = false;
  bool _hasCheckedNotificationPermissions = false;
  String? _pendingNotificationReference;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BackgroundRefreshSignalService.instance.ensureListening();
    unawaited(BankDetectionStartupService.runOnAppOpen());
    unawaited(_loadActiveProfileId());

    _widgetLaunchIntentSub = WidgetLaunchIntentService.instance.stream.listen(
      (target) {
        if (target != WidgetLaunchTarget.budget) return;
        _onTabSelected(_budgetIndex);
      },
    );

    _notificationIntentSub = NotificationIntentBus.instance.stream.listen(
      (intent) {
        if (!mounted) return;
        if (intent is CategorizeTransactionIntent) {
          unawaited(_handleNotificationCategorize(intent.reference));
        }
      },
    );

    _backgroundRefreshSub =
        BackgroundRefreshSignalService.instance.stream.listen((_) {
      if (!mounted) return;
      final transactionProvider =
          Provider.of<TransactionProvider>(context, listen: false);
      final budgetProvider =
          Provider.of<BudgetProvider>(context, listen: false);
      unawaited(transactionProvider.loadData());
      unawaited(budgetProvider.loadBudgets());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadHomeDataWhileLocked();
    });

    // Refresh immediately after a foreground save. addPostFrameCallback()
    // can sit idle until the next UI interaction if no frame is scheduled.
    _smsService.onTransactionSaved = (tx) {
      if (!mounted) return;

      final transactionProvider =
          Provider.of<TransactionProvider>(context, listen: false);
      final budgetProvider = Provider.of<BudgetProvider>(
        context,
        listen: false,
      );

      unawaited(transactionProvider.loadData());
      unawaited(budgetProvider.loadBudgets());

      final bankLabel = transactionProvider.getBankShortName(tx.bankId);
      final sign = tx.type == 'CREDIT'
          ? '+'
          : tx.type == 'DEBIT'
              ? '-'
              : '';

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            '$bankLabel: $sign ETB ${formatNumberWithComma(tx.amount)}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialTarget =
          WidgetLaunchIntentService.instance.consumePendingTarget();
      if (initialTarget != WidgetLaunchTarget.budget) return;
      _onTabSelected(_budgetIndex);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.instance.emitLaunchIntentIfAny();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initSmsPermissions();
      await _checkNotificationPermissions();
      if (mounted) _authenticateIfAvailable();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetLaunchIntentSub?.cancel();
    _notificationIntentSub?.cancel();
    _backgroundRefreshSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isAuthenticated) {
      unawaited(
        Provider.of<TransactionProvider>(context, listen: false).loadData(),
      );
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

  void _preloadHomeDataWhileLocked() {
    if (!mounted || _isAuthenticated) return;

    final provider = Provider.of<TransactionProvider>(context, listen: false);
    if (provider.dataVersion > 0 || provider.isLoading) return;
    unawaited(provider.loadData());
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

  Future<void> _checkNotificationPermissions() async {
    if (kIsWeb) return;
    if (_hasCheckedNotificationPermissions) return;
    _hasCheckedNotificationPermissions = true;

    final permissionsGranted =
        await NotificationService.instance.arePermissionsGranted();
    if (!permissionsGranted && mounted) {
      await NotificationService.instance.requestPermissionsIfNeeded();
    }
  }

  static const String _batteryOptDismissedKey =
      'battery_optimization_prompt_dismissed';

  Future<void> _checkBatteryOptimization() async {
    if (!_autoShowBatteryOptimizationPrompt) return;
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!mounted) return;

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_batteryOptDismissedKey) == true) return;

      if (!mounted) return;

      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Keep transaction alerts active'),
          content: const Text(
            'To make sure you get notified instantly when a transaction '
            'happens, Totals needs to be excluded from battery optimization. '
            'Without this, your phone may stop delivering notifications '
            'in the background.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                prefs.setBool(_batteryOptDismissedKey, true);
                Navigator.pop(ctx, false);
              },
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );

      if (shouldRequest == true) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      if (kDebugMode) {
        print('debug: Battery optimization check failed: $e');
      }
    }
  }

  void _onAuthSuccess() {
    if (!mounted) return;
    setState(() => _isAuthenticated = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final pendingReference = _pendingNotificationReference;
      if (pendingReference != null) {
        _pendingNotificationReference = null;
        await _openTransactionFromNotification(pendingReference);
      }

      if (mounted) {
        unawaited(_checkBatteryOptimization());
      }
    });
  }

  Future<void> _handleNotificationCategorize(String reference) async {
    if (!_isAuthenticated) {
      _pendingNotificationReference = reference;
      await _authenticateIfAvailable();
      return;
    }

    await _openTransactionFromNotification(reference);
  }

  Future<void> _openTransactionFromNotification(String reference) async {
    if (!mounted) return;

    if (_currentIndex != _homeIndex) {
      _onTabSelected(_homeIndex);
    }

    final provider = Provider.of<TransactionProvider>(context, listen: false);
    await provider.loadData();
    if (!mounted) return;

    Transaction? match;
    for (final transaction in provider.allTransactions) {
      if (transaction.reference == reference) {
        match = transaction;
        break;
      }
    }

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction not found'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await showTransactionDetailsSheet(
      context: context,
      transaction: match,
      provider: provider,
      initiallyExpandCategory: true,
      showQuickAccessCategories: true,
    );
  }

  Future<void> _authenticateIfAvailable() async {
    if (_isAuthenticated || _isAuthenticating) return;

    if (kIsWeb) {
      _onAuthSuccess();
      return;
    }

    setState(() => _isAuthenticating = true);

    try {
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();

      if (!canCheckBiometrics && !isDeviceSupported) {
        _onAuthSuccess();
        return;
      }

      final didAuthenticate = await _auth.authenticate(
        localizedReason: 'Authenticate to access Totals',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      if (!mounted) return;
      if (didAuthenticate) {
        _onAuthSuccess();
      }
    } on PlatformException catch (e) {
      if (_shouldBypassSecurity(e)) {
        _onAuthSuccess();
      } else {
        if (kDebugMode) print('debug: Auth error: $e');
      }
    } catch (e) {
      if (kDebugMode) print('debug: Auth error: $e');
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  void lockApp() {
    setState(() {
      _isAuthenticated = false;
      _currentIndex = _homeIndex;
    });
  }

  void openMoneyAccountsPage() {
    _onTabSelected(_moneyIndex);

    void openAccountsWhenReady([int attempts = 0]) {
      final moneyState = _moneyPageKey.currentState;
      if (moneyState != null && moneyState.mounted) {
        moneyState.openAccountsTab();
        return;
      }

      if (attempts >= 3) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openAccountsWhenReady(attempts + 1);
      });
    }

    openAccountsWhenReady();
  }

  void openSettingsPage() {
    _onTabSelected(_settingsIndex);
  }

  Future<void> _loadActiveProfileId() async {
    final activeProfileId = await _profileRepo.getActiveProfileId();
    if (!mounted) return;
    setState(() {
      _activeProfileId = activeProfileId;
    });
  }

  void _onTabSelected(int index) {
    if (index == _settingsIndex) {
      final now = DateTime.now();
      final isDoubleTap = _lastProfileTabTapAt != null &&
          now.difference(_lastProfileTabTapAt!) <=
              const Duration(milliseconds: 700);
      _lastProfileTabTapAt = now;
      if (isDoubleTap) {
        _lastProfileTabTapAt = null;
        lockApp();
        return;
      }
    } else {
      _lastProfileTabTapAt = null;
    }

    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  String _profileInitials(String name) {
    if (name.isEmpty) return '?';
    final list = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (list.isEmpty) return '?';
    if (list.length >= 2) {
      return (list[0][0] + list[1][0]).toUpperCase();
    }
    return list.first[0].toUpperCase();
  }

  String _cashAccountNumber(TransactionProvider provider) {
    final cashAccounts = provider.accountSummaries
        .where((summary) => summary.bankId == CashConstants.bankId)
        .toList();
    return cashAccounts.isNotEmpty
        ? cashAccounts.first.accountNumber
        : CashConstants.defaultAccountNumber;
  }

  void _showQuickCashSheet() {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    showAddCashTransactionSheet(
      context: context,
      provider: provider,
      accountNumber: _cashAccountNumber(provider),
      initialIsDebit: true,
    );
  }

  Future<void> _showQuickAccessAccountsSheet() async {
    final quickAccessAccounts = await _userAccountRepo.getUserAccounts();
    if (!mounted) return;

    final userAccounts = await _accountRepo.getAccounts();
    if (!mounted) return;

    final configuredBanks = await _bankConfigService.getBanks();
    if (!mounted) return;

    final banksById = <int, Bank>{
      for (final bank in configuredBanks) bank.id: bank,
    };
    for (final bank in AllBanksFromAssets.getAllBanks()) {
      banksById.putIfAbsent(bank.id, () => bank);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _QuickAccessAccountsSheet(
          quickAccessAccounts: quickAccessAccounts,
          userAccounts: userAccounts
              .where((account) => account.bank != CashConstants.bankId)
              .toList(growable: false),
          banksById: banksById,
          onManageAccounts: () {
            Navigator.of(sheetContext).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountsPage()),
            );
          },
          onCopyAccount: (account) async {
            Navigator.of(sheetContext).pop();
            await Clipboard.setData(
              ClipboardData(text: account.accountNumber),
            );
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${account.accountNumber} copied to clipboard',
                ),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          },
          onCopyUserAccount: (account) async {
            Navigator.of(sheetContext).pop();
            await Clipboard.setData(
              ClipboardData(text: account.accountNumber),
            );
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${account.accountNumber} copied to clipboard',
                ),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _onProfileLongPressAt(Rect anchorRect) async {
    final profiles = await _profileRepo.getProfiles();
    final activeProfileId = await _profileRepo.getActiveProfileId();
    if (!mounted || profiles.isEmpty) return;

    final selectedProfileId = await _showProfilePickerMenu(
      anchorRect: anchorRect,
      profiles: profiles,
      activeProfileId: activeProfileId,
    );

    if (selectedProfileId == null || selectedProfileId == activeProfileId) {
      return;
    }

    final selected = profiles.where((p) => p.id == selectedProfileId).toList();
    await _profileRepo.setActiveProfile(selectedProfileId);
    if (!mounted) return;

    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
    await txProvider.loadData();
    await budgetProvider.loadBudgets();

    if (!mounted) return;
    setState(() {
      _activeProfileId = selectedProfileId;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          selected.isNotEmpty
              ? 'Switched to ${selected.first.name}'
              : 'Profile switched',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<int?> _showProfilePickerMenu({
    required Rect anchorRect,
    required List<Profile> profiles,
    required int? activeProfileId,
  }) async {
    final overlayBox =
        Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return null;

    const rowHeight = 48.0;
    const menuVerticalGap = 8.0;
    final visibleProfiles = profiles.where((p) => p.id != null).toList();
    final anchorTopLeft = overlayBox.globalToLocal(anchorRect.topLeft);
    final anchorBottomRight = overlayBox.globalToLocal(anchorRect.bottomRight);
    final anchorRectInOverlay = Rect.fromPoints(
      anchorTopLeft,
      anchorBottomRight,
    ).inflate(4);
    final estimatedMenuHeight = (visibleProfiles.length * rowHeight) + 16.0;
    final menuTop =
        (anchorRectInOverlay.top - estimatedMenuHeight - menuVerticalGap)
            .clamp(8.0, overlayBox.size.height - estimatedMenuHeight - 8.0)
            .toDouble();
    final menuAnchorRect = Rect.fromLTWH(
      anchorRectInOverlay.left,
      menuTop,
      anchorRectInOverlay.width,
      0,
    );

    final selected = await showMenu<int>(
      context: context,
      color: AppColors.cardColor(context),
      elevation: 10,
      position: RelativeRect.fromRect(
        menuAnchorRect,
        Offset.zero & overlayBox.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: visibleProfiles.map((profile) {
        final profileId = profile.id!;
        final isActive = profileId == activeProfileId;
        return PopupMenuItem<int>(
          value: profileId,
          height: rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? AppColors.primaryLight
                      : AppColors.mutedFill(context),
                ),
                alignment: Alignment.center,
                child: Text(
                  _profileInitials(profile.name),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isActive
                        ? Colors.white
                        : AppColors.textSecondary(context),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              if (isActive)
                const Icon(
                  AppIcons.check_rounded,
                  size: 16,
                  color: AppColors.primaryLight,
                ),
            ],
          ),
        );
      }).toList(growable: false),
    );

    return selected;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return RedesignLockScreen(onUnlock: _authenticateIfAvailable);
    }

    return SafeArea(
      bottom: false,
      child: WillPopScope(
        onWillPop: () async {
          if (_currentIndex == _budgetIndex) {
            final handled =
                _budgetPageKey.currentState?.handleSystemBack() ?? false;
            if (handled) return false;
          }
          return true;
        },
        child: Scaffold(
          extendBody: true,
          body: PageView(
            controller: _pageController,
            physics: const PageScrollPhysics(),
            onPageChanged: (index) {
              if (_currentIndex == index || !mounted) return;
              setState(() {
                _currentIndex = index;
              });
            },
            children: [
              const RedesignHomePage(),
              RedesignMoneyPage(key: _moneyPageKey),
              RedesignBudgetPage(key: _budgetPageKey),
              const RedesignToolsPage(),
              RedesignSettingsPage(
                key: ValueKey('settings-${_activeProfileId ?? 'none'}'),
              ),
            ],
          ),
          bottomNavigationBar: RedesignBottomNav(
            currentIndex: _currentIndex,
            pageController: _pageController,
            onTap: _onTabSelected,
            onMoneyLongPress: _showQuickCashSheet,
            onToolsLongPress: _showQuickAccessAccountsSheet,
            onProfileLongPressAt: _onProfileLongPressAt,
          ),
        ),
      ),
    );
  }
}

class _QuickAccessAccountsSheet extends StatefulWidget {
  final List<UserAccount> quickAccessAccounts;
  final List<Account> userAccounts;
  final Map<int, Bank> banksById;
  final VoidCallback onManageAccounts;
  final ValueChanged<UserAccount> onCopyAccount;
  final ValueChanged<Account> onCopyUserAccount;

  const _QuickAccessAccountsSheet({
    required this.quickAccessAccounts,
    required this.userAccounts,
    required this.banksById,
    required this.onManageAccounts,
    required this.onCopyAccount,
    required this.onCopyUserAccount,
  });

  @override
  State<_QuickAccessAccountsSheet> createState() =>
      _QuickAccessAccountsSheetState();
}

class _QuickAccessAccountsSheetState extends State<_QuickAccessAccountsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == _selectedTabIndex) return;
      _selectedTabIndex = _tabController.index;
      if (_selectedTabIndex != 0) {
        FocusScope.of(context).unfocus();
      }
    });
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<UserAccount> get _filteredQuickAccessAccounts {
    if (_query.isEmpty) return widget.quickAccessAccounts;
    return widget.quickAccessAccounts.where((account) {
      final bank = widget.banksById[account.bankId];
      return _matchesQuery(
        bankName: bank?.name,
        bankShortName: bank?.shortName,
        accountNumber: account.accountNumber,
        holderName: account.accountHolderName,
      );
    }).toList(growable: false);
  }

  List<Account> get _filteredUserAccounts {
    return widget.userAccounts;
  }

  bool _matchesQuery({
    required String accountNumber,
    required String holderName,
    String? bankName,
    String? bankShortName,
  }) {
    return accountNumber.toLowerCase().contains(_query) ||
        holderName.toLowerCase().contains(_query) ||
        (bankName ?? '').toLowerCase().contains(_query) ||
        (bankShortName ?? '').toLowerCase().contains(_query);
  }

  AccountSharePayload? get _sharePayload {
    if (widget.userAccounts.isEmpty) return null;
    final name = widget.userAccounts
        .map((account) => account.accountHolderName.trim())
        .firstWhere((name) => name.isNotEmpty, orElse: () => '');
    if (name.isEmpty) return null;

    final entries = widget.userAccounts
        .map(
          (account) => AccountShareEntry(
            bankId: account.bank,
            accountNumber: account.accountNumber,
            name: account.accountHolderName.trim(),
          ),
        )
        .toList(growable: false);
    if (entries.isEmpty) return null;

    return AccountSharePayload(name: name, accounts: entries);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final maxAvailableHeight = (media.size.height - media.viewInsets.bottom)
        .clamp(240.0, media.size.height)
        .toDouble();
    final sheetHeight =
        (media.size.height * 0.82).clamp(240.0, maxAvailableHeight).toDouble();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Container(
            height: sheetHeight,
            decoration: BoxDecoration(
              color: AppColors.cardColor(context),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: AppColors.borderColor(context)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.mutedFill(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [
                              AppColors.blue.withOpacity(0.18),
                              AppColors.primaryLight.withOpacity(0.12),
                            ],
                          ),
                        ),
                        child: const Icon(
                          AppIcons.account_balance_outlined,
                          color: AppColors.blue,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Account Hub',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            // if (isQuickTab) ...[
                            //   const SizedBox(height: 2),
                            //   Text(
                            //     'Search and copy saved quick-access accounts.',
                            //     style: theme.textTheme.bodySmall?.copyWith(
                            //       color: AppColors.textSecondary(context),
                            //     ),
                            //   ),
                            // ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          AppColors.mutedFill(context).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: AppColors.primaryDark,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryDark.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.textSecondary(context),
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      padding: EdgeInsets.zero,
                      labelPadding: EdgeInsets.zero,
                      splashBorderRadius: BorderRadius.circular(8),
                      onTap: (index) {
                        if (index != 0) {
                          FocusScope.of(context).unfocus();
                        }
                      },
                      tabs: const [
                        Tab(height: 34, text: 'Quick'),
                        Tab(height: 34, text: 'Mine'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _QuickAccessAccountsTab(
                            accounts: _filteredQuickAccessAccounts,
                            totalAccountCount:
                                widget.quickAccessAccounts.length,
                            banksById: widget.banksById,
                            searchController: _searchController,
                            query: _query,
                            onCopyAccount: widget.onCopyAccount,
                            onManageAccounts: widget.onManageAccounts,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _UserAccountsTab(
                            accounts: _filteredUserAccounts,
                            totalAccountCount: widget.userAccounts.length,
                            banksById: widget.banksById,
                            payload: _sharePayload,
                            onCopyAccount: widget.onCopyUserAccount,
                          ),
                        ),
                      ],
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

class _QuickAccessAccountsTab extends StatelessWidget {
  final List<UserAccount> accounts;
  final int totalAccountCount;
  final Map<int, Bank> banksById;
  final TextEditingController searchController;
  final String query;
  final ValueChanged<UserAccount> onCopyAccount;
  final VoidCallback onManageAccounts;

  const _QuickAccessAccountsTab({
    required this.accounts,
    required this.totalAccountCount,
    required this.banksById,
    required this.searchController,
    required this.query,
    required this.onCopyAccount,
    required this.onManageAccounts,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAccounts = accounts.isNotEmpty;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 14),
        _QuickAccessAccountsSearchField(
          controller: searchController,
          query: query,
        ),
        const SizedBox(height: 12),
        Text(
          hasAccounts
              ? 'Saved quick-access accounts. Tap any row to copy and close.'
              : 'No saved quick-access accounts yet.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 12),
        if (hasAccounts)
          for (int index = 0; index < accounts.length; index++) ...[
            _QuickAccessAccountTile(
              account: accounts[index],
              bank: banksById[accounts[index].bankId],
              onTap: () => onCopyAccount(accounts[index]),
            ),
            if (index != accounts.length - 1) const SizedBox(height: 10),
          ]
        else
          _EmptyAccountsState(
            title: 'Nothing saved for quick access',
            subtitle:
                'Add bank accounts from the Tools screen and they will show up here.',
            actionLabel: 'Add Accounts',
            onAction: onManageAccounts,
          ),
        if (hasAccounts) ...[
          const SizedBox(height: 12),
          Text(
            'Showing ${accounts.length} of $totalAccountCount saved accounts.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onManageAccounts,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryLight,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Manage Accounts',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickAccessAccountsSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String query;

  const _QuickAccessAccountsSearchField({
    required this.controller,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search accounts, banks, or names',
        prefixIcon: Icon(
          Icons.search_rounded,
          color: AppColors.textTertiary(context),
        ),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                onPressed: controller.clear,
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: AppColors.surfaceColor(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _UserAccountsTab extends StatelessWidget {
  final List<Account> accounts;
  final int totalAccountCount;
  final Map<int, Bank> banksById;
  final AccountSharePayload? payload;
  final ValueChanged<Account> onCopyAccount;

  const _UserAccountsTab({
    required this.accounts,
    required this.totalAccountCount,
    required this.banksById,
    required this.payload,
    required this.onCopyAccount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAccounts = accounts.isNotEmpty;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 14),
        Text(
          hasAccounts
              ? 'Registered accounts used across your profile.'
              : 'No registered accounts yet.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 12),
        _AccountsQrCard(
          payload: payload,
          totalAccountCount: totalAccountCount,
        ),
        const SizedBox(height: 12),
        if (hasAccounts)
          for (int index = 0; index < accounts.length; index++) ...[
            _UserAccountTile(
              account: accounts[index],
              bank: banksById[accounts[index].bank],
              onCopy: () => onCopyAccount(accounts[index]),
            ),
            if (index != accounts.length - 1) const SizedBox(height: 10),
          ]
        else
          const _EmptyAccountsState(
            title: 'No registered accounts',
            subtitle:
                'Once your accounts are added to Totals, they will appear here and in the QR section above.',
          ),
        if (hasAccounts) ...[
          const SizedBox(height: 12),
          Text(
            '$totalAccountCount registered account${totalAccountCount == 1 ? '' : 's'} available for sharing.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ],
    );
  }
}

class _AccountsQrCard extends StatelessWidget {
  final AccountSharePayload? payload;
  final int totalAccountCount;

  const _AccountsQrCard({
    required this.payload,
    required this.totalAccountCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = payload != null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        children: [
          Text(
            payload?.name ?? 'Share Your Accounts',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasData
                ? '$totalAccountCount account${totalAccountCount == 1 ? '' : 's'} included'
                : 'No QR data available yet',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 18),
          if (hasData)
            AccountShareQrCode(
              data: AccountSharePayload.encode(payload!),
              fallback: Text(
                'Too much data to render QR',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            )
          else
            Container(
              width: 220,
              height: 220,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.cardColor(context),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              padding: const EdgeInsets.all(20),
              child: Text(
                'Add accounts first, then long-press Tools again to see your QR here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickAccessAccountTile extends StatelessWidget {
  final UserAccount account;
  final Bank? bank;
  final VoidCallback onTap;

  const _QuickAccessAccountTile({
    required this.account,
    required this.bank,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.surfaceColor(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.mutedFill(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: bank == null
                    ? Icon(
                        AppIcons.account_balance_outlined,
                        color: AppColors.textSecondary(context),
                      )
                    : Image.asset(
                        bank!.image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          AppIcons.account_balance_outlined,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bank?.shortName ?? bank?.name ?? 'Unknown Bank',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      account.accountHolderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      account.accountNumber,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.cardColor(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderColor(context)),
                ),
                child: Icon(
                  Icons.content_copy_rounded,
                  size: 18,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserAccountTile extends StatelessWidget {
  final Account account;
  final Bank? bank;
  final VoidCallback onCopy;

  const _UserAccountTile({
    required this.account,
    required this.bank,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.mutedFill(context),
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: bank == null
                ? Icon(
                    AppIcons.account_balance_outlined,
                    color: AppColors.textSecondary(context),
                  )
                : Image.asset(
                    bank!.image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      AppIcons.account_balance_outlined,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bank?.shortName ?? bank?.name ?? 'Unknown Bank',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  account.accountHolderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  account.accountNumber,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.cardColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: IconButton(
              onPressed: onCopy,
              splashRadius: 18,
              icon: Icon(
                Icons.content_copy_rounded,
                size: 18,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAccountsState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyAccountsState({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            AppIcons.account_balance_outlined,
            size: 28,
            color: AppColors.textTertiary(context),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
