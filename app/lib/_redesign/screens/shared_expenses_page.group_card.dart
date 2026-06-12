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

