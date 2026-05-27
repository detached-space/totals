import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

class RedesignPlaceholderPage extends StatefulWidget {
  final String title;
  final bool showRedesignToggle;

  const RedesignPlaceholderPage({
    super.key,
    required this.title,
    this.showRedesignToggle = false,
  });

  @override
  State<RedesignPlaceholderPage> createState() =>
      _RedesignPlaceholderPageState();
}

class _RedesignPlaceholderPageState extends State<RedesignPlaceholderPage> {
  bool _useRedesign = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.showRedesignToggle) _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _useRedesign = prefs.getBool('use_redesign') ?? true;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleRedesign(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_redesign', value);
    setState(() => _useRedesign = value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10nTextRead('Restart the app to apply the new design.'),
        ),
      ),
    );
  }

  String _scaleLabel(double scale) {
    final formatted = scale
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '${formatted}x';
  }

  int _closestScaleIndex(double value, List<double> options) {
    int bestIndex = 0;
    double bestDelta = (value - options.first).abs();
    for (int i = 1; i < options.length; i++) {
      final delta = (value - options[i]).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<void> _showFontSizeSheet(ThemeProvider themeProvider) async {
    final initialScale = themeProvider.uiScale;
    final options = themeProvider.availableUiScales;
    int selectedIndex = _closestScaleIndex(initialScale, options);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final selectedScale = options[selectedIndex];
          Future<void> updateScale(int index) async {
            if (index == selectedIndex) return;
            setSheetState(() => selectedIndex = index);
            await themeProvider.setUiScale(options[index]);
          }

          return Container(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 +
                  MediaQuery.of(sheetContext).viewInsets.bottom +
                  MediaQuery.of(sheetContext).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: AppColors.cardColor(sheetContext),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 16),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.slate400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Display Size',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(sheetContext),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Preview and choose your preferred interface size.',
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(sheetContext),
                      ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor(sheetContext),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.borderColor(sheetContext)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preview',
                        style: TextStyle(
                          fontSize: 16 * selectedScale,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(sheetContext),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Transaction categorized successfully.',
                        style: TextStyle(
                          fontSize: 13 * selectedScale,
                          color: AppColors.textSecondary(sheetContext),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Current size: ${_scaleLabel(selectedScale)}',
                        style: TextStyle(
                          fontSize: 12 * selectedScale,
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Slider(
                  value: selectedIndex.toDouble(),
                  min: 0,
                  max: (options.length - 1).toDouble(),
                  divisions: options.length - 1,
                  label: _scaleLabel(selectedScale),
                  activeColor: AppColors.primaryLight,
                  inactiveColor: AppColors.borderColor(sheetContext),
                  onChanged: (value) {
                    updateScale(value.round());
                  },
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < options.length; i++)
                      ChoiceChip(
                        label: Text(_scaleLabel(options[i])),
                        selected: i == selectedIndex,
                        selectedColor:
                            AppColors.primaryLight.withValues(alpha: 0.2),
                        side: BorderSide(
                          color: i == selectedIndex
                              ? AppColors.primaryLight
                              : AppColors.borderColor(sheetContext),
                        ),
                        labelStyle: TextStyle(
                          color: i == selectedIndex
                              ? AppColors.primaryLight
                              : AppColors.textPrimary(sheetContext),
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) => updateScale(i),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: AppColors.borderColor(sheetContext)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                              color: AppColors.textSecondary(sheetContext)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: AppColors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          context.l10nText('Apply'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed != true && mounted) {
      await themeProvider.setUiScale(initialScale);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10nText('You'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10nText('Preferences & settings.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 20),

              // Dark Mode toggle
              _SettingTile(
                icon: AppIcons.dark_mode_outlined,
                iconColor: AppColors.primaryLight,
                title: context.l10nText('Dark Mode'),
                subtitle:
                    context.l10nText('Switch between light and dark theme'),
                trailing: Switch(
                  value: isDark,
                  onChanged: (_) => themeProvider.toggleTheme(),
                  activeColor: AppColors.primaryLight,
                ),
              ),

              _SettingTile(
                icon: AppIcons.zoom_out_map_rounded,
                iconColor: AppColors.incomeSuccess,
                title: context.l10nText('Display Size'),
                subtitle:
                    context.l10nText('Preview and adjust interface scale'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      themeProvider.uiScaleLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      AppIcons.chevron_right,
                      color: AppColors.textTertiary(context),
                      size: 20,
                    ),
                  ],
                ),
                onTap: () => _showFontSizeSheet(themeProvider),
              ),

              // Redesign toggle
              if (widget.showRedesignToggle && !_isLoading)
                _SettingTile(
                  icon: AppIcons.palette_rounded,
                  iconColor: AppColors.amber,
                  title: 'Use Redesign',
                  subtitle: 'Switch to the new design system',
                  trailing: Switch(
                    value: _useRedesign,
                    onChanged: _toggleRedesign,
                    activeColor: AppColors.primaryLight,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
