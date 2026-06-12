import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/screens/shared_expense_vault_sheets.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/shared_expense_repository.dart';
import 'package:totals/services/shared_expense_realtime_bus.dart';
import 'package:totals/services/totals_engine_client.dart';

part 'shared_expenses_page.analytics.dart';
part 'shared_expenses_page.ios_widgets.dart';
part 'shared_expenses_page.sheets.dart';
part 'shared_expenses_page.transactions.dart';
part 'shared_expenses_page.detail.dart';
part 'shared_expenses_page.group_card.dart';

void _sharedExpensesPageLog(String message) {
  if (kDebugMode) {
    debugPrint('debug: SharedExpensesPage: $message');
  }
}

String _logId(String value) {
  if (value.length <= 12) return value;
  return '${value.substring(0, 8)}...${value.substring(value.length - 4)}';
}

String _formatEtb(num amount, [BuildContext? context]) {
  final value = amount.round();
  final sign = value < 0 ? '-' : '';
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  final currency = context?.l10nText('ETB') ?? 'ETB';
  return currency == 'ብር' ? '$sign$buffer $currency' : '$sign$currency $buffer';
}

String _formatExpenseAmountInput(double? amount) {
  if (amount == null || amount <= 0) return '';
  final normalized = amount.abs();
  if (normalized == normalized.roundToDouble()) {
    return normalized.toStringAsFixed(0);
  }
  return normalized.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

final List<Bank> _sharedExpenseBanks = [
  Bank(
    id: CashConstants.bankId,
    name: CashConstants.bankName,
    shortName: CashConstants.bankShortName,
    codes: const [],
    image: CashConstants.bankImage,
    colors: CashConstants.bankColors,
  ),
  ...AllBanksFromAssets.getAllBanks(),
];

Bank _sharedExpenseBankFor(int bankId) {
  for (final bank in _sharedExpenseBanks) {
    if (bank.id == bankId) return bank;
  }
  return Bank(
    id: bankId,
    name: 'Bank',
    shortName: bankId > 0 ? 'Bank $bankId' : 'Bank',
    codes: const [],
    image: '',
  );
}

String _sharedPaymentBankLabel(BuildContext context, int bankId) {
  final bank = _sharedExpenseBankFor(bankId);
  final label = bank.shortName.trim().isNotEmpty
      ? bank.shortName.trim()
      : bank.name.trim();
  return context.l10nText(label.isEmpty ? 'Bank' : label);
}

String _paymentAccountNumber(SharedPaymentAddress address) {
  return address.accountNumber.trim();
}

Future<void> _copyPaymentAccountNumber(
  BuildContext context,
  SharedPaymentAddress address,
) async {
  final accountNumber = _paymentAccountNumber(address);
  if (accountNumber.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: accountNumber));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.l10nTextRead('Account number copied')),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}

Map<String, double> _memberSpentTotalsFor(SharedExpenseGroup group) {
  final totals = <String, double>{
    for (final member in group.members) member.devicePublicKey: 0.0,
  };
  for (final expense in group.expenses) {
    if (expense.deleted) continue;
    if (expense.amount <= 0 || expense.paidBy.isEmpty) continue;
    totals.update(
      expense.paidBy,
      (current) => current + expense.amount,
      ifAbsent: () => expense.amount,
    );
  }
  return totals;
}

String _splitReasonForTransaction(Transaction transaction) {
  final note = transaction.note?.trim();
  if (note != null && note.isNotEmpty) return _trimExpenseReason(note);

  final isCredit = transaction.type?.toUpperCase() == 'CREDIT';
  final party = isCredit ? transaction.creditor : transaction.receiver;
  final trimmedParty = party?.trim();
  if (trimmedParty != null && trimmedParty.isNotEmpty) {
    return _trimExpenseReason(trimmedParty);
  }

  return 'Shared expense';
}

int? _timestampFromTransaction(Transaction transaction) {
  final raw = transaction.time?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return parsed.toLocal().millisecondsSinceEpoch;
}

String _transactionCounterpartyLabel(Transaction transaction) {
  final receiver = transaction.receiver?.trim();
  if (receiver != null && receiver.isNotEmpty) return receiver;
  final creditor = transaction.creditor?.trim();
  if (creditor != null && creditor.isNotEmpty) return creditor;
  final note = transaction.note?.trim();
  if (note != null && note.isNotEmpty) return note;
  return 'Transaction';
}

String _transactionDateLabel(Transaction transaction) {
  final timestamp = _timestampFromTransaction(transaction);
  if (timestamp == null) return '';
  return _formatSharedDate(DateTime.fromMillisecondsSinceEpoch(timestamp));
}

String _transactionLinkSummary(Transaction transaction,
    [BuildContext? context]) {
  final date = _transactionDateLabel(transaction);
  final pieces = [
    _transactionCounterpartyLabel(transaction),
    _formatEtb(transaction.amount.abs(), context),
    if (date.isNotEmpty) date,
  ];
  return pieces.join(' · ');
}

int _lastGroupEventTimestamp(SharedExpenseGroup group) {
  var latest = group.createdAt.millisecondsSinceEpoch;
  for (final entry in group.activity) {
    if (entry.timestamp > latest) latest = entry.timestamp;
  }
  for (final expense in group.expenses) {
    final timestamp = expense.revisedAt ?? expense.timestamp;
    if (timestamp > latest) latest = timestamp;
  }
  return latest;
}

String _trimExpenseReason(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 80) return trimmed;
  return trimmed.substring(0, 80);
}

Set<String> _memberKeysForGroup(SharedExpenseGroup group) {
  return group.members
      .map((member) => member.devicePublicKey)
      .where((key) => key.isNotEmpty)
      .toSet();
}

