import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/models/category.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

/// Shared transaction tile used across all redesign pages.
///
/// Layout matches the money-page "transactions section" style:
///   Left:  bank name  +  category chip
///   Right: amount     +  name (marquee if long)  +  optional timestamp
class TransactionTile extends StatelessWidget {
  final String bank;
  final String category;
  final Category? categoryModel;
  final String? personLabel;
  final ValueChanged<String>? onPersonTap;
  final bool isCategorized;

  /// Whether the transaction is a debit (expense).
  /// Used to pick the category chip color.
  final bool isDebit;

  /// Whether the transaction is a self-transfer (e.g. ATM withdrawal → deposit).
  /// When true the tile is rendered in a faded/muted style.
  final bool isSelfTransfer;

  /// Whether the transaction is categorized as Misc/uncategorized.
  /// When true the tile is rendered faded with a grey chip.
  final bool isMisc;

  /// Whether this transaction is linked to a shared expense.
  final bool isShared;

  /// Whether this transaction is currently being linked to a shared expense.
  final bool isSharing;

  final String amount;
  final Color amountColor;
  final String name;

  /// Optional timestamp line shown below the name.
  final String? timestamp;

  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onCategoryTap;
  final VoidCallback? onLongPress;

  const TransactionTile({
    super.key,
    required this.bank,
    required this.category,
    this.categoryModel,
    this.personLabel,
    this.onPersonTap,
    required this.isCategorized,
    required this.isDebit,
    required this.amount,
    required this.amountColor,
    required this.name,
    this.isSelfTransfer = false,
    this.isMisc = false,
    this.isShared = false,
    this.isSharing = false,
    this.timestamp,
    this.selected = false,
    this.onTap,
    this.onCategoryTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = isSelfTransfer || isMisc;
    final resolvedPersonLabel = personLabel?.trim();

    return Opacity(
      opacity: faded ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryLight.withValues(alpha: 0.08)
              : AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primaryLight
                : AppColors.borderColor(context),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                if (selected) ...[
                  const Icon(
                    AppIcons.check_circle_rounded,
                    size: 20,
                    color: AppColors.primaryLight,
                  ),
                  const SizedBox(width: 10),
                ],
                // Left: bank + category
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bank,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          TransactionCategoryChip(
                            label: category,
                            category: categoryModel,
                            isCategorized: isCategorized,
                            isDebit: isDebit,
                            isSelfTransfer: isSelfTransfer,
                            isMisc: isMisc,
                            onTap: onCategoryTap,
                          ),
                          if (resolvedPersonLabel != null &&
                              resolvedPersonLabel.isNotEmpty)
                            _TransactionPersonChip(
                              label: resolvedPersonLabel,
                              muted: faded,
                              onTap: onPersonTap == null
                                  ? null
                                  : () => onPersonTap!(resolvedPersonLabel),
                            ),
                          if (isSharing)
                            _SharedTransactionChip(
                              label: context.l10nText('Sharing'),
                              color: AppColors.amber,
                            )
                          else if (isShared)
                            _SharedTransactionChip(
                              label: context.l10nText('Shared'),
                              color: AppColors.primaryLight,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Right: amount + name + timestamp
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        amount,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: faded
                              ? AppColors.textTertiary(context)
                              : amountColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TileMarqueeText(
                        text: name,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary(context),
                          letterSpacing: 0.4,
                        ),
                      ),
                      if (timestamp != null && timestamp!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          timestamp!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary(context),
                            fontSize: 10,
                          ),
                        ),
                      ],
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

class _SharedTransactionChip extends StatelessWidget {
  final String label;
  final Color color;

  const _SharedTransactionChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }
}

class _TransactionPersonChip extends StatelessWidget {
  final String label;
  final bool muted;
  final VoidCallback? onTap;

  const _TransactionPersonChip({
    required this.label,
    required this.muted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = muted
        ? AppColors.textTertiary(context)
        : AppColors.textSecondary(context);

    final chip = Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppIcons.person_outline,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chip,
    );
  }
}

// ── Category Chip ───────────────────────────────────────────────────────────

class TransactionCategoryChip extends StatelessWidget {
  final String label;
  final Category? category;
  final bool isCategorized;
  final bool isDebit;
  final bool isSelfTransfer;
  final bool isMisc;
  final VoidCallback? onTap;

