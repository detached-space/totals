part of 'shared_expenses_page.dart';

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
  final SharedExpenseFabController? fabController;
  final ValueChanged<SharedExpense> onEditExpense;
  final ValueChanged<SettlementDebt> onSettleDebt;
  final VoidCallback onSendNudge;
  final void Function(String debtorPk, double amount) onNudgeDebt;

  const _SharedGroupDetailView({
    super.key,
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
    this.fabController,
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
    _scheduleFabControllerSync();
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
    if (oldWidget.fabController != widget.fabController) {
      oldWidget.fabController?.clear();
    }
    _scheduleFabControllerSync();
  }

  @override
  void dispose() {
    widget.fabController?.clear();
    super.dispose();
  }

  void _scheduleFabControllerSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncFabController();
    });
  }

  void _syncFabController() {
    final controller = widget.fabController;
    if (controller == null) return;
    if (_showMembers) {
      controller.clear();
      return;
    }
    controller.show(
      onPressed: widget.onAddExpense,
      isBusy: widget.isMutating,
      busyLabel: widget.mutationLabel,
    );
  }

  bool handleSystemBack() {
    if (_showTransactions) {
      _setShowTransactions(false);
      return true;
    }
    if (_showMembers) {
      _setShowMembers(false);
      return true;
    }
    return false;
  }

  void _setShowTransactions(bool value) {
    setState(() => _showTransactions = value);
    _scheduleFabControllerSync();
  }

  void _setShowMembers(bool value) {
    setState(() => _showMembers = value);
    _scheduleFabControllerSync();
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
        onBack: () => _setShowTransactions(false),
        onEditExpense: widget.onEditExpense,
      );
    }

    final members = _memberViews(context);
    if (_showMembers) {
      return _SharedGroupMembersView(
        group: widget.group,
        members: members,
        onBack: () => _setShowMembers(false),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background(context),
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
                      onOpenMembers: () => _setShowMembers(true),
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
                      onSeeAll: () => _setShowTransactions(true),
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
    // Me first, then everyone else alphabetical by resolved display name
    // (case-insensitive). Members with no display name yet sort by their
    // short pubkey so ordering stays stable across rebuilds.
    String resolvedKey(SharedExpenseMember m) {
      final name = widget.group
          .displayNameFor(widget.myPublicKey, m.devicePublicKey)
          .trim();
      return (name.isNotEmpty ? name : m.devicePublicKey).toLowerCase();
    }

    final rawMembers = widget.group.members
        .where((member) => member.devicePublicKey.isNotEmpty)
        .toList(growable: true)
      ..sort((a, b) {
        if (a.devicePublicKey == widget.myPublicKey) return -1;
        if (b.devicePublicKey == widget.myPublicKey) return 1;
        return resolvedKey(a).compareTo(resolvedKey(b));
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
    // Cash accounts have no real account number to copy — suppress the
    // copy affordance even when the caller asked for it.
    final effectiveCopyable =
        copyable && address.bankId != CashConstants.bankId;
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
          if (effectiveCopyable) ...[
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

    if (!effectiveCopyable) return content;
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
      for (final debt in originalDebtPlanFor(group).debts) {
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
    final plan = originalDebtPlanFor(group);

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

// ============================================================================
// Partial settlement sheet — runs after the user picks "Settle" on the debt
// action sheet. The user can edit the amount; we prefill with the suggested
// debt amount and let them go higher OR lower. Returns the validated amount
// (always > 0) or null when the user dismisses without confirming.
// ============================================================================

Future<double?> showPartialSettleSheet(
  BuildContext context, {
  required SharedExpenseGroup group,
  required SettlementDebt debt,
  required String myPublicKey,
}) async {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.black.withValues(alpha: 0.5),
    builder: (sheetContext) => _PartialSettleSheet(
      group: group,
      debt: debt,
      myPublicKey: myPublicKey,
    ),
  );
}

class _PartialSettleSheet extends StatefulWidget {
  final SharedExpenseGroup group;
  final SettlementDebt debt;
  final String myPublicKey;
  const _PartialSettleSheet({
    required this.group,
    required this.debt,
    required this.myPublicKey,
  });

  @override
  State<_PartialSettleSheet> createState() => _PartialSettleSheetState();
}

class _PartialSettleSheetState extends State<_PartialSettleSheet> {
  late final TextEditingController _amountCtrl = TextEditingController(
    text: _formatExpenseAmountInput(widget.debt.amount),
  );
  late final FocusNode _amountFocusNode = FocusNode();
  String? _error;

  bool get _iAmThePayer => widget.debt.from == widget.myPublicKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _amountCtrl.text.trim().replaceAll(',', '');
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      setState(() {
        _error =
            context.l10nText('Enter an amount greater than zero.');
      });
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final counterpartyPk =
        _iAmThePayer ? widget.debt.to : widget.debt.from;
    final counterpartyName =
        widget.group.displayNameFor(widget.myPublicKey, counterpartyPk);
    final title = _iAmThePayer
        ? '${context.l10nText('Settle with')} $counterpartyName'
        : '${context.l10nText('Mark received from')} $counterpartyName';
    final cta = _iAmThePayer
        ? context.l10nText('Confirm payment')
        : context.l10nText('Mark received');
    final owedLine = '${context.l10nText('Owed:')} '
        '${_formatEtb(widget.debt.amount, context)}';

    return _IosModalShell(
      title: title,
      footer: [
        _IosFormSubmit(
          label: cta,
          enabled: true,
          onTap: _submit,
          topPadding: 0,
        ),
      ],
      children: [
        _IosAmountRow(
          controller: _amountCtrl,
          focusNode: _amountFocusNode,
          autofocus: false,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: const TextStyle(
                color: AppColors.red,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                owedLine,
                style: const TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _amountCtrl.text =
                      _formatExpenseAmountInput(widget.debt.amount);
                  _amountCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _amountCtrl.text.length),
                  );
                  _error = null;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border:
                      Border.all(color: AppColors.borderColor(context)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  context.l10nText('Full amount'),
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _iAmThePayer
              ? context.l10nText(
                  'Pay less than what\'s owed to record a partial settlement. The remainder stays as debt until you settle it later.',
                )
              : context.l10nText(
                  'Enter what you actually received. The remainder stays as debt until they pay the rest.',
                ),
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12.5,
            height: 1.4,
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
              for (var i = 0; i < entries.length; i++)
                _ActivityRow(
                  entry: entries[i],
                  group: group,
                  myPublicKey: myPublicKey,
                  isFirst: i == 0,
                  isLast: i == entries.length - 1,
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
  final bool isFirst;
  final bool isLast;
  const _ActivityRow({
    required this.entry,
    required this.group,
    required this.myPublicKey,
    required this.isFirst,
    required this.isLast,
  });

  /// Find the SharedExpense this activity entry is tied to (when the
  /// kind is one of the expense_* / settlement_created kinds). Falls back
  /// to null when the expense was deleted, or when the entry doesn't
  /// reference one.
  SharedExpense? _linkedExpense() {
    final id = entry.data['expenseId'];
    if (id is! String || id.isEmpty) return null;
    for (final e in group.expenses) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Snapshot of "what was this entry about?" — preserves the reason and
  /// amount even when the expense was later deleted (the entry itself
  /// stores `reason` / `amount` at creation/deletion time as a fallback).
  ({String reason, double amount})? _expenseSnapshot() {
    final expense = _linkedExpense();
    if (expense != null) {
      return (reason: expense.reason, amount: expense.amount);
    }
    final dataReason = entry.data['reason'];
    final dataAmount = entry.data['amount'];
    if (dataReason is String && dataReason.isNotEmpty) {
      final amt = dataAmount is num ? dataAmount.toDouble() : 0.0;
      return (reason: dataReason, amount: amt);
    }
    return null;
  }

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
    final expenseSnap = _expenseSnapshot();
    final tsLine = _exactTime(entry.timestamp);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimelineRail(
            dotColor: actorColor,
            isFirst: isFirst,
            isLast: isLast,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary(context),
                            height: 1.3,
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
                      ],
                    ),
                  ),
                  if (expenseSnap != null &&
                      !_describeReferencesExpense(entry))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _ExpenseRefChip(
                        reason: expenseSnap.reason,
                        amount: expenseSnap.amount,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      ago.isEmpty ? tsLine : '$tsLine  ·  $ago',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
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

  /// The kinds whose [_describe] already inlines the reason+amount — for
  /// those we don't render the expense ref chip below, to avoid duplicating
  /// the same expense reference twice in the same row.
  bool _describeReferencesExpense(SharedActivityEntry e) {
    return e.kind == 'expense_created' ||
        e.kind == 'expense_deleted' ||
        e.kind == 'settlement_created';
  }

  static String _exactTime(int ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day} · $hh:$mm';
  }

  /// Compact date used by the expense-date-edit before→after pair (no
  /// time-of-day component since the date is the *expense's* date, not
  /// when the edit happened).
  static String _formatDateShort(int ts) {
    if (ts <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _describe(SharedActivityEntry e, BuildContext context) {
    switch (e.kind) {
      case 'group_created':
        return context.l10nText('created the group');
      case 'group_renamed':
        final before = (e.data['before'] as String?)?.trim() ?? '';
        final after = (e.data['after'] as String?)?.trim() ?? '';
        if (before.isEmpty) {
          return '${context.l10nText('renamed the group to')} "$after"';
        }
        return '${context.l10nText('renamed the group:')} "$before" → "$after"';
      case 'member_approved':
        return context.l10nText('approved a new member');
      case 'member_joined':
        return context.l10nText('joined the group');
      case 'member_left':
        return context.l10nText('left the group');
      case 'expense_created':
        return '${context.l10nText('added')} "${e.data['reason'] ?? context.l10nText('an expense')}" · ${_formatEtb(e.data['amount'] ?? 0, context)}';
      case 'expense_amount_changed':
        final beforeAmt = (e.data['before'] as num?)?.toDouble() ?? 0;
        final afterAmt = (e.data['after'] as num?)?.toDouble() ?? 0;
        return '${context.l10nText('changed amount:')} '
            '${_formatEtb(beforeAmt, context)} → ${_formatEtb(afterAmt, context)}';
      case 'expense_reason_changed':
        final before = (e.data['before'] as String?) ?? '';
        final after = (e.data['after'] as String?) ?? '';
        return '${context.l10nText('renamed expense:')} "$before" → "$after"';
      case 'expense_paid_by_changed':
        final beforePk = (e.data['before'] as String?) ?? '';
        final afterPk = (e.data['after'] as String?) ?? '';
        final beforeName = beforePk.isEmpty
            ? context.l10nText('nobody')
            : group.displayNameFor(myPublicKey, beforePk);
        final afterName = afterPk.isEmpty
            ? context.l10nText('nobody')
            : group.displayNameFor(myPublicKey, afterPk);
        return '${context.l10nText('changed payer:')} $beforeName → $afterName';
      case 'expense_split_changed':
        final beforeCount = (e.data['before'] as List?)?.length ?? 0;
        final afterCount = (e.data['after'] as List?)?.length ?? 0;
        final beforeLabel = beforeCount == 1
            ? context.l10nText('person')
            : context.l10nText('people');
        final afterLabel = afterCount == 1
            ? context.l10nText('person')
            : context.l10nText('people');
        return '${context.l10nText('changed split:')} '
            '$beforeCount $beforeLabel → $afterCount $afterLabel';
      case 'expense_date_changed':
        final beforeMs = (e.data['before'] as num?)?.toInt() ?? 0;
        final afterMs = (e.data['after'] as num?)?.toInt() ?? 0;
        return '${context.l10nText('changed date:')} '
            '${_formatDateShort(beforeMs)} → ${_formatDateShort(afterMs)}';
      case 'expense_linked_transaction_changed':
        final beforeRef = (e.data['before'] as String?) ?? '';
        final afterRef = (e.data['after'] as String?) ?? '';
        if (beforeRef.isEmpty && afterRef.isNotEmpty) {
          return context.l10nText('linked a transaction');
        }
        if (beforeRef.isNotEmpty && afterRef.isEmpty) {
          return context.l10nText('removed the linked transaction');
        }
        return context.l10nText('changed the linked transaction');
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

/// Left-side rail that connects sibling activity entries with a vertical
/// line, with a single dot for this entry's row. [isFirst] and [isLast]
/// trim the line so it doesn't dangle above the topmost or below the
/// bottommost entry. Used by [_ActivityRow]; the row's [IntrinsicHeight]
/// stretches the rail to the row's full height so [Expanded] below works.
class _TimelineRail extends StatelessWidget {
  final Color dotColor;
  final bool isFirst;
  final bool isLast;
  const _TimelineRail({
    required this.dotColor,
    required this.isFirst,
    required this.isLast,
  });

  static const double _railWidth = 18;
  static const double _dotSize = 12;
  static const double _stubHeight = 6;
  static const double _lineThickness = 2;

  @override
  Widget build(BuildContext context) {
    final lineColor = AppColors.borderColor(context);
    return SizedBox(
      width: _railWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Stub above the dot — connects to the previous entry's tail.
          SizedBox(
            height: _stubHeight,
            width: _lineThickness,
            child: isFirst
                ? const SizedBox.shrink()
                : ColoredBox(color: lineColor),
          ),
          // The dot itself, in the actor's group colour.
          Container(
            width: _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          // Continuation tail — fills the remaining row height down to the
          // next entry's stub, except on the last row where it's hidden so
          // the line doesn't dangle past the final dot.
          Expanded(
            child: isLast
                ? const SizedBox.shrink()
                : SizedBox(
                    width: _lineThickness,
                    child: ColoredBox(color: lineColor),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Pill that names the expense an activity entry refers to. Surfaced under
/// the activity message when the kind is one of the expense_* edit kinds
/// whose description ("changed who paid", "updated the date", …) doesn't
/// already inline the expense reason. Keeps the user from having to guess
/// "edited what?" — common request once a group has more than a handful
/// of expenses.
class _ExpenseRefChip extends StatelessWidget {
  final String reason;
  final double amount;
  const _ExpenseRefChip({required this.reason, required this.amount});

  @override
  Widget build(BuildContext context) {
    final hasReason = reason.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppIcons.receipt_long_rounded,
            size: 12,
            color: AppColors.textTertiary(context),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              hasReason ? reason : context.l10nText('Expense'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (amount > 0) ...[
            const SizedBox(width: 6),
            Text(
              '· ${_formatEtb(amount, context)}',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