Future<bool> showSplitTransactionWithGroupFlow({
  required BuildContext context,
  required Transaction transaction,
  SharedExpenseRepository? repository,
}) async {
  final repo = repository ?? SharedExpenseRepository();
  final messenger = ScaffoldMessenger.maybeOf(context);
  TransactionProvider? transactionProvider;
  try {
    transactionProvider = context.read<TransactionProvider>();
  } catch (_) {
    transactionProvider = null;
  }
  String? sharingTxRef;

  void showSnack(String message) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  final linkedTxRef = transaction.reference.trim();
  if (linkedTxRef.isEmpty) {
    showSnack(context.l10nTextRead(
      'This transaction cannot be split because it has no reference.',
    ));
    return false;
  }

  try {
    final myPublicKey = await repo.myPublicKey();
    final linkedRefs = await repo.getAllLinkedTxRefs();
    if (linkedRefs.contains(linkedTxRef)) {
      if (context.mounted) {
        showSnack(context.l10nTextRead(
          'This transaction is already split with a group.',
        ));
      }
      return false;
    }

    final groups = (await repo.getGroups())
        .where((group) => group.hasGroupKey)
        .toList(growable: true)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (!context.mounted) return false;
    if (groups.isEmpty) {
      showSnack(context.l10nTextRead(
        'Create or join an approved shared group before splitting.',
      ));
      return false;
    }

    final selectedGroup = await showModalBottomSheet<SharedExpenseGroup>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _SplitGroupPickerSheet(
        groups: groups,
        myPublicKey: myPublicKey,
        amount: transaction.amount.abs(),
      ),
    );
    if (selectedGroup == null || !context.mounted) return false;

    var didSplit = false;
    await showModalBottomSheet<_ExpenseSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _ExpenseDraftSheet(
        group: selectedGroup,
        myPublicKey: myPublicKey,
        initialAmount: transaction.amount.abs(),
        initialReason: _splitReasonForTransaction(transaction),
        initialLinkedTxRef: linkedTxRef,
        submittingLabel: 'Adding',
        onSubmit: (result) async {
          if (result is! _ExpenseSheetSave) return false;

          final effectiveLinkedTxRef =
              (result.linkedTxRef?.trim().isNotEmpty ?? false)
                  ? result.linkedTxRef!.trim()
                  : linkedTxRef;
          sharingTxRef = effectiveLinkedTxRef;
          transactionProvider?.markSharedExpenseSharing(effectiveLinkedTxRef);

          try {
            final updatedGroup = await repo.splitTransactionIntoGroup(
              group: selectedGroup,
              amount: result.amount,
              reason: result.reason,
              paidBy: result.paidBy,
              splitAmong: result.splitAmong,
              linkedTxRef: effectiveLinkedTxRef,
              timestamp: result.timestamp,
            );
            await transactionProvider?.refreshSharedExpenseLinks();
            didSplit = true;

            if (!context.mounted) return true;
            if (_hasPendingLinkedExpense(
              group: updatedGroup,
              linkedTxRef: effectiveLinkedTxRef,
            )) {
              showSnack(context.l10nTextRead(
                "Saved locally. We'll send it when you're connected.",
              ));
              return true;
            }

            showSnack(
              context.l10nTextRead('Expense added to ${selectedGroup.name}'),
            );
            return true;
          } catch (error) {
            if (context.mounted) {
              showSnack(error.toString().replaceFirst('Exception: ', ''));
            }
            return false;
          } finally {
            transactionProvider?.unmarkSharedExpenseSharing(sharingTxRef);
          }
        },
      ),
    );
    return didSplit;
  } catch (error) {
    if (context.mounted) {
      showSnack(error.toString().replaceFirst('Exception: ', ''));
    }
    return false;
  } finally {
    transactionProvider?.unmarkSharedExpenseSharing(sharingTxRef);
  }
}

bool _hasPendingLinkedExpense({
  required SharedExpenseGroup group,
  required String linkedTxRef,
}) {
  final normalized = linkedTxRef.trim();
  if (normalized.isEmpty) return false;
  return group.expenses.any(
    (expense) =>
        !expense.deleted &&
        expense.status == 'pending' &&
        expense.linkedTxRef?.trim() == normalized,
  );
}

class SharedExpenseNavigationController {
  _RedesignSharedExpensesPageState? _state;
  String? _pendingActivitiesGroupId;

  void openActivitiesForGroup(String groupId) {
    final trimmed = groupId.trim();
    if (trimmed.isEmpty) return;
    final state = _state;
    if (state == null) {
      _pendingActivitiesGroupId = trimmed;
      return;
    }
    state._openGroupActivitiesFromNotification(trimmed);
  }

  void refresh() {
    _state?._refreshFromTabSwitch();
  }

  void _attach(_RedesignSharedExpensesPageState state) {
    _state = state;
    final pendingGroupId = _pendingActivitiesGroupId;
    if (pendingGroupId == null) return;
    _pendingActivitiesGroupId = null;
    state._openGroupActivitiesFromNotification(pendingGroupId);
  }

  void _detach(_RedesignSharedExpensesPageState state) {
    if (_state == state) _state = null;
  }
}

class SharedExpenseFabController extends ChangeNotifier {
  SharedExpenseFabConfig? _config;
  bool _isDisposed = false;

  SharedExpenseFabConfig? get config => _config;

  void show({
    required VoidCallback onPressed,
    required bool isBusy,
    required String? busyLabel,
  }) {
    if (_isDisposed) return;
    _config = SharedExpenseFabConfig(
      onPressed: onPressed,
      isBusy: isBusy,
      busyLabel: busyLabel,
    );
    notifyListeners();
  }

