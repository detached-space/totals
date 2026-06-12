part of 'shared_expenses_page.dart';

// ============================================================================
// iOS-styled modal shell + form atoms.
// Match the iOS web-view styling pixel-for-pixel:
//   - Modal bg: --bg-dark (page color, NOT card white)
//   - 24px corner radius top, 24px padding all sides
//   - Handle: 36×4 px borderColor 2px-radius, 20px below
//   - Form labels: 13px / w600 / UPPERCASE / 0.5px letter-spacing / textSecondary
//   - Form inputs: 14/16 padding, 12px radius, bg = cardColor, 1px border
//   - Submit: linear gradient #6366F1 → #818CF8, 16px / w600, 12px radius
//   - Shared chip: 5/10 padding, 999px radius, bg cardColor, border borderColor
//     Active: primaryLight border + rgba(99,102,241,0.08) bg
// ============================================================================

const Color _iosPrimary = Color(0xFF6366F1);
const Color _iosPrimaryLight = Color(0xFF818CF8);
const Color _iosNegative = Color(0xFFEF4444);

class _IosModalShell extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget> footer;
  final Widget? titleWidget;
  final bool closeEnabled;
  const _IosModalShell({
    required this.title,
    required this.children,
    this.footer = const [],
    this.titleWidget,
    this.closeEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.background(context);
    final cardColor = AppColors.cardColor(context);
    final textPrimary = AppColors.textPrimary(context);
    final borderColor = AppColors.borderColor(context);
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final bottomSafeArea = mediaQuery.viewPadding.bottom;
    final keyboardLiftBuffer = keyboardInset > 0 ? 28.0 : 0.0;
    final hasFooter = footer.isNotEmpty;
    final actionBottomGap = keyboardInset > 0
        ? 4.0
        : (mediaQuery.size.height * 0.014).clamp(8.0, 14.0);
    final actionTopGap = keyboardInset > 0 ? 12.0 : 20.0;
    final formBottomPadding = hasFooter
        ? (keyboardInset > 0 ? 8.0 : 4.0)
        : (keyboardInset > 0 ? 16.0 : 24.0);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset + keyboardLiftBuffer),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          color: bg,
          constraints: BoxConstraints(
            maxHeight: mediaQuery.size.height * 0.9,
          ),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxHeight = constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : mediaQuery.size.height * 0.9;

                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            24,
                            0,
                            24,
                            formBottomPadding,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Handle — 36×4, borderColor, 2px radius, 20px below
                              Center(
                                child: Container(
                                  margin: const EdgeInsets.only(
                                    top: 10,
                                    bottom: 20,
                                  ),
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: borderColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              // Header — title left, close button right
                              Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: titleWidget ??
                                          Text(
                                            context.l10nText(title),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w600,
                                              color: textPrimary,
                                            ),
                                          ),
                                    ),
                                    // 32×32 rounded-square close button (matches iOS)
                                    Opacity(
                                      opacity: closeEnabled ? 1 : 0.45,
                                      child: InkWell(
                                        onTap: closeEnabled
                                            ? () => Navigator.of(context).pop()
                                            : null,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: cardColor,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            Icons.close,
                                            size: 16,
                                            color: textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ...children,
                            ],
                          ),
                        ),
                      ),
                      if (hasFooter) ...[
                        SizedBox(height: actionTopGap),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            0,
                            24,
                            bottomSafeArea + actionBottomGap,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: footer,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _IosFormGroup extends StatelessWidget {
  final String label;
  final Widget child;
  final Widget? labelTrailing;
  const _IosFormGroup({
    required this.label,
    required this.child,
    this.labelTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10nText(label).toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                if (labelTrailing != null) labelTrailing!,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _IosFormInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? hint;
  final int? maxLength;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  const _IosFormInput({
    required this.controller,
    this.focusNode,
    this.autofocus = false,
    this.hint,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardColor(context);
    final borderColor = AppColors.borderColor(context);
    final textPrimary = AppColors.textPrimary(context);
    final textMuted = AppColors.textTertiary(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      style: TextStyle(fontSize: 16, color: textPrimary),
      decoration: InputDecoration(
        hintText: hint == null ? null : context.l10nText(hint!),
        hintStyle: TextStyle(color: textMuted, fontSize: 16),
        filled: true,
        fillColor: cardColor,
        counterText: '',
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _iosPrimary, width: 2),
        ),
      ),
    );
  }
}

class _IosCheckboxRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _IosCheckboxRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardColor(context);
    final borderColor = AppColors.borderColor(context);
    final textPrimary = AppColors.textPrimary(context);

    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10nText(title),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Checkbox(
              value: value,
              onChanged: (checked) => onChanged(checked ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _IosValueRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showChevron;

  const _IosValueRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardColor(context);
    final borderColor = AppColors.borderColor(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primaryLight),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 10),
              Icon(
                AppIcons.chevron_right,
                size: 17,
                color: AppColors.textTertiary(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IosSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const _IosSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(color: AppColors.textPrimary(context), fontSize: 15),
      decoration: InputDecoration(
        hintText: context.l10nText(hint),
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        prefixIcon: Icon(
          AppIcons.search,
          size: 18,
          color: AppColors.textTertiary(context),
        ),
        filled: true,
        fillColor: AppColors.cardColor(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _iosPrimary, width: 2),
        ),
      ),
    );
  }
}

class _IosAmountRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  const _IosAmountRow({
    required this.controller,
    this.focusNode,
    this.autofocus = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textMuted = AppColors.textTertiary(context);
    final borderColor = AppColors.borderColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: borderColor, width: 1),
          ),
        ),
        padding: const EdgeInsets.only(top: 12, bottom: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.55,
              ),
              child: IntrinsicWidth(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  textAlign: TextAlign.center,
                  autofocus: autofocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '0',
                    hintStyle: TextStyle(
                      color: textMuted.withValues(alpha: 0.45),
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              context.l10nText('ETB'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IosSharedMemberSelector extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final List<String> memberKeys;
  final bool Function(String publicKey) isSelected;
  final ValueChanged<String> onTap;

  const _IosSharedMemberSelector({
    required this.group,
    required this.myPublicKey,
    required this.memberKeys,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (memberKeys.isEmpty) {
      return Text(
        context.l10nText('No members'),
        style: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: memberKeys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final pk = memberKeys[index];
          return _IosSharedChip(
            label: group.displayNameFor(myPublicKey, pk),
            dotColor: Color(memberColorFor(group, pk)),
            active: isSelected(pk),
            onTap: () => onTap(pk),
          );
        },
      ),
    );
  }
}

class _IosSharedChip extends StatelessWidget {
  final String label;
  final Color dotColor;
  final bool active;
  final VoidCallback onTap;
  const _IosSharedChip({
    required this.label,
    required this.dotColor,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardColor(context);
    final borderColor = AppColors.borderColor(context);
    final textPrimary = AppColors.textPrimary(context);
    final initial = label.trim().isEmpty
        ? '?'
        : String.fromCharCode(label.trim().runes.first).toUpperCase();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 36,
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF6366F1).withValues(alpha: 0.08)
              : cardColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? _iosPrimary : borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IosTextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _IosTextAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          context.l10nText(label),
          style: const TextStyle(
            color: _iosPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _IosFormSubmit extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool enabled;
  final bool isBusy;
  final VoidCallback onTap;
  final double topPadding;
  const _IosFormSubmit({
    required this.label,
    this.icon,
    required this.enabled,
    this.isBusy = false,
    required this.onTap,
    this.topPadding = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Opacity(
        opacity: enabled || isBusy ? 1 : 0.6,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled && !isBusy ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_iosPrimary, _iosPrimaryLight],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBusy) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      context.l10nText(label),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!isBusy && icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(icon, size: 18, color: Colors.white),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IosSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const _IosSecondaryButton({
    required this.label,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final borderColor = AppColors.borderColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: textPrimary),
                const SizedBox(width: 8),
              ],
              Text(
                context.l10nText(label),
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IosDangerButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool armed;
  final VoidCallback? onTap;
  const _IosDangerButton({
    required this.label,
    this.icon,
    required this.armed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.borderColor(context);
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
            decoration: BoxDecoration(
              color: armed ? _iosNegative.withValues(alpha: 0.10) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: armed ? _iosNegative : borderColor,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: _iosNegative),
                  const SizedBox(width: 8),
                ],
                Text(
                  context.l10nText(label),
                  style: const TextStyle(
                    color: _iosNegative,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
