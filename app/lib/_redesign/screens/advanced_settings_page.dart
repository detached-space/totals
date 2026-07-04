import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_home_page.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
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
  Set<ToolsFabItem> _visibleTools =
      AdvancedSettingsService.defaultToolsFabItems;
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
      _visibleTools = AdvancedSettingsService.instance.toolsFabItems.value;
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

  Future<void> _openToolsFabPicker() async {
    final picked = await showModalBottomSheet<Set<ToolsFabItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var draft = Set<ToolsFabItem>.of(_visibleTools);
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void toggle(ToolsFabItem item) {
              final isSelected = draft.contains(item);
              if (isSelected && draft.length == 1) return;
              setSheetState(() {
                draft = Set<ToolsFabItem>.of(draft);
                isSelected ? draft.remove(item) : draft.add(item);
              });
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.82,
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                20 + MediaQuery.of(ctx).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: AppColors.cardColor(ctx),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.slate400,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ctx.l10nText('Tools button'),
                          style: TextStyle(
                            color: AppColors.textPrimary(ctx),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${draft.length}/${ToolsFabItem.values.length}',
                        style: TextStyle(
                          color: AppColors.textSecondary(ctx),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final item in ToolsFabItem.values) ...[
                    _ToolsFabOptionTile(
                      icon: _toolsFabIcon(item),
                      color: AppColors.primaryLight,
                      title: _toolsFabLabel(ctx, item),
                      selected: draft.contains(item),
                      canToggle: draft.length > 1 || !draft.contains(item),
                      onTap: () => toggle(item),
                    ),
                    if (item != ToolsFabItem.values.last)
                      const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, draft),
                      child: Text(ctx.l10nText('Done')),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (picked == null || _sameToolsSelection(picked, _visibleTools)) return;
    await AdvancedSettingsService.instance.setToolsFabItems(picked);
    if (!mounted) return;
    setState(() {
      _visibleTools = AdvancedSettingsService.instance.toolsFabItems.value;
    });
  }

  bool _sameToolsSelection(Set<ToolsFabItem> left, Set<ToolsFabItem> right) {
    if (left.length != right.length) return false;
    return left.every(right.contains);
  }

  String _toolsFabSummary(BuildContext context) {
    if (_visibleTools.length == ToolsFabItem.values.length) {
      return context.l10nText('All tools');
    }
    return '${_visibleTools.length} ${context.l10nText('tools shown')}';
  }

  String _toolsFabLabel(BuildContext context, ToolsFabItem item) {
    switch (item) {
      case ToolsFabItem.quickAccounts:
        return context.l10nText('Quick Accounts');
      case ToolsFabItem.verifyPayments:
        return context.l10nText('Verify Payments');
      case ToolsFabItem.loans:
        return context.l10nText('Loans');
      case ToolsFabItem.failedParsings:
        return context.l10nText('Failed Parsings');
      case ToolsFabItem.dataSync:
        return context.l10nText('Data Sync');
      case ToolsFabItem.webDashboard:
        return context.l10nText('Web Dashboard');
    }
  }

  IconData _toolsFabIcon(ToolsFabItem item) {
    switch (item) {
      case ToolsFabItem.quickAccounts:
        return AppIcons.account_balance_outlined;
      case ToolsFabItem.verifyPayments:
        return AppIcons.qr_code_scanner_rounded;
      case ToolsFabItem.loans:
        return AppIcons.debts;
      case ToolsFabItem.failedParsings:
        return AppIcons.sms_outlined;
      case ToolsFabItem.dataSync:
        return AppIcons.cloud_download;
      case ToolsFabItem.webDashboard:
        return AppIcons.dashboard_outlined;
    }
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
                DataSyncTile(
                  icon: AppIcons.cloud_download,
                  title: context.l10nText('Data Sync'),
                  subtitle: context
                      .l10nText('Send your data to a backend you choose'),
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DataSyncHomePage(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
                          child: const Icon(
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
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.cardColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: InkWell(
                    onTap: _openToolsFabPicker,
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
                          child: const Icon(
                            AppIcons.grid_view_outlined,
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
                                context.l10nText('Tools button'),
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _toolsFabSummary(context),
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

class _ToolsFabOptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final bool selected;
  final bool canToggle;
  final VoidCallback onTap;

  const _ToolsFabOptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.selected,
    required this.canToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: canToggle ? 1 : 0.62,
      child: Material(
        color: selected
            ? color.withValues(alpha: AppColors.isDark(context) ? 0.18 : 0.1)
            : AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: canToggle ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: AppColors.isDark(context) ? 0.2 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Checkbox(
                  value: selected,
                  onChanged: canToggle ? (_) => onTap() : null,
                  checkColor: AppColors.white,
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return color;
                    return Colors.transparent;
                  }),
                  side: BorderSide(color: AppColors.borderColor(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
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
