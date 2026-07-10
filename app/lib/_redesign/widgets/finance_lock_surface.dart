import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';

/// The side-effect-free visual shared by the startup and interactive lock
/// screens.
class FinanceLockSurface extends StatefulWidget {
  const FinanceLockSurface({
    super.key,
    required this.statusText,
    this.onTap,
    this.unlockPromptText,
    this.showProgressIndicator = false,
  });

  final String statusText;
  final VoidCallback? onTap;
  final String? unlockPromptText;
  final bool showProgressIndicator;

  @override
  State<FinanceLockSurface> createState() => _FinanceLockSurfaceState();
}

class _FinanceLockSurfaceState extends State<FinanceLockSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1, end: 1.08).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _glowAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryLight.withValues(
                                alpha: _glowAnimation.value * 0.18,
                              ),
                              blurRadius: 28 + (_glowAnimation.value * 14),
                              spreadRadius: _glowAnimation.value * 6,
                            ),
                          ],
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: Image.asset(
                    'assets/images/logo-text.png',
                    width: 120,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  liveRegion: true,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      widget.statusText,
                      key: ValueKey(widget.statusText),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 60),
                if (widget.unlockPromptText case final promptText?)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          AppIcons.fingerprint_rounded,
                          size: 18,
                          color: AppColors.primaryDark,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          promptText,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (widget.showProgressIndicator)
                  const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primaryLight,
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
