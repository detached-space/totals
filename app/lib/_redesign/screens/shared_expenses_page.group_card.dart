part of 'shared_expenses_page.dart';

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
    final isPending =
        group.status == SharedExpenseGroupStatus.pendingApproval;
    final isLocalOnly =
        group.status == SharedExpenseGroupStatus.localOnly;
    final isJustYou = group.memberCount <= 1;
    final canCopyInvite = !isPending && !isLocalOnly;
    final theTitleStyle = theme.textTheme.titleSmall?.copyWith(
      color: AppColors.textPrimary(context),
      fontWeight: FontWeight.w800,
      fontSize: 15,
    );

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: isPending ? null : onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ───── Title row ─────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theTitleStyle,
                        ),
                        if (isPending) ...[
                          const SizedBox(height: 4),
                          Text(
                            isJustYou
                                ? context.l10nText('just you')
                                : group.memberCount == 1
                                    ? context.l10nText('1 member')
                                    : '${group.memberCount} ${context.l10nText('members')}',
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isPending) ...[
                    _CopyInvitePillButton(onTap: onCopyInvite),
                    const SizedBox(width: 8),
                    _StatusChip(
                      label: context.l10nText('Pending approval'),
                      color: AppColors.amber,
                    ),
                  ] else ...[
                    _StatusChip(
                      label: context.l10nText('Synced'),
                      color: AppColors.incomeSuccess,
                    ),
                    if (canCopyInvite) ...[
                      const SizedBox(width: 2),
                      _GroupCardKebabMenu(onCopyInvite: onCopyInvite),
                    ],
                  ],
                ],
              ),
              // ───── Avatars below title (synced only, multi-member) ─────
              if (!isPending && !isJustYou) ...[
                const SizedBox(height: 10),
                _GroupCardMemberAvatars(
                  group: group,
                  myPublicKey: myPublicKey,
                ),
              ],
              // ───── Body: balance + counterparty + bottom-right chevron ─
              if (!isPending) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _GroupCardBody(
                        group: group,
                        myPublicKey: myPublicKey,
                        isPending: false,
                        isJustYou: isJustYou,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: Center(
                        child: Icon(
                          AppIcons.chevron_right,
                          size: 14,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // ───── Cancel request (pending, full width danger) ─────
              if (isPending) ...[
                const SizedBox(height: 14),
                _CancelRequestButton(
                  armed: _cancelArmed,
                  onTap: _onCancelTap,
                ),
              ],
              // ───── Pending approvals from others ─────
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

/// Inline pill-style Copy invite shown next to the Pending approval chip
/// in the pending card title row. The standalone bottom button kept its
/// outline for the synced card; this is a tighter sibling for the right
/// shoulder of the pending card.
class _CopyInvitePillButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CopyInvitePillButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(AppIcons.copy, size: 11),
        label: Text(context.l10nText('Copy invite')),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary(context),
          side: BorderSide(color: AppColors.borderColor(context)),
          minimumSize: const Size(0, 26),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          textStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _GroupCardMemberAvatars extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  const _GroupCardMemberAvatars({
    required this.group,
    required this.myPublicKey,
  });

  @override
  Widget build(BuildContext context) {
    final entries = group.members
        .where((m) => m.devicePublicKey.isNotEmpty)
        .toList()
      ..sort((a, b) {
        if (a.devicePublicKey == myPublicKey) return -1;
        if (b.devicePublicKey == myPublicKey) return 1;
        final an = group
            .displayNameFor(myPublicKey, a.devicePublicKey)
            .toLowerCase();
        final bn = group
            .displayNameFor(myPublicKey, b.devicePublicKey)
            .toLowerCase();
        return an.compareTo(bn);
      });
    const maxVisible = 2;
    final visible = entries.take(maxVisible).toList();
    final overflow = entries.length - visible.length;
    const avatarSize = 22.0;
    const overlap = 8.0;
    final slotCount = visible.length + (overflow > 0 ? 1 : 0);
    final stackWidth =
        avatarSize + (slotCount - 1) * (avatarSize - overlap);
    final borderColor = AppColors.cardColor(context);
    return SizedBox(
      width: stackWidth,
      height: avatarSize,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * (avatarSize - overlap),
              child: _AvatarCircle(
                size: avatarSize,
                color: Color(
                  memberColorFor(group, visible[i].devicePublicKey),
                ),
                text: _initialFor(
                  group.displayNameFor(
                    myPublicKey,
                    visible[i].devicePublicKey,
                  ),
                ),
                borderColor: borderColor,
                fontSize: 10,
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * (avatarSize - overlap),
              child: _AvatarCircle(
                size: avatarSize,
                color: AppColors.textTertiary(context),
                text: '+$overflow',
                borderColor: borderColor,
                fontSize: 9,
              ),
            ),
        ],
      ),
    );
  }

  static String _initialFor(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first).toUpperCase();
  }
}

