import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/_redesign/widgets/feature_preview_sheet.dart';
import 'package:totals/l10n/app_localizations.dart';

class FeatureDiscoveryPage extends StatelessWidget {
  const FeatureDiscoveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previews = totalsFeaturePreviews;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.background(context),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            AppIcons.arrow_back_rounded,
            color: AppColors.textPrimary(context),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          context.l10nText('Discover Totals'),
          style: theme.textTheme.titleLarge?.copyWith(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          for (var index = 0; index < previews.length; index++) ...[
            _FeatureDiscoveryTile(
              item: previews[index],
              onTap: () => showFeaturePreviewSheet(
                context,
                items: previews,
                initialIndex: index,
              ),
            ),
            if (index < previews.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _FeatureDiscoveryTile extends StatelessWidget {
  const _FeatureDiscoveryTile({
    required this.item,
    required this.onTap,
  });

  final FeaturePreviewItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      key: ValueKey<String>('feature-discovery-card-${item.videoCacheKey}'),
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10nText(item.title),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.l10nText(item.summary),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                AppIcons.chevron_right_rounded,
                color: AppColors.textTertiary(context),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
