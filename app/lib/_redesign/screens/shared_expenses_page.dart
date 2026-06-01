import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/shared_expense_repository.dart';

void _sharedExpensesPageLog(String message) {
  if (kDebugMode) {
    debugPrint('debug: SharedExpensesPage: $message');
  }
}

String _logId(String value) {
  if (value.length <= 12) return value;
  return '${value.substring(0, 8)}...${value.substring(value.length - 4)}';
}

String _formatEtb(num amount) {
  final value = amount.round();
  final sign = value < 0 ? '-' : '';
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return '${sign}ETB $buffer';
}

class RedesignSharedExpensesPage extends StatefulWidget {
  const RedesignSharedExpensesPage({super.key});

  @override
  State<RedesignSharedExpensesPage> createState() =>
      _RedesignSharedExpensesPageState();
}

class _RedesignSharedExpensesPageState extends State<RedesignSharedExpensesPage>
    with AutomaticKeepAliveClientMixin<RedesignSharedExpensesPage> {
  final SharedExpenseRepository _repository = SharedExpenseRepository();
  final AccountRepository _accountRepository = AccountRepository();
  static const String _accountShareDisplayNameKey =
      'account_share_display_name';

  List<SharedExpenseGroup> _groups = const [];
  String _myPublicKey = '';
  bool _isRefreshing = false;
  bool _isMutating = false;
  bool _engineReachable = true;
  String? _approvingMemberKey;
  SharedExpenseGroup? _selectedGroup;
  _CreatingGroupDraft? _creatingGroup;

  @override
  void initState() {
    super.initState();
    _loadGroups(refreshFromEngine: true, showErrors: false);
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

  SharedExpenseGroup? _updatedSelectedGroup(List<SharedExpenseGroup> groups) {
    final selected = _selectedGroup;
    if (selected == null) return null;
    for (final group in groups) {
      if (group.id == selected.id) return group;
    }
    return selected;
  }

  void _openGroup(SharedExpenseGroup group) {
    _sharedExpensesPageLog('openGroup group=${_logId(group.id)}');
    setState(() => _selectedGroup = group);
  }

  void _closeGroup() {
    _sharedExpensesPageLog('closeGroup');
    setState(() => _selectedGroup = null);
  }

  void _showAddExpenseComingSoon() {
    _showSnack(context.l10nTextRead('Expense entry is coming next'));
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
    final displayName = await _defaultDisplayName();
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
      ),
    );
    if (input == null) return;

    _sharedExpensesPageLog('createGroup submitted name="${input.groupName}"');
    setState(() {
      _isMutating = true;
      _creatingGroup = _CreatingGroupDraft(
        name: input.groupName,
        displayName: input.displayName,
      );
    });
    try {
      await _saveDefaultDisplayName(input.displayName);
      final group = await _repository.createGroup(
        name: input.groupName,
        displayName: input.displayName,
      );
      if (mounted) {
        setState(() {
          _creatingGroup = null;
          _groups = [
            group,
            ..._groups.where((existing) => existing.id != group.id),
          ];
        });
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
          _creatingGroup = null;
        });
      }
    }
  }

  Future<void> _joinGroup() async {
    final joinedMessage = context.l10nTextRead('Joined group');
    final displayName = await _defaultDisplayName();
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
      ),
    );
    if (input == null) return;

    _sharedExpensesPageLog('joinGroup submitted code="${input.groupName}"');
    setState(() => _isMutating = true);
    try {
      await _saveDefaultDisplayName(input.displayName);
      await _repository.joinGroup(
        inviteOrCode: input.groupName,
        displayName: input.displayName,
      );
      await _loadGroups(refreshFromEngine: true, showErrors: false);
      _showSnack(joinedMessage);
      _sharedExpensesPageLog('joinGroup done');
    } catch (error, stackTrace) {
      _sharedExpensesPageLog('joinGroup failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isMutating = false);
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
    setState(() => _approvingMemberKey = member.devicePublicKey);
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
      if (mounted) setState(() => _approvingMemberKey = null);
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
    if (selectedGroup != null) {
      return _SharedGroupDetailView(
        group: selectedGroup,
        myPublicKey: _myPublicKey,
        shortKey: _shortKey,
        onBack: _closeGroup,
        onCopyInvite: () => _copyInvite(selectedGroup),
        onAddExpense: _showAddExpenseComingSoon,
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
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10nText('Split expenses with friends'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _ActionBar(
                        isBusy: _isMutating,
                        isRefreshing: _isRefreshing,
                        onCreate: _createGroup,
                        onJoin: _joinGroup,
                        onRefresh: () => _loadGroups(refreshFromEngine: true),
                      ),
                      if (!_engineReachable) ...[
                        const SizedBox(height: 12),
                        _EngineStatusBanner(
                          label: context.l10nText(
                            'Totals Engine is not reachable yet',
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
                        isRefreshing: _isRefreshing,
                        pendingMembers: pendingMembers,
                        shortKey: _shortKey,
                        approvingMemberKey: _approvingMemberKey,
                        onOpen: () => _openGroup(group),
                        onCopyInvite: () => _copyInvite(group),
                        onApproveMember: (member) =>
                            _approveMember(group, member),
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
  final bool isRefreshing;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onRefresh;

  const _ActionBar({
    required this.isBusy,
    required this.isRefreshing,
    required this.onCreate,
    required this.onJoin,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FilledButton.icon(
          onPressed: isBusy ? null : onCreate,
          icon: const Icon(AppIcons.add, size: 18, color: AppColors.white),
          label: Text(context.l10nText('New')),
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
          icon: Icon(
            AppIcons.lock_outline_rounded,
            size: 18,
            color: AppColors.textPrimary(context),
          ),
          label: Text(context.l10nText('Join')),
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

  const _EmptySharedState({
    required this.onCreate,
    required this.onJoin,
    required this.isBusy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              icon: const Icon(AppIcons.add, color: AppColors.white),
              label: Text(context.l10nText('Create group')),
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
              icon: Icon(
                AppIcons.lock_outline_rounded,
                color: AppColors.textPrimary(context),
              ),
              label: Text(context.l10nText('Join with code')),
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
                  label: context.l10nText('Creating'),
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
                    context.l10nText('Preparing invite code'),
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
  final String Function(String value) shortKey;
  final VoidCallback onBack;
  final VoidCallback onCopyInvite;
  final VoidCallback onAddExpense;

  const _SharedGroupDetailView({
    required this.group,
    required this.myPublicKey,
    required this.shortKey,
    required this.onBack,
    required this.onCopyInvite,
    required this.onAddExpense,
  });

  @override
  State<_SharedGroupDetailView> createState() => _SharedGroupDetailViewState();
}

class _SharedGroupDetailViewState extends State<_SharedGroupDetailView> {
  int _selectedTab = 0;
  bool _showTransactions = false;

  static const List<Color> _memberColors = [
    AppColors.primaryLight,
    AppColors.incomeSuccess,
    Color(0xFFDB2777),
    AppColors.amber,
    AppColors.blue,
  ];

  @override
  void didUpdateWidget(covariant _SharedGroupDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.id != widget.group.id) {
      _showTransactions = false;
      _selectedTab = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showTransactions) {
      return _SharedGroupTransactionsView(
        group: widget.group,
        onBack: () => setState(() => _showTransactions = false),
        onAddExpense: widget.onAddExpense,
      );
    }

    final members = _memberViews(context);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: SizedBox(
          width: 52,
          height: 52,
          child: FloatingActionButton(
            onPressed: widget.onAddExpense,
            backgroundColor: AppColors.primaryLight,
            foregroundColor: AppColors.white,
            elevation: 8,
            shape: const CircleBorder(),
            child: const Icon(AppIcons.add, size: 26),
          ),
        ),
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
                      onBack: widget.onBack,
                      onCopyInvite: widget.onCopyInvite,
                    ),
                    const SizedBox(height: 16),
                    _SharedGroupIdentityHeader(
                      group: widget.group,
                      members: members,
                    ),
                    const SizedBox(height: 18),
                    _SharedBalanceSummaryCard(
                      group: widget.group,
                      members: members,
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
                    ),
                  1 => const _SharedGroupActivitiesTab(),
                  _ => _SharedGroupAnalyticsTab(
                      group: widget.group,
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
      final displayName = isMe
          ? widget.group.myDisplayName.trim()
          : '${context.l10nText('Member')} ${i + 1}';
      final label =
          displayName.isNotEmpty ? displayName : context.l10nText('You');
      views.add(
        _SharedMemberView(
          label: label,
          shortKey: widget.shortKey(member.devicePublicKey),
          color: _memberColors[i % _memberColors.length],
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

  const _SharedMemberView({
    required this.label,
    required this.shortKey,
    required this.color,
  });

  String get initial {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}

class _SharedGroupTransactionsView extends StatefulWidget {
  final SharedExpenseGroup group;
  final VoidCallback onBack;
  final VoidCallback onAddExpense;

  const _SharedGroupTransactionsView({
    required this.group,
    required this.onBack,
    required this.onAddExpense,
  });

  @override
  State<_SharedGroupTransactionsView> createState() =>
      _SharedGroupTransactionsViewState();
}

class _SharedGroupTransactionsViewState
    extends State<_SharedGroupTransactionsView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const transactionCount = 0;
    final hasQuery = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: SizedBox(
          width: 52,
          height: 52,
          child: FloatingActionButton(
            onPressed: widget.onAddExpense,
            backgroundColor: AppColors.primaryLight,
            foregroundColor: AppColors.white,
            elevation: 8,
            shape: const CircleBorder(),
            child: const Icon(AppIcons.add, size: 26),
          ),
        ),
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
                    _SharedTransactionsSearchField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 12),
                    const _SharedTransactionsFilterRow(),
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
                    _SharedTransactionsEmptyState(hasQuery: hasQuery),
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

class _SharedTransactionsSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SharedTransactionsSearchField({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: BorderSide(color: AppColors.borderColor(context)),
    );

    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w600,
            ),
        decoration: InputDecoration(
          hintText: context.l10nText('Search reason or member...'),
          hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.textTertiary(context),
                fontWeight: FontWeight.w500,
              ),
          prefixIcon: Icon(
            AppIcons.search,
            size: 22,
            color: AppColors.textTertiary(context),
          ),
          filled: true,
          fillColor: AppColors.cardColor(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: AppColors.primaryLight),
          ),
        ),
      ),
    );
  }
}

class _SharedTransactionsFilterRow extends StatelessWidget {
  const _SharedTransactionsFilterRow();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SharedTransactionsFilterChip(
          label: context.l10nText('Type'),
          value: context.l10nText('All'),
        ),
        _SharedTransactionsFilterChip(
          label: context.l10nText('When'),
          value: context.l10nText('All time'),
        ),
        _SharedTransactionsFilterChip(
          label: context.l10nText('Paid by'),
          value: context.l10nText('All'),
        ),
      ],
    );
  }
}

class _SharedTransactionsFilterChip extends StatelessWidget {
  final String label;
  final String value;

  const _SharedTransactionsFilterChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textTertiary(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 104),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            AppIcons.expand_more,
            size: 14,
            color: AppColors.textTertiary(context),
          ),
        ],
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
            _formatEtb(0),
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
  final VoidCallback onBack;
  final VoidCallback onCopyInvite;

  const _SharedGroupDetailTopBar({
    required this.onBack,
    required this.onCopyInvite,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
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
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textTertiary(context),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onCopyInvite,
          icon: const Icon(AppIcons.more_horiz, size: 24),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.cardColor(context),
            foregroundColor: AppColors.textSecondary(context),
            side: BorderSide(color: AppColors.borderColor(context)),
            minimumSize: const Size(44, 44),
            shape: const CircleBorder(),
          ),
        ),
      ],
    );
  }
}