class _GroupCardBody extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final bool isPending;
  final bool isJustYou;

  const _GroupCardBody({
    required this.group,
    required this.myPublicKey,
    required this.isPending,
    required this.isJustYou,
  });

  @override
  Widget build(BuildContext context) {
    if (isPending) {
      return Text(
        context.l10nText('Waiting for someone to send the key…'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    if (isJustYou) {
      return Text(
        context.l10nText('No expenses yet'),
        style: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final balances = computeBalancesFor(group);
    final myBalance = balances[myPublicKey] ?? 0;
    if (myBalance.abs() < 0.5) {
      return Text(
        context.l10nText('All settled'),
        style: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return _GroupCardBalanceBlock(
      group: group,
      myPublicKey: myPublicKey,
      myBalance: myBalance,
    );
  }
}

class _GroupCardBalanceBlock extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final double myBalance;
  const _GroupCardBalanceBlock({
    required this.group,
    required this.myPublicKey,
    required this.myBalance,
  });

  @override
  Widget build(BuildContext context) {
    final isOwed = myBalance > 0;
    final amount = _formatEtb(myBalance.abs(), context);
    final balanceText = context
        .l10n(
          isOwed ? 'shared.youAreOwedAmount' : 'shared.youOweAmount',
          isOwed ? "you're owed {amount}" : 'you owe {amount}',
        )
        .replaceFirst('{amount}', amount);
    final balanceColor = isOwed ? AppColors.incomeSuccess : AppColors.red;
    final plan = originalDebtPlanFor(group);
    SettlementDebt? topDebt;
    for (final d in plan.debts) {
      if (d.from != myPublicKey && d.to != myPublicKey) continue;
      if (topDebt == null || d.amount > topDebt.amount) topDebt = d;
    }
    final counterpartyPk = topDebt == null
        ? null
        : topDebt.from == myPublicKey
            ? topDebt.to
            : topDebt.from;
    final iAmDebtor = topDebt != null && topDebt.from == myPublicKey;
    final counterpartyName = counterpartyPk == null
        ? null
        : group.displayNameFor(myPublicKey, counterpartyPk);
    final counterpartyColor = counterpartyPk == null
        ? AppColors.textSecondary(context)
        : Color(memberColorFor(group, counterpartyPk));
    final relative = _localizedShortRelative(
      context,
      _lastGroupEventTimestamp(group),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          balanceText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: balanceColor,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (counterpartyName != null) ...[
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: iAmDebtor
                      ? '${context.l10nText('to')} '
                      : '${context.l10nText('from')} ',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: counterpartyName,
                  style: TextStyle(
                    color: counterpartyColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: ' · $relative',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

class _CancelRequestButton extends StatelessWidget {
  final bool armed;
  final VoidCallback onTap;
  const _CancelRequestButton({required this.armed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const danger = Color(0xFFBE123C);
    final fg = armed ? AppColors.white : danger;
    final bg = armed ? danger : Colors.transparent;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          backgroundColor: bg,
          side: BorderSide(
            color: armed ? danger : danger.withValues(alpha: 0.55),
          ),
          minimumSize: const Size.fromHeight(40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          armed
              ? context.l10nText('Tap again to confirm')
              : context.l10nText('Cancel request'),
        ),
      ),
    );
  }
}

/// Three-dot kebab on the right shoulder of synced cards. Houses
/// Copy invite (previously a bottom-of-card button) so the card has
/// fewer visible affordances and the tap target lives next to the
/// status pill where the user expects per-card actions.
///
/// PopupMenuButton wraps an IconButton internally, whose default
/// MaterialTapTargetSize.padded inflates the touch area to 48x48 even
/// when the icon is small. We override that via a Theme so the button
/// shrinks to ~26 px and lines up with the Synced chip next to it.
/// PopupMenuButton handles its own gesture arena, beating the parent
/// card's InkWell — no manual showMenu plumbing needed.
class _GroupCardKebabMenu extends StatelessWidget {
  final VoidCallback onCopyInvite;
  const _GroupCardKebabMenu({required this.onCopyInvite});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: Theme(
        data: Theme.of(context).copyWith(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: PopupMenuButton<String>(
          tooltip: context.l10nText('More options'),
          icon: Icon(
            AppIcons.more_vert,
            size: 16,
            color: AppColors.textTertiary(context),
          ),
          iconSize: 16,
          padding: EdgeInsets.zero,
          splashRadius: 16,
          offset: const Offset(0, 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          constraints: const BoxConstraints(minWidth: 160),
          onSelected: (value) {
            if (value == 'copy_invite') onCopyInvite();
          },
          itemBuilder: (menuContext) => [
            PopupMenuItem<String>(
              value: 'copy_invite',
              height: 40,
              child: Row(
                children: [
                  Icon(
                    AppIcons.share_outline,
                    size: 16,
                    color: AppColors.textSecondary(menuContext),
                  ),
                  const SizedBox(width: 10),
                  // itemBuilder fires from a tap handler (showButtonMenu →
                  // handleTap), NOT during a build pass. l10nText uses
                  // context.watch under the hood, which throws outside build.
                  // Use the read-only variant here.
                  Text(menuContext.l10nTextRead('Share invite')),
                ],
              ),
            ),
          ],
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
      height: 26,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