  const TransactionCategoryChip({
    super.key,
    required this.label,
    this.category,
    required this.isCategorized,
    required this.isDebit,
    this.isSelfTransfer = false,
    this.isMisc = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final localizedLabel = context.l10nText(label);

    // Self-transfer or Misc: neutral gray filled chip
    if (isSelfTransfer || isMisc) {
      return _maybeWrapPressable(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.textTertiary(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: Text(
              localizedLabel,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ),
      );
    }

    if (isCategorized) {
      final color = _categoryColor();
      return _maybeWrapPressable(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: Text(
              localizedLabel,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ),
      );
    }

    return _maybeWrapPressable(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.textTertiary(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 132),
          child: Text(
            localizedLabel,
            style: TextStyle(
              color: AppColors.isDark(context)
                  ? AppColors.slate400
                  : AppColors.slate700,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ),
    );
  }

  Widget _maybeWrapPressable({
    required Widget child,
  }) {
    if (onTap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }

  Color _categoryColor() {
    final cat = category;
    if (cat == null) {
      return isDebit ? AppColors.red : AppColors.incomeSuccess;
    }
    final explicit =
        _normalizeColorKey(cat.colorKey) ?? _extractColorKey(cat.iconKey);
    if (explicit != null) {
      return _colorFromKey(explicit);
    }
    return _kCategoryColorPalette[_fallbackColorIndex(cat)];
  }

  String? _normalizeColorKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String? _extractColorKey(String? iconKey) {
    if (iconKey == null || iconKey.isEmpty) return null;
    const prefix = 'color:';
    if (!iconKey.startsWith(prefix)) return null;
    final key = iconKey.substring(prefix.length).trim();
    return key.isEmpty ? null : key;
  }

  Color _colorFromKey(String colorKey) {
    return _kCategoryColorByKey[colorKey] ?? _kCategoryColorPalette.first;
  }

  int _fallbackColorIndex(Category cat) {
    final seed = '${cat.flow}:${cat.name.toLowerCase()}';
    int hash = 0;
    for (final code in seed.codeUnits) {
      hash = (hash + code) & 0x7fffffff;
    }
    return hash % _kCategoryColorPalette.length;
  }
}

// ── Truncated Text ──────────────────────────────────────────────────────────

class TileMarqueeText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const TileMarqueeText({super.key, required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }
}

const Map<String, Color> _kCategoryColorByKey = {
  'blue': AppColors.blue,
  'emerald': AppColors.incomeSuccess,
  'amber': AppColors.amber,
  'red': AppColors.red,
  'rose': Color(0xFFFB7185),
  'magenta': Color(0xFFD946EF),
  'violet': Color(0xFF8B5CF6),
  'indigo': Color(0xFF6366F1),
  'teal': Color(0xFF14B8A6),
  'mint': Color(0xFF34D399),
  'orange': Color(0xFFF97316),
  'tangerine': Color(0xFFFF8C42),
  'yellow': Color(0xFFEAB308),
  'cyan': Color(0xFF06B6D4),
  'sky': Color(0xFF0EA5E9),
  'lime': Color(0xFF84CC16),
  'pink': Color(0xFFEC4899),
  'brown': Color(0xFFA16207),
  'gray': Color(0xFF6B7280),
};

const List<Color> _kCategoryColorPalette = [
  AppColors.blue,
  AppColors.incomeSuccess,
  AppColors.amber,
  AppColors.red,
  Color(0xFFFB7185),
  Color(0xFFD946EF),
  Color(0xFF8B5CF6),
  Color(0xFF6366F1),
  Color(0xFF14B8A6),
  Color(0xFF34D399),
  Color(0xFFF97316),
  Color(0xFFFF8C42),
  Color(0xFFEAB308),
  Color(0xFF06B6D4),
  Color(0xFF0EA5E9),
  Color(0xFF84CC16),
  Color(0xFFEC4899),
  Color(0xFFA16207),
  Color(0xFF6B7280),
];
