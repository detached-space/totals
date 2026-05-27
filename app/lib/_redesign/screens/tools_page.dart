import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/screens/accounts_page.dart';
import 'package:totals/screens/failed_parses_page.dart';
import 'package:totals/screens/verify_payments_page.dart';
import 'package:totals/screens/web_page.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

class RedesignToolsPage extends StatelessWidget {
  const RedesignToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10nText('Tools'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10nText('Handy utilities at your fingertips.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 20),
              _ToolTile(
                icon: AppIcons.dashboard_outlined,
                iconColor: AppColors.primaryLight,
                title: context.l10nText('Web Dashboard'),
                subtitle: context.l10nText('View your finances in a browser'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WebPage()),
                ),
              ),
              _ToolTile(
                icon: AppIcons.account_balance_outlined,
                iconColor: AppColors.blue,
                title: context.l10nText('Quick Accounts'),
                subtitle: context.l10nText('Manage linked bank accounts'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountsPage()),
                ),
              ),
              _ToolTile(
                icon: AppIcons.qr_code_scanner_rounded,
                iconColor: AppColors.incomeSuccess,
                title: context.l10nText('Verify Payments'),
                subtitle:
                    context.l10nText('Scan and verify transaction receipts'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VerifyPaymentsPage()),
                ),
              ),
              _ToolTile(
                icon: AppIcons.sms_outlined,
                iconColor: AppColors.amber,
                title: context.l10nText('Failed Parsings'),
                subtitle: context
                    .l10nText('Review bank transactions without patterns'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FailedParsesPage()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  AppIcons.chevron_right_rounded,
                  color: AppColors.textTertiary(context),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
