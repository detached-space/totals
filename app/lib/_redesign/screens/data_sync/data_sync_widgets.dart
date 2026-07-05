import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/services/data_sync/sync_models.dart';

/// Shared building blocks for the Data Sync screens. Public counterparts of the
/// file-private widgets used elsewhere in the redesign, matching the same
/// visual language (rounded cards, list tiles, bottom sheets).

class DataSyncSectionHeader extends StatelessWidget {
  final String label;
  const DataSyncSectionHeader(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class DataSyncCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const DataSyncCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: child,
    );
  }
}

class DataSyncTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  const DataSyncTile({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.primaryLight;
    return DataSyncCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (showChevron)
              Icon(
                AppIcons.chevron_right_rounded,
                color: AppColors.textTertiary(context),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class DataSyncStatusPill extends StatelessWidget {
  final String status;
  const DataSyncStatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final (color, label) = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  (Color, String) _styleFor(String status) {
    switch (status) {
      case SyncOutboxStatus.sent:
      case 'ok':
        return (AppColors.incomeSuccess, 'Sent');
      case SyncOutboxStatus.pending:
        return (AppColors.amber, 'Pending');
      case SyncOutboxStatus.sending:
        return (AppColors.primaryLight, 'Sending');
      case 'stopped':
        return (AppColors.slate500, 'Stopped');
      case SyncOutboxStatus.dead:
      case SyncOutboxStatus.failed:
      case 'error':
        return (AppColors.red, 'Failed');
      default:
        return (AppColors.slate500, status);
    }
  }
}

class DataSyncTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;

  const DataSyncTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            helperText: helper,
            helperMaxLines: 3,
            filled: true,
            fillColor: AppColors.surfaceColor(context),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.borderColor(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryLight),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.borderColor(context)),
            ),
          ),
        ),
      ],
    );
  }
}

class DataSyncPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const DataSyncPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Present [child] in a rounded, scrollable, keyboard-aware bottom sheet with a
/// drag handle, title, and close button.
Future<T?> showDataSyncSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  bool scrollable = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final mediaQuery = MediaQuery.of(ctx);
      final keyboardInset = mediaQuery.viewInsets.bottom;
      final bottomSafeArea = mediaQuery.viewPadding.bottom;
      final keyboardLiftBuffer = keyboardInset > 0 ? 28.0 : 0.0;
      final contentBottomPadding =
          scrollable ? bottomSafeArea + (keyboardInset > 0 ? 16.0 : 20.0) : 0.0;

      return AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset + keyboardLiftBuffer),
        child: SafeArea(
          top: false,
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : mediaQuery.size.height;
              final sheetHeightLimit = mediaQuery.size.height * 0.9;
              final maxHeight = availableHeight < sheetHeightLimit
                  ? availableHeight
                  : sheetHeightLimit;

              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardColor(ctx),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: AppColors.slate400,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: AppColors.textPrimary(ctx),
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: Icon(
                              AppIcons.close_rounded,
                              color: AppColors.textTertiary(ctx),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (scrollable)
                        Flexible(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding:
                                EdgeInsets.only(bottom: contentBottomPadding),
                            child: child,
                          ),
                        )
                      else
                        Flexible(child: child),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
