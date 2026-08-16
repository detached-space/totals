import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

void showCreditDebitBreakdownSheet(
  BuildContext context, {
  required double totalCredit,
  required double totalDebit,
  required double transferIn,
  required double transferOut,
  required double feesAndVat,
  required double unreconciledAdjustment,
  required int reconciliationMismatchCount,
  VoidCallback? onUnreconciledTap,
  required bool showAmounts,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CreditDebitBreakdownSheet(
      totalCredit: totalCredit,
      totalDebit: totalDebit,
      transferIn: transferIn,
      transferOut: transferOut,
      feesAndVat: feesAndVat,
      unreconciledAdjustment: unreconciledAdjustment,
      reconciliationMismatchCount: reconciliationMismatchCount,
      onUnreconciledTap: onUnreconciledTap,
      showAmounts: showAmounts,
    ),
  );
}

class _CreditDebitBreakdownSheet extends StatelessWidget {
  final double totalCredit;
  final double totalDebit;
  final double transferIn;
  final double transferOut;
  final double feesAndVat;
  final double unreconciledAdjustment;
  final int reconciliationMismatchCount;
  final VoidCallback? onUnreconciledTap;
  final bool showAmounts;

  const _CreditDebitBreakdownSheet({
    required this.totalCredit,
    required this.totalDebit,
    required this.transferIn,
    required this.transferOut,
    required this.feesAndVat,
    required this.unreconciledAdjustment,
    required this.reconciliationMismatchCount,
    this.onUnreconciledTap,
    required this.showAmounts,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final externalDebit = math.max(0.0, totalDebit - feesAndVat);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color:
                        AppColors.textTertiary(context).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10nText('Credit & debit breakdown'),
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      AppIcons.close,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
              Text(
                context.l10nText(
                  'Credit is money that came in. Debit is money that went out. Moving money between your own accounts appears on both sides.',
                ),
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              _FlowBreakdownSection(
                title: 'Money in (credit)',
                color: AppColors.incomeSuccess,
                rows: <_FlowBreakdownRowData>[
                  _FlowBreakdownRowData(
                    'Received from others',
                    'Salary, payments, refunds, or money from another person.',
                    totalCredit,
                  ),
                  _FlowBreakdownRowData(
                    'Moved in from your accounts',
                    'Money you moved here from another account you own.',
                    transferIn,
                  ),
                ],
                total: totalCredit + transferIn,
                totalLabel: 'Total money in',
                showAmounts: showAmounts,
              ),
              const SizedBox(height: 14),
              _FlowBreakdownSection(
                title: 'Money out (debit)',
                color: AppColors.red,
                rows: <_FlowBreakdownRowData>[
                  _FlowBreakdownRowData(
                    'Paid or sent to others',
                    'Purchases, withdrawals, bills, or money sent to someone.',
                    externalDebit,
                  ),
                  _FlowBreakdownRowData(
                    'Moved out to your accounts',
                    'Money you moved from here to another account you own.',
                    transferOut,
                  ),
                  _FlowBreakdownRowData(
                    'Bank fees & VAT',
                    'Charges taken by your bank or wallet.',
                    feesAndVat,
                  ),
                ],
                total: externalDebit + transferOut + feesAndVat,
                totalLabel: 'Total money out',
                showAmounts: showAmounts,
              ),
              if (reconciliationMismatchCount > 0) ...[
                const SizedBox(height: 14),
                _UnreconciledActivityText(
                  adjustment: unreconciledAdjustment,
                  mismatchCount: reconciliationMismatchCount,
                  showAmount: showAmounts,
                  onTap: onUnreconciledTap,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreconciledActivityText extends StatelessWidget {
  final double adjustment;
  final int mismatchCount;
  final bool showAmount;
  final VoidCallback? onTap;

  const _UnreconciledActivityText({
    required this.adjustment,
    required this.mismatchCount,
    required this.showAmount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currencyLabel = context.l10nText('ETB');
    final formatter = NumberFormat('#,##0.00');
    final amountLabel = showAmount
        ? '${adjustment >= 0 ? '+' : '-'}$currencyLabel ${formatter.format(adjustment.abs())}'
        : '$currencyLabel ***';

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10nText('Unreconciled activity'),
                style: const TextStyle(
                  color: AppColors.amber,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              amountLabel,
              style: const TextStyle(
                color: AppColors.amber,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${context.l10nText('Balance checkpoints that did not match')}: $mismatchCount',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
    final tap = onTap;
    if (tap == null) return content;
    return Semantics(
      button: true,
      label: context.l10nText('View unreconciled transactions'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) => tap());
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
        ),
      ),
    );
  }
}

class _FlowBreakdownRowData {
  final String label;
  final String description;
  final double amount;

  const _FlowBreakdownRowData(this.label, this.description, this.amount);
}

class _FlowBreakdownSection extends StatelessWidget {
  final String title;
  final Color color;
  final List<_FlowBreakdownRowData> rows;
  final double total;
  final String totalLabel;
  final bool showAmounts;

  const _FlowBreakdownSection({
    required this.title,
    required this.color,
    required this.rows,
    required this.total,
    required this.totalLabel,
    required this.showAmounts,
  });

  @override
  Widget build(BuildContext context) {
    final currencyLabel = context.l10nText('ETB');
    final formatter = NumberFormat('#,##0.00');
    String amountLabel(double amount) => showAmounts
        ? '$currencyLabel ${formatter.format(amount)}'
        : '$currencyLabel ***';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10nText(title),
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10nText(row.label),
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10nText(row.description),
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  amountLabel(row.amount),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Container(height: 1, color: AppColors.borderColor(context)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10nText(totalLabel),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                amountLabel(total),
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