  void clear() {
    if (_isDisposed) return;
    if (_config == null) return;
    _config = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

@immutable
class SharedExpenseFabConfig {
  final VoidCallback onPressed;
  final bool isBusy;
  final String? busyLabel;

  const SharedExpenseFabConfig({
    required this.onPressed,
    required this.isBusy,
    required this.busyLabel,
  });
}

class SharedExpenseFabButton extends StatelessWidget {
  final SharedExpenseFabConfig config;

  const SharedExpenseFabButton({
    super.key,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final label = context.l10nText(config.busyLabel ?? 'Sending');
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: config.isBusy
          ? Semantics(
              enabled: false,
              child: IgnorePointer(
                child: FloatingActionButton.extended(
                  heroTag: 'shared-expense-fab',
                  onPressed: () {},
                  backgroundColor:
                      AppColors.primaryLight.withValues(alpha: 0.82),
                  foregroundColor: AppColors.white,
                  elevation: 8,
                  icon: const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  ),
                  label: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            )
          : SizedBox(
              width: 52,
              height: 52,
              child: FloatingActionButton(
                heroTag: 'shared-expense-fab',
                onPressed: config.onPressed,
                backgroundColor: AppColors.primaryLight,
                foregroundColor: AppColors.white,
                elevation: 8,
                shape: const CircleBorder(),
                child: const Icon(AppIcons.add, size: 26),
              ),
            ),
    );
  }
}

class RedesignSharedExpensesPage extends StatefulWidget {
  final SharedExpenseNavigationController? navigationController;
  final SharedExpenseFabController? fabController;

  const RedesignSharedExpensesPage({
    super.key,
    this.navigationController,
    this.fabController,
  });

  @override
  State<RedesignSharedExpensesPage> createState() =>
      _RedesignSharedExpensesPageState();
}

class _RedesignSharedExpensesPageState extends State<RedesignSharedExpensesPage>
    with
        AutomaticKeepAliveClientMixin<RedesignSharedExpensesPage>,
        WidgetsBindingObserver {
  final SharedExpenseRepository _repository = SharedExpenseRepository();
  final AccountRepository _accountRepository = AccountRepository();
  static const String _accountShareDisplayNameKey =
      'account_share_display_name';
  static const String _sharedExpensePaymentAddressKey =
      'shared_expense_payment_address';
  static const Duration _pollInterval = Duration(minutes: 30);
  static const Duration _realtimeReconnectDelay = Duration(seconds: 3);
  static const Duration _rateLimitedReconnectDelay = Duration(seconds: 30);
  static const Duration _maxRealtimeReconnectDelay = Duration(minutes: 2);
  static const Duration _minBackgroundRefreshGap = Duration(minutes: 2);
  static const int _activitiesTabIndex = 1;

  List<SharedExpenseGroup> _groups = const [];
  String _myPublicKey = '';
  bool _isRefreshing = false;
  bool _isMutating = false;
  String? _mutationLabel;
  bool _engineReachable = true;
  String? _approvingMemberKey;
  SharedExpenseGroup? _selectedGroup;
  String? _pendingNotificationGroupId;
  int _selectedGroupInitialTabIndex = 0;
  int _selectedGroupOpenRequestId = 0;
  _CreatingGroupDraft? _creatingGroup;
  Timer? _pollTimer;
  DateTime? _lastBackgroundRefresh;
  StreamSubscription<void>? _groupListRealtimeSubscription;
  Timer? _groupListRealtimeReconnectTimer;
  int _groupListRealtimeReconnectAttempts = 0;
  StreamSubscription<SharedExpenseGroup>? _pendingRealtimeSubscription;
  Timer? _pendingRealtimeReconnectTimer;
  int _pendingRealtimeReconnectAttempts = 0;
  StreamSubscription<SharedExpenseGroup>? _realtimeBusSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.navigationController?._attach(this);
    _loadGroups(refreshFromEngine: true, showErrors: false);
    _startPolling();
    _startGroupListRealtimeSubscription();
    _startPendingRealtimeSubscription();
    // The notification coordinator's per-group stream may consume a payload
    // before our own stream sees it, leaving _applyJoinRequest with nothing
    // new to apply. Listen to the bus so we still re-render in that case.
    _realtimeBusSubscription =
        SharedExpenseRealtimeBus.instance.stream.listen(_applyRealtimeGroup);
  }

  @override
  void didUpdateWidget(covariant RedesignSharedExpensesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationController != widget.navigationController) {
      oldWidget.navigationController?._detach(this);
      widget.navigationController?._attach(this);
    }
    if (oldWidget.fabController != widget.fabController) {
      oldWidget.fabController?.clear();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.navigationController?._detach(this);
    widget.fabController?.clear();
    _pollTimer?.cancel();
    _groupListRealtimeReconnectTimer?.cancel();
    unawaited(_groupListRealtimeSubscription?.cancel());
    _pendingRealtimeReconnectTimer?.cancel();
    unawaited(_pendingRealtimeSubscription?.cancel());
    unawaited(_realtimeBusSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Always fetch on resume — the 2-minute cooldown in _backgroundRefresh
      // is too conservative for "user opened the app from recents and is
      // looking at the screen right now". _refreshFromTabSwitch is the same
      // no-spinner path used for tab navigation.
      _refreshFromTabSwitch();
      _ensureRealtimeStreamsAlive();
    }
  }

  void _ensureRealtimeStreamsAlive() {
    if (_groupListRealtimeSubscription == null) {
      _groupListRealtimeReconnectTimer?.cancel();
      _groupListRealtimeReconnectTimer = null;
      _startGroupListRealtimeSubscription();
    }
    if (_pendingRealtimeSubscription == null) {
      _pendingRealtimeReconnectTimer?.cancel();
      _pendingRealtimeReconnectTimer = null;
      _startPendingRealtimeSubscription();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _backgroundRefresh());
  }

  Future<void> _backgroundRefresh() async {
    if (!mounted) return;
    if (_isRefreshing || _isMutating) return;
    if (_groups.isEmpty) return;
    final now = DateTime.now();
    if (_lastBackgroundRefresh != null &&
        now.difference(_lastBackgroundRefresh!) < _minBackgroundRefreshGap) {
      return;
    }
    _lastBackgroundRefresh = now;
    try {
      final groups = await _repository.refreshGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _selectedGroup = _updatedSelectedGroup(groups);
      });
      _syncRealtimeSubscriptions(groups);
      _tryOpenPendingNotificationGroup();
    } catch (error) {
      _sharedExpensesPageLog('backgroundRefresh failed: $error');
    }
  }

  void _startGroupListRealtimeSubscription() {
    if (_groupListRealtimeSubscription != null) return;
    _sharedExpensesPageLog('group list realtime subscribe');
    _groupListRealtimeSubscription =
        _repository.watchGroupListRealtime().listen(
      (_) => _refreshFromGroupListRealtime(),
      onError: (Object error, StackTrace stackTrace) {
        _sharedExpensesPageLog('group list realtime failed: $error');
        if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
        _groupListRealtimeSubscription = null;
        _scheduleGroupListRealtimeReconnect(error);
      },
      onDone: () {
        _sharedExpensesPageLog('group list realtime done');
        _groupListRealtimeSubscription = null;
        _scheduleGroupListRealtimeReconnect();
      },
    );
  }

  void _scheduleGroupListRealtimeReconnect([Object? error]) {
    if (!mounted) return;
    if (_groupListRealtimeReconnectTimer != null) return;
    final delay = _realtimeReconnectDelayFor(
      error,
      attempt: _groupListRealtimeReconnectAttempts++,
    );
    _groupListRealtimeReconnectTimer = Timer(delay, () {
      _groupListRealtimeReconnectTimer = null;
      if (!mounted) return;
      _startGroupListRealtimeSubscription();
    });
  }

