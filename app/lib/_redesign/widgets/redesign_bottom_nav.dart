import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

class RedesignBottomNav extends StatefulWidget {
  static const int _tabCount = 5;

  final int currentIndex;
  final PageController pageController;
  final ValueChanged<int> onTap;
  final VoidCallback? onMoneyLongPress;
  final VoidCallback? onSharedLongPress;
  final ValueChanged<Rect>? onProfileLongPressAt;

  const RedesignBottomNav({
    super.key,
    required this.currentIndex,
    required this.pageController,
    required this.onTap,
    this.onMoneyLongPress,
    this.onSharedLongPress,
    this.onProfileLongPressAt,
  });

  @override
  State<RedesignBottomNav> createState() => _RedesignBottomNavState();
}

class _RedesignBottomNavState extends State<RedesignBottomNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _selectionController;
  late Animation<double> _selectionAnimation;
  ValueNotifier<bool>? _pageScrollingNotifier;

  double get _targetIndex =>
      widget.currentIndex.clamp(0, RedesignBottomNav._tabCount - 1).toDouble();

  @override
  void initState() {
    super.initState();
    _selectionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _selectionAnimation = AlwaysStoppedAnimation<double>(_targetIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _attachPageScrollingListener();
    });
  }

  @override
  void didUpdateWidget(covariant RedesignBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController != widget.pageController) {
      _detachPageScrollingListener();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _attachPageScrollingListener();
      });
    }
    if (oldWidget.currentIndex == widget.currentIndex) return;

    if (_isPageScrolling) {
      _selectionController.stop();
      _selectionAnimation = AlwaysStoppedAnimation<double>(
        _resolveControllerPage(),
      );
      return;
    }

    final currentPosition = _selectionAnimation.value;
    _selectionController.stop();
    _selectionController.reset();
    _selectionAnimation = Tween<double>(
      begin: currentPosition,
      end: _targetIndex,
    ).animate(
      CurvedAnimation(
        parent: _selectionController,
        curve: Curves.easeOutCubic,
      ),
    );
    _selectionController.forward();
  }

  @override
  void dispose() {
    _detachPageScrollingListener();
    _selectionController.dispose();
    super.dispose();
  }

  bool get _isPageScrolling => _pageScrollingNotifier?.value ?? false;

  double _resolveControllerPage() {
    if (!widget.pageController.hasClients) return _targetIndex;
    final page = widget.pageController.page;
    if (page == null || !page.isFinite) return _targetIndex;
    return page
        .clamp(0.0, (RedesignBottomNav._tabCount - 1).toDouble())
        .toDouble();
  }

  void _attachPageScrollingListener() {
    if (!widget.pageController.hasClients) return;
    final notifier = widget.pageController.position.isScrollingNotifier;
    if (identical(_pageScrollingNotifier, notifier)) return;

    _detachPageScrollingListener();
    _pageScrollingNotifier = notifier;
    notifier.addListener(_handlePageScrollingChanged);
  }

  void _detachPageScrollingListener() {
    _pageScrollingNotifier?.removeListener(_handlePageScrollingChanged);
    _pageScrollingNotifier = null;
  }

  void _handlePageScrollingChanged() {
    if (_isPageScrolling) {
      _selectionController.stop();
      return;
    }

    _selectionController.stop();
    setState(() {
      _selectionAnimation = AlwaysStoppedAnimation<double>(
        _resolveControllerPage(),
      );
    });
  }

  double _resolveSelectionPosition() {
    if (_pageScrollingNotifier == null && widget.pageController.hasClients) {
      _attachPageScrollingListener();
    }
    // Follow the finger while the PageView moves; use the independent tween
    // for direct jumps, where PageController has no intermediate positions.
    return _isPageScrolling
        ? _resolveControllerPage()
        : _selectionAnimation.value;
  }

  double _selectionProgress(double page, int index) {
    return (1 - (page - index).abs()).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    const indicatorSize = 4.0;
    final items = [
      (
        label: context.l10n('nav.home', 'Home'),
        activeIcon: AppIcons.home_filled,
        inactiveIcon: AppIcons.home_outlined,
        onLongPress: null,
        onLongPressAt: null,
      ),
      (
        label: context.l10n('nav.money', 'Money'),
        activeIcon: AppIcons.account_balance_wallet,
        inactiveIcon: AppIcons.account_balance_wallet_outlined,
        onLongPress: widget.onMoneyLongPress,
        onLongPressAt: null,
      ),
      (
        label: context.l10n('nav.budget', 'Budget'),
        activeIcon: AppIcons.savings,
        inactiveIcon: AppIcons.savings_outlined,
        onLongPress: null,
        onLongPressAt: null,
      ),
      (
        label: context.l10n('nav.shared', 'Shared'),
        activeIcon: AppIcons.group,
        inactiveIcon: AppIcons.group_outlined,
        onLongPress: widget.onSharedLongPress,
        onLongPressAt: null,
      ),
      (
        label: context.l10n('nav.you', 'You'),
        activeIcon: AppIcons.person,
        inactiveIcon: AppIcons.person_outline,
        onLongPress: null,
        onLongPressAt: widget.onProfileLongPressAt,
      ),
    ];

    return AnimatedBuilder(
      animation: widget.pageController,
      builder: (context, child) {
        return AnimatedBuilder(
          animation: _selectionController,
          builder: (context, child) {
            final page = _resolveSelectionPosition();

            return SafeArea(
              top: false,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.cardColor(context),
                  border: Border(
                      top: BorderSide(color: AppColors.borderColor(context))),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = constraints.maxWidth / items.length;
                    final indicatorLeft =
                        (page * itemWidth) + ((itemWidth - indicatorSize) / 2);

                    return Stack(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (var index = 0; index < items.length; index++)
                              _NavItem(
                                label: items[index].label,
                                activeIcon: items[index].activeIcon,
                                inactiveIcon: items[index].inactiveIcon,
                                selectionProgress:
                                    _selectionProgress(page, index),
                                onTap: () => widget.onTap(index),
                                onLongPress: items[index].onLongPress,
                                onLongPressAt: items[index].onLongPressAt,
                              ),
                          ],
                        ),
                        Positioned(
                          left: indicatorLeft,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              key: const ValueKey(
                                'bottom-nav-selection-indicator',
                              ),
                              width: indicatorSize,
                              height: indicatorSize,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _NavItem extends StatefulWidget {
  final String label;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final double selectionProgress;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<Rect>? onLongPressAt;

  const _NavItem({
    required this.label,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.selectionProgress,
    required this.onTap,
    this.onLongPress,
    this.onLongPressAt,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.90)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.90, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 65,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final emphasis = Curves.easeOutCubic.transform(widget.selectionProgress);
    const iconSize = 22.0;
    const labelSize = 11.0;
    const indicatorSize = 4.0;
    final color = Color.lerp(
      AppColors.textTertiary(context),
      AppColors.primaryLight,
      emphasis,
    )!;
    final labelOpacity = lerpDouble(0.72, 1, emphasis)!;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        onLongPress: widget.onLongPress ??
            (widget.onLongPressAt == null
                ? null
                : () {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final topLeft = box.localToGlobal(Offset.zero);
                    widget.onLongPressAt!(Rect.fromLTWH(
                      topLeft.dx,
                      topLeft.dy,
                      box.size.width,
                      box.size.height,
                    ));
                  }),
        child: ScaleTransition(
          scale: _scale,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: 1 - emphasis,
                        child: Icon(
                          widget.inactiveIcon,
                          size: iconSize,
                          color: color,
                        ),
                      ),
                      Opacity(
                        opacity: emphasis,
                        child: Icon(
                          widget.activeIcon,
                          size: iconSize,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Opacity(
                  opacity: labelOpacity,
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: labelSize,
                      fontWeight:
                          emphasis >= 0.6 ? FontWeight.w600 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                const SizedBox(
                  width: indicatorSize,
                  height: indicatorSize,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
