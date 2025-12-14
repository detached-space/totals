import 'dart:ui';
import 'package:flutter/material.dart';

class CustomBottomNavModern extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNavModern({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = [
      {'icon': Icons.home_outlined, 'filledIcon': Icons.home, 'label': 'Home'},
      {'icon': Icons.analytics_outlined, 'filledIcon': Icons.analytics, 'label': 'Analytics'},
      {'icon': Icons.web_outlined, 'filledIcon': Icons.web, 'label': 'Web'},
      {'icon': Icons.settings_outlined, 'filledIcon': Icons.settings, 'label': 'Settings'},
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    // --- Simplified Glassmorphism Container ---
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // Reduced blur
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).canvasColor.withOpacity(0.8), // Simpler background
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white10 : Colors.black12, // Thin, subtle border
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Container(
              height: 60, // Slightly reduced height
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(tabs.length, (index) {
                  final isActive = currentIndex == index;
                  final tab = tabs[index];

                  // Use a simpler flex ratio. The active tab needs more room for text.
                  // This removes the need for complex, error-prone measurement in the LayoutBuilder.
                  return Flexible(
                    flex: isActive ? 2 : 1, // Active tab gets 2x the base space
                    child: GestureDetector(
                      onTap: () => onTap(index),
                      behavior: HitTestBehavior.opaque,
                      child: _BottomNavItem(
                        isActive: isActive,
                        primaryColor: primaryColor,
                        iconColor: iconColor,
                        icon: tab['icon'] as IconData,
                        filledIcon: tab['filledIcon'] as IconData,
                        label: tab['label'] as String,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final bool isActive;
  final Color primaryColor;
  final Color iconColor;
  final IconData icon;
  final IconData filledIcon;
  final String label;

  const _BottomNavItem({
    required this.isActive,
    required this.primaryColor,
    required this.iconColor,
    required this.icon,
    required this.filledIcon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    const double iconSize = 24.0;
    const Duration duration = Duration(milliseconds: 300);
    const double textSpacing = 8.0;

    // --- Core Fix: Remove complex calculation and rely on AnimatedContainer + AnimatedSize ---
    // The previous implementation used LayoutBuilder + TextPainter to calculate width, 
    // and then used AnimatedSize. This combination caused conflicts and complexity.
    // By using Flexible(flex: 2) in the parent and letting the content size the AnimatedContainer 
    // (using mainAxisSize: MainAxisSize.min and AnimatedSize), the layout becomes robust.

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.center,
      height: 48,
      // Removed explicit width: The internal Row/AnimatedSize will size the container when mainAxisSize.min is used.
      
      // Use minimal padding when inactive, larger when active for visual effect.
      padding: EdgeInsets.symmetric(
        horizontal: isActive ? 12 : 8,
      ),
      decoration: BoxDecoration(
        color: isActive
            ? primaryColor.withOpacity(0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
      ),
      
      // The Row must use MainAxisSize.min for the AnimatedSize to work properly 
      // when collapsing the text, allowing the container to shrink.
      child: Row(
        mainAxisSize: MainAxisSize.min, // *** CRITICAL FIX ***
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with simple AnimatedScale
          AnimatedScale(
            scale: isActive ? 1.08 : 1.0,
            duration: duration,
            curve: Curves.easeInOutCubic,
            child: Icon(
              isActive ? filledIcon : icon,
              size: iconSize,
              color: isActive ? primaryColor : iconColor,
            ),
          ),
          
          // Animated text label using AnimatedSize for smooth expansion
          // The container holding the text is what expands/collapses.
          AnimatedSize(
            duration: duration,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.centerLeft,
            child: isActive
                ? Padding(
                    padding: const EdgeInsets.only(left: textSpacing),
                    // Use a Container or SizedBox with a defined width if text is very long, 
                    // but for this design, letting the Text widget dictate the size is fine.
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                      maxLines: 1,
                      // The text is contained by the AnimatedSize's dynamic width, 
                      // so ellipsis is only needed if the text is longer than the
                      // available space given by the Flexible widget.
                      overflow: TextOverflow.ellipsis, 
                    ),
                  )
                : const SizedBox.shrink(), // Size is 0 when inactive
          ),
        ],
      ),
    );
  }
}