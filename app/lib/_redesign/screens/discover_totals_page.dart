import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/ios_setup_guide_page.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

/// The guided walkthroughs, gathered in one place instead of scattered through
/// Settings. Both entries open the same clip-and-action sheet.
class DiscoverTotalsPage extends StatelessWidget {
  const DiscoverTotalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(AppIcons.arrow_back_rounded,
              color: AppColors.textPrimary(context)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          context.l10nText('Discover Totals'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            context.l10nText(
              'Short walkthroughs for the parts of Totals that need setting up '
              'outside the app.',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _DiscoverTile(
            icon: AppIcons.bolt_rounded,
            iconColor: AppColors.amber,
            title: context.l10nText('Set up SMS automation'),
            subtitle: context.l10nText(
              'Install the Shortcut and wire the Messages automation',
            ),
            onTap: () => openIosSetupGuide(context),
          ),
          const SizedBox(height: 12),
          _DiscoverTile(
            icon: AppIcons.download_rounded,
            iconColor: AppColors.blue,
            title: context.l10nText('Import from backup'),
            subtitle: context.l10nText(
              'Bring your data over from the Scriptable version',
            ),
            onTap: () => openIosImportGuide(context),
          ),
        ],
      ),
    );
  }
}

class _DiscoverTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DiscoverTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.chevron_right,
                  size: 18, color: AppColors.textTertiary(context)),
            ],
          ),
        ),
      ),
    );
  }
}