  Future<void> _refreshFromTabSwitch() async {
    if (!mounted || _isRefreshing || _isMutating) return;
    _sharedExpensesPageLog('refresh from tab switch');
    try {
      final groups = await _repository.refreshGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _selectedGroup = _updatedSelectedGroup(groups);
      });
      _syncRealtimeSubscriptions(groups);
    } catch (error) {
      _sharedExpensesPageLog('refresh from tab switch failed: $error');
    }
  }

  Future<void> _refreshFromGroupListRealtime() async {
    if (!mounted || _isRefreshing || _isMutating) return;
    _sharedExpensesPageLog('group list realtime refresh');
    _groupListRealtimeReconnectAttempts = 0;
    setState(() => _isRefreshing = true);
    try {
      final groups = await _repository.refreshGroups();
      final reachable = await _repository.isEngineReachable();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _selectedGroup = _updatedSelectedGroup(groups);
        _engineReachable = reachable;
      });
      _syncRealtimeSubscriptions(groups);
      _tryOpenPendingNotificationGroup();
    } catch (error, stackTrace) {
      _sharedExpensesPageLog('group list realtime refresh failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _engineReachable = false);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _loadGroups({
    bool refreshFromEngine = false,
    bool showErrors = true,
  }) async {
    if (!mounted) return;
    _sharedExpensesPageLog(
      'loadGroups start refreshFromEngine=$refreshFromEngine showErrors=$showErrors',
    );
    setState(() {
      if (refreshFromEngine) _isRefreshing = true;
    });

    try {
      final localGroups = await _repository.getGroups();
      final myPublicKey = await _repository.myPublicKey();
      if (mounted) {
        setState(() {
          _groups = localGroups;
          _selectedGroup = _updatedSelectedGroup(localGroups);
          _myPublicKey = myPublicKey;
        });
        _syncRealtimeSubscriptions(localGroups);
        _tryOpenPendingNotificationGroup();
      }

      if (refreshFromEngine) {
        final groups = await _repository.refreshGroups();
        final reachable = await _repository.isEngineReachable();
        if (mounted) {
          setState(() {
            _groups = groups;
            _selectedGroup = _updatedSelectedGroup(groups);
            _engineReachable = reachable;
          });
          _syncRealtimeSubscriptions(groups);
          _tryOpenPendingNotificationGroup();
        }
        _sharedExpensesPageLog(
          'loadGroups refreshed groups=${groups.length} reachable=$reachable',
        );
      }
    } catch (error, stackTrace) {
      _sharedExpensesPageLog('loadGroups failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _engineReachable = false);
        if (showErrors) {
          _showSnack(error.toString().replaceFirst('Exception: ', ''));
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<String> _defaultDisplayName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString(_accountShareDisplayNameKey)?.trim();
      if (savedName != null && savedName.isNotEmpty) return savedName;

      final accounts = await _accountRepository.getAccounts();
      for (final account in accounts) {
        if (account.bank == CashConstants.bankId) continue;
        final holderName = account.accountHolderName.trim();
        if (holderName.isEmpty) continue;
        await prefs.setString(_accountShareDisplayNameKey, holderName);
        return holderName;
      }
    } catch (error, stackTrace) {
      _sharedExpensesPageLog('defaultDisplayName failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
    }
    return '';
  }

  List<AccountSummary> _selectablePaymentAccounts(
      TransactionProvider provider) {
    final accounts = List<AccountSummary>.from(provider.accountSummaries)
      ..sort((a, b) {
        if (a.bankId == CashConstants.bankId) return -1;
        if (b.bankId == CashConstants.bankId) return 1;
        return a.bankId.compareTo(b.bankId);
      });
    if (accounts.isEmpty) {
      accounts.add(
        AccountSummary(
          bankId: CashConstants.bankId,
          accountNumber: CashConstants.defaultAccountNumber,
          accountHolderName: CashConstants.defaultAccountHolderName,
          totalTransactions: 0,
          totalCredit: 0,
          totalDebit: 0,
          settledBalance: 0,
          balance: 0,
          pendingCredit: 0,
        ),
      );
    }
    return accounts;
  }

  SharedPaymentAddress _addressFromAccount(AccountSummary account) {
    return SharedPaymentAddress(
      bankId: account.bankId,
      accountNumber: account.accountNumber,
      accountHolderName: account.accountHolderName,
    );
  }

  Future<SharedPaymentAddress> _defaultPaymentAddress(
    TransactionProvider provider,
  ) async {
    final accounts = _selectablePaymentAccounts(provider);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sharedExpensePaymentAddressKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final saved = SharedPaymentAddress.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (saved.isValid) {
            for (final account in accounts) {
              if (account.bankId == saved.bankId &&
                  account.accountNumber == saved.accountNumber) {
                return _addressFromAccount(account);
              }
            }
          }
        }
      }
    } catch (error, stackTrace) {
      _sharedExpensesPageLog('defaultPaymentAddress failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
    }
    return _addressFromAccount(accounts.first);
  }

  Future<void> _saveDefaultPaymentAddress(
    SharedPaymentAddress paymentAddress,
  ) async {
    if (!paymentAddress.isValid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _sharedExpensePaymentAddressKey,
        jsonEncode(paymentAddress.toJson()),
      );
    } catch (error, stackTrace) {
      _sharedExpensesPageLog('saveDefaultPaymentAddress failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
    }
  }

  SharedExpenseGroup? _updatedSelectedGroup(List<SharedExpenseGroup> groups) {
    final selected = _selectedGroup;
    if (selected == null) return null;
    for (final group in groups) {
      if (group.id == selected.id) return _canOpenGroup(group) ? group : null;
    }
    return _canOpenGroup(selected) ? selected : null;
  }

  bool _canOpenGroup(SharedExpenseGroup group) {
    return group.status != SharedExpenseGroupStatus.pendingApproval;
  }

  void _beginMutation(String label) {
    if (!mounted) return;
    setState(() {
      _isMutating = true;
      _mutationLabel = label;
    });
  }

  void _endMutation() {
    if (!mounted) return;
    setState(() {
      _isMutating = false;
      _mutationLabel = null;
    });
  }

  void _syncRealtimeSubscriptions(List<SharedExpenseGroup> groups) {
    // The pending payload stream is always-on (started in initState and
    // re-verified on resume). This call serves as a belt-and-suspenders
    // check: if the subscription died and no reconnect is pending, restart
    // it now that we're already doing group work.
    if (_pendingRealtimeSubscription == null &&
        _pendingRealtimeReconnectTimer == null) {
      _startPendingRealtimeSubscription();
    }
  }

  void _startPendingRealtimeSubscription() {
    if (_pendingRealtimeSubscription != null) return;
    if (_pendingRealtimeReconnectTimer != null) return;
    _sharedExpensesPageLog('pending realtime subscribe');

    final subscription = _repository.watchAllGroupsRealtime().listen(
      (group) {
        _pendingRealtimeReconnectAttempts = 0;
        _applyRealtimeGroup(group);
      },
      onError: (Object error, StackTrace stackTrace) {
        _sharedExpensesPageLog('pending realtime failed: $error');
        if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
        _pendingRealtimeSubscription = null;
        if (error is TotalsEngineException && error.statusCode == 403) {
          unawaited(_loadGroups(refreshFromEngine: true, showErrors: false));
          return;
        }
        _schedulePendingRealtimeReconnect(error);
      },
      onDone: () {
        _sharedExpensesPageLog('pending realtime done');
        _pendingRealtimeSubscription = null;
        _schedulePendingRealtimeReconnect();
      },
    );
    _pendingRealtimeSubscription = subscription;
  }

  void _schedulePendingRealtimeReconnect([Object? error]) {
    if (!mounted) return;
    if (_pendingRealtimeReconnectTimer != null) return;
    final delay = _realtimeReconnectDelayFor(
      error,
      attempt: _pendingRealtimeReconnectAttempts++,
    );
    _pendingRealtimeReconnectTimer = Timer(delay, () {
      _pendingRealtimeReconnectTimer = null;
      if (!mounted) return;
      _startPendingRealtimeSubscription();
    });
  }

  Duration _realtimeReconnectDelayFor(Object? error, {required int attempt}) {
    if (error is TotalsEngineException && error.statusCode == 429) {
      final retryAfter = error.retryAfter;
      if (retryAfter != null) return _clampRealtimeDelay(retryAfter);
      final multiplier = math.pow(2, math.min(attempt, 2)).toInt();
      return _clampRealtimeDelay(_rateLimitedReconnectDelay * multiplier);
    }
    return _realtimeReconnectDelay;
  }

  Duration _clampRealtimeDelay(Duration delay) {
    if (delay < _realtimeReconnectDelay) return _realtimeReconnectDelay;
    if (delay > _maxRealtimeReconnectDelay) return _maxRealtimeReconnectDelay;
    return delay;
  }

  SharedExpenseGroup? _groupInState(String groupId) {
    for (final group in _groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  void _applyRealtimeGroup(SharedExpenseGroup updatedGroup) {
    if (!mounted) return;
    setState(() {
      var replaced = false;
      final next = _groups.map((group) {
        if (group.id != updatedGroup.id) return group;
        replaced = true;
        return updatedGroup;
      }).toList(growable: true);
      if (!replaced) next.insert(0, updatedGroup);

      _groups = next;
      _selectedGroup = _selectedGroup?.id == updatedGroup.id
          ? (_canOpenGroup(updatedGroup) ? updatedGroup : null)
          : _updatedSelectedGroup(next);
      _engineReachable = true;
    });
    _tryOpenPendingNotificationGroup();
  }

  void _openGroupActivitiesFromNotification(String groupId) {
    final trimmed = groupId.trim();
    if (trimmed.isEmpty) return;
    _pendingNotificationGroupId = trimmed;
    _tryOpenPendingNotificationGroup();
    if (_pendingNotificationGroupId != null) {
      unawaited(_loadGroups(refreshFromEngine: true, showErrors: false));
    }
  }

  void _tryOpenPendingNotificationGroup() {
    final groupId = _pendingNotificationGroupId;
    if (groupId == null || groupId.isEmpty) return;
    final group = _groupInState(groupId);
    if (group == null) return;
    _pendingNotificationGroupId = null;
    _openGroup(
      group,
      initialTabIndex: _activitiesTabIndex,
      fromNotification: true,
    );
  }

  void _openGroup(
    SharedExpenseGroup group, {
    int initialTabIndex = 0,
    bool fromNotification = false,
  }) {
    _sharedExpensesPageLog('openGroup group=${_logId(group.id)}');
    if (!_canOpenGroup(group)) {
      if (!fromNotification) {
        _showSnack(context.l10nTextRead(
          'You can open this group after approval.',
        ));
      }
      return;
    }
    setState(() {
      _selectedGroup = group;
      _selectedGroupInitialTabIndex = initialTabIndex;
      _selectedGroupOpenRequestId += 1;
    });
  }

  void _closeGroup() {
    _sharedExpensesPageLog('closeGroup');
    widget.fabController?.clear();
    setState(() => _selectedGroup = null);
  }

  Future<void> _openGroupSettings(SharedExpenseGroup group) async {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final accounts = _selectablePaymentAccounts(provider);
    final initialPaymentAddress = group.myPaymentAddress ??
        (_myPublicKey.isEmpty ? null : group.paymentAddresses[_myPublicKey]) ??
        await _defaultPaymentAddress(provider);
    if (!mounted) return;
    final result = await showModalBottomSheet<_GroupSettingsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (sheetContext) => _GroupSettingsSheet(
        initialName: group.name,
        initialDisplayName: group.myDisplayName,
        initialBackfillNewMembers: group.backfillNewMembers,
        paymentAccounts: accounts,
        initialPaymentAddress: initialPaymentAddress,
      ),
    );
    if (result == null || !mounted) return;

    if (result is _GroupSettingsCopyInvite) {
      await _copyInvite(group);
      return;
    }

    if (result is _GroupSettingsLeave) {
      _beginMutation('Leaving group');
      try {
        await _repository.leaveGroup(group);
        if (!mounted) return;
        final groups = await _repository.getGroups();
        if (!mounted) return;
        setState(() {
          _groups = groups;
          _selectedGroup = null;
        });
        _syncRealtimeSubscriptions(groups);
        _showSnack(context.l10nTextRead('You left the group'));
      } catch (error) {
        _showSnack(error.toString().replaceFirst('Exception: ', ''));
      } finally {
        _endMutation();
      }
      return;
    }

    if (result is _GroupSettingsSave) {
      final nameChanged = result.name.trim() != group.name;
      final displayChanged = result.displayName.trim() != group.myDisplayName;
      final backfillChanged =
          result.backfillNewMembers != group.backfillNewMembers;
      final paymentChanged = result.paymentAddress != initialPaymentAddress;
      if (!nameChanged &&
          !displayChanged &&
          !backfillChanged &&
          !paymentChanged) {
        return;
      }
      _beginMutation('Saving');
      try {
        await _saveDefaultPaymentAddress(result.paymentAddress);
        final updated = await _repository.updateMeta(
          group: group,
          name: nameChanged ? result.name.trim() : null,
          myDisplayName: displayChanged ? result.displayName.trim() : null,
          backfillNewMembers:
              backfillChanged ? result.backfillNewMembers : null,
          paymentAddress: paymentChanged ? result.paymentAddress : null,
        );
        if (!mounted) return;
        final groups = await _repository.getGroups();
        if (!mounted) return;
        setState(() {
          _groups = groups;
          _selectedGroup = updated;
        });
        _syncRealtimeSubscriptions(groups);
        _showSnack(context.l10nTextRead('Saved'));
      } catch (error) {
        _showSnack(error.toString().replaceFirst('Exception: ', ''));
      } finally {
        _endMutation();
      }
    }
  }

  Future<void> _openExpenseSheet(
    SharedExpenseGroup group, {
    SharedExpense? expense,
  }) async {
    if (!group.hasGroupKey) {
      _showSnack(context.l10nTextRead(
        'Wait until you have the group key before adding an expense.',
      ));
      return;
    }

    Future<bool> submitExpenseResult(_ExpenseSheetResult result) async {
      if (!mounted) return false;
      final mutationLabel = result is _ExpenseSheetDelete
          ? 'Deleting'
          : expense != null
              ? 'Saving'
              : 'Sending';
      final successMessage = result is _ExpenseSheetDelete
          ? context.l10nTextRead('Expense deleted')
          : expense != null
              ? context.l10nTextRead('Expense updated')
              : context.l10nTextRead('Expense added');
      _beginMutation(mutationLabel);
      final transactionProvider = context.read<TransactionProvider>();
      String? sharingTxRef;
      if (result is _ExpenseSheetSave &&
          (result.linkedTxRef?.trim().isNotEmpty ?? false)) {
        sharingTxRef = result.linkedTxRef!.trim();
        transactionProvider.markSharedExpenseSharing(sharingTxRef);
      }
      try {
        SharedExpenseGroup updated = group;
        if (result is _ExpenseSheetDelete && expense != null) {
          updated = await _repository.deleteExpense(
            group: group,
            expenseId: expense.id,
          );
        } else if (result is _ExpenseSheetSave) {
          if (expense != null) {
            updated = await _repository.updateExpense(
              group: group,
              before: expense,
              amount: result.amount,
              reason: result.reason,
              paidBy: result.paidBy,
              splitAmong: result.splitAmong,
              timestamp: result.timestamp,
              linkedTxRef: result.linkedTxRef,
              clearLinkedTxRef: result.linkedTxRef == null,
            );
          } else {
            updated = await _repository.createExpense(
              group: group,
              amount: result.amount,
              reason: result.reason,
              paidBy: result.paidBy,
              splitAmong: result.splitAmong,
              timestamp: result.timestamp,
              linkedTxRef: result.linkedTxRef,
            );
          }
        }
        if (!mounted) return true;
        final groups = await _repository.getGroups();
        if (!mounted) return true;
        setState(() {
          _groups = groups;
          _selectedGroup = updated;
        });
        _syncRealtimeSubscriptions(groups);
        await transactionProvider.refreshSharedExpenseLinks();
        unawaited(transactionProvider.loadData());
        _showSnack(successMessage);
        return true;
      } catch (error) {
        _showSnack(error.toString().replaceFirst('Exception: ', ''));
        return false;
      } finally {
        transactionProvider.unmarkSharedExpenseSharing(sharingTxRef);
        _endMutation();
      }
    }

    await showModalBottomSheet<_ExpenseSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (sheetContext) => _ExpenseDraftSheet(
        group: group,
        myPublicKey: _myPublicKey,
        editing: expense,
        submittingLabel: expense == null ? 'Adding' : 'Saving',
        onSubmit: submitExpenseResult,
      ),
    );
  }

  Future<void> _settleWith(
    SharedExpenseGroup group,
    String recipientPk,
    double amount,
  ) async {
    _beginMutation('Settling');
    try {
      final updated = await _repository.settleUpWith(
        group: group,
        recipientPk: recipientPk,
        amount: amount,
      );
      if (!mounted) return;
      final groups = await _repository.getGroups();
      setState(() {
        _groups = groups;
        _selectedGroup = updated;
      });
      _syncRealtimeSubscriptions(groups);
      final name = group.displayNameFor(_myPublicKey, recipientPk);
      _showSnack('Settled with $name');
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      _endMutation();
    }
  }

  Future<void> _settleDebt(
    SharedExpenseGroup group,
    SettlementDebt debt,
  ) async {
    if (debt.from == _myPublicKey) {
      await _settleWith(group, debt.to, debt.amount);
      return;
    }
    if (debt.to != _myPublicKey) {
      _showSnack(
          context.l10nTextRead('Only people in this debt can settle it'));
      return;
    }

    _beginMutation('Settling');
    try {
      final updated = await _repository.createExpense(
        group: group,
        amount: debt.amount,
        reason: 'Settlement',
        paidBy: debt.from,
        splitAmong: [debt.to],
        kind: 'settlement',
      );
      if (!mounted) return;
      final groups = await _repository.getGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _selectedGroup = updated;
      });
      _syncRealtimeSubscriptions(groups);
      final name = group.displayNameFor(_myPublicKey, debt.from);
      _showSnack('Settled with $name');
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      _endMutation();
    }
  }

  Future<void> _sendNudge(SharedExpenseGroup group) async {
    final debtsOwedToMe = settlementPlanFor(group)
        .debts
        .where((debt) => debt.to == _myPublicKey)
        .toList(growable: false);
    final amountByDebtor = <String, double>{};
    for (final debt in debtsOwedToMe) {
      if (debt.from.isEmpty || debt.amount < 0.5) continue;
      amountByDebtor.update(
        debt.from,
        (current) => current + debt.amount,
        ifAbsent: () => debt.amount,
      );
    }
    final targets = amountByDebtor.entries
        .map((entry) => _NudgeTarget(
              publicKey: entry.key,
              amount: entry.value,
            ))
        .where((target) => target.amount >= 0.5)
        .toList(growable: false)
      ..sort((a, b) {
        final byAmount = b.amount.compareTo(a.amount);
        if (byAmount != 0) return byAmount;
        return group
            .displayNameFor(_myPublicKey, a.publicKey)
            .compareTo(group.displayNameFor(_myPublicKey, b.publicKey));
      });
    if (targets.isEmpty) {
      _showSnack(context.l10nTextRead('No one owes you right now'));
      return;
    }

    final shouldChooseTargets = group.memberCount > 2 && targets.length > 1;
    final selectedTargets = shouldChooseTargets
        ? await showModalBottomSheet<List<_NudgeTarget>>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            barrierColor: AppColors.black.withValues(alpha: 0.5),
            builder: (_) => _NudgePickerSheet(
              group: group,
              myPublicKey: _myPublicKey,
              targets: targets,
            ),
          )
        : targets;
    if (selectedTargets == null || selectedTargets.isEmpty) return;

    await _submitNudgeTargets(group, selectedTargets);
  }

  Future<void> _sendNudgeToDebtor(
    SharedExpenseGroup group,
    String debtorPk,
    double amount,
  ) async {
    if (debtorPk.isEmpty || amount < 0.5) {
      _showSnack(context.l10nTextRead('No one owes you right now'));
      return;
    }
    await _submitNudgeTargets(
      group,
      [
        _NudgeTarget(
          publicKey: debtorPk,
          amount: amount,
        ),
      ],
    );
  }

  Future<void> _submitNudgeTargets(
    SharedExpenseGroup group,
    List<_NudgeTarget> selectedTargets,
  ) async {
    final amount = selectedTargets.fold<double>(
      0,
      (sum, target) => sum + target.amount,
    );
    final debtorPks = selectedTargets
        .map((target) => target.publicKey)
        .where((pk) => pk.isNotEmpty)
        .toList(growable: false);
    if (debtorPks.isEmpty || amount < 0.5) {
      _showSnack(context.l10nTextRead('No one owes you right now'));
      return;
    }

    _beginMutation('Sending nudge');
    try {
      final updated = await _repository.sendNudge(
        group: group,
        amount: amount,
        debtorPks: debtorPks,
      );
      if (!mounted) return;
      final groups = await _repository.getGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _selectedGroup = updated;
      });
      _syncRealtimeSubscriptions(groups);
      _showSnack(context.l10nTextRead('Nudge sent'));
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      _endMutation();
    }
  }

  void _showAddExpenseComingSoon() {
    final group = _selectedGroup;
    if (group != null) {
      _openExpenseSheet(group);
    } else {
      _showSnack(context.l10nTextRead('Open a group first to add an expense.'));
    }
  }

  Future<void> _saveDefaultDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accountShareDisplayNameKey, trimmed);
    } catch (error, stackTrace) {
      _sharedExpensesPageLog('saveDefaultDisplayName failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _createGroup() async {
    final copiedMessage = context.l10nTextRead('Invite code copied');
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final displayName = await _defaultDisplayName();
    final accounts = _selectablePaymentAccounts(provider);
    final paymentAddress = await _defaultPaymentAddress(provider);
    if (!mounted) return;

    final input = await showModalBottomSheet<_GroupFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _GroupFormSheet(
        title: sheetContext.l10nText('Create Group'),
        primaryLabel: sheetContext.l10nText('Create'),
        groupLabel: sheetContext.l10nText('GROUP NAME'),
        groupHint: sheetContext.l10nText('Trip to Lalibela, Roommates...'),
        nameLabel: sheetContext.l10nText('YOUR NAME'),
        nameHint: sheetContext.l10nText('How other members see you'),
        initialName: displayName,
        paymentAccounts: accounts,
        initialPaymentAddress: paymentAddress,
      ),
    );
    if (input == null) return;

    _sharedExpensesPageLog('createGroup submitted name="${input.groupName}"');
    setState(() {
      _isMutating = true;
      _mutationLabel = 'Creating group';
      _creatingGroup = _CreatingGroupDraft(
        name: input.groupName,
        displayName: input.displayName,
      );
    });
    try {
      await _saveDefaultDisplayName(input.displayName);
      await _saveDefaultPaymentAddress(input.paymentAddress);
      final group = await _repository.createGroup(
        name: input.groupName,
        displayName: input.displayName,
        paymentAddress: input.paymentAddress,
      );
      if (mounted) {
        final groups = [
          group,
          ..._groups.where((existing) => existing.id != group.id),
        ];
        setState(() {
          _creatingGroup = null;
          _groups = groups;
        });
        _syncRealtimeSubscriptions(groups);
      }
      await _copyInvite(group, showSnack: false);
      _showSnack(copiedMessage);
      _sharedExpensesPageLog('createGroup done group=${_logId(group.id)}');
    } catch (error, stackTrace) {
      _sharedExpensesPageLog('createGroup failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isMutating = false;
          _mutationLabel = null;
          _creatingGroup = null;
        });
      }
    }
  }

  Future<void> _joinGroup() async {
    final requestedMessage = context.l10nTextRead('Join request sent');
    final joinedMessage = context.l10nTextRead('Joined group');
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final displayName = await _defaultDisplayName();
    final accounts = _selectablePaymentAccounts(provider);
    final paymentAddress = await _defaultPaymentAddress(provider);
    if (!mounted) return;

    final input = await showModalBottomSheet<_GroupFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _GroupFormSheet(
        title: sheetContext.l10nText('Join Group'),
        primaryLabel: sheetContext.l10nText('Join'),
        groupLabel: sheetContext.l10nText('GROUP CODE'),
        groupHint: sheetContext.l10nText('paste invite code (UUID)'),
        nameLabel: sheetContext.l10nText('YOUR NAME'),
        nameHint: sheetContext.l10nText('How other members see you'),
        initialName: displayName,
        paymentAccounts: accounts,
        initialPaymentAddress: paymentAddress,
      ),
    );
    if (input == null) return;

    _sharedExpensesPageLog('joinGroup submitted code="${input.groupName}"');
    _beginMutation('Sending request');
    try {
      await _saveDefaultDisplayName(input.displayName);
      await _saveDefaultPaymentAddress(input.paymentAddress);
      final joined = await _repository.joinGroup(
        inviteOrCode: input.groupName,
        displayName: input.displayName,
        paymentAddress: input.paymentAddress,
      );
      await _loadGroups(refreshFromEngine: true, showErrors: false);
      _showSnack(joined.hasGroupKey ? joinedMessage : requestedMessage);
      _sharedExpensesPageLog('joinGroup done');
    } catch (error, stackTrace) {
      _sharedExpensesPageLog('joinGroup failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      _showSnack(error.toString());
    } finally {
      _endMutation();
    }
  }

  Future<void> _approveMember(
    SharedExpenseGroup group,
    SharedExpenseMember member,
  ) async {
    final approvedMessage = context.l10nTextRead('Member approved');
    _sharedExpensesPageLog(
      'approveMember tapped group=${_logId(group.id)} '
      'member=${_logId(member.devicePublicKey)}',
    );
    setState(() {
      _isMutating = true;
      _mutationLabel = 'Approving';
      _approvingMemberKey = member.devicePublicKey;
    });
    try {
      await _repository.approveMember(group: group, member: member);
      await _loadGroups(refreshFromEngine: true, showErrors: false);
      _showSnack(approvedMessage);
      _sharedExpensesPageLog('approveMember done group=${_logId(group.id)}');
    } catch (error, stackTrace) {
      _sharedExpensesPageLog('approveMember failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isMutating = false;
          _mutationLabel = null;
          _approvingMemberKey = null;
        });
      }
    }
  }

  Future<void> _copyInvite(
    SharedExpenseGroup group, {
    bool showSnack = true,
  }) async {
    await Clipboard.setData(
      ClipboardData(text: _repository.inviteCodeFor(group.id)),
    );
    if (!mounted || !showSnack) return;
    _showSnack(context.l10nTextRead('Invite code copied'));
  }

  Future<void> _cancelJoinRequest(SharedExpenseGroup group) async {
    _sharedExpensesPageLog('cancelJoinRequest group=${_logId(group.id)}');
    _beginMutation('Cancelling request');
    try {
      await _repository.leaveGroup(group);
      if (!mounted) return;
      final groups = await _repository.getGroups();
      if (!mounted) return;
      setState(() => _groups = groups);
      _syncRealtimeSubscriptions(groups);
      _showSnack(context.l10nTextRead('Join request cancelled'));
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      _endMutation();
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _shortKey(String value) {
    if (value.length <= 14) return value;
    return '${value.substring(0, 8)}...${value.substring(value.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final selectedGroup = _selectedGroup;
    if (selectedGroup != null && _canOpenGroup(selectedGroup)) {
      return _SharedGroupDetailView(
        group: selectedGroup,
        myPublicKey: _myPublicKey,
        initialTabIndex: _selectedGroupInitialTabIndex,
        openRequestId: _selectedGroupOpenRequestId,
        shortKey: _shortKey,
        onBack: _closeGroup,
        onOpenSettings: () => _openGroupSettings(selectedGroup),
        onAddExpense: _showAddExpenseComingSoon,
        isMutating: _isMutating,
        mutationLabel: _mutationLabel,
        fabController: widget.fabController,
        onEditExpense: (e) => _openExpenseSheet(selectedGroup, expense: e),
        onSettleDebt: (debt) => _settleDebt(selectedGroup, debt),
        onSendNudge: () => _sendNudge(selectedGroup),
        onNudgeDebt: (debtorPk, amount) =>
            _sendNudgeToDebtor(selectedGroup, debtorPk, amount),
      );
    }

    final theme = Theme.of(context);
    const contentPadding = EdgeInsets.fromLTRB(20, 16, 20, 24);
    final groupCardCount = _groups.length + (_creatingGroup == null ? 0 : 1);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadGroups(refreshFromEngine: true),
          color: AppColors.primaryLight,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: contentPadding.copyWith(bottom: 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n('nav.shared', 'Shared'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10nText('Split expenses with friends'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _ActionBar(
                        isBusy: _isMutating,
                        busyLabel: _mutationLabel,
                        isRefreshing: _isRefreshing,
                        onCreate: _createGroup,
                        onJoin: _joinGroup,
                        onRefresh: () => _loadGroups(refreshFromEngine: true),
                      ),
                      SharedExpenseVaultBanner(hasGroups: _groups.isNotEmpty),
                      const SharedExpenseVaultDebugRow(),
                      if (!_engineReachable) ...[
                        const SizedBox(height: 12),
                        _EngineStatusBanner(
                          label: context.l10nText(
                            'Totals Engine is not reachable',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_groups.isEmpty && _creatingGroup == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptySharedState(
                    onCreate: _createGroup,
                    onJoin: _joinGroup,
                    isBusy: _isMutating,
                    busyLabel: _mutationLabel,
                  ),
                )
              else
                SliverPadding(
                  padding: contentPadding.copyWith(top: 26),
                  sliver: SliverList.separated(
                    itemCount: groupCardCount,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (_creatingGroup != null && index == 0) {
                        return _CreatingGroupCard(draft: _creatingGroup!);
                      }
                      final groupIndex =
                          index - (_creatingGroup == null ? 0 : 1);
                      final group = _groups[groupIndex];
                      final pendingMembers =
                          group.pendingApprovalMembers(_myPublicKey);
                      return _SharedGroupCard(
                        group: group,
                        myPublicKey: _myPublicKey,
                        isRefreshing: _isRefreshing,
                        pendingMembers: pendingMembers,
                        shortKey: _shortKey,
                        approvingMemberKey: _approvingMemberKey,
                        onOpen: () => _openGroup(group),
                        onCopyInvite: () => _copyInvite(group),
                        onApproveMember: (member) =>
                            _approveMember(group, member),
                        onCancelJoinRequest: () => _cancelJoinRequest(group),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool isBusy;
  final String? busyLabel;
  final bool isRefreshing;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onRefresh;

  const _ActionBar({
    required this.isBusy,
    required this.busyLabel,
    required this.isRefreshing,
    required this.onCreate,
    required this.onJoin,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isCreatingGroup = isBusy && busyLabel == 'Creating group';
    final isSendingRequest = isBusy && busyLabel == 'Sending request';
    return Row(
      children: [
        FilledButton.icon(
          onPressed: isBusy ? null : onCreate,
          icon: isCreatingGroup
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : const Icon(AppIcons.add, size: 18, color: AppColors.white),
          label: Text(
            context.l10nText(isCreatingGroup ? 'Creating group' : 'New'),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryLight,
            foregroundColor: AppColors.white,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: isBusy ? null : onJoin,
          icon: isSendingRequest
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryLight,
                  ),
                )
              : Icon(
                  AppIcons.lock_outline_rounded,
                  size: 18,
                  color: AppColors.textPrimary(context),
                ),
          label: Text(
            context.l10nText(isSendingRequest ? 'Sending request' : 'Join'),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary(context),
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            side: BorderSide(color: AppColors.borderColor(context)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: isRefreshing ? null : onRefresh,
          icon: isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryLight,
                  ),
                )
              : Icon(
                  AppIcons.refresh,
                  color: AppColors.textSecondary(context),
                ),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.cardColor(context),
            side: BorderSide(color: AppColors.borderColor(context)),
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      ],
    );
  }
}

class _SplitGroupPickerSheet extends StatelessWidget {
  final List<SharedExpenseGroup> groups;
  final String myPublicKey;
  final double amount;

  const _SplitGroupPickerSheet({
    required this.groups,
    required this.myPublicKey,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondary(context);
    final chooseText = context
        .l10n('shared.chooseWhereToAddAmount', 'Choose where to add {amount}.')
        .replaceFirst('{amount}', _formatEtb(amount, context));
    return _IosModalShell(
      title: 'Split with group',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            chooseText,
            style: TextStyle(
              color: textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        for (final group in groups) ...[
          _SplitGroupOption(
            group: group,
            myPublicKey: myPublicKey,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SplitGroupOption extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;

  const _SplitGroupOption({
    required this.group,
    required this.myPublicKey,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardColor(context);
    final borderColor = AppColors.borderColor(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final memberKeys = _memberKeysForGroup(group).toList(growable: false);
    final visibleMembers = memberKeys.take(3).toList(growable: false);
    final avatarStackWidth = visibleMembers.isEmpty
        ? 28.0
        : 28.0 + ((visibleMembers.length - 1) * 12.0);

    return InkWell(
      onTap: () => Navigator.of(context).pop(group),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            SizedBox(
              width: avatarStackWidth,
              height: 32,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < visibleMembers.length; i++)
                    Positioned(
                      left: i * 12,
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              Color(memberColorFor(group, visibleMembers[i])),
                          shape: BoxShape.circle,
                          border: Border.all(color: cardColor, width: 2),
                        ),
                        child: Text(
                          group
                              .displayNameFor(myPublicKey, visibleMembers[i])
                              .trim()
                              .characters
                              .take(1)
                              .toString()
                              .toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (visibleMembers.isEmpty)
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: cardColor, width: 2),
                      ),
                      child: const Icon(
                        AppIcons.group_outlined,
                        size: 14,
                        color: AppColors.white,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    group.memberCount == 1
                        ? '1 member'
                        : '${group.memberCount} members',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              AppIcons.chevron_right,
              size: 18,
              color: AppColors.textTertiary(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _EngineStatusBanner extends StatelessWidget {
  final String label;

  const _EngineStatusBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.wifi_off, color: AppColors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySharedState extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final bool isBusy;
  final String? busyLabel;

  const _EmptySharedState({
    required this.onCreate,
    required this.onJoin,
    required this.isBusy,
    required this.busyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCreatingGroup = isBusy && busyLabel == 'Creating group';
    final isSendingRequest = isBusy && busyLabel == 'Sending request';

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 60, 36, 96),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              AppIcons.group_outlined,
              color: AppColors.primaryLight,
              size: 38,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            context.l10nText('No groups yet'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.l10nText(
              'Create or join a group to split expenses with friends.',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary(context),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isBusy ? null : onCreate,
              icon: isCreatingGroup
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(AppIcons.add, color: AppColors.white),
              label: Text(
                context.l10nText(
                  isCreatingGroup ? 'Creating group' : 'Create group',
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryLight,
                foregroundColor: AppColors.white,
                minimumSize: const Size(0, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isBusy ? null : onJoin,
              icon: isSendingRequest
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryLight,
                      ),
                    )
                  : Icon(
                      AppIcons.lock_outline_rounded,
                      color: AppColors.textPrimary(context),
                    ),
              label: Text(
                context.l10nText(
                  isSendingRequest ? 'Sending request' : 'Join with code',
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary(context),
                minimumSize: const Size(0, 56),
                side: BorderSide(color: AppColors.borderColor(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const SharedExpenseVaultRestoreLink(),
        ],
      ),
    );
  }
}

class _CreatingGroupDraft {
  final String name;
  final String displayName;

  const _CreatingGroupDraft({
    required this.name,
    required this.displayName,
  });
}

class _CreatingGroupCard extends StatelessWidget {
  final _CreatingGroupDraft draft;

  const _CreatingGroupCard({required this.draft});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.primaryLight.withValues(alpha: 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10nText('1 member'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${context.l10nText('Sharing as')} ${draft.displayName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(
                  label: context.l10nText('Creating group'),
                  color: AppColors.blue,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryLight,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10nText('Creating group'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

