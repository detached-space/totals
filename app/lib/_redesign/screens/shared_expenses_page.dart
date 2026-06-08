import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:totals/services/totals_engine_client.dart';

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

class RedesignSharedExpensesPage extends StatefulWidget {
  final SharedExpenseNavigationController? navigationController;

  const RedesignSharedExpensesPage({
    super.key,
    this.navigationController,
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
  static const Duration _pollInterval = Duration(minutes: 5);
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
  final Map<String, StreamSubscription<SharedExpenseGroup>>
      _realtimeSubscriptions = {};
  final Map<String, Timer> _realtimeReconnectTimers = {};
  final Set<String> _forbiddenRealtimeGroupIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.navigationController?._attach(this);
    _loadGroups(refreshFromEngine: true, showErrors: false);
    _startPolling();
    _startGroupListRealtimeSubscription();
  }

  @override
  void didUpdateWidget(covariant RedesignSharedExpensesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationController != widget.navigationController) {
      oldWidget.navigationController?._detach(this);
      widget.navigationController?._attach(this);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.navigationController?._detach(this);
    _pollTimer?.cancel();
    _groupListRealtimeReconnectTimer?.cancel();
    unawaited(_groupListRealtimeSubscription?.cancel());
    _pendingRealtimeReconnectTimer?.cancel();
    unawaited(_pendingRealtimeSubscription?.cancel());
    for (final timer in _realtimeReconnectTimers.values) {
      timer.cancel();
    }
    for (final subscription in _realtimeSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _realtimeReconnectTimers.clear();
    _realtimeSubscriptions.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _backgroundRefresh();
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

  bool _shouldStreamGroup(SharedExpenseGroup group) {
    if (group.id.isEmpty || _forbiddenRealtimeGroupIds.contains(group.id)) {
      return false;
    }
    switch (group.status) {
      case SharedExpenseGroupStatus.localOnly:
        return false;
      case SharedExpenseGroupStatus.ready:
        return true;
      case SharedExpenseGroupStatus.pendingApproval:
        return _myPublicKey.isNotEmpty &&
            group.members.any(
              (member) => member.devicePublicKey == _myPublicKey,
            );
    }
  }

  void _syncRealtimeSubscriptions(List<SharedExpenseGroup> groups) {
    for (final groupId in _realtimeSubscriptions.keys.toList()) {
      _stopRealtimeSubscription(groupId);
    }
    for (final groupId in _realtimeReconnectTimers.keys.toList()) {
      _realtimeReconnectTimers.remove(groupId)?.cancel();
    }

    final shouldStream = groups.any(_shouldStreamGroup);
    if (!shouldStream) {
      _stopPendingRealtimeSubscription();
      return;
    }
    _startPendingRealtimeSubscription();
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

  void _stopPendingRealtimeSubscription() {
    _pendingRealtimeReconnectTimer?.cancel();
    _pendingRealtimeReconnectTimer = null;
    _pendingRealtimeReconnectAttempts = 0;
    final subscription = _pendingRealtimeSubscription;
    _pendingRealtimeSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
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
      if (!_groups.any(_shouldStreamGroup)) return;
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

  void _startRealtimeSubscription(String groupId) {
    if (_realtimeSubscriptions.containsKey(groupId)) return;
    _sharedExpensesPageLog('realtime subscribe group=${_logId(groupId)}');

    final subscription = _repository.watchGroupRealtime(groupId).listen(
      _applyRealtimeGroup,
      onError: (Object error, StackTrace stackTrace) {
        _sharedExpensesPageLog(
          'realtime stream failed group=${_logId(groupId)}: $error',
        );
        if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
        _realtimeSubscriptions.remove(groupId);
        if (error is TotalsEngineException && error.statusCode == 403) {
          _forbiddenRealtimeGroupIds.add(groupId);
          unawaited(_loadGroups(refreshFromEngine: true, showErrors: false));
          return;
        }
        _scheduleRealtimeReconnect(groupId);
      },
      onDone: () {
        _sharedExpensesPageLog('realtime stream done group=${_logId(groupId)}');
        _realtimeSubscriptions.remove(groupId);
        _scheduleRealtimeReconnect(groupId);
      },
    );
    _realtimeSubscriptions[groupId] = subscription;
  }

  void _stopRealtimeSubscription(String groupId) {
    final subscription = _realtimeSubscriptions.remove(groupId);
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    _realtimeReconnectTimers.remove(groupId)?.cancel();
  }

  void _scheduleRealtimeReconnect(String groupId) {
    if (!mounted) return;
    if (_realtimeReconnectTimers.containsKey(groupId)) return;
    _realtimeReconnectTimers[groupId] = Timer(_realtimeReconnectDelay, () {
      _realtimeReconnectTimers.remove(groupId);
      if (!mounted) return;
      final group = _groupInState(groupId);
      if (group == null || !_shouldStreamGroup(group)) return;
      if (_realtimeSubscriptions.containsKey(groupId)) return;
      _startRealtimeSubscription(groupId);
    });
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

class _SharedGroupDetailView extends StatefulWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final int initialTabIndex;
  final int openRequestId;
  final String Function(String value) shortKey;
  final VoidCallback onBack;
  final VoidCallback onOpenSettings;
  final VoidCallback onAddExpense;
  final bool isMutating;
  final String? mutationLabel;
  final ValueChanged<SharedExpense> onEditExpense;
  final ValueChanged<SettlementDebt> onSettleDebt;
  final VoidCallback onSendNudge;
  final void Function(String debtorPk, double amount) onNudgeDebt;

  const _SharedGroupDetailView({
    required this.group,
    required this.myPublicKey,
    required this.initialTabIndex,
    required this.openRequestId,
    required this.shortKey,
    required this.onBack,
    required this.onOpenSettings,
    required this.onAddExpense,
    required this.isMutating,
    required this.mutationLabel,
    required this.onEditExpense,
    required this.onSettleDebt,
    required this.onSendNudge,
    required this.onNudgeDebt,
  });

  @override
  State<_SharedGroupDetailView> createState() => _SharedGroupDetailViewState();
}

class _SharedGroupDetailViewState extends State<_SharedGroupDetailView> {
  late int _selectedTab;
  bool _showTransactions = false;
  bool _showMembers = false;

  static const List<Color> _memberColors = [
    AppColors.primaryLight,
    AppColors.incomeSuccess,
    Color(0xFFDB2777),
    AppColors.amber,
    AppColors.blue,
  ];

  @override
  void initState() {
    super.initState();
    _selectedTab = _normalizedTabIndex(widget.initialTabIndex);
  }

  @override
  void didUpdateWidget(covariant _SharedGroupDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.id != widget.group.id ||
        oldWidget.openRequestId != widget.openRequestId) {
      _showTransactions = false;
      _showMembers = false;
      _selectedTab = _normalizedTabIndex(widget.initialTabIndex);
    }
  }

  int _normalizedTabIndex(int value) {
    if (value < 0) return 0;
    if (value > 2) return 2;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    if (_showTransactions) {
      return _SharedGroupTransactionsView(
        group: widget.group,
        myPublicKey: widget.myPublicKey,
        onBack: () => setState(() => _showTransactions = false),
        onAddExpense: widget.onAddExpense,
        isMutating: widget.isMutating,
        mutationLabel: widget.mutationLabel,
        onEditExpense: widget.onEditExpense,
      );
    }

    final members = _memberViews(context);
    if (_showMembers) {
      return _SharedGroupMembersView(
        group: widget.group,
        members: members,
        onBack: () => setState(() => _showMembers = false),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _SharedExpenseFab(
        onPressed: widget.onAddExpense,
        isBusy: widget.isMutating,
        busyLabel: widget.mutationLabel,
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SharedGroupDetailTopBar(
                      group: widget.group,
                      members: members,
                      onBack: widget.onBack,
                      onOpenSettings: widget.onOpenSettings,
                      onOpenMembers: () => setState(() => _showMembers = true),
                    ),
                    const SizedBox(height: 18),
                    _SharedBalanceSummaryCard(
                      group: widget.group,
                      members: members,
                      myPublicKey: widget.myPublicKey,
                      onNudge: widget.onSendNudge,
                    ),
                    const SizedBox(height: 16),
                    _SharedGroupTabs(
                      selectedIndex: _selectedTab,
                      onChanged: (index) => setState(() {
                        _selectedTab = index;
                      }),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 128),
              sliver: SliverToBoxAdapter(
                child: switch (_selectedTab) {
                  0 => _SharedGroupHomeTab(
                      members: members,
                      onSeeAll: () => setState(() => _showTransactions = true),
                      group: widget.group,
                      myPublicKey: widget.myPublicKey,
                      onEditExpense: widget.onEditExpense,
                      onSettleDebt: widget.onSettleDebt,
                      onNudgeDebt: widget.onNudgeDebt,
                    ),
                  1 => _SharedGroupActivitiesTab(
                      group: widget.group,
                      myPublicKey: widget.myPublicKey,
                    ),
                  _ => _SharedGroupAnalyticsTab(
                      group: widget.group,
                      myPublicKey: widget.myPublicKey,
                      pendingApprovalCount: widget.group
                          .pendingApprovalMembers(widget.myPublicKey)
                          .length,
                    ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_SharedMemberView> _memberViews(BuildContext context) {
    final rawMembers = widget.group.members
        .where((member) => member.devicePublicKey.isNotEmpty)
        .toList(growable: true)
      ..sort((a, b) {
        if (a.devicePublicKey == widget.myPublicKey) return -1;
        if (b.devicePublicKey == widget.myPublicKey) return 1;
        return 0;
      });
    final members = rawMembers.isEmpty
        ? [
            SharedExpenseMember(
              devicePublicKey: widget.myPublicKey,
              joinedAt: widget.group.createdAt,
            ),
          ]
        : rawMembers;
    final views = <_SharedMemberView>[];
    for (var i = 0; i < members.length; i++) {
      final member = members[i];
      final isMe = member.devicePublicKey == widget.myPublicKey ||
          (widget.myPublicKey.isEmpty && i == 0);
      final resolved = widget.group.displayNameFor(
        widget.myPublicKey,
        member.devicePublicKey,
      );
      final label = resolved.trim().isNotEmpty
          ? resolved
          : (isMe ? context.l10nText('You') : context.l10nText('Member'));
      final color = member.devicePublicKey.isEmpty
          ? _memberColors[i % _memberColors.length]
          : Color(memberColorFor(widget.group, member.devicePublicKey));
      final paymentAddress = isMe
          ? widget.group.myPaymentAddress ??
              widget.group.paymentAddresses[member.devicePublicKey]
          : widget.group.paymentAddresses[member.devicePublicKey];
      views.add(
        _SharedMemberView(
          label: label,
          shortKey: widget.shortKey(member.devicePublicKey),
          color: color,
          publicKey: member.devicePublicKey,
          paymentAddress: paymentAddress,
        ),
      );
    }
    return views;
  }
}

class _SharedMemberView {
  final String label;
  final String shortKey;
  final Color color;
  final String publicKey;
  final SharedPaymentAddress? paymentAddress;

  const _SharedMemberView({
    required this.label,
    required this.shortKey,
    required this.color,
    this.publicKey = '',
    this.paymentAddress,
  });

  String get initial {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}

class _SharedExpenseFab extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isBusy;
  final String? busyLabel;

  const _SharedExpenseFab({
    required this.onPressed,
    this.isBusy = false,
    this.busyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final label = context.l10nText(busyLabel ?? 'Sending');
    return SafeArea(
      minimum: const EdgeInsets.only(right: 4, bottom: 92),
      child: isBusy
          ? Semantics(
              enabled: false,
              child: IgnorePointer(
                child: FloatingActionButton.extended(
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
                onPressed: onPressed,
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

class _SharedGroupMembersView extends StatelessWidget {
  final SharedExpenseGroup group;
  final List<_SharedMemberView> members;
  final VoidCallback onBack;

  const _SharedGroupMembersView({
    required this.group,
    required this.members,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final spentTotals = _memberSpentTotalsFor(group);
    final balances = computeBalancesFor(group);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _SharedMembersTopBar(onBack: onBack),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              sliver: SliverList.separated(
                itemCount: members.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final member = members[index];
                  return _SharedMemberDetailCard(
                    member: member,
                    spent: spentTotals[member.publicKey] ?? 0,
                    balance: balances[member.publicKey] ?? 0,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedMembersTopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _SharedMembersTopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(AppIcons.arrow_back_rounded, size: 25),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.textPrimary(context),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10nText('Members'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedMemberDetailCard extends StatelessWidget {
  final _SharedMemberView member;
  final double spent;
  final double balance;

  const _SharedMemberDetailCard({
    required this.member,
    required this.spent,
    required this.balance,
  });

  @override
  Widget build(BuildContext context) {
    final balanceColor = balance > 0.5
        ? AppColors.incomeSuccess
        : balance < -0.5
            ? AppColors.red
            : AppColors.textPrimary(context);
    final paymentAddress = member.paymentAddress;

    return Container(
      constraints: const BoxConstraints(minHeight: 94),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _SharedMemberCircle(
                member: member,
                size: 46,
                fontSize: 18,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${context.l10nText('Spent')}: ${_formatEtb(spent, context)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 118,
                child: Text(
                  balance.abs() < 0.5
                      ? _formatEtb(0, context)
                      : _formatEtb(balance, context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: balanceColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
              ),
            ],
          ),
          if (paymentAddress != null && paymentAddress.isValid) ...[
            const SizedBox(height: 12),
            _SharedPaymentAccountRow(
              address: paymentAddress,
              title: context.l10nText('Payment account'),
              copyable: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _SharedPaymentAccountRow extends StatelessWidget {
  final SharedPaymentAddress address;
  final String title;
  final bool copyable;

  const _SharedPaymentAccountRow({
    required this.address,
    required this.title,
    required this.copyable,
  });

  @override
  Widget build(BuildContext context) {
    final bank = _sharedExpenseBankFor(address.bankId);
    final bankName = _sharedPaymentBankLabel(context, address.bankId);
    final accountNumber = _paymentAccountNumber(address);
    final content = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background(context).withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        children: [
          _PaymentBankIcon(bank: bank, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$bankName · $accountNumber',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
              ],
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: 10),
            Icon(
              AppIcons.copy,
              size: 18,
              color: AppColors.textSecondary(context),
            ),
          ],
        ],
      ),
    );

    if (!copyable) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _copyPaymentAccountNumber(context, address),
        borderRadius: BorderRadius.circular(10),
        child: content,
      ),
    );
  }
}

class _PaymentBankIcon extends StatelessWidget {
  final Bank bank;
  final double size;

  const _PaymentBankIcon({
    required this.bank,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: bank.image.isEmpty
            ? _PaymentBankFallback()
            : Image.asset(
                bank.image,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _PaymentBankFallback(),
              ),
      ),
    );
  }
}

class _PaymentBankFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      color: AppColors.cardColor(context),
      child: Icon(
        AppIcons.account_balance_rounded,
        size: 22,
        color: AppColors.textSecondary(context),
      ),
    );
  }
}

class _SharedMemberCircle extends StatelessWidget {
  final _SharedMemberView member;
  final double size;
  final double fontSize;

  const _SharedMemberCircle({
    required this.member,
    required this.size,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: member.color,
        shape: BoxShape.circle,
      ),
      child: Text(
        member.initial,
        style: TextStyle(
          color: AppColors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SharedTransactionFilter {
  final String? kind;
  final String? paidBy;
  final double? minAmount;
  final double? maxAmount;
  final DateTime? startDate;
  final DateTime? endDate;

  const _SharedTransactionFilter({
    this.kind,
    this.paidBy,
    this.minAmount,
    this.maxAmount,
    this.startDate,
    this.endDate,
  });

  bool get isActive =>
      kind != null ||
      paidBy != null ||
      minAmount != null ||
      maxAmount != null ||
      startDate != null ||
      endDate != null;

  int get activeCount {
    int count = 0;
    if (kind != null) count++;
    if (paidBy != null) count++;
    if (minAmount != null || maxAmount != null) count++;
    if (startDate != null || endDate != null) count++;
    return count;
  }
}

class _SharedTransactionPayerOption {
  final String publicKey;
  final String label;

  const _SharedTransactionPayerOption({
    required this.publicKey,
    required this.label,
  });
}

class _SharedGroupTransactionsView extends StatefulWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final VoidCallback onBack;
  final VoidCallback onAddExpense;
  final bool isMutating;
  final String? mutationLabel;
  final ValueChanged<SharedExpense> onEditExpense;

  const _SharedGroupTransactionsView({
    required this.group,
    required this.myPublicKey,
    required this.onBack,
    required this.onAddExpense,
    required this.isMutating,
    required this.mutationLabel,
    required this.onEditExpense,
  });

  @override
  State<_SharedGroupTransactionsView> createState() =>
      _SharedGroupTransactionsViewState();
}

class _SharedGroupTransactionsViewState
    extends State<_SharedGroupTransactionsView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _SharedTransactionFilter _filter = const _SharedTransactionFilter();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilterSheet() async {
    final payerOptions = _payerOptions();
    final result = await showModalBottomSheet<_SharedTransactionFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SharedTransactionsFilterSheet(
        currentFilter: _filter,
        payerOptions: payerOptions,
      ),
    );

    if (!mounted || result == null) return;
    setState(() => _filter = result);
  }

  List<_SharedTransactionPayerOption> _payerOptions() {
    final keys = <String>{};
    for (final member in widget.group.members) {
      if (member.devicePublicKey.isNotEmpty) {
        keys.add(member.devicePublicKey);
      }
    }
    for (final expense in widget.group.expenses) {
      if (expense.paidBy.isNotEmpty) keys.add(expense.paidBy);
    }

    final options = keys.map((publicKey) {
      final label = widget.group.displayNameFor(widget.myPublicKey, publicKey);
      return _SharedTransactionPayerOption(
        publicKey: publicKey,
        label: label.trim().isEmpty ? _logId(publicKey) : label,
      );
    }).toList()
      ..sort((a, b) {
        if (a.publicKey == widget.myPublicKey) return -1;
        if (b.publicKey == widget.myPublicKey) return 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return options;
  }

  List<SharedExpense> _filteredExpenses() {
    final queryLower = _query.trim().toLowerCase();
    final result = widget.group.expenses.where((expense) {
      if (expense.deleted) return false;

      if (_filter.kind != null && expense.kind != _filter.kind) {
        return false;
      }

      if (_filter.paidBy != null && expense.paidBy != _filter.paidBy) {
        return false;
      }

      if (_filter.minAmount != null && expense.amount < _filter.minAmount!) {
        return false;
      }

      if (_filter.maxAmount != null && expense.amount > _filter.maxAmount!) {
        return false;
      }

      if (_filter.startDate != null || _filter.endDate != null) {
        if (expense.timestamp <= 0) return false;
        final timestamp =
            DateTime.fromMillisecondsSinceEpoch(expense.timestamp);
        if (_filter.startDate != null) {
          final start = DateTime(
            _filter.startDate!.year,
            _filter.startDate!.month,
            _filter.startDate!.day,
          );
          if (timestamp.isBefore(start)) return false;
        }
        if (_filter.endDate != null) {
          final end = _filter.endDate!
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1));
          if (timestamp.isAfter(end)) return false;
        }
      }

      if (queryLower.isEmpty) return true;
      final reasonMatch = expense.reason.toLowerCase().contains(queryLower);
      final payerName = widget.group
          .displayNameFor(widget.myPublicKey, expense.paidBy)
          .toLowerCase();
      final payerMatch = payerName.contains(queryLower);
      final recipientMatch = expense.splitAmong.any((publicKey) {
        final label = widget.group
            .displayNameFor(widget.myPublicKey, publicKey)
            .toLowerCase();
        return label.contains(queryLower);
      });
      return reasonMatch || payerMatch || recipientMatch;
    }).toList(growable: false)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.trim().isNotEmpty;
    final hasEmptyFilterState = hasQuery || _filter.isActive;
    final filtered = _filteredExpenses();
    final transactionCount = filtered.length;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _SharedExpenseFab(
        onPressed: widget.onAddExpense,
        isBusy: widget.isMutating,
        busyLabel: widget.mutationLabel,
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SharedTransactionsTopBar(
                      groupName: widget.group.name,
                      onBack: widget.onBack,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      context.l10nText('Transactions'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppColors.textPrimary(context),
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                    ),
                    const SizedBox(height: 18),
                    _SharedTransactionsSearchFilterRow(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      onFilterTap: _openFilterSheet,
                      activeFilterCount: _filter.activeCount,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 128),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SharedTransactionsCountHeader(count: transactionCount),
                    if (filtered.isEmpty)
                      _SharedTransactionsEmptyState(
                          hasQuery: hasEmptyFilterState)
                    else
                      Column(
                        children: [
                          for (var i = 0; i < filtered.length; i++)
                            _SharedExpenseRow(
                              expense: filtered[i],
                              group: widget.group,
                              myPublicKey: widget.myPublicKey,
                              showDivider: i < filtered.length - 1,
                              onTap: () => widget.onEditExpense(filtered[i]),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedTransactionsTopBar extends StatelessWidget {
  final String groupName;
  final VoidCallback onBack;

  const _SharedTransactionsTopBar({
    required this.groupName,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onBack,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              AppIcons.chevron_left,
              size: 20,
              color: AppColors.textTertiary(context),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                groupName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textTertiary(context),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedTransactionsSearchFilterRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;
  final int activeFilterCount;

  const _SharedTransactionsSearchFilterRow({
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
    this.activeFilterCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary(context),
              ),
              decoration: InputDecoration(
                hintText: context.l10nText('Search reason or member...'),
                hintStyle: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                filled: true,
                fillColor: AppColors.surfaceColor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderColor(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderColor(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.primaryLight,
                    width: 1.3,
                  ),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _SharedTransactionsFilterActionButton(
          onTap: onFilterTap,
          activeFilterCount: activeFilterCount,
        ),
      ],
    );
  }
}

class _SharedTransactionsFilterActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final int activeFilterCount;

  const _SharedTransactionsFilterActionButton({
    required this.onTap,
    this.activeFilterCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    const badgeSize = 18.0;
    const badgeOffset = -4.0;
    const iconSize = 22.0;
    const borderRadius = 10.0;
    const badgeFontSize = 10.0;
    final hasFilters = activeFilterCount > 0;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: hasFilters
                  ? AppColors.primaryDark.withValues(alpha: 0.1)
                  : AppColors.cardColor(context),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: hasFilters
                    ? AppColors.primaryDark
                    : AppColors.borderColor(context),
              ),
            ),
            child: Icon(
              AppIcons.filter_list,
              color: hasFilters
                  ? AppColors.primaryDark
                  : AppColors.textSecondary(context),
              size: iconSize,
            ),
          ),
          if (hasFilters)
            Positioned(
              top: badgeOffset,
              right: badgeOffset,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$activeFilterCount',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: badgeFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SharedTransactionsFilterSheet extends StatefulWidget {
  final _SharedTransactionFilter currentFilter;
  final List<_SharedTransactionPayerOption> payerOptions;

  const _SharedTransactionsFilterSheet({
    required this.currentFilter,
    required this.payerOptions,
  });

  @override
  State<_SharedTransactionsFilterSheet> createState() =>
      _SharedTransactionsFilterSheetState();
}

class _SharedTransactionsFilterSheetState
    extends State<_SharedTransactionsFilterSheet> {
  late String? _selectedKind;
  late String? _selectedPaidBy;
  late final TextEditingController _minAmountController;
  late final TextEditingController _maxAmountController;
  String? _amountErrorText;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _selectedKind = widget.currentFilter.kind;
    _selectedPaidBy = widget.currentFilter.paidBy;
    _minAmountController = TextEditingController(
      text: _formatAmountInput(widget.currentFilter.minAmount),
    );
    _maxAmountController = TextEditingController(
      text: _formatAmountInput(widget.currentFilter.maxAmount),
    );
    _startDate = widget.currentFilter.startDate;
    _endDate = widget.currentFilter.endDate;
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  void _clearAll() {
    setState(() {
      _selectedKind = null;
      _selectedPaidBy = null;
      _minAmountController.clear();
      _maxAmountController.clear();
      _amountErrorText = null;
      _startDate = null;
      _endDate = null;
    });
  }

  void _apply() {
    final minRaw = _minAmountController.text;
    final maxRaw = _maxAmountController.text;
    final minAmount = _parseAmountInput(minRaw);
    final maxAmount = _parseAmountInput(maxRaw);
    final amountError = _buildAmountValidationMessage(
      minRaw: minRaw,
      maxRaw: maxRaw,
      minAmount: minAmount,
      maxAmount: maxAmount,
    );

    if (amountError != null) {
      setState(() => _amountErrorText = amountError);
      return;
    }

    Navigator.of(context).pop(
      _SharedTransactionFilter(
        kind: _selectedKind,
        paidBy: _selectedPaidBy,
        minAmount: minAmount,
        maxAmount: maxAmount,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
  }

  double? _parseAmountInput(String raw) {
    final normalized = raw.replaceAll(',', '').trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  bool _hasInvalidAmountInput(String raw) {
    final normalized = raw.replaceAll(',', '').trim();
    return normalized.isNotEmpty && double.tryParse(normalized) == null;
  }

  String? _buildAmountValidationMessage({
    required String minRaw,
    required String maxRaw,
    required double? minAmount,
    required double? maxAmount,
  }) {
    if (_hasInvalidAmountInput(minRaw) || _hasInvalidAmountInput(maxRaw)) {
      return 'Enter a valid amount';
    }
    if (minAmount != null && maxAmount != null && maxAmount < minAmount) {
      return 'Maximum must be at least minimum.';
    }
    return null;
  }

  String _formatAmountInput(double? amount) {
    if (amount == null) return '';
    if (amount == amount.roundToDouble()) {
      return amount.toStringAsFixed(0);
    }
    return amount
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _handleAmountChanged(String _) {
    if (_amountErrorText == null) return;
    final minRaw = _minAmountController.text;
    final maxRaw = _maxAmountController.text;
    final minAmount = _parseAmountInput(minRaw);
    final maxAmount = _parseAmountInput(maxRaw);
    setState(() {
      _amountErrorText = _buildAmountValidationMessage(
        minRaw: minRaw,
        maxRaw: maxRaw,
        minAmount: minAmount,
        maxAmount: maxAmount,
      );
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) {
        final dark = AppColors.isDark(ctx);
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: dark
                ? const ColorScheme.dark(
                    primary: AppColors.primaryLight,
                    onPrimary: AppColors.white,
                    surface: AppColors.darkCard,
                    onSurface: AppColors.white,
                  )
                : const ColorScheme.light(
                    primary: AppColors.primaryDark,
                    onPrimary: AppColors.white,
                    surface: AppColors.white,
                    onSurface: AppColors.slate900,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final navBarPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.slate400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10nText('Filter Transactions'),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    AppIcons.close,
                    color: AppColors.textSecondary(context),
                  ),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                16 + bottomPadding + navBarPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('TYPE'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SharedFilterSheetChip(
                        label: 'All',
                        selected: _selectedKind == null,
                        onTap: () => setState(() => _selectedKind = null),
                      ),
                      _SharedFilterSheetChip(
                        label: 'Expense',
                        selected: _selectedKind == 'expense',
                        onTap: () => setState(() => _selectedKind = 'expense'),
                      ),
                      _SharedFilterSheetChip(
                        label: 'Settlement',
                        selected: _selectedKind == 'settlement',
                        onTap: () =>
                            setState(() => _selectedKind = 'settlement'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('PAID BY'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SharedFilterSheetChip(
                        label: 'All',
                        selected: _selectedPaidBy == null,
                        onTap: () => setState(() => _selectedPaidBy = null),
                      ),
                      for (final payer in widget.payerOptions)
                        _SharedFilterSheetChip(
                          label: payer.label,
                          selected: _selectedPaidBy == payer.publicKey,
                          onTap: () =>
                              setState(() => _selectedPaidBy = payer.publicKey),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('AMOUNT RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SharedAmountFilterField(
                          controller: _minAmountController,
                          hint: 'Min',
                          hasError: _amountErrorText != null,
                          onChanged: _handleAmountChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SharedAmountFilterField(
                          controller: _maxAmountController,
                          hint: 'Max',
                          hasError: _amountErrorText != null,
                          onChanged: _handleAmountChanged,
                        ),
                      ),
                    ],
                  ),
                  if (_amountErrorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.l10nText(_amountErrorText!),
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel('DATE RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SharedDatePickerField(
                          hint: 'Start date',
                          value: _startDate != null
                              ? _formatSharedDate(_startDate!)
                              : null,
                          onTap: () => _pickDate(isStart: true),
                          onClear: _startDate != null
                              ? () => setState(() => _startDate = null)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SharedDatePickerField(
                          hint: 'End date',
                          value: _endDate != null
                              ? _formatSharedDate(_endDate!)
                              : null,
                          onTap: () => _pickDate(isStart: false),
                          onClear: _endDate != null
                              ? () => setState(() => _endDate = null)
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clearAll,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary(context),
                            side: BorderSide(
                              color: AppColors.borderColor(context),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Clear All'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _apply,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Apply Filters'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      context.l10nText(text),
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

class _SharedFilterSheetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SharedFilterSheetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryDark
              : AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primaryDark
                : AppColors.borderColor(context),
          ),
        ),
        child: Text(
          context.l10nText(label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                selected ? AppColors.white : AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SharedDatePickerField extends StatelessWidget {
  final String hint;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _SharedDatePickerField({
    required this.hint,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? context.l10nText(hint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value != null
                      ? AppColors.textPrimary(context)
                      : AppColors.textTertiary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  AppIcons.close,
                  size: 16,
                  color: AppColors.textTertiary(context),
                ),
              )
            else
              Icon(
                AppIcons.calendar_today_outlined,
                size: 16,
                color: AppColors.textTertiary(context),
              ),
          ],
        ),
      ),
    );
  }
}

class _SharedAmountFilterField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  const _SharedAmountFilterField({
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      style: TextStyle(
        color: AppColors.textPrimary(context),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: context.l10nText(hint),
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        prefixText: '${context.l10nText('ETB')} ',
        prefixStyle: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: AppColors.surfaceColor(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.borderColor(context),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.borderColor(context),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.primaryLight,
          ),
        ),
      ),
    );
  }
}

class _SharedTransactionsCountHeader extends StatelessWidget {
  final int count;

  const _SharedTransactionsCountHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final transactionLabel = count == 1
        ? context.l10nText('TRANSACTION')
        : context.l10nText('TRANSACTIONS');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 6, bottom: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderColor(context)),
        ),
      ),
      child: Text(
        '$count $transactionLabel',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.textTertiary(context),
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
      ),
    );
  }
}

class _SharedTransactionsEmptyState extends StatelessWidget {
  final bool hasQuery;

  const _SharedTransactionsEmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderColor(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              AppIcons.receipt_long_rounded,
              color: AppColors.primaryLight,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasQuery
                      ? context.l10nText('No matching transactions')
                      : context.l10nText('No transactions yet'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasQuery
                      ? context.l10nText('Try a different search.')
                      : context.l10nText('Group expenses will appear here.'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary(context),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatEtb(0, context),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
          ),
        ],
      ),
    );
  }
}

class _SharedGroupDetailTopBar extends StatelessWidget {
  final SharedExpenseGroup group;
  final List<_SharedMemberView> members;
  final VoidCallback onBack;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMembers;

  const _SharedGroupDetailTopBar({
    required this.group,
    required this.members,
    required this.onBack,
    required this.onOpenSettings,
    required this.onOpenMembers,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 67,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 44,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final centerMaxWidth =
                    (constraints.maxWidth - 132).clamp(120.0, 220.0).toDouble();

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: centerMaxWidth),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onOpenMembers,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: _SharedGroupAppBarTitle(group: group),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: onBack,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                AppIcons.chevron_left,
                                size: 20,
                                color: AppColors.textTertiary(context),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                context.l10nText('Groups'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: AppColors.textTertiary(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: onOpenSettings,
                        icon: const Icon(AppIcons.more_horiz, size: 24),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.cardColor(context),
                          foregroundColor: AppColors.textSecondary(context),
                          side: BorderSide(
                            color: AppColors.borderColor(context),
                          ),
                          minimumSize: const Size(44, 44),
                          shape: const CircleBorder(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -5),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpenMembers,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _StackedMemberAvatars(
                    members: members,
                    maxVisible: 4,
                    showOverflowCount: true,
                    size: 23,
                    overlap: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedGroupAppBarTitle extends StatelessWidget {
  final SharedExpenseGroup group;

  const _SharedGroupAppBarTitle({
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      group.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w900,
          ),
    );
  }
}

class _StackedMemberAvatars extends StatelessWidget {
  final List<_SharedMemberView> members;
  final int maxVisible;
  final bool showOverflowCount;
  final double size;
  final double overlap;

  const _StackedMemberAvatars({
    required this.members,
    this.maxVisible = 4,
    this.showOverflowCount = false,
    this.size = 28,
    this.overlap = 19,
  });

  @override
  Widget build(BuildContext context) {
    final shouldShowOverflow = showOverflowCount && members.length > maxVisible;
    final visibleCount =
        shouldShowOverflow ? (maxVisible > 0 ? maxVisible - 1 : 0) : maxVisible;
    final visibleMembers = members.take(visibleCount).toList(growable: false);
    final overflowCount =
        shouldShowOverflow ? members.length - visibleMembers.length : 0;
    final itemCount = visibleMembers.length + (shouldShowOverflow ? 1 : 0);
    if (itemCount == 0) return const SizedBox.shrink();

    return SizedBox(
      width: size + ((itemCount - 1) * overlap),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < visibleMembers.length; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: visibleMembers[i].color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.background(context),
                    width: 2,
                  ),
                ),
                child: Text(
                  visibleMembers[i].initial,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ),
          if (shouldShowOverflow)
            Positioned(
              left: visibleMembers.length * overlap,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary(context),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.background(context),
                    width: 2,
                  ),
                ),
                child: Text(
                  '+$overflowCount',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SharedBalanceSummaryCard extends StatelessWidget {
  final SharedExpenseGroup group;
  final List<_SharedMemberView> members;
  final String myPublicKey;
  final VoidCallback? onNudge;

  const _SharedBalanceSummaryCard({
    required this.group,
    required this.members,
    required this.myPublicKey,
    this.onNudge,
  });

  @override
  Widget build(BuildContext context) {
    final isReady = group.status == SharedExpenseGroupStatus.ready;
    final balances =
        isReady ? computeBalancesFor(group) : const <String, double>{};
    final myBalance = balances[myPublicKey] ?? 0.0;
    final settled = myBalance.abs() < 0.5;
    final showNudgeAction = isReady && !settled && myBalance > 0;

    final String label;
    final Color amountColor;
    if (!isReady) {
      label = context.l10nText('PENDING SETUP');
      amountColor = AppColors.textPrimary(context);
    } else if (settled) {
      label = context.l10nText("YOU'RE SETTLED UP");
      amountColor = AppColors.textPrimary(context);
    } else if (myBalance > 0) {
      label = context.l10nText("YOU'RE OWED");
      amountColor = AppColors.incomeSuccess;
    } else {
      label = context.l10nText('YOU OWE');
      amountColor = AppColors.red;
    }

    final amountText = _formatEtb(myBalance.abs(), context);
    final String? subtitleText = !isReady
        ? context.l10nText('Waiting for group approval')
        : settled
            ? context.l10nText('Everything is even')
            : showNudgeAction
                ? context.l10nText('Send a nudge')
                : null;

    final memberByPublicKey = {
      for (final member in members)
        if (member.publicKey.isNotEmpty) member.publicKey: member,
    };
    final amountByCounterparty = <String, double>{};
    if (isReady && !settled) {
      for (final debt in settlementPlanFor(group).debts) {
        final String? counterpartyPk;
        if (myBalance > 0 && debt.to == myPublicKey) {
          counterpartyPk = debt.from;
        } else if (myBalance < 0 && debt.from == myPublicKey) {
          counterpartyPk = debt.to;
        } else {
          counterpartyPk = null;
        }
        if (counterpartyPk == null || counterpartyPk.isEmpty) continue;
        amountByCounterparty.update(
          counterpartyPk,
          (current) => current + debt.amount,
          ifAbsent: () => debt.amount,
        );
      }
    }
    final counterparties = amountByCounterparty.entries
        .map((entry) {
          final member = memberByPublicKey[entry.key];
          final label = member?.label ??
              group.displayNameFor(
                myPublicKey,
                entry.key,
              );
          final color =
              member?.color ?? Color(memberColorFor(group, entry.key));
          return _SharedDebtCounterpartySummary(
            label: label,
            color: color,
            amount: entry.value,
          );
        })
        .where((summary) => summary.amount >= 0.5)
        .toList(growable: false)
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final topCounterparties = counterparties.take(2).toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary(context),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    amountText,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: amountColor,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                  ),
                  if (subtitleText != null) ...[
                    const SizedBox(height: 8),
                    _SharedBalanceSubtitle(
                      text: subtitleText,
                      onTap: showNudgeAction ? onNudge : null,
                    ),
                  ],
                ],
              ),
            ),
            if (topCounterparties.isNotEmpty) ...[
              const SizedBox(width: 14),
              VerticalDivider(
                color: AppColors.borderColor(context),
                width: 1,
                thickness: 1,
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final counterparty in topCounterparties) ...[
                      Text(
                        counterparty.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: counterparty.color,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatEtb(counterparty.amount, context),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: myBalance > 0
                                  ? AppColors.incomeSuccess
                                  : AppColors.red,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SharedDebtCounterpartySummary {
  final String label;
  final Color color;
  final double amount;

  const _SharedDebtCounterpartySummary({
    required this.label,
    required this.color,
    required this.amount,
  });
}

class _SharedBalanceSubtitle extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;

  const _SharedBalanceSubtitle({
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary(context),
        );
    if (onTap == null) {
      return Text(text, style: baseStyle);
    }

    final linkStyle = baseStyle?.copyWith(
      color: AppColors.primaryLight,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primaryLight.withValues(alpha: 0.55),
    );

    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(text, style: linkStyle),
            ),
          ),
        ),
      ),
    );
  }
}

class _SharedGroupTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _SharedGroupTabs({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.l10nText('Home'),
      context.l10nText('Activities'),
      context.l10nText('Analytics'),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.mutedFill(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: _SharedGroupTabButton(
                label: labels[i],
                isSelected: selectedIndex == i,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _SharedGroupTabButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SharedGroupTabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryDark : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: isSelected
                  ? AppColors.white
                  : AppColors.textSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

class _SharedGroupHomeTab extends StatelessWidget {
  final List<_SharedMemberView> members;
  final VoidCallback onSeeAll;
  final SharedExpenseGroup group;
  final String myPublicKey;
  final ValueChanged<SharedExpense> onEditExpense;
  final ValueChanged<SettlementDebt> onSettleDebt;
  final void Function(String debtorPk, double amount) onNudgeDebt;

  const _SharedGroupHomeTab({
    required this.members,
    required this.onSeeAll,
    required this.group,
    required this.myPublicKey,
    required this.onEditExpense,
    required this.onSettleDebt,
    required this.onNudgeDebt,
  });

  Future<void> _openDebtActions(
    BuildContext context,
    SettlementDebt debt,
  ) async {
    final action = await showModalBottomSheet<_DebtAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _DebtActionSheet(
        debt: debt,
        group: group,
        myPublicKey: myPublicKey,
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case _DebtAction.settle:
        if (debt.from == myPublicKey || debt.to == myPublicKey) {
          onSettleDebt(debt);
        }
        break;
      case _DebtAction.nudge:
        if (debt.to == myPublicKey) {
          onNudgeDebt(debt.from, debt.amount);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = group.expenses
        .where((e) => !e.deleted)
        .toList(growable: false)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final recent = active.take(6).toList(growable: false);
    final plan = settlementPlanFor(group);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SharedSectionHeader(
          label: context.l10nText('RECENT'),
          actionLabel: context.l10nText('See all'),
          onAction: onSeeAll,
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          _SharedDetailEmptyBlock(
            icon: AppIcons.receipt_long_rounded,
            title: context.l10nText('No expenses yet'),
            subtitle: context.l10nText(
              'Tap + to add the first group expense.',
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < recent.length; i++)
                _SharedExpenseRow(
                  expense: recent[i],
                  group: group,
                  myPublicKey: myPublicKey,
                  showDivider: i < recent.length - 1,
                  onTap: () => onEditExpense(recent[i]),
                ),
            ],
          ),
        const SizedBox(height: 22),
        _SharedSectionHeader(label: context.l10nText('Debts')),
        const SizedBox(height: 8),
        if (plan.debts.isEmpty)
          const _SharedSettleEmptyRow()
        else
          Column(
            children: [
              for (final debt in plan.debts)
                _SharedSettleArrow(
                  debt: debt,
                  group: group,
                  myPublicKey: myPublicKey,
                  onTap: () => _openDebtActions(context, debt),
                ),
            ],
          ),
      ],
    );
  }
}

/// One row in the Recent list — colored left bar + reason + amount.
class _SharedExpenseRow extends StatelessWidget {
  final SharedExpense expense;
  final SharedExpenseGroup group;
  final String myPublicKey;
  final VoidCallback? onTap;
  final bool showDivider;
  const _SharedExpenseRow({
    required this.expense,
    required this.group,
    required this.myPublicKey,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final transactionProvider = context.watch<TransactionProvider>();
    final linkedRef = expense.linkedTxRef?.trim();
    final linkedTransaction = transactionProvider.transactionByReference(
      linkedRef,
    );
    final payerColor = Color(memberColorFor(group, expense.paidBy));
    final payerName = group.displayNameFor(myPublicKey, expense.paidBy);
    final isSettlement = expense.kind == 'settlement';
    final recipient =
        expense.splitAmong.isNotEmpty ? expense.splitAmong.first : '';
    final recipientName = recipient.isNotEmpty
        ? group.displayNameFor(myPublicKey, recipient)
        : '';
    final recipientColor = recipient.isNotEmpty
        ? Color(memberColorFor(group, recipient))
        : payerColor;
    final ago = _shortRelative(expense.timestamp);

    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: AppColors.borderColor(context),
                  width: 1,
                ),
              )
            : null,
      ),
      child: IntrinsicHeight(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: payerColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isSettlement)
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              payerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: payerColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          Text('  →  ',
                              style: TextStyle(
                                  color: AppColors.textTertiary(context),
                                  fontWeight: FontWeight.w600)),
                          Flexible(
                            child: Text(
                              recipientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: recipientColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        expense.reason.isEmpty ? '(no reason)' : expense.reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary(context),
                            ),
                        children: [
                          if (!isSettlement) ...[
                            TextSpan(
                              text: payerName,
                              style: TextStyle(
                                color: payerColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text:
                                  ' ${context.l10nText('paid')} · ${context.l10nText('split')} ${expense.splitAmong.length}',
                            ),
                          ] else
                            TextSpan(text: context.l10nText('Settlement')),
                          if (ago.isNotEmpty) TextSpan(text: ' · $ago'),
                          if (expense.status == 'pending')
                            TextSpan(
                              text: ' · ${context.l10nText('sending')}…',
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (linkedRef != null && linkedRef.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      GestureDetector(
                        onTap: linkedTransaction == null
                            ? null
                            : () => showTransactionDetailsSheet(
                                  context: context,
                                  transaction: linkedTransaction,
                                  provider: transactionProvider,
                                ),
                        child: Row(
                          children: [
                            const Icon(
                              AppIcons.receipt_long_rounded,
                              size: 13,
                              color: AppColors.primaryLight,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                linkedTransaction == null
                                    ? '${context.l10nText('Linked')} · ${_logId(linkedRef)}'
                                    : '${context.l10nText('Linked')} · ${_transactionLinkSummary(linkedTransaction, context)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.primaryLight,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 96,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatEtb(expense.amount, context),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: content,
      ),
    );
  }
}

class _SharedSettleArrow extends StatelessWidget {
  final SettlementDebt debt;
  final SharedExpenseGroup group;
  final String myPublicKey;
  final VoidCallback onTap;
  const _SharedSettleArrow({
    required this.debt,
    required this.group,
    required this.myPublicKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fromName = group.displayNameFor(myPublicKey, debt.from);
    final toName = group.displayNameFor(myPublicKey, debt.to);
    final fromColor = Color(memberColorFor(group, debt.from));
    final toColor = Color(memberColorFor(group, debt.to));
    final nameStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: AppColors.textPrimary(context),
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        );
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.borderColor(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _SharedDebtAvatar(
                        name: fromName,
                        color: fromColor,
                        size: 40,
                        fontSize: 15,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fromName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nameStyle,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatEtb(debt.amount, context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppColors.red,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 48,
                  child: Icon(
                    Icons.arrow_forward,
                    size: 26,
                    color: AppColors.incomeSuccess,
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          toName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: nameStyle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _SharedDebtAvatar(
                        name: toName,
                        color: toColor,
                        size: 40,
                        fontSize: 15,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SharedDebtAvatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  final double fontSize;

  const _SharedDebtAvatar({
    required this.name,
    required this.color,
    this.size = 22,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

enum _DebtAction { settle, nudge }

class _DebtAmountRow extends StatelessWidget {
  final double amount;

  const _DebtAmountRow({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Text(
            context.l10nText('Amount').toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary(context),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _formatEtb(amount, context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DebtSheetTitle extends StatelessWidget {
  final String debtLabel;
  final String debtorName;
  final Color debtorColor;

  const _DebtSheetTitle({
    required this.debtLabel,
    required this.debtorName,
    required this.debtorColor,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary(context),
    );
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: debtLabel),
          TextSpan(
            text: ' · ',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
          TextSpan(
            text: debtorName,
            style: TextStyle(color: debtorColor),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _DebtActionSheet extends StatelessWidget {
  final SettlementDebt debt;
  final SharedExpenseGroup group;
  final String myPublicKey;

  const _DebtActionSheet({
    required this.debt,
    required this.group,
    required this.myPublicKey,
  });

  @override
  Widget build(BuildContext context) {
    final fromName = group.displayNameFor(myPublicKey, debt.from);
    final toName = group.displayNameFor(myPublicKey, debt.to);
    final fromColor = Color(memberColorFor(group, debt.from));
    final canSettle = debt.from == myPublicKey || debt.to == myPublicKey;
    final canNudge = debt.to == myPublicKey;
    final payToAddress =
        debt.from == myPublicKey ? group.paymentAddresses[debt.to] : null;

    return _IosModalShell(
      title: context.l10nText('Debt'),
      titleWidget: _DebtSheetTitle(
        debtLabel: context.l10nText('Debt'),
        debtorName: fromName,
        debtorColor: fromColor,
      ),
      children: [
        _DebtAmountRow(amount: debt.amount),
        if (payToAddress != null && payToAddress.isValid) ...[
          _SharedPaymentAccountRow(
            address: payToAddress,
            title: '${context.l10nText('Pay')} $toName',
            copyable: true,
          ),
          const SizedBox(height: 10),
        ],
        IgnorePointer(
          ignoring: !canSettle,
          child: Opacity(
            opacity: canSettle ? 1 : 0.45,
            child: _IosValueRow(
              icon: AppIcons.check_circle_rounded,
              title: context.l10nText('Mark as settled'),
              subtitle: canSettle
                  ? context.l10nText('Record that this debt was paid')
                  : context.l10nText(
                      'Only people in this debt can mark it settled',
                    ),
              showChevron: false,
              onTap: () => Navigator.of(context).pop(_DebtAction.settle),
            ),
          ),
        ),
        const SizedBox(height: 10),
        IgnorePointer(
          ignoring: !canNudge,
          child: Opacity(
            opacity: canNudge ? 1 : 0.45,
            child: _IosValueRow(
              icon: AppIcons.notifications_outlined,
              title: context.l10nText('Nudge'),
              subtitle: canNudge
                  ? context.l10nText('Remind them to pay you')
                  : context.l10nText('You can nudge people who owe you'),
              showChevron: false,
              onTap: () => Navigator.of(context).pop(_DebtAction.nudge),
            ),
          ),
        ),
      ],
    );
  }
}

String _formatSharedDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[date.month - 1];
  return '$month ${date.day}, ${date.year}';
}

String _shortRelative(int ts) {
  if (ts <= 0) return '';
  final diff = DateTime.now().millisecondsSinceEpoch - ts;
  if (diff < 60 * 1000) return 'just now';
  if (diff < 60 * 60 * 1000) return '${(diff / (60 * 1000)).floor()}m ago';
  if (diff < 24 * 60 * 60 * 1000) {
    return '${(diff / (60 * 60 * 1000)).floor()}h ago';
  }
  if (diff < 7 * 24 * 60 * 60 * 1000) {
    return '${(diff / (24 * 60 * 60 * 1000)).floor()}d ago';
  }
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[d.month - 1]} ${d.day}';
}

String _localizedShortRelative(BuildContext context, int ts) {
  if (ts <= 0) return '';
  final diff = DateTime.now().millisecondsSinceEpoch - ts;
  if (diff < 60 * 1000) {
    return context.l10n('shared.timeJustNow', 'just now');
  }
  if (diff < 60 * 60 * 1000) {
    final count = (diff / (60 * 1000)).floor().toString();
    return context
        .l10n('shared.timeMinutesAgo', '{count}m ago')
        .replaceFirst('{count}', count);
  }
  if (diff < 24 * 60 * 60 * 1000) {
    final count = (diff / (60 * 60 * 1000)).floor().toString();
    return context
        .l10n('shared.timeHoursAgo', '{count}h ago')
        .replaceFirst('{count}', count);
  }
  if (diff < 7 * 24 * 60 * 60 * 1000) {
    final count = (diff / (24 * 60 * 60 * 1000)).floor().toString();
    return context
        .l10n('shared.timeDaysAgo', '{count}d ago')
        .replaceFirst('{count}', count);
  }
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return _formatSharedDate(d);
}

class _SharedGroupActivitiesTab extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  const _SharedGroupActivitiesTab({
    required this.group,
    required this.myPublicKey,
  });

  @override
  Widget build(BuildContext context) {
    final entries = [...group.activity]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SharedSectionHeader(label: context.l10nText('ACTIVITIES')),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          _SharedDetailEmptyBlock(
            icon: AppIcons.toc_rounded,
            title: context.l10nText('No activity yet'),
            subtitle: context.l10nText(
              'Expenses, approvals, and settlements will appear here.',
            ),
          )
        else
          Column(
            children: [
              for (final entry in entries)
                _ActivityRow(
                  entry: entry,
                  group: group,
                  myPublicKey: myPublicKey,
                ),
            ],
          ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final SharedActivityEntry entry;
  final SharedExpenseGroup group;
  final String myPublicKey;
  const _ActivityRow({
    required this.entry,
    required this.group,
    required this.myPublicKey,
  });

  @override
  Widget build(BuildContext context) {
    final actorName = entry.actor.isEmpty
        ? context.l10nText('Someone')
        : group.displayNameFor(myPublicKey, entry.actor);
    final actorColor = entry.actor.isEmpty
        ? AppColors.textSecondary(context)
        : Color(memberColorFor(group, entry.actor));
    final message = _describe(entry, context);
    final ago = _shortRelative(entry.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 7, right: 10),
            decoration: BoxDecoration(
              color: actorColor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                children: [
                  TextSpan(
                    text: actorName,
                    style: TextStyle(
                      color: actorColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' $message'),
                  if (ago.isNotEmpty)
                    TextSpan(
                      text: '  ·  $ago',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _describe(SharedActivityEntry e, BuildContext context) {
    switch (e.kind) {
      case 'group_created':
        return context.l10nText('created the group');
      case 'group_renamed':
        return '${context.l10nText('renamed the group to')} "${e.data['after'] ?? ''}"';
      case 'member_approved':
        return context.l10nText('approved a new member');
      case 'member_joined':
        return context.l10nText('joined the group');
      case 'member_left':
        return context.l10nText('left the group');
      case 'expense_created':
        return '${context.l10nText('added')} "${e.data['reason'] ?? context.l10nText('an expense')}" · ${_formatEtb(e.data['amount'] ?? 0, context)}';
      case 'expense_amount_changed':
        return '${context.l10nText('changed amount to')} ${_formatEtb(e.data['after'] ?? 0, context)}';
      case 'expense_reason_changed':
        return '${context.l10nText('renamed expense to')} "${e.data['after'] ?? ''}"';
      case 'expense_paid_by_changed':
        return context.l10nText('changed who paid');
      case 'expense_split_changed':
        return context.l10nText('changed the split');
      case 'expense_date_changed':
        return context.l10nText('updated the date');
      case 'expense_linked_transaction_changed':
        return e.data['after'] == null
            ? context.l10nText('removed the linked transaction')
            : context.l10nText('linked a transaction');
      case 'expense_deleted':
        return '${context.l10nText('deleted')} "${e.data['reason'] ?? context.l10nText('an expense')}"';
      case 'settlement_created':
        return '${context.l10nText('settled up')} · ${_formatEtb(e.data['amount'] ?? 0, context)}';
      case 'nudge_sent':
        return '${context.l10nText('sent a nudge')} · ${_formatEtb(e.data['amount'] ?? 0, context)}';
      default:
        return e.kind;
    }
  }
}

enum _SharedAnalyticsChartMode { bubbles, monthly }

enum _SharedAnalyticsPeriod { sevenDays, thirtyDays, allTime }

enum _SharedAnalyticsBarPeriod { daily, monthly }

class _SharedAnalyticsTimeWindow {
  final DateTime start;
  final DateTime endExclusive;

  const _SharedAnalyticsTimeWindow({
    required this.start,
    required this.endExclusive,
  });

  bool includes(int timestamp) {
    return timestamp >= start.millisecondsSinceEpoch &&
        timestamp < endExclusive.millisecondsSinceEpoch;
  }
}

int? _sharedAnalyticsCutoffFor(_SharedAnalyticsPeriod period) {
  final now = DateTime.now();
  switch (period) {
    case _SharedAnalyticsPeriod.sevenDays:
      return now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    case _SharedAnalyticsPeriod.thirtyDays:
      return now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    case _SharedAnalyticsPeriod.allTime:
      return null;
  }
}

DateTime _sharedAnalyticsWeekStartForOffset(int offset) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final currentWeekStart = today.subtract(
    Duration(days: today.weekday - DateTime.monday),
  );
  return currentWeekStart.add(Duration(days: offset * 7));
}

DateTime _sharedAnalyticsMonthStartForOffset(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month + offset, 1);
}

String _sharedAnalyticsPeriodShortLabel(
  BuildContext context,
  _SharedAnalyticsPeriod period,
) {
  switch (period) {
    case _SharedAnalyticsPeriod.sevenDays:
      return context.l10nText('7D');
    case _SharedAnalyticsPeriod.thirtyDays:
      return context.l10nText('30D');
    case _SharedAnalyticsPeriod.allTime:
      return context.l10nText('All');
  }
}

String _sharedAnalyticsPeriodLongLabel(
  BuildContext context,
  _SharedAnalyticsPeriod period,
) {
  switch (period) {
    case _SharedAnalyticsPeriod.sevenDays:
      return context.l10nText('Last 7 days');
    case _SharedAnalyticsPeriod.thirtyDays:
      return context.l10nText('Last 30 days');
    case _SharedAnalyticsPeriod.allTime:
      return context.l10nText('All time');
  }
}

String _sharedAnalyticsChartModeLabel(
  BuildContext context,
  _SharedAnalyticsChartMode mode,
) {
  switch (mode) {
    case _SharedAnalyticsChartMode.bubbles:
      return context.l10nText('Bubble chart');
    case _SharedAnalyticsChartMode.monthly:
      return context.l10nText('Bar chart');
  }
}

String _sharedAnalyticsMonthLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

String _sharedAnalyticsDateLabel(DateTime date) {
  final month = _sharedAnalyticsMonthLabel(date).split(' ').first;
  return '$month ${date.day}';
}

String _sharedAnalyticsDateRangeLabel(DateTime start, DateTime endInclusive) {
  if (start.year == endInclusive.year && start.month == endInclusive.month) {
    final month = _sharedAnalyticsMonthLabel(start).split(' ').first;
    return '$month ${start.day} - ${endInclusive.day}';
  }
  return '${_sharedAnalyticsDateLabel(start)} - ${_sharedAnalyticsDateLabel(endInclusive)}';
}

String _sharedAnalyticsWeekdayLabel(BuildContext context, int index) {
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return context.l10nText(labels[index.clamp(0, labels.length - 1)]);
}

String _formatCompactSharedAmount(num amount, BuildContext context) {
  final value = amount.abs();
  final currency = context.l10nText('ETB');
  final suffix = currency == 'ብር' ? ' ብር' : '';
  final prefix = currency == 'ብር' ? '' : '$currency ';
  final compact = value >= 1000000
      ? '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)}M'
      : value >= 1000
          ? '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}K'
          : value.round().toString();
  return '$prefix$compact$suffix';
}

String _formatSignedCompactSharedAmount(num amount, BuildContext context) {
  final sign = amount < -0.5
      ? '-'
      : amount > 0.5
          ? '+'
          : '';
  return '$sign${_formatCompactSharedAmount(amount, context)}';
}

class _SharedGroupAnalyticsTab extends StatefulWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final int pendingApprovalCount;

  const _SharedGroupAnalyticsTab({
    required this.group,
    required this.myPublicKey,
    required this.pendingApprovalCount,
  });

  @override
  State<_SharedGroupAnalyticsTab> createState() =>
      _SharedGroupAnalyticsTabState();
}

class _SharedGroupAnalyticsTabState extends State<_SharedGroupAnalyticsTab> {
  _SharedAnalyticsChartMode _chartMode = _SharedAnalyticsChartMode.bubbles;
  _SharedAnalyticsPeriod _period = _SharedAnalyticsPeriod.thirtyDays;
  _SharedAnalyticsBarPeriod _barPeriod = _SharedAnalyticsBarPeriod.daily;
  int _barWeekOffset = 0;
  int _barMonthOffset = 0;

  _SharedAnalyticsTimeWindow? get _activeBarAnalyticsWindow {
    if (_chartMode != _SharedAnalyticsChartMode.monthly) return null;

    switch (_barPeriod) {
      case _SharedAnalyticsBarPeriod.daily:
        final weekStart = _sharedAnalyticsWeekStartForOffset(_barWeekOffset);
        return _SharedAnalyticsTimeWindow(
          start: weekStart,
          endExclusive: weekStart.add(const Duration(days: 7)),
        );
      case _SharedAnalyticsBarPeriod.monthly:
        final monthStart = _sharedAnalyticsMonthStartForOffset(_barMonthOffset);
        return _SharedAnalyticsTimeWindow(
          start: monthStart,
          endExclusive: DateTime(monthStart.year, monthStart.month + 1, 1),
        );
    }
  }

  String? _activeBarAnalyticsLabel(_SharedAnalyticsTimeWindow? window) {
    if (window == null) return null;

    switch (_barPeriod) {
      case _SharedAnalyticsBarPeriod.daily:
        return _sharedAnalyticsDateRangeLabel(
          window.start,
          window.endExclusive.subtract(const Duration(days: 1)),
        );
      case _SharedAnalyticsBarPeriod.monthly:
        return _sharedAnalyticsMonthLabel(window.start);
    }
  }

  void _navigateBarPeriod({required bool newer}) {
    setState(() {
      switch (_barPeriod) {
        case _SharedAnalyticsBarPeriod.daily:
          if (newer) {
            if (_barWeekOffset < 0) _barWeekOffset++;
          } else {
            _barWeekOffset--;
          }
          break;
        case _SharedAnalyticsBarPeriod.monthly:
          if (newer) {
            if (_barMonthOffset < 0) _barMonthOffset++;
          } else {
            _barMonthOffset--;
          }
          break;
      }
    });
  }

  bool get _hasNewerBarPeriod {
    switch (_barPeriod) {
      case _SharedAnalyticsBarPeriod.daily:
        return _barWeekOffset < 0;
      case _SharedAnalyticsBarPeriod.monthly:
        return _barMonthOffset < 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final barWindow = _activeBarAnalyticsWindow;
    final analytics = _SharedAnalyticsSnapshot.fromGroup(
      widget.group,
      period: _period,
      timeWindow: barWindow,
    );
    final analyticsLabel = _activeBarAnalyticsLabel(barWindow);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SharedSectionHeader(label: context.l10nText('ANALYTICS')),
        const SizedBox(height: 8),
        _SharedAnalyticsChartCard(
          group: widget.group,
          analytics: analytics,
          myPublicKey: widget.myPublicKey,
          mode: _chartMode,
          period: _period,
          barPeriod: _barPeriod,
          barWeekOffset: _barWeekOffset,
          barMonthOffset: _barMonthOffset,
          onModeChanged: (mode) => setState(() => _chartMode = mode),
          onPeriodChanged: (period) => setState(() => _period = period),
          onBarPeriodChanged: (period) => setState(() => _barPeriod = period),
          onNavigateToOlderBarPeriod: () => _navigateBarPeriod(newer: false),
          onNavigateToNewerBarPeriod:
              _hasNewerBarPeriod ? () => _navigateBarPeriod(newer: true) : null,
        ),
        const SizedBox(height: 12),
        _SharedSpendingByDayPanel(
          analytics: analytics,
          period: _period,
          periodLabelOverride: analyticsLabel,
        ),
        const SizedBox(height: 12),
        _SharedAnalyticsPanel(
          title: context.l10nText('Top contributors'),
          subtitle: context.l10nText('Members who covered the most spending'),
          emptyTitle: context.l10nText('No spending yet'),
          emptySubtitle: context.l10nText('Shared expenses will appear here.'),
          children: [
            for (final member in analytics.topSpenders.take(5))
              _SharedAnalyticsMemberBar(
                group: widget.group,
                myPublicKey: widget.myPublicKey,
                publicKey: member.publicKey,
                value: member.value,
                maxValue: analytics.maxSpent,
                trailing: _formatEtb(member.value, context),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _SharedMoneyFlowSection(
          group: widget.group,
          analytics: analytics,
          myPublicKey: widget.myPublicKey,
        ),
        const SizedBox(height: 12),
        _SharedAnalyticsSummaryGrid(
          group: widget.group,
          analytics: analytics,
          pendingApprovalCount: widget.pendingApprovalCount,
        ),
      ],
    );
  }
}

class _SharedAnalyticsSnapshot {
  final double splitTotal;
  final double settlementTotal;
  final double openBalanceTotal;
  final double maxSpent;
  final double maxBalanceAbs;
  final int splitExpenseCount;
  final int settlementCount;
  final int activeMemberCount;
  final int openDebtCount;
  final int linkedTransactionCount;
  final double largestExpenseAmount;
  final String largestExpenseReason;
  final String largestExpensePaidBy;
  final double largestSettlementAmount;
  final String largestSettlementFrom;
  final String largestSettlementTo;
  final double largestDebtAmount;
  final String largestDebtFrom;
  final String largestDebtTo;
  final double averageExpenseAmount;
  final double maxMonthSpend;
  final double maxDebtAbs;
  final double maxWeekdaySpend;
  final int peakWeekdayIndex;
  final List<_SharedAnalyticsMemberValue> topSpenders;
  final List<_SharedAnalyticsMemberValue> balanceLeaders;
  final List<_SharedAnalyticsMemberValue> balanceBubbles;
  final List<_SharedAnalyticsMonthBucket> monthlyBuckets;
  final List<double> weekdayTotals;

  const _SharedAnalyticsSnapshot({
    required this.splitTotal,
    required this.settlementTotal,
    required this.openBalanceTotal,
    required this.maxSpent,
    required this.maxBalanceAbs,
    required this.splitExpenseCount,
    required this.settlementCount,
    required this.activeMemberCount,
    required this.openDebtCount,
    required this.linkedTransactionCount,
    required this.largestExpenseAmount,
    required this.largestExpenseReason,
    required this.largestExpensePaidBy,
    required this.largestSettlementAmount,
    required this.largestSettlementFrom,
    required this.largestSettlementTo,
    required this.largestDebtAmount,
    required this.largestDebtFrom,
    required this.largestDebtTo,
    required this.averageExpenseAmount,
    required this.maxMonthSpend,
    required this.maxDebtAbs,
    required this.maxWeekdaySpend,
    required this.peakWeekdayIndex,
    required this.topSpenders,
    required this.balanceLeaders,
    required this.balanceBubbles,
    required this.monthlyBuckets,
    required this.weekdayTotals,
  });

  factory _SharedAnalyticsSnapshot.fromGroup(
    SharedExpenseGroup group, {
    required _SharedAnalyticsPeriod period,
    _SharedAnalyticsTimeWindow? timeWindow,
  }) {
    final cutoff = _sharedAnalyticsCutoffFor(period);
    final scopedExpenses = timeWindow != null
        ? group.expenses
            .where((expense) => timeWindow.includes(expense.timestamp))
            .toList(growable: false)
        : cutoff == null
            ? group.expenses
            : group.expenses
                .where((expense) => expense.timestamp >= cutoff)
                .toList(growable: false);
    final scopedGroup = timeWindow == null && cutoff == null
        ? group
        : group.copyWith(expenses: scopedExpenses);
    final spentByMember = <String, double>{
      for (final member in group.members) member.devicePublicKey: 0,
    };
    final activeMembers = <String>{};
    var splitTotal = 0.0;
    var settlementTotal = 0.0;
    var splitExpenseCount = 0;
    var settlementCount = 0;
    var linkedTransactionCount = 0;
    var largestExpenseAmount = 0.0;
    var largestExpenseReason = '';
    var largestExpensePaidBy = '';
    var largestSettlementAmount = 0.0;
    var largestSettlementFrom = '';
    var largestSettlementTo = '';
    final monthTotalsByMember = <int, Map<String, double>>{};
    final weekdayTotals = List<double>.filled(7, 0);

    for (final expense in scopedExpenses) {
      if (expense.deleted || expense.amount <= 0) continue;
      if (expense.kind == 'settlement') {
        settlementCount++;
        settlementTotal += expense.amount;
        if (expense.amount > largestSettlementAmount) {
          largestSettlementAmount = expense.amount;
          largestSettlementFrom = expense.paidBy;
          largestSettlementTo =
              expense.splitAmong.isEmpty ? '' : expense.splitAmong.first;
        }
        continue;
      }

      splitExpenseCount++;
      splitTotal += expense.amount;
      if (expense.amount > largestExpenseAmount) {
        largestExpenseAmount = expense.amount;
        largestExpenseReason = expense.reason;
        largestExpensePaidBy = expense.paidBy;
      }
      if (expense.linkedTxRef?.trim().isNotEmpty ?? false) {
        linkedTransactionCount++;
      }
      if (expense.paidBy.isNotEmpty) {
        activeMembers.add(expense.paidBy);
        spentByMember.update(
          expense.paidBy,
          (current) => current + expense.amount,
          ifAbsent: () => expense.amount,
        );
      }
      activeMembers.addAll(expense.splitAmong.where((pk) => pk.isNotEmpty));

      final paidDate = DateTime.fromMillisecondsSinceEpoch(expense.timestamp);
      final weekdayIndex = (paidDate.weekday - 1).clamp(0, 6).toInt();
      weekdayTotals[weekdayIndex] += expense.amount;
      final monthKey = paidDate.year * 100 + paidDate.month;
      final monthlyMemberTotals =
          monthTotalsByMember.putIfAbsent(monthKey, () => <String, double>{});
      monthlyMemberTotals.update(
        expense.paidBy,
        (current) => current + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }

    final topSpenders = spentByMember.entries
        .where((entry) => entry.value >= 0.5)
        .map((entry) => _SharedAnalyticsMemberValue(
              publicKey: entry.key,
              value: entry.value,
            ))
        .toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    final plan = settlementPlanFor(scopedGroup);
    final openBalanceTotal =
        plan.debts.fold<double>(0, (sum, debt) => sum + debt.amount);
    final largestDebt = plan.debts.isEmpty
        ? null
        : (plan.debts.toList(growable: false)
              ..sort((a, b) => b.amount.compareTo(a.amount)))
            .first;
    final balanceLeaders = plan.balances.entries
        .where((entry) => entry.value.abs() >= 0.5)
        .map((entry) => _SharedAnalyticsMemberValue(
              publicKey: entry.key,
              value: entry.value,
            ))
        .toList(growable: false)
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final balanceBubbles = [
      for (final member in group.members)
        if (member.devicePublicKey.isNotEmpty)
          _SharedAnalyticsMemberValue(
            publicKey: member.devicePublicKey,
            value: plan.balances[member.devicePublicKey] ?? 0,
          ),
    ]..sort((a, b) {
        final aIsDebt = a.value < -0.5;
        final bIsDebt = b.value < -0.5;
        if (aIsDebt != bIsDebt) return aIsDebt ? -1 : 1;
        return b.value.abs().compareTo(a.value.abs());
      });

    final maxSpent = topSpenders.isEmpty ? 0.0 : topSpenders.first.value;
    final maxBalanceAbs =
        balanceLeaders.isEmpty ? 0.0 : balanceLeaders.first.value.abs();
    final maxDebtAbs =
        balanceBubbles.where((member) => member.value < -0.5).fold<double>(
              0,
              (max, member) =>
                  member.value.abs() > max ? member.value.abs() : max,
            );
    final monthlyBuckets = monthTotalsByMember.entries
        .map((entry) {
          final year = entry.key ~/ 100;
          final month = entry.key % 100;
          final memberTotals = entry.value;
          final total = memberTotals.values.fold<double>(
            0,
            (sum, value) => sum + value,
          );
          final members = memberTotals.entries
              .where((member) => member.value >= 0.5)
              .map((member) => _SharedAnalyticsMemberValue(
                    publicKey: member.key,
                    value: member.value,
                  ))
              .toList(growable: false)
            ..sort((a, b) => b.value.compareTo(a.value));
          return _SharedAnalyticsMonthBucket(
            month: DateTime(year, month),
            total: total,
            members: members,
          );
        })
        .where((bucket) => bucket.total >= 0.5)
        .toList(growable: false)
      ..sort((a, b) => b.month.compareTo(a.month));
    final recentMonthlyBuckets = monthlyBuckets.take(6).toList(growable: false)
      ..sort((a, b) => a.month.compareTo(b.month));
    final maxMonthSpend = recentMonthlyBuckets.fold<double>(
      0,
      (max, bucket) => bucket.total > max ? bucket.total : max,
    );
    var maxWeekdaySpend = 0.0;
    var peakWeekdayIndex = 0;
    for (var i = 0; i < weekdayTotals.length; i++) {
      if (weekdayTotals[i] > maxWeekdaySpend) {
        maxWeekdaySpend = weekdayTotals[i];
        peakWeekdayIndex = i;
      }
    }

    return _SharedAnalyticsSnapshot(
      splitTotal: splitTotal,
      settlementTotal: settlementTotal,
      openBalanceTotal: openBalanceTotal,
      maxSpent: maxSpent,
      maxBalanceAbs: maxBalanceAbs,
      splitExpenseCount: splitExpenseCount,
      settlementCount: settlementCount,
      activeMemberCount: activeMembers.length,
      openDebtCount: plan.debts.length,
      linkedTransactionCount: linkedTransactionCount,
      largestExpenseAmount: largestExpenseAmount,
      largestExpenseReason: largestExpenseReason,
      largestExpensePaidBy: largestExpensePaidBy,
      largestSettlementAmount: largestSettlementAmount,
      largestSettlementFrom: largestSettlementFrom,
      largestSettlementTo: largestSettlementTo,
      largestDebtAmount: largestDebt?.amount ?? 0,
      largestDebtFrom: largestDebt?.from ?? '',
      largestDebtTo: largestDebt?.to ?? '',
      averageExpenseAmount:
          splitExpenseCount == 0 ? 0 : splitTotal / splitExpenseCount,
      maxMonthSpend: maxMonthSpend,
      maxDebtAbs: maxDebtAbs,
      maxWeekdaySpend: maxWeekdaySpend,
      peakWeekdayIndex: peakWeekdayIndex,
      topSpenders: topSpenders,
      balanceLeaders: balanceLeaders,
      balanceBubbles: balanceBubbles,
      monthlyBuckets: recentMonthlyBuckets,
      weekdayTotals: weekdayTotals,
    );
  }
}

class _SharedAnalyticsMemberValue {
  final String publicKey;
  final double value;

  const _SharedAnalyticsMemberValue({
    required this.publicKey,
    required this.value,
  });
}

class _SharedAnalyticsMonthBucket {
  final DateTime month;
  final double total;
  final List<_SharedAnalyticsMemberValue> members;

  const _SharedAnalyticsMonthBucket({
    required this.month,
    required this.total,
    required this.members,
  });
}

class _SharedAnalyticsChartCard extends StatelessWidget {
  final SharedExpenseGroup group;
  final _SharedAnalyticsSnapshot analytics;
  final String myPublicKey;
  final _SharedAnalyticsChartMode mode;
  final _SharedAnalyticsPeriod period;
  final _SharedAnalyticsBarPeriod barPeriod;
  final int barWeekOffset;
  final int barMonthOffset;
  final ValueChanged<_SharedAnalyticsChartMode> onModeChanged;
  final ValueChanged<_SharedAnalyticsPeriod> onPeriodChanged;
  final ValueChanged<_SharedAnalyticsBarPeriod> onBarPeriodChanged;
  final VoidCallback onNavigateToOlderBarPeriod;
  final VoidCallback? onNavigateToNewerBarPeriod;

  const _SharedAnalyticsChartCard({
    required this.group,
    required this.analytics,
    required this.myPublicKey,
    required this.mode,
    required this.period,
    required this.barPeriod,
    required this.barWeekOffset,
    required this.barMonthOffset,
    required this.onModeChanged,
    required this.onPeriodChanged,
    required this.onBarPeriodChanged,
    required this.onNavigateToOlderBarPeriod,
    required this.onNavigateToNewerBarPeriod,
  });

  Future<void> _openChartSelector(BuildContext context) async {
    final selected = await showModalBottomSheet<_SharedAnalyticsChartMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomPadding = MediaQuery.of(sheetContext).padding.bottom;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.background(sheetContext),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary(sheetContext)
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    sheetContext.l10nText('Select chart'),
                    style: TextStyle(
                      color: AppColors.textPrimary(sheetContext),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sheetContext.l10nText('Choose a chart.'),
                    style: TextStyle(
                      color: AppColors.textSecondary(sheetContext),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final option in _SharedAnalyticsChartMode.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SharedAnalyticsChartSheetOption(
                        title: _sharedAnalyticsChartModeLabel(
                          sheetContext,
                          option,
                        ),
                        selected: option == mode,
                        onTap: () => Navigator.of(sheetContext).pop(option),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!context.mounted || selected == null || selected == mode) {
      return;
    }
    onModeChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final chartTitle = _sharedAnalyticsChartModeLabel(context, mode);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SharedAnalyticsChartPicker(
                      label: chartTitle,
                      onTap: () => _openChartSelector(context),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode == _SharedAnalyticsChartMode.bubbles
                          ? context.l10nText(
                              'Members who owe more appear larger',
                            )
                          : context.l10nText(
                              barPeriod == _SharedAnalyticsBarPeriod.daily
                                  ? 'Weekly expenses by payer'
                                  : 'Monthly expenses by payer',
                            ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary(context),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              if (mode != _SharedAnalyticsChartMode.bubbles) ...[
                const SizedBox(width: 12),
                _SharedBarPeriodToggle(
                  period: barPeriod,
                  onChanged: onBarPeriodChanged,
                ),
              ],
            ],
          ),
          if (mode == _SharedAnalyticsChartMode.bubbles) ...[
            const SizedBox(height: 10),
            _SharedAnalyticsPeriodSelector(
              period: period,
              onChanged: onPeriodChanged,
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 14),
          if (mode == _SharedAnalyticsChartMode.bubbles)
            _SharedMemberBubbleChart(
              group: group,
              myPublicKey: myPublicKey,
              analytics: analytics,
            )
          else
            _SharedWeeklyExpenseBarChart(
              group: group,
              myPublicKey: myPublicKey,
              period: barPeriod,
              weekOffset: barWeekOffset,
              monthOffset: barMonthOffset,
              onNavigateToOlderPeriod: onNavigateToOlderBarPeriod,
              onNavigateToNewerPeriod: onNavigateToNewerBarPeriod,
            ),
        ],
      ),
    );
  }
}

class _SharedAnalyticsChartPicker extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SharedAnalyticsChartPicker({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(width: 4),
          Icon(
            AppIcons.keyboard_arrow_down_rounded,
            size: 20,
            color: AppColors.textTertiary(context),
          ),
        ],
      ),
    );
  }
}

class _SharedAnalyticsChartSheetOption extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _SharedAnalyticsChartSheetOption({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primaryLight.withValues(alpha: 0.12)
          : AppColors.surfaceColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  AppIcons.check_rounded,
                  color: AppColors.primaryLight,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharedBarPeriodToggle extends StatelessWidget {
  final _SharedAnalyticsBarPeriod period;
  final ValueChanged<_SharedAnalyticsBarPeriod> onChanged;

  const _SharedBarPeriodToggle({
    required this.period,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final toggleBg = AppColors.mutedFill(context).withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: toggleBg,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SharedBarPeriodToggleButton(
            label: 'D',
            selected: period == _SharedAnalyticsBarPeriod.daily,
            onTap: () => onChanged(_SharedAnalyticsBarPeriod.daily),
          ),
          _SharedBarPeriodToggleButton(
            label: 'M',
            selected: period == _SharedAnalyticsBarPeriod.monthly,
            onTap: () => onChanged(_SharedAnalyticsBarPeriod.monthly),
          ),
        ],
      ),
    );
  }
}

class _SharedBarPeriodToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SharedBarPeriodToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardColor(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          context.l10nText(label),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected
                ? AppColors.textPrimary(context)
                : AppColors.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

class _SharedAnalyticsPeriodSelector extends StatelessWidget {
  final _SharedAnalyticsPeriod period;
  final ValueChanged<_SharedAnalyticsPeriod> onChanged;

  const _SharedAnalyticsPeriodSelector({
    required this.period,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.mutedFill(context).withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in _SharedAnalyticsPeriod.values) ...[
              _SharedAnalyticsPeriodChip(
                label: _sharedAnalyticsPeriodShortLabel(context, option),
                selected: period == option,
                onTap: () => onChanged(option),
              ),
              if (option != _SharedAnalyticsPeriod.values.last)
                const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }
}

class _SharedAnalyticsPeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SharedAnalyticsPeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryLight.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primaryLight.withValues(alpha: 0.34)
                : Colors.transparent,
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: selected
                ? AppColors.primaryLight
                : AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _SharedMemberBubbleChart extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final _SharedAnalyticsSnapshot analytics;

  const _SharedMemberBubbleChart({
    required this.group,
    required this.myPublicKey,
    required this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    final nodes = _buildBubbleNodes();
    if (nodes.isEmpty) {
      return _SharedAnalyticsEmptyLine(
        title: context.l10nText('No balances yet'),
        subtitle: context.l10nText('Shared expenses will appear here.'),
      );
    }

    final extents = _bubbleChartExtents(nodes);
    final chartHeight = math.max(184.0, extents.height + 24);

    return SizedBox(
      height: chartHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final center = _bubbleChartCenter(
            extents: extents,
            chartWidth: constraints.maxWidth,
            chartHeight: chartHeight,
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final node in nodes)
                _SharedDebtBubble(
                  group: group,
                  myPublicKey: myPublicKey,
                  node: node,
                  center: center,
                ),
            ],
          );
        },
      ),
    );
  }

  List<_SharedDebtBubbleNode> _buildBubbleNodes() {
    final members = analytics.balanceBubbles.take(8).toList(growable: false);
    if (members.isEmpty) return const <_SharedDebtBubbleNode>[];

    final nodes = <_SharedDebtBubbleNode>[];
    final centerMember = members.first;
    nodes.add(
      _SharedDebtBubbleNode(
        member: centerMember,
        diameter: _bubbleDiameter(centerMember.value),
        offset: Offset.zero,
      ),
    );

    final offsets = _orbitOffsetsForCount(members.length - 1);
    final centerDiameter = nodes.first.diameter;
    final orbitScale = (centerDiameter / 132.0).clamp(0.82, 1.12).toDouble();

    for (var i = 1; i < members.length; i++) {
      final member = members[i];
      final diameter = _bubbleDiameter(member.value);
      final baseOffset = offsets[i - 1];
      final radiusAdjustment = (diameter - 64) / 2;
      final offset = Offset(
        (baseOffset.dx * orbitScale) +
            (baseOffset.dx == 0 ? 0 : baseOffset.dx.sign * radiusAdjustment),
        (baseOffset.dy * orbitScale) +
            (baseOffset.dy == 0 ? 0 : baseOffset.dy.sign * radiusAdjustment),
      );
      nodes.add(
        _SharedDebtBubbleNode(
          member: member,
          diameter: diameter,
          offset: offset,
        ),
      );
    }

    return nodes;
  }

  double _bubbleDiameter(double value) {
    final abs = value.abs();
    final hasDebt = analytics.maxDebtAbs > 0.5;
    if (value < -0.5) {
      final ratio =
          analytics.maxDebtAbs <= 0 ? 1.0 : (abs / analytics.maxDebtAbs);
      return 76 + (ratio.clamp(0.0, 1.0).toDouble() * 42);
    }
    if (value > 0.5) {
      final ratio = analytics.maxBalanceAbs <= 0
          ? 0.0
          : (abs / analytics.maxBalanceAbs).clamp(0.0, 1.0).toDouble();
      return hasDebt ? 48 + (ratio * 22) : 62 + (ratio * 32);
    }
    return hasDebt ? 44 : 62;
  }

  List<Offset> _orbitOffsetsForCount(int count) {
    switch (count) {
      case 0:
        return const <Offset>[];
      case 1:
        return const <Offset>[Offset(0, -76)];
      case 2:
        return const <Offset>[
          Offset(-70, -42),
          Offset(70, -42),
        ];
      case 3:
        return const <Offset>[
          Offset(-78, -10),
          Offset(0, -80),
          Offset(76, 56),
        ];
      case 4:
        return const <Offset>[
          Offset(-34, 70),
          Offset(72, 56),
          Offset(-82, -10),
          Offset(6, -84),
        ];
      case 5:
        return const <Offset>[
          Offset(-34, 72),
          Offset(74, 58),
          Offset(-84, -8),
          Offset(6, -86),
          Offset(84, -8),
        ];
      default:
        return const <Offset>[
          Offset(-34, 72),
          Offset(74, 58),
          Offset(-86, -8),
          Offset(6, -86),
          Offset(86, -8),
          Offset(-82, 58),
          Offset(86, -70),
        ];
    }
  }

  _SharedBubbleChartExtents _bubbleChartExtents(
    List<_SharedDebtBubbleNode> nodes,
  ) {
    if (nodes.isEmpty) {
      return const _SharedBubbleChartExtents(
        minX: 0,
        maxX: 0,
        minY: 0,
        maxY: 0,
      );
    }

    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final node in nodes) {
      final radius = node.diameter / 2;
      minX = math.min(minX, node.offset.dx - radius);
      maxX = math.max(maxX, node.offset.dx + radius);
      minY = math.min(minY, node.offset.dy - radius);
      maxY = math.max(maxY, node.offset.dy + radius);
    }

    return _SharedBubbleChartExtents(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );
  }

  Offset _bubbleChartCenter({
    required _SharedBubbleChartExtents extents,
    required double chartWidth,
    required double chartHeight,
  }) {
    final leftInset = math.max(0.0, (chartWidth - extents.width) / 2);
    final topInset = 12 +
        math.max(
          0.0,
          (chartHeight - extents.height - 24) / 2,
        );
    return Offset(leftInset - extents.minX, topInset - extents.minY);
  }
}

class _SharedDebtBubbleNode {
  final _SharedAnalyticsMemberValue member;
  final double diameter;
  final Offset offset;

  const _SharedDebtBubbleNode({
    required this.member,
    required this.diameter,
    required this.offset,
  });
}

class _SharedBubbleChartExtents {
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  const _SharedBubbleChartExtents({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  double get width => maxX - minX;
  double get height => maxY - minY;
}

class _SharedDebtBubble extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final _SharedDebtBubbleNode node;
  final Offset center;

  const _SharedDebtBubble({
    required this.group,
    required this.myPublicKey,
    required this.node,
    required this.center,
  });

  @override
  Widget build(BuildContext context) {
    final value = node.member.value;
    final isDebt = value < -0.5;
    final isOwed = value > 0.5;
    final color = Color(memberColorFor(group, node.member.publicKey));
    final name = group.displayNameFor(myPublicKey, node.member.publicKey);
    final amount = value.abs() < 0.5
        ? _formatCompactSharedAmount(0, context)
        : _formatSignedCompactSharedAmount(value, context);
    final status = isDebt
        ? context.l10nText('should pay')
        : isOwed
            ? context.l10nText('is owed')
            : context.l10nText('settled');
    final bubbleCenter = center + node.offset;
    final tintedFill = color.withValues(alpha: isDebt ? 0.18 : 0.12);
    final fillColor =
        Color.lerp(AppColors.mutedFill(context), tintedFill, 0.58) ??
            tintedFill;
    final borderColor = color.withValues(alpha: isDebt ? 0.46 : 0.34);

    return Positioned(
      left: bubbleCenter.dx - (node.diameter / 2),
      top: bubbleCenter.dy - (node.diameter / 2),
      width: node.diameter,
      height: node.diameter,
      child: Container(
        decoration: BoxDecoration(
          color: fillColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final diameter = constraints.maxWidth;
            final nameFont = (diameter * 0.15).clamp(8.0, 18.0).toDouble();
            final amountFont = (diameter * 0.105).clamp(7.0, 13.0).toDouble();
            final statusFont = (diameter * 0.085).clamp(7.0, 10.0).toDouble();
            final textColor = isDebt ? color : AppColors.textSecondary(context);
            return Padding(
              padding: EdgeInsets.all((diameter * 0.13).clamp(6.0, 14.0)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: diameter * 0.78,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor,
                          fontSize: nameFont,
                          fontWeight: FontWeight.w800,
                          height: 1.02,
                        ),
                      ),
                      SizedBox(height: diameter * 0.035),
                      Text(
                        amount,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.isDark(context)
                              ? AppColors.textPrimary(context)
                              : AppColors.textPrimary(context),
                          fontSize: amountFont,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      if (diameter >= 80) ...[
                        SizedBox(height: diameter * 0.035),
                        Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: statusFont,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SharedWeeklyExpenseBarChart extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final _SharedAnalyticsBarPeriod period;
  final int weekOffset;
  final int monthOffset;
  final VoidCallback onNavigateToOlderPeriod;
  final VoidCallback? onNavigateToNewerPeriod;

  const _SharedWeeklyExpenseBarChart({
    required this.group,
    required this.myPublicKey,
    required this.period,
    required this.weekOffset,
    required this.monthOffset,
    required this.onNavigateToOlderPeriod,
    required this.onNavigateToNewerPeriod,
  });

  int get _effectiveOffset {
    switch (period) {
      case _SharedAnalyticsBarPeriod.daily:
        return weekOffset;
      case _SharedAnalyticsBarPeriod.monthly:
        return monthOffset;
    }
  }

  DateTime _weekStartForOffset(int offset) {
    return _sharedAnalyticsWeekStartForOffset(offset);
  }

  DateTime _monthStartForOffset(int offset) {
    return _sharedAnalyticsMonthStartForOffset(offset);
  }

  _SharedWeeklyExpenseSeries _buildSeries(BuildContext context, int offset) {
    switch (period) {
      case _SharedAnalyticsBarPeriod.daily:
        return _buildDailySeries(context, offset);
      case _SharedAnalyticsBarPeriod.monthly:
        return _buildMonthlySeries(offset);
    }
  }

  _SharedWeeklyExpenseSeries _buildDailySeries(
    BuildContext context,
    int offset,
  ) {
    final weekStart = _weekStartForOffset(offset);
    final weekEndExclusive = weekStart.add(const Duration(days: 7));
    final memberTotalsByDay = List<Map<String, double>>.generate(
      7,
      (_) => <String, double>{},
    );

    for (final expense in group.expenses) {
      if (expense.deleted ||
          expense.kind == 'settlement' ||
          expense.amount <= 0 ||
          expense.paidBy.isEmpty) {
        continue;
      }

      final paidAt = DateTime.fromMillisecondsSinceEpoch(expense.timestamp);
      final paidDay = DateTime(paidAt.year, paidAt.month, paidAt.day);
      if (paidDay.isBefore(weekStart) || !paidDay.isBefore(weekEndExclusive)) {
        continue;
      }

      final dayIndex = paidDay.difference(weekStart).inDays.clamp(0, 6).toInt();
      memberTotalsByDay[dayIndex].update(
        expense.paidBy,
        (current) => current + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }

    final buckets = <_SharedAnalyticsDayBucket>[];
    for (var index = 0; index < memberTotalsByDay.length; index++) {
      final memberTotals = memberTotalsByDay[index];
      final members = memberTotals.entries
          .where((entry) => entry.value >= 0.5)
          .map((entry) => _SharedAnalyticsMemberValue(
                publicKey: entry.key,
                value: entry.value,
              ))
          .toList(growable: false)
        ..sort((a, b) => b.value.compareTo(a.value));
      final total = members.fold<double>(
        0,
        (sum, member) => sum + member.value,
      );
      buckets.add(
        _SharedAnalyticsDayBucket(
          day: weekStart.add(Duration(days: index)),
          total: total,
          members: members,
        ),
      );
    }

    final maxSpend = buckets.fold<double>(
      0,
      (max, bucket) => bucket.total > max ? bucket.total : max,
    );
    return _SharedWeeklyExpenseSeries(
      periodLabel: _rangeLabel(weekStart),
      labels: List<String>.generate(
        7,
        (index) => _sharedAnalyticsWeekdayLabel(context, index),
      ),
      buckets: buckets,
      maxSpend: maxSpend,
      legendMembers: _legendMembers(buckets),
    );
  }

  _SharedWeeklyExpenseSeries _buildMonthlySeries(int offset) {
    final monthStart = _monthStartForOffset(offset);
    final nextMonthStart = DateTime(monthStart.year, monthStart.month + 1, 1);
    final memberTotalsByWeek = List<Map<String, double>>.generate(
      5,
      (_) => <String, double>{},
    );

    for (final expense in group.expenses) {
      if (expense.deleted ||
          expense.kind == 'settlement' ||
          expense.amount <= 0 ||
          expense.paidBy.isEmpty) {
        continue;
      }

      final paidAt = DateTime.fromMillisecondsSinceEpoch(expense.timestamp);
      final paidDay = DateTime(paidAt.year, paidAt.month, paidAt.day);
      if (paidDay.isBefore(monthStart) || !paidDay.isBefore(nextMonthStart)) {
        continue;
      }

      final weekIndex = ((paidDay.day - 1) ~/ 7).clamp(0, 4).toInt();
      memberTotalsByWeek[weekIndex].update(
        expense.paidBy,
        (current) => current + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }

    final buckets = <_SharedAnalyticsDayBucket>[];
    for (var index = 0; index < memberTotalsByWeek.length; index++) {
      final memberTotals = memberTotalsByWeek[index];
      final members = memberTotals.entries
          .where((entry) => entry.value >= 0.5)
          .map((entry) => _SharedAnalyticsMemberValue(
                publicKey: entry.key,
                value: entry.value,
              ))
          .toList(growable: false)
        ..sort((a, b) => b.value.compareTo(a.value));
      final total = members.fold<double>(
        0,
        (sum, member) => sum + member.value,
      );
      buckets.add(
        _SharedAnalyticsDayBucket(
          day: monthStart.add(Duration(days: index * 7)),
          total: total,
          members: members,
        ),
      );
    }

    final maxSpend = buckets.fold<double>(
      0,
      (max, bucket) => bucket.total > max ? bucket.total : max,
    );
    return _SharedWeeklyExpenseSeries(
      periodLabel: _sharedAnalyticsMonthLabel(monthStart),
      labels: const ['W1', 'W2', 'W3', 'W4', 'W5'],
      buckets: buckets,
      maxSpend: maxSpend,
      legendMembers: _legendMembers(buckets),
    );
  }

  double _legendHeight(int memberCount) {
    if (memberCount <= 0) return 0;
    final rowCount = (memberCount / 2).ceil();
    return 12 + (rowCount * 22) + ((rowCount - 1) * 8);
  }

  double _pageHeight(_SharedWeeklyExpenseSeries series) {
    return 18 + 10 + 220 + _legendHeight(series.legendMembers.length);
  }

  String _rangeLabel(DateTime weekStart) {
    final end = weekStart.add(const Duration(days: 6));
    return _sharedAnalyticsDateRangeLabel(weekStart, end);
  }

  Widget _buildPage(BuildContext context, _SharedWeeklyExpenseSeries series) {
    final hasSpending = series.buckets.any((bucket) => bucket.total >= 0.5);
    final maxValue = series.maxSpend;
    final chartMax = maxValue <= 0 ? 100.0 : math.max(100.0, maxValue * 1.18);
    final interval = math.max(25.0, chartMax / 4);

    return Column(
      key: ValueKey<String>('shared-bar-${period.name}-${series.periodLabel}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          series.periodLabel,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary(context),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        if (!hasSpending)
          SizedBox(
            height: 220,
            child: Center(
              child: _SharedAnalyticsEmptyLine(
                title: context.l10nText(
                  period == _SharedAnalyticsBarPeriod.daily
                      ? 'No weekly spending'
                      : 'No monthly spending',
                ),
                subtitle: context.l10nText('Shared expenses will appear here.'),
              ),
            ),
          )
        else
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                minY: 0,
                maxY: chartMax,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color:
                        AppColors.borderColor(context).withValues(alpha: 0.65),
                    strokeWidth: 0.8,
                    dashArray: const [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= series.buckets.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 8,
                          child: Text(
                            series.labels[index],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var index = 0; index < series.buckets.length; index++)
                    _barGroupFor(
                      context,
                      index: index,
                      bucket: series.buckets[index],
                    ),
                ],
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipRoundedRadius: 12,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (group) => AppColors.cardColor(context),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final bucket = series.buckets[group.x];
                      final label = series.labels[group.x];
                      return BarTooltipItem(
                        '$label\n${_formatEtb(bucket.total, context)}',
                        TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        if (series.legendMembers.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SharedMonthlyMemberLegend(
            group: group,
            myPublicKey: myPublicKey,
            members: series.legendMembers,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final offset = _effectiveOffset;
    final currentSeries = _buildSeries(context, offset);
    final previousSeries = _buildSeries(context, offset - 1);
    final hasNewerPeriod = offset < 0;
    final nextSeries =
        hasNewerPeriod ? _buildSeries(context, offset + 1) : currentSeries;
    final viewportHeight = math.max(
      _pageHeight(previousSeries),
      math.max(_pageHeight(currentSeries), _pageHeight(nextSeries)),
    );

    return _SharedAnalyticsSwipePager(
      height: viewportHeight,
      recenterKey: Object.hash(
        period,
        offset,
        group.expenses.length,
        group.activity.length,
      ),
      onPrevious: onNavigateToOlderPeriod,
      onNext: hasNewerPeriod ? onNavigateToNewerPeriod : null,
      itemBuilder: (context, index) {
        final series = index == 0
            ? previousSeries
            : index == 1
                ? currentSeries
                : nextSeries;
        return _buildPage(context, series);
      },
    );
  }

  BarChartGroupData _barGroupFor(
    BuildContext context, {
    required int index,
    required _SharedAnalyticsDayBucket bucket,
  }) {
    var cumulative = 0.0;
    final stackItems = <BarChartRodStackItem>[];
    for (final member in bucket.members) {
      final from = cumulative;
      cumulative += member.value;
      stackItems.add(
        BarChartRodStackItem(
          from,
          cumulative,
          Color(memberColorFor(group, member.publicKey)),
        ),
      );
    }

    return BarChartGroupData(
      x: index,
      barRods: [
        BarChartRodData(
          toY: bucket.total,
          width: 24,
          borderRadius: BorderRadius.circular(7),
          color: AppColors.primaryLight.withValues(alpha: 0.18),
          rodStackItems: stackItems,
        ),
      ],
    );
  }

  List<_SharedAnalyticsMemberValue> _legendMembers(
    List<_SharedAnalyticsDayBucket> buckets,
  ) {
    final totals = <String, double>{};
    for (final bucket in buckets) {
      for (final member in bucket.members) {
        totals.update(
          member.publicKey,
          (current) => current + member.value,
          ifAbsent: () => member.value,
        );
      }
    }
    final members = totals.entries
        .map((entry) => _SharedAnalyticsMemberValue(
              publicKey: entry.key,
              value: entry.value,
            ))
        .toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    return members.take(6).toList(growable: false);
  }
}

class _SharedAnalyticsDayBucket {
  final DateTime day;
  final double total;
  final List<_SharedAnalyticsMemberValue> members;

  const _SharedAnalyticsDayBucket({
    required this.day,
    required this.total,
    required this.members,
  });
}

class _SharedWeeklyExpenseSeries {
  final String periodLabel;
  final List<String> labels;
  final List<_SharedAnalyticsDayBucket> buckets;
  final double maxSpend;
  final List<_SharedAnalyticsMemberValue> legendMembers;

  const _SharedWeeklyExpenseSeries({
    required this.periodLabel,
    required this.labels,
    required this.buckets,
    required this.maxSpend,
    required this.legendMembers,
  });
}

class _SharedAnalyticsSwipePager extends StatefulWidget {
  final double height;
  final Object recenterKey;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final IndexedWidgetBuilder itemBuilder;

  const _SharedAnalyticsSwipePager({
    required this.height,
    required this.recenterKey,
    this.onPrevious,
    this.onNext,
    required this.itemBuilder,
  });

  @override
  State<_SharedAnalyticsSwipePager> createState() =>
      _SharedAnalyticsSwipePagerState();
}

class _SharedAnalyticsSwipePagerState
    extends State<_SharedAnalyticsSwipePager> {
  late final PageController _pageController;
  bool _isRecenteringPage = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
  }

  @override
  void didUpdateWidget(covariant _SharedAnalyticsSwipePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recenterKey != widget.recenterKey &&
        _pageController.hasClients &&
        (_pageController.page?.round() ?? 1) != 1) {
      _pageController.jumpToPage(1);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _commitPageChange(int page) {
    if (_isRecenteringPage || page == 1) return;

    setState(() => _isRecenteringPage = true);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(1);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _isRecenteringPage = false);
    });

    if (page == 0) {
      widget.onPrevious?.call();
    } else {
      widget.onNext?.call();
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_isRecenteringPage || notification.depth != 0) return false;
    if (notification is! ScrollEndNotification) return false;

    final metrics = notification.metrics;
    if (metrics is! PageMetrics) return false;

    final page = metrics.page?.round() ?? 1;
    _commitPageChange(page);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: widget.height,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: PageView.builder(
            controller: _pageController,
            itemCount: 3,
            physics: const PageScrollPhysics(),
            itemBuilder: widget.itemBuilder,
          ),
        ),
      ),
    );
  }
}

class _SharedMonthlyMemberLegend extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final List<_SharedAnalyticsMemberValue> members;

  const _SharedMonthlyMemberLegend({
    required this.group,
    required this.myPublicKey,
    required this.members,
  });

  @override
  Widget build(BuildContext context) {
    final columns = <Widget>[];
    for (var index = 0; index < members.length; index += 2) {
      final top = members[index];
      final bottom = index + 1 < members.length ? members[index + 1] : null;
      columns.add(
        Padding(
          padding: EdgeInsets.only(right: index + 2 < members.length ? 14 : 0),
          child: SizedBox(
            width: 186,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SharedMonthlyMemberLegendItem(
                  group: group,
                  myPublicKey: myPublicKey,
                  member: top,
                ),
                if (bottom != null) ...[
                  const SizedBox(height: 10),
                  _SharedMonthlyMemberLegendItem(
                    group: group,
                    myPublicKey: myPublicKey,
                    member: bottom,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(right: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columns,
      ),
    );
  }
}

class _SharedMonthlyMemberLegendItem extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final _SharedAnalyticsMemberValue member;

  const _SharedMonthlyMemberLegendItem({
    required this.group,
    required this.myPublicKey,
    required this.member,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Color(memberColorFor(group, member.publicKey)),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            group.displayNameFor(myPublicKey, member.publicKey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _formatEtb(member.value, context),
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _SharedSpendingByDayPanel extends StatelessWidget {
  final _SharedAnalyticsSnapshot analytics;
  final _SharedAnalyticsPeriod period;
  final String? periodLabelOverride;

  const _SharedSpendingByDayPanel({
    required this.analytics,
    required this.period,
    this.periodLabelOverride,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = analytics.maxWeekdaySpend;
    final periodLabel =
        periodLabelOverride ?? _sharedAnalyticsPeriodLongLabel(context, period);
    final peakLabel = _sharedAnalyticsWeekdayLabel(
      context,
      analytics.peakWeekdayIndex,
    );
    final infoText = maxValue > 0
        ? '${context.l10nText('Peak')}: $peakLabel'
        : context.l10nText('No shared spending in this range.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                context.l10nText('Spending by Day'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.mutedFill(context).withValues(
                    alpha: AppColors.isDark(context) ? 0.38 : 0.7,
                  ),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: AppColors.borderColor(context)),
                ),
                child: Text(
                  periodLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            infoText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 14),
          if (maxValue <= 0)
            SizedBox(
              height: 84,
              child: Center(
                child: Text(
                  context.l10nText('Shared expenses will appear here.'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                ),
              ),
            )
          else
            SizedBox(
              height: 84,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (index) {
                  final value = analytics.weekdayTotals[index];
                  final ratio = maxValue > 0
                      ? (value / maxValue).clamp(0.0, 1.0).toDouble()
                      : 0.0;
                  final barHeight = 10 + (ratio * 52);
                  final isPeak =
                      index == analytics.peakWeekdayIndex && maxValue > 0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: Duration(
                              milliseconds: 260 + (index * 28),
                            ),
                            curve: Curves.easeOutCubic,
                            height: barHeight,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: isPeak
                                    ? const [
                                        Color(0xFF4ADE80),
                                        Color(0xFF22C55E),
                                      ]
                                    : const [
                                        Color(0xFF7C83EA),
                                        Color(0xFF5B60D9),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(7),
                              boxShadow: [
                                BoxShadow(
                                  color: (isPeak
                                          ? const Color(0xFF22C55E)
                                          : const Color(0xFF5B60D9))
                                      .withValues(alpha: 0.18),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _sharedAnalyticsWeekdayLabel(context, index),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: isPeak
                                          ? AppColors.textPrimary(context)
                                          : AppColors.textSecondary(context),
                                      fontWeight: isPeak
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _SharedMoneyFlowSection extends StatelessWidget {
  final SharedExpenseGroup group;
  final _SharedAnalyticsSnapshot analytics;
  final String myPublicKey;

  const _SharedMoneyFlowSection({
    required this.group,
    required this.analytics,
    required this.myPublicKey,
  });

  @override
  Widget build(BuildContext context) {
    final largestExpenseName = analytics.largestExpenseReason.trim().isEmpty
        ? context.l10nText('Largest expense')
        : analytics.largestExpenseReason.trim();
    final largestExpensePayer = analytics.largestExpensePaidBy.trim().isEmpty
        ? context.l10nText('Unknown')
        : group.displayNameFor(myPublicKey, analytics.largestExpensePaidBy);
    final largestDebtLabel = analytics.largestDebtAmount <= 0
        ? context.l10nText('No open debt')
        : '${group.displayNameFor(myPublicKey, analytics.largestDebtFrom)} → ${group.displayNameFor(myPublicKey, analytics.largestDebtTo)}';
    final largestSettlementLabel = analytics.largestSettlementAmount <= 0
        ? context.l10nText('No settlements yet')
        : '${group.displayNameFor(myPublicKey, analytics.largestSettlementFrom)} → ${group.displayNameFor(myPublicKey, analytics.largestSettlementTo)}';

    return _SharedAnalyticsPanel(
      title: context.l10nText('Money flow'),
      subtitle: context.l10nText('Largest money movements in this group'),
      emptyTitle: context.l10nText('No money flow yet'),
      emptySubtitle: context.l10nText('Shared expenses will appear here.'),
      children: [
        _SharedMoneyFlowRow(
          label: context.l10nText('Largest expense'),
          value: analytics.largestExpenseAmount <= 0
              ? _formatEtb(0, context)
              : _formatEtb(analytics.largestExpenseAmount, context),
          subtitle: analytics.largestExpenseAmount <= 0
              ? context.l10nText('No expenses yet')
              : '$largestExpenseName · $largestExpensePayer',
          color: AppColors.primaryLight,
        ),
        _SharedMoneyFlowRow(
          label: context.l10nText('Largest debt'),
          value: _formatEtb(analytics.largestDebtAmount, context),
          subtitle: largestDebtLabel,
          color: AppColors.red,
        ),
        _SharedMoneyFlowRow(
          label: context.l10nText('Largest settlement'),
          value: _formatEtb(analytics.largestSettlementAmount, context),
          subtitle: largestSettlementLabel,
          color: AppColors.incomeSuccess,
        ),
        _SharedMoneyFlowRow(
          label: context.l10nText('Average split'),
          value: _formatEtb(analytics.averageExpenseAmount, context),
          subtitle:
              '${analytics.splitExpenseCount} ${context.l10nText(analytics.splitExpenseCount == 1 ? 'expense' : 'expenses')}',
          color: AppColors.amber,
        ),
      ],
    );
  }
}

class _SharedMoneyFlowRow extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color color;

  const _SharedMoneyFlowRow({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _SharedAnalyticsSummaryGrid extends StatelessWidget {
  final SharedExpenseGroup group;
  final _SharedAnalyticsSnapshot analytics;
  final int pendingApprovalCount;

  const _SharedAnalyticsSummaryGrid({
    required this.group,
    required this.analytics,
    required this.pendingApprovalCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SharedSectionHeader(label: context.l10nText('GROUP SNAPSHOT')),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SharedMetricTile(
                icon: AppIcons.receipt_long_rounded,
                accentColor: AppColors.primaryLight,
                label: context.l10nText('Split volume'),
                value: _formatEtb(analytics.splitTotal, context),
                subtitle:
                    '${analytics.splitExpenseCount} ${context.l10nText(analytics.splitExpenseCount == 1 ? 'expense' : 'expenses')}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SharedMetricTile(
                icon: AppIcons.group_outlined,
                accentColor: AppColors.incomeSuccess,
                label: context.l10nText('Active members'),
                value: '${analytics.activeMemberCount}/${group.memberCount}',
                subtitle: context.l10nText('participated in splits'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SharedMetricTile(
                icon: AppIcons.account_balance_rounded,
                accentColor: analytics.openBalanceTotal > 0.5
                    ? AppColors.red
                    : AppColors.incomeSuccess,
                label: context.l10nText('Open balances'),
                value: _formatEtb(analytics.openBalanceTotal, context),
                subtitle: analytics.openDebtCount == 0
                    ? context.l10nText('All settled')
                    : '${analytics.openDebtCount} ${context.l10nText(analytics.openDebtCount == 1 ? 'debt' : 'debts')}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SharedMetricTile(
                icon: AppIcons.check_circle_rounded,
                accentColor: AppColors.amber,
                label: context.l10nText('Linked splits'),
                value: '${analytics.linkedTransactionCount}',
                subtitle:
                    '$pendingApprovalCount ${context.l10nText('approvals')}',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SharedAnalyticsPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emptyTitle;
  final String emptySubtitle;
  final List<Widget> children;

  const _SharedAnalyticsPanel({
    required this.title,
    required this.subtitle,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          if (children.isEmpty)
            _SharedAnalyticsEmptyLine(
              title: emptyTitle,
              subtitle: emptySubtitle,
            )
          else
            ...children,
        ],
      ),
    );
  }
}

class _SharedAnalyticsMemberBar extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final String publicKey;
  final double value;
  final double maxValue;
  final String trailing;

  const _SharedAnalyticsMemberBar({
    required this.group,
    required this.myPublicKey,
    required this.publicKey,
    required this.value,
    required this.maxValue,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final barColor = Color(memberColorFor(group, publicKey));
    final percent =
        maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0).toDouble();
    final name = group.displayNameFor(myPublicKey, publicKey);

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                trailing,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary(context),
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 7,
              backgroundColor: AppColors.surfaceColor(context),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedAnalyticsEmptyLine extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SharedAnalyticsEmptyLine({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary(context),
                ),
          ),
        ],
      ),
    );
  }
}

class _SharedSectionHeader extends StatelessWidget {
  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SharedSectionHeader({
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textTertiary(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryLight,
              textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _SharedDetailEmptyBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SharedDetailEmptyBlock({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.borderColor(context)),
          bottom: BorderSide(color: AppColors.borderColor(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryLight, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary(context),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedSettleEmptyRow extends StatelessWidget {
  const _SharedSettleEmptyRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderColor(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10nText('No debts'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedMetricTile extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String label;
  final String value;
  final String subtitle;

  const _SharedMetricTile({
    required this.icon,
    required this.accentColor,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textTertiary(context),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _SharedGroupCard extends StatefulWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final bool isRefreshing;
  final List<SharedExpenseMember> pendingMembers;
  final String Function(String value) shortKey;
  final String? approvingMemberKey;
  final VoidCallback onOpen;
  final VoidCallback onCopyInvite;
  final ValueChanged<SharedExpenseMember> onApproveMember;
  final VoidCallback onCancelJoinRequest;

  const _SharedGroupCard({
    required this.group,
    required this.myPublicKey,
    required this.isRefreshing,
    required this.pendingMembers,
    required this.shortKey,
    required this.approvingMemberKey,
    required this.onOpen,
    required this.onCopyInvite,
    required this.onApproveMember,
    required this.onCancelJoinRequest,
  });

  @override
  State<_SharedGroupCard> createState() => _SharedGroupCardState();
}

class _SharedGroupCardState extends State<_SharedGroupCard> {
  bool _cancelArmed = false;
  Timer? _cancelDisarmTimer;

  // Convenience aliases so existing references inside build() stay short.
  SharedExpenseGroup get group => widget.group;
  String get myPublicKey => widget.myPublicKey;
  bool get isRefreshing => widget.isRefreshing;
  List<SharedExpenseMember> get pendingMembers => widget.pendingMembers;
  String Function(String value) get shortKey => widget.shortKey;
  String? get approvingMemberKey => widget.approvingMemberKey;
  VoidCallback get onOpen => widget.onOpen;
  VoidCallback get onCopyInvite => widget.onCopyInvite;
  ValueChanged<SharedExpenseMember> get onApproveMember =>
      widget.onApproveMember;

  @override
  void dispose() {
    _cancelDisarmTimer?.cancel();
    super.dispose();
  }

  void _onCancelTap() {
    if (!_cancelArmed) {
      setState(() => _cancelArmed = true);
      _cancelDisarmTimer?.cancel();
      _cancelDisarmTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _cancelArmed = false);
      });
      return;
    }
    widget.onCancelJoinRequest();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReadyRefreshing =
        isRefreshing && group.status == SharedExpenseGroupStatus.ready;
    final statusLabel = isReadyRefreshing
        ? context.l10nText('Refreshing')
        : switch (group.status) {
            SharedExpenseGroupStatus.ready => context.l10nText('Synced'),
            SharedExpenseGroupStatus.pendingApproval =>
              context.l10nText('Pending approval'),
            SharedExpenseGroupStatus.localOnly =>
              context.l10nText('Local only'),
          };
    final statusColor = isReadyRefreshing
        ? AppColors.blue
        : switch (group.status) {
            SharedExpenseGroupStatus.ready => AppColors.incomeSuccess,
            SharedExpenseGroupStatus.pendingApproval => AppColors.amber,
            SharedExpenseGroupStatus.localOnly =>
              AppColors.textTertiary(context),
          };

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderColor(context)),
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
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          group.memberCount == 1
                              ? context.l10nText('1 member')
                              : '${group.memberCount} ${context.l10nText('members')}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed:
                            group.status == SharedExpenseGroupStatus.localOnly
                                ? null
                                : onCopyInvite,
                        icon: const Icon(AppIcons.copy, size: 17),
                        tooltip: context.l10nText('Copy code'),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.cardColor(context),
                          foregroundColor: AppColors.textSecondary(context),
                          disabledForegroundColor:
                              AppColors.textTertiary(context),
                          side: BorderSide(
                            color: AppColors.borderColor(context),
                          ),
                          minimumSize: const Size(36, 36),
                          fixedSize: const Size(36, 36),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(label: statusLabel, color: statusColor),
                    ],
                  ),
                ],
              ),
              if (group.status == SharedExpenseGroupStatus.ready) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _GroupCardBalanceLine(
                        group: group,
                        myPublicKey: myPublicKey,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      context
                          .l10n('shared.updatedTime', 'Updated {time}')
                          .replaceFirst(
                            '{time}',
                            _localizedShortRelative(
                              context,
                              _lastGroupEventTimestamp(group),
                            ),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              if (group.status == SharedExpenseGroupStatus.pendingApproval) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _onCancelTap,
                      icon: Icon(
                        AppIcons.close,
                        size: 17,
                        color: _cancelArmed
                            ? Colors.white
                            : const Color(0xFFBE123C),
                      ),
                      label: Text(
                        _cancelArmed
                            ? context.l10nText('Tap again to cancel')
                            : context.l10nText('Cancel request'),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _cancelArmed
                            ? Colors.white
                            : const Color(0xFFBE123C),
                        backgroundColor:
                            _cancelArmed ? const Color(0xFFBE123C) : null,
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        side: BorderSide(
                          color: _cancelArmed
                              ? const Color(0xFFBE123C)
                              : const Color(0xFFBE123C).withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (group.status == SharedExpenseGroupStatus.pendingApproval) ...[
                const SizedBox(height: 16),
                _InlineNote(
                  icon: AppIcons.lock_outline_rounded,
                  text: context.l10nText('Waiting for approval'),
                  color: AppColors.amber,
                ),
              ],
              if (pendingMembers.isNotEmpty) ...[
                const SizedBox(height: 18),
                Divider(color: AppColors.borderColor(context), height: 1),
                const SizedBox(height: 14),
                Text(
                  context.l10nText('Approval needed'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                for (final member in pendingMembers)
                  _PendingMemberRow(
                    member: member,
                    displayName: group.displayNameFor(
                      myPublicKey,
                      member.devicePublicKey,
                    ),
                    shortKey: shortKey,
                    isApproving: approvingMemberKey == member.devicePublicKey,
                    onApprove: () => onApproveMember(member),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InlineNote({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

class _PendingMemberRow extends StatelessWidget {
  final SharedExpenseMember member;
  final String displayName;
  final String Function(String value) shortKey;
  final bool isApproving;
  final VoidCallback onApprove;

  const _PendingMemberRow({
    required this.member,
    required this.displayName,
    required this.shortKey,
    required this.isApproving,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              AppIcons.person_outline,
              size: 18,
              color: AppColors.primaryLight,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Builder(builder: (_) {
              final shortPk = shortKey(member.devicePublicKey);
              final hasName = displayName.trim().isNotEmpty &&
                  displayName.trim() != shortPk;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasName ? displayName : shortPk,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (hasName)
                    Text(
                      shortPk,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              );
            }),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: isApproving ? null : onApprove,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              foregroundColor: AppColors.white,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: isApproving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : Text(context.l10nText('Approve')),
          ),
        ],
      ),
    );
  }
}

class _NudgeTarget {
  final String publicKey;
  final double amount;

  const _NudgeTarget({
    required this.publicKey,
    required this.amount,
  });
}

class _NudgePickerSheet extends StatefulWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final List<_NudgeTarget> targets;

  const _NudgePickerSheet({
    required this.group,
    required this.myPublicKey,
    required this.targets,
  });

  @override
  State<_NudgePickerSheet> createState() => _NudgePickerSheetState();
}

class _NudgePickerSheetState extends State<_NudgePickerSheet> {
  late Set<String> _selectedPks;

  @override
  void initState() {
    super.initState();
    _selectedPks = widget.targets.map((target) => target.publicKey).toSet();
  }

  List<_NudgeTarget> get _selectedTargets => widget.targets
      .where((target) => _selectedPks.contains(target.publicKey))
      .toList(growable: false);

  double get _selectedAmount => _selectedTargets.fold<double>(
        0,
        (sum, target) => sum + target.amount,
      );

  void _toggle(String publicKey) {
    setState(() {
      if (_selectedPks.contains(publicKey)) {
        _selectedPks.remove(publicKey);
      } else {
        _selectedPks.add(publicKey);
      }
    });
  }

  void _submit() {
    final selected = _selectedTargets;
    if (selected.isEmpty) return;
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    return _IosModalShell(
      title: context.l10nText('Send a nudge'),
      footer: [
        _IosFormSubmit(
          label: _selectedPks.length == 1
              ? context.l10nText('Send nudge')
              : context.l10nText('Send nudges'),
          icon: Icons.notifications_active_outlined,
          enabled: _selectedPks.isNotEmpty,
          onTap: _submit,
          topPadding: 0,
        ),
      ],
      children: [
        _IosFormGroup(
          label: context.l10nText('People who owe you'),
          labelTrailing: Text(
            _formatEtb(_selectedAmount, context),
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Column(
            children: [
              for (final target in widget.targets) ...[
                _NudgeTargetRow(
                  group: widget.group,
                  myPublicKey: widget.myPublicKey,
                  target: target,
                  selected: _selectedPks.contains(target.publicKey),
                  onTap: () => _toggle(target.publicKey),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NudgeTargetRow extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final _NudgeTarget target;
  final bool selected;
  final VoidCallback onTap;

  const _NudgeTargetRow({
    required this.group,
    required this.myPublicKey,
    required this.target,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = group.displayNameFor(myPublicKey, target.publicKey);
    final color = Color(memberColorFor(group, target.publicKey));
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final borderColor = AppColors.borderColor(context);
    final cardColor = AppColors.cardColor(context);
    final initial = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryLight.withValues(alpha: 0.08)
                : cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primaryLight : borderColor,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatEtb(target.amount, context),
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                activeColor: AppColors.primaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupFormResult {
  final String groupName;
  final String displayName;
  final SharedPaymentAddress paymentAddress;

  const _GroupFormResult({
    required this.groupName,
    required this.displayName,
    required this.paymentAddress,
  });
}

class _GroupFormSheet extends StatefulWidget {
  final String title;
  final String primaryLabel;
  final String groupLabel;
  final String groupHint;
  final String nameLabel;
  final String nameHint;
  final String initialName;
  final List<AccountSummary> paymentAccounts;
  final SharedPaymentAddress initialPaymentAddress;

  const _GroupFormSheet({
    required this.title,
    required this.primaryLabel,
    required this.groupLabel,
    required this.groupHint,
    required this.nameLabel,
    required this.nameHint,
    required this.initialName,
    required this.paymentAccounts,
    required this.initialPaymentAddress,
  });

  @override
  State<_GroupFormSheet> createState() => _GroupFormSheetState();
}

class _GroupFormSheetState extends State<_GroupFormSheet> {
  late final TextEditingController _groupController;
  late final TextEditingController _nameController;
  late SharedPaymentAddress _paymentAddress;
  bool _hasTriedSubmit = false;

  @override
  void initState() {
    super.initState();
    _groupController = TextEditingController();
    _nameController = TextEditingController(text: widget.initialName);
    _paymentAddress = widget.initialPaymentAddress;
  }

  @override
  void dispose() {
    _groupController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final groupName = _groupController.text.trim();
    final displayName = _nameController.text.trim();
    setState(() => _hasTriedSubmit = true);
    if (groupName.isEmpty || displayName.isEmpty) return;

    Navigator.of(context).pop(
      _GroupFormResult(
        groupName: groupName,
        displayName: displayName,
        paymentAddress: _paymentAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final bottomSafeArea = mediaQuery.viewPadding.bottom;
    final keyboardLiftBuffer = keyboardInset > 0 ? 28.0 : 0.0;
    final actionBottomGap = keyboardInset > 0
        ? 4.0
        : (mediaQuery.size.height * 0.014).clamp(8.0, 14.0);
    final actionTopGap = keyboardInset > 0 ? 12.0 : 20.0;
    final formBottomPadding = keyboardInset > 0 ? 8.0 : 4.0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset + keyboardLiftBuffer),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: mediaQuery.size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: AppColors.background(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxHeight = constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : mediaQuery.size.height * 0.9;

              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          20,
                          18,
                          20,
                          formBottomPadding,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 22),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style:
                                        theme.textTheme.headlineSmall?.copyWith(
                                      color: AppColors.textPrimary(context),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(AppIcons.close_rounded),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        AppColors.cardColor(context),
                                    foregroundColor:
                                        AppColors.textPrimary(context),
                                    minimumSize: const Size(48, 48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            _SheetTextField(
                              controller: _groupController,
                              label: widget.groupLabel,
                              hint: widget.groupHint,
                              textInputAction: TextInputAction.next,
                              showError: _hasTriedSubmit &&
                                  _groupController.text.trim().isEmpty,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 20),
                            _SheetTextField(
                              controller: _nameController,
                              label: widget.nameLabel,
                              hint: widget.nameHint,
                              textInputAction: TextInputAction.done,
                              showError: _hasTriedSubmit &&
                                  _nameController.text.trim().isEmpty,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 22),
                            _PaymentAddressSelector(
                              label: context.l10nText('PAYMENT ACCOUNT'),
                              accounts: widget.paymentAccounts,
                              selected: _paymentAddress,
                              onChanged: (address) {
                                setState(() => _paymentAddress = address);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: actionTopGap),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        bottomSafeArea + actionBottomGap,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _submit,
                          iconAlignment: IconAlignment.end,
                          icon: const Icon(
                            AppIcons.check_rounded,
                            size: 20,
                          ),
                          label: Text(widget.primaryLabel),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryLight,
                            foregroundColor: AppColors.white,
                            minimumSize: const Size(0, 58),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputAction textInputAction;
  final bool showError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  const _SheetTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.textInputAction,
    required this.showError,
    required this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor =
        showError ? AppColors.red : AppColors.borderColor(context);
    final focusedBorderColor =
        showError ? AppColors.red : AppColors.primaryLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.trim().isNotEmpty) ...[
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: controller,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.textTertiary(context),
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: AppColors.cardColor(context),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: focusedBorderColor,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.red,
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.red,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentAddressSelector extends StatelessWidget {
  final String label;
  final List<AccountSummary> accounts;
  final SharedPaymentAddress selected;
  final ValueChanged<SharedPaymentAddress> onChanged;

  const _PaymentAddressSelector({
    required this.label,
    required this.accounts,
    required this.selected,
    required this.onChanged,
  });

  SharedPaymentAddress _addressFor(AccountSummary account) {
    return SharedPaymentAddress(
      bankId: account.bankId,
      accountNumber: account.accountNumber,
      accountHolderName: account.accountHolderName,
    );
  }

  bool _isSelected(AccountSummary account) {
    return account.bankId == selected.bankId &&
        account.accountNumber == selected.accountNumber;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: accounts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final account = accounts[index];
              final address = _addressFor(account);
              return _PaymentAddressChip(
                bank: _sharedExpenseBankFor(account.bankId),
                title: _sharedPaymentBankLabel(context, account.bankId),
                selected: _isSelected(account),
                onTap: () => onChanged(address),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PaymentAddressChip extends StatelessWidget {
  final Bank bank;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentAddressChip({
    required this.bank,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor =
        selected ? AppColors.primaryLight : AppColors.borderColor(context);
    final textColor =
        selected ? AppColors.primaryLight : AppColors.textSecondary(context);

    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 82,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 54,
                height: 54,
                padding: EdgeInsets.all(selected ? 3 : 4),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryLight.withValues(alpha: 0.08)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: borderColor,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: ClipOval(
                  child: bank.image.isEmpty
                      ? _PaymentBankFallback()
                      : Image.asset(
                          bank.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _PaymentBankFallback(),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: textColor,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Add-expense sheet (minimal — amount + reason, equal split among all members).
// ============================================================================

abstract class _ExpenseSheetResult {
  const _ExpenseSheetResult();
}

class _ExpenseSheetSave extends _ExpenseSheetResult {
  final double amount;
  final String reason;
  final String paidBy;
  final List<String> splitAmong;
  final int timestamp;
  final String? linkedTxRef;
  const _ExpenseSheetSave({
    required this.amount,
    required this.reason,
    required this.paidBy,
    required this.splitAmong,
    required this.timestamp,
    this.linkedTxRef,
  });
}

class _ExpenseSheetDelete extends _ExpenseSheetResult {
  const _ExpenseSheetDelete();
}

typedef _ExpenseSheetSubmit = Future<bool> Function(
  _ExpenseSheetResult result,
);

class _ExpenseDraftSheet extends StatefulWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final SharedExpense? editing;
  final double? initialAmount;
  final String? initialReason;
  final String? initialLinkedTxRef;
  final String? submittingLabel;
  final _ExpenseSheetSubmit? onSubmit;

  const _ExpenseDraftSheet({
    required this.group,
    required this.myPublicKey,
    this.editing,
    this.initialAmount,
    this.initialReason,
    this.initialLinkedTxRef,
    this.submittingLabel,
    this.onSubmit,
  });

  @override
  State<_ExpenseDraftSheet> createState() => _ExpenseDraftSheetState();
}

class _ExpenseDraftSheetState extends State<_ExpenseDraftSheet> {
  late final TextEditingController _amountCtrl = TextEditingController(
    text: _formatExpenseAmountInput(
      widget.editing?.amount ?? widget.initialAmount,
    ),
  );
  late final TextEditingController _reasonCtrl = TextEditingController(
    text: widget.editing?.reason ?? widget.initialReason ?? '',
  );
  late final FocusNode _amountFocusNode = FocusNode();
  late final FocusNode _reasonFocusNode = FocusNode();
  late String _paidBy = widget.editing?.paidBy ?? widget.myPublicKey;
  late Set<String> _split = widget.editing != null
      ? widget.editing!.splitAmong.toSet()
      : _memberKeysForGroup(widget.group);
  late DateTime _paidAt = DateTime.fromMillisecondsSinceEpoch(
    widget.editing?.timestamp ?? DateTime.now().millisecondsSinceEpoch,
  );
  late String? _linkedTxRef =
      widget.editing?.linkedTxRef ?? widget.initialLinkedTxRef;
  bool _deleteArmed = false;
  bool _isSubmitting = false;
  String? _submittingLabel;
  Timer? _deleteDisarmTimer;

  bool get _isEditing => widget.editing != null;
  bool get _startsFromLinkedTransaction =>
      widget.editing == null && widget.initialLinkedTxRef != null;
  bool get _requiresLinkedTransaction =>
      widget.editing == null && widget.initialLinkedTxRef != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_startsFromLinkedTransaction) {
        _focusReasonField(selectAll: true);
      } else {
        _amountFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    _amountFocusNode.dispose();
    _reasonFocusNode.dispose();
    _deleteDisarmTimer?.cancel();
    super.dispose();
  }

  void _focusReasonField({bool selectAll = false}) {
    _reasonFocusNode.requestFocus();
    final text = _reasonCtrl.text;
    _reasonCtrl.selection = selectAll
        ? TextSelection(baseOffset: 0, extentOffset: text.length)
        : TextSelection.collapsed(offset: text.length);
  }

  Future<void> _submitResult(
    _ExpenseSheetResult result, {
    required String submittingLabel,
  }) async {
    if (_isSubmitting) return;
    final submit = widget.onSubmit;
    if (submit == null) {
      Navigator.of(context).pop(result);
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSubmitting = true;
      _submittingLabel = submittingLabel;
    });

    var shouldClose = false;
    try {
      shouldClose = await submit(result);
    } catch (_) {
      shouldClose = false;
    }
    if (!mounted) return;
    if (shouldClose) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      _isSubmitting = false;
      _submittingLabel = null;
    });
  }

  void _submit() {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final reason = _reasonCtrl.text.trim();
    if (_isSubmitting || amount <= 0 || reason.isEmpty || _split.isEmpty) {
      return;
    }
    unawaited(
      _submitResult(
        _ExpenseSheetSave(
          amount: amount,
          reason: reason,
          paidBy: _paidBy,
          splitAmong: _split.toList(),
          timestamp: _paidAt.millisecondsSinceEpoch,
          linkedTxRef: _linkedTxRef,
        ),
        submittingLabel:
            widget.submittingLabel ?? (_isEditing ? 'Saving' : 'Adding'),
      ),
    );
  }

  Future<void> _pickPaidAt() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _paidAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _paidAt.hour,
        _paidAt.minute,
      );
    });
  }

  Transaction? _linkedTransaction(TransactionProvider provider) {
    return provider.transactionByReference(_linkedTxRef);
  }

  Future<void> _pickLinkedTransaction() async {
    final provider = context.read<TransactionProvider>();
    final currentRef = _linkedTxRef;
    final linkedRefs = provider.sharedExpenseLinkedRefs
        .where((ref) => ref != currentRef)
        .toSet();
    final candidates = provider.allTransactions
        .where((transaction) =>
            transaction.reference.trim().isNotEmpty &&
            !linkedRefs.contains(transaction.reference))
        .toList(growable: false)
      ..sort((a, b) {
        final aTime = _timestampFromTransaction(a) ?? 0;
        final bTime = _timestampFromTransaction(b) ?? 0;
        return bTime.compareTo(aTime);
      });

    final selected = await showModalBottomSheet<Transaction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _LinkedTransactionPickerSheet(
        transactions: candidates,
        selectedRef: currentRef,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _linkedTxRef = selected.reference;
      final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
      if (amount <= 0) {
        _amountCtrl.text = _formatExpenseAmountInput(selected.amount.abs());
      }
      if (_reasonCtrl.text.trim().isEmpty) {
        _reasonCtrl.text = _splitReasonForTransaction(selected);
      }
    });
    _focusReasonField();
  }

  void _clearLinkedTransaction() {
    if (_requiresLinkedTransaction) return;
    setState(() => _linkedTxRef = null);
  }

  void _onDeleteTap() {
    if (_isSubmitting) return;
    if (!_deleteArmed) {
      setState(() => _deleteArmed = true);
      _deleteDisarmTimer?.cancel();
      _deleteDisarmTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _deleteArmed = false);
      });
      return;
    }
    unawaited(
      _submitResult(
        const _ExpenseSheetDelete(),
        submittingLabel: 'Deleting',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactionProvider = context.watch<TransactionProvider>();
    final linkedTransaction = _linkedTransaction(transactionProvider);
    final keys = widget.group.members
        .map((m) => m.devicePublicKey)
        .where((k) => k.isNotEmpty)
        .toList();

    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final reason = _reasonCtrl.text.trim();
    final canSave = amount > 0 && reason.isNotEmpty && _split.isNotEmpty;
    final allSelected = keys.isNotEmpty && _split.length == keys.length;

    return PopScope(
      canPop: !_isSubmitting,
      child: _IosModalShell(
        title: _isEditing ? 'Edit Expense' : 'Add Expense',
        closeEnabled: !_isSubmitting,
        footer: [
          _IosFormSubmit(
            label: _isSubmitting
                ? (_submittingLabel ??
                    (widget.submittingLabel ??
                        (_isEditing ? 'Saving' : 'Adding')))
                : _isEditing
                    ? 'Save'
                    : 'Add',
            enabled: canSave && !_isSubmitting,
            isBusy: _isSubmitting,
            onTap: _submit,
            topPadding: 0,
          ),
          if (_isEditing) ...[
            const SizedBox(height: 10),
            _IosDangerButton(
              label: _deleteArmed ? 'Tap again to delete' : 'Delete expense',
              icon: Icons.delete_outline,
              armed: _deleteArmed,
              onTap: _isSubmitting ? null : _onDeleteTap,
            ),
          ],
        ],
        children: [
          // Amount row — centered huge input with currency suffix + bottom rule.
          _IosAmountRow(
            controller: _amountCtrl,
            focusNode: _amountFocusNode,
            autofocus: !_startsFromLinkedTransaction,
            onChanged: (_) => setState(() {}),
          ),
          _IosFormGroup(
            label: 'For what?',
            child: _IosFormInput(
              controller: _reasonCtrl,
              focusNode: _reasonFocusNode,
              autofocus: _startsFromLinkedTransaction,
              hint: 'e.g., Dinner, Hotel, Taxi',
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
          ),
          _IosFormGroup(
            label: 'When',
            child: _IosValueRow(
              icon: AppIcons.calendar_today_outlined,
              title: _formatSharedDate(_paidAt),
              onTap: _pickPaidAt,
            ),
          ),
          _IosFormGroup(
            label: 'Transaction',
            labelTrailing: _linkedTxRef == null || _requiresLinkedTransaction
                ? null
                : _IosTextAction(
                    label: 'Remove',
                    onTap: _clearLinkedTransaction,
                  ),
            child: _IosValueRow(
              icon: AppIcons.receipt_long_rounded,
              title: linkedTransaction == null
                  ? _linkedTxRef == null
                      ? context.l10nText('Link transaction')
                      : context.l10nText('Linked transaction')
                  : _transactionCounterpartyLabel(linkedTransaction),
              subtitle: linkedTransaction == null
                  ? _linkedTxRef ?? context.l10nText('Optional')
                  : _transactionLinkSummary(linkedTransaction, context),
              onTap: _pickLinkedTransaction,
            ),
          ),
          _IosFormGroup(
            label: 'Paid by',
            child: _IosSharedMemberSelector(
              group: widget.group,
              myPublicKey: widget.myPublicKey,
              memberKeys: keys,
              isSelected: (pk) => _paidBy == pk,
              onTap: (pk) => setState(() => _paidBy = pk),
            ),
          ),
          _IosFormGroup(
            label: 'Split between',
            labelTrailing: _IosTextAction(
              label: allSelected ? 'None' : 'All',
              onTap: () => setState(() {
                _split = allSelected ? <String>{} : keys.toSet();
              }),
            ),
            child: _IosSharedMemberSelector(
              group: widget.group,
              myPublicKey: widget.myPublicKey,
              memberKeys: keys,
              isSelected: _split.contains,
              onTap: (pk) => setState(() {
                if (_split.contains(pk)) {
                  _split = {..._split}..remove(pk);
                } else {
                  _split = {..._split, pk};
                }
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedTransactionPickerSheet extends StatefulWidget {
  final List<Transaction> transactions;
  final String? selectedRef;

  const _LinkedTransactionPickerSheet({
    required this.transactions,
    required this.selectedRef,
  });

  @override
  State<_LinkedTransactionPickerSheet> createState() =>
      _LinkedTransactionPickerSheetState();
}

class _LinkedTransactionPickerSheetState
    extends State<_LinkedTransactionPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Transaction> _filteredTransactions() {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.transactions
        : widget.transactions.where((transaction) {
            return transaction.reference.toLowerCase().contains(query) ||
                _transactionCounterpartyLabel(transaction)
                    .toLowerCase()
                    .contains(query) ||
                (transaction.note?.toLowerCase().contains(query) ?? false);
          }).toList(growable: false);
    return filtered.take(80).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTransactions();
    return _IosModalShell(
      title: 'Link Transaction',
      children: [
        _IosSearchField(
          controller: _searchCtrl,
          hint: 'Search transactions',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              context.l10nText('No available transactions'),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          for (final transaction in filtered) ...[
            _LinkedTransactionOption(
              transaction: transaction,
              selected: transaction.reference == widget.selectedRef,
              onTap: () => Navigator.of(context).pop(transaction),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _LinkedTransactionOption extends StatelessWidget {
  final Transaction transaction;
  final bool selected;
  final VoidCallback onTap;

  const _LinkedTransactionOption({
    required this.transaction,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final cardColor = AppColors.cardColor(context);
    final borderColor =
        selected ? AppColors.primaryLight : AppColors.borderColor(context);
    final date = _transactionDateLabel(transaction);
    final subtitle = [
      _formatEtb(transaction.amount.abs(), context),
      if (date.isNotEmpty) date,
      _logId(transaction.reference),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                AppIcons.receipt_long_rounded,
                color: AppColors.primaryLight,
                size: 17,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _transactionCounterpartyLabel(transaction),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                AppIcons.check_circle_rounded,
                color: AppColors.primaryLight,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupCardBalanceLine extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  const _GroupCardBalanceLine({
    required this.group,
    required this.myPublicKey,
  });

  @override
  Widget build(BuildContext context) {
    final balances = computeBalancesFor(group);
    final myBalance = balances[myPublicKey] ?? 0.0;
    if (myBalance.abs() < 0.5) {
      return Text(
        context.l10nText('All settled'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textTertiary(context),
              fontWeight: FontWeight.w600,
            ),
      );
    }
    final isOwed = myBalance > 0;
    final text = isOwed
        ? context
            .l10n('shared.youAreOwedAmount', "You're owed {amount}")
            .replaceFirst('{amount}', _formatEtb(myBalance, context))
        : context
            .l10n('shared.youOweAmount', 'You owe {amount}')
            .replaceFirst('{amount}', _formatEtb(myBalance.abs(), context));
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isOwed ? AppColors.incomeSuccess : AppColors.red,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

// ============================================================================
// Group settings sheet — edit name + your display name, copy invite, leave.
// ============================================================================

abstract class _GroupSettingsResult {
  const _GroupSettingsResult();
}

class _GroupSettingsSave extends _GroupSettingsResult {
  final String name;
  final String displayName;
  final bool backfillNewMembers;
  final SharedPaymentAddress paymentAddress;
  const _GroupSettingsSave(
    this.name,
    this.displayName,
    this.backfillNewMembers,
    this.paymentAddress,
  );
}

class _GroupSettingsCopyInvite extends _GroupSettingsResult {
  const _GroupSettingsCopyInvite();
}

class _GroupSettingsLeave extends _GroupSettingsResult {
  const _GroupSettingsLeave();
}

class _GroupSettingsSheet extends StatefulWidget {
  final String initialName;
  final String initialDisplayName;
  final bool initialBackfillNewMembers;
  final List<AccountSummary> paymentAccounts;
  final SharedPaymentAddress initialPaymentAddress;
  const _GroupSettingsSheet({
    required this.initialName,
    required this.initialDisplayName,
    required this.initialBackfillNewMembers,
    required this.paymentAccounts,
    required this.initialPaymentAddress,
  });

  @override
  State<_GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

class _GroupSettingsSheetState extends State<_GroupSettingsSheet> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _displayCtrl =
      TextEditingController(text: widget.initialDisplayName);
  late bool _backfillNewMembers = widget.initialBackfillNewMembers;
  late SharedPaymentAddress _paymentAddress = widget.initialPaymentAddress;
  bool _leaveArmed = false;
  Timer? _disarmTimer;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _displayCtrl.dispose();
    _disarmTimer?.cancel();
    super.dispose();
  }

  void _onLeaveTap() {
    if (!_leaveArmed) {
      setState(() => _leaveArmed = true);
      _disarmTimer?.cancel();
      _disarmTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _leaveArmed = false);
      });
      return;
    }
    Navigator.of(context).pop(const _GroupSettingsLeave());
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameCtrl.text.trim().isNotEmpty &&
        _displayCtrl.text.trim().isNotEmpty &&
        (_nameCtrl.text.trim() != widget.initialName ||
            _displayCtrl.text.trim() != widget.initialDisplayName ||
            _backfillNewMembers != widget.initialBackfillNewMembers ||
            _paymentAddress != widget.initialPaymentAddress);

    return _IosModalShell(
      title: 'Edit Group',
      footer: [
        _IosFormSubmit(
          label: 'Save',
          enabled: canSave,
          onTap: () => Navigator.of(context).pop(
            _GroupSettingsSave(
              _nameCtrl.text.trim(),
              _displayCtrl.text.trim(),
              _backfillNewMembers,
              _paymentAddress,
            ),
          ),
          topPadding: 0,
        ),
        const SizedBox(height: 10),
        _IosSecondaryButton(
          label: 'Copy invite',
          icon: Icons.content_copy,
          onTap: () =>
              Navigator.of(context).pop(const _GroupSettingsCopyInvite()),
        ),
        const SizedBox(height: 10),
        _IosDangerButton(
          label: _leaveArmed ? 'Tap again to confirm' : 'Leave group',
          icon: Icons.logout,
          armed: _leaveArmed,
          onTap: _onLeaveTap,
        ),
      ],
      children: [
        _IosFormGroup(
          label: 'Group name',
          child: _IosFormInput(
            controller: _nameCtrl,
            hint: 'Trip to Lalibela, Roommates…',
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
        ),
        _IosFormGroup(
          label: 'Your name',
          child: _IosFormInput(
            controller: _displayCtrl,
            hint: 'How other members see you',
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
        ),
        _IosFormGroup(
          label: 'New members',
          child: _IosCheckboxRow(
            title: 'Backfill history',
            value: _backfillNewMembers,
            onChanged: (value) => setState(() {
              _backfillNewMembers = value;
            }),
          ),
        ),
        _IosFormGroup(
          label: 'Payment account',
          child: _PaymentAddressSelector(
            label: '',
            accounts: widget.paymentAccounts,
            selected: _paymentAddress,
            onChanged: (address) {
              setState(() => _paymentAddress = address);
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// iOS-styled modal shell + form atoms.
// Match the iOS web-view styling pixel-for-pixel:
//   - Modal bg: --bg-dark (page color, NOT card white)
//   - 24px corner radius top, 24px padding all sides
//   - Handle: 36×4 px borderColor 2px-radius, 20px below
//   - Form labels: 13px / w600 / UPPERCASE / 0.5px letter-spacing / textSecondary
//   - Form inputs: 14/16 padding, 12px radius, bg = cardColor, 1px border
//   - Submit: linear gradient #6366F1 → #818CF8, 16px / w600, 12px radius
//   - Shared chip: 5/10 padding, 999px radius, bg cardColor, border borderColor
//     Active: primaryLight border + rgba(99,102,241,0.08) bg
// ============================================================================

const Color _iosPrimary = Color(0xFF6366F1);
const Color _iosPrimaryLight = Color(0xFF818CF8);
const Color _iosNegative = Color(0xFFEF4444);

class _IosModalShell extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget> footer;
  final Widget? titleWidget;
  final bool closeEnabled;
  const _IosModalShell({
    required this.title,
    required this.children,
    this.footer = const [],
    this.titleWidget,
    this.closeEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.background(context);
    final cardColor = AppColors.cardColor(context);
    final textPrimary = AppColors.textPrimary(context);
    final borderColor = AppColors.borderColor(context);
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final bottomSafeArea = mediaQuery.viewPadding.bottom;
    final keyboardLiftBuffer = keyboardInset > 0 ? 28.0 : 0.0;
    final hasFooter = footer.isNotEmpty;
    final actionBottomGap = keyboardInset > 0
        ? 4.0
        : (mediaQuery.size.height * 0.014).clamp(8.0, 14.0);
    final actionTopGap = keyboardInset > 0 ? 12.0 : 20.0;
    final formBottomPadding = hasFooter
        ? (keyboardInset > 0 ? 8.0 : 4.0)
        : (keyboardInset > 0 ? 16.0 : 24.0);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset + keyboardLiftBuffer),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          color: bg,
          constraints: BoxConstraints(
            maxHeight: mediaQuery.size.height * 0.9,
          ),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxHeight = constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : mediaQuery.size.height * 0.9;

                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            24,
                            0,
                            24,
                            formBottomPadding,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Handle — 36×4, borderColor, 2px radius, 20px below
                              Center(
                                child: Container(
                                  margin: const EdgeInsets.only(
                                    top: 10,
                                    bottom: 20,
                                  ),
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: borderColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              // Header — title left, close button right
                              Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: titleWidget ??
                                          Text(
                                            context.l10nText(title),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w600,
                                              color: textPrimary,
                                            ),
                                          ),
                                    ),
                                    // 32×32 rounded-square close button (matches iOS)
                                    Opacity(
                                      opacity: closeEnabled ? 1 : 0.45,
                                      child: InkWell(
                                        onTap: closeEnabled
                                            ? () => Navigator.of(context).pop()
                                            : null,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: cardColor,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            Icons.close,
                                            size: 16,
                                            color: textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ...children,
                            ],
                          ),
                        ),
                      ),
                      if (hasFooter) ...[
                        SizedBox(height: actionTopGap),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            0,
                            24,
                            bottomSafeArea + actionBottomGap,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: footer,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _IosFormGroup extends StatelessWidget {
  final String label;
  final Widget child;
  final Widget? labelTrailing;
  const _IosFormGroup({
    required this.label,
    required this.child,
    this.labelTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10nText(label).toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                if (labelTrailing != null) labelTrailing!,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _IosFormInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? hint;
  final int? maxLength;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  const _IosFormInput({
    required this.controller,
    this.focusNode,
    this.autofocus = false,
    this.hint,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardColor(context);
    final borderColor = AppColors.borderColor(context);
    final textPrimary = AppColors.textPrimary(context);
    final textMuted = AppColors.textTertiary(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      style: TextStyle(fontSize: 16, color: textPrimary),
      decoration: InputDecoration(
        hintText: hint == null ? null : context.l10nText(hint!),
        hintStyle: TextStyle(color: textMuted, fontSize: 16),
        filled: true,
        fillColor: cardColor,
        counterText: '',
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _iosPrimary, width: 2),
        ),
      ),
    );
  }
}

class _IosCheckboxRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _IosCheckboxRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardColor(context);
    final borderColor = AppColors.borderColor(context);
    final textPrimary = AppColors.textPrimary(context);

    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10nText(title),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Checkbox(
              value: value,
              onChanged: (checked) => onChanged(checked ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _IosValueRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showChevron;

  const _IosValueRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardColor(context);
    final borderColor = AppColors.borderColor(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primaryLight),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 10),
              Icon(
                AppIcons.chevron_right,
                size: 17,
                color: AppColors.textTertiary(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IosSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const _IosSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(color: AppColors.textPrimary(context), fontSize: 15),
      decoration: InputDecoration(
        hintText: context.l10nText(hint),
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        prefixIcon: Icon(
          AppIcons.search,
          size: 18,
          color: AppColors.textTertiary(context),
        ),
        filled: true,
        fillColor: AppColors.cardColor(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _iosPrimary, width: 2),
        ),
      ),
    );
  }
}

class _IosAmountRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  const _IosAmountRow({
    required this.controller,
    this.focusNode,
    this.autofocus = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textMuted = AppColors.textTertiary(context);
    final borderColor = AppColors.borderColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: borderColor, width: 1),
          ),
        ),
        padding: const EdgeInsets.only(top: 12, bottom: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.55,
              ),
              child: IntrinsicWidth(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  textAlign: TextAlign.center,
                  autofocus: autofocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '0',
                    hintStyle: TextStyle(
                      color: textMuted.withValues(alpha: 0.45),
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              context.l10nText('ETB'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IosSharedMemberSelector extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final List<String> memberKeys;
  final bool Function(String publicKey) isSelected;
  final ValueChanged<String> onTap;

  const _IosSharedMemberSelector({
    required this.group,
    required this.myPublicKey,
    required this.memberKeys,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (memberKeys.isEmpty) {
      return Text(
        context.l10nText('No members'),
        style: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: memberKeys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final pk = memberKeys[index];
          return _IosSharedChip(
            label: group.displayNameFor(myPublicKey, pk),
            dotColor: Color(memberColorFor(group, pk)),
            active: isSelected(pk),
            onTap: () => onTap(pk),
          );
        },
      ),
    );
  }
}

class _IosSharedChip extends StatelessWidget {
  final String label;
  final Color dotColor;
  final bool active;
  final VoidCallback onTap;
  const _IosSharedChip({
    required this.label,
    required this.dotColor,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardColor(context);
    final borderColor = AppColors.borderColor(context);
    final textPrimary = AppColors.textPrimary(context);
    final initial = label.trim().isEmpty
        ? '?'
        : String.fromCharCode(label.trim().runes.first).toUpperCase();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 36,
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF6366F1).withValues(alpha: 0.08)
              : cardColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? _iosPrimary : borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IosTextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _IosTextAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          context.l10nText(label),
          style: const TextStyle(
            color: _iosPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _IosFormSubmit extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool enabled;
  final bool isBusy;
  final VoidCallback onTap;
  final double topPadding;
  const _IosFormSubmit({
    required this.label,
    this.icon,
    required this.enabled,
    this.isBusy = false,
    required this.onTap,
    this.topPadding = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Opacity(
        opacity: enabled || isBusy ? 1 : 0.6,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled && !isBusy ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_iosPrimary, _iosPrimaryLight],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBusy) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      context.l10nText(label),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!isBusy && icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(icon, size: 18, color: Colors.white),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IosSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const _IosSecondaryButton({
    required this.label,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final borderColor = AppColors.borderColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: textPrimary),
                const SizedBox(width: 8),
              ],
              Text(
                context.l10nText(label),
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IosDangerButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool armed;
  final VoidCallback? onTap;
  const _IosDangerButton({
    required this.label,
    this.icon,
    required this.armed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.borderColor(context);
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
            decoration: BoxDecoration(
              color: armed ? _iosNegative.withValues(alpha: 0.10) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: armed ? _iosNegative : borderColor,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: _iosNegative),
                  const SizedBox(width: 8),
                ],
                Text(
                  context.l10nText(label),
                  style: const TextStyle(
                    color: _iosNegative,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
