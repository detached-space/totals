import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/services/advanced_settings_service.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

class RedesignAdvancedSettingsPage extends StatefulWidget {
  const RedesignAdvancedSettingsPage({super.key});

  @override
  State<RedesignAdvancedSettingsPage> createState() =>
      _RedesignAdvancedSettingsPageState();
}

class _RedesignAdvancedSettingsPageState
    extends State<RedesignAdvancedSettingsPage> {
  ProfileDoubleTapAction _selected = ProfileDoubleTapAction.lock;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AdvancedSettingsService.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _selected = AdvancedSettingsService.instance.profileDoubleTapAction.value;
      _loading = false;
    });
  }

  Future<void> _openActionPicker() async {
    final picked = await showModalBottomSheet<ProfileDoubleTapAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 20 + MediaQuery.of(ctx).padding.bottom),
          decoration: BoxDecoration(
            color: AppColors.cardColor(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.slate400,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              _OptionTile(
                title: ctx.l10nText('Lock app'),
                selected: _selected == ProfileDoubleTapAction.lock,
                onTap: () => Navigator.pop(ctx, ProfileDoubleTapAction.lock),
              ),
              const SizedBox(height: 8),
              _OptionTile(
                title: ctx.l10nText('Do nothing'),
                selected: _selected == ProfileDoubleTapAction.doNothing,
                onTap: () =>
                    Navigator.pop(ctx, ProfileDoubleTapAction.doNothing),
              ),
            ],
          ),
        );
      },
    );

    if (picked == null || picked == _selected) return;
    await AdvancedSettingsService.instance.setProfileDoubleTapAction(picked);
    if (!mounted) return;
    setState(() => _selected = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(context.l10nText('Advanced')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.cardColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: InkWell(
                    onTap: _openActionPicker,
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryLight.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            AppIcons.person_outline_rounded,
                            color: AppColors.primaryLight,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Profile double tap',
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _selected == ProfileDoubleTapAction.lock
                                    ? 'Lock app'
                                    : 'Do nothing',
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          AppIcons.chevron_right_rounded,
                          color: AppColors.textTertiary(context),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primaryLight.withValues(alpha: 0.12)
          : AppColors.surfaceColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  AppIcons.check_rounded,
                  color: AppColors.primaryLight,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
