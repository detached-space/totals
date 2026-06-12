part of 'shared_expenses_page.dart';

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