class _SharedGroupIdentityHeader extends StatelessWidget {
  final SharedExpenseGroup group;
  final List<_SharedMemberView> members;

  const _SharedGroupIdentityHeader({
    required this.group,
    required this.members,
  });

  @override
  Widget build(BuildContext context) {
    final pillColor =
        AppColors.isDark(context) ? AppColors.darkSurface : AppColors.slate900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: pillColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            group.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _StackedMemberAvatars(members: members),
            const SizedBox(width: 10),
            Text(
              group.memberCount == 1
                  ? context.l10nText('1 member')
                  : '${group.memberCount} ${context.l10nText('members')}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textTertiary(context),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StackedMemberAvatars extends StatelessWidget {
  final List<_SharedMemberView> members;

  const _StackedMemberAvatars({required this.members});

  @override
  Widget build(BuildContext context) {
    final visibleMembers = members.take(4).toList(growable: false);
    return SizedBox(
      width: 24.0 + ((visibleMembers.length - 1).clamp(0, 3) * 19.0),
      height: 28,
      child: Stack(
        children: [
          for (var i = 0; i < visibleMembers.length; i++)
            Positioned(
              left: i * 19,
              child: Container(
                width: 28,
                height: 28,
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
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
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

  const _SharedBalanceSummaryCard({
    required this.group,
    required this.members,
  });

  @override
  Widget build(BuildContext context) {
    final counterparties = members.skip(1).take(2).toList(growable: false);

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
                    group.status == SharedExpenseGroupStatus.ready
                        ? context.l10nText("YOU'RE SETTLED UP")
                        : context.l10nText('PENDING SETUP'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary(context),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _formatEtb(0),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    group.status == SharedExpenseGroupStatus.ready
                        ? context.l10nText('No balances yet')
                        : context.l10nText('Waiting for group approval'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10nText('Add an expense to start splitting.'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary(context),
                        ),
                  ),
                ],
              ),
            ),
            if (counterparties.isNotEmpty) ...[
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
                    for (final member in counterparties) ...[
                      Text(
                        member.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: member.color,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatEtb(0),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppColors.textPrimary(context),
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

  const _SharedGroupHomeTab({
    required this.members,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SharedSectionHeader(
          label: context.l10nText('RECENT'),
          actionLabel: context.l10nText('See all'),
          onAction: onSeeAll,
        ),
        const SizedBox(height: 8),
        _SharedDetailEmptyBlock(
          icon: AppIcons.receipt_long_rounded,
          title: context.l10nText('No expenses yet'),
          subtitle: context.l10nText(
            'Tap + to add the first group expense.',
          ),
        ),
        const SizedBox(height: 22),
        _SharedSectionHeader(label: context.l10nText('SETTLE')),
        const SizedBox(height: 8),
        _SharedSettleEmptyRow(members: members),
      ],
    );
  }
}

class _SharedGroupActivitiesTab extends StatelessWidget {
  const _SharedGroupActivitiesTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SharedSectionHeader(label: context.l10nText('ACTIVITIES')),
        const SizedBox(height: 8),
        _SharedDetailEmptyBlock(
          icon: AppIcons.toc_rounded,
          title: context.l10nText('No activity yet'),
          subtitle: context.l10nText(
            'Expenses, approvals, and settlements will appear here.',
          ),
        ),
      ],
    );
  }
}

class _SharedGroupAnalyticsTab extends StatelessWidget {
  final SharedExpenseGroup group;
  final int pendingApprovalCount;

  const _SharedGroupAnalyticsTab({
    required this.group,
    required this.pendingApprovalCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SharedSectionHeader(label: context.l10nText('ANALYTICS')),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SharedMetricTile(
                label: context.l10nText('Total spent'),
                value: _formatEtb(0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SharedMetricTile(
                label: context.l10nText('Members'),
                value: '${group.memberCount}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SharedMetricTile(
                label: context.l10nText('Open balances'),
                value: _formatEtb(0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SharedMetricTile(
                label: context.l10nText('Approvals'),
                value: '$pendingApprovalCount',
              ),
            ),
          ],
        ),
      ],
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
          TextButton.icon(
            onPressed: onAction,
            iconAlignment: IconAlignment.end,
            icon: const Icon(AppIcons.arrow_forward, size: 16),
            label: Text(actionLabel!),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryLight,
              textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
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
  final List<_SharedMemberView> members;

  const _SharedSettleEmptyRow({required this.members});

  @override
  Widget build(BuildContext context) {
    final from = members.isNotEmpty ? members.first : null;
    final to = members.length > 1
        ? members[1]
        : members.isNotEmpty
            ? members.first
            : null;

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
            child: from == null || to == null || from == to
                ? Text(
                    context.l10nText('Nothing to settle'),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w800,
                        ),
                  )
                : Row(
                    children: [
                      Flexible(
                        child: Text(
                          from.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: from.color,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(
                          AppIcons.arrow_forward,
                          color: AppColors.primaryLight,
                          size: 18,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          to.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: to.color,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 16),
          Text(
            _formatEtb(0),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _SharedMetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _SharedMetricTile({
    required this.label,
    required this.value,
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
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textTertiary(context),
                  fontWeight: FontWeight.w800,
                ),
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
        ],
      ),
    );
  }
}

class _SharedGroupCard extends StatelessWidget {
  final SharedExpenseGroup group;
  final bool isRefreshing;
  final List<SharedExpenseMember> pendingMembers;
  final String Function(String value) shortKey;
  final String? approvingMemberKey;
  final VoidCallback onOpen;
  final VoidCallback onCopyInvite;
  final ValueChanged<SharedExpenseMember> onApproveMember;

  const _SharedGroupCard({
    required this.group,
    required this.isRefreshing,
    required this.pendingMembers,
    required this.shortKey,
    required this.approvingMemberKey,
    required this.onOpen,
    required this.onCopyInvite,
    required this.onApproveMember,
  });

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
                        const SizedBox(height: 12),
                        Text(
                          '${group.memberCount} ${context.l10nText('members')}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          shortKey(group.id),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textTertiary(context),
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(label: statusLabel, color: statusColor),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        group.status == SharedExpenseGroupStatus.localOnly
                            ? null
                            : onCopyInvite,
                    icon: const Icon(AppIcons.copy, size: 17),
                    label: Text(context.l10nText('Copy code')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary(context),
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      side: BorderSide(color: AppColors.borderColor(context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
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
  final String Function(String value) shortKey;
  final bool isApproving;
  final VoidCallback onApprove;

  const _PendingMemberRow({
    required this.member,
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
            child: Text(
              shortKey(member.devicePublicKey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
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

class _GroupFormResult {
  final String groupName;
  final String displayName;

  const _GroupFormResult({
    required this.groupName,
    required this.displayName,
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

  const _GroupFormSheet({
    required this.title,
    required this.primaryLabel,
    required this.groupLabel,
    required this.groupHint,
    required this.nameLabel,
    required this.nameHint,
    required this.initialName,
  });

  @override
  State<_GroupFormSheet> createState() => _GroupFormSheetState();
}

class _GroupFormSheetState extends State<_GroupFormSheet> {
  late final TextEditingController _groupController;
  late final TextEditingController _nameController;
  bool _hasTriedSubmit = false;

  @override
  void initState() {
    super.initState();
    _groupController = TextEditingController();
    _nameController = TextEditingController(text: widget.initialName);
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              20 + mediaQuery.padding.bottom,
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
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(AppIcons.close_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.cardColor(context),
                        foregroundColor: AppColors.textPrimary(context),
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
                  showError:
                      _hasTriedSubmit && _groupController.text.trim().isEmpty,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                _SheetTextField(
                  controller: _nameController,
                  label: widget.nameLabel,
                  hint: widget.nameHint,
                  textInputAction: TextInputAction.done,
                  showError:
                      _hasTriedSubmit && _nameController.text.trim().isEmpty,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(AppIcons.check_rounded, size: 20),
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
                const SizedBox(height: 48),
              ],
            ),
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
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
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
