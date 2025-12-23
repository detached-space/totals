import 'package:flutter/material.dart';

class CategoryFilterButton extends StatelessWidget {
  final String label;
  final int selectedCount;
  final VoidCallback onTap;
  final IconData icon;

  const CategoryFilterButton({
    super.key,
    required this.label,
    required this.selectedCount,
    required this.onTap,
    this.icon = Icons.tune_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = selectedCount > 0;
    final borderColor = isActive
        ? theme.colorScheme.primary.withOpacity(0.35)
        : theme.colorScheme.onSurfaceVariant.withOpacity(0.2);
    final background = isActive
        ? theme.colorScheme.primary.withOpacity(0.12)
        : theme.colorScheme.surfaceVariant.withOpacity(0.3);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color:
                    isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$selectedCount',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CategoryFilterIconButton extends StatelessWidget {
  final IconData icon;
  final int selectedCount;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? iconColor;

  const CategoryFilterIconButton({
    super.key,
    required this.icon,
    required this.selectedCount,
    required this.onTap,
    this.tooltip,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = selectedCount > 0;
    final borderColor = isActive
        ? theme.colorScheme.primary.withOpacity(0.35)
        : theme.colorScheme.onSurfaceVariant.withOpacity(0.2);
    final background = isActive
        ? theme.colorScheme.primary.withOpacity(0.12)
        : theme.colorScheme.surfaceVariant.withOpacity(0.3);
    final resolvedIconColor = iconColor == null
        ? (isActive
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant)
        : (isActive ? iconColor! : iconColor!.withOpacity(0.7));

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: resolvedIconColor,
                ),
              ),
              if (isActive)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      '$selectedCount',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (tooltip == null) {
      return button;
    }

    return Tooltip(
      message: tooltip!,
      child: button,
    );
  }
}
