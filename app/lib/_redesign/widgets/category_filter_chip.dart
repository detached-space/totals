import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/l10n/app_localizations.dart';

class CategoryFilterChip extends StatelessWidget {
  const CategoryFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.flow,
    this.subtleFlowTint = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? flow;
  final bool subtleFlowTint;

  @override
  Widget build(BuildContext context) {
    final normalizedFlow = flow?.trim().toLowerCase();
    final accent = subtleFlowTint
        ? switch (normalizedFlow) {
            'income' => AppColors.incomeSuccess,
            'expense' => AppColors.red,
            _ => null,
          }
        : null;
    final isDark = AppColors.isDark(context);
    final backgroundColor = accent == null
        ? selected
            ? AppColors.primaryDark
            : AppColors.surfaceColor(context)
        : accent.withValues(
            alpha: selected
                ? isDark
                    ? 0.24
                    : 0.16
                : isDark
                    ? 0.14
                    : 0.08,
          );
    final borderColor = accent == null
        ? selected
            ? AppColors.primaryDark
            : AppColors.borderColor(context)
        : accent.withValues(alpha: selected ? 0.7 : 0.35);
    final foregroundColor = accent == null
        ? selected
            ? AppColors.white
            : AppColors.textSecondary(context)
        : _flowForegroundColor(normalizedFlow!, isDark: isDark);
    final localizedLabel = context.l10nText(label);
    final flowLabel = switch (normalizedFlow) {
      'income' => context.l10nText('Income'),
      'expense' => context.l10nText('Expense'),
      _ => null,
    };

    return Semantics(
      button: true,
      selected: selected,
      label: flowLabel == null
          ? localizedLabel
          : '$localizedLabel, $flowLabel ${context.l10nText('category')}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            localizedLabel,
            style: TextStyle(
              color: foregroundColor,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Color _flowForegroundColor(String flow, {required bool isDark}) {
    if (flow == 'income') {
      return isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
    }
    return isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
  }
}
